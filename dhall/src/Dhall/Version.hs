-- | Dhall Standard version information.
module Dhall.Version
    ( latestSupportedStandardVersion
    ) where

import Data.Version (Version, makeVersion)

-- | Latest version of Dhall Standard supported by this library.
--
-- To convert the 'Version' into 'String', please, use
-- 'Data.Version.showVersion':
--
-- >>> showVersion latestSupportedStandardVersion
-- "6.0.0"
latestSupportedStandardVersion :: Version
latestSupportedStandardVersion = makeVersion [6, 0, 0]
