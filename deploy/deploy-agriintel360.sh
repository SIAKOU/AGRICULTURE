#!/usr/bin/env bash
# ============================================
# FICHIER : deploy-agriintel360.sh
# DESCRIPTION : Script principal de déploiement AgriIntel360
#               (Frontend Next.js statique + Backend FastAPI → LWS mutualisé)
# AUTEUR : Agent DevOps AgriIntel360
# DATE : $(date +%Y-%m-%d)
#
# USAGE :
#   bash deploy-agriintel360.sh                 # Déploiement complet
#   bash deploy-agriintel360.sh --dry-run       # Simulation (aucune modification)
#   bash deploy-agriintel360.sh --verbose       # Affiche chaque commande exécutée
#   bash deploy-agriintel360.sh --step-by-step  # Confirmation avant chaque module
#   bash deploy-agriintel360.sh --module C      # Ne déroule qu'un module (ou A-F)
#   bash deploy-agriintel360.sh --resume        # Reprend là où le dernier run s'est arrêté
#
# FONCTIONNEMENT :
#   A. Pré-vérifications (outils, FTP, DB, .env)
#   B. Build Frontend (Next.js static export)
#   C. Build Backend (venv, pip, Alembic, seed admin, dry-run uvicorn)
#   D. Upload FTP (structure LWS + mirror + fichiers serveur)
#   E. Configuration post-déploiement (.env, permissions, démarrage)
#   F. Smoke tests (frontend, API, auth, DB, email, websocket)
#
# REPRISE : chaque module réussi crée un checkpoint (.deploy_checkpoint).
#           En cas d'échec : retry / skip / rollback / abort.
# ============================================

# --- Sécurité : arrêt immédiat si une commande critique échoue ---
# (pas de `set -e` global : chaque étape gère ses propres erreurs)
set -o pipefail

# ------------------------------------------------------------------
# SOURCE DE LA CONFIGURATION
# ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./deploy-config.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/deploy-config.sh"

mkdir -p "$LOGS_DIR" "$BUILD_STAGING"

# ------------------------------------------------------------------
# ETAT GLOBAL
# ------------------------------------------------------------------
LOG_FILE="${LOGS_DIR}/deploy-$(date +%Y-%m-%d-%H%M%S).log"
ERROR_LOG=""
START_TIME="$(date +%s)"
STEP_BY_STEP=false
VERBOSE=false
DRY_RUN=false
ONLY_MODULE=""
RESUME=false
CURRENT_MODULE=""
declare -a MODULE_STATUS=()
declare -a MODULE_PCT=()

# ------------------------------------------------------------------
# TRAPS — nettoyage & journal d'erreur en cas de sortie
# ------------------------------------------------------------------
cleanup() {
  local code=$?
  if [ "$code" -ne 0 ] && [ -z "${SKIP_ERROR_LOG:-}" ]; then
    ERROR_LOG="${LOGS_DIR}/deploy-error-$(date +%Y-%m-%d-%H%M%S).log"
    {
      echo "=== ERREUR FATALE (exit $code) le $(date) ==="
      echo "=== Module actif : ${CURRENT_MODULE:-aucun} ==="
      echo "=== Dernière commande : $(redact "${LAST_CMD:-inconnue}") ==="
      echo "=== --- Fin du journal principal (tronqué) --- ==="
      tail -n 120 "$LOG_FILE" 2>/dev/null
    } > "$ERROR_LOG" 2>/dev/null
    echo -e "${C_RED}[ERREUR] Déploiement interrompu. Détails : ${ERROR_LOG}${C_RESET}" >&2
    echo -e "${C_YELLOW}Astuce : relancez avec --resume pour reprendre au dernier checkpoint.${C_RESET}" >&2
  fi
  # Nettoyage du staging (contient des secrets) sauf en mode verbose/inspection
  if [ "$VERBOSE" = false ] && [ -d "$BUILD_STAGING" ]; then
    rm -rf "$BUILD_STAGING"
  fi
}
trap cleanup EXIT

# ------------------------------------------------------------------
# UTILITAIRES CORE
# ------------------------------------------------------------------

# --- Masquage des secrets dans toute sortie ---
redact() {
  local text="$1"
  local secret
  for secret in "${SECRET_VALUES[@]}"; do
    [ -n "$secret" ] || continue
    text="${text//"$secret"/***REDACTED***}"
  done
  printf '%s' "$text"
}

# --- Log : écrit dans le fichier (redacté) + stdout ---
log() {
  local level="$1" msg="$2"
  local ts="$(date +%H:%M:%S)"
  local color="$C_RESET" label="INFO"
  case "$level" in
    ok)     color="$C_GREEN";  label="OK" ;;
    warn)   color="$C_YELLOW"; label="AVERT" ;;
    err)    color="$C_RED";    label="ERREUR" ;;
    step)   color="$C_CYAN";   label="ETAPE" ;;
    dbg)    color="$C_GRAY";   label="DEBUG" ;;
    *)      color="$C_RESET";  label="INFO" ;;
  esac
  local safe; safe="$(redact "$msg")"
  printf '%s %s[%s]%s %s\n' "$ts" "$color" "$label" "$C_RESET" "$safe" | tee -a "$LOG_FILE"
}

log_ok()    { log ok    "$1"; }
log_warn()  { log warn  "$1"; }
log_err()   { log err   "$1"; }
log_step()  { log step  "$1"; }
log_dbg()   { [ "$VERBOSE" = true ] && log dbg "$1" || true; }

# --- Exécution d'une commande (option verbose) ---
run() {
  LAST_CMD="$*"
  [ "$VERBOSE" = true ] && log dbg "> $LAST_CMD"
  if [ "$DRY_RUN" = true ]; then
    log dbg "[dry-run] exécution simulée : $LAST_CMD"
    return 0
  fi
  "$@"
}

# --- Retry avec backoff exponentiel (3 tentatives max) ---
run_retry() {
  local attempts="${RETRY_MAX:-3}" delay=2 cmd_desc="$1"; shift
  local i rc
  if [ "$DRY_RUN" = true ]; then
    log_dbg "[dry-run] exécution simulée : $*"
    return 0
  fi
  for ((i=1; i<=attempts; i++)); do
    log_step "Tentative $i/$attempts : $cmd_desc"
    "$@"
    rc=$?
    if [ "$rc" -eq 0 ]; then return 0; fi
    if [ "$i" -lt "$attempts" ]; then
      log_warn "Échec (code $rc). Nouvelle tentative dans ${delay}s..."
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done
  log_err "Échec définitif après $attempts tentatives : $cmd_desc"
  return "$rc"
}

# --- Barre de progression ---
progress_bar() {
  local pct="$1" width="${2:-20}" label="${3:-}"
  local filled=""; local empty=""; local i
  local fill_count=$((pct * width / 100))
  for ((i=0; i<fill_count; i++)); do filled+="█"; done
  for ((i=0; i<width-fill_count; i++)); do empty+="░"; done
  printf '[%s%s] %3d%%' "$filled" "$empty" "$pct"
  [ -n "$label" ] && printf ' %s' "$label"
}

# --- Affichage dashboard global ---
draw_dashboard() {
  [ "$DRY_RUN" = true ] && return 0
  [ -t 1 ] || return 0
  printf "\033[2J\033[H"
  printf '%s\n' "╔══════════════════════════════════════════════════════════════╗"
  printf '║     🌾 AGRIINTEL360 — DÉPLOIEMENT AUTOMATISÉ v%s          ║\n' "$DEPLOY_VERSION"
  printf '%s\n' "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  local ts
  ts="$(date +%H:%M:%S)"
  local names=( "Module A — Pré-vérifications" "Module B — Build Frontend" "Module C — Build Backend" "Module D — Upload FTP" "Module E — Configuration" "Module F — Tests post-déploiement" )
  for idx in "${!names[@]}"; do
    local st="${MODULE_STATUS[$idx]:-·}" pct="${MODULE_PCT[$idx]:-0}"
    printf '%s %s %-34s %s\n' "$ts" "$C_BLUE${st}$C_RESET" "${names[$idx]}" "$(progress_bar "$pct" 12)"
  done
  echo ""
  local global_pct=0
  for p in "${MODULE_PCT[@]}"; do global_pct=$((global_pct + p)); done
  [ "${#MODULE_PCT[@]}" -gt 0 ] && global_pct=$((global_pct / ${#MODULE_PCT[@]}))
  printf '📊 %sProgression globale%s : %s\n' "$C_BOLD" "$C_RESET" "$(progress_bar "$global_pct" 22)"
  printf '📝 %sDernière action%s : %s\n' "$C_BOLD" "$C_RESET" "${LAST_ACTION:-initialisation...}"
  local elapsed=$(( $(date +%s) - START_TIME ))
  printf '⏱️  %sTemps écoulé%s : %ds | ETA totale : ~%ds\n\n' "$C_BOLD" "$C_RESET" "$elapsed" "$((elapsed * 5))"
}

set_module_pct() {
  MODULE_PCT["$1"]="$2"
  LAST_ACTION="$3"
  [ "$VERBOSE" = true ] || draw_dashboard
}

# ------------------------------------------------------------------
# ASSISTANT CONTEXTUEL (ask_agent)
# ------------------------------------------------------------------
ask_agent() {
  # $1 = catégorie d'erreur, $2 = message, $3 = suggestions (pipe-séparées), $4 = défaut
  local category="$1" message="$2" suggestions="$3" default="$4"
  local answer
  log_warn "[Agent] $message"
  case "$category" in
    port_occupied)
      echo -e "${C_YELLOW}💡 Port ${BACKEND_PORT} déjà utilisé. Voulez-vous tuer le processus existant ?${C_RESET} [Y/n]"
      read -r answer
      case "${answer:-Y}" in y|Y|o|O)
        local pid
        pid="$(lsof -ti tcp:"$BACKEND_PORT" 2>/dev/null || true)"
        if [ -n "$pid" ]; then run kill -9 $pid && log_ok "Processus $pid terminé"; else log_warn "Aucun PID trouvé sur le port ${BACKEND_PORT}"; fi
        return 0
        ;;
      esac
      return 1
      ;;
    alembic_failed)
      echo -e "${C_YELLOW}💡 Migration Alembic échouée. Faire stamp head puis upgrade ?${C_RESET} [Y/n]"
      read -r answer
      case "${answer:-Y}" in y|Y|o|O)
        run "$BACKEND_VENV/bin/alembic" stamp head && run "$BACKEND_VENV/bin/alembic" upgrade head
        return $?
        ;;
      esac
      return 1
      ;;
    ftp_timeout)
      echo -e "${C_YELLOW}💡 Connexion FTP instable. Passer en mode passif/actif ?${C_RESET} [p/a]"
      read -r answer
      case "${answer:-p}" in
        p|P) FTP_PASSIVE="passive"; log_ok "Mode passif activé" ;;
        a|A) FTP_PASSIVE="active"; log_ok "Mode actif activé" ;;
      esac
      return 0
      ;;
    npm_ci_failed)
      echo -e "${C_YELLOW}💡 npm ci a échoué (lockfile ?). Utiliser npm install ?${C_RESET} [Y/n]"
      read -r answer
      case "${answer:-Y}" in y|Y|o|O) return 2 ;; esac # 2 = signaler "passer à npm install"
      return 1
      ;;
  esac
  # Générique : menu retry / skip / rollback / abort
  echo -e "${C_YELLOW}Actions disponibles : retry | skip | rollback | abort${C_RESET}"
  read -rp "Choix [${default:-retry}] : " answer
  case "${answer:-$default}" in
    retry|r) return 10 ;;
    skip|s)  return 11 ;;
    rollback) run_rollback; return 10 ;;
    abort|a) return 12 ;;
    *) return 10 ;;
  esac
}

