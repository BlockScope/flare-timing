{-# LANGUAGE DeriveGeneric #-}

{-|
Module      : Data.Flight.TrackZone
Copyright   : (c) Block Scope Limited 2017
License     : BSD3
Maintainer  : phil.dejoux@blockscope.com
Stability   : experimental

Intersection of pilot tracks with competition zones.
-}
module Data.Flight.TrackZone
    ( -- * Track Zone Intersection
      TaskTracks(..)
    , PilotTracks(..)
    , TaskTrack(..)
    , TrackLine(..)
    , LatLng(..)
    , FlownTrack(..)
    , PilotFlownTrack(..)
    ) where

import GHC.Generics (Generic)
import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.Flight.LatLng (Latitude(..), Longitude(..))
import Data.Flight.Pilot (Pilot(..))

data TaskTracks =
    TaskTracks { taskTracks :: [TaskTrack] } deriving (Show, Generic)

instance ToJSON TaskTracks
instance FromJSON TaskTracks

data PilotTracks =
    PilotTracks { pilotTracks :: [[PilotFlownTrack]] } deriving (Show, Generic)

instance ToJSON PilotTracks
instance FromJSON PilotTracks

data TaskTrack
    = TaskTrack { pointToPoint :: Maybe TrackLine
                , edgeToEdge :: Maybe TrackLine
                }
    deriving (Show, Generic)

instance ToJSON TaskTrack
instance FromJSON TaskTrack

data TrackLine =
    TrackLine { distance :: Double
              , waypoints :: [LatLng]
              , legs :: [Double]
              } deriving (Show, Generic)

instance ToJSON TrackLine
instance FromJSON TrackLine

data LatLng =
    LatLng { lat :: Latitude
           , lng :: Longitude
           } deriving (Eq, Show, Generic)

instance ToJSON LatLng
instance FromJSON LatLng

data FlownTrack =
    FlownTrack { launched :: Bool
               , madeGoal :: Bool
               , zonesMade :: [Bool]
               , timeToGoal :: Maybe Double
               , distanceToGoal :: Maybe Double
               , bestDistance :: Maybe Double
               } deriving (Show, Generic)

instance ToJSON FlownTrack
instance FromJSON FlownTrack

data PilotFlownTrack =
    PilotFlownTrack Pilot (Maybe FlownTrack)
    deriving (Show, Generic)

instance ToJSON PilotFlownTrack
instance FromJSON PilotFlownTrack
