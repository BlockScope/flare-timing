{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell #-}

module Flight.Gap.Ratio.Goal (NominalGoal(..)) where

import Control.Newtype (Newtype(..))
import Data.Aeson.Via.Scientific (deriveDefaultDecimalPlaces, deriveViaSci)

newtype NominalGoal = NominalGoal Rational
    deriving (Eq, Ord, Show)

instance Newtype NominalGoal Rational where
    pack = NominalGoal
    unpack (NominalGoal a) = a

deriveDefaultDecimalPlaces 8 ''NominalGoal
deriveViaSci ''NominalGoal