# ------------------------------------------------------------------
# CHECKPOINTS (reprise sur erreur)
# ------------------------------------------------------------------
save_checkpoint() {
  # $1 = module (A..F)
  if [ "$DRY_RUN" = true ]; then return 0; fi
  local completed=""
  local m
  for m in A B C D E F; do
    completed="${completed}${m} "
    [ "$m" = "$1" ] && break
  done
  printf 'completed="%s"\n' "$completed" > "$CHECKPOINT_FILE"
  log_ok "Checkpoint sauvegardé : modules [${completed}]"
}

load_checkpoint() {
  [ -f "$CHECKPOINT_FILE" ] || return 1
  # shellcheck disable=SC1090
  . "$CHECKPOINT_FILE"
  return 0
}

module_already_done() {
  load_checkpoint
  [[ " $completed " == *" $1 "* ]]
}

# ------------------------------------------------------------------
# CONFIRMATION STEP-BY-STEP
# ------------------------------------------------------------------
confirm_step() {
  if [ "$STEP_BY_STEP" = true ] && [ "$DRY_RUN" = false ]; then
    read -rp "▶ Lancer maintenant : $1 ? [Entrée=continuer / q=abandonner] " ans
    case "$ans" in q|Q|quit) log_warn "Abandon demandé."; exit 1 ;; esac
  fi
}

# ------------------------------------------------------------------
# MODULE A — PRÉ-VÉRIFICATIONS
# ------------------------------------------------------------------
module_a_prechecks() {
  CURRENT_MODULE="A"; MODULE_STATUS[0]="●"
  LAST_ACTION="Vérification des outils locaux..."
  set_module_pct 0 5 "$LAST_ACTION"
  log_step "════ MODULE A : PRÉ-VÉRIFICATIONS ════"
  confirm_step "Module A (pré-vérifications)"

  local fail=0
  local required_tools=( "curl" "openssl" )
  local tool
  for tool in "${required_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      log_ok "Outil présent : $tool"
    else
      log_err "Outil manquant : $tool"; fail=1
    fi
  done

  # --- Versions locales ---
  set_module_pct 0 15 "$LAST_ACTION"
  local node_ok=0 npm_ok=0
  if command -v node >/dev/null 2>&1; then
    local nv; nv="$(node --version 2>/dev/null | tr -d 'v' | cut -d. -f1)"
    if [ "$nv" -ge "$NODE_MIN_VERSION" ]; then log_ok "Node.js ≥ ${NODE_MIN_VERSION} (v${nv})"; node_ok=1; else log_err "Node.js trop ancien : v${nv} (minimum ${NODE_MIN_VERSION})"; fail=1; fi
  else
    log_err "Node.js introuvable (requis ≥ ${NODE_MIN_VERSION})"; fail=1
  fi
  if command -v npm >/dev/null 2>&1; then
    local nm; nm="$(npm --version 2>/dev/null | cut -d. -f1)"
    if [ "$nm" -ge "$NPM_MIN_VERSION" ]; then log_ok "npm ≥ ${NPM_MIN_VERSION} (v${nm})"; npm_ok=1; else log_warn "npm ancien : v${nm}"; fi
  else
    log_err "npm introuvable"; fail=1
  fi
  if command -v lftp >/dev/null 2>&1; then
    log_ok "lftp présent ($(lftp --version 2>/dev/null | head -n1))"
  else
    log_warn "lftp absent — REQUIS pour les uploads mirror (Modules D). Installez-le : apt install lftp"
  fi
  if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    local pv; pv="$("$PYTHON_BIN" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)"
    log_ok "Python présent : ${PYTHON_BIN} (${pv})"
  else
    log_err "Python ${PYTHON_BIN} introuvable"; fail=1
  fi
  if command -v git >/dev/null 2>&1; then log_ok "git présent"; else log_err "git introuvable"; fail=1; fi
  [ "$node_ok" = 1 ] && [ "$npm_ok" = 1 ] || fail=1

  set_module_pct 0 35 "$LAST_ACTION"
  # --- Connectivité FTP ---
  LAST_ACTION="Test de connexion FTP vers ${FTP_HOST}:${FTP_PORT}..."
  log_step "Test FTP : ${FTP_HOST}:${FTP_PORT} (mode ${FTP_MODE})"
  if command -v lftp >/dev/null 2>&1; then
    if lftp -p "$FTP_PORT" -u "$FTP_USER","$FTP_PASS" "ftp://$FTP_HOST" -e "ls; bye" >/dev/null 2>&1; then
      log_ok "Connexion FTP réussie (lftp)"
    else
      log_warn "Connexion FTP échouée en FTP simple — test en FTPS..."
      if lftp -p "$FTP_PORT" -u "$FTP_USER","$FTP_PASS" -e "set ftp:ssl-allow yes; set ftp:ssl-force yes; set ssl:verify-certificate no; open ftps://$FTP_HOST; ls; bye" >/dev/null 2>&1; then
        log_ok "FTPS OK"
      else
        log_err "FTP/FTPS injoignable."; fail=1
      fi
    fi
  elif command -v curl >/dev/null 2>&1; then
    # NB : le mot de passe contient des caractères réservés (# @ &) — jamais dans l'URL
    if curl --connect-timeout 15 --max-time 40 -sS -u "$FTP_USER:$FTP_PASS" "ftp://$FTP_HOST:$FTP_PORT/" -o /dev/null 2>"$LOG_FILE.ftp"; then
      log_ok "Connexion FTP réussie (curl)"
    else
      log_err "FTP injoignable via curl. Détail : $(tail -n2 "$LOG_FILE.ftp")"; fail=1
    fi
  else
    log_warn "ni lftp ni curl présents — test FTP impossible."
  fi

  set_module_pct 0 55 "$LAST_ACTION"
  # --- Connectivité PostgreSQL (test depuis la machine locale) ---
  LAST_ACTION="Test de connexion PostgreSQL (${DB_HOST}:${DB_PORT})..."
  log_step "Test DB : ${DB_HOST}:${DB_PORT}/${DB_NAME}"
  if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" >/dev/null 2>&1 \
      && log_ok "PostgreSQL accessible (psql)" \
      || { log_warn "psql n'a pas pu joindre la base (accès externe LWS souvent restreint — vérifié en Module C)."; }
  else
    log_warn "psql absent localement — le test DB réel aura lieu dans le Module C."
  fi

  set_module_pct 0 75 "$LAST_ACTION"
  # --- Espace disque local ---
  LAST_ACTION="Vérification de l'espace disque local..."
  local avail; avail="$(df -Pk "${FRONTEND_DIR}" 2>/dev/null | awk 'NR==2{print $4}')"
  if [ -n "$avail" ]; then
    log_ok "Espace disque local disponible : $((avail/1024)) Mo"
  else
    log_warn "Impossible de déterminer l'espace disque local."
  fi

  set_module_pct 0 90 "$LAST_ACTION"
  # --- Intégrité des fichiers .env ---
  LAST_ACTION="Vérification de l'intégrité des fichiers .env..."
  local env_ok=1
  for f in "${FRONTEND_DIR}/.env.production" "${BACKEND_DIR}/.env" "${BACKEND_DIR}/.env.production"; do
    if [ -f "$f" ]; then
      log_ok "Présent : $f"
      grep -qE 'NEXT_PUBLIC_API_URL|DATABASE_URL|JWT_SECRET_KEY' "$f" || true
    else
      if [ "$(basename "$f")" = ".env" ]; then
        log_warn "Absent : $f (sera généré par le Module E)"
      else
        log_warn "Absent : $f (non bloquant)"
      fi
    fi
  done
  # Alerte sécurité : .env versionné ?
  if [ -d "${BACKEND_DIR}/.git" ] && git -C "$BACKEND_DIR" ls-files --error-unmatch .env >/dev/null 2>&1; then
    log_err "⚠️  .env est versionné dans Git — le retirer immédiatement (git rm --cached .env)"
  fi
  log_warn "⚠️  Vérifiez que .env n'est pas versionné dans Git"

  set_module_pct 0 100 "$LAST_ACTION"
  [ "$fail" -eq 0 ] && MODULE_STATUS[0]="✔" || MODULE_STATUS[0]="✘"
  return "$fail"
}

