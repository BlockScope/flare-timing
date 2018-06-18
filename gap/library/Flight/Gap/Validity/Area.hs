{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell #-}

module Flight.Gap.Validity.Area (NominalDistanceArea(..)) where

import "newtype" Control.Newtype (Newtype(..))
import Data.Aeson.Via.Scientific (deriveDefDec, deriveViaSci)

newtype NominalDistanceArea = NominalDistanceArea Rational
    deriving (Eq, Ord, Show)

instance Newtype NominalDistanceArea Rational where
    pack = NominalDistanceArea
    unpack (NominalDistanceArea a) = a

deriveDefDec 8 ''NominalDistanceArea
deriveViaSci ''NominalDistanceArea
