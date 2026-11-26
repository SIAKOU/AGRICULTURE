#!/usr/bin/env bash
# ============================================================
# health-check.sh — AgriIntel360 (à exécuter sur le serveur LWS)
#
# Vérifie, dans l'ordre : processus, API interne, API publique, frontend,
# puis un jeu de tests de fumée sur les routes critiques. Le script sort en
# erreur (code 1) dès qu'une vérification échoue, ce qui permet de l'utiliser
# comme garde-fou à la fin d'un déploiement.
#
# Usage :
#   bash health-check.sh                 # diagnostic complet
#   bash health-check.sh --auto-restart  # redémarre le backend si muet
#   bash health-check.sh --email         # envoie une alerte si échec
#   bash health-check.sh --smoke-only    # uniquement les tests de fumée API
#
# Parcours authentifié (facultatif) : exporter SMOKE_EMAIL et SMOKE_PASSWORD.
#   SMOKE_EMAIL=... SMOKE_PASSWORD=... bash health-check.sh --smoke-only
# Sans ces variables, la section est ignorée (avertissement, pas d'échec).
#
# Codes attendus : une route protégée doit répondre 401/403 (le garde
# d'authentification fonctionne) — un 404 signale une route absente, donc un
# déploiement incomplet.
# ============================================================
set -u

APP_URL="https://agriintel360.lsgrouptogo.com"
API="${APP_URL}/api/v1"
HOST="127.0.0.1"
PORT="8001"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; reset='\033[0m'
DATE="$(date '+%Y-%m-%d %H:%M:%S')"
MODE="${1:-}"

# Identifiants facultatifs du parcours authentifié, lus dans un fichier local
# non versionné (permissions 600) pour ne jamais les écrire dans la crontab.
# Format : SMOKE_EMAIL=... / SMOKE_PASSWORD=...
if [ -f "${ROOT}/.health-smoke-env" ]; then
  # shellcheck disable=SC1091
  set -a; . "${ROOT}/.health-smoke-env"; set +a
fi

OVERALL=0
FAILED_NAMES=()

# ------------------------------------------------------------
# check_route <libellé> <url> <codes attendus séparés par |>
# ------------------------------------------------------------
check_route() {
  local label="$1" url="$2" expected="$3"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 "$url" 2>/dev/null)"
  local ok=1
  local IFS='|'
  for candidate in $expected; do
    [ "$code" = "$candidate" ] && ok=0
  done
  unset IFS

  if [ "$ok" -eq 0 ]; then
    printf '%b✔ %-46s → %s%b\n' "$green" "$label" "$code" "$reset"
    return 0
  fi
  printf '%b✘ %-46s → %s (attendu : %s)%b\n' "$red" "$label" "$code" "$expected" "$reset"
  OVERALL=1
  FAILED_NAMES+=("$label (HTTP $code)")
  return 1
}

echo "── AgriIntel360 Health Check — $DATE ──"

if [ "$MODE" != "--smoke-only" ]; then
  # ---------- 1. Processus uvicorn ----------
  if (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null) | grep -q ":${PORT} "; then
    printf '%b✔ [1/9] uvicorn en écoute sur %s:%s%b\n' "$green" "$HOST" "$PORT" "$reset"
  else
    printf '%b✘ [1/9] RIEN n’écoute sur %s:%s%b\n' "$red" "$HOST" "$PORT" "$reset"
    OVERALL=1
    FAILED_NAMES+=("uvicorn muet sur ${PORT}")
    if [ "$MODE" = "--auto-restart" ]; then
      printf '%b→ Redémarrage automatique du backend…%b\n' "$yellow" "$reset"
      bash "${ROOT}/start-backend.sh" || exit 1
      sleep 5
      if (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null) | grep -q ":${PORT} "; then
        OVERALL=0
      fi
    fi
  fi

  # ---------- 2. API interne (uvicorn direct) ----------
  check_route "API interne /health" "http://${HOST}:${PORT}/api/v1/health" "200"

  # ---------- 3. API publique (via Apache/PHP) ----------
  check_route "API publique /health" "${API}/health" "200"

  # ---------- 4. Frontend statique ----------
  check_route "Frontend /" "${APP_URL}/" "200"
else
  echo "(mode tests de fumée uniquement)"
fi

# ------------------------------------------------------------
# 5 → 9. Tests de fumée des routes réellement branchées
#    (voir docs/ANALYSE.md §6 et scripts/check-api-contract.py)
# ------------------------------------------------------------

# 5. Sonde sans authentification ni base : prouve que FastAPI répond.
check_route "GET /ping" "${API}/ping" "200"

# 6. Météo : dépend de la source externe Open-Meteo. Un 200 prouve que le
#    backend sort bien sur Internet ; 502/503 signale une source injoignable.
check_route "GET /weather/current (Open-Meteo)" "${API}/weather/current?city=Lome" "200"