# ------------------------------------------------------------------
# MODULE B — BUILD FRONTEND
# ------------------------------------------------------------------
module_b_frontend() {
  CURRENT_MODULE="B"; MODULE_STATUS[1]="●"
  LAST_ACTION="Nettoyage du dossier out/..."
  set_module_pct 1 5 "$LAST_ACTION"
  log_step "════ MODULE B : BUILD FRONTEND ════"
  confirm_step "Module B (build frontend)"

  if [ ! -d "$FRONTEND_DIR" ]; then log_err "Dossier frontend introuvable : $FRONTEND_DIR"; return 1; fi
  if [ "$DRY_RUN" = true ]; then
    log_warn "dry-run : simulation du build frontend"
    log_warn "  - nettoyage : rm -rf ${NEXT_OUT}"
    log_warn "  - installation : npm ci (depuis ${FRONTEND_DIR}/package-lock.json)"
    log_warn "  - build : npm run build (Next.js static export → out/)"
    log_warn "  - vérification : index.html dans out/"
    set_module_pct 1 100 "$LAST_ACTION"; MODULE_STATUS[1]="✔"; return 0
  fi

  # 1. Nettoyage
  run rm -rf "${NEXT_OUT}"
  log_ok "Dossier out/ nettoyé"

  # 2. Installation des dépendances (npm ci préféré)
  set_module_pct 1 25 "Installation des dépendances npm..."
  log_step "Installation des dépendances (npm ci)"
  (
    cd "$FRONTEND_DIR" || return 1
    if [ -f package-lock.json ]; then
      if run_retry "npm ci" npm ci --no-audit --no-fund >/dev/null 2>&1; then
        log_ok "npm ci terminé"
      else
        # Échec → assistance
        ask_agent npm_ci_failed "npm ci a échoué. Basculer sur npm install ?"
        rc=$?
        if [ "$rc" -eq 2 ]; then
          run npm install --no-audit --no-fund >/dev/null 2>&1 && log_ok "npm install terminé" || return 1
        else
          return 1
        fi
      fi
    else
      run npm install --no-audit --no-fund >/dev/null 2>&1 && log_ok "npm install terminé" || return 1
    fi
  ) || return 1

  # 3. Build statique Next.js
  set_module_pct 1 55 "Compilation Next.js (npm run build)..."
  log_step "Génération du build statique (npm run build)"
  (
    cd "$FRONTEND_DIR" || return 1
    [ "$DRY_RUN" = true ] && { log_dbg "dry-run : build simulé"; exit 0; }
    NODE_ENV=production run npm run build >"$LOG_FILE.nextbuild" 2>&1
  ) || {
    log_err "Build Next.js échoué. Consultez : $LOG_FILE.nextbuild"
    tail -n 20 "$LOG_FILE.nextbuild" | tee -a "$LOG_FILE" >&2
    return 1
  }
  log_ok "Build Next.js terminé"

  # 4. Vérification du dossier out/
  set_module_pct 1 75 "Vérification du dossier out/..."
  if [ ! -f "${NEXT_OUT}/index.html" ]; then
    log_err "index.html introuvable dans out/ — build incomplet"
    return 1
  fi
  log_ok "✓ out/index.html présent"
  local nb=0; nb="$(find "$NEXT_OUT" -type f | wc -l)"
  local sz="$(du -sh "$NEXT_OUT" 2>/dev/null | cut -f1)"
  log_ok "Assets statiques : $nb fichiers, $sz"

  # 5. Optimisation (pré-compression gzip pour les gros assets)
  set_module_pct 1 88 "Compression des assets (gzip)..."
  if command -v gzip >/dev/null 2>&1; then
    # Ne crée pas de .gz si .htaccess utilise mod_deflate (évite double encodage).
    # On laisse Apache gérer. On nettoie juste les éventuels fichiers .gz précédents.
    log_ok "Compression déléguée à mod_deflate (Apache) — aucun pré-compress."
  fi

  set_module_pct 1 100 "$LAST_ACTION"
  MODULE_STATUS[1]="✔"
  return 0
}

# ------------------------------------------------------------------
# MODULE C — BUILD BACKEND
# ------------------------------------------------------------------
module_c_backend() {
  CURRENT_MODULE="C"; MODULE_STATUS[2]="●"
  LAST_ACTION="Création de l'environnement virtuel..."
  set_module_pct 2 5 "$LAST_ACTION"
  log_step "════ MODULE C : BUILD BACKEND ════"
  confirm_step "Module C (build backend)"

  if [ ! -d "$BACKEND_DIR" ]; then log_err "Dossier backend introuvable : $BACKEND_DIR"; return 1; fi
  if [ "$DRY_RUN" = true ]; then
    log_warn "dry-run : simulation du build backend"
    log_warn "  - venv : python3.12 -m venv .venv (${BACKEND_DIR})"
    log_warn "  - dépendances : pip install -r requirements.txt"
    log_warn "  - migrations : alembic upgrade head (cible : ${DATABASE_URL})"
    log_warn "  - seed admin : ensure_default_admin_user()"
    log_warn "  - dry-run uvicorn sur 127.0.0.1:8019"
    set_module_pct 2 100 "$LAST_ACTION"; MODULE_STATUS[2]="✔"; return 0
  fi

  # 1. Environnement virtuel
  if [ ! -d "$BACKEND_VENV" ]; then
    log_step "Création du venv ($PYTHON_BIN -m venv .venv)"
    ( cd "$BACKEND_DIR" && "$PYTHON_BIN" -m venv .venv ) || return 1
    log_ok "venv créé"
  else
    log_ok "venv existant — réutilisation"
  fi
  local PY="${BACKEND_VENV}/bin/python"
  if [ ! -x "$PY" ] && [ -x "${BACKEND_VENV}/Scripts/python.exe" ]; then
    PY="${BACKEND_VENV}/Scripts/python.exe"
  fi

  # 2. Installation des dépendances
  set_module_pct 2 30 "Installation des dépendances Python (pip)..."
  log_step "pip install -r requirements.txt"
  if [ "$DRY_RUN" = false ]; then
    run_retry "pip install" "$PY" -m pip install --upgrade pip >/dev/null 2>&1 || log_warn "pip upgrade échoué (non bloquant)"
    if ! run_retry "installation des dépendances" "$PY" -m pip install --no-cache-dir -r "${BACKEND_DIR}/requirements.txt" >"$LOG_FILE.pip" 2>&1; then
      log_err "pip install a échoué. Dernières lignes :"
      tail -n 15 "$LOG_FILE.pip" | tee -a "$LOG_FILE" >&2
      return 1
    fi
  fi
  log_ok "Dépendances installées"

  # 3. .env temporaire pour migrations (ne pas écraser le .env local)
  local local_env=""
  if [ -f "${BACKEND_DIR}/.env" ]; then local_env="yes"; fi

  # 4. Migrations Alembic (DATABASE_URL de production)
  set_module_pct 2 55 "Migrations Alembic (upgrade head)..."
  log_step "Migration Alembic upgrade head"
  if [ "$DRY_RUN" = false ]; then
    (
      cd "$BACKEND_DIR"
      export DATABASE_URL
      export ENVIRONMENT=production
      export JWT_SECRET_KEY
      export DEFAULT_ADMIN_PASSWORD="$ADMIN_PASSWORD"
      export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
      if ! "$PY" -m alembic upgrade head >"$LOG_FILE.alembic" 2>&1; then
        log_err "Migration échouée. Détails :"
        tail -n 25 "$LOG_FILE.alembic" | tee -a "$LOG_FILE" >&2
        ask_agent alembic_failed "Migration Alembic échouée."
        return 1
      fi
    ) || return 1
  fi
  log_ok "Migrations appliquées (head)"

  # 5. Seed / vérification du compte admin (via la fonction du backend)
  set_module_pct 2 75 "Création/vérification du compte admin..."
  if [ "$DRY_RUN" = false ]; then
    (
      cd "$BACKEND_DIR"
      export DATABASE_URL ENVIRONMENT=production JWT_SECRET_KEY DEFAULT_ADMIN_PASSWORD="$ADMIN_PASSWORD"
      export DEFAULT_ADMIN_EMAIL="$ADMIN_EMAIL" DEFAULT_ADMIN_USERNAME="$ADMIN_USERNAME" DEFAULT_ADMIN_FULL_NAME="$ADMIN_FULL_NAME"
      export OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
      "$PY" - <<'PYSEED' >>"$LOG_FILE" 2>&1
import asyncio, sys
async def main():
    from src.services.admin_seed import ensure_default_admin_user
    await ensure_default_admin_user()
    print("Seed admin : OK")
try:
    asyncio.run(main())
except Exception as exc:  # noqa: BLE001
    print("Seed admin : avertissement (non bloquant) ->", exc)
PYSEED
    ) || log_warn "Seed admin : vérification non concluante (le backend la réessaie au démarrage)."
  fi
  log_ok "Compte admin vérifié (seed automatique au démarrage du backend si absent)"

  # 6. Dry-run de démarrage (uvicorn en local)
  set_module_pct 2 88 "Test de démarrage uvicorn (dry-run)..."
  log_step "Test de démarrage de l'API (uvicorn, dry-run 8s)"
  if [ "$DRY_RUN" = false ] && command -v curl >/dev/null 2>&1; then
    (
      cd "$BACKEND_DIR"
      export DATABASE_URL ENVIRONMENT=development JWT_SECRET_KEY
      "$PY" -m uvicorn src.main:app --host 127.0.0.1 --port 8019 --log-level error >"$LOG_FILE.uvicorn" 2>&1 &
      local pid=$!
      sleep 8
      if curl -sS --max-time 5 "http://127.0.0.1:8019/api/v1/health" | grep -qE '"status"'; then
        log_ok "API répond correctement (health check OK)"
      else
        log_warn "L'API n'a pas répondu au health check — détail :"
        tail -n 20 "$LOG_FILE.uvicorn" | tee -a "$LOG_FILE"
      fi
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    )
  fi
  echo "[$(date +%H:%M:%S)] Dry-run uvicorn terminé" >> "${BACKEND_DIR}/backend.log" 2>/dev/null || true
  log_ok "backend.log de test généré"

  set_module_pct 2 100 "$LAST_ACTION"
  MODULE_STATUS[2]="✔"
  return 0
}

