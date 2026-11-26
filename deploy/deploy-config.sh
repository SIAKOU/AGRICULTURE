#!/usr/bin/env bash
# ============================================
# FICHIER : deploy-config.sh
# DESCRIPTION : Configuration centralisée du déploiement AgriIntel360
# AUTEUR : Agent DevOps AgriIntel360
# DATE : $(date +%Y-%m-%d)
#
# USAGE : Ce fichier est sourcé (source) par les scripts de déploiement.
#         Il ne doit JAMAIS être exécuté directement.
#
# SECURITE : Les mots de passe présents ici sont des SECRETS.
#            - Ne versionnez PAS ce fichier dans git.
#            - Restreignez les permissions : chmod 600 deploy-config.sh
#            - En production, préférez les variables d'environnement :
#              export AGRI_FTP_PASS=... && ./deploy-agriintel360.sh
# ============================================

# ------------------------------------------------------------------
# VERSION & MODE
# ------------------------------------------------------------------
DEPLOY_VERSION="1.0.0"
# Mode opératoire par défaut : "production". Peut être "dry-run".
DEPLOY_MODE="${AGRI_DEPLOY_MODE:-production}"

# ------------------------------------------------------------------
# CHEMINS LOCAUX (machine de développement)
# ------------------------------------------------------------------
# Racine du projet (deux dossiers frères : frontend + backend)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="${PROJECT_ROOT}/frontend"
BACKEND_DIR="${PROJECT_ROOT}/backend"
DEPLOY_DIR="${PROJECT_ROOT}/deploy"

# Dossier de sortie du build statique Next.js (défini par next.config.js : output:'export')
NEXT_OUT="${FRONTEND_DIR}/out"
# Fichier de build temporaire (préparation des fichiers à uploader)
BUILD_STAGING="${DEPLOY_DIR}/staging"

# ------------------------------------------------------------------
# HEBERGEMENT LWS — FTP
# ------------------------------------------------------------------
FTP_HOST="ftp.lsgrouptogo.com"
FTP_PORT="21"
FTP_USER="doc@agriintel360.lsgrouptogo.com"
# Mot de passe : préférer la variable d'env AGRI_FTP_PASS (conseillé)
# puis le fichier .deploy-secrets (ignoré par git) avant de fallback ici.
FTP_PASS_DEFAULT='.OYhsGzlo&#e1@]Y'
# Mode FTP : "ftps" (explicite) ou "ftps_implicit". LWS supporte le FTPS explicite.
FTP_MODE="${AGRI_FTP_MODE:-ftps}"
# Mode passif/actif : "passive" (recommandé derrière un pare-feu) ou "active"
FTP_PASSIVE="${AGRI_FTP_PASSIVE:-passive}"

# Répertoire racine distant (relatif à la racine FTP du compte)
REMOTE_ROOT="/agriintel360.lsgrouptogo.com"
REMOTE_BACKEND_DIR="${REMOTE_ROOT}/api"
REMOTE_LOGS_DIR="${REMOTE_ROOT}/logs"
REMOTE_STAGING_DIR="${REMOTE_ROOT}/_frontend"
# Dossier "live" réellement servi — identique à la racine du domaine
REMOTE_LIVE_DIR="${REMOTE_ROOT}"

# ------------------------------------------------------------------
# BASE DE DONNÉES PostgreSQL (LWS)
# ------------------------------------------------------------------
DB_HOST="127.0.0.1"     # localhost résout ::1 et est refusé sur LWS → 127.0.0.1
DB_PORT="5432"
DB_NAME="c2606883c_agriintel360"
DB_USER="c2606883c_agriintel"
DB_PASS_DEFAULT='VZAT?Ka$22zBKsaY'

# ------------------------------------------------------------------
# DOMAINE / APPLICATION
# ------------------------------------------------------------------
APP_DOMAIN="agriintel360.lsgrouptogo.com"
APP_URL="https://${APP_DOMAIN}"
API_BASE_URL="${APP_URL}/api/v1"
WS_URL="wss://${APP_DOMAIN}"
# Compte admin par défaut (seed en Module C)
ADMIN_EMAIL="admin@agriintel360.lsgrouptogo.com"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD_DEFAULT='AgriInt3l_2026!ChangeMe'
ADMIN_FULL_NAME="Administrateur AgriIntel360"

