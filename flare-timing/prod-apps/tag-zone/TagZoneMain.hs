{-# OPTIONS_GHC -fplugin Data.UnitsOfMeasure.Plugin #-}

import System.Environment (getProgName)
import System.Console.CmdArgs.Implicit (cmdArgs)
import Formatting ((%), fprint)
import Formatting.Clock (timeSpecs)
import Data.Time.Clock (UTCTime)
import System.Clock (getTime, Clock(Monotonic))
import Data.Maybe (catMaybes, fromMaybe)
import Data.List (transpose, sortOn, sort)
import Control.Monad (mapM_)
import Control.Exception.Safe (catchIO)
import System.FilePath (takeFileName)

import Flight.Cmd.Paths (LenientFile(..), checkPaths)
import Flight.Cmd.Options (ProgramName(..), Extension(..))
import Flight.Cmd.BatchOptions (CmdBatchOptions(..), mkOptions)

import Flight.Zone.Raw (RawZone)
import Flight.Mask (TaskZone, tagZones, zoneToCylinder)
import Flight.Comp
    ( FileType(CompInput)
    , Pilot(..)
    , CompSettings(..)
    , CompInputFile(..)
    , CrossZoneFile(..)
    , Task(..)
    , Zones(..)
    , compToCross
    , crossToTag
    , findCompInput
    , ensureExt
    )
import Flight.Track.Cross
    ( Crossing(..), TrackCross(..), TrackFlyingSection(..)
    , PilotTrackCross(..), InterpolatedFix(..), ZoneTag(..)
    )
import Flight.Track.Tag
    (Tagging(..), TrackTime(..), TrackTag(..), PilotTrackTag(..))
import Flight.Scribe (readComp, readCrossing, writeTagging)
import TagZoneOptions (description)

main :: IO ()
main = do
    name <- getProgName
    options <- cmdArgs $ mkOptions
                            (ProgramName name)
                            description
                            (Just $ Extension "*.comp-input.yaml")

    let lf = LenientFile {coerceFile = ensureExt CompInput}
    err <- checkPaths lf options

    maybe (drive options) putStrLn err

drive :: CmdBatchOptions -> IO ()
drive o = do
    -- SEE: http://chrisdone.com/posts/measuring-duration-in-haskell
    start <- getTime Monotonic
    files <- findCompInput o
    if null files then putStrLn "Couldn't find any input files."
                  else mapM_ go files
    end <- getTime Monotonic
    fprint ("Tagging zones completed in " % timeSpecs % "\n") start end

go :: CompInputFile -> IO ()
go compFile@(CompInputFile compPath) = do
    let crossFile@(CrossZoneFile crossPath) = compToCross compFile
    putStrLn $ "Reading tasks from '" ++ takeFileName compPath ++ "'"
    putStrLn $ "Reading zone crossings from '" ++ takeFileName crossPath ++ "'"

    cs <-
        catchIO
            (Just <$> readComp compFile)
            (const $ return Nothing)

    cgs <-
        catchIO
            (Just <$> readCrossing crossFile)
            (const $ return Nothing)

    case (cs, cgs) of
        (Nothing, _) -> putStrLn "Couldn't read the comp settings."
        (_, Nothing) -> putStrLn "Couldn't read the crossings."
        (Just CompSettings{tasks}, Just Crossing{crossing, flying}) -> do
            let pss :: [[PilotTrackTag]] =
                    [
                        (\case
                            PilotTrackCross p Nothing ->
                                PilotTrackTag p Nothing

                            PilotTrackCross p (Just xs) ->
                                PilotTrackTag p (Just $ flownTag zs' xs))
                        <$> cg

                    | Task{zones = Zones{raw = zs}} <- tasks
                    , let zs' = (zoneToCylinder :: RawZone -> TaskZone Double) <$> zs
                    | cg <- crossing
                    ]

            let tss :: [[Maybe UTCTime]] =
                    (fmap . fmap)
                        (\case
                            (_, Nothing) -> Nothing
                            (_, Just x) -> flownTime x)
                        flying

            let times =
                    [ timed ps ts
                    | ps <- pss
                    | ts <- tss
                    ]

            let tagZone =
                    Tagging { timing = times
                            , tagging = pss
                            }

            writeTagging (crossToTag crossFile) tagZone

timed :: [PilotTrackTag] -> [Maybe UTCTime] -> TrackTime
timed xs ys =
    TrackTime
        { zonesSum = length <$> rankTime
        , zonesFirst = firstTag <$> zs'
        , zonesLast = lastTag <$> zs'
        , zonesRankTime = rankTime
        , zonesRankPilot = (fmap . fmap) fst rs'
        , lastLanding = down
        }
    where
        down =
            case catMaybes ys of
                [] -> Nothing
                ts ->
                    case reverse $ sort ts of
                        [] -> Nothing
                        (t : _) -> Just t

        zs :: [[Maybe UTCTime]]
        zs = fromMaybe [] . tagTimes <$> xs

        zs' :: [[Maybe UTCTime]]
        zs' = transpose zs

        rs :: [[Maybe (Pilot, UTCTime)]]
        rs = transpose $ rankByTag xs

        rs' :: [[(Pilot, UTCTime)]]
        rs' = sortOnTag <$> rs

        rankTime = (fmap . fmap) snd rs'

-- | Rank the pilots tagging each zone in a single task.
rankByTag :: [PilotTrackTag]
          -- ^ The list of pilots flying the task and the zones they tagged.
          -> [[Maybe (Pilot, UTCTime)]]
          -- ^ For each zone in the task, the sorted list of tag ordered pairs of
          -- pilots and their tag times.
rankByTag xs =
    (fmap . fmap) g zss
    where
        -- A list of pilots and maybe their tagged zones.
        ys :: [(Pilot, Maybe [Maybe UTCTime])]
        ys = (\t@(PilotTrackTag p _) -> (p, tagTimes t)) <$> xs

        f :: (Pilot, Maybe [Maybe UTCTime]) -> Maybe [(Pilot, Maybe UTCTime)]
        f (p, ts) = do
            ts' <- ts
            return $ (,) p <$> ts'

        -- For each zone, an unsorted list of pilots.
        zss :: [[(Pilot, Maybe UTCTime)]]
        zss = catMaybes $ f <$> ys

        -- Associate the pilot with each zone.
        g :: (Pilot, Maybe UTCTime) -> Maybe (Pilot, UTCTime)
        g (p, t) = do
            t' <- t
            return (p, t')

sortOnTag :: forall a. [Maybe (a, UTCTime)] -> [(a, UTCTime)]
sortOnTag xs =
    sortOn snd $ catMaybes xs

firstTag :: [Maybe UTCTime] -> Maybe UTCTime
firstTag xs =
    if null ys then Nothing else Just $ minimum ys
    where
        ys = catMaybes xs

lastTag :: [Maybe UTCTime] -> Maybe UTCTime
lastTag xs =
    if null ys then Nothing else Just $ maximum ys
    where
        ys = catMaybes xs

-- | Gets the pilots zone tag times.
tagTimes :: PilotTrackTag -> Maybe [Maybe UTCTime]
tagTimes (PilotTrackTag _ Nothing) = Nothing
tagTimes (PilotTrackTag _ (Just xs)) =
    Just $ fmap (time . inter) <$> zonesTag xs

flownTag :: [TaskZone a] -> TrackCross -> TrackTag
flownTag zs TrackCross{zonesCrossSelected} =
    TrackTag
        { zonesTag = tagZones zs zonesCrossSelected
        }

flownTime :: TrackFlyingSection -> Maybe UTCTime
flownTime TrackFlyingSection{flyingTimes = Nothing} = Nothing
flownTime TrackFlyingSection{flyingTimes = Just (_, t)} = Just t
