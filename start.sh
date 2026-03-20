#!/bin/bash
# ============================================================
#  Dots & Boxes — запуск всього одним скриптом
#  ./start.sh
# ============================================================

ROOT="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[START]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()  { echo -e "${RED}[ERR]${NC}   $1"; }

cleanup() {
    echo ""
    log "Зупиняємо сервери..."
    [ -n "$PID_HASKELL" ] && kill "$PID_HASKELL" 2>/dev/null
    [ -n "$PID_PROLOG"  ] && kill "$PID_PROLOG"  2>/dev/null
    [ -n "$PID_PROXY"   ] && kill "$PID_PROXY"   2>/dev/null
    wait 2>/dev/null
    log "Готово."
    exit 0
}
trap cleanup INT TERM

# Чекаємо поки порт відповідає (макс 15 сек)
wait_port() {
    local port=$1
    local name=$2
    for i in $(seq 1 15); do
        if nc -z 127.0.0.1 "$port" 2>/dev/null; then
            log "$name :$port готовий"
            return 0
        fi
        sleep 1
    done
    err "$name :$port не відповів за 15 сек"
    return 1
}

# ── Перевірка інструментів ──────────────────────────────────
HAS_CABAL=0; HAS_SWIPL=0; HAS_NODE=0
command -v cabal &>/dev/null && HAS_CABAL=1 || warn "cabal не знайдено — Haskell бекенд пропущено"
command -v swipl &>/dev/null && HAS_SWIPL=1 || warn "swipl не знайдено  — Prolog бекенд пропущено"
command -v node  &>/dev/null && HAS_NODE=1  || warn "node не знайдено   — CORS proxy пропущено"

echo ""
echo "  ● dots & boxes — старт"
echo "  ─────────────────────────────────────"

PID_HASKELL=""; PID_PROLOG=""; PID_PROXY=""

# ── Haskell backend (порт 3000) ─────────────────────────────
if [ $HAS_CABAL -eq 1 ]; then
    log "Збираємо Haskell бекенд..."
    cd "$ROOT/haskell-backend"
    if cabal build -j 2>/tmp/dots_haskell_build.log; then
        cabal run >> /tmp/dots_haskell.log 2>&1 &
        PID_HASKELL=$!
        wait_port 3000 "Haskell" || { kill "$PID_HASKELL" 2>/dev/null; PID_HASKELL=""; }
    else
        err "Помилка збірки Haskell:"
        tail -5 /tmp/dots_haskell_build.log
    fi
fi

# ── Prolog backend (порт 3002) ──────────────────────────────
if [ $HAS_SWIPL -eq 1 ]; then
    cd "$ROOT/prolog-backend"
    swipl -g "server(3002),thread_get_message(stop)" prolog-server.pl >> /tmp/dots_prolog.log 2>&1 &
    PID_PROLOG=$!
    if wait_port 3002 "Prolog"; then
        : # ok
    else
        err "Лог Prolog:"
        cat /tmp/dots_prolog.log
        kill "$PID_PROLOG" 2>/dev/null
        PID_PROLOG=""
    fi
fi

# ── CORS proxy (порт 3001 → 3002) ───────────────────────────
if [ $HAS_NODE -eq 1 ] && [ -n "$PID_PROLOG" ]; then
    cd "$ROOT/prolog-backend"
    node cors-proxy.js >> /tmp/dots_proxy.log 2>&1 &
    PID_PROXY=$!
    wait_port 3001 "Proxy" || { kill "$PID_PROXY" 2>/dev/null; PID_PROXY=""; }
fi

# ── Підсумок ────────────────────────────────────────────────
echo ""
echo "  ─────────────────────────────────────"
[ -n "$PID_HASKELL" ] && echo -e "  ${GREEN}✓${NC} Haskell  → http://localhost:3000"
[ -z "$PID_HASKELL" ] && echo -e "  ${RED}✗${NC} Haskell  → не запущений"
[ -n "$PID_PROLOG"  ] && echo -e "  ${GREEN}✓${NC} Prolog   → http://localhost:3001"
[ -z "$PID_PROLOG"  ] && echo -e "  ${RED}✗${NC} Prolog   → не запущений"
echo "  ─────────────────────────────────────"

if [ -z "$PID_HASKELL" ] && [ -z "$PID_PROLOG" ]; then
    err "Жоден бекенд не запустився. Виходимо."
    exit 1
fi

# ── Відкриваємо фронтенд ────────────────────────────────────
FRONTEND="$ROOT/frontend/index.html"
if [ -f "$FRONTEND" ]; then
    log "Відкриваємо фронтенд..."
    open "$FRONTEND" 2>/dev/null || xdg-open "$FRONTEND" 2>/dev/null || \
        warn "Відкрийте вручну: file://$FRONTEND"
fi

echo ""
log "Натисніть Ctrl+C щоб зупинити всі сервери."
echo ""

wait