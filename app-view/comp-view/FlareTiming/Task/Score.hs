module FlareTiming.Task.Score (tableScore) where

import Prelude hiding (min)
import Reflex.Dom
import qualified Data.Text as T (Text, pack, unpack, breakOn)
import Text.Printf (printf)
import Data.Time.Clock (UTCTime)
import Data.Time.Format (formatTime, defaultTimeLocale)
import Data.Time.LocalTime (TimeZone, minutesToTimeZone, utcToLocalTime)

import WireTypes.Track.Point
    ( Points(..)
    , TaskPoints(..)
    , Breakdown(..)
    , Velocity(..)
    , PilotDistance(..)
    , PilotTime(..)
    , PilotVelocity(..)
    , showDistancePoints
    , showArrivalPoints
    , showLeadingPoints
    , showTimePoints
    )
import WireTypes.Comp (UtcOffset(..))
import WireTypes.Pilot (Pilot(..))
import FlareTiming.Pilot (showPilotId, showPilotName)

tableScore
    :: MonadWidget t m
    => Dynamic t UtcOffset
    -> Dynamic t [(Pilot, Breakdown)]
    -> m ()
tableScore utcOffset xs = do
    let classR = "class" =: "has-text-right"
    let thR = elClass "th" "has-text-right" . text
    let thU = elClass "th" "has-text-right has-text-grey-light" . text
    let th = el "th" . text

    _ <- elClass "table" "table is-narrow is-fullwidth" $
            el "thead" $ do
                el "tr" $ do
                    elAttr "th" (classR <> "rowspan" =: "3") $ text "Id"
                    elAttr "th" ("rowspan" =: "3") $ text "Pilot"
                    elAttr "th" ("colspan" =: "5" ) $ text "Velocity"
                    elAttr "th" ("colspan" =: "5") $ text "Points"
                el "tr" $ do
                    th "SS"
                    th "ES"
                    thR "Time"
                    thR "Velocity"
                    thR "Distance"
                    thR "Distance"
                    thR "Lead"
                    thR "Time"
                    thR "Arrival"
                    thR "Total"
                el "tr" $ do
                    elAttr "th" ("colspan" =: "2") $ text ""
                    thU "HH:MM:SS"
                    thU "km / h"
                    thU "km"
                    elAttr "th" ("colspan" =: "5") $ text ""
                simpleList xs (row utcOffset)

    return ()

row
    :: MonadWidget t m
    => Dynamic t UtcOffset
    -> Dynamic t (Pilot, Breakdown)
    -> m ()
row utcOffset x = do
    let tz = timeZone <$> utcOffset
    let pilot = fst <$> x
    let b = snd <$> x
    let points = breakdown . snd <$> x
    let v = velocity . snd <$> x

    let td = el "td" . dynText
    let tdR = elClass "td" "has-text-right" . dynText

    el "tr" $ do
        tdR $ showPilotId <$> pilot
        td $ showPilotName <$> pilot
        tdR $ zipDynWith showSs tz v
        tdR $ zipDynWith showEs tz v
        tdR $ showVelocityTime <$> v
        tdR $ showVelocityVelocity <$> v
        tdR $ showVelocityDistance <$> v
        tdR $ showDistancePoints . (\Points{distance = d} -> d) <$> points
        tdR $ showLeadingPoints . leading <$> points
        tdR $ showTimePoints . time <$> points
        tdR $ showArrivalPoints . arrival <$> points
        elClass "td" "has-text-right has-text-weight-bold" . dynText $
            showTotal . total <$> b

showTotal :: TaskPoints -> T.Text
showTotal (TaskPoints p) = T.pack . show $ (truncate p :: Integer)

showSs :: TimeZone -> Velocity -> T.Text
showSs tz Velocity{ss = Just t} = showT tz t
showSs _ _ = ""

showEs :: TimeZone -> Velocity -> T.Text
showEs tz Velocity{es = Just t} = showT tz t
showEs _ _ = ""

showVelocityTime :: Velocity -> T.Text
showVelocityTime Velocity{gsElapsed = Just (PilotTime t)} =
    T.pack $ show2i hr' ++ ":" ++ show2i min' ++ ":" ++ show2i sec'
    where
        hrStr = T.unpack . fst . T.breakOn " h" . T.pack $ t
        hr = read hrStr :: Double
        sec = round $ 3600 * hr
        (hr', min) = sec `divMod` 3600
        (min', sec') = min `divMod` 60

showVelocityTime _ = ""

showVelocityVelocity :: Velocity -> T.Text
showVelocityVelocity Velocity{gsVelocity = Just (PilotVelocity v)} =
    fst . T.breakOn " km / h" . T.pack $ v
showVelocityVelocity _ = ""

showVelocityDistance :: Velocity -> T.Text
showVelocityDistance Velocity{distance = Just (PilotDistance d)} =
    fst . T.breakOn " km" . T.pack $ d
showVelocityDistance _ = ""

show2i :: Integer -> String
show2i = printf "%02d"

showT :: TimeZone -> UTCTime -> T.Text
showT tz = 
    T.pack
    . formatTime defaultTimeLocale "%T"
    . utcToLocalTime tz

timeZone :: UtcOffset -> TimeZone
timeZone UtcOffset{timeZoneMinutes = tzMins} = minutesToTimeZone tzMins
