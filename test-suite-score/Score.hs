module Main (main) where

import qualified Flight.Score as FS

import Test.Tasty (TestTree, testGroup, defaultMain)
import Test.Tasty.SmallCheck as SC
import Test.SmallCheck.Series as SC
import Test.Tasty.QuickCheck as QC
import Test.Tasty.HUnit as HU ((@?=), testCase)
import Data.Ratio ((%))


main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Tests" [properties, unitTests]

properties :: TestTree
properties = testGroup "Properties" [scProps, qcProps]

scProps :: TestTree
scProps = testGroup "(checked by SmallCheck)"
    [ SC.testProperty "Launch validity is in the range of [0, 1]" scLaunchValidity
    ]

qcProps :: TestTree
qcProps = testGroup "(checked by QuickCheck)"
    [ QC.testProperty "Launch validity is in the range of [0, 1]" qcLaunchValidity
    ]

unitTests :: TestTree
unitTests = testGroup "Unit tests"
    [ HU.testCase "Launch validity 0 0 == 0, (nominal actual)" $
        FS.launchValidity (0 % 1) (0 % 1) @?= (0 % 1)

    , HU.testCase "Launch validity 1 0 == 0, (nominal actual)" $
        FS.launchValidity (1 % 1) (0 % 1) @?= (0 % 1)

    , HU.testCase "Launch validity 0 1 == 1, (nominal actual)" $
        FS.launchValidity (0 % 1) (1 % 1) @?= (1 % 1)

    , HU.testCase "Launch validity 1 1 == 1, (nominal actual)" $
        FS.launchValidity (1 % 1) (1 % 1) @?= (1 % 1)
    ]

launchValidity :: Integer -> Integer -> Integer -> Integer -> Bool
launchValidity nx dx ny dy =
    let nominalLaunch = nx % dx
        fractionLaunching = ny % dy
        lv = FS.launchValidity nominalLaunch fractionLaunching
    in lv >= (0 % 1) && lv <= (1 % 1)

scLaunchValidity
    :: Monad m => SC.NonNegative Integer
    -> SC.Positive Integer
    -> SC.NonNegative Integer
    -> SC.Positive Integer
    -> SC.Property m
scLaunchValidity
    (SC.NonNegative nx)
    (SC.Positive dx)
    (SC.NonNegative ny)
    (SC.Positive dy) =
    nx <= dx && ny <= dy SC.==> launchValidity nx dx ny dy

qcLaunchValidity
    :: QC.NonNegative Integer
    -> QC.Positive Integer
    -> QC.NonNegative Integer
    -> QC.Positive Integer
    -> QC.Property
qcLaunchValidity
    (QC.NonNegative nx)
    (QC.Positive dx)
    (QC.NonNegative ny)
    (QC.Positive dy) =
    nx <= dx && ny <= dy QC.==> launchValidity nx dx ny dy