# ------------------------------------------------------------------
# EMAIL / SMTP (LWS)
# ------------------------------------------------------------------
MAIL_SERVER="${APP_DOMAIN}"
MAIL_PORT="465"
MAIL_USE_SSL="true"
MAIL_USERNAME="doc@agriintel360.lsgrouptogo.com"
# Par défaut : mêmes identifiants que le compte FTP/email LWS
MAIL_PASSWORD_DEFAULT="${FTP_PASS_DEFAULT}"

# ------------------------------------------------------------------
# OUTILS LOCAUX
# ------------------------------------------------------------------
NODE_MIN_VERSION="18"
NPM_MIN_VERSION="9"
# Binaire Python : python3.12 est préféré (requis par requirements.txt)
PYTHON_BIN="${AGRI_PYTHON_BIN:-python3.12}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  PYTHON_BIN="python3"
fi

# ------------------------------------------------------------------
# BACKEND — venv & migrations
# ------------------------------------------------------------------
BACKEND_VENV="${BACKEND_DIR}/.venv"
# Limiter les threads BLAS/OpenMP (évite "pthread_create failed" sur mutualisé)
export OPENBLAS_NUM_THREADS=1
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1

# ------------------------------------------------------------------
# PORTAIL UVICORN
# ------------------------------------------------------------------
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="8001"

# ------------------------------------------------------------------
# SSH OPTIONNEL (si activé sur l'hébergement LWS)
# Si AGRI_SSH_ENABLED=true, le déploiement exécutera les commandes
# serveur (start/stop backend) à distance au lieu d'afficher des instructions.
SSH_ENABLED="${AGRI_SSH_ENABLED:-false}"
SSH_HOST="agriintel360.lsgrouptogo.com"
SSH_PORT="22"
SSH_USER="${FTP_USER}"

# ------------------------------------------------------------------
# JOURNALISATION
# ------------------------------------------------------------------
LOGS_DIR="${DEPLOY_DIR}/logs"
CHECKPOINT_FILE="${DEPLOY_DIR}/.deploy_checkpoint"
SECRETS_FILE="${DEPLOY_DIR}/.deploy-secrets"

# ------------------------------------------------------------------
# COULEURS TERMINAL
# ------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[0;31m'
  C_GREEN=$'\033[0;32m'
  C_YELLOW=$'\033[0;33m'
  C_BLUE=$'\033[0;34m'
  C_MAGENTA=$'\033[0;35m'
  C_CYAN=$'\033[0;36m'
  C_GRAY=$'\033[0;90m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""
  C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_GRAY=""
fi

# ------------------------------------------------------------------
# RESOLUTION DES SECRETS (env > fichier secrets > valeur par défaut)
# ------------------------------------------------------------------
# Charger les secrets éventuellement stockés dans .deploy-secrets
# (créé automatiquement à la première exécution avec permissions 600)
_resolve_secret() {
  # $1 = variable env, $2 = valeur par défaut
  local env_var="$1" default="$2" file_val=""
  if [ -f "$SECRETS_FILE" ]; then
    file_val="$(grep -E "^${env_var}=" "$SECRETS_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)"
  fi
  if [ -n "${!env_var:-}" ]; then
    printf '%s' "${!env_var}"
  elif [ -n "$file_val" ]; then
    printf '%s' "$file_val"
  else
    printf '%s' "$default"
  fi
}

FTP_PASS="$( _resolve_secret AGRI_FTP_PASS "$FTP_PASS_DEFAULT" )"
DB_PASS="$(  _resolve_secret AGRI_DB_PASS   "$DB_PASS_DEFAULT" )"
MAIL_PASSWORD="$( _resolve_secret AGRI_MAIL_PASSWORD "$MAIL_PASSWORD_DEFAULT" )"
ADMIN_PASSWORD="$( _resolve_secret AGRI_ADMIN_PASSWORD "$ADMIN_PASSWORD_DEFAULT" )"

# ------------------------------------------------------------------
# JWT SECRET (généré une fois puis réutilisé)
# ------------------------------------------------------------------
JWT_SECRET_FILE="${DEPLOY_DIR}/.deploy-jwt-secret"
if [ -f "$JWT_SECRET_FILE" ]; then
  JWT_SECRET_KEY="$(cat "$JWT_SECRET_FILE")"
else
  JWT_SECRET_KEY="$(openssl rand -hex 64 2>/dev/null || head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  if [ -n "$JWT_SECRET_KEY" ]; then
    umask 077
    printf '%s' "$JWT_SECRET_KEY" > "$JWT_SECRET_FILE"
  fi
fi

# ------------------------------------------------------------------
# LISTE DES SECRETS À MASQUER DANS LES LOGS
# ------------------------------------------------------------------
declare -a SECRET_VALUES=( "$FTP_PASS" "$DB_PASS" "$MAIL_PASSWORD" "$ADMIN_PASSWORD" "$JWT_SECRET_KEY" )

