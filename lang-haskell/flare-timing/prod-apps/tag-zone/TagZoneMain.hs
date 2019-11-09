{-# OPTIONS_GHC -fplugin Data.UnitsOfMeasure.Plugin #-}

import System.Environment (getProgName)
import System.Console.CmdArgs.Implicit (cmdArgs)
import Formatting ((%), fprint)
import Formatting.Clock (timeSpecs)
import System.Clock (getTime, Clock(Monotonic))
import Control.Monad (mapM_)
import Control.Exception.Safe (catchIO)
import System.FilePath (takeFileName)

import Flight.Cmd.Paths (LenientFile(..), checkPaths)
import Flight.Cmd.Options (ProgramName(..), Extension(..))
import Flight.Cmd.BatchOptions (CmdBatchOptions(..), mkOptions)

import Flight.Earth.Ellipsoid (wgs84)
import Flight.Earth.Sphere (earthRadius)
import Flight.Geodesy (EarthMath(..), EarthModel(..), Projection(..))
import Flight.Mask (TaskZone, GeoTag(..), GeoSliver(..))
import Flight.Comp
    ( FileType(CompInput)
    , CompSettings(..)
    , CompInputFile(..)
    , CrossZoneFile(..)
    , Comp(..)
    , Task(..)
    , compToCross
    , crossToTag
    , findCompInput
    , ensureExt
    )
import Flight.Track.Cross
    (Crossing(..), TrackCross(..), PilotTrackCross(..), endOfFlying)
import Flight.Track.Tag
    ( Tagging(..), TrackTag(..), PilotTrackTag(..)
    , timed
    )
import Flight.Scribe (readComp, readCrossing, writeTagging)
import TagZoneOptions (description)
import Flight.Span.Math (Math(..))

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
drive o@CmdBatchOptions{math} = do
    -- SEE: http://chrisdone.com/posts/measuring-duration-in-haskell
    start <- getTime Monotonic
    files <- findCompInput o
    if null files then putStrLn "Couldn't find any input files."
                  else mapM_ (go math) files
    end <- getTime Monotonic
    fprint ("Tagging zones completed in " % timeSpecs % "\n") start end

go :: Math -> CompInputFile -> IO ()
go math compFile@(CompInputFile compPath) = do
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
        (Nothing, _) ->
            putStrLn "Couldn't read the comp settings."

        (_, Nothing) ->
            putStrLn "Couldn't read the crossings."

        (Just CompSettings{tasks, comp = Comp{earthMath}}, Just Crossing{crossing, flying}) -> do
            let pss :: [[PilotTrackTag]] =
                    [
                        (\case
                            PilotTrackCross p Nothing ->
                                PilotTrackTag p Nothing

                            PilotTrackCross p (Just xs) ->
                                PilotTrackTag p (Just $ flownTag math earthMath zs xs))
                        <$> cg

                    | Task{zones} <- tasks

                    , let zs =
                              fromZones @Double @Double
                                  ( earthMath
                                  , let e = EarthAsEllipsoid wgs84 in case earthMath of
                                        Pythagorus -> EarthAsFlat UTM
                                        Haversines -> EarthAsSphere earthRadius
                                        Vincenty -> e
                                        AndoyerLambert -> e
                                        ForsytheAndoyerLambert -> e
                                        FsAndoyer -> e
                                  )
                                  zones

                    | cg <- crossing
                    ]

            let times =
                    [ timed ps fs
                    | ps <- pss
                    | fs <- fmap (endOfFlying . snd) <$> flying
                    ]

            let tagZone = Tagging{timing = times, tagging = pss}

            writeTagging (crossToTag crossFile) tagZone

flownTag
    :: Math
    -> EarthMath
    -> [TaskZone Double]
    -> TrackCross
    -> TrackTag
flownTag Floating earthMath zs TrackCross{zonesCrossSelected} =
    TrackTag
        { zonesTag =
            tagZones @Double @Double
                ( earthMath
                , let e = EarthAsEllipsoid wgs84 in case earthMath of
                      Pythagorus -> EarthAsFlat UTM
                      Haversines -> EarthAsSphere earthRadius
                      Vincenty -> e
                      AndoyerLambert -> e
                      ForsytheAndoyerLambert -> e
                      FsAndoyer -> e
                )
                zs
                zonesCrossSelected
        }
flownTag Rational _ _ _ = error "Flown tag not yet implemented for rational math."