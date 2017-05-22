{-# OPTIONS_GHC -fno-warn-unused-binds #-}

{-|
Module      : Flight.Score
Copyright   : (c) Block Scope Limited 2017
License     : BSD3
Maintainer  : phil.dejoux@blockscope.com
Stability   : experimental

Provides GAP scoring for hang gliding and paragliding competitons.
-}
module Flight.Score
    ( -- * Nominals
      NominalLaunch(..)
    , NominalTime(..)
    , NominalDistance(..)
    , NominalGoal(..)
    -- * Units
    , Seconds
    , Metres
    -- * Ratio
    , isNormal
    , isFoldNormal
    -- * Validity
    , LaunchValidity(..)
    , TimeValidity(..)
    , DistanceValidity(..)
    , TaskValidity(..)
    , launchValidity
    , distanceValidity
    , timeValidity
    , taskValidity
    -- * Weighting
    , GoalRatio(..)
    , DistanceRatio(..)
    , DistanceWeight(..)
    , LeadingWeight(..)
    , ArrivalWeight(..)
    , TimeWeight(..)
    , Lw(..)
    , Aw(..)
    , distanceWeight
    , leadingWeight
    , arrivalWeight
    , timeWeight
    -- * Fractional allotment of arrival points
    , PilotsAtEss(..)
    , PositionAtEss(..)
    , ArrivalFraction(..)
    , arrivalFraction
    -- * Fractional allotment of time points
    , BestTime(..)
    , PilotTime(..)
    , SpeedFraction(..)
    , speedFraction
    ) where

import Flight.Ratio (isNormal, isFoldNormal)
import Flight.Allot
    ( PilotsAtEss(..)
    , PositionAtEss(..)
    , ArrivalFraction(..)
    , arrivalFraction
    , BestTime(..)
    , PilotTime(..)
    , SpeedFraction(..)
    , speedFraction
    )
import Flight.Validity
    ( NominalLaunch(..)
    , NominalTime(..)
    , NominalDistance(..)
    , NominalGoal(..)
    , LaunchValidity(..)
    , TimeValidity(..)
    , DistanceValidity(..)
    , TaskValidity(..)
    , Seconds
    , Metres
    , launchValidity
    , distanceValidity
    , timeValidity
    , taskValidity
    )
import Flight.Weighting
    ( GoalRatio(..)
    , DistanceRatio(..)
    , DistanceWeight(..)
    , LeadingWeight(..)
    , ArrivalWeight(..)
    , TimeWeight(..)
    , Lw(..)
    , Aw(..)
    , distanceWeight
    , leadingWeight
    , arrivalWeight
    , timeWeight
    )

type DistancePoint = Rational
type SpeedPoint = Rational
type DeparturePoint = Rational
type ArrivalPoint = Rational

data FixDistance = FixDistance Seconds Metres
data PointsAllocation =
    PointsAllocation { distance :: Rational
                     , speed :: Rational
                     , departure :: Rational
                     , arrival :: Rational
                     }

distancePoints :: [Metres] -> [DistancePoint]
distancePoints = undefined

speedPoints :: [Seconds] -> [SpeedPoint]
speedPoints = undefined

departurePoints :: [FixDistance] -> [DeparturePoint]
departurePoints = undefined

arrivalPoints :: Int -> [ArrivalPoint]
arrivalPoints = undefined

allocatePoints :: Rational -> PointsAllocation
allocatePoints = undefined
