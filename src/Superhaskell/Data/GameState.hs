{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}
{-# LANGUAGE GADTs          #-}
module Superhaskell.Data.GameState (
    GameState(..), entitiesAt, entitiesAtInGroup, toRenderList
  , GenState(..), initialGenState -- TODO remove initialGenState
  , CollisionGroup(..), collidesWith
  , IsEntity(..), Entity, Entities
) where

import           Control.DeepSeq
import           Data.Fixed
import           Data.Maybe
import           GHC.Generics
import           Linear.V2                    (V2 (..))
import           Superhaskell.Data.Entities
import           Superhaskell.Data.InputState
import           Superhaskell.Data.RenderList
import           Superhaskell.Math

class (Show e, NFData e) => IsEntity e where
  eTick :: InputState -> GameState -> Id -> e -> (GameState, e)
  eRender :: GameState -> Id -> e -> KeyFrames
  eCollide :: IsEntity o => Id -> o -> GameState -> Id -> e -> (GameState, e)
  eCollisionGroup :: e -> CollisionGroup
  eBox :: e -> Box
  eWrap :: e -> Entity

  eTick _ gs _ e = (gs, e)
  eRender _ _ _ = []
  eCollide _ _ gs _ e = (gs, e)
  eCollisionGroup _ = NilCGroup
  eBox _ = Box (V2 0 0) (V2 0 0)
  eWrap = Entity

data Entity where
  Entity :: IsEntity e => e -> Entity

instance Show Entity where
  show (Entity e) = "(Entity $ " ++ show e ++ ")"

instance NFData Entity where
  rnf (Entity e) = rnf e

-- Urgh newtype wrappers.
instance IsEntity Entity where
  eTick is gs eid (Entity e) = let (gs', e') = eTick is gs eid e in (gs', Entity e')
  eRender gs eid (Entity e) = eRender gs eid e
  eCollide oid other gs eid (Entity e) = let (gs', e') = eCollide oid other gs eid e in (gs', Entity e')
  eCollisionGroup (Entity e) = eCollisionGroup e
  eBox (Entity e) = eBox e
  eWrap = id

type Entities = EntitiesC Entity

data CollisionGroup = PlayerCGroup
                    | SceneryCGroup
                    | BackgroundCGroup
                    | NilCGroup
                    deriving (Show, Generic, NFData, Eq, Enum, Bounded, Ord)

collidesWith :: CollisionGroup -> CollisionGroup -> Bool
collidesWith PlayerCGroup SceneryCGroup = True
collidesWith _ _ = False

data GameState = GameState { gsEntities :: Entities
                           , gsRunning  :: Bool
                           , gsGenState :: GenState
                           , gsViewPort :: Box
                           }
               deriving (Show, Generic, NFData)

data GenState = GenState { genBound     :: Float
                         }
               deriving (Show, Generic, NFData)

-- Stores information that the generation component needs across iterations
-- Such as up to where it already generated the world
initialGenState :: GenState
initialGenState = GenState { genBound = 0.0
                           }

entitiesAt :: V2 Float -> GameState -> [Entity]
entitiesAt p gs = foldr (\e es -> if boxContains p (eBox e) then e:es else es) [] (gsEntities gs)

entitiesAtInGroup :: V2 Float -> CollisionGroup -> GameState -> [Entity]
entitiesAtInGroup p g gs = filter ((== g) . eCollisionGroup) (entitiesAt p gs)

toRenderList :: Float -> GameState -> RenderList
toRenderList time gs = concatMap (applyAnimation time) $ mapWithId (eRender gs) (gsEntities gs)

applyAnimation :: Float -> KeyFrames -> RenderList
applyAnimation time kfs = maybe [] fst $ safeHead $ dropWhile (\(_, end) -> end < offset) framesWithEnds
    where totalDuration = sum $ map kfDuration kfs
          offset = time `mod'` totalDuration
          framesWithEnds = zip (map kfRenderList kfs)
                               (tail $ scanl (+) 0 $ map kfDuration kfs) -- Drop the first (0)

safeHead :: [a] -> Maybe a
safeHead [] = Nothing
safeHead (x:xs) = Just x
