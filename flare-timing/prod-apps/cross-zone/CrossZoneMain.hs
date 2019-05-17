{-# OPTIONS_GHC -fplugin Data.UnitsOfMeasure.Plugin #-}

import System.Environment (getProgName)
import System.Console.CmdArgs.Implicit (cmdArgs)
import Formatting ((%), fprint)
import Formatting.Clock (timeSpecs)
import System.Clock (getTime, Clock(Monotonic))
import Data.Maybe (catMaybes, isNothing)
import Data.List (nub, sort)
import Control.Lens ((^?), element)
import Control.Monad (mapM_)
import Control.Exception.Safe (catchIO)
import System.FilePath (takeFileName)

import Flight.Cmd.Paths (LenientFile(..), checkPaths)
import Flight.Cmd.Options (ProgramName(..))
import Flight.Cmd.BatchOptions (CmdBatchOptions(..), mkOptions)
import Flight.Comp
    ( FileType(CompInput)
    , CompInputFile(..)
    , CompSettings(..)
    , PilotName(..)
    , Pilot(..)
    , TrackFileFail(..)
    , IxTask(..)
    , Task(..)
    , Zones
    , compToCross
    , findCompInput
    , ensureExt
    , pilotNamed
    )
import Flight.Units ()
import Flight.Track.Cross
    (TrackFlyingSection(..)
    , TrackCross(..)
    , PilotTrackCross(..)
    , Crossing(..)
    , StopWindow(..)
    , trackLogErrors
    )
import Flight.LatLng.Rational (defEps)
import qualified Flight.Earth.Sphere.PointToPoint.Rational as Rat
    (azimuthFwd, distanceHaversine)
import qualified Flight.Earth.Sphere.PointToPoint.Double as Dbl
    (azimuthFwd, distanceHaversine)
import Flight.Mask
    ( TaskZone
    , FnIxTask
    , FnTask
    , MadeZones(..)
    , SelectedCrossings(..)
    , NomineeCrossings(..)
    , unSelectedCrossings
    , unNomineeCrossings
    , checkTracks
    , madeZones
    , zonesToTaskZones
    , nullFlying
    )
import Flight.Scribe (readComp, writeCrossing)
import CrossZoneOptions (description)
import Flight.Span.Math (Math(..))

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
    fprint ("Tracks crossing zones completed in " % timeSpecs % "\n") start end

go :: CmdBatchOptions -> CompInputFile -> IO ()
go co@CmdBatchOptions{pilot, task} compFile@(CompInputFile compPath) = do
    putStrLn $ "Reading competition from '" ++ takeFileName compPath ++ "'"

    compSettings <-
        catchIO
            (Just <$> readComp compFile)
            (const $ return Nothing)

    case compSettings of
        Nothing -> putStrLn "Couldn't read the comp settings."
        Just cs@CompSettings{tasks} -> do
            let ixs = IxTask <$> task
            let ps = pilotNamed cs $ PilotName <$> pilot
            tracks <-
                catchIO
                    (Just <$> (checkAll $ math co) compFile ixs ps)
                    (const $ return Nothing)

            case tracks of
                Nothing -> putStrLn "Unable to read tracks for pilots."
                Just ts -> writeCrossings compFile tasks ts

writeCrossings
    :: CompInputFile
    -> [Task k]
    -> [[Either (Pilot, TrackFileFail) (Pilot, MadeZones)]]
    -> IO ()
writeCrossings compFile tasks xs = do
    let ys :: [([(Pilot, Maybe MadeZones)], [Maybe (Pilot, TrackFileFail)])] =
            unzip <$>
            (fmap . fmap)
                (\case
                    Left err@(p, _) ->
                        ((p, Nothing), Just err)

                    Right (p, x) ->
                        ((p, Just x), Nothing))
                xs

    let pss = fst <$> ys
    let ess = catMaybes . snd <$> ys

    let pErrs :: [[Pilot]] =
            [ fst <$> filter ((/= TrackLogFileNotSet) . snd) es
            | es <- ess
            ]

    let stopWindows :: [Maybe StopWindow] =
            const Nothing <$> tasks

    let flying = (fmap . fmap . fmap . fmap) madeZonesToFlying pss

    let notFlys :: [[Pilot]] =
            [ fmap fst . filter snd
              $ (fmap . fmap) (maybe False (not . flew)) fs
            | fs <- flying
            ]

    let dnfs =
            [ sort . nub $ es ++ ns
            | es <- pErrs
            | ns <- notFlys
            ]

    let crossZone =
            Crossing
                { suspectDnf = dnfs
                , stopWindow = stopWindows
                , flying = flying
                , crossing = (fmap . fmap) crossings pss
                , trackLogError = trackLogErrors <$> ess
                }

    writeCrossing (compToCross compFile) crossZone

madeZonesToCross :: MadeZones -> TrackCross
madeZonesToCross x =
    TrackCross
        { zonesCrossSelected = unSelectedCrossings . selectedCrossings $ x
        , zonesCrossNominees = unNomineeCrossings . nomineeCrossings $ x
        }

crossings :: (Pilot, Maybe MadeZones) -> PilotTrackCross
crossings (p, x) =
    PilotTrackCross p $ madeZonesToCross <$> x

flew :: TrackFlyingSection -> Bool
flew TrackFlyingSection{flyingFixes, flyingSeconds}
    | isNothing flyingFixes = False
    | isNothing flyingSeconds = False
    | otherwise = f flyingFixes || f flyingSeconds
    where
        f :: Ord a => Maybe (a, a) -> Bool
        f Nothing = False
        f (Just (a, b)) = a < b

madeZonesToFlying :: MadeZones -> TrackFlyingSection
madeZonesToFlying MadeZones{flying} = flying

checkAll
    :: Math
    -> CompInputFile
    -> [IxTask]
    -> [Pilot]
    -> IO [[Either (Pilot, TrackFileFail) (Pilot, MadeZones)]]
checkAll math =
    checkTracks $ \CompSettings{tasks} -> flown math tasks

flown :: Math -> FnIxTask k MadeZones
flown math tasks (IxTask i) fs =
    case tasks ^? element (i - 1) of
        Nothing ->
            MadeZones
                { flying = nullFlying
                , selectedCrossings = SelectedCrossings []
                , nomineeCrossings = NomineeCrossings []
                }

        Just task ->
            flownTask math task fs

flownTask :: Math -> FnTask k MadeZones
flownTask =
    \case
        Rational ->
            let az = Rat.azimuthFwd defEps in
            madeZones
                az
                (Rat.distanceHaversine defEps)
                (zonesToTaskZones az :: Zones -> [TaskZone Rational])
        Floating ->
            let az = Dbl.azimuthFwd in
            madeZones
                az
                Dbl.distanceHaversine
                (zonesToTaskZones az :: Zones -> [TaskZone Double])
