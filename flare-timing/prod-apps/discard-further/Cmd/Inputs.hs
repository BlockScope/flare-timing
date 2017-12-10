{-# LANGUAGE ScopedTypeVariables #-}

module Cmd.Inputs (readTimeRowsFromCsv) where

import Control.Monad.Except (ExceptT(..), lift)
import qualified Data.ByteString.Lazy as BL
import Data.Csv (Header, decodeByName)
import Data.Vector (Vector)
import Flight.Track.Time (TimeRow(..))
import Flight.Comp (AlignFile(..))

readTimeRowsFromCsv :: AlignFile
                    -> ExceptT String IO (Header, Vector TimeRow)
readTimeRowsFromCsv (AlignFile csvPath) = do
    contents <- lift $ BL.readFile csvPath
    ExceptT . return $ decodeByName contents
