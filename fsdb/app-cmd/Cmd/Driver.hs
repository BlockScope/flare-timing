{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Cmd.Driver (driverMain) where

import Control.Monad (mapM_)
import System.Directory (doesFileExist, doesDirectoryExist)
import System.FilePath (takeFileName)
import System.FilePath.Find (FileType(..), (==?), (&&?), find, always, fileType, extension)

import Cmd.Args (withCmdArgs)
import Cmd.Options (CmdOptions(..), Detail(..))
import qualified Data.Flight.Nominal as N (parse)
import qualified Data.Flight.Waypoint as W (parse)

driverMain :: IO ()
driverMain = withCmdArgs drive

drive :: CmdOptions -> IO ()
drive CmdOptions{..} = do
    dfe <- doesFileExist file
    if dfe then
        go file
    else do
        dde <- doesDirectoryExist dir
        if dde then do
            files <- find always (fileType ==? RegularFile &&? extension ==? ".fsdb") dir
            mapM_ go files
        else
            putStrLn "Couldn't find any flight score competition database input files."
    where
        go path = do
            putStrLn $ takeFileName path
            contents <- readFile path
            let contents' = dropWhile (/= '<') contents

            if null detail || Nominals `elem` detail
                then do
                    nominal <- N.parse contents'
                    case nominal of
                         Left msg -> print msg
                         Right nominal' -> print nominal'
                else
                   return ()

            if null detail || Tasks `elem` detail
               then do
                    tasks <- W.parse contents'
                    case tasks of
                         Left msg -> print msg
                         Right tasks' -> print tasks'
               else
                   return ()