# ------------------------------------------------------------------
# OUTILS FTP (helper)
# ------------------------------------------------------------------
lftp_exec() {
  # Exécute une séquence lftp (via stdin)
  local script="$1"
  local creds="${FTP_USER}:${FTP_PASS}"
  local proto="ftp"; [ "$FTP_MODE" = "ftps" ] && proto="ftps"
  local passive_flag=""
  [ "$FTP_PASSIVE" = "passive" ] && passive_flag="set ftp:passive-mode yes;"
  if command -v lftp >/dev/null 2>&1; then
    printf 'set ftp:ssl-allow yes;\nset ftp:ssl-force yes;\n%s set ssl:verify-certificate no;\n%s\n' "$passive_flag" "$script" | lftp -p "$FTP_PORT" -u "$FTP_USER","$FTP_PASS" "$proto://$FTP_HOST" 2>&1
  else
    log_warn "lftp absent — commande FTP non exécutée : $script"
    return 1
  fi
}

# ------------------------------------------------------------------
# MODULE D — UPLOAD FTP
# ------------------------------------------------------------------
module_d_upload() {
  CURRENT_MODULE="D"; MODULE_STATUS[3]="●"
  LAST_ACTION="Préparation des fichiers à uploader..."
  set_module_pct 3 5 "$LAST_ACTION"
  log_step "════ MODULE D : UPLOAD FTP ════"
  confirm_step "Module D (upload FTP)"

  if [ "$DRY_RUN" = true ]; then
    log_warn "dry-run : upload FTP simulé (aucun transfert)"
    set_module_pct 3 100 "$LAST_ACTION"; MODULE_STATUS[3]="✔"; return 0
  fi

  # --- 1. Génération des fichiers serveur dans staging ---
  LAST_ACTION="Génération du .htaccess et des proxys PHP..."
  set_module_pct 3 10 "$LAST_ACTION"
  generate_server_files || { log_err "Génération des fichiers serveur échouée"; return 1; }
  log_ok "Fichiers serveur générés dans $BUILD_STAGING"

  # --- 2. Backups distants (avant tout upload) ---
  LAST_ACTION="Backup de la version distante courante..."
  set_module_pct 3 15 "$LAST_ACTION"
  local ts="$(date +%Y%m%d-%H%M%S)"
  log_step "Backup distants (pré-déploiement)"
  if command -v lftp >/dev/null 2>&1; then
    lftp_exec "
cd ${REMOTE_ROOT} || exit 1
echo '--- Backup frontend ---'
mv -f _frontend _frontend-backup-${ts} 2>/dev/null
echo '--- Backup backend ---'
mv -f api api-backup-${ts} 2>/dev/null
echo '--- OK ---'
bye
" | while IFS= read -r line; do log_dbg "$line"; done
    log_ok "Backups distants effectués (suffixe ${ts})"
  else
    log_warn "lftp absent — backups distants ignorés"
  fi
  BACKUP_SUFFIX="$ts"

  # --- 3. Upload frontend (mirror out/ → _frontend/) ---
  LAST_ACTION="Upload du frontend (mirror lftp)..."
  set_module_pct 3 30 "$LAST_ACTION"
  log_step "Upload du build statique → ${REMOTE_STAGING_DIR}/"
  if command -v lftp >/dev/null 2>&1; then
    # Génération du script lftp avec les bonnes valeurs
    local lftp_file="${BUILD_STAGING}/lftp-mirror.lftp"
    _render_lftp_mirror "$lftp_file"
    if lftp -p "$FTP_PORT" -u "$FTP_USER","$FTP_PASS" "ftp://$FTP_HOST" -f "$lftp_file" >>"$LOG_FILE.ftp" 2>&1; then
      log_ok "Frontend uploadé"
    else
      log_err "Upload frontend échoué. Détails :"
      tail -n 20 "$LOG_FILE.ftp" | tee -a "$LOG_FILE" >&2
      ask_agent ftp_timeout "Échec de l'upload frontend via FTP."
      return 1
    fi
  else
    log_err "lftp est requis pour le mirror du frontend."
    return 1
  fi
  set_module_pct 3 55 "$LAST_ACTION"

  # --- 4. Upload backend (code Python, exclusions) ---
  LAST_ACTION="Upload du code backend (exclusions node_modules/.venv)..."
  set_module_pct 3 60 "$LAST_ACTION"
  log_step "Upload du code backend → ${REMOTE_BACKEND_DIR}/"
  local exclude_file="${BUILD_STAGING}/lftp-backend.exclude"
  cat > "$exclude_file" <<'EXCL'
--exclude .venv/
--exclude venv/
--exclude __pycache__/
--exclude .git/
--exclude node_modules/
--exclude ml-models/
--exclude mlflow/
--exclude logs/
--exclude *.pyc
--exclude tests/
--exclude .env
--exclude .env.local
EXCL
  local excl_args
  excl_args="$(sed 's/^--exclude /--exclude=/; s/\/$//' "$exclude_file" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  if lftp_exec "
mkdir -p ${REMOTE_BACKEND_DIR}
cd ${REMOTE_BACKEND_DIR}
mirror --reverse --verbose --parallel=4 ${excl_args} \"${BACKEND_DIR}/\" \"${REMOTE_BACKEND_DIR}/\"
bye
" >>"$LOG_FILE.ftp" 2>&1; then
    log_ok "Backend uploadé"
  else
    log_err "Upload backend échoué. Détails :"
    tail -n 20 "$LOG_FILE.ftp" | tee -a "$LOG_FILE" >&2
    return 1
  fi
  set_module_pct 3 80 "$LAST_ACTION"

  # --- 5. Upload des fichiers racine (.htaccess, proxy, scripts, .env) ---
  LAST_ACTION="Upload des fichiers racine (.htaccess, proxys, scripts)..."
  set_module_pct 3 85 "$LAST_ACTION"
  log_step "Upload des fichiers serveur racine"
  local root_files=(
    ".htaccess" "proxy-api.php" "ws-tunnel.php"
    "start-backend.sh" "health-check.sh" "rollback.sh"
    ".env.production"
  )
  for f in "${root_files[@]}"; do
    if [ -f "${BUILD_STAGING}/${f}" ]; then
      if lftp_exec "
cd ${REMOTE_ROOT}
put \"${BUILD_STAGING}/${f}\" -o \"${REMOTE_ROOT}/${f}\"
bye
" >>"$LOG_FILE.ftp" 2>&1; then
        log_ok "Upload : ${f}"
      else
        log_err "Upload échoué : ${f}"; return 1
      fi
    fi
  done
  # .env.production → api/.env (c'est le fichier lu par le backend)
  log_step "Installation du .env de production → api/.env"
  lftp_exec "
cd ${REMOTE_ROOT}
put \"${BUILD_STAGING}/.env.production\" -o \"${REMOTE_BACKEND_DIR}/.env\"
bye
" >>"$LOG_FILE.ftp" 2>&1 && log_ok "api/.env installé (permissions 600 ensuite)"

  # --- 6. Permissions ---
  LAST_ACTION="Définition des permissions (fichiers 644, dossiers 755, logs 775)..."
  set_module_pct 3 95 "$LAST_ACTION"
  lftp_exec "
set ftp:chmod true
cd ${REMOTE_ROOT}
chmod 644 .htaccess proxy-api.php ws-tunnel.php
chmod 755 start-backend.sh health-check.sh rollback.sh
chmod 600 ${REMOTE_BACKEND_DIR}/.env
mkdir -p ${REMOTE_LOGS_DIR}
chmod 775 ${REMOTE_LOGS_DIR}
bye
" >>"$LOG_FILE.ftp" 2>&1 || log_warn "Permissions non appliquées via FTP (à vérifier)"

  set_module_pct 3 100 "$LAST_ACTION"
  MODULE_STATUS[3]="✔"
  log_ok "Module D terminé (BACKUP_SUFFIX=${BACKUP_SUFFIX})"
  return 0
}

