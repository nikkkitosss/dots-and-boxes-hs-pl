# 🎮 Dots & Boxes — Haskell + Prolog

A classic pen-and-paper game with two backends: functional **Haskell** and logic-based **SWI-Prolog**. Frontend is plain HTML/JS.

## 📁 Structure
```
.
├── frontend/           # index.html — open in browser
├── haskell-backend/    # Scotty HTTP server, port 3000
└── prolog-backend/     # SWI-Prolog HTTP server, port 3001
```

## 🚀 Running

### 1. Haskell backend (port 3000)
```bash
cd haskell-backend && cabal run
```
> Requires: [GHC + Cabal](https://www.haskell.org/ghcup/)

### 2. Prolog backend (port 3001)
```bash
cd prolog-backend && swipl -g "server(3001)" prolog-server.pl
```
> Requires: [SWI-Prolog](https://www.swi-prolog.org/)

### 3. Frontend
Open `frontend/index.html` in your browser and pick a backend in the top-right corner.

> ⚠️ Both backends can run simultaneously on different ports.

## 🎯 How to Play
1. Enter player names and choose a grid size (2×2 — 5×5)
2. Click **NEW GAME**
3. Take turns clicking edges between dots
4. Closing a box captures it and grants an extra turn
5. Most boxes wins