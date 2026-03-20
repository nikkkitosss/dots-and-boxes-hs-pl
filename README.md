# 🎮 Dots & Boxes — Haskell + Prolog

A classic pen-and-paper game with two interchangeable backends: functional **Haskell** and logic-based **SWI-Prolog**. Frontend is plain HTML/JS with no dependencies.

## 📁 Structure

```
.
├── start.sh                  # launches everything at once
├── frontend/
│   └── index.html            # open in browser
├── haskell-backend/
│   ├── Server.hs             # Scotty HTTP server, port 3000
│   └── dots-and-boxes.cabal
└── prolog-backend/
    ├── prolog-server.pl      # SWI-Prolog HTTP server, port 3002
    └── cors-proxy.js         # Node.js CORS proxy, port 3001
```

## 🚀 Running

### Automatic (recommended)

```bash
chmod +x start.sh
./start.sh
```

Starts Haskell, Prolog, CORS proxy and opens the browser. `Ctrl+C` stops everything.

### Manual (3 terminals)

```bash
# Terminal 1 — Haskell (port 3000)
cd haskell-backend && cabal run

# Terminal 2 — Prolog (port 3002)
cd prolog-backend && swipl -g "server(3002),thread_get_message(stop)" prolog-server.pl

# Terminal 3 — CORS proxy (port 3001 → 3002)
cd prolog-backend && node cors-proxy.js
```

Then open `frontend/index.html` in your browser.

**Requirements:** [GHC + Cabal](https://www.haskell.org/ghcup/) · [SWI-Prolog](https://www.swi-prolog.org/) · [Node.js](https://nodejs.org/)

## 🎯 How to Play

1. Enter player names and choose a grid size (2×2 — 5×5)
2. Select a **game mode** and **difficulty**
3. Click **NEW GAME**
4. Take turns clicking edges between dots
5. Closing a box captures it and grants an extra turn
6. The player with the most boxes wins

## 🤖 Game Modes

| Mode | Description |
|------|-------------|
| Human–Human | Both players are human |
| Human–Computer | P1 is human, P2 is computer |
| Computer–Human | P1 is computer, P2 is human |
| Computer–Computer | Both players are computer, game runs automatically |

## 🧠 Computer Algorithm

### Minimax with Alpha-Beta Pruning (Haskell)

Classic minimax search with alpha-beta pruning. Search depth is controlled by difficulty:

| Level | Plies | Description |
|-------|-------|-------------|
| Easy | 2 | Looks 2 half-moves ahead |
| Medium | 4 | Looks 4 half-moves ahead |
| Hard | 6 | Looks 6 half-moves ahead |
| Expert | 8 | Looks 8 half-moves ahead |

A **ply** is one move by either player. Alpha-beta pruning discards branches where `α ≥ β`, significantly reducing the search tree.

### CLP Move Filtering (both backends)

Before running minimax, the move domain is narrowed through a **constraint hierarchy** — an implementation of CLP(FD) ideas:

```
Constraint-1 (CAPTURING): ∃ move that captures a box → domain = {capturing_moves}
Constraint-2 (SAFE):      no capturing → ∃ safe move → domain = {safe_moves}
Constraint-3 (ALL):       no safe moves → domain = all_valid_moves
```

A **capturing move** completes a box (3 sides → 4). A **safe move** does not give the opponent a free box (does not create a 3-sided cell). This drastically reduces branching factor and encodes the core Dots & Boxes strategy.

### Prolog Backend

Uses `all_valid_moves/1` with `between/3` as a generator and `include/3` for filtering. Strategy is driven entirely by the CLP filter — no recursive minimax (avoided due to conflicts between `assert/retract` and save/restore state).

## 🔌 API

Both backends expose the same REST API:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/state` | GET | Current game state |
| `/new` | POST | New game `{size, name1, name2, mode, difficulty}` |
| `/move` | POST | Human move `{dir, row, col}` |
| `/ai` | POST | Computer move |

### Response example

```json
{
  "size": 3,
  "lines": [{"dir": "H", "row": 0, "col": 1}],
  "owners": [{"row": 0, "col": 0, "player": 1}],
  "score1": 2, "score2": 1,
  "current": 1,
  "name1": "Alice", "name2": "Bob",
  "moveCount": 5,
  "over": false, "winner": null,
  "mode": "human-ai",
  "difficulty": "Hard (6 plies)",
  "depth": 6,
  "lastAI": {"dir": "V", "row": 1, "col": 2}
}
```