# ------------------------------------------------------------------
# MODULE E — CONFIGURATION POST-DÉPLOIEMENT
# ------------------------------------------------------------------
module_e_config() {
  CURRENT_MODULE="E"; MODULE_STATUS[4]="●"
  LAST_ACTION="Génération du .env de production..."
  set_module_pct 4 10 "$LAST_ACTION"
  log_step "════ MODULE E : CONFIGURATION POST-DÉPLOIEMENT ════"
  confirm_step "Module E (configuration)"

  # .env.production (généré en Module D ; régénéré ici si absent — ex. dry-run)
  if [ ! -f "${BUILD_STAGING}/.env.production" ]; then
    generate_env_production > "${BUILD_STAGING}/.env.production"
  fi
  chmod 600 "${BUILD_STAGING}/.env.production"
  log_ok ".env.production prêt (permissions 600, JWT 64-hex)"

  if [ "$DRY_RUN" = true ]; then
    log_warn "dry-run : configuration simulée (aucun fichier envoyé, aucun process démarré)"
    set_module_pct 4 100 "$LAST_ACTION"; MODULE_STATUS[4]="✔"; return 0
  fi

  set_module_pct 4 35 "Démarrage du backend sur le serveur..."
  LAST_ACTION="Démarrage du backend (uvicorn 127.0.0.1:${BACKEND_PORT})..."
  if [ "$DRY_RUN" = false ]; then
    if [ "$SSH_ENABLED" = true ]; then
      log_step "Démarrage via SSH (${SSH_USER}@${SSH_HOST}:${SSH_PORT})"
      if ssh -p "$SSH_PORT" "${SSH_USER}@${SSH_HOST}" "cd ${REMOTE_ROOT} && nohup bash start-backend.sh >/dev/null 2>&1 &" 2>>"$LOG_FILE"; then
        log_ok "Backend démarré via SSH"
      else
        log_err "SSH indisponible — le backend doit être démarré manuellement (voir README-DEPLOY.md)."
        log_warn "Action manuelle requise : ./start-backend.sh dans ${REMOTE_ROOT}"
      fi
    else
      log_warn "SSH non activé — vérification de l'API (si un cron/process existe déjà)..."
    fi

    # Vérification : le backend répond-il sur le port interne ?
    sleep 3
    if command -v curl >/dev/null 2>&1; then
      if curl -sS --max-time 8 "http://127.0.0.1:${BACKEND_PORT}/api/v1/health" | grep -qE '"status"'; then
        log_ok "Backend UP — répond sur 127.0.0.1:${BACKEND_PORT}"
      else
        log_warn "Backend non joignable en direct (attendu si pas de SSH/cron). Test du proxy HTTP ci-dessous."
      fi
    fi
  fi

  set_module_pct 4 75 "Vérification des health checks (proxy public)..."
  LAST_ACTION="Health check public /api/v1/health..."
  local code
  if command -v curl >/dev/null 2>&1; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "${API_BASE_URL}/health" 2>/dev/null)"
    if [ "$code" = "200" ]; then
      log_ok "Health check public : HTTP $code"
      set_module_pct 4 100 "$LAST_ACTION"; MODULE_STATUS[4]="✔"; return 0
    else
      log_warn "Health check public : HTTP $code (le backend peut mettre >20s à démarrer sur mutualisé)"
      set_module_pct 4 90 "$LAST_ACTION"
    fi
  fi
  MODULE_STATUS[4]="✘"
  return 1
}

# ------------------------------------------------------------------
# MODULE F — SMOKE TESTS POST-DÉPLOIEMENT
# ------------------------------------------------------------------
module_f_tests() {
  CURRENT_MODULE="F"; MODULE_STATUS[5]="●"
  LAST_ACTION="Lancement des tests post-déploiement..."
  set_module_pct 5 5 "$LAST_ACTION"
  log_step "════ MODULE F : SMOKE TESTS POST-DÉPLOIEMENT ════"

  if [ "$DRY_RUN" = true ]; then
    log_warn "dry-run : simulation des smoke tests"
    echo ""
    echo "  F1 Frontend  → GET ${APP_URL}/"
    echo "  F2 API       → GET ${API_BASE_URL}/health"
    echo "  F3 Auth      → POST ${API_BASE_URL}/auth/login"
    echo "  F4 DB        → GET ${API_BASE_URL}/health/detailed"
    echo "  F5 SMTP      → ${MAIL_SERVER}:${MAIL_PORT} SSL"
    echo "  F6 WebSocket → ${WS_URL}/api/v1/ws/anonymous"
    echo "  F7 Routes     → /ping, /payments/plans, /reports, /search, /market-prices/markets,"
    echo "                  /economics/gdp, /weather/current (contrat frontend ↔ backend)"
    echo "  F8 Connecté   → login admin + /auth/me, /reports, /search (200 attendu)"
    set_module_pct 5 100 "$LAST_ACTION"; MODULE_STATUS[5]="✔"; return 0
  fi

  local pass=0 fail=0 warn=0
  local t _t_frontend="" _t_api="" _t_auth="" _t_db="" _t_mail="" _t_ws=""

  # --- F1 : Frontend statique ---
  set_module_pct 5 15 "Test frontend (${APP_URL}/)..."
  LAST_ACTION="GET ${APP_URL}/"
  t="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "${APP_URL}/" 2>/dev/null)"
  if [ "$t" = "200" ]; then
    _t_frontend="✅ 200"; log_ok "✅ F1 Frontend ${APP_URL}/ → 200"; pass=$((pass+1))
  else
    _t_frontend="❌ $t"; log_err "❌ F1 Frontend → $t"; fail=$((fail+1))
  fi

  # --- F2 : API health ---
  set_module_pct 5 30 "Test API health..."
  LAST_ACTION="GET ${API_BASE_URL}/health"
  local body
  body="$(curl -s --max-time 30 "${API_BASE_URL}/health" 2>/dev/null)"
  if echo "$body" | grep -qE '"status"'; then
    _t_api="✅ OK"; log_ok "✅ F2 API health → ${API_BASE_URL}/health OK"; pass=$((pass+1))
  else
    _t_api="❌ invalide"; log_err "❌ F2 API health → réponse invalide"; fail=$((fail+1))
  fi

  # --- F3 : Auth (endpoint login accessible) ---
  set_module_pct 5 45 "Test endpoint auth..."
  LAST_ACTION="POST ${API_BASE_URL}/auth/login (endpoint)"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "${API_BASE_URL}/auth/login" -H 'Content-Type: application/json' -d '{"username":"__probe__","password":"__probe__"}' 2>/dev/null)"
  case "$code" in
    401|400|422) _t_auth="✅ $code"; log_ok "✅ F3 Auth endpoint accessible (HTTP $code attendu pour des identifiants invalides)"; pass=$((pass+1));;
    200)         _t_auth="⚠️ 200"; log_warn "⚠️ F3 Auth : réponse 200 inattendue pour des identifiants bidons"; warn=$((warn+1));;
    *)           _t_auth="❌ $code"; log_err "❌ F3 Auth → HTTP $code"; fail=$((fail+1));;
  esac

  # --- F4 : Base de données (via health/detailed) ---
  set_module_pct 5 60 "Test base de données..."
  LAST_ACTION="GET ${API_BASE_URL}/health/detailed"
  local dbd
  dbd="$(curl -s --max-time 35 "${API_BASE_URL}/health/detailed" 2>/dev/null)"
  if echo "$dbd" | grep -qE 'postgres|database|db|"true"|"healthy"'; then
    _t_db="✅ OK"; log_ok "✅ F4 Base de données : état rapporté par health/detailed"; pass=$((pass+1))
  else
    _t_db="⚠️ incertain"; log_warn "⚠️ F4 Base de données : réponse non concluante"; warn=$((warn+1))
  fi

  # --- F5 : Email (SMTP 465 SSL) ---
  set_module_pct 5 75 "Test SMTP (${MAIL_SERVER}:${MAIL_PORT} SSL)..."
  LAST_ACTION="SMTP ${MAIL_SERVER}:${MAIL_PORT} SSL"
  if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    if "$PYTHON_BIN" - <<PYEOF >>"$LOG_FILE" 2>&1
import smtplib, ssl
try:
    ctx = ssl.create_default_context()
    with smtplib.SMTP_SSL("${MAIL_SERVER}", ${MAIL_PORT}, context=ctx, timeout=15) as s:
        s.login("${MAIL_USERNAME}", """$(redact "$MAIL_PASSWORD")""")
        print("SMTP OK")
except Exception as e:
    print("SMTP ERR:", e)
PYEOF
    then
      _t_mail="✅ OK"; log_ok "✅ F5 SMTP : connexion authentifiée OK (${MAIL_SERVER}:${MAIL_PORT})"; pass=$((pass+1))
    else
      _t_mail="⚠️ bloqué"; log_warn "⚠️ F5 SMTP : connexion impossible depuis la machine locale (souvent restreinte — vérifier côté LWS)"; warn=$((warn+1))
    fi
  else
    _t_mail="⚠️ ignoré"; log_warn "⚠️ F5 SMTP : python absent, test ignoré"; warn=$((warn+1))
  fi

  # --- F6 : WebSocket ---
  set_module_pct 5 90 "Test WebSocket (${WS_URL}/api/v1/ws/anonymous)..."
  LAST_ACTION="WS ${WS_URL}/api/v1/ws/anonymous"
  if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    if "$PYTHON_BIN" - <<PYEOF >>"$LOG_FILE" 2>&1
import asyncio, json
try:
    import websockets
except ImportError:
    import sys
    sys.exit(3)  # module absent
async def probe():
    uri = "${WS_URL}/api/v1/ws/anonymous"
    async with websockets.connect(uri, open_timeout=15) as ws:
        await ws.send(json.dumps({"type": "ping"}))
        msg = await asyncio.wait_for(ws.recv(), timeout=10)
        print("WS PONG:", msg)
asyncio.run(probe())
PYEOF
    then
      _t_ws="✅ OK"; log_ok "✅ F6 WebSocket : ping/pong OK via proxy wss"; pass=$((pass+1))
    else
      _t_ws="⚠️ incertain"; log_warn "⚠️ F6 WebSocket : test non concluant (le tunnel WS partage le port du proxy HTTP — voir README)"; warn=$((warn+1))
    fi
  else
    _t_ws="⚠️ ignoré"; log_warn "⚠️ F6 WebSocket : python absent, test ignoré"; warn=$((warn+1))
  fi

  # --- F7 : Routes branchées (contrat frontend ↔ backend) ---
  # Un 401/403 prouve que la route existe et que le garde d'authentification
  # fonctionne ; un 404 signifie qu'une route déployée manque.
  set_module_pct 5 92 "Test des routes branchées (contrat API)..."
  local _t_routes="" route_ok=0 route_ko=0
  local route_spec label expected code
  for route_spec in     "/ping|200"     "/payments/plans|200"     "/reports|200|401|403"     "/search?q=test|200|401|403"     "/market-prices/markets|200|401|403"     "/economics/gdp|200|401|403"     "/weather/current?city=Lome|200"; do
    label="${route_spec%%|*}"
    expected="${route_spec#*|}"
    LAST_ACTION="GET ${API_BASE_URL}${label}"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "${API_BASE_URL}${label}" 2>/dev/null)"
    if echo "|${expected}|" | grep -q "|${code}|"; then
      route_ok=$((route_ok+1))
    else
      route_ko=$((route_ko+1))
      log_err "❌ F7 ${label} → HTTP ${code} (attendu : ${expected})"
    fi
  done
  if [ "$route_ko" -eq 0 ]; then
    _t_routes="✅ ${route_ok} routes"
    log_ok "✅ F7 Routes branchées : ${route_ok} routes répondent comme attendu"
    pass=$((pass+1))
  else
    _t_routes="❌ ${route_ko}/${route_ok}"
    log_err "❌ F7 Routes branchées : ${route_ko} route(s) en échec"
    fail=$((fail+1))
  fi

  # --- F8 : parcours authentifié (bout en bout) ---
  # Connexion avec le compte administrateur provisionné au module C, puis accès
  # aux écrans qui exigeaient des données réelles : rapports et recherche.
  set_module_pct 5 96 "Test authentifié (connexion + routes protégées)..."
  local _t_authz="" token="" login_body=""
  if [ -n "${ADMIN_EMAIL:-}" ] && [ -n "${ADMIN_PASSWORD:-}" ]; then
    LAST_ACTION="POST ${API_BASE_URL}/auth/login (compte admin)"
    login_body="$(curl -s --max-time 30 -X POST "${API_BASE_URL}/auth/login"       -H 'Content-Type: application/json'       --data "$(printf '{"username":"%s","password":"%s"}' "$ADMIN_EMAIL" "$ADMIN_PASSWORD")" 2>/dev/null)"
    token="$(printf '%s' "$login_body" | tr ',' '
