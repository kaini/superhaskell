-- +------+-----------+-----+
--        |           |     |
--        |           |     |
--  prune |  viewport | gen |
--        |           |     |
--        |           |     |
-- +------+-----------+-----+
{-# LANGUAGE OverloadedStrings #-}
module Superhaskell.Generation (updateWorld) where

import           Control.Lens
import           Control.Monad.Random
import           Data.Foldable
import           Data.Function                  (on)
import           Linear.V2
import           Superhaskell.Data.Entities
import           Superhaskell.Data.GameState
import           Superhaskell.Entities.Platform
import           Superhaskell.Math

updateWorld :: RandomGen g => GameState -> Rand g GameState
updateWorld gs@GameState{gsEntities = es, gsViewPort = vp@(Box (V2 vpl _) _)} = do
  -- TODO handle player here
  let lastPlatformY = (^._y) $ maximumBy (compare `on` (^._x)) $ fmap (rightTop . eBox) (gsEntities gs)
  generated <- generate vp lastPlatformY (gsGenState gs)
  let nBound = maximum $ genBound (gsGenState gs):map ((^._x) . rightBottom . eBox) generated
  let pruned = prune vpl es
  let nGenState = (gsGenState gs) { genBound = nBound }
  let nes = appendOthers generated pruned
  return gs{ gsEntities = nes
           , gsGenState = nGenState }

prune :: Float -> Entities -> Entities
prune vpleft = filterOthers (not . isLeftOfViewport vpleft)

-- TODO correct height
-- We partition the world (horizontally) into partitionWidth wide sections (at least 1)
-- In each partition we generate a single platform
generate :: RandomGen g => Box -> Float -> GenState -> Rand g [Entity]
generate _vp@(Box (V2 l _) (V2 w h)) lastY _gs@GenState{genBound = bound}
  | bound >= (l+w+genAhead) = return []
  | otherwise = do
    let parts = partition bound (l+w+genAhead)
    mapM (\p -> eWrap <$> generatePlatform (lastY-h/4, lastY+h/8) p) parts

partition :: Float -> Float -> [(Float, Float)]
partition l r = zip parts (tail' parts)
  where w = r - l
        pc = floor(w / partitionWidth)
        parts = scanl (+) l (replicate pc partitionWidth)

generatePlatform :: RandomGen g => (Float, Float) -> (Float, Float) -> Rand g Platform
generatePlatform (b, t) (l, r)= do
    pos_x <- getRandomR (l, r-3)
    pos_y <- getRandomR (b, t)
    let p = platform (V2 pos_x pos_y) 3
    return p

isLeftOfViewport :: IsEntity e => Float -> e -> Bool
isLeftOfViewport leftBound e = boxRight <= leftBound
  where boxRight = rightBottom (eBox e) ^._x

partitionWidth :: Float
partitionWidth = 4

genAhead :: Float
genAhead = 8

tail' :: [a] -> [a]
tail' [] = []
tail' (_:xs) = xs
