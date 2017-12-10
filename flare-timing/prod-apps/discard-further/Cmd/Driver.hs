{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE PartialTypeSignatures #-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DuplicateRecordFields #-}

{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

module Cmd.Driver (driverMain) where

import System.Environment (getProgName)
import System.Console.CmdArgs.Implicit (cmdArgs)
import Formatting ((%), fprint)
import Formatting.Clock (timeSpecs)
import System.Clock (getTime, Clock(Monotonic))
import Control.Monad (mapM_, when, zipWithM_)
import Control.Monad.Except (ExceptT, runExceptT)
import System.Directory (doesFileExist, doesDirectoryExist, createDirectoryIfMissing)
import System.FilePath.Find
    (FileType(..), (==?), (&&?), find, always, fileType, extension)
import System.FilePath ((</>), takeFileName)
import Data.Vector (Vector)
import qualified Data.Vector as V (fromList, toList)

import Flight.Cmd.Paths (checkPaths)
import Flight.Cmd.Options (CmdOptions(..), ProgramName(..), mkOptions)
import Cmd.Options (description)
import Cmd.Inputs (readTimeRowsFromCsv)
import Cmd.Outputs (writeTimeRowsToCsv)

import Flight.Comp
    ( DiscardDir(..)
    , AlignDir(..)
    , CompFile(..)
    , AlignFile(..)
    , DiscardFile(..)
    , CompSettings(..)
    , Pilot(..)
    , TrackFileFail
    , compFileToCompDir
    , discardDir
    , alignPath
    )
import Flight.TrackLog (IxTask(..))
import Flight.Units ()
import Flight.Mask (checkTracks)
import Flight.Track.Time (TimeRow(..), TickRow(..), discardFurther)

headers :: [String]
headers = ["tick", "distance"]

driverMain :: IO ()
driverMain = do
    name <- getProgName
    options <- cmdArgs $ mkOptions (ProgramName name) description Nothing
    err <- checkPaths options
    case err of
        Just msg -> putStrLn msg
        Nothing -> drive options

drive :: CmdOptions -> IO ()
drive CmdOptions{..} = do
    -- SEE: http://chrisdone.com/posts/measuring-duration-in-haskell
    start <- getTime Monotonic
    dfe <- doesFileExist file
    if dfe then
        withFile (CompFile file)
    else do
        dde <- doesDirectoryExist dir
        if dde then do
            files <- find always (fileType ==? RegularFile &&? extension ==? ".comp-inputs.yaml") dir
            mapM_ withFile (CompFile <$> files)
        else
            putStrLn "Couldn't find any flight score competition yaml input files."
    end <- getTime Monotonic
    fprint ("Filtering times completed in " % timeSpecs % "\n") start end
    where
        withFile compFile@(CompFile compPath) = do
            putStrLn $ "Reading competition from '" ++ takeFileName compPath ++ "'"
            filterTime
                compFile
                (IxTask <$> task)
                (Pilot <$> pilot)
                checkAll

filterTime :: CompFile
           -> [IxTask]
           -> [Pilot]
           -> (CompFile
               -> [IxTask]
               -> [Pilot]
               -> ExceptT String IO [[Either (Pilot, _) (Pilot, _)]])
           -> IO ()
filterTime compFile selectTasks selectPilots f = do
    checks <- runExceptT $ f compFile selectTasks selectPilots

    case checks of
        Left msg -> print msg
        Right xs -> do
            let ys :: [[Pilot]] =
                    (fmap . fmap)
                        (\case
                            Left (p, _) -> p
                            Right (p, _) -> p)
                        xs

            _ <- zipWithM_
                (\ n zs ->
                    when (includeTask selectTasks $ IxTask n) $
                        mapM_ (readFilterWrite compFile n) zs)
                [1 .. ]
                ys

            return ()

checkAll :: CompFile
         -> [IxTask]
         -> [Pilot]
         -> ExceptT
             String
             IO
             [
                 [Either (Pilot, TrackFileFail) (Pilot, ())
                 ]
             ]
checkAll = checkTracks $ \CompSettings{tasks} -> (\ _ _ _ -> ()) tasks

includeTask :: [IxTask] -> IxTask -> Bool
includeTask tasks = if null tasks then const True else (`elem` tasks)

readFilterWrite :: CompFile -> Int -> Pilot -> IO ()
readFilterWrite compFile iTask pilot = do
    _ <- createDirectoryIfMissing True dOut
    rows <- runExceptT $ readTimeRowsFromCsv (AlignFile (dIn </> f))
    case rows of
        Left msg ->
            print msg

        Right (_, xs) ->
            writeTimeRowsToCsv (DiscardFile $ dOut </> f) headers $ discard xs
    where
        dir = compFileToCompDir compFile
        (AlignDir dIn, AlignFile f) = alignPath dir iTask pilot
        (DiscardDir dOut) = discardDir dir iTask

timeToTick :: TimeRow -> TickRow
timeToTick TimeRow{tick, distance} = TickRow tick distance

discard :: Vector TimeRow -> Vector TickRow
discard xs =
    V.fromList . discardFurther . dropZeros . V.toList $ timeToTick <$> xs

dropZeros :: [TickRow] -> [TickRow]
dropZeros =
    dropWhile ((== 0) . d)
    where
        d = distance :: (TickRow -> Double)
