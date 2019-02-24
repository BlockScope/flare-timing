{-# LANGUAGE JavaScriptFFI #-}
{-# LANGUAGE ForeignFunctionInterface #-}

module FlareTiming.Plot.Arrival.Plot
    ( Plot(..)
    , hgPlot
    ) where

import Prelude hiding (map, log)
import GHCJS.Types (JSVal)
import GHCJS.DOM.Element (IsElement)
import GHCJS.DOM.Types (Element(..), toElement, toJSVal, toJSValListOf)

import WireTypes.ValidityWorking (PilotsFlying(..))
import WireTypes.Point (GoalRatio(..))

-- SEE: https://gist.github.com/ali-abrar/fa2adbbb7ee64a0295cb
newtype Plot = Plot { unPlot :: JSVal }

foreign import javascript unsafe
    "functionPlot(\
    \{ target: '#hg-plot-arrival'\
    \, title: 'Arrival Point Distribution'\
    \, width: 360\
    \, height: 360\
    \, disableZoom: true\
    \, xAxis: {label: 'Arrival Placing', domain: [0, $2 + 1]}\
    \, yAxis: {domain: [0, 1.01]}\
    \, data: [{\
    \    points: $3\
    \  , fnType: 'points'\
    \  , color: 'blue'\
    \  , range: [1, $2]\
    \  , graphType: 'polyline'\
    \  },{\
    \    points: $4\
    \  , fnType: 'points'\
    \  , color: 'blue'\
    \  , attr: { r: 2 }\
    \  , range: [1, $2]\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $5\
    \  , fnType: 'points'\
    \  , color: 'red'\
    \  , attr: { r: 3 }\
    \  , range: [1, $2]\
    \  , graphType: 'scatter'\
    \  }]\
    \, annotations: [{\
    \    y: 0.2\
    \  , text: 'minimum possible fraction'\
    \  }]\
    \})"
    hgPlot_ :: JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> IO JSVal

hgPlot
    :: IsElement e
    => e
    -> PilotsFlying
    -> GoalRatio
    -> [[Double]]
    -> [[Double]]
    -> IO Plot
hgPlot e _ _ xs ys = do
    let n :: Integer = fromIntegral $ length xs + length ys

    n' <- toJSVal (fromIntegral n :: Double)
    let xy :: [[Double]] = [[x', fn n x'] | x <- [1 .. 10 * n], let x' = 0.1 * fromIntegral x]
    xy' <- toJSValListOf xy
    xs' <- toJSValListOf xs
    ys' <- toJSValListOf ys

    Plot <$> hgPlot_ (unElement . toElement $ e) n' xy' xs' ys'

fn :: Integer -> Double -> Double
fn n x = 0.2 + 0.037 * y + 0.13 * y**2 + 0.633 * y**3
    where
        y :: Double
        y = 1.0 - (x - 1.0) / (fromIntegral n)