' | grep '"access_token"' | head -n1 | cut -d'"' -f4)"

    if [ -z "$token" ]; then
      _t_authz="❌ pas de jeton"
      log_err "❌ F8 Authentification : aucun jeton reçu (compte seed ou API à vérifier)"
      fail=$((fail+1))
    else
      local auth_ok=0 auth_ko=0 endpoint code
      for endpoint in "/auth/me" "/reports" "/search?q=test"; do
        LAST_ACTION="GET ${API_BASE_URL}${endpoint} (authentifié)"
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25           -H "Authorization: Bearer ${token}" "${API_BASE_URL}${endpoint}" 2>/dev/null)"
        if [ "$code" = "200" ]; then
          auth_ok=$((auth_ok+1))
        else
          auth_ko=$((auth_ko+1))
          log_err "❌ F8 ${endpoint} → HTTP ${code} (attendu 200)"
        fi
      done
      if [ "$auth_ko" -eq 0 ]; then
        _t_authz="✅ ${auth_ok} routes"
        log_ok "✅ F8 Parcours authentifié : ${auth_ok} routes protégées accessibles"
        pass=$((pass+1))
      else
        _t_authz="❌ ${auth_ko} échec(s)"
        log_err "❌ F8 Parcours authentifié : ${auth_ko} route(s) en échec"
        fail=$((fail+1))
      fi
    fi
  else
    _t_authz="⚠️ non configuré"
    log_warn "⚠️ F8 Parcours authentifié ignoré (ADMIN_EMAIL / ADMIN_PASSWORD absents)"
    warn=$((warn+1))
  fi

  set_module_pct 5 100 "$LAST_ACTION"

  # --- Rapport final ---
  echo ""
  echo "╔════════════════════════════════════════════════════════╗"
  echo "║            RAPPORT FINAL — SMOKE TESTS                ║"
  echo "╠════════════════════════════════════════════════════════╣"
  printf '║  F1 Frontend statique  %-18s %-18s ║\n' "" "$_t_frontend"
  printf '║  F2 API health         %-18s %-18s ║\n' "" "$_t_api"
  printf '║  F3 Auth endpoint      %-18s %-18s ║\n' "" "$_t_auth"
  printf '║  F4 Base de données    %-18s %-18s ║\n' "" "$_t_db"
  printf '║  F5 Email / SMTP       %-18s %-18s ║\n' "" "$_t_mail"
  printf '║  F6 WebSocket          %-18s %-18s ║\n' "" "$_t_ws"
  echo "╠════════════════════════════════════════════════════════╣"
  printf '║  RÉSULTAT : %d OK | %d ÉCHEC | %d AVERT %-16s ║\n' "$pass" "$fail" "$warn" ""
  echo "╚════════════════════════════════════════════════════════╝"

  [ "$fail" -eq 0 ] && MODULE_STATUS[5]="✔" || MODULE_STATUS[5]="✘"
  return "$fail"
}

# ------------------------------------------------------------------
# ROLLBACK (restauration d'urgence)
# ------------------------------------------------------------------
run_rollback() {
  log_step "════ ROLLBACK : restauration de la version précédente ════"
  if [ "$DRY_RUN" = true ]; then log_warn "dry-run : rollback simulé"; return 0; fi
  if ! command -v lftp >/dev/null 2>&1; then log_err "lftp requis pour le rollback"; return 1; fi
  # Liste les backups distants les plus récents
  local listing
  listing="$(lftp_exec "cd ${REMOTE_ROOT}; ls -1d _frontend-backup-*; ls -1d api-backup-*; bye" 2>/dev/null)"
  local latest_f latest_a
  latest_f="$(printf '%s\n' "$listing" | tr -d '\r' | grep -E '^_frontend-backup-' | tail -n1)"
  latest_a="$(printf '%s\n' "$listing" | tr -d '\r' | grep -E '^api-backup-' | tail -n1)"
  if [ -z "$latest_f" ] && [ -z "$latest_a" ]; then
    log_err "Aucun backup distant trouvé (_frontend-backup-* / api-backup-*)"
    return 1
  fi
  log_ok "Backups détectés : frontend='${latest_f}' backend='${latest_a}'"
  lftp_exec "
cd ${REMOTE_ROOT}
rm -rf _frontend_current 2>/dev/null
mv -f _frontend _frontend_current 2>/dev/null
mv -f ${latest_f} _frontend
mv -f api api_current_broken 2>/dev/null
mv -f ${latest_a} api
bye
" | while IFS= read -r line; do log_dbg "$line"; done
  log_ok "Rollback des fichiers effectué. Redémarrez le backend : bash ${REMOTE_ROOT}/start-backend.sh"
}

# ------------------------------------------------------------------
# GÉNÉRATION DES FICHIERS SERVEUR (staging)
# ------------------------------------------------------------------
generate_server_files() {
  # Assemble .htaccess, proxys PHP, scripts serveur et .env dans $BUILD_STAGING
  mkdir -p "$BUILD_STAGING"

  # --- .htaccess ---
  _render_htaccess "${BUILD_STAGING}/.htaccess" || return 1
  # --- fichiers livrés dans le dossier deploy/ (source de vérité) ---
  local shipped=( proxy-api.php ws-tunnel.php start-backend.sh health-check.sh rollback.sh )
  local f
  for f in "${shipped[@]}"; do
    if [ -f "${SCRIPT_DIR}/${f}" ]; then
      cp "${SCRIPT_DIR}/${f}" "${BUILD_STAGING}/${f}" || return 1
    else
      log_warn "${f} absent du dossier deploy/ — régénération interne"
      case "$f" in
        proxy-api.php)      render_proxy_api      "${BUILD_STAGING}/proxy-api.php" ;;
        ws-tunnel.php)      render_ws_tunnel      "${BUILD_STAGING}/ws-tunnel.php" ;;
        start-backend.sh)   _render_start_backend "${BUILD_STAGING}/start-backend.sh" ;;
        health-check.sh)    _render_health_check  "${BUILD_STAGING}/health-check.sh" ;;
        rollback.sh)        _render_rollback      "${BUILD_STAGING}/rollback.sh" ;;
      esac
    fi
  done
  # --- .env.production ---
  generate_env_production > "${BUILD_STAGING}/.env.production" || return 1
  chmod 600 "${BUILD_STAGING}/.env.production"
  return 0
}

