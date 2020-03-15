module Flight.Gap.Leading.Area
    ( LeadingAreas(..)
    , LeadingArea(..)
    , LeadingArea1Units, zeroLeadingArea1Units
    , LeadingArea2Units, zeroLeadingArea2Units
    ) where

import GHC.Generics (Generic)
import "newtype" Control.Newtype (Newtype(..))
import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.Csv (ToField(..), FromField(..))
import Data.UnitsOfMeasure (KnownUnit, Unpack, (*:), u, zero)
import Data.UnitsOfMeasure.Internal (Quantity(..))

import Flight.Units ()
import Data.Via.Scientific (DefaultDecimalPlaces(..), DecimalPlaces(..))
import Data.Via.UnitsOfMeasure (ViaQ(..))

type LeadingAreaUnits u = Quantity Double u
type LeadingArea1Units = Quantity Double [u| km*s |]
type LeadingArea2Units = Quantity Double [u| (km^2)*s |]

zeroLeadingArea1Units :: LeadingArea1Units
zeroLeadingArea1Units =
    (zero :: Quantity _ [u| km |])
    *:
    (zero :: Quantity _ [u| s |])

zeroLeadingArea2Units :: LeadingArea2Units
zeroLeadingArea2Units =
    (zero :: Quantity _ [u| km |])
    *:
    (zero :: Quantity _ [u| km |])
    *:
    (zero :: Quantity _ [u| s |])

data LeadingAreas a b =
    LeadingAreas
        { areaFlown :: a
        , areaAfterLanding :: b
        , areaBeforeStart :: b
        }
    deriving (Eq, Ord, Generic)
    deriving anyclass (ToJSON, FromJSON)

deriving instance (Show a, Show b) => Show (LeadingAreas a b)

newtype LeadingArea a = LeadingArea a
    deriving (Eq, Ord, Show, Generic)

instance (q ~ LeadingAreaUnits u) => DefaultDecimalPlaces (LeadingArea q) where
    defdp _ = DecimalPlaces 4

instance (q ~ LeadingAreaUnits u) => Newtype (LeadingArea q) q where
    pack = LeadingArea
    unpack (LeadingArea a) = a

instance (KnownUnit (Unpack u), q ~ LeadingAreaUnits u) => ToJSON (LeadingArea q) where
    toJSON x = toJSON $ ViaQ x

instance (KnownUnit (Unpack u), q ~ LeadingAreaUnits u) => FromJSON (LeadingArea q) where
    parseJSON o = do
        ViaQ x <- parseJSON o
        return x

instance (q ~ LeadingAreaUnits u) => ToField (LeadingArea q) where
    toField (LeadingArea (MkQuantity x)) = toField x

instance (q ~ LeadingAreaUnits u) => FromField (LeadingArea q) where
    parseField x = LeadingArea . MkQuantity <$> parseField x
