{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Driver (driverMain) where

import Control.Monad (mapM_)
import Args (withCmdArgs)
import System.Directory (doesFileExist, doesDirectoryExist)
import System.FilePath (takeFileName)
import System.FilePath.Find (FileType(..), find, always, fileType, (==?))
import Options (DriveOptions(..))

drive :: DriveOptions -> IO ()
drive DriveOptions{..} = do
    dfe <- doesFileExist file
    if dfe then
        go file
    else do
        dde <- doesDirectoryExist dir
        if dde then do
            files <- find always (fileType ==? RegularFile) dir
            mapM_ go files
        else
            putStrLn "Couldn't find any IGC input files."
    where
        go path = do
            putStrLn $ takeFileName path

driverMain :: IO ()
driverMain = withCmdArgs drive
