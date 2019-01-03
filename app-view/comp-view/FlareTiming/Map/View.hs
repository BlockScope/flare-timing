module FlareTiming.Map.View (viewMap) where

-- TODO: Find out why hiding Debug.Trace.debugEvent doesn't work.
-- Ambiguous occurrence ‘traceEvent’
-- It could refer to either ‘Debug.Trace.traceEvent’,
--                           imported from ‘Debug.Trace’ at ...
--                           or ‘Reflex.Dom.traceEvent’,
--                           imported from ‘Reflex.Dom’ at ...
--                           (and originally defined in ‘Reflex.Class’)
-- import Debug.Trace hiding (debugEvent)
-- import Reflex.Dom
-- import qualified Debug.Trace as DT
import Prelude hiding (map)
import Text.Printf (printf)
import Reflex.Dom

import qualified Data.Text as T (Text, pack)
import Reflex.Time (delay)
import Data.Maybe (catMaybes, listToMaybe)
import qualified Data.Map as Map
import Data.List (zipWith4)
import Control.Monad (sequence)
import Control.Monad.IO.Class (liftIO)

import qualified FlareTiming.Map.Leaflet as L
    ( Marker(..)
    , Circle(..)
    , map
    , mapSetView
    , layerGroup
    , layerGroupAddToMap
    , tileLayer
    , marker
    , markerPopup
    , mapInvalidateSize
    , circle
    , circleAddToMap
    , trackline
    , polyline
    , fitBounds
    , panToBounds
    , latLngBounds
    , layersControl
    , layersExpand
    , addOverlay
    )
import WireTypes.Pilot (Pilot(..), PilotName(..), getPilotName)
import WireTypes.Comp (Task(..), SpeedSection, getAllRawZones)
import WireTypes.Zone
    (Zones(..), RawZone(..), RawLatLng(..), RawLat(..), RawLng(..))
import WireTypes.ZoneKind (Radius(..))
import WireTypes.Route
    ( OptimalRoute, TrackLine
    , TaskRoute(..), TaskRouteSubset(..), SpeedRoute(..)
    , optimalTaskRoute, optimalTaskRouteSubset, optimalSpeedRoute
    )
import qualified FlareTiming.Turnpoint as TP (getName)
import FlareTiming.Comms (getTaskPilotDf)
import FlareTiming.Events (IxTask(..))

data ZoomOrPan = Zoom | Pan deriving Show

zoomButton
    :: MonadWidget t m
    => (RawZone, T.Text)
    -> m (Event t [RawZone])
zoomButton (z, btnClass) = do
    let s = TP.getName z
    (e, _) <- elClass' "a" btnClass $ text s
    return $ [z] <$ domEvent Click e

zoomOrPanIcon :: ZoomOrPan -> T.Text
zoomOrPanIcon Zoom = "fa fa-search-plus"
zoomOrPanIcon Pan = "fa fa-arrows"

pilotToSelectMap :: [Pilot] -> Map.Map Int T.Text
pilotToSelectMap ps =
    Map.fromList
    $ (0, "Select a pilot")
    : zipWith (\i (Pilot (_, PilotName n)) -> (i, T.pack n)) [1..] ps

pilotAtIdx :: Int -> [Pilot] -> Maybe Pilot
pilotAtIdx 0 _ = Nothing
pilotAtIdx ii ps =
    -- WARNING: The zeroth item is the prompt in the select.
    listToMaybe . take 1 . drop (ii - 1) $ ps

taskZoneButtons
    :: MonadWidget t m
    => Task
    -> Dynamic t [Pilot]
    -> Event t ()
    -> m (Dynamic t ZoomOrPan, Dynamic t [RawZone], Event t Pilot)
