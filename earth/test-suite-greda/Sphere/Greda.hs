module Sphere.Greda (units) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit as HU ((@?=), testCase)

import Flight.Units ()
import Flight.Zone (Zone(..))
import ToLatLng (toLatLngD)
import qualified Greda as G (task1)
import Sphere.Span (sepD)

task1 :: [Zone Double]
task1 = G.task1 toLatLngD

units :: TestTree
units =
    testGroup "Greda 2011/2012"
    [ HU.testCase "Task 1 zones are separated" $
        sepD task1 @?= True
    ]
