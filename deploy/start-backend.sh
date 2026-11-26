#!/usr/bin/env bash
# ============================================
# start-backend.sh — AgriIntel360 (À EXÉCUTER SUR LE SERVEUR LWS)
# Description : Démarre/redémarre le backend FastAPI (uvicorn)
#               sur 127.0.0.1:8001 en arrière-plan (nohup).
# Auteur : Agent DevOps AgriIntel360
#
# Usage :
#   bash start-backend.sh              # Démarrage / redémarrage
#   bash start-backend.sh --foreground # Démarrage en avant-plan (debug)
# ============================================
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_ROOT="${ROOT}/api"
LOGS_DIR="${ROOT}/logs"
HOST="127.0.0.1"
PORT="8001"
MODE="${1:-background}"

mkdir -p "$LOGS_DIR"

# ---------- Arrêt de l'ancien processus ----------
if [ -f "$LOGS_DIR/uvicorn.pid" ]; then
  OLD_PID="$(cat "$LOGS_DIR/uvicorn.pid" 2>/dev/null || true)"
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Arrêt de l'ancien uvicorn (PID $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 2
  fi
fi
pkill -9 -f "uvicorn.*src.main" 2>/dev/null || true
sleep 1

cd "$BACKEND_ROOT"

# ---------- Environnement virtuel ----------
if [ -d .venv ]; then
  # shellcheck disable=SC1091
  source .venv/bin/activate
else
  echo "ERREUR : .venv absent dans ${BACKEND_ROOT}."
  echo "Installez les dépendances : python3.12 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt"
  exit 1
fi

# ---------- Chargement du .env ----------
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env 2>/dev/null || true
  set +a
fi

# ---------- Limitation threads BLAS/OpenMP (mutualisé) ----------
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

# ---------- Démarrage ----------
if [ "$MODE" = "--foreground" ]; then
  exec python -m uvicorn src.main:app \
    --host "$HOST" --port "$PORT" \
    --workers 1 --timeout-keep-alive 30 --log-level info
fi

nohup python -m uvicorn src.main:app \
  --host "$HOST" --port "$PORT" \
  --workers 1 --timeout-keep-alive 30 --log-level warning \
  >> "$LOGS_DIR/backend.log" 2>&1 &
echo $! > "$LOGS_DIR/uvicorn.pid"

sleep 3
if kill -0 "$(cat "$LOGS_DIR/uvicorn.pid")" 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✔ uvicorn démarré (PID $(cat "$LOGS_DIR/uvicorn.pid")) sur ${HOST}:${PORT}"
  echo "   Logs : ${LOGS_DIR}/backend.log"
  echo "   Vérification : curl -s http://127.0.0.1:${PORT}/api/v1/health"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✘ Le processus s'est arrêté au démarrage. Dernières lignes :"
  tail -n 30 "$LOGS_DIR/backend.log"
  exit 1
fi