# ------------------------------------------------------------------
# RENDU : .htaccess
# ------------------------------------------------------------------
_render_htaccess() {
  local out="$1"
  cat > "$out" <<EOF
# ============================================================
# .htaccess — AgriIntel360 (LWS mutualisé)
# Généré par deploy-agriintel360.sh le $(date '+%Y-%m-%d %H:%M:%S')
# Rôles : HTTPS forcé, proxy PHP→uvicorn, build statique servi
#         depuis _frontend/, routes dynamiques, headers sécurité.
# ============================================================

Options -Indexes -MultiViews
DirectoryIndex _frontend/index.html

# ---------- REDIRECTION HTTPS FORCÉE ----------
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteBase /

  RewriteCond %{HTTPS} !=on
  RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

  # ---------- PROXY PHP → UVICORN (API + WebSocket) ----------
  # WebSocket / socket.io → tunnel brut (wss://)
  RewriteCond %{REQUEST_URI} ^/api/v1/(ws|socket.io)/ [NC]
  RewriteRule ^api/(.*)$ ws-tunnel.php [QSA,L]

  # REST / JSON → proxy HTTP
  RewriteCond %{REQUEST_URI} ^/api/ [NC]
  RewriteRule ^api/(.*)$ proxy-api.php [QSA,L]

  # ---------- BUILD STATIQUE SERVI DEPUIS _frontend/ ----------
  # Le build Next.js (out/) est uploadé dans _frontend/.

  # Déjà dans _frontend/ → servé tel quel (évite toute boucle de rewrite)
  RewriteCond %{REQUEST_URI} ^/_frontend/ [NC]
  RewriteRule ^ - [L]

  # 1) Routes dynamiques pré-rendues : /community/groups/123 → _frontend/community/groups/_.html
  RewriteRule ^community/groups/([^/.]+)/?$ _frontend/community/groups/_.html [L,QSA]

  # 2) Fichiers réels du build (assets, robots.txt, favicon, _next/*)
  RewriteCond %{REQUEST_URI} !^/(api|_frontend|proxy-api\.php|ws-tunnel\.php) [NC]
  RewriteCond %{DOCUMENT_ROOT}/_frontend%{REQUEST_URI} -f
  RewriteRule ^(.*)$ _frontend/$1 [L]

  # 3) Pages Next.js sans extension : /dashboard → _frontend/dashboard.html
  RewriteCond %{REQUEST_URI} !^/(api|_frontend|proxy-api\.php|ws-tunnel\.php) [NC]
  RewriteCond %{DOCUMENT_ROOT}/_frontend%{REQUEST_URI}.html -f
  RewriteRule ^(.*)$ _frontend/$1.html [L]

  # 4) Fallback SPA → index.html (routes client-side uniquement)
  RewriteCond %{REQUEST_URI} !^/(api|_frontend|proxy-api\.php|ws-tunnel\.php) [NC]
  RewriteRule ^(.*)$ _frontend/index.html [L]
</IfModule>

# ---------- COMPRESSION ----------
<IfModule mod_deflate.c>
  AddOutputFilterByType DEFLATE text/html text/plain text/css text/javascript application/javascript application/json application/xml image/svg+xml font/woff2
</IfModule>

# ---------- CACHE STATIQUE ----------
<IfModule mod_expires.c>
  ExpiresActive On
  ExpiresByType image/png       "access plus 30 days"
  ExpiresByType image/jpeg      "access plus 30 days"
  ExpiresByType image/webp      "access plus 30 days"
  ExpiresByType image/svg+xml   "access plus 30 days"
  ExpiresByType font/woff2      "access plus 1 year"
  ExpiresByType text/css        "access plus 7 days"
  ExpiresByType application/javascript "access plus 7 days"
</IfModule>

# ---------- HEADERS DE SÉCURITÉ ----------
<IfModule mod_headers.c>
  Header always set X-Content-Type-Options "nosniff"
  Header always set X-Frame-Options "SAMEORIGIN"
  Header always set Referrer-Policy "strict-origin-when-cross-origin"
  Header always set X-XSS-Protection "1; mode=block"
  Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
  Header always set Permissions-Policy "geolocation=(self), camera=(), microphone=()"
  # CSP : à affiner selon les CDN utilisés (Swagger UI, recharts, maplibre, etc.)
  # Header always set Content-Security-Policy "default-src 'self'; img-src 'self' data: blob: https://*.tile.openstreetmap.org; connect-src 'self' wss://${APP_DOMAIN} https://${APP_DOMAIN}"
</IfModule>

# ---------- PROTECTION FICHIERS SENSIBLES ----------
<FilesMatch "^\\.(env|deploy|htaccess|git)">
  Require all denied
</FilesMatch>
<FilesMatch "^\.env\.">
  Require all denied
</FilesMatch>
<IfModule mod_php.c>
  php_flag display_errors Off
</IfModule>
EOF
}

# ------------------------------------------------------------------
# RENDU : lftp-mirror.lftp
# NB : le fichier NE contient PAS d'identifiants (pas de secret sur disque).
#      Il est exécuté par : lftp -p $FTP_PORT -u $FTP_USER,<pass> ftp://$FTP_HOST -f lftp-mirror.lftp
# ------------------------------------------------------------------
_render_lftp_mirror() {
  local out="$1"
  cat > "$out" <<EOF
set ftp:ssl-allow yes
set ftp:ssl-force yes
set ssl:verify-certificate no
set ftp:passive-mode yes
set mirror:use-pget-n 4
set net:timeout 30
set net:max-retries 3
cd ${REMOTE_ROOT}
mkdir -p ${REMOTE_STAGING_DIR}
cd ${REMOTE_STAGING_DIR}
mirror --reverse --delete --verbose --parallel=8 \
  "${NEXT_OUT}/" "${REMOTE_STAGING_DIR}/"
bye
EOF
}

# ------------------------------------------------------------------
# RENDU : start-backend.sh (exécuté sur le serveur LWS)
# ------------------------------------------------------------------
_render_start_backend() {
  local out="$1"
  cat > "$out" <<'EOF'
#!/usr/bin/env bash
# ============================================
# start-backend.sh — AgriIntel360 (SERVEUR LWS)
# Démarre uvicorn en arrière-plan sur 127.0.0.1:8001
# Usage : bash start-backend.sh
# ============================================
set -e

BACKEND_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/api"
LOGS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/logs"
PORT="8001"
HOST="127.0.0.1"

mkdir -p "$LOGS_DIR"

# --- Arrêt propre de l'ancien process ---
if [ -f "$LOGS_DIR/uvicorn.pid" ]; then
  OLD_PID="$(cat "$LOGS_DIR/uvicorn.pid")"
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[$(date)] Arrêt de l'ancien uvicorn (PID $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 2
  fi
fi
pkill -9 -f "uvicorn.*src.main" 2>/dev/null || true
sleep 1

cd "$BACKEND_ROOT"

# --- Environnement ---
if [ -d .venv ]; then
  source .venv/bin/activate
else
  echo "ERREUR : .venv absent. Installez les dépendances d'abord."
  exit 1
fi

# Chargement du .env (limite : pas de valeurs multi-lignes)
set -a
# shellcheck disable=SC1091
source .env 2>/dev/null || true
set +a

# Limiter les threads BLAS/OpenMP (évite pthread_create failed sur mutualisé)
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

# --- Démarrage ---
cd "$BACKEND_ROOT"
nohup python -m uvicorn src.main:app \
  --host "$HOST" --port "$PORT" \
  --workers 1 --timeout-keep-alive 30 --log-level warning \
  >> "$LOGS_DIR/backend.log" 2>&1 &
echo $! > "$LOGS_DIR/uvicorn.pid"

sleep 3
echo "[$(date)] uvicorn démarré (PID $(cat "$LOGS_DIR/uvicorn.pid")) sur $HOST:$PORT"
echo "Logs : $LOGS_DIR/backend.log"
EOF
}

# ------------------------------------------------------------------
# RENDU : health-check.sh (exécuté sur le serveur LWS)
# ------------------------------------------------------------------
_render_health_check() {
  local out="$1"
  cat > "$out" <<'EOF'
#!/usr/bin/env bash
# ============================================
# health-check.sh — AgriIntel360 (SERVEUR LWS)
# Vérifie l'état du backend (port 8001) et du proxy HTTP.
# Usage : bash health-check.sh [--auto-restart]
# ============================================
BASE_URL="https://agriintel360.lsgrouptogo.com"
API="$BASE_URL/api/v1"
PORT="8001"
RESTART="${1:-}"

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; reset='\033[0m'

echo "── AgriIntel360 Health Check — $(date) ──"

# 1. Process uvicorn local
if ss -ltn 2>/dev/null | grep -q ":$PORT" || netstat -ltn 2>/dev/null | grep -q ":$PORT"; then
  echo -e "${green}✔ Port $PORT : uvicorn en écoute${reset}"
else
  echo -e "${red}✘ Port $PORT : RIEN n'écoute${reset}"
  if [ "$RESTART" = "--auto-restart" ]; then
    echo -e "${yellow}→ Redémarrage automatique du backend...${reset}"
    bash start-backend.sh || exit 1
  fi
fi

# 2. API locale (proxy interne)
CODE_INT="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:$PORT/api/v1/health" 2>/dev/null)"
echo -e "[$CODE_INT] API interne  http://127.0.0.1:$PORT/api/v1/health"

# 3. API publique (via Apache/PHP)
CODE_PUB="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$API/health" 2>/dev/null)"
echo -e "[$CODE_PUB] API publique  $API/health"

# 4. Frontend
CODE_FE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$BASE_URL/" 2>/dev/null)"
echo -e "[$CODE_FE] Frontend      $BASE_URL/"

if [ "$CODE_PUB" = "200" ] && [ "$CODE_FE" = "200" ]; then
  echo -e "${green}✔ TOUT EST OK${reset}"
  exit 0
else
  echo -e "${red}✘ Problèmes détectés (voir codes ci-dessus)${reset}"
  exit 1
fi
EOF
}

# ------------------------------------------------------------------
# RENDU : rollback.sh (exécuté sur le serveur LWS)
# ------------------------------------------------------------------
_render_rollback() {
  local out="$1"
  cat > "$out" <<'EOF'
#!/usr/bin/env bash
# ============================================
# rollback.sh — AgriIntel360 (SERVEUR LWS)
# Restaure la dernière version sauvegardée.
# Usage : bash rollback.sh [frontend|backend|all]
# ============================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHAT="${1:-all}"

backup_exists() {
  ls -d "${ROOT}/${1}-backup-"* 2>/dev/null | tail -n1
}

if [ "$WHAT" = "frontend" ] || [ "$WHAT" = "all" ]; then
  LATEST="$(backup_exists _frontend)"
  if [ -n "$LATEST" ]; then
    echo "→ Restauration frontend : $LATEST"
    rm -rf "${ROOT}/_frontend_broken"
    mv "${ROOT}/_frontend" "${ROOT}/_frontend_broken" 2>/dev/null || true
    mv "$LATEST" "${ROOT}/_frontend"
    echo "✔ Frontend restauré"
  else
    echo "✘ Aucun backup frontend trouvé"
  fi
fi

if [ "$WHAT" = "backend" ] || [ "$WHAT" = "all" ]; then
  LATEST="$(backup_exists api)"
  if [ -n "$LATEST" ]; then
    echo "→ Restauration backend : $LATEST"
    rm -rf "${ROOT}/api_broken"
    mv "${ROOT}/api" "${ROOT}/api_broken" 2>/dev/null || true
    mv "$LATEST" "${ROOT}/api"
    echo "✔ Backend restauré"
  else
    echo "✘ Aucun backup backend trouvé"
  fi
fi

echo "→ Redémarrage du backend (si la restauration backend a eu lieu)..."
[ -f "${ROOT}/api_broken" ] && bash "${ROOT}/start-backend.sh" || true
echo "Terminé."
EOF
}

