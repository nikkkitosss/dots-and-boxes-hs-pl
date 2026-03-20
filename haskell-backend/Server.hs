{-# LANGUAGE OverloadedStrings #-}

-- ============================================================
--  Dots & Boxes — Haskell Backend (Scotty)
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
import           Data.Maybe                   (fromMaybe, listToMaybe)
import           Data.List                    (maximumBy, minimumBy, sortBy)
import           Data.Ord                     (comparing, Down(..))
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

-- Режим гри
data GameMode
  = HumanHuman
  | HumanAI    -- P1=Human, P2=AI
  | AIHuman    -- P1=AI,    P2=Human
  | AIAI
  deriving (Eq, Show)

-- Рівень складності ↔ глибина мінімаксу (в напів-ходах)
data Difficulty = Easy | Medium | Hard | Expert
  deriving (Eq, Show)

diffDepth :: Difficulty -> Int
diffDepth Easy   = 2
diffDepth Medium = 4
diffDepth Hard   = 6
diffDepth Expert = 8

diffName :: Difficulty -> String
diffName Easy   = "Легкий (2 нп)"
diffName Medium = "Середній (4 нп)"
diffName Hard   = "Важкий (6 нп)"
diffName Expert = "Експерт (8 нп)"

data GameState = GameState
  { gsSize       :: Size
  , gsLines      :: Set.Set Line
  , gsOwners     :: Map.Map (Row, Col) Player
  , gsScores     :: (Int, Int)
  , gsCurrent    :: Player
  , gsNames      :: (String, String)
  , gsMoveCount  :: Int
  , gsOver       :: Bool
  , gsWinner     :: Maybe String
  -- нові поля
  , gsMode       :: GameMode
  , gsDifficulty :: Difficulty
  , gsLastAI     :: Maybe Line   -- останній хід AI для UI
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

modeStr :: GameMode -> String
modeStr HumanHuman = "human-human"
modeStr HumanAI    = "human-ai"
modeStr AIHuman    = "ai-human"
modeStr AIAI       = "ai-ai"

instance ToJSON GameState where
  toJSON gs = object
    [ "size"       .= gsSize gs
    , "lines"      .= map lineVal  (Set.toList (gsLines gs))
    , "owners"     .= map ownerVal (Map.toList (gsOwners gs))
    , "score1"     .= fst (gsScores gs)
    , "score2"     .= snd (gsScores gs)
    , "current"    .= playerInt (gsCurrent gs)
    , "name1"      .= fst (gsNames gs)
    , "name2"      .= snd (gsNames gs)
    , "moveCount"  .= gsMoveCount gs
    , "over"       .= gsOver gs
    , "winner"     .= gsWinner gs
    , "mode"       .= modeStr (gsMode gs)
    , "difficulty" .= diffName (gsDifficulty gs)
    , "depth"      .= diffDepth (gsDifficulty gs)
    , "lastAI"     .= fmap lineVal (gsLastAI gs)
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

parseDifficulty :: String -> Difficulty
parseDifficulty "easy"   = Easy
parseDifficulty "medium" = Medium
parseDifficulty "hard"   = Hard
parseDifficulty "expert" = Expert
parseDifficulty _        = Medium

parseMode :: String -> GameMode
parseMode "human-human" = HumanHuman
parseMode "human-ai"    = HumanAI
parseMode "ai-human"    = AIHuman
parseMode "ai-ai"       = AIAI
parseMode _             = HumanHuman

-- ============================================================
-- ІГРОВА ЛОГІКА
-- ============================================================

initGame :: Size -> String -> String -> GameMode -> Difficulty -> GameState
initGame n n1 n2 mode diff = GameState
  { gsSize       = n
  , gsLines      = Set.empty
  , gsOwners     = Map.empty
  , gsScores     = (0, 0)
  , gsCurrent    = P1
  , gsNames      = (n1, n2)
  , gsMoveCount  = 0
  , gsOver       = False
  , gsWinner     = Nothing
  , gsMode       = mode
  , gsDifficulty = diff
  , gsLastAI     = Nothing
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

allMoves :: GameState -> [Line]
allMoves gs =
  [ Line H r c | r <- [0..n], c <- [0..n-1], Set.notMember (Line H r c) drawn ] ++
  [ Line V r c | r <- [0..n-1], c <- [0..n], Set.notMember (Line V r c) drawn ]
  where
    n     = gsSize gs
    drawn = gsLines gs

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
                , gsMoveCount = gsMoveCount gs + 1
                , gsLastAI    = Nothing }
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


sidesOfBox :: Set.Set Line -> (Row, Col) -> Int
sidesOfBox lns (r, c) =
  length $ filter (`Set.member` lns)
    [Line H r c, Line H (r+1) c, Line V r c, Line V r (c+1)]

completesBox :: GameState -> Line -> Bool
completesBox gs ln =
  any (\rc -> sidesOfBox (gsLines gs) rc == 3) (adjBoxes (gsSize gs) ln)


opensBox :: GameState -> Line -> Bool
opensBox gs ln =
  let lns' = Set.insert ln (gsLines gs)
  in any (\rc -> sidesOfBox lns' rc == 3) (adjBoxes (gsSize gs) ln)

clpFilterMoves :: GameState -> [Line] -> [Line]
clpFilterMoves gs moves =
  let capturing = filter (completesBox gs) moves
      safe      = filter (not . opensBox gs) moves
  in if not (null capturing)
       then capturing          -- Constraint-1: захоплюй
       else if not (null safe)
         then safe             -- Constraint-2: безпечні
         else moves            -- Constraint-3: немає вибору

-- ============================================================
-- МІНІМАКС З АЛЬФА-БЕТОЮ
-- ============================================================

-- Оцінка позиції для P1 (>0 = добре для P1, <0 = добре для P2)
evaluate :: GameState -> Int
evaluate gs = fst (gsScores gs) - snd (gsScores gs)

-- Мінімакс з альфа-бета відсіканням
-- maximizing = True якщо зараз хід P1
minimax :: GameState -> Int -> Int -> Int -> Bool -> Int
minimax gs depth alpha beta maximizing
  | depth == 0 || gsOver gs = evaluate gs
  | maximizing =
      let moves = clpFilterMoves gs (allMoves gs)
          go [] a _    = a
          go (m:ms) a b =
            case makeMove gs m of
              Left  _   -> go ms a b
              Right gs' ->
                -- якщо P1 ще ходить (захопив клітинку) → залишаємось maximizing
                let stillMax = gsCurrent gs' == P1
                    val = minimax gs' (depth-1) a b stillMax
                    a'  = max a val
                in if a' >= b then a'   -- beta cut-off
                   else go ms a' b
      in go moves alpha beta
  | otherwise =
      let moves = clpFilterMoves gs (allMoves gs)
          go [] _ b    = b
          go (m:ms) a b =
            case makeMove gs m of
              Left  _   -> go ms a b
              Right gs' ->
                let stillMin = gsCurrent gs' == P2
                    val = minimax gs' (depth-1) a b (not stillMin)
                    b'  = min b val
                in if a >= b' then b'  -- alpha cut-off
                   else go ms a b'
      in go moves alpha beta

-- Вибір найкращого ходу для поточного гравця
bestMove :: GameState -> Maybe Line
bestMove gs
  | null moves = Nothing
  | otherwise  =
      let depth    = diffDepth (gsDifficulty gs)
          isMax    = gsCurrent gs == P1
          scored   = [ (m, scoreMove m) | m <- moves ]
          best     = if isMax
                       then maximumBy (comparing snd) scored
                       else minimumBy (comparing snd) scored
      in Just (fst best)
  where
    moves = clpFilterMoves gs (allMoves gs)
    scoreMove m = case makeMove gs m of
      Left  _   -> if gsCurrent gs == P1 then minBound else maxBound
      Right gs' ->
        let depth = diffDepth (gsDifficulty gs)
            isMax = gsCurrent gs == P1
            stillSame = gsCurrent gs' == gsCurrent gs
        in minimax gs' (depth - 1) minBound maxBound
             (if stillSame then isMax else not isMax)

-- Чи потрібен AI-хід зараз?
needsAI :: GameState -> Bool
needsAI gs = not (gsOver gs) && case gsMode gs of
  HumanHuman -> False
  HumanAI    -> gsCurrent gs == P2
  AIHuman    -> gsCurrent gs == P1
  AIAI       -> True

-- Виконати всі AI-ходи поспіль (для режиму AI-AI може бути кілька)
runAI :: GameState -> IO GameState
runAI gs
  | not (needsAI gs) = return gs
  | otherwise = case bestMove gs of
      Nothing -> return gs
      Just ln ->
        case makeMove gs ln of
          Left  _   -> return gs
          Right gs' -> do
            let gs'' = gs' { gsLastAI = Just ln }
            runAI gs''

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
  ref <- newIORef (initGame 3 "Гравець 1" "Гравець 2" HumanHuman Medium)
  putStrLn "Haskell backend -> http://localhost:3000"

  scotty 3000 $ do

    middleware corsMiddleware

    options (regex ".*") $ do
      status status204

    get "/state" $ do
      gs <- liftIO (readIORef ref)
      json gs

    -- POST /new  { size, name1, name2, mode, difficulty }
    post "/new" $ do
      body <- jsonData :: ActionM Value
      let sz   = fromMaybe 3              (getInt "size"       body)
          n1   = fromMaybe "Гравець 1"    (getStr "name1"      body)
          n2   = fromMaybe "Гравець 2"    (getStr "name2"      body)
          mode = parseMode  $ fromMaybe "human-human" (getStr "mode"       body)
          diff = parseDifficulty $ fromMaybe "medium"       (getStr "difficulty" body)
          gs0  = initGame sz n1 n2 mode diff
      gs1 <- liftIO (runAI gs0)
      liftIO (writeIORef ref gs1)
      json gs1

    -- POST /move { dir, row, col }
    post "/move" $ do
      body <- jsonData :: ActionM Value
      let ds  = fromMaybe "H" (getStr "dir" body)
          row = fromMaybe 0   (getInt "row" body)
          col = fromMaybe 0   (getInt "col" body)
          dir = if map toUpper ds == "V" then V else H
      gs <- liftIO (readIORef ref)
      -- перевірка: чи зараз хід людини
      let humanTurn = case gsMode gs of
            HumanHuman -> True
            HumanAI    -> gsCurrent gs == P1
            AIHuman    -> gsCurrent gs == P2
            AIAI       -> False
      if not humanTurn
        then do
          status status400
          json (object ["error" .= ("Зараз хід комп'ютера" :: String)])
        else
          case makeMove gs (Line dir row col) of
            Left err  -> do
              status status400
              json (object ["error" .= err])
            Right gs' -> do
              gs'' <- liftIO (runAI gs')
              liftIO (writeIORef ref gs'')
              json gs''

    -- POST /ai  — примусовий AI-хід (для кнопки "наступний хід AI")
    post "/ai" $ do
      gs <- liftIO (readIORef ref)
      case bestMove gs of
        Nothing -> json gs
        Just ln ->
          case makeMove gs ln of
            Left  _   -> json gs
            Right gs' -> do
              let gs'' = gs' { gsLastAI = Just ln }
              gs3 <- liftIO (runAI gs'')
              liftIO (writeIORef ref gs3)
              json gs3