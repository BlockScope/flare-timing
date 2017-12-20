module Flight.Mask.Distance
    ( dashDistancesToGoal
    , dashDistanceToGoal
    , dashDistanceFlown
    ) where

import Data.Time.Clock (UTCTime)
import Data.List (inits)
import Data.UnitsOfMeasure ((-:))
import Data.UnitsOfMeasure.Internal (Quantity(..))

import Flight.Kml (MarkedFixes(..))
import qualified Flight.Kml as Kml (Fix)
import Flight.Track.Cross (Fix(..))
import Flight.Comp (Task(..))
import Flight.Score (PilotDistance(..))
import Flight.Units ()
import Flight.Mask.Internal.Zone (ZoneIdx, TaskZone(..), fixFromFix, fixToPoint)
import Flight.Mask.Internal.Race (Sliver(..), Ticked)
import Flight.Mask.Internal.Dash (dashToGoalR)
import qualified Flight.Zone.Raw as Raw (RawZone(..))
import Flight.Distance (TaskDistance(..))

dashDistancesToGoal
    :: (Real a, Fractional a)
    => Ticked
    -> Sliver a
    -> (Raw.RawZone -> TaskZone a)
    -> Task
    -> MarkedFixes
    -> Maybe [(Maybe Fix, Maybe (TaskDistance a))]
    -- ^ Nothing indicates no such task or a task with no zones.
dashDistancesToGoal
    ticked sliver zoneToCyl task@Task{zones} MarkedFixes{mark0, fixes} =
    -- NOTE: A ghci session using inits & tails.
    -- inits [1 .. 4]
    -- [[],[1],[1,2],[1,2,3],[1,2,3,4]]
    --
    -- tails [1 .. 4]
    -- [[1,2,3,4],[2,3,4],[3,4],[4],[]]
    --
    -- tails $ reverse [1 .. 4]
    -- [[4,3,2,1],[3,2,1],[2,1],[1],[]]
    --
    -- drop 1 $ inits [1 .. 4]
    -- [[1],[1,2],[1,2,3],[1,2,3,4]]
    if null zones then Nothing else Just
    $ lfg zoneToCyl task mark0
    <$> drop 1 (inits ixs)
    where
        lfg = lastFixToGoal ticked sliver
        ixs = index fixes

dashDistanceToGoal
    :: (Real a, Fractional a)
    => Ticked
    -> Sliver a
    -> (Raw.RawZone -> TaskZone a)
    -> Task
    -> MarkedFixes
    -> Maybe (TaskDistance a)
    -- ^ Nothing indicates no such task or a task with no zones.
dashDistanceToGoal
    ticked
    sliver zoneToCyl
    Task{speedSection, zones}
    MarkedFixes{fixes} =
    if null zones then Nothing else
    dashToGoalR ticked sliver fixToPoint speedSection zs ixs
    where
        zs = zoneToCyl <$> zones
        ixs = reverse . index $ fixes

-- | The distance from the last fix to goal passing through the remaining
-- control zones.
lastFixToGoal :: (Real a, Fractional a)
              => Ticked
              -> Sliver a
              -> (Raw.RawZone -> TaskZone a)
              -> Task
              -> UTCTime
              -> [(ZoneIdx, Kml.Fix)]
              -> (Maybe Fix, Maybe (TaskDistance a))
lastFixToGoal
    ticked
    sliver
    zoneToCyl
    Task{speedSection, zones}
    mark0
    ixs =
    case iys of
        [] -> (Nothing, Nothing)
        ((i, y) : _) -> (Just $ fixFromFix mark0 i y, d)
    where
        d = dashToGoalR ticked sliver fixToPoint speedSection zs iys
        zs = zoneToCyl <$> zones
        iys = reverse ixs

dashDistanceFlown
    :: (Real a, Fractional a)
    => TaskDistance a
    -> Ticked
    -> Sliver a
    -> (Raw.RawZone -> TaskZone a)
    -> Task
    -> MarkedFixes
    -> Maybe (PilotDistance a)
dashDistanceFlown
    (TaskDistance dTask)
    ticked
    sliver
    zoneToCyl
    Task{speedSection, zones}
    MarkedFixes{fixes} =
    if null zones then Nothing else do
        TaskDistance dPilot
            <- dashToGoalR ticked sliver fixToPoint speedSection zs ixs

        let (MkQuantity diff) = dTask -: dPilot

        return $ PilotDistance diff
    where
        zs = zoneToCyl <$> zones
        ixs = reverse . index $ fixes

index :: [a] -> [(ZoneIdx, a)]
index = zip [1 .. ]