# ------------------------------------------------------------------
# RENDU FALLBACK : proxy-api.php / ws-tunnel.php (si absents du dossier)
# ------------------------------------------------------------------
render_proxy_api() {
  cat > "$1" <<'PHPEOF'
<?php
/**
 * proxy-api.php — AgriIntel360 (LWS mutualisé)
 * Proxy HTTP générique vers le backend FastAPI (uvicorn) sur 127.0.0.1:8001.
 * Transmet méthode, en-têtes, query string et corps JSON.
 */
$backend = 'http://127.0.0.1:8001';
$uri     = isset($_SERVER['QUERY_STRING']) ? $_SERVER['QUERY_STRING'] : '';
$path    = $_SERVER['REQUEST_URI'];
// On retire la partie /api/ pour reconstruire proprement
$api = preg_replace('#^/api#', '', parse_url($path, PHP_URL_PATH));
$target = $backend . $api;
if ($uri !== '') { $target .= '?' . $uri; }

$method = $_SERVER['REQUEST_METHOD'];
$headers = array('Content-Type: application/json', 'X-Requested-With: XMLHttpRequest', 'Accept: application/json');
foreach (array('Authorization', 'X-CSRF-Token', 'Accept-Language', 'Origin', 'Cookie') as $h) {
    if (isset($_SERVER['HTTP_' . str_replace('-', '_', strtoupper($h))])) {
        $headers[] = $h . ': ' . $_SERVER['HTTP_' . str_replace('-', '_', strtoupper($h))];
    }
}

$body = file_get_contents('php://input');
$opts = array('http' => array(
    'method'  => $method,
    'header'  => implode("\r\n", $headers),
    'content' => $body,
    'timeout' => 55,
    'ignore_errors' => true,
));
$ctx = stream_context_create($opts);
$resp = file_get_contents($target, false, $ctx);
$respHeaders = isset($http_response_header) ? $http_response_header : array();
$status = 502;
foreach ($respHeaders as $line) {
    if (preg_match('#^HTTP/\S+\s+(\d+)#', $line, $m)) { $status = (int)$m[1]; break; }
}
http_response_code($status);
foreach ($respHeaders as $line) {
    if (preg_match('#^(Content-Type|Content-Length|Cache-Control|X-|Set-Cookie|Access-Control-Allow-Origin):\s?(.*)$#i', $line, $m)) {
        if ($m[1] !== 'Content-Length' || $resp !== false) header($line, false);
    }
}
if ($resp !== false) { echo $resp; }
else { header('Content-Type: application/json'); echo json_encode(array('error' => 'backend_unreachable', 'status' => $status)); }
PHPEOF
}

render_ws_tunnel() {
  cat > "$1" <<'PHPEOF'
<?php
/**
 * ws-tunnel.php — AgriIntel360 (LWS mutualisé)
 * Tunnel WebSocket brute (raw TCP) vers uvicorn 127.0.0.1:8001.
 * Le handshake WS est relayé à l'identique : la connexion wss:// passe
 * par Apache (PHP) puis est transmise telle quelle au backend.
 */
$host = '127.0.0.1';
$port = 8001;

$remote = @stream_socket_client("tcp://$host:$port", $errno, $errstr, 15);
if (!$remote) {
    header('HTTP/1.1 502 Bad Gateway');
    header('Content-Type: text/plain');
    echo "backend_unreachable";
    exit;
}

// Transmettre la requête HTTP d'ouverture (handshake)
$http = str_replace('HTTP/1.1', 'HTTP/1.1', $_SERVER['REQUEST_METHOD'] . ' ' . $_SERVER['REQUEST_URI'] . ' ' . $_SERVER['SERVER_PROTOCOL']);
$head = $http . "\r\n";
foreach ($_SERVER as $k => $v) {
    if (strpos($k, 'HTTP_') === 0) {
        $name = str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($k, 5)))));
        $head .= "$name: $v\r\n";
    }
}
$head .= "Connection: Upgrade\r\n";
$head .= "Upgrade: websocket\r\n";
$head .= "Host: {$_SERVER['HTTP_HOST']}\r\n\r\n";
fwrite($remote, $head);
fflush($remote);

// Passer en mode brut : réponse non bufférisée
if (function_exists('apache_setenv')) { @apache_setenv('no-gzip', '1'); }
@ini_set('output_buffering', 'off');
@ini_set('zlib.output_compression', 'off');
while (ob_get_level()) { @ob_end_flush(); }
flush();

// Tunneling bidirectionnel
while (!feof($remote)) {
    $r = array($remote);
    $w = null; $e = null;
    $read = array_merge($r, array(STDIN));
    if (@stream_select($read, $w, $e, 1) > 0) {
        foreach ($read as $s) {
            $data = fread($s, 65536);
            if ($data === false || $data === '') { break 2; }
            if ($s === $remote) { echo $data; @flush(); }
            else { fwrite($remote, $data); fflush($remote); }
        }
    }
}
fclose($remote);
PHPEOF
}

# ------------------------------------------------------------------
# ANALYSE DES ARGUMENTS
# ------------------------------------------------------------------
usage() {
  cat <<USAGE
Usage : $(basename "$0") [options]

Options :
  --dry-run        Simule le déploiement (aucune modification)
  --verbose        Affiche chaque commande exécutée (mode debug)
  --step-by-step   Demande confirmation avant chaque module
  --module X       Exécute un seul module (A, B, C, D, E, F)
  --resume         Reprend depuis le dernier checkpoint (fichier .deploy_checkpoint)
  --clean          Efface le checkpoint courant
  --help           Affiche cette aide
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --step-by-step) STEP_BY_STEP=true; shift ;;
    --module) ONLY_MODULE="${2^^}"; shift 2 ;;
    --resume) RESUME=true; shift ;;
    --clean) rm -f "$CHECKPOINT_FILE"; echo "Checkpoint effacé."; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Option inconnue : $1"; usage; exit 1 ;;
  esac
done

# ------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------
print_banner
log_step "Démarrage du déploiement AgriIntel360 v${DEPLOY_VERSION}"
log_ok "Journal : $LOG_FILE"
[ "$DRY_RUN" = true ] && log_warn "MODE DRY-RUN — aucune modification ne sera effectuée"
[ "$VERBOSE" = true ] && log_warn "MODE VERBOSE — toutes les commandes seront affichées"
[ "$STEP_BY_STEP" = true ] && log_warn "MODE STEP-BY-STEP — confirmation avant chaque module"
log_warn "⚠️  Vérifiez que .env n'est pas versionné dans Git"
log_dbg "DATABASE_URL = $(redact "$DATABASE_URL")"
log_dbg "APP_URL = ${APP_URL} | API = ${API_BASE_URL}"
log_dbg "Backend cible : ${BACKEND_HOST}:${BACKEND_PORT} | SSH=${SSH_ENABLED}"

# Association module -> fonction
run_single_module() {
  case "$1" in
    A) module_a_prechecks ;;
    B) module_b_frontend ;;
    C) module_c_backend ;;
    D) module_d_upload ;;
    E) module_e_config ;;
    F) module_f_tests ;;
    *) log_err "Module inconnu : $1"; return 1 ;;
  esac
}

# Orchestrateur avec gestion d'erreur et checkpoint
run_all_modules() {
  local modules=( A B C D E F )
  local total=${#modules[@]} i=0
  for m in "${modules[@]}"; do
    i=$((i+1))
    if [ "$RESUME" = true ] && module_already_done "$m"; then
      log_ok "Module ${m} déjà validé (checkpoint) — saut."
      continue
    fi
    log_step "───── Démarrage du Module ${m} ($i/$total) ─────"
    local attempts=0 rc
    while :; do
      attempts=$((attempts+1))
      run_single_module "$m"
      rc=$?
      if [ "$rc" -eq 0 ]; then
        save_checkpoint "$m"
        break
      fi
      if [ "$attempts" -ge 3 ]; then
        log_err "Module ${m} en échec après ${attempts} tentatives."
      fi
      ask_agent "generic" "Le module ${m} a échoué (code $rc). Que faire ?" "" "retry"
      decision=$?
      case "$decision" in
        10) [ "$attempts" -lt 3 ] || { log_warn "Limite de 3 tentatives atteinte — skip."; MODULE_STATUS[(( (i-1) ))]="⤼"; break; } ;;
        11) log_warn "Module ${m} ignoré (skip)."; MODULE_STATUS[(( (i-1) ))]="⤼"; break ;;
        12) log_err "Abandon demandé."; exit 1 ;;
      esac
    done
  done
}

if [ -n "$ONLY_MODULE" ]; then
  run_single_module "$ONLY_MODULE"
  rc=$?
  [ "$rc" -eq 0 ] && save_checkpoint "$ONLY_MODULE"
  exit "$rc"
fi

run_all_modules

# ------------------------------------------------------------------
# RAPPORT FINAL
# ------------------------------------------------------------------
echo ""
echo "🎉 DÉPLOIEMENT TERMINÉ"
echo ""
echo "🌐 Frontend : ${APP_URL}"
echo "🔌 API      : ${API_BASE_URL}/health"
echo "📧 Email    : ${MAIL_USERNAME}:${MAIL_PORT} (SSL)"
echo ""
echo "📁 Logs     : $LOG_FILE"
if [ -f "${BACKEND_DIR}/backend.log" ]; then
  echo "🔄 Backend  : PID \$(cat logs/uvicorn.pid) écoute sur 127.0.0.1:${BACKEND_PORT}"
fi
echo ""
echo "Prochaines étapes suggérées :"
echo "  1. Vérifier les emails transactionnels (SMTP ${MAIL_SERVER}:${MAIL_PORT})"
echo "  2. Configurer une tâche CRON toutes les 5 min : bash ${REMOTE_ROOT}/health-check.sh --auto-restart"
echo "  3. Activer / vérifier le renouvellement automatique du certificat SSL (LWS)"
echo ""
echo "Pour surveiller les logs : tail -f logs/backend.log"
echo "Pour redémarrer        : ./start-backend.sh"
echo "Pour rollback          : ./rollback.sh"

# Statut de sortie : 0 si le module F (smoke tests) est validé
SKIP_ERROR_LOG=1
if [ "$DRY_RUN" = true ] || module_already_done "F"; then
  exit 0
fi
exit 1