taskZoneButtons t@Task{speedSection} ps eDownloaded = do
    let ps' = pilotToSelectMap <$> ps
    let zones = getAllRawZones t
    let btn = "button"
    let btnStart = "button has-text-success"
    let btnEnd = "button has-text-danger"

    let zoneClasses =
            maybe
                (zip zones $ repeat btn)
                (\(start, end) ->
                    zipWith
                        (\z i ->
                            let c = if | i == start -> btnStart
                                       | i == end -> btnEnd
                                       | otherwise -> btn
                            in (z, c))
                        zones
                        [1..])

    elClass "div" "field is-grouped" $ do
        x <- elClass "p" "control" $ do
                elClass "div" "buttons has-addons" $ do
                    rec (zoom, _) <-
                            elClass' "a" "button" $ do
                                elClass "span" "icon is-small" $
                                    elDynClass "i" zpClass $ return ()
                                el "span" $ dynText zpText

                        zoomOrPan <-
                            (fmap . fmap)
                            (\case True -> Pan; False -> Zoom)
                            (toggle True $ domEvent Click zoom)

                        let zpText = ffor zoomOrPan $ T.pack . (++ " to ...") . show
                        let zpClass = ffor zoomOrPan zoomOrPanIcon

                    (extents, _) <- elAttr' "a" ("class" =: "button") $ text "Extents"
                    let allZones = zones <$ domEvent Click extents

                    eachZone <- sequence $ zoomButton <$> zoneClasses speedSection
                    zs <- holdDyn zones . leftmost $ allZones : eachZone
                    return $ (zoomOrPan, zs)

        dd <- elClass "p" "control" $ do
            elClass "span" "select" $
                dropdown 0 ps' def

        let isSelected = ffor (value dd) (/= 0)

        rec (download, _)
                    <- elClass "p" "control" $ do
                        elDynAttr' "a" downloadAttrs  $ do
                            elClass "span" "icon is-small" $
                                elDynClass "i" downloadClass $ return ()
                            el "span" $ text "Fetch Track"

            let eDownload = domEvent Click download

            downloadClass <- holdDyn "fa fa-download" $ leftmost
                                [ "fa fa-spinner" <$ eDownload
                                , "fa fa-download" <$ eDownloaded
                                ]
            downloadAttrs <- holdDyn ("class" =: "button is-link") $ leftmost
                                [ "class" =: "button is-link" <$ eDownload
                                , "class" =: "button is-link" <$ eDownloaded
                                , ffor (updated isSelected) (\case
                False -> "class" =: "button is-link" <> "disabled" =: ""
                True -> "class" =: "button is-link")
                                ]

        let p = ffor2 (value dd) ps pilotAtIdx
        let y = fforMaybe (tagPromptlyDyn p $ eDownload) id

        return (fst x, snd x, y)

showLatLng :: (Double, Double) -> String
showLatLng (lat, lng) =
    printf fmt (abs lat) (abs lng)
    where
        fmt = case (lat < 0, lng < 0) of
                  (True, True) -> "%f °S, %f °W"
                  (False, True) -> "%f °N, %f °W"
                  (True, False) -> "%f °S, %f °E"
                  (False, False) -> "%f °N, %f °E"

newtype TurnpointName = TurnpointName String
newtype Color = Color String

marker :: Color -> (Double, Double) -> IO L.Marker
marker _ latLng = do
    mark <- L.marker latLng
    L.markerPopup mark $ showLatLng latLng
    return mark

turnpoint
    :: TurnpointName
    -> Color
    -> (Double, Double)
    -> (Radius, Maybe Radius)
    -> IO (L.Marker, (L.Circle, Maybe L.Circle))
turnpoint (TurnpointName tpName) (Color color) latLng (Radius r, g) = do
    xMark <- L.marker latLng
    L.markerPopup xMark tpName
    xCyl <- L.circle latLng r color False True
    yCyl <- sequence $ (\(Radius y) -> L.circle latLng y color True False) <$> g
    return (xMark, (xCyl, yCyl))

zoneToLL :: RawZone -> (Double, Double)
zoneToLL RawZone{lat = RawLat lat', lng = RawLng lng'} =
    (fromRational lat', fromRational lng')

zoneToLLR :: RawZone -> (Double, Double, Double)
zoneToLLR RawZone{lat = RawLat lat', lng = RawLng lng', radius = Radius r} =
    (fromRational lat', fromRational lng', r)

rawToLL :: RawLatLng -> (Double, Double)
rawToLL RawLatLng{lat = RawLat lat', lng = RawLng lng'} =
    (fromRational lat', fromRational lng')

viewMap
    :: MonadWidget t m
    => IxTask
    -> Dynamic t Task
    -> Dynamic t (OptimalRoute (Maybe TrackLine))
    -> Event t (Pilot, [[Double]])
    -> m (Event t Pilot)
