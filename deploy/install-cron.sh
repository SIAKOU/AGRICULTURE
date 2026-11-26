#!/usr/bin/env bash
# ============================================================
# install-cron.sh — Surveillance AgriIntel360 (serveur LWS)
#
# Installe (ou met à jour) une tâche CRON qui exécute `health-check.sh` toutes
# les 5 minutes, avec redémarrage automatique du backend et alerte e-mail.
#
# Idempotent : la tâche est identifiée par un marqueur `# agriintel360-health`,
# donc relancer le script met à jour la ligne au lieu de la dupliquer. Une
# sauvegarde de la crontab existante est faite avant toute modification.
#
# Usage (sur le serveur, en tant qu'utilisateur du site) :
#   bash install-cron.sh              # installe ou met à jour
#   bash install-cron.sh --show       # affiche la tâche installée
#   bash install-cron.sh --uninstall  # retire la tâche
#   bash install-cron.sh --dry-run    # montre ce qui serait fait
#
# Les identifiants du parcours authentifié sont lus depuis `.deploy-secrets`
# (AGRI_SMOKE_EMAIL / AGRI_SMOKE_PASSWORD) et écrits dans `.health-smoke-env`
# en permissions 600 — jamais dans la crontab.
# ============================================================
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER="# agriintel360-health"
CRON_SCHEDULE="*/5 * * * *"
HEALTH="${ROOT}/health-check.sh"
LOG_DIR="${ROOT}/logs"
LOG_FILE="${LOG_DIR}/health-check.log"
SMOKE_ENV="${ROOT}/.health-smoke-env"
SECRETS="${ROOT}/.deploy-secrets"

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; reset='\033[0m'
MODE="${1:-}"

log()  { printf '%b%s%b\n' "$green" "$*" "$reset"; }
warn() { printf '%b%s%b\n' "$yellow" "$*" "$reset"; }
err()  { printf '%b%s%b\n' "$red" "$*" "$reset"; }

CRON_LINE="${CRON_SCHEDULE} cd ${ROOT} && bash ${HEALTH} --auto-restart --email >> ${LOG_FILE} 2>&1 ${MARKER}"

# ------------------------------------------------------------
# Préparation de l'environnement (dossiers, identifiants, logrotate)
# ------------------------------------------------------------
prepare() {
  [ -x "$HEALTH" ] || [ -f "$HEALTH" ] || { err "health-check.sh introuvable dans ${ROOT}"; exit 1; }
  mkdir -p "$LOG_DIR"

  if [ -f "$SECRETS" ]; then
    local email password
    email="$(grep -E '^AGRI_SMOKE_EMAIL=' "$SECRETS" 2>/dev/null | head -n1 | cut -d= -f2-)"
    password="$(grep -E '^AGRI_SMOKE_PASSWORD=' "$SECRETS" 2>/dev/null | head -n1 | cut -d= -f2-)"
    if [ -n "$email" ] && [ -n "$password" ]; then
      umask 077
      printf 'SMOKE_EMAIL=%s\nSMOKE_PASSWORD=%s\n' "$email" "$password" > "$SMOKE_ENV"
      chmod 600 "$SMOKE_ENV" 2>/dev/null || true
      log "Identifiants de fumée écrits dans .health-smoke-env (600)"
    else
      warn "AGRI_SMOKE_EMAIL / AGRI_SMOKE_PASSWORD absents de .deploy-secrets : parcours authentifié ignoré"
    fi
  else
    warn ".deploy-secrets absent : parcours authentifié ignoré"
  fi

  # Rotation simple : au-delà de 5 Mo, le journal est archivé et repart à zéro.
  if [ -f "$LOG_FILE" ]; then
    local size
    size="$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')"
    if [ -n "$size" ] && [ "$size" -gt 5242880 ]; then
      mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null || true
      log "Journal de santé archivé (${LOG_FILE}.1)"
    fi
  fi
}

# ------------------------------------------------------------
# Crontab : lecture/écriture
# ------------------------------------------------------------
have_crontab() { command -v crontab >/dev/null 2>&1; }

current_crontab() { crontab -l 2>/dev/null || true; }

show_cron() {
  if ! have_crontab; then
    warn "crontab absent sur cet hôte — utilisez le gestionnaire de CRON de LWS."
    echo "  Commande à planifier (toutes les 5 minutes) :"
    echo "  ${CRON_LINE}"
    return 0
  fi
  local found
  found="$(current_crontab | grep -F "$MARKER" || true)"
  if [ -n "$found" ]; then
    log "Tâche installée :"
    echo "  $found"
  else
    warn "Aucune tâche ${MARKER} installée."
  fi
}

install_cron() {
  if ! have_crontab; then
    warn "crontab absent sur cet hôte — planification manuelle requise."
    echo ""
    echo "Sur LWS (panneau CRON), ajoutez :"
    echo "  ${CRON_LINE}"
    echo ""
    echo "Sur un serveur avec crontab, relancez ce script."
    return 1
  fi

  local backup
  backup="${ROOT}/logs/crontab-backup-$(date +%Y%m%d-%H%M%S).txt"
  mkdir -p "${ROOT}/logs"
  current_crontab > "$backup" 2>/dev/null || true
  chmod 600 "$backup" 2>/dev/null || true
  log "Sauvegarde de la crontab : ${backup}"

  local tmp
  tmp="$(mktemp)"
  # On retire l'ancienne ligne marquée, puis on ajoute la nouvelle.
  current_crontab | grep -vF "$MARKER" > "$tmp" || true
  printf '%s\n' "$CRON_LINE" >> "$tmp"

  if crontab "$tmp"; then
    log "Tâche CRON installée : ${CRON_SCHEDULE} → health-check.sh --auto-restart --email"
  else
    err "Échec de l'installation de la crontab"
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

uninstall_cron() {
  if ! have_crontab; then
    warn "crontab absent : rien à retirer (supprimez la tâche dans le panneau LWS)."
    return 0
  fi
  local tmp
  tmp="$(mktemp)"
  current_crontab | grep -vF "$MARKER" > "$tmp" || true
  crontab "$tmp" && log "Tâche ${MARKER} retirée"
  rm -f "$tmp"
}

# ------------------------------------------------------------
case "$MODE" in
  --show)
    show_cron
    ;;
  --uninstall)
    uninstall_cron
    ;;
  --dry-run)
    echo "Mode simulation — aucune modification."
    echo "  Fichier d'identifiants : ${SMOKE_ENV}"
    echo "  Journal                : ${LOG_FILE}"
    echo "  Ligne CRON             : ${CRON_LINE}"
    [ -f "$HEALTH" ] && log "health-check.sh présent" || err "health-check.sh manquant"
    have_crontab && log "crontab disponible" || warn "crontab absent (planification manuelle sur LWS)"
    ;;
  "")
    prepare
    if install_cron; then
      echo ""
      echo "Surveillance active :"
      echo "  Journal : tail -f ${LOG_FILE}"
      echo "  Test    : bash ${HEALTH}"
      echo "  Retrait : bash install-cron.sh --uninstall"
    else
      echo ""
      warn "Surveillance NON installée : planifiez la ligne ci-dessus dans le panneau CRON LWS."
      exit 1
    fi
    ;;
  -h|--help|*)
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
esac
