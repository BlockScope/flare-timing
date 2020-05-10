{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

{-|
Module      : Flight.Track.Lead
Copyright   : (c) Block Scope Limited 2018
License     : MPL-2.0
Maintainer  : phil.dejoux@blockscope.com
Stability   : experimental

The lead standing of a pilot's track in comparison to other pilots.
-}
module Flight.Track.Lead
    ( TrackLead(..)
    , DiscardingLead(..)
    , LeadingAreaSum
    , MkLeadingCoef
    , MkAreaToCoef
    , sumAreas
    , compLeading
    , lwScalingDefault
    , cmpArea
    ) where

import "newtype" Control.Newtype (Newtype(..))
import Data.List (sortOn)
import Data.String (IsString())
import GHC.Generics (Generic)
import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.UnitsOfMeasure ((+:), KnownUnit, Unpack, u, toRational')
import Data.UnitsOfMeasure.Internal (Quantity(..))

import Flight.Field (FieldOrdering(..))
import Flight.Distance (QTaskDistance)
import Flight.Comp (Pilot)
import "flight-gap-lead" Flight.Score
    ( LeadingArea(..), LeadingCoef(..), LeadingFraction(..)
    , LeadingAreaUnits, LeadingAreaToCoefUnits, LengthOfSs, AreaToCoef
    , leadingFraction
    )
import "flight-gap-weight" Flight.Score (LwScaling(..))
import Flight.Track.Time (LeadingAreas(..), taskToLeading, minLeadingCoef)
import Flight.Zone.MkZones (Discipline(..))

-- | For each task, the discarding for leading for that task. Further fixes are
-- discarded and the leading areas collated.
newtype DiscardingLead u =
    DiscardingLead
        { areas :: [[(Pilot, LeadingAreas (LeadingArea u) (LeadingArea u))]]
        }
    deriving (Eq, Ord, Generic)

instance FieldOrdering (DiscardingLead u) where
    fieldOrder _ = cmpArea compare

cmpArea :: (Ord a, IsString a) => (a -> a -> Ordering) -> a -> a -> Ordering
cmpArea f a b =
    case (a, b) of
        ("areaFlown", _) -> LT

        ("areaAfterLanding", "areaFlown") -> GT
        ("areaAfterLanding", _) -> LT

        ("areaBeforeStart", _) -> GT

        _ -> f a b

data TrackLead u =
    TrackLead
        { area :: LeadingArea u
        , coef :: LeadingCoef (Quantity Double [u| 1 |])
        , frac :: LeadingFraction
        }
    deriving (Eq, Ord, Generic)

deriving anyclass instance (KnownUnit (Unpack u), q ~ Quantity Double u, FromJSON (LeadingArea q)) => FromJSON (TrackLead q)
deriving anyclass instance (KnownUnit (Unpack u), q ~ Quantity Double u, ToJSON (LeadingArea q)) => ToJSON (TrackLead q)
deriving anyclass instance (KnownUnit (Unpack u), q ~ Quantity Double u, FromJSON (LeadingArea q)) => FromJSON (DiscardingLead q)
deriving anyclass instance (KnownUnit (Unpack u), q ~ Quantity Double u, ToJSON (LeadingArea q)) => ToJSON (DiscardingLead q)

-- | The default explicit leading weight scaling for each discipline?
lwScalingDefault :: Discipline -> LwScaling
lwScalingDefault HangGliding = LwScaling 1
lwScalingDefault Paragliding = LwScaling 2

type LeadingAreaSum u =
    ( LeadingAreas (LeadingArea (LeadingAreaUnits u)) (LeadingArea (LeadingAreaUnits u))
    -> LeadingArea (LeadingAreaUnits u)
    )

sumAreas :: (KnownUnit (Unpack u)) => LeadingAreaSum u
sumAreas LeadingAreas{areaFlown = LeadingArea af, areaAfterLanding = LeadingArea al} =
    LeadingArea $ af +: al

type MkLeadingCoef u = LengthOfSs -> LeadingAreaToCoefUnits u -> Quantity Double [u| 1 |]
type MkAreaToCoef v = LengthOfSs -> AreaToCoef (LeadingAreaToCoefUnits v)

compLeading
    :: (KnownUnit (Unpack u))
    => LeadingAreaSum u
    -> MkLeadingCoef u
    -> DiscardingLead (LeadingAreaUnits u)
    -> [Maybe (QTaskDistance Double [u| m |])]
    ->
        ( [Maybe (LeadingCoef (Quantity Double [u| 1 |]))]
        , [[(Pilot, TrackLead (LeadingAreaUnits u))]]
        )
compLeading sumAreas' invert DiscardingLead{areas = ass} lsTask =
    (lcMins, lead)
    where
        ks :: [Quantity Rational _ -> Quantity Double [u| 1 |]]
        ks =
                [ maybe
                    (const [u| 1 |])
                    invert
                    l

                | l <- (fmap . fmap) taskToLeading lsTask
                ]

        css :: [[(Pilot, LeadingCoef (Quantity Double [u| 1 |]))]] =
                [ (fmap $ LeadingCoef . k . toRational' . unpack . sumAreas') <$> as
                | k <- ks
                | as <- ass
                ]

        lcMins :: [Maybe (LeadingCoef (Quantity Double [u| 1 |]))]
        lcMins = minLeadingCoef <$> (fmap . fmap) snd css

        lead :: [[(Pilot, TrackLead (LeadingAreaUnits _))]] =
                sortOn ((\TrackLead{coef = LeadingCoef c} -> c) . snd)
                <$>
                [
                    [
                        ( p
                        , TrackLead
                            { area = sumAreas' a
                            , coef = c
                            , frac =
                                maybe
                                    (LeadingFraction 0)
                                    (`leadingFraction` c)
                                    lcMin
                            }
                        )

                    | (_, a) <- as
                    | (p, c) <- cs
                    ]

                | lcMin <- lcMins
                | as <- ass
                | cs <- css
                ]
