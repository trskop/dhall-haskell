{-# LANGUAGE RecordWildCards    #-}
{-# LANGUAGE OverloadedStrings  #-}

{-| This module contains logic for converting Dhall expressions to and from
    CBOR expressions which can in turn be converted to and from a binary
    representation
-}

module Dhall.Binary
    ( -- * Standard versions
      StandardVersion
    , Dhall.Binary.StandardVersion.defaultStandardVersion

    -- * Encoding and decoding
    , encode
    , decode

    -- * Exceptions
    , DecodingFailure(..)
    ) where

import Codec.CBOR.Term (Term(..))
import Control.Applicative (empty, (<|>))
import Control.Exception (Exception)
import Dhall.Binary.StandardVersion (StandardVersion)
import Dhall.Core
    ( Binding(..)
    , Chunks(..)
    , Const(..)
    , Directory(..)
    , Expr(..)
    , File(..)
    , FilePrefix(..)
    , Import(..)
    , ImportHashed(..)
    , ImportMode(..)
    , ImportType(..)
    , Scheme(..)
    , URL(..)
    , Var(..)
    )

import Data.ByteArray.Encoding (Base(..))
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty(..))
import Data.Monoid ((<>))
import Prelude hiding (exponent)
import GHC.Float (double2Float, float2Double)

import qualified Crypto.Hash
import qualified Data.ByteArray.Encoding
import qualified Data.ByteString
import qualified Data.Sequence
import qualified Data.Text
import qualified Data.Text.Encoding
import qualified Dhall.Binary.StandardVersion
import qualified Dhall.Map
import qualified Dhall.Set

{-| Convert a function applied to multiple arguments to the base function and
    the list of arguments
-}
unApply :: Expr s a -> (Expr s a, [Expr s a])
unApply e = (baseFunction₀, diffArguments₀ [])
  where
    ~(baseFunction₀, diffArguments₀) = go e

    go (App f a) = (baseFunction, diffArguments . (a :))
      where
        ~(baseFunction, diffArguments) = go f
    go baseFunction = (baseFunction, id)

-- | Encode a Dhall expression to a CBOR `Term`
encode :: Expr s Import -> Term
encode (Var (V "_" n)) =
    TInteger n
encode (Var (V x 0)) =
    TString x
encode (Var (V x n)) =
    TList [ TString x, TInteger n ]
encode NaturalBuild =
    TString "Natural/build"
encode NaturalFold =
    TString "Natural/fold"
encode NaturalIsZero =
    TString "Natural/isZero"
encode NaturalEven =
    TString "Natural/even"
encode NaturalOdd =
    TString "Natural/odd"
encode NaturalToInteger =
    TString "Natural/toInteger"
encode NaturalShow =
    TString "Natural/show"
encode IntegerToDouble =
    TString "Integer/toDouble"
encode IntegerShow =
    TString "Integer/show"
encode DoubleShow =
    TString "Double/show"
encode ListBuild =
    TString "List/build"
encode ListFold =
    TString "List/fold"
encode ListLength =
    TString "List/length"
encode ListHead =
    TString "List/head"
encode ListLast =
    TString "List/last"
encode ListIndexed =
    TString "List/indexed"
encode ListReverse =
    TString "List/reverse"
encode OptionalFold =
    TString "Optional/fold"
encode OptionalBuild =
    TString "Optional/build"
encode Bool =
    TString "Bool"
encode Optional =
    TString "Optional"
encode None =
    TString "None"
encode Natural =
    TString "Natural"
encode Integer =
    TString "Integer"
encode Double =
    TString "Double"
encode Text =
    TString "Text"
encode TextShow =
    TString "Text/show"
encode List =
    TString "List"
encode (Const Type) =
    TString "Type"
encode (Const Kind) =
    TString "Kind"
encode (Const Sort) =
    TString "Sort"
encode e@(App _ _) =
    TList ([ TInt 0, f₁ ] ++ map encode arguments)
  where
    (f₀, arguments) = unApply e

    f₁ = encode f₀
encode (Lam "_" _A₀ b₀) =
    TList [ TInt 1, _A₁, b₁ ]
  where
    _A₁ = encode _A₀
    b₁  = encode b₀
encode (Lam x _A₀ b₀) =
    TList [ TInt 1, TString x, _A₁, b₁ ]
  where
    _A₁ = encode _A₀
    b₁  = encode b₀
encode (Pi "_" _A₀ _B₀) =
    TList [ TInt 2, _A₁, _B₁ ]
  where
    _A₁ = encode _A₀
    _B₁ = encode _B₀
encode (Pi x _A₀ _B₀) =
    TList [ TInt 2, TString x, _A₁, _B₁ ]
  where
    _A₁ = encode _A₀
    _B₁ = encode _B₀
encode (BoolOr l₀ r₀) =
    TList [ TInt 3, TInt 0, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (BoolAnd l₀ r₀) =
    TList [ TInt 3, TInt 1, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (BoolEQ l₀ r₀) =
    TList [ TInt 3, TInt 2, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (BoolNE l₀ r₀) =
    TList [ TInt 3, TInt 3, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (NaturalPlus l₀ r₀) =
    TList [ TInt 3, TInt 4, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (NaturalTimes l₀ r₀) =
    TList [ TInt 3, TInt 5, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (TextAppend l₀ r₀) =
    TList [ TInt 3, TInt 6, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (ListAppend l₀ r₀) =
    TList [ TInt 3, TInt 7, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (Combine l₀ r₀) =
    TList [ TInt 3, TInt 8, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (Prefer l₀ r₀) =
    TList [ TInt 3, TInt 9, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (CombineTypes l₀ r₀) =
    TList [ TInt 3, TInt 10, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (ImportAlt l₀ r₀) =
    TList [ TInt 3, TInt 11, l₁, r₁ ]
  where
    l₁ = encode l₀
    r₁ = encode r₀
encode (ListLit _T₀ xs₀)
    | null xs₀  = TList [ TInt 4, _T₁ ]
    | otherwise = TList ([ TInt 4, TNull ] ++ xs₁)
  where
    _T₁ = case _T₀ of
        Nothing -> TNull
        Just t  -> encode t

    xs₁ = map encode (Data.Foldable.toList xs₀)
encode (OptionalLit _T₀ Nothing) =
    TList [ TInt 5, _T₁ ]
  where
    _T₁ = encode _T₀
encode (OptionalLit _T₀ (Just t₀)) =
    TList [ TInt 5, _T₁, t₁ ]
  where
    _T₁ = encode _T₀
    t₁  = encode t₀
encode (Some t₀) =
    TList [ TInt 5, TNull, t₁ ]
  where
    t₁ = encode t₀
encode (Merge t₀ u₀ Nothing) =
    TList [ TInt 6, t₁, u₁ ]
  where
    t₁ = encode t₀
    u₁ = encode u₀
encode (Merge t₀ u₀ (Just _T₀)) =
    TList [ TInt 6, t₁, u₁, _T₁ ]
  where
    t₁  = encode t₀
    u₁  = encode u₀
    _T₁ = encode _T₀
encode (Record xTs₀) =
    TList [ TInt 7, TMap xTs₁ ]
  where
    xTs₁ = do
        (x₀, _T₀) <- Dhall.Map.toList (Dhall.Map.sort xTs₀)
        let x₁  = TString x₀
        let _T₁ = encode _T₀
        return (x₁, _T₁)
encode (RecordLit xts₀) =
    TList [ TInt 8, TMap xts₁ ]
  where
    xts₁ = do
        (x₀, t₀) <- Dhall.Map.toList (Dhall.Map.sort xts₀)
        let x₁ = TString x₀
        let t₁ = encode t₀
        return (x₁, t₁)
encode (Field t₀ x) =
    TList [ TInt 9, t₁, TString x ]
  where
    t₁ = encode t₀
encode (Project t₀ xs₀) =
    TList ([ TInt 10, t₁ ] ++ xs₁)
  where
    t₁  = encode t₀
    xs₁ = map TString (Dhall.Set.toList xs₀)
encode (Union xTs₀) =
    TList [ TInt 11, TMap xTs₁ ]
  where
    xTs₁ = do
        (x₀, _T₀) <- Dhall.Map.toList (Dhall.Map.sort xTs₀)
        let x₁  = TString x₀
        let _T₁ = encode _T₀
        return (x₁, _T₁)
encode (UnionLit x t₀ yTs₀) =
    TList [ TInt 12, TString x, t₁, TMap yTs₁ ]
  where
    t₁ = encode t₀

    yTs₁ = do
        (y₀, _T₀) <- Dhall.Map.toList (Dhall.Map.sort yTs₀)
        let y₁  = TString y₀
        let _T₁ = encode _T₀
        return (y₁, _T₁)
encode (BoolLit b) =
    TBool b
encode (BoolIf t₀ l₀ r₀) =
    TList [ TInt 14, t₁, l₁, r₁ ]
  where
    t₁ = encode t₀
    l₁ = encode l₀
    r₁ = encode r₀
encode (NaturalLit n) =
    TList [ TInt 15, TInteger (fromIntegral n) ]
encode (IntegerLit n) =
    TList [ TInt 16, TInteger n ]
encode (DoubleLit n64)
    -- cborg always encodes NaN as "7e00"
    | isNaN n64 = THalf n32
    | useHalf   = THalf n32
    | useFloat  = TFloat n32
    | otherwise = TDouble n64
  where
    n32      = double2Float n64
    useFloat = n64 == float2Double n32
    -- the other three cases for Half-floats are 0.0 and the infinities
    useHalf  = or $ fmap (n64 ==) [0.0, infinity, -infinity]
    infinity = 1/0 :: Double
encode (TextLit (Chunks xys₀ z₀)) =
    TList ([ TInt 18 ] ++ xys₁ ++ [ z₁ ])
  where
    xys₁ = do
        (x₀, y₀) <- xys₀
        let x₁ = TString x₀
        let y₁ = encode y₀
        [ x₁, y₁ ]

    z₁ = TString z₀
encode (Embed x) =
    importToTerm x
encode (Let as₀ b₀) =
    TList ([ TInt 25 ] ++ as₁ ++ [ b₁ ])
  where
    as₁ = do
        Binding x mA₀ a₀ <- toList as₀

        let mA₁ = case mA₀ of
                Nothing  -> TNull
                Just _A₀ -> encode _A₀

        let a₁ = encode a₀

        [ TString x, mA₁, a₁ ]

    b₁ = encode b₀
encode (Annot t₀ _T₀) =
    TList [ TInt 26, t₁, _T₁ ]
  where
    t₁  = encode t₀
    _T₁ = encode _T₀
encode (Note _ e) =
    encode e

importToTerm :: Import -> Term
importToTerm import_ =
    case importType of
        Remote (URL { scheme = scheme₀, ..}) ->
            TList
                (   prefix
                ++  [ TInt scheme₁, using, TString authority ]
                ++  map TString (reverse components)
                ++  [ TString file ]
                ++  (case query    of Nothing -> [ TNull ]; Just q -> [ TString q ])
                ++  (case fragment of Nothing -> [ TNull ]; Just f -> [ TString f ])
                )
          where
            using = case headers of
                Nothing ->
                    TNull
                Just h ->
                    importToTerm
                        (Import { importHashed = h, importMode = Code })

            scheme₁ = case scheme₀ of
                HTTP  -> 0
                HTTPS -> 1
            File {..} = path

            Directory {..} = directory

        Local prefix₀ path ->
                TList
                    (   prefix
                    ++  [ TInt prefix₁ ]
                    ++  map TString components₁
                    ++  [ TString file ]
                    )
          where
            File {..} = path

            Directory {..} = directory

            prefix₁ = case prefix₀ of
              Absolute -> 2
              Here     -> 3
              Parent   -> 4
              Home     -> 5

            components₁ = reverse components

        Env x ->
            TList (prefix ++ [ TInt 6, TString x ])

        Missing ->
            TList (prefix ++ [ TInt 7 ])
  where
    prefix = [ TInt 24, h, m ]
      where
        h = case hash of
            Nothing ->
                TNull
            Just digest ->
                TList
                    [ TString "sha256", TString (Data.Text.pack (show digest)) ]

        m = TInt (case importMode of Code -> 0; RawText -> 1)

    Import {..} = import_

    ImportHashed {..} = importHashed

decodeMaybe :: Term -> Maybe (Expr s Import)
decodeMaybe (TInt n) =
    return (Var (V "_" (fromIntegral n)))
decodeMaybe (TInteger n) =
    return (Var (V "_" n))
decodeMaybe (TString "Natural/build") =
    return NaturalBuild
decodeMaybe (TString "Natural/fold") =
    return NaturalFold
decodeMaybe (TString "Natural/isZero") =
    return NaturalIsZero
decodeMaybe (TString "Natural/even") =
    return NaturalEven
decodeMaybe (TString "Natural/odd") =
    return NaturalOdd
decodeMaybe (TString "Natural/toInteger") =
    return NaturalToInteger
decodeMaybe (TString "Natural/show") =
    return NaturalShow
decodeMaybe (TString "Integer/toDouble") =
    return IntegerToDouble
decodeMaybe (TString "Integer/show") =
    return IntegerShow
decodeMaybe (TString "Double/show") =
    return DoubleShow
decodeMaybe (TString "List/build") =
    return ListBuild
decodeMaybe (TString "List/fold") =
    return ListFold
decodeMaybe (TString "List/length") =
    return ListLength
decodeMaybe (TString "List/head") =
    return ListHead
decodeMaybe (TString "List/last") =
    return ListLast
decodeMaybe (TString "List/indexed") =
    return ListIndexed
decodeMaybe (TString "List/reverse") =
    return ListReverse
decodeMaybe (TString "Optional/fold") =
    return OptionalFold
decodeMaybe (TString "Optional/build") =
    return OptionalBuild
decodeMaybe (TString "Bool") =
    return Bool
decodeMaybe (TString "Optional") =
    return Optional
decodeMaybe (TString "None") =
    return None
decodeMaybe (TString "Natural") =
    return Natural
decodeMaybe (TString "Integer") =
    return Integer
decodeMaybe (TString "Double") =
    return Double
decodeMaybe (TString "Text") =
    return Text
decodeMaybe (TString "Text/show") =
    return TextShow
decodeMaybe (TString "List") =
    return List
decodeMaybe (TString "Type") =
    return (Const Type)
decodeMaybe (TString "Kind") =
    return (Const Kind)
decodeMaybe (TString "Sort") =
    return (Const Sort)
decodeMaybe (TString "_") =
    empty
decodeMaybe (TString x) =
    return (Var (V x 0))
decodeMaybe (TList [ TString x, TInt n ]) =
    return (Var (V x (fromIntegral n)))
decodeMaybe (TList [ TString x, TInteger n ]) =
    return (Var (V x n))
decodeMaybe (TList (TInt 0 : f₁ : xs₁)) = do
    f₀  <- decodeMaybe f₁
    xs₀ <- traverse decodeMaybe xs₁
    return (foldl App f₀ xs₀)
decodeMaybe (TList [ TInt 1, _A₁, b₁ ]) = do
    _A₀ <- decodeMaybe _A₁
    b₀  <- decodeMaybe b₁
    return (Lam "_" _A₀ b₀)
decodeMaybe (TList [ TInt 1, TString x, _A₁, b₁ ]) = do
    _A₀ <- decodeMaybe _A₁
    b₀  <- decodeMaybe b₁
    return (Lam x _A₀ b₀)
decodeMaybe (TList [ TInt 2, _A₁, _B₁ ]) = do
    _A₀ <- decodeMaybe _A₁
    _B₀ <- decodeMaybe _B₁
    return (Pi "_" _A₀ _B₀)
decodeMaybe (TList [ TInt 2, TString x, _A₁, _B₁ ]) = do
    _A₀ <- decodeMaybe _A₁
    _B₀ <- decodeMaybe _B₁
    return (Pi x _A₀ _B₀)
decodeMaybe (TList [ TInt 3, TInt n, l₁, r₁ ]) = do
    l₀ <- decodeMaybe l₁
    r₀ <- decodeMaybe r₁
    op <- case n of
            0  -> return BoolOr
            1  -> return BoolAnd
            2  -> return BoolEQ
            3  -> return BoolNE
            4  -> return NaturalPlus
            5  -> return NaturalTimes
            6  -> return TextAppend
            7  -> return ListAppend
            8  -> return Combine
            9  -> return Prefer
            10 -> return CombineTypes
            11 -> return ImportAlt
            _  -> empty
    return (op l₀ r₀)
decodeMaybe (TList [ TInt 4, _T₁ ]) = do
    _T₀ <- decodeMaybe _T₁
    return (ListLit (Just _T₀) empty)
decodeMaybe (TList (TInt 4 : TNull : xs₁ )) = do
    xs₀ <- traverse decodeMaybe xs₁
    return (ListLit Nothing (Data.Sequence.fromList xs₀))
decodeMaybe (TList [ TInt 5, _T₁ ]) = do
    _T₀ <- decodeMaybe _T₁
    return (OptionalLit _T₀ Nothing)
decodeMaybe (TList [ TInt 5, TNull, t₁ ]) = do
    t₀ <- decodeMaybe t₁
    return (Some t₀)
decodeMaybe (TList [ TInt 5, _T₁, t₁ ]) = do
    _T₀ <- decodeMaybe _T₁
    t₀  <- decodeMaybe t₁
    return (OptionalLit _T₀ (Just t₀))
decodeMaybe (TList [ TInt 6, t₁, u₁ ]) = do
    t₀ <- decodeMaybe t₁
    u₀ <- decodeMaybe u₁
    return (Merge t₀ u₀ Nothing)
decodeMaybe (TList [ TInt 6, t₁, u₁, _T₁ ]) = do
    t₀  <- decodeMaybe t₁
    u₀  <- decodeMaybe u₁
    _T₀ <- decodeMaybe _T₁
    return (Merge t₀ u₀ (Just _T₀))
decodeMaybe (TList [ TInt 7, TMap xTs₁ ]) = do
    let process (TString x, _T₁) = do
            _T₀ <- decodeMaybe _T₁

            return (x, _T₀)
        process _ =
            empty

    xTs₀ <- traverse process xTs₁

    return (Record (Dhall.Map.fromList xTs₀))
decodeMaybe (TList [ TInt 8, TMap xts₁ ]) = do
    let process (TString x, t₁) = do
           t₀ <- decodeMaybe t₁

           return (x, t₀)
        process _ =
            empty

    xts₀ <- traverse process xts₁

    return (RecordLit (Dhall.Map.fromList xts₀))
decodeMaybe (TList [ TInt 9, t₁, TString x ]) = do
    t₀ <- decodeMaybe t₁

    return (Field t₀ x)
decodeMaybe (TList (TInt 10 : t₁ : xs₁)) = do
    t₀ <- decodeMaybe t₁

    let process (TString x) = return x
        process  _          = empty

    xs₀ <- traverse process xs₁

    return (Project t₀ (Dhall.Set.fromList xs₀))
decodeMaybe (TList [ TInt 11, TMap xTs₁ ]) = do
    let process (TString x, _T₁) = do
            _T₀ <- decodeMaybe _T₁

            return (x, _T₀)
        process _ =
            empty

    xTs₀ <- traverse process xTs₁

    return (Union (Dhall.Map.fromList xTs₀))
decodeMaybe (TList [ TInt 12, TString x, t₁, TMap yTs₁ ]) = do
    t₀ <- decodeMaybe t₁

    let process (TString y, _T₁) = do
            _T₀ <- decodeMaybe _T₁

            return (y, _T₀)
        process _ =
            empty

    yTs₀ <- traverse process yTs₁

    return (UnionLit x t₀ (Dhall.Map.fromList yTs₀))
decodeMaybe (TBool b) = do
    return (BoolLit b)
decodeMaybe (TList [ TInt 14, t₁, l₁, r₁ ]) = do
    t₀ <- decodeMaybe t₁
    l₀ <- decodeMaybe l₁
    r₀ <- decodeMaybe r₁

    return (BoolIf t₀ l₀ r₀)
decodeMaybe (TList [ TInt 15, TInt n ]) = do
    return (NaturalLit (fromIntegral n))
decodeMaybe (TList [ TInt 15, TInteger n ]) = do
    return (NaturalLit (fromInteger n))
decodeMaybe (TList [ TInt 16, TInt n ]) = do
    return (IntegerLit (fromIntegral n))
decodeMaybe (TList [ TInt 16, TInteger n ]) = do
    return (IntegerLit n)
decodeMaybe (THalf n) = do
    return (DoubleLit (float2Double n))
decodeMaybe (TFloat n) = do
    return (DoubleLit (float2Double n))
decodeMaybe (TDouble n) = do
    return (DoubleLit n)
decodeMaybe (TList (TInt 18 : xs)) = do
    let process (TString x : y₁ : zs) = do
            y₀ <- decodeMaybe y₁

            ~(xys, z) <- process zs

            return ((x, y₀) : xys, z)
        process [ TString z ] = do
            return ([], z)
        process _ = do
            empty

    (xys, z) <- process xs

    return (TextLit (Chunks xys z))
decodeMaybe (TList (TInt 24 : h : TInt mode : TInt n : xs)) = do
    hash <- case h of
        TNull -> do
            return Nothing

        TList [ TString "sha256", TString base16Text ] -> do
            let base16Bytes = Data.Text.Encoding.encodeUtf8 base16Text
            digestBytes <- case Data.ByteArray.Encoding.convertFromBase Base16 base16Bytes of
                Left  _           -> empty
                Right digestBytes -> return (digestBytes :: Data.ByteString.ByteString)

            digest <- Crypto.Hash.digestFromByteString digestBytes
            return (Just digest)

        _ -> do
            empty

    importMode <- case mode of
        0 -> return Code
        1 -> return RawText
        _ -> empty

    let remote scheme = do
            let process [ TString file, q, f ] = do
                    query <- case q of
                        TNull     -> return Nothing
                        TString x -> return (Just x)
                        _         -> empty
                    fragment <- case f of
                        TNull     -> return Nothing
                        TString x -> return (Just x)
                        _         -> empty
                    return ([], file, query, fragment)
                process (TString path : ys) = do
                    (paths, file, query, fragment) <- process ys
                    return (path : paths, file, query, fragment)
                process _ = do
                    empty

            (headers, authority, paths, file, query, fragment) <- case xs of
                headers₀ : TString authority : ys -> do
                    headers₁ <- case headers₀ of
                        TNull -> return Nothing
                        _     -> do
                            Embed (Import { importHashed = headers }) <- decodeMaybe headers₀
                            return (Just headers)
                    (paths, file, query, fragment) <- process ys
                    return (headers₁, authority, paths, file, query, fragment)
                _ -> do
                    empty

            let components = reverse paths
            let directory  = Directory {..}
            let path       = File {..}

            return (Remote (URL {..}))

    let local prefix = do
            let process [ TString file ] = do
                    return ([], file)
                process (TString path : ys) = do
                    (paths, file) <- process ys
                    return (path : paths, file)
                process _ =
                    empty

            (paths, file) <- process xs

            let components = reverse paths
            let directory  = Directory {..}

            return (Local prefix (File {..}))

    let env = do
            case xs of
                [ TString x ] -> return (Env x)
                _             -> empty

    let missing = return Missing

    importType <- case n of
        0 -> remote HTTP
        1 -> remote HTTPS
        2 -> local Absolute
        3 -> local Here
        4 -> local Parent
        5 -> local Home
        6 -> env
        7 -> missing
        _ -> empty

    let importHashed = ImportHashed {..}

    return (Embed (Import {..}))
decodeMaybe (TList (TInt 25 : xs)) = do
    let process (TString x : _A₁ : a₁ : ls₁) = do
            mA₀ <- case _A₁ of
                TNull -> return Nothing
                _     -> fmap Just (decodeMaybe _A₁)

            a₀  <- decodeMaybe a₁

            let binding = Binding x mA₀ a₀

            case ls₁ of
                [ b₁ ] -> do
                    b₀ <- decodeMaybe b₁

                    return (Let (binding :| []) b₀)
                _ -> do
                    Let (l₀ :| ls₀) b₀ <- process ls₁

                    return (Let (binding :| (l₀ : ls₀)) b₀)
        process _ = do
            empty

    process xs
decodeMaybe (TList [ TInt 26, t₁, _T₁ ]) = do
    t₀  <- decodeMaybe t₁
    _T₀ <- decodeMaybe _T₁
    return (Annot t₀ _T₀)
decodeMaybe _ =
    empty

-- | Decode a Dhall expression from a CBOR `Term`
decode :: Term -> Either DecodingFailure (Expr s Import)
decode term =
    case decodeWithoutVersion <|> decodeWithVersion of
        Just expression -> Right expression
        Nothing         -> Left (CBORIsNotDhall term)
  where
    -- This is the behavior specified by the standard
    decodeWithoutVersion = decodeMaybe term

    -- For backwards compatibility with older expressions that have a version
    -- tag to ease the migration
    decodeWithVersion = do
        TList [ TString _, taggedTerm ] <- return term
        decodeMaybe taggedTerm

data DecodingFailure = CBORIsNotDhall Term
    deriving (Eq)

instance Exception DecodingFailure

_ERROR :: String
_ERROR = "\ESC[1;31mError\ESC[0m"

instance Show DecodingFailure where
    show (CBORIsNotDhall term) =
            _ERROR <> ": Cannot decode CBOR to Dhall\n"
        <>  "\n"
        <>  "The following CBOR expression does not encode a valid Dhall expression\n"
        <>  "\n"
        <>  "↳ " <> show term <> "\n"
