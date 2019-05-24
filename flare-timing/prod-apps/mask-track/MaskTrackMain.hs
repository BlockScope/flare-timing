﻿{-# OPTIONS_GHC -fplugin Data.UnitsOfMeasure.Plugin #-}
{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

import Prelude hiding (last)
import System.Environment (getProgName)
import System.Console.CmdArgs.Implicit (cmdArgs)
import Data.Function (on)
import Data.Maybe (fromMaybe, catMaybes, isJust)
import Data.List (sortOn, groupBy, partition)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map (fromList)
import Formatting ((%), fprint)
import Formatting.Clock (timeSpecs)
import System.Clock (getTime, Clock(Monotonic))
import Control.Arrow (second)
import Control.Lens ((^?), element)
import Control.Exception.Safe (MonadThrow, catchIO)
import Control.Monad (join)
import Control.Monad.Except (MonadIO)
import Data.UnitsOfMeasure ((-:), u, convert, toRational', unQuantity)
import Data.UnitsOfMeasure.Internal (Quantity(..))
import System.FilePath (takeFileName)
import Statistics.Sample (mean, stdDev)
import qualified Data.Vector as V (fromList)

import Flight.Clip (FlyCut(..), FlyClipping(..))
import Flight.LatLng (QAlt)
import Flight.Route (OptimalRoute(..))
import qualified Flight.Comp as Cmp (Nominal(..), DfNoTrackPilot(..))
import Flight.Comp
    ( FileType(CompInput)
    , CompInputFile(..)
    , TaskLengthFile(..)
    , TagZoneFile(..)
    , PegFrameFile(..)
    , CompSettings(..)
    , PilotName(..)
    , Pilot(..)
    , PilotGroup(didFlyNoTracklog)
    , TaskStop(..)
    , Task(..)
    , IxTask(..)
    , TrackFileFail(..)
    , RoutesLookupTaskDistance(..)
    , TaskRouteDistance(..)
    , MadeGoal(..)
    , LandedOut(..)
    , DfNoTrack(..)
    , StartGate(..)
    , StartEnd(..)
    , compToTaskLength
    , compToCross
    , compToMask
    , crossToTag
    , tagToPeg
    , findCompInput
    , speedSectionToLeg
    , ensureExt
    , pilotNamed
    )
import Flight.Distance
    (QTaskDistance, TaskDistance(..), unTaskDistanceAsKm)
import Flight.Mask
    ( FnIxTask
    , checkTracks
    , togoAtLanding
    , madeAtLanding
    )
import Flight.Comp.Distance (compDistance, compNigh)
import Flight.Track.Tag (Tagging)
import Flight.Track.Place (reIndex)
import Flight.Track.Time
    (TimeToTick, TickToTick, AwardedVelocity(..), copyTimeToTick)
import qualified Flight.Track.Time as Time (TimeRow(..), TickRow(..))
import Flight.Track.Arrival (TrackArrival(..))
import Flight.Track.Distance
    ( TrackDistance(..), TrackReach(..), AwardedDistance(..)
    , Clamp(..), Nigh, Land
    )
import qualified Flight.Track.Distance as Track (awardByFrac)
import Flight.Track.Lead (compLeading)
import Flight.Track.Mask (Masking(..), RaceTime(..))
import Flight.Track.Speed (TrackSpeed(..), pilotTime)
import Flight.Kml (LatLngAlt(..), MarkedFixes(..))
import Flight.Cmd.Paths (LenientFile(..), checkPaths)
import Flight.Cmd.Options (ProgramName(..))
import Flight.Cmd.BatchOptions (CmdBatchOptions(..), mkOptions)
import Flight.Lookup.Stop (ScoredLookup(..), stopFlying)
import qualified Flight.Lookup as Lookup
    ( scoredTimeRange, arrivalRank, ticked, compRoutes, compRaceTimes
    , pilotTime, pilotEssTime
    )
import Flight.Lookup.Tag
    ( TaskLeadingLookup(..)
    , tagTaskLeading
    , tagArrivalRank
    , tagPilotTime
    , tagTicked
    )
import Flight.Scribe
    ( readComp, readRoute, readTagging, readFraming, writeMasking
    , readCompLeading, readCompBestDistances, readCompTimeRows
    )
import Flight.Lookup.Route (routeLength)
import qualified Flight.Score as Gap (bestTime')
import Flight.Score
    ( PilotsAtEss(..), ArrivalPlacing(..)
    , BestTime(..), PilotTime(..)
    , MinimumDistance(..), PilotDistance(..), BestDistance(..)
    , LinearFraction(..), LengthOfSs(..)
    , arrivalFraction, speedFraction, linearFraction, areaToCoef
    )
import Flight.Span.Math (Math(..))
import MaskTrackOptions (description)
import Stats (TimeStats(..), FlightStats(..), DashPathInputs(..), nullStats, altToAlt)

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
    fprint ("Masking tracks completed in " % timeSpecs % "\n") start end

go :: CmdBatchOptions -> CompInputFile -> IO ()
go CmdBatchOptions{..} compFile@(CompInputFile compPath) = do
    let lenFile@(TaskLengthFile lenPath) = compToTaskLength compFile
    let tagFile@(TagZoneFile tagPath) = crossToTag . compToCross $ compFile
    let stopFile@(PegFrameFile stopPath) = tagToPeg tagFile
    putStrLn $ "Reading competition from '" ++ takeFileName compPath ++ "'"
    putStrLn $ "Reading task length from '" ++ takeFileName lenPath ++ "'"
    putStrLn $ "Reading zone tags from '" ++ takeFileName tagPath ++ "'"
    putStrLn $ "Reading scored times from '" ++ takeFileName stopPath ++ "'"

    compSettings <-
        catchIO
            (Just <$> readComp compFile)
            (const $ return Nothing)

    tagging <-
        catchIO
            (Just <$> readTagging tagFile)
            (const $ return Nothing)

    stopping <-
        catchIO
            (Just <$> readFraming stopFile)
            (const $ return Nothing)

    routes <-
        catchIO
            (Just <$> readRoute lenFile)
            (const $ return Nothing)

    let scoredLookup = stopFlying stopping
    let lookupTaskLength = routeLength taskRoute taskRouteSpeedSubset stopRoute routes

    case (compSettings, tagging, stopping, routes) of
        (Nothing, _, _, _) -> putStrLn "Couldn't read the comp settings."
        (_, Nothing, _, _) -> putStrLn "Couldn't read the taggings."
        (_, _, Nothing, _) -> putStrLn "Couldn't read the scored frame."
        (_, _, _, Nothing) -> putStrLn "Couldn't read the routes."
        (Just cs, Just _, Just _, Just _) ->
            writeMask
                cs
                lookupTaskLength
                (tagTaskLeading tagging)
                (IxTask <$> task)
                (pilotNamed cs $ PilotName <$> pilot)
                compFile
                (check math lookupTaskLength scoredLookup tagging)

writeMask
    :: CompSettings k
    -> RoutesLookupTaskDistance
    -> TaskLeadingLookup
    -> [IxTask]
    -> [Pilot]
    -> CompInputFile
    -> (CompInputFile
        -> [IxTask]
        -> [Pilot]
        -> IO
            [
                [Either
                    (Pilot, TrackFileFail)
                    (Pilot, Pilot -> FlightStats k)
                ]
            ])
    -> IO ()
writeMask
    CompSettings
        { nominal = Cmp.Nominal{free = free@(MinimumDistance dMin)}
        , tasks
        , pilotGroups
        }
    routes
    lookupTaskLeading
    selectTasks selectPilots compFile f = do

    checks <-
        catchIO
            (Just <$> f compFile selectTasks selectPilots)
            (const $ return Nothing)

    case checks of
        Nothing -> putStrLn "Unable to read tracks for pilots."

        Just fss -> do

            let dfNtss = didFlyNoTracklog <$> pilotGroups

            let fssDf =
                    [ let ps = Cmp.pilot <$> dfNts in
                      filter
                          ( not
                          . (`elem` ps)
                          . (\case Left (p, _) -> p; Right (p, _) -> p))
                          flights
                    | flights <- fss
                    | DfNoTrack dfNts <- dfNtss
                    ]

            let iTasks = IxTask <$> [1 .. length fss]

            -- Task lengths (ls).
            let lsTask' = Lookup.compRoutes routes iTasks
            let lsWholeTask = (fmap . fmap) wholeTaskDistance lsTask'
            let lsSpeedSubset = (fmap . fmap) speedSubsetDistance lsTask'

            let yssDf :: [[(Pilot, FlightStats _)]] =
                    [ fmap
                        (\case
                            Left (p, _) -> (p, nullStats)
                            Right (p, g) -> (p, g p))
                        flights
                    | flights <- fssDf
                    ]

            let yssDfNt :: [[(Pilot, FlightStats _)]] =
                    [
                        fmap
                        (\Cmp.DfNoTrackPilot
                            { pilot = p
                            , awardedReach = dA
                            , awardedVelocity = AwardedVelocity{ss, es}
                            } ->
                            let dm :: Quantity Double [u| m |] = convert dMin

                                d = TaskDistance
                                    <$> maybe
                                        (Just dm)
                                        (\dAward -> do
                                            td <- lTask
                                            let a = awardByFrac (Clamp True) td dAward

                                            return $ max a dm)
                                        dA

                                sLand = madeAwarded <$> lTask <*> d

                                sTime =
                                    case (ss, es) of
                                        (Just ss', Just es') ->
                                            let se = StartEnd ss' es
                                                ssT = pilotTime [StartGate ss'] se
                                                gsT = pilotTime gates se
                                            in
                                                do
                                                    ssT' <- ssT
                                                    gsT' <- gsT
                                                    return
                                                        TimeStats
                                                            { ssTime = ssT'
                                                            , gsTime = gsT'
                                                            , esMark = es'
                                                            , positionAtEss = Nothing
                                                            }
                                        _ -> Nothing

                            in (p, nullStats{statLand = sLand, statTimeRank = sTime}))
                        dfNts
                    | DfNoTrack dfNts <- dfNtss
                    | lTask <- (fmap. fmap) wholeTaskDistance lsTask'
                    | gates <- startGates <$> tasks
                    ]

            let yss =
                    [ rankByArrival ysDf ysDfNt
                    | ysDf <- yssDf
                    | ysDfNt <- yssDfNt
                    ]

            -- Zones (zs) of the task and zones ticked.
            let zsTaskTicked :: [Map Pilot _] =
                    Map.fromList . landTaskTicked <$> yss

            -- Distances (ds) of the landout spot.
            let dsLand :: [[(Pilot, TrackDistance Land)]] = landDistances <$> yss
            let dsAlt :: [[(Pilot, QAlt Double [u| m |])]] = landAltitudes <$> yss

            -- Arrivals (as).
            let as :: [[(Pilot, TrackArrival)]] = arrivals <$> yss

            -- Velocities (vs).
            let ssVs :: [Maybe (BestTime (Quantity Double [u| h |]), [(Pilot, TrackSpeed)])] =
                    times ssTime <$> yss

            let gsVs :: [Maybe (BestTime (Quantity Double [u| h |]), [(Pilot, TrackSpeed)])] =
                    times gsTime <$> yss

            -- Times (ts).
            let ssBestTime = (fmap . fmap) fst ssVs
            let gsBestTime = (fmap . fmap) fst gsVs

            -- For each task, for each pilot, the row closest to goal.
            rows :: [[Maybe (Pilot, Time.TickRow)]]
                <- readCompBestDistances
                    compFile
                    (includeTask selectTasks)
                    ((fmap . fmap) fst dsLand)

            let psArriving = (fmap . fmap) fst as
            let psLandingOut = (fmap . fmap) fst dsLand
            let pilots =
                    [ pAs ++ pLs
                    | pAs <- psArriving
                    | pLs <- psLandingOut
                    ]

            let raceTime =
                    [ do
                        rt@RaceTime{..} <- crt
                        return $
                            maybe
                                rt
                                (\stp ->
                                    uncut . clipToCut $
                                        FlyCut
                                            { cut = Just (openTask, min stp closeTask)
                                            , uncut = rt
                                            })
                                (retroactive <$> stopped task)

                    | crt <- Lookup.compRaceTimes lookupTaskLeading iTasks tasks
                    | task <- tasks
                    ]

            -- NOTE: Leading point calculations use the reach without altitude
            -- bonus applied.
            let nullAltBonuses :: [TimeToTick] = const copyTimeToTick <$> tasks
            let nullTickToTicks :: [TickToTick] = const id <$> tasks

            rowsLeadingStep :: [[(Pilot, [Time.TickRow])]]
                <- readCompLeading
                        nullAltBonuses
                        nullTickToTicks
                        routes
                        compFile
                        (includeTask selectTasks)
                        (IxTask <$> [1 .. ])
                        (speedSectionToLeg . speedSection <$> tasks)
                        raceTime
                        pilots

            let (lcMin, lead) = compLeading rowsLeadingStep lsSpeedSubset tasks

            let lcAreaToCoef =
                    [
                        areaToCoef
                        . LengthOfSs
                        . (\(TaskDistance d) -> convert . toRational' $ d)
                        <$> ssLen
                    | ssLen <- lsSpeedSubset
                    ]

            let (dsSumArriving, dsSumLandingOut, dsBest, rowTicks) =
                    compDistance
                        free
                        lsWholeTask
                        (MadeGoal <$> psArriving)
                        (LandedOut <$> psLandingOut)
                        gsBestTime
                        rows

            -- NOTE: This is the sum of distance over minimum distance.
            let dsSum =
                    [
                        (fmap $ TaskDistance . MkQuantity)
                        . (\case 0 -> Nothing; x -> Just x)
                        . sum
                        . fmap unTaskDistanceAsKm
                        . catMaybes
                        $ [aSum, lSum]
                    | aSum <- dsSumArriving
                    | lSum <- dsSumLandingOut
                    ]

            dsNighRows :: [[Maybe (Pilot, Time.TimeRow)]]
                <- readCompTimeRows
                        compFile
                        (includeTask selectTasks)
                        (catMaybes <$> rowTicks)

            let dsNigh :: [[(Pilot, TrackDistance Nigh)]] =
                    compNigh lsWholeTask zsTaskTicked dsNighRows

            let rsNigh :: [[(Pilot, TrackReach)]] =
                    [
                        catMaybes
                        $
                            (\case
                                (_, Nothing) -> Nothing
                                (a, Just b) -> Just (a, b))
                            . (fmap (\TrackDistance{made} -> do
                                    TaskDistance b <- dBest
                                    td@(TaskDistance d) <- made

                                    let bd :: BestDistance (Quantity Double [u| km |]) =
                                            BestDistance $ convert b
                                    let pd :: PilotDistance (Quantity Double [u| km |]) =
                                            PilotDistance $ convert d

                                    return
                                        TrackReach
                                            { reach = td
                                            , frac = linearFraction bd pd
                                            }))
                            <$> ds

                    | dBest <- dsBest
                    | ds <- dsNigh
                    ]

            let rsArrive :: [[(Pilot, TrackReach)]] =
                    [
                        case dBest of
                            Nothing -> []
                            Just td@(TaskDistance b) ->
                                let bd :: BestDistance (Quantity Double [u| km |]) =
                                        BestDistance $ convert b

                                    pd :: PilotDistance (Quantity Double [u| km |]) =
                                        PilotDistance $ convert b

                                    tr =
                                        TrackReach
                                            { reach = td
                                            , frac = linearFraction bd pd
                                            }
                                in (flip (,)) tr <$> ps

                    | dBest <- dsBest
                    | ps <- psArriving
                    ]

            let rss :: [[(Pilot, TrackReach)]] =
                    [
                        sortOn
                            ( negate
                            . (\TrackReach{frac = LinearFraction lf} -> lf)
                            . snd
                            )
                        $ xs ++ ys
                    | xs <- rsArrive
                    | ys <- rsNigh
                    ]

            let rssRaw =
                    [ V.fromList
                        [ unQuantity r | (_, TrackReach{reach = TaskDistance r}) <- rs]
                    | rs <- rss
                    ]

            let rsMean :: [QTaskDistance Double [u| m |]] = TaskDistance . MkQuantity . mean <$> rssRaw
            let rsStdDev  :: [QTaskDistance Double [u| m |]] = TaskDistance . MkQuantity . stdDev <$> rssRaw

            let fssRaw =
                    [ V.fromList
                        [ unQuantity $ max r (convert dMin) | (_, TrackReach{reach = TaskDistance r}) <- rs]
                    | rs <- rss
                    ]

            let fsMean :: [QTaskDistance Double [u| m |]] = TaskDistance . MkQuantity . mean <$> fssRaw
            let fsStdDev  :: [QTaskDistance Double [u| m |]] = TaskDistance . MkQuantity . stdDev <$> fssRaw

            writeMasking
                (compToMask compFile)
                Masking
                    { pilotsAtEss = PilotsAtEss . toInteger . length <$> as
                    , raceTime = raceTime
                    , ssBestTime = ssBestTime
                    , gsBestTime = gsBestTime
                    , taskDistance = lsWholeTask
                    , taskSpeedDistance = lsSpeedSubset
                    , bestDistance = dsBest
                    , sumDistance = dsSum
                    , leadAreaToCoef = lcAreaToCoef
                    , leadCoefMin = lcMin
                    , leadRank = lead
                    , arrivalRank = as
                    , flownMean = fsMean
                    , flownStdDev = fsStdDev
                    , reachMean = rsMean
                    , reachStdDev = rsStdDev
                    , reachRank = rss
                    , ssSpeed = fromMaybe [] <$> (fmap . fmap) snd ssVs
                    , gsSpeed = fromMaybe [] <$> (fmap . fmap) snd gsVs
                    , nigh = dsNigh
                    , land = dsLand
                    , altStopped = dsAlt
                    }

awardByFrac
    :: Clamp
    -> QTaskDistance Double [u| m |]
    -> AwardedDistance
    -> Quantity Double [u| m |]
awardByFrac c td a = convert $ Track.awardByFrac c td a

madeAwarded :: QTaskDistance Double [u| m |] -> Land -> TrackDistance Land
madeAwarded (TaskDistance td) d@(TaskDistance d') =
    TrackDistance
        { togo = Just . TaskDistance $ td -: d'
        , made = Just d
        }

includeTask :: [IxTask] -> IxTask -> Bool
includeTask tasks = if null tasks then const True else (`elem` tasks)


landTaskTicked :: [(Pilot, FlightStats k)] -> [(Pilot, _)]
landTaskTicked xs =
    (\(p, FlightStats{..}) -> (p, statDash)) <$> xs

landAltitudes :: [(Pilot, FlightStats k)] -> [(Pilot, QAlt Double [u| m |])]
landAltitudes xs =
    catMaybes
    $ fmap (\(p, FlightStats{..}) -> (p,) <$> statAlt) xs

landDistances :: [(Pilot, FlightStats k)] -> [(Pilot, TrackDistance Land)]
landDistances xs =
    sortOn (togo . snd)
    . catMaybes
    $ fmap (\(p, FlightStats{..}) -> (p,) <$> statLand) xs

arrivals :: [(Pilot, FlightStats k)] -> [(Pilot, TrackArrival)]
arrivals xs =
    sortOn (rank . snd) $ (fmap . fmap) f ys
    where
        ys :: [(Pilot, ArrivalPlacing)]
        ys =
            catMaybes
            $ (\(p, FlightStats{..}) -> (p,) <$> (join $ positionAtEss <$> statTimeRank))
            <$> xs

        pilots :: PilotsAtEss
        pilots = PilotsAtEss . toInteger $ length ys

        f position =
            TrackArrival
                { rank = position
                , frac = arrivalFraction pilots position
                }

times
    :: (TimeStats -> PilotTime (Quantity Double [u| h |]))
    -> [(Pilot, FlightStats k)]
    -> Maybe (BestTime (Quantity Double [u| h |]), [(Pilot, TrackSpeed)])
times f xs =
    (\ bt -> (bt, sortOn (time . snd) $ second (g bt) <$> ys))
    <$> Gap.bestTime' ts
    where
        ys :: [(Pilot, PilotTime (Quantity Double [u| h |]))]
        ys =
            catMaybes
            $ (\(p, FlightStats{..}) -> (p,) . f <$> statTimeRank)
            <$> xs

        ts :: [PilotTime (Quantity Double [u| h |])]
        ts = snd <$> ys

        g best t =
            TrackSpeed
                { time = t
                , frac = speedFraction best t
                }

check
    :: (MonadThrow m, MonadIO m)
    => Math
    -> RoutesLookupTaskDistance
    -> ScoredLookup
    -> Maybe Tagging
    -> CompInputFile
    -> [IxTask]
    -> [Pilot]
    -> m [[Either (Pilot, TrackFileFail) (Pilot, Pilot -> FlightStats k)]]
check math lengths flying tags = checkTracks $ \CompSettings{tasks} ->
    flown math lengths flying tags tasks

flown
    :: Math
    -> RoutesLookupTaskDistance
    -> ScoredLookup
    -> Maybe Tagging
    -> FnIxTask k (Pilot -> FlightStats k)
flown math (RoutesLookupTaskDistance lookupTaskLength) flying tags tasks iTask fixes =
    maybe
        (const nullStats)
        (\d -> flown' d flying math tags tasks iTask fixes)
        taskLength
    where
        taskLength = (fmap wholeTaskDistance . ($ iTask)) =<< lookupTaskLength

flown'
    :: QTaskDistance Double [u| m |]
    -> ScoredLookup
    -> Math
    -> Maybe Tagging
    -> FnIxTask k (Pilot -> FlightStats k)
flown' dTaskF flying math tags tasks iTask@(IxTask i) mf@MarkedFixes{mark0} p =
    case maybeTask of
        Nothing -> nullStats

        Just task' ->
            case (ssTime, gsTime, esTime, arrivalRank) of
                (Just a, Just b, Just e, c@(Just _)) ->
                    tickedStats {statTimeRank = Just $ TimeStats a b e c}

                _ ->
                    tickedStats
                        { statLand = Just $ landDistance task'
                        , statAlt =
                            case reverse ys of
                                [] -> Nothing
                                y : _ -> Just . altToAlt $ altGps y
                        }

    where
        maybeTask = tasks ^? element (i - 1)

        ticked = Lookup.ticked (tagTicked tags) mf iTask speedSection' p
        (_, esTime) = Lookup.pilotEssTime (tagPilotTime tags) mf iTask [] speedSection' p
        ssTime = Lookup.pilotTime (tagPilotTime tags) mf iTask [] speedSection' p
        gsTime = Lookup.pilotTime (tagPilotTime tags) mf iTask startGates' speedSection' p
        arrivalRank = Lookup.arrivalRank (tagArrivalRank tags) mf iTask speedSection' p
        FlyCut{uncut = MarkedFixes{fixes = ys}} = clipToCut xs

        xs =
            FlyCut
                { cut = Lookup.scoredTimeRange flying mark0 iTask p
                , uncut = mf
                }

        tickedStats =
            nullStats
                { statDash =
                    DashPathInputs
                        { dashTask = maybeTask
                        , dashTicked = ticked
                        , dashFlyCut = Just xs
                        }
                }

        landDistance task =
            TrackDistance
                { togo = togoAtLanding math ticked task xs
                , made = madeAtLanding math dTaskF ticked task xs
                }

        startGates' =
            case tasks ^? element (fromIntegral i - 1) of
                Nothing -> []
                Just Task{..} -> startGates

        speedSection' =
            case tasks ^? element (fromIntegral i - 1) of
                Nothing -> Nothing
                Just Task{..} -> speedSection

rankByArrival
    :: [(Pilot, FlightStats _)]
    -> [(Pilot, FlightStats _)]
    -> [(Pilot, FlightStats _)]
rankByArrival xsDf xsDfNt =
    case any isJust yTs of
        False -> xsDf ++ xsDfNt
        True ->
            [ (rankArrival f ii ) <$> y
            | (ii, ys) <-
                        reIndex
                        . zip [1..]
                        . groupBy ((==) `on` (fmap Stats.esMark) . statTimeRank . snd)
                        $ xs
            , let f =
                    if length ys == 1
                        then ArrivalPlacing
                        else (\x -> ArrivalPlacingEqual x (fromIntegral $ length ys))
            , y <- ys
            ]
            ++ xsLandout
    where
        yTs = statTimeRank . snd <$> xsDfNt

        xs :: [(Pilot, FlightStats _)]
        xs =
            sortOn ((fmap Stats.esMark) . statTimeRank . snd)
            $ xsArrived

        (xsArrived, xsLandout) =
            partition (\(_, FlightStats{statTimeRank = r}) -> isJust r)
            $ xsDf ++ xsDfNt

rankArrival :: (Integer -> ArrivalPlacing) -> Integer -> FlightStats _ -> FlightStats _ 
rankArrival _ _ x@FlightStats{statTimeRank = Nothing} = x
rankArrival f ii x@FlightStats{statTimeRank = Just y} =
    x{statTimeRank = Just y{positionAtEss = Just $ f ii}}
