{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE QuasiQuotes #-}

{-# LANGUAGE PartialTypeSignatures #-}
{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

module Flight.Distance
    ( TaskDistance(..)
    , PathDistance(..)
    , fromKms
    , toKm
    ) where

import Data.UnitsOfMeasure (u, convert, fromRational', toRational')
import Data.UnitsOfMeasure.Internal (Quantity(..))
import Data.Bifunctor.Flip (Flip(..))

import Flight.LatLng (LatLng(..))
import Data.Number.RoundingFunctions (dpRound)

fromKms :: Fractional a => Quantity a [u| km |] -> TaskDistance a
fromKms q = TaskDistance (convert q)

-- | Convert to kilometres with mm accuracy.
toKm :: (Real a, Fractional a) => TaskDistance a -> Double
toKm = toKm' (dpRound 6 . toRational)

toKm' :: Fractional a => (a -> Rational) -> TaskDistance a -> Double
toKm' f (TaskDistance d) =
    fromRational $ f dKm
    where 
        MkQuantity dKm = convert d :: Quantity _ [u| km |]

showDistance :: Quantity Rational [u| m |] -> String
showDistance d =
    "d = " ++ show dbl
    where
        km = convert d :: Quantity Rational [u| km |]
        Flip rounded = dpRound 3 <$> Flip km
        dbl = fromRational' rounded :: Quantity Double [u| km |]

newtype TaskDistance a =
    TaskDistance (Quantity a [u| m |])
    deriving (Eq, Ord)

instance (Real a, Fractional a) => Show (TaskDistance a) where
    show (TaskDistance d) = showDistance $ toRational' d

-- | The distance along a path of edges spanning vertices.
data PathDistance a =
    PathDistance
        { edgesSum :: TaskDistance a
        -- ^ The distance from the center of the first zone to the center of
        -- the last zone. An edge joins two vertices. These are summed to get
        -- the distance along the path that visits the vertices, each in turn.
        , vertices :: [ LatLng a [u| rad |] ]
        -- ^ The vertices that each edge spans.
        }

instance (Real a, Fractional a) => Show (PathDistance a) where
    show (PathDistance (TaskDistance d) _) = showDistance $ toRational' d
