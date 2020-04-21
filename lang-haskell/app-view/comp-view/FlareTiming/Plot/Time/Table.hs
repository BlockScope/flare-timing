{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

module FlareTiming.Plot.Time.Table (tableSpeed) where

import Reflex.Dom
import qualified Data.Text as T (Text)
import Data.Map (Map)
import qualified Data.Map.Strict as Map

import qualified WireTypes.Fraction as Frac (Fractions(..))
import WireTypes.Fraction (showSpeedFrac, showSpeedFracDiff)
import qualified WireTypes.Point as Norm (NormBreakdown(..))
import WireTypes.Speed (TrackSpeed(..), PilotTime(..))
import qualified WireTypes.Speed as Speed (TrackSpeed(..))
import WireTypes.Pilot (Pilot(..), pilotIdsWidth)
import WireTypes.Point (StartGate)
import FlareTiming.Pilot (showPilot, hashIdHyphenPilot)
import FlareTiming.Time (showHmsForHours, showHours)
import FlareTiming.Task.Score.Show (showPilotTime, showPilotTimeDiff)

tableSpeed
    :: MonadWidget t m
    => Dynamic t [StartGate]
    -> Dynamic t [(Pilot, Norm.NormBreakdown)]
    -> Dynamic t [(Pilot, TrackSpeed)]
    -> Dynamic t [Pilot]
    -> m (Event t Pilot)
tableSpeed sgs sEx xs select = do
    let w = ffor xs (pilotIdsWidth . fmap fst)
    ev :: Event _ (Event _ Pilot) <- elClass "table" "table is-striped" $ do
            el "thead" $ do
                el "tr" $ do
                    elAttr "th" ("colspan" =: "2")
                        $ text ""
                    elAttr "th" ("colspan" =: "2" <> "class" =: "th-norm time-or-pace") . dynText
                        $ ffor sgs (\case [] -> "Pace"; _ -> "Time")
                    elAttr "th" ("colspan" =: "3" <> "class" =: "th-time-frac")
                        $ text "Fraction"

                    el "th" $ text ""

                el "tr" $ do
                    el "th" $ text "H.hhh"
                    el "th" $ text "HH:MM:SS"
                    elClass "th" "th-norm th-norm-pace" $ text "✓"
                    elClass "th" "th-norm th-time-diff" $ text "Δ"

                    el "th" $ text ""
                    elClass "th" "th-norm" $ text "✓"
                    elClass "th" "th-norm" $ text "Δ"
                    el "th" . dynText $ ffor w hashIdHyphenPilot

                    return ()

            ev <- dyn $ ffor sEx (\sEx' -> do
                    let mapN = Map.fromList sEx'

                    ePilots <- el "tbody" $
                        simpleList xs (uncurry (rowSpeed w select mapN) . splitDynPure)
                    let ePilot' = switchDyn $ leftmost <$> ePilots
                    return ePilot')

            return ev
    ePilot <- switchHold never ev
    return ePilot

rowSpeed
    :: MonadWidget t m
    => Dynamic t Int
    -> Dynamic t [Pilot]
    -> Map Pilot Norm.NormBreakdown
    -> Dynamic t Pilot
    -> Dynamic t TrackSpeed
    -> m (Event t Pilot)
rowSpeed w select mapN p ts = do
    pilot <- sample $ current p
    let rowClass = ffor2 p select (\p' ps -> if p' `elem` ps then "is-selected" else "")

    (yTime, yTimeDiff, yFrac, yFracDiff) <- sample . current
                $ ffor2 p ts (\p' TrackSpeed{time, frac} ->
                    case Map.lookup p' mapN of
                        Just
                            Norm.NormBreakdown
                                { timeElapsed = timeN
                                , fractions = Frac.Fractions{time = fracN}
                                } ->
                            ( showPilotTime time
                            , maybe "" (flip showPilotTimeDiff time) timeN

                            , showSpeedFrac fracN
                            , showSpeedFracDiff fracN frac
                            )

                        _ -> ("", "", "", ""))

    (eRow, _) <- elDynClass' "tr" rowClass $ do
        el "td" . dynText $ showHr . Speed.time <$> ts
        el "td" . dynText $ showHms . Speed.time <$> ts
        elClass "td" "td-norm td-norm-pace" . text $ yTime
        elClass "td" "td-norm td-time-diff" . text $ yTimeDiff
        el "td" . dynText $ showSpeedFrac . frac <$> ts
        elClass "td" "td-norm" . text $ yFrac
        elClass "td" "td-norm" . text $ yFracDiff
        el "td" . dynText $ ffor2 w p showPilot

        return ()

    let ePilot = const pilot <$> domEvent Click eRow
    return ePilot

showHr :: PilotTime -> T.Text
showHr (PilotTime x) = showHours x

showHms :: PilotTime -> T.Text
showHms (PilotTime x) = showHmsForHours x