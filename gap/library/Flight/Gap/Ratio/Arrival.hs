{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell #-}

module Flight.Gap.Ratio.Arrival (ArrivalFraction(..)) where

import Control.Newtype (Newtype(..))
import Data.Aeson.Via.Scientific (deriveDefaultDecimalPlaces, deriveViaSci)

newtype ArrivalFraction = ArrivalFraction Rational
    deriving (Eq, Ord, Show)

instance Newtype ArrivalFraction Rational where
    pack = ArrivalFraction
    unpack (ArrivalFraction a) = a

deriveDefaultDecimalPlaces 8 ''ArrivalFraction
deriveViaSci ''ArrivalFraction
