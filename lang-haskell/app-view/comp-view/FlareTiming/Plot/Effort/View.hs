{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

module FlareTiming.Plot.Effort.View (effortPlot) where

import Reflex.Dom
import Data.List (find)
import Data.Maybe (catMaybes)
import Control.Monad.IO.Class (MonadIO(..), liftIO)
import qualified FlareTiming.Plot.Effort.Plot as P (effortPlot)

import WireTypes.Fraction (EffortFraction(..))
import WireTypes.Effort (TrackEffort(..))
import WireTypes.Point (PilotDistance(..))
import qualified WireTypes.Point as Norm (NormBreakdown(..))
import WireTypes.Pilot (Pilot(..), nullPilot, pilotIdsWidth)
import FlareTiming.Pilot (hashIdHyphenPilot)
import FlareTiming.Plot.Effort.Table (tableEffort)
import FlareTiming.Plot.Event (mkLegend, legendClasses, numLegendPilots, selectPilots)

placings :: [TrackEffort] -> [[Double]]
placings = fmap xy

xy :: TrackEffort -> [Double]
xy TrackEffort{effort = PilotDistance x, frac = EffortFraction y} =
    [x, y]

timeRange :: [TrackEffort] -> (Double, Double)
timeRange xs =
    (minimum ys, maximum ys)
    where
        ys = (\TrackEffort{effort = PilotDistance x} -> x) <$> xs

effortPlot
    :: MonadWidget t m
    => Dynamic t [(Pilot, Norm.NormBreakdown)]
    -> Dynamic t [(Pilot, TrackEffort)]
    -> m ()
effortPlot sEx xs = do
    let w = ffor xs (pilotIdsWidth . fmap fst)

    elClass "div" "tile is-ancestor" $ mdo
        elClass "div" "tile" $
            elClass "div" "tile is-parent is-vertical" $
                elClass "div" "tile is-child" $ do
                    let dMsgClass = ffor dPilot (\p -> "message is-primary" <> if p == nullPilot then "" else " is-hidden")

                    _ <- elDynClass "article" dMsgClass $ do
                            elClass "div" "message-header" $ do
                                el "p" $ text "Plot Instructions"
                            elClass "div" "message-body" $
                                text "Tap a row to highlight that pilot's point on the plot."

                            return ()

                    (elPlot, _) <- elAttr' "div" (("id" =: "hg-plot-effort") <> ("style" =: "height: 640px;width: 700px")) $ return ()
                    performEvent_ $ ffor eRedraw (\ps -> liftIO $ do
                        let efforts = snd . unzip $ ys
                        let efforts' =
                                snd . unzip . catMaybes $
                                [ find (\(Pilot (qid, _), _) -> pid == qid) ys
                                | Pilot (pid, _) <- ps
                                ]

                        _ <- P.effortPlot (_element_raw elPlot) (timeRange efforts) (placings efforts) (placings efforts')
                        return ())

                    let dTableClass = ffor dPilot (\p -> "legend table" <> if p == nullPilot then " is-hidden" else "")
                    elAttr "div" ("id" =: "legend-effort" <> "class" =: "level") $
                            elClass "div" "level-item" $ do
                                _ <- elDynClass "table" dTableClass $ do
                                        el "thead" $ do
                                            el "tr" $ do
                                                el "th" $ text ""
                                                el "th" . dynText $ ffor w hashIdHyphenPilot
                                                return ()

                                            sequence_
                                                [ widgetHold (return ()) $ ffor e (mkLegend w c)
                                                | c <- legendClasses
                                                | e <- [e1, e2, e3, e4, e5]
                                                ]

                                            return ()

                                        el "tfoot" $ do
                                            el "tr" $ do
                                                el "td" $ text "--"
                                                el "td" $ text "line of constant effort"
                                                return ()

                                return ()
                    return ()

        ys <- sample $ current xs

        let pilots :: [Pilot] = take numLegendPilots $ repeat nullPilot
        dPilots :: Dynamic _ [Pilot] <- foldDyn (\pa pas -> take numLegendPilots $ pa : pas) pilots (updated dPilot)
        (dPilot, eRedraw, (e1, e2, e3, e4, e5))
            <- selectPilots dPilots (\dPilots' -> elClass "div" "tile is-child" $ tableEffort sEx xs dPilots')

        return ()

    return ()
