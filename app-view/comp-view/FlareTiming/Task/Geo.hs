module FlareTiming.Task.Geo (tableGeo) where

import Reflex
import Reflex.Dom
import qualified Data.Text as T (Text, pack)

import FlareTiming.Comms
import WireTypes.Route
    ( OptimalRoute(..), TaskLength(..)
    , TrackLine(..), PlanarTrackLine(..), TaskLegs(..)
    , taskLength, taskLegs, showTaskDistance
    )
import FlareTiming.Events (IxTask(..))

tableGeo
    :: MonadWidget t m
    => IxTask
    -> m ()
tableGeo ix = do
    elClass "div" "tile is-parent" $ do
        elClass "article" "tile is-child box" $ do
            elClass "p" "title" $ text "Geo distance comparison"
            elClass "div" "content" $
                tableCmp ix

rowOptimal
    :: MonadWidget t m
    => T.Text
    -> T.Text
    -> m (Dynamic t (OptimalRoute (Maybe TrackLine)))
    -> m ()
rowOptimal earth algo  lnTask = do
    ln <- (fmap . fmap) taskLength lnTask
    let d = ffor ln (maybe "" $ \TaskLength{..} ->
                showTaskDistance taskRoute)

    legs <- (fmap . fmap) ((maybe "" $ T.pack . show . length . (\TaskLegs{legs} -> legs)) . taskLegs) lnTask

    el "tr" $ do
        el "td" $ text earth
        el "td" $ text algo
        el "td" $ text earth
        el "td" $ text algo
        elClass "td" "td-geo-distance" $ dynText d
        elClass "td" "td-geo-legs" $ dynText legs

rowSpherical :: MonadWidget t m => IxTask -> m ()
rowSpherical = rowOptimal "Sphere" "Haversines" . getTaskLengthSphericalEdge

rowEllipsoid :: MonadWidget t m => IxTask -> m ()
rowEllipsoid = rowOptimal "Ellipsoid" "Vincenty" . getTaskLengthEllipsoidEdge

rowTrackLine
    :: MonadWidget t m
    => T.Text
    -> T.Text
    -> T.Text
    -> T.Text
    -> Dynamic t (Maybe TrackLine)
    -> m ()
rowTrackLine earthIn algoIn earthOut algoOut ln = do
    let d = ffor ln (maybe "" $ \TrackLine{distance = x} -> showTaskDistance x)

    let legs =
            ffor ln (maybe "" $ T.pack . show . length . (\TrackLine{legs = xs} -> xs))

    el "tr" $ do
        el "td" $ text earthIn
        el "td" $ text algoIn
        el "td" $ text earthOut
        el "td" $ text algoOut
        elClass "td" "td-geo-distance" $ dynText d
        elClass "td" "td-geo-legs" $ dynText legs

rowProjectedSphere
    :: MonadWidget t m
    => IxTask
    -> m ()
rowProjectedSphere ix = do
    ln  <- getTaskLengthProjectedEdgeSpherical ix
    rowTrackLine "Plane" "Pythagorus" "Sphere" "Haversines" ln

rowProjectedEllipsoid
    :: MonadWidget t m
    => IxTask
    -> m ()
rowProjectedEllipsoid ix = do
    ln <- getTaskLengthProjectedEdgeEllipsoid ix
    rowTrackLine "Plane" "Pythagorus" "Ellipsoid" "Vincenty" ln

rowProjectedPlanar
    :: MonadWidget t m
    => IxTask
    -> m ()
rowProjectedPlanar ix = do
    ln <- getTaskLengthProjectedEdgePlanar ix
    let d = ffor ln (maybe "" $ \PlanarTrackLine{distance = x} -> showTaskDistance x)

    let legs =
            ffor ln (maybe "" $ T.pack . show . length . (\PlanarTrackLine{legs = xs} -> xs))

    el "tr" $ do
        el "td" $ text "Plane"
        el "td" $ text "Pythagorus"
        el "td" $ text "Plane"
        el "td" $ text "Pythagorus"
        elClass "td" "td-geo-distance" $ dynText d
        elClass "td" "td-geo-legs" $ dynText legs

tableCmp
    :: MonadWidget t m
    => IxTask
    -> m ()
tableCmp ix = do
    _ <- elClass "table" "table is-striped" $ do
            el "thead" $ do
                el "tr" $ do
                    elAttr "th" ("colspan" =: "2" <> "class" =: "th-geo-network") $ text "Network Paths Cost *"
                    elAttr "th" ("colspan" =: "2" <> "class" =: "th-geo-path") $ text "Shortest Path Cost †"
                    elAttr "th" ("colspan" =: "2" <> "class" =: "th-geo-how-far") $ text "Shortest Path Distance"

                el "tr" $ do
                    elClass "th" "th-geo-network-earth" $ text "Earth"
                    elClass "th" "th-geo-network-algo" $ text "Algorithm"
                    elClass "th" "th-geo-path-earth" $ text "Earth"
                    elClass "th" "th-geo-path-algo" $ text "Algorithm"
                    elClass "th" "th-geo-distance" $ text "Distance"
                    elClass "th" "th-geo-legs" $ text "Legs"

            _ <- el "tbody" $ do
                rowSpherical ix
                rowEllipsoid ix

                rowProjectedSphere ix
                rowProjectedEllipsoid ix
                rowProjectedPlanar ix

            let tr = el "tr" . elAttr "td" ("colspan" =: "6")
            _ <- el "tfoot" $ do
                tr $ text "* The Earth model and algorithm used when constructing a network of points with distance between pairs as the cost to be minimized when finding the shortest path through the network"
                tr $ text "† The Earth model and algorithm used when reporting the sum of distances between pairs of points along the path as the path distance"

            return ()

    return ()
