module Flight.Earth.Flat.Cylinder.Rational (circumSample) where

import Data.Functor.Identity (runIdentity)
import Control.Monad.Except (runExceptT)
import qualified Data.Number.FixedFunctions as F
import Data.UnitsOfMeasure (u, convert)
import Data.UnitsOfMeasure.Internal (Quantity(..))
import qualified UTMRef as HCEN (UTMRef(..), toLatLng)
import qualified LatLng as HCLL (LatLng(..))

import Flight.LatLng (Lat(..), Lng(..), LatLng(..))
import Flight.LatLng.Rational (Epsilon(..), defEps)
import Flight.Zone
    ( Zone(..)
    , QRadius
    , Radius(..)
    , Bearing(..)
    , ArcSweep(..)
    , center
    , radius
    , toRationalZone
    )
import Flight.Zone.Path (distancePointToPoint)
import Flight.Earth.Flat.PointToPoint.Rational (distanceEuclidean)
import Flight.Distance (TaskDistance(..), PathDistance(..))
import Flight.Zone.Cylinder
    ( TrueCourse(..)
    , ZonePoint(..)
    , Tolerance(..)
    , Samples(..)
    , SampleParams(..)
    , CircumSample
    , orbit
    , radial
    , point
    , sourceZone
    , fromRationalZonePoint
    )
import Flight.Earth.Flat.Projected.Internal (zoneToProjectedEastNorth)

fromHcLatLng :: HCLL.LatLng -> LatLng Rational [u| rad |]
fromHcLatLng HCLL.LatLng{latitude, longitude} =
    LatLng (Lat . convert $ lat, Lng . convert $ lng)
    where
        lat :: Quantity Rational [u| deg |]
        lat = MkQuantity . toRational $ latitude

        lng :: Quantity Rational [u| deg |]
        lng = MkQuantity . toRational $ longitude

eastNorthToLatLng :: HCEN.UTMRef -> Either String HCLL.LatLng
eastNorthToLatLng = runIdentity . runExceptT . HCEN.toLatLng

circum
    :: Epsilon
    -> LatLng Rational [u| rad |]
    -> QRadius Rational [u| m |]
    -> TrueCourse Rational 
    -> LatLng Rational [u| rad |]
circum e xLL r tc =
    case circumEN e xLL r tc of
        Left _ -> xLL
        Right yEN ->
            case eastNorthToLatLng yEN of
                Left _ -> xLL
                Right yLL -> fromHcLatLng yLL

circumEN
    :: Epsilon
    -> LatLng Rational [u| rad |]
    -> QRadius Rational [u| m |]
    -> TrueCourse Rational 
    -> Either String HCEN.UTMRef
circumEN e xLL r tc =
    translate e r tc <$> zoneToProjectedEastNorth (Point xLL)

translate
    :: Epsilon
    -> QRadius Rational [u| m |]
    -> TrueCourse Rational
    -> HCEN.UTMRef
    -> HCEN.UTMRef
translate
    (Epsilon e) (Radius (MkQuantity rRadius)) (TrueCourse (MkQuantity rtc)) x =
    HCEN.UTMRef
        (fromRational (xE + dE))
        (fromRational (xN + dN))
        (HCEN.latZone x)
        (HCEN.lngZone x)
        (HCEN.datum x)
    where
        xE :: Rational
        xE = toRational $ HCEN.easting x

        xN :: Rational
        xN = toRational $ HCEN.northing x

        dE :: Rational
        dE = rRadius * F.cos e rtc

        dN :: Rational
        dN = rRadius * F.sin e rtc

-- | Generates a pair of lists, the lat/lng of each generated point
-- and its distance from the center. It will generate 'samples' number of such
-- points that should lie close to the circle. The difference between
-- the distance to the origin and the radius should be less han the 'tolerance'.
--
-- The points of the compass are divided by the number of samples requested.
circumSample :: CircumSample Rational
circumSample SampleParams{..} (ArcSweep (Bearing (MkQuantity bearing))) arc0 _zoneM zoneN =
    (fromRationalZonePoint <$> fst ys, snd ys)
    where
        nNum = unSamples spSamples
        half = nNum `div` 2
        step = bearing / (fromInteger nNum)
        mid = maybe 0 (\ZonePoint{radial = Bearing (MkQuantity b)} -> b) arc0

        zone' :: Zone Rational
        zone' =
            case arc0 of
              Nothing -> zoneN
              Just ZonePoint{..} -> sourceZone

        xs :: [TrueCourse Rational]
        xs =
            TrueCourse . MkQuantity <$>
                let lhs = [mid - (fromInteger n) * step | n <- [1 .. half]]
                    rhs = [mid + (fromInteger n) * step | n <- [1 .. half]]
                in lhs ++ (mid : rhs)

        (Radius (MkQuantity limitRadius)) = radius zone'
        limitRadius' = toRational limitRadius
        r = Radius (MkQuantity limitRadius')

        ptCenter = center zone'
        circumR = circum defEps ptCenter

        getClose' = getClose defEps zone' ptCenter limitRadius' spTolerance

        ys :: ([ZonePoint Rational], [TrueCourse Rational])
        ys = unzip $ getClose' 10 (Radius (MkQuantity 0)) (circumR r) <$> xs

getClose :: Epsilon
         -> Zone Rational
         -> LatLng Rational [u| rad |] -- ^ The center point.
         -> Rational -- ^ The limit radius.
         -> Tolerance Rational
         -> Int -- ^ How many tries.
         -> QRadius Rational [u| m |] -- ^ How far from the center.
         -> (TrueCourse Rational -> LatLng Rational [u| rad |]) -- ^ A point from the origin on this radial
         -> TrueCourse Rational -- ^ The true course for this radial.
         -> (ZonePoint Rational, TrueCourse Rational)
getClose epsilon zone' ptCenter limitRadius spTolerance trys yr@(Radius (MkQuantity offset)) f x@(TrueCourse tc)
    | trys <= 0 = (zp', x)
    | unTolerance spTolerance <= 0 = (zp', x)
    | limitRadius <= unTolerance spTolerance = (zp', x)
    | otherwise =
        case d `compare` limitRadius of
             EQ ->
                 (zp', x)

             GT ->
                 let offset' =
                         offset - (d - limitRadius) * 105 / 100

                     f' =
                         circumR (Radius (MkQuantity $ limitRadius + offset'))

                 in
                     getClose
                         epsilon
                         zone'
                         ptCenter
                         limitRadius
                         spTolerance
                         (trys - 1)
                         (Radius (MkQuantity offset'))
                         f'
                         x
                 
             LT ->
                 if d > toRational (limitRadius - unTolerance spTolerance)
                 then (zp', x)
                 else
                     let offset' =
                             offset + (limitRadius - d) * 94 / 100

                         f' =
                             circumR (Radius (MkQuantity $ limitRadius + offset'))
                     in
                         getClose
                             epsilon
                             zone'
                             ptCenter
                             limitRadius
                             spTolerance
                             (trys - 1)
                             (Radius (MkQuantity offset'))
                             f'
                             x
    where
        circumR = circum epsilon ptCenter

        y = f x
        zp' = ZonePoint { sourceZone = toRationalZone zone'
                        , point = y
                        , radial = Bearing tc
                        , orbit = yr
                        } :: ZonePoint Rational
                       
        (TaskDistance (MkQuantity d)) =
            edgesSum
            $ distancePointToPoint
                distanceEuclidean
                [Point ptCenter, Point y]
