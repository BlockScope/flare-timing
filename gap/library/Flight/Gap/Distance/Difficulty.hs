module Flight.Gap.Distance.Difficulty
    ( SumOfDifficulty(..)
    , Difficulty(..)
    , gradeDifficulty
    ) where

import Data.Ratio ((%))
import Data.Maybe (catMaybes)
import Data.List (sort, sortOn, nub)
import qualified Data.Map.Strict as Map
import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.UnitsOfMeasure (u)
import Data.UnitsOfMeasure.Internal (Quantity(..))
import GHC.Generics (Generic)

import Flight.Units ()
import Flight.Gap.Distance.Pilot (PilotDistance(..))
import Flight.Gap.Distance.Stop (FlownMax(..))
import Flight.Gap.Distance.Relative (RelativeDifficulty(..))
import Flight.Gap.Fraction.Difficulty (DifficultyFraction(..))
import Flight.Gap.Distance.Chunk
    ( IxChunk(..)
    , Lookahead(..)
    , Chunk(..)
    , ChunkLandings(..)
    , ChunkRelativeDifficulty(..)
    , ChunkDifficultyFraction(..)
    , toChunk
    , toIxChunk
    , lookahead
    , chunkLandouts
    , sumLandouts
    , collectDowns
    )
import Flight.Gap.Pilots (Pilot)

-- | The sum of all chunk difficulties.
newtype SumOfDifficulty = SumOfDifficulty Integer
    deriving (Eq, Ord, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data Difficulty =
    Difficulty
        { sumOf :: SumOfDifficulty
        -- ^ The sum of the downward counts.
        , startChunk :: [(IxChunk, Chunk (Quantity Double [u| km |]))]
        -- ^ The task distance to the start of this chunk.
        , endChunk :: [(IxChunk, Chunk (Quantity Double [u| km |]))]
        -- ^ The task distance to the end of this chunk.
        , endAhead :: [(IxChunk, Chunk (Quantity Double [u| km |]))]
        -- ^ The task distance to the end of lookahead chunk.
        , downward :: [ChunkLandings]
        -- ^ The number on their way down for a landing between this chunk and
        -- the lookahead offset.
        , relative :: [ChunkRelativeDifficulty]
        -- ^ The relative difficulty of each chunk.
        , fractional :: [ChunkDifficultyFraction]
        -- ^ The fractional difficulty of each chunk.
        }
    deriving (Eq, Ord, Show, Generic, ToJSON, FromJSON)

-- | For a list of distances flown by pilots, works out the distance difficulty
-- fraction for each pilot. A consensus on difficulty is attained by counting
-- those who landout in sections of the course. A section is drawn from the
-- chunk of landing and then so many chunks further along the course. How far
-- to look ahead depends on the task and the number of landouts.
gradeDifficulty
    :: FlownMax (Quantity Double [u| km |])
    -> [Pilot]
    -> [PilotDistance (Quantity Double [u| km |])]
    -> Difficulty
gradeDifficulty best@(FlownMax bd) pilots landings =
    Difficulty
        { sumOf = SumOfDifficulty sumOfDiff
        , startChunk = zip ys nubStarts
        , endChunk = zip ys nubEnds
        , endAhead = zip ys nubEndsAhead
        , downward = collectDowns pilots xs downList
        , relative =
            catMaybes $
            (\y -> do
                rel <- Map.lookup y relMap
                let f = uncurry ChunkRelativeDifficulty . fmap (RelativeDifficulty . toRational)
                return $ f (y, rel))
            <$> ys
        , fractional =
            catMaybes $
            (\y -> do
                frac <- Map.lookup y fracMap
                let f = uncurry ChunkDifficultyFraction . fmap (DifficultyFraction . toRational)
                return $ f (y, frac))
            <$> ys
        }
    where
        -- When pilots fly away from goal looking for lift but land out they
        -- can end up with a negative distance along the course. We'll zero
        -- these landings before starting on course difficulty.
        xs = (\(PilotDistance d) -> PilotDistance $ max d [u| 0 km |]) <$> landings

        ahead@(Lookahead n) = lookahead best xs
        gd = PilotDistance bd
        gIx = toIxChunk gd
        ix0 = toIxChunk (PilotDistance [u| 0 km |])

        ixs = [ix0 .. gIx]

        -- The following snippets labelled A & B are from scoring tasks #1 & #7
        -- from the QuestAir Open competition, 2016-05-07 to 2016-05-13,
        -- Groveland, Florida, USA.
        -- https://airtribune.com/2016-quest-air-open-national-championships/results

        -- The indices of the chunks in which pilots landed out. More than one
        -- pilot can landout in the same chunk.
        zs = chunkLandouts xs

        ys :: [IxChunk]
        ys = nub zs

        starts = toChunk <$> ys
        nubStarts = nub starts

        ends = toChunk . (\(IxChunk x) -> IxChunk $ x + 1) <$> ys
        nubEnds = nub ends

        endsAhead = toChunk . (\(IxChunk x) -> IxChunk $ x + n + 1) <$> ys
        nubEndsAhead = nub endsAhead

        ns :: [(IxChunk, Int)]
        ns = sumLandouts zs

        vMap :: Map.Map IxChunk Int
        vMap = Map.fromList ns

        -- Sum the number of landouts in the next so many chunks to lookahead.
        downList = (\y -> (y, sumMap ahead vMap y)) <$> ys
        downMap = Map.fromList downList

        listOfAll = (\j -> (j, sumMap ahead vMap j)) <$> ixs

        listOfDiffs = scanl1 (\(_, b) (c, d) -> (c, b + d)) listOfAll

        lookaheadMap :: Map.Map IxChunk Integer
        lookaheadMap = toInteger <$> Map.fromList listOfAll

        sumOfDiff :: Integer
        sumOfDiff = toInteger . sum . take 1 . reverse . sort $ snd <$> listOfDiffs

        relativeDiffMap :: Map.Map IxChunk Double
        relativeDiffMap = (\d -> fromRational $ d % (2 * sumOfDiff)) <$> lookaheadMap

        relList = sortOn fst $ Map.toList relativeDiffMap
        sumRels = scanl1 (\(_, b) (c, d) -> (c, b + d)) relList

        fracMap = Map.intersection (Map.fromList sumRels) downMap

        relMap = Map.intersection (Map.fromList relList) downMap

sumMap :: Lookahead -> Map.Map IxChunk Int -> IxChunk -> Int
sumMap (Lookahead n) nMap (IxChunk ic) =
    sum $ Map.elems filtered
    where
        -- NOTE: If n = 1, we want to look 100m ahead. We want to look
        -- in chunk ic but not in chunk ic + 1.
        kMin = ic
        kMax = ic + n

        filtered =
            Map.filterWithKey
                (\(IxChunk k) _ -> kMin <= k && k < kMax)
                nMap
