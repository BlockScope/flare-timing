{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE FlexibleInstances #-}

{-|
Module      : Data.Flight.Kml
Copyright   : (c) Block Scope Limited 2017
License     : BSD3
Maintainer  : phil.dejoux@blockscope.com
Stability   : experimental

Provides parsing the KML format for waypoint fixes.
-}
module Data.Flight.Kml
    ( Fix
    , LLA
    , T.LatLngAlt(..)
    , T.FixMark(..)
    , Seconds
    , Latitude
    , Longitude
    , Altitude
    , mkPosition
    , parse
    , parseTimeOffsets
    , parseBaroMarks
    , parseCoords
    , showCoords
    , roundTripCoords
    , formatFloat
    ) where

import Text.XML.HXT.DOM.TypeDefs (XmlTree)
import Text.XML.HXT.Core
    ( ArrowXml
    , (&&&)
    , (>>>)
    , (/>)
    , (>>.)
    , runX
    , getText
    , withValidate
    , withWarnings
    , readString
    , no
    , hasName
    , getChildren
    , hasAttrValue
    , filterA
    , listA
    , unlistA
    , arr
    , orElse
    , constA
    )
import Data.List (concatMap)
import Data.List.Split (splitOn)
import Text.Parsec.Token as P
import Text.Parsec.Char (spaces)
import Text.ParserCombinators.Parsec
    ( GenParser
    , (<?>)
    , char
    , eof
    , option
    , sepBy
    )
import qualified Text.ParserCombinators.Parsec as P (parse)
import Text.Parsec.Language (emptyDef)
import Data.Functor.Identity (Identity)
import Text.Parsec.Prim (ParsecT, parsecMap)
import Numeric (showFFloat)
import qualified Data.Flight.Types as T (LatLngAlt(..), FixMark(..))
import Data.Flight.Types
    ( LLA(..)
    , Fix(..)
    , Seconds
    , Latitude
    , Longitude
    , Altitude
    , mkPosition
    )

lexer :: GenTokenParser String u Identity
lexer = P.makeTokenParser emptyDef

pFloat:: ParsecT String u Identity Rational
pFloat = parsecMap toRational $ P.float lexer 

pNat :: ParsecT String u Identity Integer
pNat = P.natural lexer 

zipFixes :: [ Seconds ] -> [LLA] -> [ Maybe Altitude ] -> [ Fix ]
zipFixes = zipWith3 Fix

-- | Get the fixes. Some KML files don't have PressureAltitude.
getFix :: ArrowXml a => a XmlTree Fix
getFix =
    getTrack
    >>> (listA getCoord
            &&& (getFsInfo
                 >>> (listA getTime
                      &&& listA getBaro `orElse` constA []
                     )
                )
        )
    >>> arr (\(c, (a, b)) ->
            case b of
              [] -> zipFixes a c (repeat Nothing)
              _ -> zipFixes a c (Just <$> b))
    >>> unlistA
    where
        isMetadata =
            getChildren
            >>> hasName "Metadata"
            >>> hasAttrValue "type" (== "track")

        getTrack =
            getChildren
            >>> hasName "Document"
            /> hasName "Folder"
            /> hasName "Placemark"
            >>> filterA isMetadata
            >>. take 1

        getFsInfo =
            getChildren
            >>> hasName "Metadata"
            /> hasName "FsInfo"
            >>. take 1

        getTime =
            getChildren
            >>> hasName "SecondsFromTimeOfFirstPoint"
            /> getText
            >>. concatMap parseTimeOffsets

        getBaro =
            getChildren
            >>> hasName "PressureAltitude"
            /> getText
            >>. concatMap parseBaroMarks

        getCoord =
            getChildren
            >>> hasName "LineString"
            /> hasName "coordinates"
            /> getText
            >>. concatMap parseCoords

parse :: String -> IO (Either String [ Fix ])
parse contents = do
    let doc = readString [ withValidate no, withWarnings no ] contents
    xs <- runX $ doc >>> getFix
    return $ Right xs

pNats :: GenParser Char st [ Integer ]
pNats = do
    _ <- spaces
    xs <- pNat `sepBy` spaces
    _ <- eof
    return xs

parseTimeOffsets :: String -> [ Integer ]
parseTimeOffsets s =
    case P.parse pNats "(stdin)" s of
         Left _ -> []
         Right xs -> xs

parseBaroMarks :: String -> [ Integer ]
parseBaroMarks s =
    case P.parse pNats "(stdin)" s of
         Left _ -> []
         Right xs -> xs

pFix :: GenParser Char st (Rational, Rational, Integer)
pFix = do
    latSign <- option id $ const negate <$> char '-'
    lat <- pFloat <?> "No latitude"
    _ <- char ','
    lngSign <- option id $ const negate <$> char '-'
    lng <- pFloat <?> "No longitude"
    _ <- char ','
    altSign <- option id $ const negate <$> char '-'
    alt <- pNat <?> "No altitude"
    return (latSign lat, lngSign lng, altSign alt)

pFixes :: GenParser Char st [ (Rational, Rational, Integer) ]
pFixes = do
    _ <- spaces
    xs <- pFix `sepBy` spaces <?> "No fixes"
    _ <- eof
    return xs

formatFloat :: String -> String
formatFloat s =
    -- NOTE: Avoid "0." because ...
    --    *Main Data.Waypoint> (read "0." :: Double)
    --    *** Exception: Prelude.read: no parse
    --    *Main Data.Waypoint> (read "0.0" :: Double)
    --    0.0
    case splitOn "." s of
         [ a, "" ] -> showFFloat (Just 6) (read a :: Double) ""
         _ -> showFFloat (Just 6) (read s :: Double) ""

roundTripCoords :: (Rational, Rational, Integer) -> (Double, Double, Integer)
roundTripCoords (lat, lng, alt) =
    let lat' = read $ formatFloat $ show (fromRational lat :: Double)
        lng' = read $ formatFloat $ show (fromRational lng :: Double)
    in (lat', lng', alt)

showCoords :: (Rational, Rational, Integer) -> String
showCoords (lat, lng, alt) =
    mconcat [ formatFloat $ show (fromRational lat :: Double)
            , ","
            , formatFloat $ show (fromRational lng :: Double)
            , ","
            , show alt
            ]

parseCoords :: String -> [ LLA ]
parseCoords s =
    case P.parse pFixes "(stdin)" s of
         Left _ -> []
         Right xs -> (\(lat, lng, alt) -> LLA lat lng alt) <$> xs
