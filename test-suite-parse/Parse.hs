{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE QuasiQuotes #-}

module Main (main) where

import Data.Waypoint (parseTime, parseBaro, parseCoord)

import Test.Tasty
import Test.Tasty.SmallCheck as SC
import Test.SmallCheck.Series as SC
import Test.Tasty.QuickCheck as QC
import Test.Tasty.HUnit

import Data.List (sort)
import Data.List.Split (split, splitOn, dropBlanks, dropDelims, oneOf, chunksOf)
import Text.RawString.QQ (r)
import Numeric

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Tests" [properties, unitTests]

properties :: TestTree
properties = testGroup "Properties" [scProps, qcProps]

scProps :: TestTree
scProps = testGroup "(checked by SmallCheck)"
    [ SC.testProperty "sort == sort . reverse" $
        \xs-> sort (xs :: [Int]) == sort (reverse xs)

    -- WARNING: Failing test.
    --    there exists [-1] such that
    --      condition is false
    , SC.testProperty "parse time from [ ints ]" parsePositiveInts'
    ]

qcProps :: TestTree
qcProps = testGroup "(checked by QuickCheck)"
    [ QC.testProperty "sort == sort . reverse" $
        \xs-> sort (xs :: [Int]) == sort (reverse xs)

    -- WARNING: Failing test.
    --   *** Failed! Falsifiable (after 5 tests and 4 shrinks):
    --   [-1]
    --   Use --quickcheck-replay '4 TFGenR 000000506988C7BD00000000004C4B40000000000000E21E0000065689DE4780 0 62 6 0' to reproduce.
    , QC.testProperty "parse time from [ ints ]" parsePositiveInts
    ]

unitTests :: TestTree
unitTests = testGroup "Unit tests"
    [ testCase "Parse time (same length)" $
        length parsedTime @?= length expectedTimeStr

    , testCase "Parse baro (same length)" $
        length parsedBaro @?= length expectedBaroStr

    , testCase "Parse coord (same length)" $
        length parsedCoord @?= length expectedCoordStr

    , testCase "Parse time (as expected)" $
        parsedTime @?= expectedTimeStr

    , testCase "Parse baro (as expected)" $
        parsedBaro @?= expectedBaroStr

    , testCase "Parse coord (as expected)" $
        parsedCoord @?= expectedCoordStr
    ]

parsePositiveInts' :: [ SC.Positive Int ] -> Bool
parsePositiveInts' xs =
    parseInts $ SC.getPositive <$> xs

parsePositiveInts :: [ QC.Positive Int ] -> Bool
parsePositiveInts xs =
    parseInts $ QC.getPositive <$> xs

parseInts :: [ Int ] -> Bool
parseInts xs =
    let strings ::  [ String ]
        strings = show <$> xs

        string :: String
        string = unwords strings

        parsed :: [ String ]
        parsed = parseTime string

    in parsed == strings

parsedTime :: [ String ]
parsedTime = parseTime timeToParse
        
expectedTimeStr :: [ String ]
expectedTimeStr = split (dropBlanks $ dropDelims $ oneOf " \n") timeToParse

timeToParse :: String
timeToParse = [r|
0 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120
125 130 135 140 145 150 155 160 165 170 175 180 185 190 195 200 205 210 215 220 225 231 236 241 246 
12519 12524 12529 12534 12539 12544 12549 12554 12559 12564 12569 12574 12579 12584 12589 12594 12599 12604 12609 12614 12619 12624 12629 12634 12639 
12644 12649 12654 12659 12664 12669 12674 12679 12684 12689
              |]

parsedBaro :: [ String ]
parsedBaro = parseBaro baroToParse

expectedBaroStr :: [ String ]
expectedBaroStr = split (dropBlanks $ dropDelims $ oneOf " \n") baroToParse

baroToParse :: String
baroToParse = [r|
221 221 221 221 221 221 221 221 221 221 221 221 221 221 221 222 222 222 222 222 222 222 222 222 222 
222 222 221 225 232 246 262 268 274 279 290 305 321 340 356 372 389 401 409 418 422 422 430 428 442 
399 397 393 384 376 368 360 350 343 340 330 319 313 313 311 311 311 311 311 311 311 312 312 312 312 
312 312 312 312 312 312 312 312 312 312
              |]

parsedCoord :: [ String ]
parsedCoord = parseCoord coordToParse

rtrimZero :: String -> String
rtrimZero =
     reverse . dropWhile (== '0') . reverse

formatFloat :: String -> String
formatFloat s =
    case splits of
         [ a, b ] -> a ++ "." ++ rtrimZero b
         _ -> s
    where
        s' = showFFloat (Just 6) (read s :: Double) ""
        splits = splitOn "." s'

triple :: [ String ] -> String
triple xs =
    case xs of
        [a, b, c] ->
            concat [ "("
                   , formatFloat a
                   , ","
                   , formatFloat b
                   , ","
                   , c
                   , ")"
                   ]

        _ -> concat xs

expectedCoordStr :: [ String ]
expectedCoordStr = 
    triple <$> chunksOf 3 (split (dropBlanks $ dropDelims $ oneOf " ,\n") coordToParse)

coordToParse :: String
coordToParse = [r|
147.932417,-33.360950,241 147.932417,-33.360950,241 147.932417,-33.360950,241 147.932417,-33.360950,241 147.932417,-33.360950,241 
147.932417,-33.360950,241 147.932417,-33.360950,241 147.932417,-33.360950,241 147.932417,-33.360950,241 147.932417,-33.360950,241 
147.932183,-33.708533,277 147.932183,-33.708533,277 147.932183,-33.708533,277 147.932183,-33.708533,277 147.932183,-33.708533,277 
147.932183,-33.708533,277 147.932183,-33.708533,277 147.932183,-33.708533,277 147.932183,-33.708533,277 147.932183,-33.708533,277
              |]
