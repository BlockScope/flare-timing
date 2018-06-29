module Main (main) where

import Test.DocTest (doctest)

arguments :: [String]
arguments =
    [ "-isrc"
    , "library/Flight/Kml.hs"
    , "library/Flight/Types.hs"
    , "library/Flight/Kml/Internal.hs"
    ]

main :: IO ()
main = doctest arguments
