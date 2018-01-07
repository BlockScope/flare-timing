{-# LANGUAGE OverloadedStrings #-}

module Igc.Driver (driverMain) where

import System.Environment (getProgName)
import System.Console.CmdArgs.Implicit (cmdArgs)
import Control.Monad (mapM_)
import System.FilePath (takeFileName)

import Flight.Cmd.Paths (checkPaths)
import Igc.Options (IgcOptions(..), mkOptions)
import Flight.Igc (parseFromFile)
import Flight.Comp (IgcFile(..), findIgc)

driverMain :: IO ()
driverMain = do
    name <- getProgName
    options <- cmdArgs $ mkOptions name
    err <- checkPaths options
    maybe (drive options) putStrLn err

drive :: IgcOptions -> IO ()
drive o = do
    files <- findIgc o
    if null files then putStrLn "Couldn't find any input files."
                  else mapM_ go files

go :: IgcFile -> IO ()
go (IgcFile path) = do
    putStrLn $ takeFileName path
    p <- parseFromFile path
    either print print p
