{-# LANGUAGE DeriveGeneric #-}

{-|
Module      : Data.Flight.Comp
Copyright   : (c) Block Scope Limited 2017
License     : BSD3
Maintainer  : phil.dejoux@blockscope.com
Stability   : experimental

Data for competitions, competitors and tasks.
-}
module Data.Flight.Comp
    ( Comp(..)
    , Nominal(..)
    , Task(..)
    , module Data.Flight.LatLng
    , module Data.Flight.Zone
    , SpeedSection
    , showTask
    ) where

import GHC.Generics (Generic)
import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.List (intercalate)

import Data.Flight.LatLng
import Data.Flight.Zone

type SpeedSection = Maybe (Integer, Integer)

data Comp = Comp { civilId :: String
                 , compName :: String 
                 , location :: String 
                 , from :: String 
                 , to :: String 
                 , utcOffset :: String 
                 } deriving (Show, Generic)

instance ToJSON Comp
instance FromJSON Comp

data Nominal = Nominal { distance :: String
                       , time :: String 
                       , goal :: String 
                       } deriving (Show, Generic)

instance ToJSON Nominal
instance FromJSON Nominal

data Task =
    Task { taskName :: String
         , speedSection :: SpeedSection
         , zones :: [Zone]
         } deriving (Eq, Show, Generic)

instance ToJSON Task
instance FromJSON Task

showTask :: Task -> String
showTask (Task name ss xs) =
    unwords [ "Task"
            , name
            , show ss
            , intercalate ", " $ showZone <$> xs
            ]
