module FlareTiming.Task (tasks) where

import Prelude hiding (map)
import Reflex.Dom
    ( MonadWidget, Event, Dynamic, XhrRequest(..), EventName(Click)
    , (=:)
    , def
    , holdDyn
    , foldDyn
    , sample
    , current
    , updated
    , widgetHold
    , widgetHold_
    , elAttr
    , elClass
    , elDynClass'
    , el
    , text
    , dynText
    , simpleList
    , getPostBuild
    , fmapMaybe
    , performRequestAsync
    , decodeXhrResponse
    , leftmost
    , domEvent
    , toggle
    )
import qualified Data.Text as T (Text, pack, intercalate)
import Data.Map (union)

import Data.Flight.Types (Task(..), Zones(..), RawZone(..), SpeedSection)
import qualified FlareTiming.Turnpoint as TP (getName)

loading :: MonadWidget t m => m ()
loading = el "li" $ text "Tasks will be shown here"

getSpeedSection :: Task -> [RawZone]
getSpeedSection (Task _ Zones{raw = tps} ss) =
    speedSectionOnly ss tps
    where
        speedSectionOnly :: SpeedSection -> [RawZone] -> [RawZone]
        speedSectionOnly Nothing xs =
            xs
        speedSectionOnly (Just (start, end)) xs =
            take (end' - start' + 1) $ drop (start' - 1) xs
            where
                start' = fromInteger start
                end' = fromInteger end

rainbow :: [String]
rainbow =
    [ "is-primary"
    , "is-warning"
    , "is-info"
    , "is-danger"
    , "is-success"
    ]

color :: Int -> String
color ii = rainbow !! (ii `mod` length rainbow)

taskTpNames
    :: forall t (m :: * -> *). MonadWidget t m
    => Dynamic t Bool
    -> Dynamic t T.Text
    -> Dynamic t [T.Text]
    -> m ()
taskTpNames detailed ii tps = do
    let e :: Event t Bool = updated detailed
    let f = do elClass "p" "subtitle" $ dynText ii; listTpNames tps

    widgetHold_ f
        $ fmap (\case
            False -> f
            True -> labelTpNames ii tps) e

listTpNames
    :: MonadWidget t m
    => Dynamic t [T.Text]
    -> m ()
listTpNames tps = do
    el "ul" $ do
        _ <- simpleList tps (el "li" . dynText)
        return ()
    return ()

labelTpNames
    :: MonadWidget t m
    => Dynamic t T.Text
    -> Dynamic t [T.Text]
    -> m ()
labelTpNames ii tps = do
    xs <- sample . current $ tps
    jj <- sample . current $ ii
    text $ jj <> ": " <> T.intercalate " - " xs
    return ()

task
    :: forall t (m :: * -> *). MonadWidget t m
    => Dynamic t (Int, Task)
    -> m (Dynamic t Bool)
task ix = do
    ii :: Int <- sample . current $ fst <$> ix
    let jj = show ii
    let x :: Dynamic t Task = snd <$> ix
    let xs = getSpeedSection <$> x
    let tps = (fmap . fmap) (T.pack . TP.getName) xs

    mdo
        (aa, _) <- elDynClass' "div" cc $ do
            elClass "div" "tile is-parent is-vertical" $
                elClass "div" (T.pack $ "tile is-child notification " ++ color ii) $ do
                    taskTpNames ee dd tps

        ee
            :: Dynamic t Bool
            <- toggle False $ domEvent Click aa

        cc
            :: Dynamic t T.Text
            <- return $ (\case False -> "tile is-1"; True -> "tile is-12") <$> ee

        dd
            :: Dynamic t T.Text
            <- return $ T.pack . (\case False -> jj; True -> "Task " ++ jj) <$> ee

        return ee

tasks :: MonadWidget t m => m ()
tasks = do
    pb :: Event t () <- getPostBuild
    elClass "div" "spacer" $ return ()
    elClass "div" "container" $ do
        _ <- el "ul" $ do widgetHold loading $ fmap getTasks pb
        elClass "div" "spacer" $ return ()

    return ()

getTasks :: MonadWidget t m => () -> m ()
getTasks () = do
    pb :: Event t () <- getPostBuild
    let defReq = "http://localhost:3000/tasks"
    let req md = XhrRequest "GET" (maybe defReq id md) def
    rsp <- performRequestAsync $ fmap req $ leftmost [ Nothing <$ pb ]

    let es :: Event t [Task] = fmapMaybe decodeXhrResponse rsp
    xs :: Dynamic t [Task] <- holdDyn [] es
    let ys :: Dynamic t [(Int, Task)] = fmap (zip [1 .. ]) xs

    _ <-
        elAttr
            "div"
            (union
                ("class" =: "tile is-ancestor")
                ("style" =: "flex-wrap: wrap;")
            ) $ do
        simpleList ys task

    return ()
