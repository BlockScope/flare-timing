{-# lANGUAGE PatternSynonyms #-}
{-# lANGUAGE ViewPatterns #-}
{-# lANGUAGE TypeSynonymInstances #-}
{-# lANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Flight.Ratio (pattern (:%), isNormal, isFoldNormal) where

import Data.Ratio ((%), numerator, denominator)

-- | SEE: http://stackoverflow.com/questions/33325370/why-cant-i-pattern-match-against-a-ratio-in-haskell
pattern num :% denom <- (\x -> (numerator x, denominator x) -> (num, denom))

class Num a => Normal a where
    isNormal :: a -> Bool

class (Normal b, Foldable m) => FoldNormal m a b where
    isFoldNormal :: (a -> b -> b) -> b -> m a -> Bool
    isFoldNormal f y xs = isNormal $ foldr f y xs

instance Normal Rational where
    isNormal x = x >= (0 % 1) && x <= (1 % 1)

instance (Normal b) => FoldNormal [] a b where
    isFoldNormal f y xs = isNormal $ foldr f y xs
