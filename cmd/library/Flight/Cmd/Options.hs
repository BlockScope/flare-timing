{-# LANGUAGE DeriveDataTypeable #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Flight.Cmd.Options
    ( CmdOptions(..)
    , ProgramName(..)
    , Description(..)
    , Extension(..)
    , mkOptions
    ) where

import Data.Maybe (fromMaybe)
import System.Console.CmdArgs.Implicit
    ( Data
    , Typeable
    , Default(def)
    , summary
    , program
    , groupname
    , typ
    , opt
    , help
    , (&=)
    )
-- | Options passed in on the command line.
data CmdOptions
    = CmdOptions { dir :: FilePath
                 -- ^ Picking all competition in this directory.
                 , file :: FilePath
                 -- ^ Picking the competition in this file.
                 , task :: [Int]
                 -- ^ Include only these tasks.
                 , pilot :: [String]
                 -- ^ Look only at these pilots
                 }
                 deriving (Data, Typeable, Show)

newtype ProgramName = ProgramName String
newtype Description = Description String
newtype Extension = Extension String

mkOptions :: ProgramName -> Description -> Maybe Extension -> CmdOptions
mkOptions (ProgramName programName) (Description description) ext =
    CmdOptions
        { dir = def
        &= help dirMsg
        &= groupname "Source"

        , file = def
        &= help fileMsg
        &= groupname "Source"

        , task = def
        &= help "Which tasks?"
        &= typ "TASK NUMBER"
        &= opt "name"
        &= groupname "Filter"

        , pilot = def
        &= help "Which pilots?"
        &= typ "PILOT NAME"
        &= opt "name"
        &= groupname "Filter"
        }
        &= summary description
        &= program programName
    where
        Extension ext' = fromMaybe (Extension "*.comp.yaml") ext
        dirMsg =  "Over all " ++ ext' ++ " files in this directory"
        fileMsg = "With this one competition " ++ ext' ++ " file"