# 7. Économie : dépend de la Banque mondiale (route protégée).
check_route "GET /economics/gdp (World Bank)" "${API}/economics/gdp" "200|401|403"

# 8. Routes ajoutées cette itération : un 401/403 prouve qu'elles existent et
#    sont protégées ; un 404 signifie qu'elles n'ont pas été déployées.
check_route "GET /search" "${API}/search?q=test" "200|401|403"
check_route "GET /market-prices/markets" "${API}/market-prices/markets" "200|401|403"

# 9. Paiements : /plans est public (sert la grille tarifaire).
check_route "GET /payments/plans" "${API}/payments/plans" "200"

# ------------------------------------------------------------
# Parcours authentifié (optionnel)
#   Activé si SMOKE_EMAIL + SMOKE_PASSWORD sont fournis (variables
#   d'environnement) ou si les identifiants admin sont exportés par
#   deploy-config.sh. Sans identifiants : simple avertissement, pas d'échec.
#   Aucun mot de passe n'est journalisé ni affiché.
# ------------------------------------------------------------
auth_smoke() {
  local email="${SMOKE_EMAIL:-${ADMIN_EMAIL:-}}"
  local password="${SMOKE_PASSWORD:-${ADMIN_PASSWORD:-}}"

  if [ -z "$email" ] || [ -z "$password" ]; then
    printf '%b… Parcours authentifié ignoré (SMOKE_EMAIL / SMOKE_PASSWORD absents)%b\n' "$yellow" "$reset"
    return 0
  fi

  local payload login_body token code endpoint
  payload="$(printf '{"username":"%s","password":"%s"}' "$email" "$password")"
  login_body="$(curl -s --max-time 25 -X POST "${API}/auth/login" \
    -H 'Content-Type: application/json' --data "$payload" 2>/dev/null)"

  # Extraction du jeton sans expression régulière à référence arrière : on éclate
  # le JSON sur les virgules, on garde la ligne "access_token", on prend le 4e
  # champ entre guillemets.
  token="$(printf '%s' "$login_body" | tr ',' '\n' \
    | grep '"access_token"' | head -n1 | cut -d'"' -f4)"

  if [ -z "$token" ]; then
    printf '%b✘ Connexion API impossible pour le compte de test (identifiants ou API)%b\n' "$red" "$reset"
    OVERALL=1
    FAILED_NAMES+=("auth/login (compte de test)")
    return 1
  fi
  printf '%b✔ Connexion API du compte de test (%s)%b\n' "$green" "$email" "$reset"

  for endpoint in "/auth/me" "/reports" "/search?q=test" "/notifications"; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 25 \
      -H "Authorization: Bearer ${token}" "${API}${endpoint}" 2>/dev/null)"
    if [ "$code" = "200" ]; then
      printf '%b✔ Authentifié %-38s → %s%b\n' "$green" "$endpoint" "$code" "$reset"
    else
      printf '%b✘ Authentifié %-38s → %s%b\n' "$red" "$endpoint" "$code" "$reset"
      OVERALL=1
      FAILED_NAMES+=("authentifié $endpoint (HTTP $code)")
    fi
  done
}

auth_smoke

# ---------- Conclusion ----------
if [ "$OVERALL" -eq 0 ]; then
  printf '%b✔ TOUT EST OK — %s%b\n' "$green" "$DATE" "$reset"
  exit 0
fi

printf '%b✘ PROBLÈMES DÉTECTÉS — %s%b\n' "$red" "$DATE" "$reset"
for name in "${FAILED_NAMES[@]:-}"; do
  [ -n "$name" ] && echo "   · $name"
done
echo "   Logs backend : ${ROOT}/logs/backend.log"

if [ "$MODE" = "--email" ]; then
  MAILFILE="$(mktemp)"
  {
    echo "Subject: [AgriIntel360] ALERTE santé $DATE"
    echo ""
    echo "Health check en échec :"
    for name in "${FAILED_NAMES[@]:-}"; do
      [ -n "$name" ] && echo " - $name"
    done
    echo ""
    echo "--- /health ---"
    curl -s --max-time 15 "${API}/health" || true
  } > "$MAILFILE"
  sendmail -f "doc@agriintel360.lsgrouptogo.com" "doc@agriintel360.lsgrouptogo.com" < "$MAILFILE" 2>/dev/null || \
    curl -s --url "smtps://agriintel360.lsgrouptogo.com:465" --ssl-reqd \
      --mail-from "doc@agriintel360.lsgrouptogo.com" \
      --mail-rcpt "doc@agriintel360.lsgrouptogo.com" \
      --upload-file "$MAILFILE" 2>/dev/null || \
    echo "   (envoi d’e-mail indisponible sur cet hôte)"
  rm -f "$MAILFILE"
fi

exit 1