viewMap ix task route pilotTrack = do
    task' <- sample . current $ task
    route' <- sample . current $ route

    map
        ix
        task'
        (optimalTaskRoute route')
        (optimalTaskRouteSubset route')
        (optimalSpeedRoute route')
        pilotTrack

map
    :: MonadWidget t m
    => IxTask
    -> Task
    -> TaskRoute
    -> TaskRouteSubset
    -> SpeedRoute
    -> Event t (Pilot, [[Double]])
    -> m (Event t Pilot)

map _ Task{zones = Zones{raw = []}} _ _ _ _ = do
    el "p" $ text "The task has no turnpoints."
    return never

map _ _ (TaskRoute []) _ _ _ = do
    return never

map _ _ _ (TaskRouteSubset []) _ _ = do
    el "p" $ text "The optimal task route speed section has no turnpoints."
    return never

map _ _ _ _ (SpeedRoute []) _ = do
    el "p" $ text "The optimal route through only the speed section has no turnpoints."
    return never

map
    ix
    task@Task{zones = Zones{raw = xs}, speedSection}
    (TaskRoute taskRoute)
    (TaskRouteSubset taskRouteSubset)
    (SpeedRoute speedRoute)
    pilotTrack = do

    let tpNames = fmap (\RawZone{..} -> TurnpointName zoneName) xs
    postBuild <- delay 1 =<< getPostBuild

    pilots <- getTaskPilotDf ix
    (zoomOrPan, evZoom, activePilot)
        <- taskZoneButtons task pilots $ () <$ pilotTrack

    (eCanvas, _) <- elAttr' "div" ("style" =: "height: 680px;width: 100%") $ return ()

    rec performEvent_ $ leftmost
            [ ffor postBuild (\_ -> liftIO $ do
                L.mapInvalidateSize lmap'
                L.fitBounds lmap' bounds'
                return ())

            , updated $ ffor2 zoomOrPan evZoom (\zp zs -> liftIO $ do
                bs <- L.latLngBounds $ zoneToLLR <$> zs

                case zp of
                    Zoom -> L.fitBounds lmap' bs
                    Pan -> L.panToBounds lmap' bs

                return ())

            , ffor pilotTrack (\(p, t) -> liftIO $ do
                pilotLine <- L.trackline t "black"
                pilotGroup <- L.layerGroup pilotLine []
                L.addOverlay layers' (getPilotName p, pilotGroup)
                L.layersExpand layers'
                return ())
            ]

        (lmap', bounds', layers') <- liftIO $ do
            lmap <- L.map (_element_raw eCanvas)
            L.mapSetView lmap (zoneToLL $ head xs) 11

            mapLayer <-
                -- SEE: http://leaflet-extras.github.io/leaflet-providers/preview/
                L.tileLayer
                    "http://{s}.tile.opentopomap.org/{z}/{x}/{y}.png"
                    17

            let len = length xs
            let cs = zoneColors len speedSection

            let xPts :: [(Double, Double)] = fmap zoneToLL xs
            let ptsTaskRoute :: [(Double, Double)] = fmap rawToLL taskRoute
            let ptsTaskRouteSubset :: [(Double, Double)] = fmap rawToLL taskRouteSubset
            let ptsSpeedRoute :: [(Double, Double)] = fmap rawToLL speedRoute

            xMarks <-
                sequence $
                    zipWith4
                        turnpoint
                        tpNames
                        cs
                        xPts
                        ((\x -> (radius x, give x)) <$> xs)

            _ <- sequence $ ((flip L.circleAddToMap) lmap . fst . snd) <$> xMarks

            let giveCyls = catMaybes $ snd . snd <$> xMarks
            _ <- sequence $ (flip L.circleAddToMap) lmap <$> giveCyls

            courseLine <- L.polyline xPts "gray"
            taskRouteLine <- L.polyline ptsTaskRoute "red"
            taskRouteSubsetLine <- L.polyline ptsTaskRouteSubset "green"
            speedRouteLine <- L.polyline ptsSpeedRoute "magenta"

            taskRouteMarks <- sequence $ zipWith marker cs ptsTaskRoute
            taskRouteSubsetMarks <- sequence $ zipWith marker cs ptsTaskRouteSubset
            speedRouteMarks <- sequence $ zipWith marker cs ptsSpeedRoute

            courseGroup <- L.layerGroup courseLine $ fst <$> xMarks
            taskRouteGroup <- L.layerGroup taskRouteLine taskRouteMarks
            taskRouteSubsetGroup <- L.layerGroup taskRouteSubsetLine taskRouteSubsetMarks
            speedRouteGroup <- L.layerGroup speedRouteLine speedRouteMarks

            -- NOTE: Adding the route now so that it displays by default but
            -- can also be hidden via the layers control. The course line is
            -- not added by default but can be shown via the layers control.
            L.layerGroupAddToMap taskRouteGroup lmap

            layers <-
                L.layersControl
                    mapLayer
                    lmap
                    courseGroup
                    taskRouteGroup
                    taskRouteSubsetGroup
                    speedRouteGroup


            bounds <- L.latLngBounds $ zoneToLLR <$> xs

            return (lmap, bounds, layers)

    return activePilot

blues :: [Color]
blues = repeat $ Color "blue"

yellows :: [Color]
yellows = repeat $ Color "yellow"

zoneColors :: Int -> SpeedSection -> [Color]
zoneColors _ Nothing = blues
zoneColors len (Just (start, end)) =
    if len < 2 then blues else
    prolog <> [Color "green"] <> xs' <> [Color "red"] <> yellows
    where
        -- NOTE: The speed section uses 1-based indexing.
        start' = fromIntegral start
        end' = fromIntegral end

        prolog = take (start' - 1) $ yellows
        xs' = take ((end' - start' + 1) - 2) blues
