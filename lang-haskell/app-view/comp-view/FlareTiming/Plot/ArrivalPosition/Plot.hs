{-# LANGUAGE JavaScriptFFI #-}
{-# LANGUAGE ForeignFunctionInterface #-}

module FlareTiming.Plot.ArrivalPosition.Plot (hgPlotPosition) where

import Prelude hiding (map, log)
import GHCJS.Types (JSVal)
import GHCJS.DOM.Element (IsElement)
import GHCJS.DOM.Types (Element(..), toElement, toJSVal, toJSValListOf)
import Data.List (nub)
import FlareTiming.Plot.Foreign (Plot(..))

foreign import javascript unsafe
    "functionPlot(\
    \{ target: '#hg-plot-arrival-position'\
    \, title: 'Arrival Position Point Distribution'\
    \, width: 700\
    \, height: 640\
    \, disableZoom: true\
    \, xAxis: {label: 'Arrival Placing', domain: [0, $2 + 1]}\
    \, yAxis: {domain: [-0.05, 1.05]}\
    \, data: [{\
    \    points: $3\
    \  , fnType: 'points'\
    \  , color: '#808080'\
    \  , range: [1, $2]\
    \  , attr: { stroke-dasharray: '5,5' }\
    \  , graphType: 'polyline'\
    \  },{\
    \    points: $4\
    \  , fnType: 'points'\
    \  , color: '#1e1e1e'\
    \  , attr: { r: 3 }\
    \  , range: [1, $2]\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $5\
    \  , fnType: 'points'\
    \  , color: '#1e1e1e'\
    \  , attr: { r: 5 }\
    \  , range: [1, $2]\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $6\
    \  , fnType: 'points'\
    \  , color: '#377eb8'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $7\
    \  , fnType: 'points'\
    \  , color: '#ff7f00'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $8\
    \  , fnType: 'points'\
    \  , color: '#4daf4a'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $9\
    \  , fnType: 'points'\
    \  , color: '#e41a1c'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $10\
    \  , fnType: 'points'\
    \  , color: '#984ea3'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $11\
    \  , fnType: 'points'\
    \  , color: '#377eb8'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $12\
    \  , fnType: 'points'\
    \  , color: '#ff7f00'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $13\
    \  , fnType: 'points'\
    \  , color: '#4daf4a'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $14\
    \  , fnType: 'points'\
    \  , color: '#e41a1c'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  },{\
    \    points: $15\
    \  , fnType: 'points'\
    \  , color: '#984ea3'\
    \  , attr: { r: 9 }\
    \  , graphType: 'scatter'\
    \  }]\
    \, annotations: [{\
    \    y: 0.2\
    \  , text: 'minimum possible fraction'\
    \  }]\
    \})"
    plotPosition_ :: JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> JSVal -> IO JSVal

hgPlotPosition
    :: IsElement e
    => e
    -> ([[Double]], [[Double]])
    -> ([[Double]], [[Double]])
    -> IO Plot
hgPlotPosition e (xsSolo, xsEqual) (ysSolo, ysEqual) = do
    let n :: Integer = fromIntegral $ length xsSolo + length xsEqual

    n' <- toJSVal (fromIntegral n :: Double)
    let xy :: [[Double]] =
            [ [x', fnPosition n x']
            | x <- [1 .. 10 * n]
            , let x' = 0.1 * fromIntegral x
            ]

    xy' <- toJSValListOf xy
    xsSolo' <- toJSValListOf xsSolo
    xsEqual' <- toJSValListOf $ nub xsEqual

    ysS1 <- toJSValListOf $ take 1 ysSolo
    ysS2 <- toJSValListOf $ take 1 $ drop 1 ysSolo
    ysS3 <- toJSValListOf $ take 1 $ drop 2 ysSolo
    ysS4 <- toJSValListOf $ take 1 $ drop 3 ysSolo
    ysS5 <- toJSValListOf $ take 1 $ drop 4 ysSolo

    ysE1 <- toJSValListOf $ take 1 ysEqual
    ysE2 <- toJSValListOf $ take 1 $ drop 1 ysEqual
    ysE3 <- toJSValListOf $ take 1 $ drop 2 ysEqual
    ysE4 <- toJSValListOf $ take 1 $ drop 3 ysEqual
    ysE5 <- toJSValListOf $ take 1 $ drop 4 ysEqual

    Plot <$>
        plotPosition_
            (unElement . toElement $ e)
            n'
            xy'
            xsSolo' xsEqual'
            ysS1 ysS2 ysS3 ysS4 ysS5
            ysE1 ysE2 ysE3 ysE4 ysE5

fnPosition :: Integer -> Double -> Double
fnPosition n x = 0.2 + 0.037 * y + 0.13 * y**2 + 0.633 * y**3
    where
        y :: Double
        y = 1.0 - (x - 1.0) / (fromIntegral n)