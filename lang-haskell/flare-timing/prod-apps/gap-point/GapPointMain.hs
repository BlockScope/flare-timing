{-# LANGUAGE DuplicateRecordFields #-}
{-# OPTIONS_GHC -fplugin Data.UnitsOfMeasure.Plugin #-}
{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

import Prelude hiding (max)
import qualified Prelude as Stats (max)
import Data.Ratio ((%))
import Data.List.NonEmpty (nonEmpty)
import Data.Maybe (maybeToList, listToMaybe, fromMaybe, catMaybes)
import Data.Either (lefts, rights)
import Data.Function ((&))
import System.Environment (getProgName)
import System.Console.CmdArgs.Implicit (cmdArgs)
import qualified Formatting as Fmt ((%), fprint)
import Formatting.Clock (timeSpecs)
import Data.Time.Clock (UTCTime)
import System.Clock (getTime, Clock(Monotonic))
import Data.Map (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Map.Merge.Strict as Map
import Data.List (sortBy, partition)
import Control.Applicative (liftA2)
import qualified Control.Applicative as A ((<$>))
import Control.Monad (mapM_, join)
import Control.Exception.Safe (catchIO)
import System.FilePath (takeFileName)
import "newtype" Control.Newtype (Newtype(..))
import Data.UnitsOfMeasure ((/:), u, convert, unQuantity)
import Data.UnitsOfMeasure.Internal (Quantity(..))

import Flight.LatLng (QAlt)
import Flight.Cmd.Paths (LenientFile(..), checkPaths)
import Flight.Cmd.Options (ProgramName(..))
import Flight.Cmd.BatchOptions (CmdBatchOptions(..), mkOptions)
import Flight.Distance (QTaskDistance, TaskDistance(..), unTaskDistanceAsKm)
import Flight.Route (OptimalRoute(..))
import qualified Flight.Comp as Cmp (DfNoTrackPilot(..))
import Flight.Comp
    ( FileType(CompInput)
    , CompInputFile(..)
    , TaskLengthFile(..)
    , CompSettings(..)
    , Comp(..)
    , Nominal(..)
    , Tweak(..)
    , CrossZoneFile(..)
    , TagZoneFile(..)
    , MaskArrivalFile(..)
    , MaskEffortFile(..)
    , MaskLeadFile(..)
    , MaskReachFile(..)
    , MaskSpeedFile(..)
    , BonusReachFile(..)
    , LandOutFile(..)
    , Pilot
    , PilotGroup(dnf, didFlyNoTracklog)
    , StartGate(..)
    , StartEnd(..)
    , Task(..)
    , TaskStop(..)
    , DfNoTrack(..)
    , RoutesLookupTaskDistance(..)
    , TaskRouteDistance(..)
    , IxTask(..)
    , EarlyStart(..)
    , compToTaskLength
    , compToCross
    , crossToTag
    , compToMaskArrival
    , compToMaskEffort
    , compToMaskLead
    , compToMaskReach
    , compToMaskSpeed
    , compToBonusReach
    , compToLand
    , compToPoint
    , findCompInput
    , ensureExt
    )
import Flight.Track.Cross
    (InterpolatedFix(..), Crossing(..), ZoneTag(..), TrackFlyingSection(..))
import Flight.Track.Tag (Tagging(..), PilotTrackTag(..), TrackTag(..))
import Flight.Track.Distance
    ( TrackDistance(..), AwardedDistance(..), Clamp(..), Nigh, Land
    , awardByFrac
    )
import Flight.Track.Time (AwardedVelocity(..))
import Flight.Track.Lead (TrackLead(..))
import Flight.Track.Arrival (TrackArrival(..))
import Flight.Track.Speed (pilotTime, startGateTaken)
import qualified Flight.Track.Speed as Speed (TrackSpeed(..))
import Flight.Track.Mask
    ( MaskingArrival(..)
    , MaskingEffort(..)
    , MaskingLead(..)
    , MaskingReach(..)
    , MaskingSpeed(..)
    )
import Flight.Track.Land (Landing(..))
import Flight.Track.Place (rankByTotal)
import Flight.Track.Point
    (Velocity(..), Breakdown(..), Pointing(..), Allocation(..))
import qualified Flight.Track.Land as Cmp (Landing(..))
import Flight.Scribe
    ( readComp, readRoute
    , readCrossing, readTagging
    , readMaskingArrival
    , readMaskingEffort
    , readMaskingLead
    , readMaskingReach
    , readMaskingSpeed
    , readBonusReach
    , readLanding
    , writePointing
    )
import Flight.Mask (RaceSections(..), section)
import Flight.Zone.SpeedSection (SpeedSection)
import Flight.Zone.MkZones (Discipline(..))
import Flight.Lookup.Route (routeLength)
import qualified Flight.Lookup as Lookup (compRoutes)
import qualified Flight.Score as Gap (ReachToggle(..), taskPoints)
import Flight.Score
    ( MinimumDistance(..), LaunchToEss(..)
    , SumOfDistance(..), PilotDistance(..)
    , PilotsAtEss(..), PilotsPresent(..), PilotsFlying(..), PilotsLanded(..)
    , GoalRatio(..), Lw(..), Aw(..), Rw(..), Ew(..)
    , NominalTime(..), BestTime(..)
    , Validity(..), ValidityWorking(..)
    , StopValidity(..), StopValidityWorking
    , ReachToggle(..), ReachStats(..)
    , DifficultyFraction(..), LeadingFraction(..)
    , ArrivalFraction(..), SpeedFraction(..)
    , DistancePoints(..), LinearPoints(..), DifficultyPoints(..)
    , LeadingPoints(..), ArrivalPoints(..), TimePoints(..)
    , PointPenalty, PointsReduced(..)
    , TaskPlacing(..), PilotVelocity(..), PilotTime(..)
    , IxChunk(..), ChunkDifficulty(..)
    , FlownMax(..)
    , JumpedTheGun(..), TooEarlyPoints(..), LaunchToStartPoints(..)
    , Penalty(..), Hg, Pg
    , unFlownMaxAsKm
    , distanceRatio, distanceWeight, reachWeight, effortWeight
    , leadingWeight, arrivalWeight, timeWeight
    , taskValidity, launchValidity, distanceValidity, timeValidity, stopValidity
    , availablePoints
    , toIxChunk
    , jumpTheGunPenaltyHg, jumpTheGunPenaltyPg
    )
import qualified Flight.Score as Gap (Validity(..), Points(..), Weights(..))
import GapPointOptions (description)

type StartEndTags = StartEnd (Maybe ZoneTag) ZoneTag

main :: IO ()
main = do
    name <- getProgName
    options <- cmdArgs $ mkOptions (ProgramName name) description Nothing

    let lf = LenientFile {coerceFile = ensureExt CompInput}
    err <- checkPaths lf options

    maybe (drive options) putStrLn err

drive :: CmdBatchOptions -> IO ()
drive o = do
    -- SEE: http://chrisdone.com/posts/measuring-duration-in-haskell
    start <- getTime Monotonic
    files <- findCompInput o
    if null files then putStrLn "Couldn't find any input files."
                  else mapM_ (go o) files
    end <- getTime Monotonic
    Fmt.fprint ("Tallying points completed in " Fmt.% timeSpecs Fmt.% "\n") start end

go :: CmdBatchOptions -> CompInputFile -> IO ()
go CmdBatchOptions{..} compFile@(CompInputFile compPath) = do
    let lenFile@(TaskLengthFile lenPath) = compToTaskLength compFile
    let crossFile@(CrossZoneFile crossPath) = compToCross compFile
    let tagFile@(TagZoneFile tagPath) = crossToTag . compToCross $ compFile
    let maskArrivalFile@(MaskArrivalFile maskArrivalPath) = compToMaskArrival compFile
    let maskEffortFile@(MaskEffortFile maskEffortPath) = compToMaskEffort compFile
    let maskLeadFile@(MaskLeadFile maskLeadPath) = compToMaskLead compFile
    let maskReachFile@(MaskReachFile maskReachPath) = compToMaskReach compFile
    let maskSpeedFile@(MaskSpeedFile maskSpeedPath) = compToMaskSpeed compFile
    let bonusReachFile@(BonusReachFile bonusReachPath) = compToBonusReach compFile
    let landFile@(LandOutFile landPath) = compToLand compFile
    let pointFile = compToPoint compFile
    putStrLn $ "Reading task length from '" ++ takeFileName lenPath ++ "'"
    putStrLn $ "Reading pilots ABS & DNF from task from '" ++ takeFileName compPath ++ "'"
    putStrLn $ "Reading zone crossings from '" ++ takeFileName crossPath ++ "'"
    putStrLn $ "Reading start and end zone tagging from '" ++ takeFileName tagPath ++ "'"
    putStrLn $ "Reading arrivals from '" ++ takeFileName maskArrivalPath ++ "'"
    putStrLn $ "Reading effort from '" ++ takeFileName maskEffortPath ++ "'"
    putStrLn $ "Reading leading from '" ++ takeFileName maskLeadPath ++ "'"
    putStrLn $ "Reading reach from '" ++ takeFileName maskReachPath ++ "'"
    putStrLn $ "Reading bonus reach from '" ++ takeFileName bonusReachPath ++ "'"
    putStrLn $ "Reading speed from '" ++ takeFileName maskSpeedPath ++ "'"
    putStrLn $ "Reading distance difficulty from '" ++ takeFileName landPath ++ "'"

    compSettings <-
        catchIO
            (Just <$> readComp compFile)
            (const $ return Nothing)

    cgs <-
        catchIO
            (Just <$> readCrossing crossFile)
            (const $ return Nothing)

    tgs <-
        catchIO
            (Just <$> readTagging tagFile)
            (const $ return Nothing)

    ma <-
        catchIO
            (Just <$> readMaskingArrival maskArrivalFile)
            (const $ return Nothing)

    me <-
        catchIO
            (Just <$> readMaskingEffort maskEffortFile)
            (const $ return Nothing)

    ml <-
        catchIO
            (Just <$> readMaskingLead maskLeadFile)
            (const $ return Nothing)

    mr <-
        catchIO
            (Just <$> readMaskingReach maskReachFile)
            (const $ return Nothing)

    br <-
        catchIO
            (Just <$> readBonusReach bonusReachFile)
            (const $ return Nothing)

    ms <-
        catchIO
            (Just <$> readMaskingSpeed maskSpeedFile)
            (const $ return Nothing)

    landing <-
        catchIO
            (Just <$> readLanding landFile)
            (const $ return Nothing)

    routes <-
        catchIO
            (Just <$> readRoute lenFile)
            (const $ return Nothing)

    let lookupTaskLength =
            routeLength
                taskRoute
                taskRouteSpeedSubset
                stopRoute
                startRoute
                routes

    case (compSettings, cgs, tgs, ma, me, ml, mr, br, ms, landing, routes) of
        (Nothing, _, _, _, _, _, _, _, _, _, _) -> putStrLn "Couldn't read the comp settings."
        (_, Nothing, _, _, _, _, _, _, _, _, _) -> putStrLn "Couldn't read the crossings."
        (_, _, Nothing, _, _, _, _, _, _, _, _) -> putStrLn "Couldn't read the taggings."
        (_, _, _, Nothing, _, _, _, _, _, _, _) -> putStrLn "Couldn't read the masking arrivals."
        (_, _, _, _, Nothing, _, _, _, _, _, _) -> putStrLn "Couldn't read the masking effort."
        (_, _, _, _, _, Nothing, _, _, _, _, _) -> putStrLn "Couldn't read the masking leading."
        (_, _, _, _, _, _, Nothing, _, _, _, _) -> putStrLn "Couldn't read the masking reach."
        (_, _, _, _, _, _, _, Nothing, _, _, _) -> putStrLn "Couldn't read the bonus reach."
        (_, _, _, _, _, _, _, _, Nothing, _, _) -> putStrLn "Couldn't read the masking speed."
        (_, _, _, _, _, _, _, _, _, Nothing, _) -> putStrLn "Couldn't read the land outs."
        (_, _, _, _, _, _, _, _, _, _, Nothing) -> putStrLn "Couldn't read the routes."
        (Just cs, Just cg, Just tg, Just mA, Just mE, Just mL, Just mR, Just bR, Just mS, Just lg, Just _) ->
            writePointing pointFile $ points' cs lookupTaskLength cg tg mA mE mL (mR, bR) mS lg

points'
    :: CompSettings k
    -> RoutesLookupTaskDistance
    -> Crossing
    -> Tagging
    -> MaskingArrival
    -> MaskingEffort
    -> MaskingLead
    -> (MaskingReach, MaskingReach)
    -> MaskingSpeed
    -> Cmp.Landing
    -> Pointing
points'
    CompSettings
        { comp =
            Comp{discipline}
        , nominal =
            Nominal
                { launch = lNom
                , goal = gNom
                , distance = dNom
                , time = tNom
                , free
                }
        , tasks
        , pilots
        , pilotGroups
        }
    routes
    Crossing{flying}
    Tagging{tagging}
    MaskingArrival
        { pilotsAtEss
        , arrivalRank
        }
    MaskingEffort
        { bestEffort
        , land
        }
    MaskingLead
        { sumDistance
        , leadRank
        }
    ( MaskingReach
        { reach = reachStatsF
        , bolster = bolsterStatsF
        , nigh = nighF
        }
    , MaskingReach
        { reach = reachStatsE
        , bolster = bolsterStatsE
        , nigh = nighE
        }
    )
    MaskingSpeed
        { ssBestTime
        , gsBestTime
        , taskSpeedDistance
        , ssSpeed
        , gsSpeed
        , altStopped
        }
    Landing
        { difficulty = landoutDifficulty
        } =
    Pointing
        { validityWorking = workings
        , validity = validities
        , allocation = allocs
        , score = score
        , scoreDf = scoreDf
        , scoreDfNoTrack = scoreDfNoTrack
        }
    where
        -- NOTE: p = pilot, t = track, nt = no track, dnf = did not fly, df = did fly
        -- s suffix is a list, ss suffix is a list of lists.
        pss = toInteger . length <$> pilots
        ntss = toInteger . length . unDfNoTrack . didFlyNoTracklog <$> pilotGroups
        dnfss = toInteger . length . dnf <$> pilotGroups

        tss =
            [ ps - (dnfs + nts)
            | ps <- pss
            | dnfs <- dnfss
            | nts <- ntss
            ]

        dfss =
            [ ts + nts
            | ts <- tss
            | nts <- ntss
            ]

        dfNtss = didFlyNoTracklog <$> pilotGroups

        -- Task lengths (ls).
        iTasks = IxTask <$> [1 .. length tss]
        lsTask' = Lookup.compRoutes routes iTasks

        lsWholeTask :: [Maybe (QTaskDistance Double [u| m |])] =
            (fmap . fmap) wholeTaskDistance lsTask'

        lsSpeedTask :: [Maybe (QTaskDistance Double [u| m |])] =
            (fmap . fmap) speedSubsetDistance lsTask'

        lsLaunchToEssTask :: [Maybe (QTaskDistance Double [u| m |])] =
            (fmap . fmap) launchToEssDistance lsTask'

        lsLaunchToSssTask :: [Maybe (QTaskDistance Double [u| m |])] =
            (fmap . fmap) launchToSssDistance lsTask'

        -- NOTE: If there is no best distance, then either the task wasn't run
        -- or it has not been scored yet.
        maybeTasks :: [a -> Maybe a]
        maybeTasks =
            [ if b == [u| 0 km |] then const Nothing else Just
            | ReachStats{max = FlownMax b} <- bolsterStatsF
            ]

        lvs =
            [ launchValidity
                lNom
                (PilotsPresent . fromInteger $ dfs + dnfs)
                (PilotsFlying . fromInteger $ dfs)
            | dfs <- dfss
            | dnfs <- dnfss
            ]

        dSums :: [SumOfDistance (Quantity Double [u| km |])] =
            [ SumOfDistance . MkQuantity $ fromMaybe 0 s
            | s <- (fmap . fmap) unTaskDistanceAsKm sumDistance
            ]

        dvs =
            [ distanceValidity
                gNom
                dNom
                pf
                free
                (ReachToggle{extra = bE, flown = bF})
                s
            | pf <- PilotsFlying <$> dfss
            | ReachStats{max = bE} <- bolsterStatsE
            | ReachStats{max = bF} <- bolsterStatsF
            | s <- dSums
            ]

        tvs =
            let f =
                    (fmap . fmap)
                        (\(BestTime x) -> BestTime (convert x :: Quantity _ [u| s |]))
            in
                [ timeValidity
                    ((\(NominalTime x) ->
                        NominalTime (convert x :: Quantity _ [u| s |])) tNom)
                    ssT
                    gsT
                    dNom
                    (ReachToggle{extra = bE, flown = bF})

                | ssT <- f ssBestTime
                | gsT <- f gsBestTime
                | ReachStats{max = bE} <- bolsterStatsE
                | ReachStats{max = bF} <- bolsterStatsF
                ]

        workings :: [Maybe ValidityWorking] =
            [ do
                lv' <- lv
                dv' <- dv
                (flip (ValidityWorking lv' dv') sv) <$> tv
            | lv <- snd <$> lvs
            | dv <- snd <$> dvs
            | tv <- snd <$> tvs
            | sv <- (join . fmap snd) <$> svs
            ]

        grs =
            [ GoalRatio $ n % dfs
            | n <- (\(PilotsAtEss x) -> x) <$> pilotsAtEss
            | dfs <- dfss
            ]

        dws = distanceWeight <$> grs

        rws =
            let rw = if discipline == HangGliding then RwHg else RwPg
            in reachWeight . rw <$> dws

        ews =
            if discipline == HangGliding
               then effortWeight . EwHg <$> dws
               else const (effortWeight EwPg) <$> dws

        lws =
            [
                leadingWeight $
                maybe
                    (if | discipline == HangGliding -> LwHg dw
                        | gr == GoalRatio 0 -> LwPgZ $ distanceRatio bd td
                        | otherwise -> LwPg dw)
                    (\k ->
                        if | discipline == HangGliding -> LwScaled k dw
                           | gr == GoalRatio 0 -> LwPgZ $ distanceRatio bd td
                           | otherwise -> LwScaled k dw)
                    (join $ leadingWeightScaling <$> tw)

            | gr <- grs
            | dw <- dws
            | tw <- taskTweak <$> tasks
            | ReachStats{max = FlownMax bd} <- bolsterStatsE
            | td <- maybe [u| 0.0 km |] (MkQuantity . unTaskDistanceAsKm) <$> lsWholeTask
            ]

        aws =
            [
                arrivalWeight $
                maybe
                    AwZero
                    (\Tweak{arrivalRank = byRank, arrivalTime = byTime} ->
                        if | discipline == Paragliding -> AwZero
                           | byTime -> AwHgTime dw
                           | byRank -> AwHgRank dw
                           | otherwise -> AwZero)
                   tw

            | dw <- dws
            | tw <- taskTweak <$> tasks
            ]

        ws =
            [ Gap.Weights rw ew dw lw aw (timeWeight dw lw aw)
            | dw <- dws
            | rw <- rws
            | ew <- ews
            | lw <- lws
            | aw <- aws
            ]

        -- NOTE: Limited to the pilots we have landing times for.
        plss :: [[(Pilot, UTCTime)]] =
            [
                catMaybes
                [ sequence (p, join $ (fmap snd . flyingTimes) <$> tfs)
                | (p, tfs) <- fts
                ]
            | fts <- flying
            ]

        pls :: [([(Pilot, UTCTime)], [(Pilot, UTCTime)])] =
            [
                case stopped of
                    Nothing -> ([], [])
                    Just TaskStop{retroactive = t} ->
                        partition
                            ((< t) . snd)
                            pfs

            | pfs <- plss
            | Task{stopped} <- tasks
            ]

        svs :: [Maybe (StopValidity, Maybe StopValidityWorking)] =
            [
                do
                    _ <- sp
                    ed' <- ed
                    let ls = PilotsLanded . fromIntegral . length $ snd <$> landedByStop
                    let sf = PilotsFlying . fromIntegral . length $ snd <$> stillFlying
                    let r = ReachToggle{extra = rE, flown = rF}

                    return $ stopValidity pf pe ls sf r ed'

            | sp <- stopped <$> tasks
            | pf <- PilotsFlying <$> dfss
            | pe <- pilotsAtEss
            | (landedByStop, stillFlying) <- pls

            | rE <- reachStatsE
            | rF <- reachStatsF

            | ed <-
                (fmap . fmap)
                    (\(TaskDistance td) -> LaunchToEss $ convert td)
                    lsLaunchToEssTask
            ]

        validities :: [Maybe Validity] =
            [ maybeTask $ Validity (taskValidity lv dv tv sv) lv dv tv sv
            | lv <- fst <$> lvs
            | dv <- fst <$> dvs
            | tv <- fst <$> tvs
            | sv <- fmap fst <$> svs
            | maybeTask <- maybeTasks
            ]

        allocs :: [Maybe Allocation]=
            [ do
                v' <- v
                let (pts, taskPoints) = availablePoints v' w
                return $ Allocation gr w pts taskPoints
            | gr <- grs
            | w <- ws
            | v <- (fmap . fmap) Gap.task validities
            ]

        -- NOTE: Pilots either get to goal or have a nigh distance.
        nighDistanceDfE :: [[(Pilot, Maybe Double)]] =
            [ let xs' = (fmap . fmap) madeNigh xs
                  ys' = (fmap . fmap) (const . Just $ unFlownMaxAsKm b) ys
              in (xs' ++ ys')
            | ReachStats{max = b} <- bolsterStatsE
            | xs <- nighE
            | ys <- arrivalRank
            ]

        nighDistanceDfF :: [[(Pilot, Maybe Double)]] =
            [ let xs' = (fmap . fmap) madeNigh xs
                  ys' = (fmap . fmap) (const . Just $ unFlownMaxAsKm b) ys
              in (xs' ++ ys')
            | ReachStats{max = b} <- bolsterStatsF
            | xs <- nighF
            | ys <- arrivalRank
            ]

        nighDistanceDfNoTrackE :: [[(Pilot, Maybe Double)]] =
            [
                (\Cmp.DfNoTrackPilot{pilot = p, awardedReach = aw} ->
                    (p, madeAwarded free lWholeTask $ Gap.extra <$> aw))
                <$> xs
            | DfNoTrack xs <- dfNtss
            | lWholeTask <- lsWholeTask
            ]

        -- NOTE: Pilots either get to the end of the speed section or
        -- they don't and will not get a speed over that section.
        speedDistance :: [[(Pilot, Maybe Double)]] =
            [ let xs' = (fmap . fmap) (const Nothing) xs
                  ys' = (fmap . fmap) (const sd) ys
              in (xs' ++ ys')
            | sd <- (fmap . fmap) unTaskDistanceAsKm taskSpeedDistance
            | xs <- nighF
            | ys <- arrivalRank
            ]

        -- NOTE: Pilots either get to goal or have a landing distance.
        landDistance :: [[(Pilot, Maybe Double)]] =
            [ let xs' = (fmap . fmap) madeLand xs
                  ys' = (fmap . fmap) (const bd) ys
              in (xs' ++ ys')
            | bd <- (fmap . fmap) unTaskDistanceAsKm bestEffort
            | xs <- land
            | ys <- arrivalRank
            ]

        stoppedAlts :: [[(Pilot, Maybe (QAlt Double [u| m |]))]] =
            [ let ys' = (fmap . fmap) (const Nothing) ys in (xs ++ ys')
            | xs <- (fmap . fmap . fmap) Just altStopped
            | ys <- arrivalRank
            ]

        difficultyDistancePointsDf :: [[(Pilot, DifficultyPoints)]] =
            [ maybe
                []
                (\ps' ->
                    let ld' = mapOfDifficulty ld

                        (f, g) = discipline & \case
                               HangGliding ->
                                    (madeDifficultyDf free ld', const $ DifficultyFraction 0.5)
                               Paragliding ->
                                    (const $ DifficultyFraction 0.0, const $ DifficultyFraction 0.0)

                        xs' = (fmap . fmap) f xs
                        ys' = (fmap . fmap) g ys
                    in
                        (fmap . fmap)
                        (applyDifficulty ps')
                        (xs' ++ ys')
                )
                ps
            | ps <- (fmap . fmap) points allocs
            | xs <- land
            | ys <- arrivalRank
            | ld <- landoutDifficulty
            ]

        dFree = TaskDistance . convert $ unpack free

        difficultyDistancePointsDfNoTrack :: [[(Pilot, DifficultyPoints)]] =
            [ maybe
                []
                (\ps' ->
                    let ld' = mapOfDifficulty ld

                        f = discipline & \case
                               HangGliding -> madeDifficultyDfNoTrack free lWholeTask ld'
                               Paragliding -> const $ DifficultyFraction 0.0

                        -- NOTE: These pilots get at least free distance.
                        freeOrMore x@AwardedDistance{awardedMade = d} =
                            let made = Stats.max dFree d in
                                if | made == d -> x
                                   | otherwise ->
                                        maybe
                                            x
                                            (\(TaskDistance (MkQuantity td)) ->
                                                let (TaskDistance (MkQuantity df)) = made in
                                                x
                                                    { awardedMade = made
                                                    , awardedFrac = min 1 $ df / td
                                                    })
                                            lWholeTask

                        xs' =
                            (\Cmp.DfNoTrackPilot{pilot = p, awardedReach = aw} ->
                                (p, f . fmap freeOrMore $ Gap.extra <$> aw))
                            <$> xs
                    in
                        (fmap . fmap)
                        (applyDifficulty ps')
                        xs'
                )
                ps
            | ps <- (fmap . fmap) points allocs
            | DfNoTrack xs <- dfNtss
            | ld <- landoutDifficulty
            | lWholeTask <- lsWholeTask
            ]

        tooEarlyPoints :: [TooEarlyPoints]
        tooEarlyPoints =
            [
                TooEarlyPoints . round . unpack
                $ maybe
                    (LinearPoints 0)
                    (\ps' ->
                        let bd = Just . TaskDistance $ convert b in
                        (applyLinear free bd ps') (Just . unQuantity $ unpack free))
                    ps
            | ReachStats{max = FlownMax b} <- bolsterStatsE
            | ps <- (fmap . fmap) points allocs
            ]

        launchToStartPoints :: [LaunchToStartPoints]
        launchToStartPoints =
            [
                LaunchToStartPoints . round . unpack
                $ maybe
                    (LinearPoints 0)
                    (\ps' ->
                        let bd = Just . TaskDistance $ convert b
                        in (applyLinear free bd ps') launchToStart)
                    ps
            | ReachStats{max = FlownMax b} <- bolsterStatsE
            | ps <- (fmap . fmap) points allocs
            | launchToStart <-
                (fmap . fmap)
                    (\(TaskDistance td) ->
                        let ss :: Quantity _ [u| m |]
                            ss = convert td
                         in unQuantity ss)
                    lsLaunchToSssTask
            ]

        nighDistancePointsDfE :: [[(Pilot, LinearPoints)]] =
            [ maybe
                []
                (\ps' ->
                    let bd = Just . TaskDistance $ convert b in
                    (fmap . fmap) (applyLinear free bd ps') ds)
                ps
            | ReachStats{max = FlownMax b} <- bolsterStatsE
            | ps <- (fmap . fmap) points allocs
            | ds <- nighDistanceDfE
            ]

        nighDistancePointsDfNoTrackE :: [[(Pilot, LinearPoints)]] =
            [ maybe
                []
                (\ps' ->
                    let bd = Just . TaskDistance $ convert b in
                    (fmap . fmap) (applyLinear free bd ps') ds)
                ps
            | ReachStats{max = FlownMax b} <- bolsterStatsE
            | ps <- (fmap . fmap) points allocs
            | ds <- nighDistanceDfNoTrackE
            ]

        leadingPoints :: [[(Pilot, LeadingPoints)]] =
            [ maybe
                []
                (\ps' ->
                    let xs' = (fmap . fmap) (const $ LeadingFraction 0) xs
                        ys' = (fmap . fmap) leadingFraction ys
                    in
                        (fmap . fmap)
                        (applyLeading ps')
                        (xs' ++ ys')
                )
                ps
            | ps <- (fmap . fmap) points allocs
            | xs <- nighF
            | ys <- leadRank
            ]

        arrivalPoints :: [[(Pilot, ArrivalPoints)]] =
            [ maybe
                []
                (\ps' ->
                    let xs' = (fmap . fmap) (const $ ArrivalFraction 0) xs
                        ys' = (fmap . fmap) arrivalFraction ys
                    in
                        (fmap . fmap)
                        (applyArrival ps')
                        (xs' ++ ys')
                )
                ps
            | ps <- (fmap . fmap) points allocs
            | xs <- nighF
            | ys <- arrivalRank
            ]

        timePoints :: _ -> [[(Pilot, TimePoints)]] =
            \speed ->
                [ maybe
                    []
                    (\ps' ->
                        let xs' = (fmap . fmap) (const $ SpeedFraction 0) xs
                            ys' = (fmap . fmap) speedFraction ys
                        in
                            (fmap . fmap)
                            (applyTime ps')
                            (xs' ++ ys')
                    )
                    ps
                | ps <- (fmap . fmap) points allocs
                | xs <- nighF
                | ys <- speed
                ]

        elapsedTime :: _ -> [[(Pilot, Maybe (PilotTime (Quantity Double [u| h |])))]] =
            \speed ->
                [ let xs' = (fmap . fmap) (const Nothing) xs
                      ys' = (fmap . fmap) (Just . Speed.time) ys
                  in (xs' ++ ys')
                | xs <- nighF
                | ys <- speed
                ]

        speedSections :: [SpeedSection] = speedSection <$> tasks

        tags :: [[(Pilot, Maybe StartEndTags)]] =
            [ (fmap . fmap) (startEnd . section ss)
              . (\(PilotTrackTag p tag) -> (p, zonesTag <$> tag))
              <$> ts
            | ss <- speedSections
            | ts <- tagging
            ]

        scoreDf :: [[(Pilot, Breakdown)]] =
            [ let dsL = Map.fromList dsLand
                  dsE = Map.fromList dsNighE
                  dsF = Map.fromList dsNighF
                  dsS = Map.fromList dsSpeed
                  ds =
                      Map.toList
                      $ Map.intersectionWith (\s (e, f, l) -> (s, e, f, l)) dsS
                      $ Map.intersectionWith (\e (f, l) -> (e, f, l)) dsE
                      $ Map.intersectionWith (,) dsF dsL

              in
                  rankByTotal . sortScores
                  $ fmap (tallyDf discipline startGates hgTooE pgTooE earlyStart)
                  A.<$> collateDf diffs linears ls as ts penals alts ds ssEs gsEs gs
            | hgTooE <- tooEarlyPoints
            | pgTooE <- launchToStartPoints
            | diffs <- difficultyDistancePointsDf
            | linears <- nighDistancePointsDfE
            | ls <- leadingPoints
            | as <- arrivalPoints
            | ts <- timePoints gsSpeed
            | dsSpeed <-
                (fmap . fmap)
                    ((fmap . fmap) (PilotDistance . MkQuantity))
                    speedDistance
            | dsNighE <-
                (fmap . fmap)
                    ((fmap . fmap) (PilotDistance . MkQuantity))
                    nighDistanceDfE
            | dsNighF <-
                (fmap . fmap)
                    ((fmap . fmap) (PilotDistance . MkQuantity))
                    nighDistanceDfF
            | dsLand <-
                (fmap . fmap)
                    ((fmap . fmap) (PilotDistance . MkQuantity))
                    landDistance
            | alts <- stoppedAlts
            | ssEs <- elapsedTime ssSpeed
            | gsEs <- elapsedTime gsSpeed
            | gs <- tags
            | Task{startGates, earlyStart} <- tasks
            | penals <- penals <$> tasks
            ]

        scoreDfNoTrack :: [[(Pilot, Breakdown)]] =
            [ rankByTotal . sortScores
              $ fmap (tallyDfNoTrack gates lSpeedTask lWholeTask)
              A.<$> collateDfNoTrack diffs linears as ts penals dsAward
            | diffs <- difficultyDistancePointsDfNoTrack
            | linears <- nighDistancePointsDfNoTrackE
            | as <- arrivalPoints
            | ts <- timePoints gsSpeed
            | dsAward <- dfNtss
            | lSpeedTask <- lsSpeedTask
            | lWholeTask <- lsWholeTask
            | gates <- startGates <$> tasks
            | penals <- penals <$> tasks
            ]

        score :: [[(Pilot, Breakdown)]] =
            [ rankByTotal . sortScores $ xs ++ ys
            | xs <- scoreDf
            | ys <- scoreDfNoTrack
            ]

sortScores :: [(Pilot, Breakdown)] -> [(Pilot, Breakdown)]
sortScores =
    sortBy
        (\(_, Breakdown{total = a}) (_, Breakdown{total = b}) ->
            b `compare` a)

zeroPoints :: Gap.Points
zeroPoints =
    Gap.Points
        { reach = LinearPoints 0
        , effort = DifficultyPoints 0
        , distance = DistancePoints 0
        , leading = LeadingPoints 0
        , arrival = ArrivalPoints 0
        , time = TimePoints 0
        }

mapOfDifficulty :: Maybe [ChunkDifficulty] -> Map IxChunk DifficultyFraction
mapOfDifficulty Nothing = Map.fromList []
mapOfDifficulty (Just xs) =
    Map.fromList $ (\ChunkDifficulty{chunk, frac} -> (chunk, frac)) <$> xs

applyDifficulty
    :: Gap.Points
    -> DifficultyFraction
    -> DifficultyPoints
applyDifficulty Gap.Points{distance = DistancePoints y} (DifficultyFraction frac) =
    -- NOTE: A fraction of distance points, not a fraction of effort points.
    DifficultyPoints $ frac * y

madeDifficultyDf
    :: MinimumDistance (Quantity Double [u| km |])
    -> Map IxChunk DifficultyFraction
    -> TrackDistance Land
    -> DifficultyFraction
madeDifficultyDf _ mapIxToFrac td =
    fromMaybe (DifficultyFraction 0) $ Map.lookup ix mapIxToFrac
    where
        pd = PilotDistance . MkQuantity . fromMaybe 0.0 $ madeLand td
        ix = toIxChunk pd

madeDifficultyDfNoTrack
    :: MinimumDistance (Quantity Double [u| km |])
    -> Maybe (QTaskDistance Double [u| m |])
    -> Map IxChunk DifficultyFraction
    -> Maybe AwardedDistance
    -> DifficultyFraction
madeDifficultyDfNoTrack (MinimumDistance dMin) td mapIxToFrac dAward =
    fromMaybe (DifficultyFraction 0) $ Map.lookup ix mapIxToFrac
    where
        pd :: Quantity Double [u| km |]
        pd =
            case (td, dAward) of
                (_, Nothing) -> dMin
                (Nothing, _) -> dMin
                (Just td', Just dAward') ->
                    -- WARNING: Don't allow awardedFrac to give a pilot
                    -- distance less than the free distance.
                    Stats.max dMin $ awardByFrac (Clamp True) td' dAward'

        ix = toIxChunk (PilotDistance pd)

madeAwarded
    :: MinimumDistance (Quantity Double [u| km |])
    -> Maybe (QTaskDistance Double [u| m |])
    -> Maybe AwardedDistance
    -> Maybe Double -- ^ The distance made in km
madeAwarded _ (Just td) (Just dAward) = Just . unQuantity $ awardByFrac (Clamp True) td dAward
madeAwarded (MinimumDistance (MkQuantity d)) _ _ = Just d

madeNigh :: TrackDistance Nigh -> Maybe Double
madeNigh TrackDistance{made} = unTaskDistanceAsKm <$> made

madeLand :: TrackDistance Land -> Maybe Double
madeLand TrackDistance{made} = unTaskDistanceAsKm <$> made

applyLinear
    :: MinimumDistance (Quantity Double [u| km |])
    -> Maybe (QTaskDistance Double [u| m |]) -- ^ The best distance
    -> Gap.Points
    -> Maybe Double -- ^ The distance made in km
    -> LinearPoints
applyLinear _ Nothing _ _ = LinearPoints 0
applyLinear _ _ _ Nothing = LinearPoints 0
applyLinear
    (MinimumDistance (MkQuantity dMin))
    (Just (TaskDistance best))
    Gap.Points{reach = LinearPoints y}
    (Just made) =
        if | best' <= 0 -> LinearPoints 0
           | otherwise -> LinearPoints $ frac * y
    where
        frac :: Rational
        frac = toRational (Stats.max dMin made) / toRational best'

        MkQuantity best' = convert best :: Quantity Double [u| km |]

leadingFraction :: TrackLead u -> LeadingFraction
leadingFraction TrackLead{frac} = frac

applyLeading :: Gap.Points -> LeadingFraction -> LeadingPoints
applyLeading Gap.Points{leading = LeadingPoints y} (LeadingFraction x) =
    LeadingPoints $ x * y

arrivalFraction :: TrackArrival -> ArrivalFraction
arrivalFraction TrackArrival{frac} = frac

applyArrival :: Gap.Points -> ArrivalFraction -> ArrivalPoints
applyArrival Gap.Points{arrival = ArrivalPoints y} (ArrivalFraction x) =
    ArrivalPoints $ x * y

speedFraction :: Speed.TrackSpeed -> SpeedFraction
speedFraction Speed.TrackSpeed{frac} = frac

applyTime :: Gap.Points -> SpeedFraction -> TimePoints
applyTime Gap.Points{time = TimePoints y} (SpeedFraction x) =
    TimePoints $ x * y

collateDf
    :: [(Pilot, DifficultyPoints)]
    -> [(Pilot, LinearPoints)]
    -> [(Pilot, LeadingPoints)]
    -> [(Pilot, ArrivalPoints)]
    -> [(Pilot, TimePoints)]
    -> [(Pilot, [PointPenalty], String)]
    -> [(Pilot, Maybe alt)]
    -> [(Pilot, (Maybe a, Maybe a, Maybe a, Maybe a))]
    -> [(Pilot, Maybe b)]
    -> [(Pilot, Maybe c)]
    -> [(Pilot, Maybe d)]
    -> [
            ( Pilot
            ,
                ( Maybe alt
                ,
                    ( Maybe d
                    ,
                        ( Maybe c
                        ,
                            ( Maybe b
                            ,
                                ( (Maybe a, Maybe a, Maybe a, Maybe a)
                                ,
                                    ( ([PointPenalty], String)
                                    , Gap.Points
                                    )
                                )
                            )
                        )
                    )
                )
            )
        ]
collateDf diffs linears ls as ts penals alts ds ssEs gsEs gs =
    Map.toList
    $ Map.intersectionWith (,) malts
    $ Map.intersectionWith (,) mg
    $ Map.intersectionWith (,) mgsEs
    $ Map.intersectionWith (,) mssEs
    $ Map.intersectionWith (,) md
    $ Map.intersectionWith (,) (mergePenalties md $ Map.fromList penals')
    $ Map.intersectionWith glueLeading ml
    $ Map.unionWith mergeSpeed mdl mta
    where
        mDiff = Map.fromList diffs
        mLinear = Map.fromList linears
        ml = Map.fromList ls
        ma = Map.fromList as
        mt = Map.fromList ts
        malts = Map.fromList alts
        md = Map.fromList ds
        mssEs = Map.fromList ssEs
        mgsEs = Map.fromList gsEs
        mg = Map.fromList gs
        penals' = tuplePenalty <$> penals

        mdl =
            Map.intersectionWith glueDiff mDiff
            $ zeroLinear <$> mLinear

        mta =
            Map.intersectionWith glueTime mt
            $ zeroArrival <$> ma

collateDfNoTrack
    :: [(Pilot, DifficultyPoints)]
    -> [(Pilot, LinearPoints)]
    -> [(Pilot, ArrivalPoints)]
    -> [(Pilot, TimePoints)]
    -> [(Pilot, [PointPenalty], String)]
    -> DfNoTrack
    -> [
            (Pilot
            ,
                ( (Maybe (ReachToggle AwardedDistance), AwardedVelocity)
                ,
                    ( ([PointPenalty], String)
                    , Gap.Points
                    )
                )
            )
        ]
collateDfNoTrack diffs linears as ts penals (DfNoTrack ds) =
    Map.toList
    $ Map.intersectionWith (,) md
    $ Map.intersectionWith (,) (mergePenalties md $ Map.fromList penals')
    $ Map.unionWith mergeSpeed mdl mta
    where
        mDiff = Map.fromList diffs
        mLinear = Map.fromList linears
        ma = Map.fromList as
        mt = Map.fromList ts
        penals' = tuplePenalty <$> penals

        md =
            Map.fromList
            $ (\Cmp.DfNoTrackPilot{pilot = p, awardedReach = aw, awardedVelocity = av} ->
                (p, (aw, av)))
            <$> ds

        mdl =
            Map.intersectionWith glueDiff mDiff
            $ zeroLinear <$> mLinear

        mta =
            Map.intersectionWith glueTime mt
            $ zeroArrival <$> ma

tuplePenalty :: (a, b, c) -> (a, (b, c))
tuplePenalty (a, b, c) = (a, (b, c))

-- | Merge maps so that each pilot has a list of penalties, possibly an empty one.
mergePenalties
    :: Map Pilot a
    -> Map Pilot ([PointPenalty], String)
    -> Map Pilot ([PointPenalty], String)
mergePenalties =
    Map.merge
        (Map.mapMissing (\_ _ -> ([], "")))
        (Map.preserveMissing)
        (Map.zipWithMatched (\_ _ y -> y))

mergeSpeed :: Gap.Points -> Gap.Points -> Gap.Points
mergeSpeed g Gap.Points{Gap.time = t, Gap.arrival = a} =
    g{Gap.time = t, Gap.arrival = a}

zeroLinear :: LinearPoints -> Gap.Points
zeroLinear r = zeroPoints {Gap.reach = r}

zeroArrival :: ArrivalPoints -> Gap.Points
zeroArrival a = zeroPoints {Gap.arrival = a}

glueDiff :: DifficultyPoints -> Gap.Points -> Gap.Points
glueDiff
    effort@(DifficultyPoints diff)
    p@Gap.Points {Gap.reach = LinearPoints linear} =
    p
        { Gap.effort = effort
        , Gap.distance = DistancePoints $ diff + linear
        }

glueLeading :: LeadingPoints -> Gap.Points -> Gap.Points
glueLeading l p = p{Gap.leading = l}

glueTime :: TimePoints -> Gap.Points -> Gap.Points
glueTime t p = p {Gap.time = t}

zeroVelocity :: Velocity
zeroVelocity =
    Velocity
        { ss = Nothing
        , gs = Nothing
        , es = Nothing
        , ssElapsed = Nothing
        , gsElapsed = Nothing
        , ssDistance = Nothing
        , ssVelocity = Nothing
        , gsVelocity = Nothing
        }

mkVelocity
    :: PilotDistance (Quantity Double [u| km |])
    -> PilotTime (Quantity Double [u| h |])
    -> PilotVelocity (Quantity Double [u| km / h |])
mkVelocity (PilotDistance d) (PilotTime t) =
    PilotVelocity $ d /: t

startEnd :: RaceSections (Maybe ZoneTag) -> StartEndTags
startEnd RaceSections{race} =
    case (race, reverse race) of
        ([], _) -> StartEnd Nothing Nothing
        (_, []) -> StartEnd Nothing Nothing
        (x : _, y : _) -> StartEnd x y

tallyDf
    :: Discipline
    -> [StartGate]
    -> TooEarlyPoints
    -> LaunchToStartPoints
    -> EarlyStart
    ->
        ( Maybe (QAlt Double [u| m |])
        ,
            ( Maybe StartEndTags
            ,
                ( Maybe (PilotTime (Quantity Double [u| h |]))
                ,
                    ( Maybe (PilotTime (Quantity Double [u| h |]))
                    ,
                        (
                            ( Maybe (PilotDistance (Quantity Double [u| km |]))
                            , Maybe (PilotDistance (Quantity Double [u| km |]))
                            , Maybe (PilotDistance (Quantity Double [u| km |]))
                            , Maybe (PilotDistance (Quantity Double [u| km |]))
                            )
                        ,
                            ( ([PointPenalty], String)
                            , Gap.Points
                            )
                        )
                    )
                )
            )
        )
    -> Breakdown
tallyDf
    hgOrPg
    startGates
    tooEarlyPoints
    launchToStartPoints
    EarlyStart{earliest, earlyPenalty}
    ( alt
    ,
        ( g
        ,
            ( gsT
            ,
                ( ssT
                ,
                    ( (dS, dE, dF, dL)
                    ,
                        ((penalties, penaltyReason), x)
                    )
                )
            )
        )
    ) =
    Breakdown
        { place = TaskPlacing 0
        , subtotal = subtotal
        , demeritFrac = fracApplied
        , demeritPoint = pointApplied
        , demeritReset = resetApplied
        , total = total
        , jump = jump
        , penaltiesJump = effectivePenaltiesJump
        , penalties = effectivePenalties
        , penaltyReason = penaltyReason
        , breakdown = x
        , velocity =
            Just
            $ zeroVelocity
                { ss = ss'
                , gs = snd <$> jumpGate
                , es = es'
                , ssDistance = dS
                , ssElapsed = ssT
                , gsElapsed = gsT
                , ssVelocity = liftA2 mkVelocity dS ssT
                , gsVelocity = liftA2 mkVelocity dS gsT
                }

        , reach = do
            dE' <- dE
            dF' <- dF
            return ReachToggle{extra = dE', flown = dF'}

        , landedMade = dL
        , stoppedAlt = alt
        }
    where
        jumpGate :: Maybe (Maybe (JumpedTheGun _), StartGate)
        jumpGate = do
                ss'' <- ss'
                gs' <- nonEmpty startGates
                return $ startGateTaken gs' ss''

        jump :: Maybe (JumpedTheGun _)
        jump = join $ fst <$> jumpGate

        ptsReduced =
            case hgOrPg of
                HangGliding ->
                    let eitherPenalties :: [Either PointPenalty (Penalty Hg)]
                        eitherPenalties =
                            maybeToList
                            $ jumpTheGunPenaltyHg tooEarlyPoints earliest earlyPenalty <$> jump

                        jumpDemerits = lefts eitherPenalties
                        jumpReset = listToMaybe $ rights eitherPenalties

                     in Gap.taskPoints jumpReset jumpDemerits penalties x

                Paragliding ->
                    let jumpReset :: Maybe (Penalty Pg)
                        jumpReset =
                            join
                            $ jumpTheGunPenaltyPg launchToStartPoints <$> jump

                     in Gap.taskPoints jumpReset [] penalties x

        PointsReduced
            { subtotal
            , fracApplied
            , pointApplied
            , resetApplied
            , total
            , effectivePenalties
            , effectivePenaltiesJump
            } = ptsReduced

        ss' = getTagTime unStart
        es' = getTagTime unEnd
        getTagTime accessor =
            ((time :: InterpolatedFix -> _) . inter)
            <$> (accessor =<< g)

tallyDfNoTrack
    :: [StartGate]
    -> Maybe (QTaskDistance Double [u| m |]) -- ^ Speed section distance
    -> Maybe (QTaskDistance Double [u| m |]) -- ^ Whole task distance
    ->
        (
            ( Maybe (ReachToggle AwardedDistance)
            , AwardedVelocity
            )
        ,
            ( ([PointPenalty], String)
            , Gap.Points
            )
        )
    -> Breakdown
tallyDfNoTrack
    startGates
    dS'
    dT'
    ( (aw', AwardedVelocity{ss, es})
    ,
        ((penalties, penaltyReason), x)
    ) =
    Breakdown
        { place = TaskPlacing 0
        , subtotal = subtotal
        , demeritFrac = fracApplied
        , demeritPoint = pointApplied
        , demeritReset = resetApplied
        , total = total
        , jump = Nothing
        , penaltiesJump = []
        , penalties = effectivePenalties
        , penaltyReason = penaltyReason
        , breakdown = x

        , velocity =
            case (ss, es) of
                (Just ss', Just _) ->
                    let se = StartEnd ss' es
                        ssT = pilotTime [StartGate ss'] se
                        gsT = pilotTime startGates se
                    in
                        Just
                        $ zeroVelocity
                            { ss = ss
                            , gs = gs
                            , es = es
                            , ssDistance = dS
                            , ssElapsed = ssT
                            , gsElapsed = gsT
                            , ssVelocity = liftA2 mkVelocity dS ssT
                            , gsVelocity = liftA2 mkVelocity dS gsT
                            }
                _ -> Nothing

        , reach = do
            dE' <- dE
            dF' <- dF
            return $ ReachToggle{extra = dE', flown = dF'}

        , landedMade = dE
        , stoppedAlt = Nothing
        }
    where
        gs = snd <$> do
                ss' <- ss
                gs' <- nonEmpty startGates
                return $ startGateTaken gs' ss'

        PointsReduced
            { subtotal
            , fracApplied
            , pointApplied
            , resetApplied
            , total
            , effectivePenalties
            } = Gap.taskPoints Nothing [] penalties x

        dE = PilotDistance <$> do
                dT <- dT'
                aw <- aw'
                return $ awardByFrac (Clamp False) dT (Gap.extra aw)

        dF = PilotDistance <$> do
                dT <- dT'
                aw <- aw'
                return $ awardByFrac (Clamp False) dT (Gap.flown aw)

        dS = PilotDistance <$> do
                TaskDistance d <- dS'
                return $ convert d
