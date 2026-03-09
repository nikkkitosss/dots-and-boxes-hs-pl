{-# LANGUAGE OverloadedStrings #-}

-- ============================================================
--  Dots & Boxes — Haskell Backend (Scotty)
--  Порт: 3000
--
--  ЗАПУСК:
--    cabal run
-- ============================================================

module Main where

import           Web.Scotty
import           Data.Aeson                    (ToJSON(..), Value(..), object, (.=))
import qualified Data.Aeson.Key               as Key
import qualified Data.Aeson.KeyMap            as KM
import qualified Data.Map.Strict              as Map
import qualified Data.Set                     as Set
import           Data.IORef
import           Control.Monad.IO.Class       (liftIO)
import qualified Data.Text                    as T
import           Data.Char                    (toUpper)
import           Data.Maybe                   (fromMaybe)
import           Network.HTTP.Types.Status    (status204, status400)
import           Network.Wai                  (Middleware, mapResponseHeaders)

-- ============================================================
-- ТИПИ
-- ============================================================

type Row  = Int
type Col  = Int
type Size = Int

data Dir    = H | V   deriving (Eq, Ord, Show)
data Player = P1 | P2 deriving (Eq, Ord, Show)
data Line   = Line Dir Row Col deriving (Eq, Ord, Show)

data GameState = GameState
  { gsSize      :: Size
  , gsLines     :: Set.Set Line
  , gsOwners    :: Map.Map (Row, Col) Player
  , gsScores    :: (Int, Int)
  , gsCurrent   :: Player
  , gsNames     :: (String, String)
  , gsMoveCount :: Int
  , gsOver      :: Bool
  , gsWinner    :: Maybe String
  }

-- ============================================================
-- JSON
-- ============================================================

playerInt :: Player -> Int
playerInt P1 = 1
playerInt P2 = 2

dirStr :: Dir -> String
dirStr H = "H"
dirStr V = "V"

instance ToJSON GameState where
  toJSON gs = object
    [ "size"      .= gsSize gs
    , "lines"     .= map lineVal  (Set.toList (gsLines gs))
    , "owners"    .= map ownerVal (Map.toList (gsOwners gs))
    , "score1"    .= fst (gsScores gs)
    , "score2"    .= snd (gsScores gs)
    , "current"   .= playerInt (gsCurrent gs)
    , "name1"     .= fst (gsNames gs)
    , "name2"     .= snd (gsNames gs)
    , "moveCount" .= gsMoveCount gs
    , "over"      .= gsOver gs
    , "winner"    .= gsWinner gs
    ]
    where
      lineVal  (Line d r c) = object ["dir" .= dirStr d, "row" .= r, "col" .= c]
      ownerVal ((r, c), p)  = object ["row" .= r, "col" .= c, "player" .= playerInt p]

-- ============================================================
-- JSON PARSING
-- ============================================================

getStr :: T.Text -> Value -> Maybe String
getStr k (Object o) = case KM.lookup (Key.fromText k) o of
  Just (String s) -> Just (T.unpack s)
  _               -> Nothing
getStr _ _ = Nothing

getInt :: T.Text -> Value -> Maybe Int
getInt k (Object o) = case KM.lookup (Key.fromText k) o of
  Just (Number n) -> Just (round n)
  _               -> Nothing
getInt _ _ = Nothing

-- ============================================================
-- ІГРОВА ЛОГІКА
-- ============================================================

initGame :: Size -> String -> String -> GameState
initGame n n1 n2 = GameState
  { gsSize      = n
  , gsLines     = Set.empty
  , gsOwners    = Map.empty
  , gsScores    = (0, 0)
  , gsCurrent   = P1
  , gsNames     = (n1, n2)
  , gsMoveCount = 0
  , gsOver      = False
  , gsWinner    = Nothing
  }

otherPlayer :: Player -> Player
otherPlayer P1 = P2
otherPlayer P2 = P1

isValid :: GameState -> Line -> Bool
isValid gs (Line dir r c) = inBounds && notDrawn
  where
    n        = gsSize gs
    inBounds = case dir of
      H -> r >= 0 && r <= n && c >= 0 && c < n
      V -> r >= 0 && r <  n && c >= 0 && c <= n
    notDrawn = Set.notMember (Line dir r c) (gsLines gs)

boxDone :: Set.Set Line -> (Row, Col) -> Bool
boxDone lns (r, c) = all (`Set.member` lns)
  [Line H r c, Line H (r + 1) c, Line V r c, Line V r (c + 1)]

adjBoxes :: Size -> Line -> [(Row, Col)]
adjBoxes n (Line H r c) = filter ok [(r, c), (r - 1, c)]
  where ok (br, bc) = br >= 0 && br < n && bc >= 0 && bc < n
adjBoxes n (Line V r c) = filter ok [(r, c), (r, c - 1)]
  where ok (br, bc) = br >= 0 && br < n && bc >= 0 && bc < n

newBoxes :: GameState -> Line -> [(Row, Col)]
newBoxes gs ln =
  [ rc
  | rc <- adjBoxes (gsSize gs) ln
  , boxDone (gsLines gs) rc
  , Map.notMember rc (gsOwners gs)
  ]

addScore :: Player -> Int -> GameState -> GameState
addScore _  0 gs = gs
addScore P1 n gs = gs { gsScores = (fst (gsScores gs) + n, snd (gsScores gs)) }
addScore P2 n gs = gs { gsScores = (fst (gsScores gs), snd (gsScores gs) + n) }

makeMove :: GameState -> Line -> Either String GameState
makeMove gs _  | gsOver gs           = Left "Гра завершена"
makeMove gs ln | not (isValid gs ln) = Left "Невалідний хід"
makeMove gs ln =
  let p    = gsCurrent gs
      gs1  = gs { gsLines     = Set.insert ln (gsLines gs)
                , gsMoveCount = gsMoveCount gs + 1 }
      nb   = newBoxes gs1 ln
      cap  = length nb
      gs2  = foldr (\rc s -> s { gsOwners = Map.insert rc p (gsOwners s) }) gs1 nb
      gs3  = addScore p cap gs2
      gs4  = if cap > 0 then gs3 else gs3 { gsCurrent = otherPlayer p }
      over = Map.size (gsOwners gs4) == gsSize gs4 ^ 2
      win  = if over then Just (computeWinner gs4) else Nothing
  in Right gs4 { gsOver = over, gsWinner = win }

computeWinner :: GameState -> String
computeWinner gs
  | s1 > s2   = fst (gsNames gs) ++ " перемагає!"
  | s2 > s1   = snd (gsNames gs) ++ " перемагає!"
  | otherwise = "Нічия!"
  where (s1, s2) = gsScores gs

-- ============================================================
-- CORS MIDDLEWARE
-- ============================================================

corsMiddleware :: Middleware
corsMiddleware app req respond =
  app req $ \res ->
    respond $ mapResponseHeaders
      ( [ ("Access-Control-Allow-Origin",  "*")
        , ("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        , ("Access-Control-Allow-Headers", "Content-Type")
        ] ++) res

-- ============================================================
-- SERVER
-- ============================================================

main :: IO ()
main = do
  ref <- newIORef (initGame 3 "Гравець 1" "Гравець 2")
  putStrLn "Haskell backend -> http://localhost:3000"

  scotty 3000 $ do

    middleware corsMiddleware

    options (regex ".*") $ do
      status status204

    get "/state" $ do
      gs <- liftIO (readIORef ref)
      json gs

    post "/new" $ do
      body <- jsonData :: ActionM Value
      let sz = fromMaybe 3           (getInt "size"  body)
          n1 = fromMaybe "Гравець 1" (getStr "name1" body)
          n2 = fromMaybe "Гравець 2" (getStr "name2" body)
      liftIO (writeIORef ref (initGame sz n1 n2))
      gs <- liftIO (readIORef ref)
      json gs

    post "/move" $ do
      body <- jsonData :: ActionM Value
      let ds  = fromMaybe "H" (getStr "dir" body)
          row = fromMaybe 0   (getInt "row" body)
          col = fromMaybe 0   (getInt "col" body)
          dir = if map toUpper ds == "V" then V else H
      gs <- liftIO (readIORef ref)
      case makeMove gs (Line dir row col) of
        Left err  -> do
          status status400
          json (object ["error" .= err])
        Right gs' -> do
          liftIO (writeIORef ref gs')
          json gs'