# ------------------------------------------------------------------
# DATABASE_URL construite automatiquement (encodage URL des caractères spéciaux)
# ------------------------------------------------------------------
_build_database_url() {
  # Encode le mot de passe pour l'inclure dans une URL (VZAT?Ka$22zBKsaY → VZAT%3FKa%2422zBKsaY)
  local enc
  enc="$("$PYTHON_BIN" -c "import urllib.parse,sys;print(urllib.parse.quote_plus(sys.argv[1], safe=''))" "$DB_PASS" 2>/dev/null)"
  if [ -z "$enc" ]; then
    # Fallback si python indisponible : encodage minimal @ et ?
    enc="$(printf '%s' "$DB_PASS" | sed 's/@/%40/g; s/?/%3F/g; s/\$/%24/g; s/&/%26/g; s/#/%23/g')"
  fi
  printf 'postgresql://%s:%s@%s:%s/%s' "$DB_USER" "$enc" "$DB_HOST" "$DB_PORT" "$DB_NAME"
}
DATABASE_URL="$(_build_database_url)"

# ------------------------------------------------------------------
# TEMPLATE .env DE PRODUCTION (sera uploadé sur le serveur)
# ------------------------------------------------------------------
# Cette fonction est utilisée par deploy-agriintel360.sh pour générer
# le .env.production à envoyer sur LWS.
generate_env_production() {
  cat <<EOF
# ============================================
# AgriIntel360 — Environnement de PRODUCTION
# Généré le $(date '+%Y-%m-%d %H:%M:%S') par deploy-agriintel360.sh
# NE PAS COMMITTER CE FICHIER — permissions 600
# ============================================

ENVIRONMENT=production
DEBUG=false

# Base de données PostgreSQL (LWS)
DATABASE_URL=${DATABASE_URL}
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}

# Session / Cache : Redis si disponible, sinon fallback filesystem
REDIS_URL=redis://127.0.0.1:6379

# Sécurité
JWT_SECRET_KEY=${JWT_SECRET_KEY}
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30
JWT_REFRESH_TOKEN_EXPIRE_DAYS=7
ALLOWED_HOSTS=["${APP_DOMAIN}","localhost","127.0.0.1"]

# Compte admin par défaut
DEFAULT_ADMIN_EMAIL=${ADMIN_EMAIL}
DEFAULT_ADMIN_USERNAME=${ADMIN_USERNAME}
DEFAULT_ADMIN_PASSWORD=${ADMIN_PASSWORD}
DEFAULT_ADMIN_FULL_NAME=${ADMIN_FULL_NAME}

# CORS — jamais "*" en production
BACKEND_CORS_ORIGINS=["https://${APP_DOMAIN}","https://www.${APP_DOMAIN}","http://127.0.0.1:8001","http://localhost:3000"]

# Frontend
FRONTEND_URL=${APP_URL}

# Email / SMTP (LWS — port 465 SSL)
MAIL_SERVER=${MAIL_SERVER}
MAIL_PORT=${MAIL_PORT}
MAIL_USE_SSL=${MAIL_USE_SSL}
MAIL_STARTTLS=false
MAIL_USERNAME=${MAIL_USERNAME}
MAIL_PASSWORD=${MAIL_PASSWORD}
MAIL_FROM="AgriIntel360 <${MAIL_USERNAME}>"
MAIL_FROM_NAME=AgriIntel360
SMTP_HOST=${MAIL_SERVER}
SMTP_PORT=${MAIL_PORT}
SMTP_USERNAME=${MAIL_USERNAME}
SMTP_PASSWORD=${MAIL_PASSWORD}
SMTP_SSL=true

# Logs
LOG_LEVEL=INFO
LOG_FILE=logs/agriintel360.log

# Paramètres serveur (mutualisé)
UPLOAD_DIR=uploads
ML_MODEL_PATH=ml-models
MODEL_UPDATE_INTERVAL_HOURS=24
PROMETHEUS_ENABLED=true
RATE_LIMIT_PER_MINUTE=60
EOF
}

# ------------------------------------------------------------------
# Bannière de démarrage
# ------------------------------------------------------------------
print_banner() {
  cat <<"BANNER"
╔══════════════════════════════════════════════════════════════╗
║     🌾 AGRIINTEL360 — DÉPLOIEMENT AUTOMATISÉ v1.0          ║
╚══════════════════════════════════════════════════════════════╝
BANNER
}
