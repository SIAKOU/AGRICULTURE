#!/usr/bin/env bash
# ============================================
# rollback.sh — AgriIntel360 (À EXÉCUTER SUR LE SERVEUR LWS)
# Description : Restauration d'urgence de la dernière version sauvegardée
#               (frontend et/ou backend) puis redémarrage du backend.
# Auteur : Agent DevOps AgriIntel360
#
# Usage :
#   bash rollback.sh           # Restaure frontend + backend
#   bash rollback.sh frontend  # Restaure uniquement le frontend
#   bash rollback.sh backend   # Restaure uniquement le backend
# ============================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHAT="${1:-all}"

echo "── AgriIntel360 Rollback — $(date '+%Y-%m-%d %H:%M:%S') ──"

backup_exists() {
  ls -d "${ROOT}/${1}-backup-"* 2>/dev/null | tail -n 1 || true
}

# ---------- Frontend ----------
if [ "$WHAT" = "frontend" ] || [ "$WHAT" = "all" ]; then
  LATEST="$(backup_exists _frontend)"
  if [ -n "$LATEST" ]; then
    echo "→ Restauration du frontend depuis : $(basename "$LATEST")"
    rm -rf "${ROOT}/_frontend_broken"
    mv "${ROOT}/_frontend" "${ROOT}/_frontend_broken" 2>/dev/null || true
    mv "$LATEST" "${ROOT}/_frontend"
    echo "✔ Frontend restauré"
  else
    echo "✘ Aucun backup frontend trouvé (cherchez : ${ROOT}/_frontend-backup-*)"
  fi
fi

# ---------- Backend ----------
if [ "$WHAT" = "backend" ] || [ "$WHAT" = "all" ]; then
  LATEST="$(backup_exists api)"
  if [ -n "$LATEST" ]; then
    echo "→ Restauration du backend depuis : $(basename "$LATEST")"
    rm -rf "${ROOT}/api_broken"
    mv "${ROOT}/api" "${ROOT}/api_broken" 2>/dev/null || true
    mv "$LATEST" "${ROOT}/api"
    echo "✔ Backend restauré"
    echo "→ Redémarrage du backend..."
    bash "${ROOT}/start-backend.sh" || {
      echo "✘ Échec du redémarrage. Restaurer manuellement : mv ${ROOT}/api_broken ${ROOT}/api"
      exit 1
    }
  else
    echo "✘ Aucun backup backend trouvé (cherchez : ${ROOT}/api-backup-*)"
  fi
fi

echo "── Terminé. Vérifiez : bash ${ROOT}/health-check.sh ──"
