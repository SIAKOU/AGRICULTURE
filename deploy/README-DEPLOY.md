# 🌾 AgriIntel360 — Déploiement Automatisé (LWS Mutualisé)

Suite de scripts **DevOps** pour déployer l'application complète AgriIntel360
(Frontend **Next.js 15** statique + Backend **FastAPI**) sur un hébergement
**mutualisé LWS**, avec assistance contextuelle, barre de progression,
journalisation et reprise automatique sur erreur.

---

## 1. Architecture cible

```
agriintel360.lsgrouptogo.com  (racine : /agriintel360.lsgrouptogo.com/)
│
├── _frontend/                  ← BUILD STATIQUE Next.js (export) — SERVI PAR .htaccess
│   ├── index.html / _next/…    ← pages, assets, robots.txt
│   └── community/groups/_.html ← route dynamique pré-rendue (generateStaticParams)
├── .htaccess                   ← HTTPS, proxy API, serv _frontend/, headers sécurité
├── proxy-api.php               ← Proxy HTTP PHP → uvicorn (127.0.0.1:8001)
├── ws-tunnel.php               ← Tunnel WebSocket brut → uvicorn
├── start-backend.sh            ← Démarrage/redémarrage du backend
├── health-check.sh             ← Diagnostic post-déploiement (+ auto-restart / alerte)
├── rollback.sh                 ← Restauration d'urgence
├── api/                        ← Code backend FastAPI + .venv + .env
├── logs/                       ← backend.log, uvicorn.pid
└── _frontend-backup-* / api-backup-*   ← sauvegardes pré-déploiement
```

> **Nota structure** : le build statique est uploadé dans **`_frontend/`**.
> Le `.htaccess` à la racine réécrit toutes les requêtes vers ce sous-dossier
> (`/dashboard` → `_frontend/dashboard.html`, `/` → `_frontend/index.html`),
> ce qui permet les sauvegardes/rollback par simple renommage de dossier.

---

## 2. Contenu du dossier `deploy/`

| Fichier | Rôle |
|---|---|
| `deploy-agriintel360.sh` | **Script principal** — Modules A→F, progression, reprise, rollback |
| `deploy-config.sh` | **Configuration centralisée** (chemins, FTP, DB, SMTP, secrets) |
| `lftp-mirror.lftp` | Script `lftp` pour le mirror du frontend (sans identifiants) |
| `.htaccess` | Règles Apache (référence — régénéré par le script principal) |
| `proxy-api.php` | Proxy HTTP PHP vers uvicorn (requis sur hébergement mutualisé) |
| `ws-tunnel.php` | Tunnel WebSocket brut vers uvicorn |
| `start-backend.sh` | Launcher backend **à exécuter sur LWS** |
| `health-check.sh` | Smoke tests **à exécuter sur LWS** (ou planifiés en CRON) — routes branchées + parcours connecté |
| `install-cron.sh` | Installe/met à jour la tâche CRON de surveillance (idempotent, sauvegarde la crontab) |
| `rollback.sh` | Restauration d'urgence **à exécuter sur LWS** |
| `README-DEPLOY.md` | Ce document |

---

## 3. Pré-requis

**Sur la machine de développement** (Linux, WSL ou Git-Bash) :

- Bash ≥ 5, `curl`, `openssl`
- **Node.js ≥ 18** et **npm ≥ 9**
- **Python 3.12** (recommandé) — ou toute version ≥ 3.11
- **lftp** *(fortement recommandé pour le mirror FTP)*
  - Debian/Ubuntu : `sudo apt install lftp` · Windows : `choco install lftp`
- (Optionnel) `psql` et `ssh` pour les vérifications avancées

**Côté LWS** :
- Accès FTP/FTPS (compte `doc@agriintel360.lsgrouptogo.com`)
- Base PostgreSQL `c2606883c_agriintel360` créée
- (Recommandé) SSH activé sur l'hébergement → démarrage automatisé du backend

---

## 4. Configuration (`deploy-config.sh`)

Toutes les valeurs modifiables sont en tête de fichier :

- Chemins locaux `FRONTEND_DIR` / `BACKEND_DIR`
- FTP : `FTP_HOST`, `FTP_PORT`, `FTP_USER`, `FTP_MODE` (`ftps`/`ftp`)
- PostgreSQL : `DB_HOST` (→ `127.0.0.1`, jamais `localhost`), `DB_NAME`, `DB_USER`
- Domaine : `APP_DOMAIN`, `ADMIN_EMAIL`, `ADMIN_USERNAME`
- SMTP : `MAIL_SERVER`, `MAIL_PORT=465`, `MAIL_USERNAME`
- SSH optionnel : `SSH_ENABLED=true` pour le pilotage distant

### 4.1 Gestion des secrets (sécurité)

Ordre de résolution (le premier trouvé gagne) :

1. Variables d'environnement : `AGRI_FTP_PASS`, `AGRI_DB_PASS`,
   `AGRI_MAIL_PASSWORD`, `AGRI_ADMIN_PASSWORD`
2. Fichier `deploy/.deploy-secrets` (au format `AGRI_FTP_PASS=…`, permissions **600**)
3. Valeurs par défaut définies dans `deploy-config.sh`

Le **JWT_SECRET_KEY** (64 octets hex) est généré une fois avec `openssl rand -hex 64`
et stocké dans `deploy/.deploy-jwt-secret` (permissions **600**).

> ⚠️ **Le `DATABASE_URL` est construit automatiquement avec le mot de passe
> encodé en URL** (`VZAT?Ka$22zBKsaY` → `VZAT%3FKa%2422zBKsaY`) — indispensable
> avec les caractères spéciaux `?`, `$`, `@`.

> 🔒 **Règles d'or** : ne jamais committer `.env`, `.deploy-secrets`,
> `.deploy-jwt-secret` ni `deploy-config.sh`. Utiliser `chmod 600` sur ces fichiers.

---

## 5. Utilisation

```bash
cd deploy

# Prévisualisation (aucune modification)
bash deploy-agriintel360.sh --dry-run

# Déploiement complet
bash deploy-agriintel360.sh

# Déploiement verbeux (affiche toutes les commandes)
bash deploy-agriintel360.sh --verbose

# Mode pas-à-pas (confirmation avant chaque module)
bash deploy-agriintel360.sh --step-by-step

# Un seul module (A|B|C|D|E|F)
bash deploy-agriintel360.sh --module B

# Reprise après un échec (reprend au dernier checkpoint)
bash deploy-agriintel360.sh --resume

# Efface le checkpoint courant
bash deploy-agriintel360.sh --clean
```

### Les 6 modules

| Module | Action |
|---|---|
| **A — Pré-vérifications** | Outils & versions, connectivité FTP, accès DB, espace disque, intégrité `.env` |
| **B — Build Frontend** | `rm -rf out/`, `npm ci`, `npm run build`, contrôle `out/index.html` |
| **C — Build Backend** | `venv`, `pip install -r requirements.txt`, `alembic upgrade head`, seed admin, dry-run uvicorn |
| **D — Upload FTP** | Backups distants, mirror `out/` → racine, upload backend (`api/`), fichiers serveur, permissions |
| **E — Configuration** | Génération `.env.production` (600), démarrage backend (SSH ou manuel), health check public |
| **F — Smoke Tests** | Frontend, API, Auth, DB, SMTP, WebSocket, **contrat des routes**, **parcours connecté** → rapport ✅/❌ |

---

## 6. Le proxy PHP (spécifique mutualisé LWS)

Apache mutualisé n'autorise pas `mod_proxy`. Le routage `/api/*` est donc assuré
par **`.htaccess` → `proxy-api.php`** :

```
RewriteCond %{REQUEST_URI} ^/api/v1/(ws|socket.io)/ [NC]
RewriteRule ^api/(.*)$ ws-tunnel.php [QSA,L]     # WebSocket → tunnel brut

RewriteCond %{REQUEST_URI} ^/api/ [NC]
RewriteRule ^api/(.*)$ proxy-api.php [QSA,L]     # REST → proxy HTTP
```

- **`proxy-api.php`** : transmet méthode, en-têtes (Authorization, CSRF, Cookie…),
  query string et corps JSON vers `127.0.0.1:8001`, puis renvoie statut + corps.
- **`ws-tunnel.php`** : relais du handshake `wss://` puis tunneling bidirectionnel
  brut vers uvicorn. Fonctionne en **mod_php / CGI**.
  - Si le serveur LWS utilise **FastCGI/FPM** (pas d'accès socket client),
    le tunnel est limité — mais le client **Socket.IO bascule alors
    automatiquement sur le transport long-polling (HTTP)**, géré par
    `proxy-api.php`. L'application reste fonctionnelle.

> Les routes dynamiques Next.js (`/community/groups/123`) sont réécrites vers
> la page pré-rendue `community/groups/_.html` (voir `generateStaticParams`).

---

## 7. Démarrage du backend sur LWS

### Option A — SSH activé (recommandé)
```bash
# Dans deploy-config.sh :
SSH_ENABLED=true
# Puis :
bash deploy-agriintel360.sh      # le Module E démarre le backend à distance
```

### Option B — Manuel (sans SSH)
Après le déploiement, depuis le panneau LWS (ou un accès shell ponctuel) :
```bash
cd /agriintel360.lsgrouptogo.com
bash start-backend.sh            # → uvicorn sur 127.0.0.1:8001
bash health-check.sh             # → diagnostic complet
```

### Option C — CRON (surveillance + auto-restart)

Automatique sur un serveur avec `crontab` :

```bash
bash install-cron.sh --dry-run    # montre ce qui serait fait
bash install-cron.sh              # installe ou met à jour la tâche
bash install-cron.sh --show       # affiche la tâche installée
bash install-cron.sh --uninstall  # la retire
```

Ce que fait `install-cron.sh` :

- ajoute (ou met à jour, grâce au marqueur `# agriintel360-health`) la ligne
  `*/5 * * * * … health-check.sh --auto-restart --email` ;
- **sauvegarde la crontab** avant modification dans `logs/crontab-backup-*.txt` (600) ;
- écrit les identifiants du parcours authentifié dans `.health-smoke-env` (600)
  à partir de `.deploy-secrets` (`AGRI_SMOKE_EMAIL`, `AGRI_SMOKE_PASSWORD`) —
  ils ne transitent **jamais** par la crontab ;
- archive le journal au-delà de 5 Mo ;
- si `crontab` n'existe pas (hébergement mutualisé), affiche la ligne à coller
  dans le panneau CRON LWS et sort en code 1.

Sur LWS sans `crontab`, planifier manuellement (toutes les 5 min) :

```bash
cd /agriintel360.lsgrouptogo.com && bash health-check.sh --auto-restart --email >> logs/health-check.log 2>&1
```

### Parcours authentifié

Pour aller au-delà du code HTTP et vérifier qu'un compte réel obtient ses
données, `health-check.sh` sait se connecter :

```bash
SMOKE_EMAIL=... SMOKE_PASSWORD=... bash health-check.sh --smoke-only
# ou, sur le serveur, via .health-smoke-env (600) rempli par install-cron.sh
```

Il contrôle alors `GET /auth/me`, `/reports`, `/search`, `/notifications` avec le
jeton obtenu — **200 attendu**. Sans identifiants, la section est ignorée
(avertissement, pas d'échec).

Dans `deploy-agriintel360.sh`, c'est l'étape **F8** : connexion avec
`ADMIN_EMAIL`/`ADMIN_PASSWORD` (déjà résolus depuis `.deploy-secrets`) puis
`/auth/me`, `/reports`, `/search`. Un échec fait échouer le module F.

---

## 8. Backups & Rollback

**Avant chaque upload**, le Module D :
- renomme `_frontend` → `_frontend-backup-YYYYMMDD-HHMMSS`
- renomme `api` → `api-backup-YYYYMMDD-HHMMSS`

**En cas de problème**, deux niveaux :

1. Depuis la machine locale (automatique à l'échec d'un module) :
   l'option `rollback` de l'assistant `ask_agent`.
2. Depuis le serveur :
   ```bash
   cd /agriintel360.lsgrouptogo.com
   bash rollback.sh          # frontend + backend
   bash rollback.sh backend  # seulement le backend
   bash rollback.sh frontend # seulement le frontend
   ```

> ⚠️ Le **dump PostgreSQL** (`pg_dump`) n'est pas réalisé par le script :
> sur mutualisé, la base n'est accessible qu'en interne (`127.0.0.1`).
> Activez les **sauvegardes automatiques** dans le panneau LWS (base + fichiers).

---

## 9. Journalisation & reprise

- **Journal principal** : `deploy/logs/deploy-YYYY-MM-DD-HHMMSS.log`
  (horodatage, commandes, stdout/stderr, codes de retour)
- **Journal d'erreur** : `deploy/logs/deploy-error-YYYY-MM-DD-HHMMSS.log`
  (créé en cas d'échec fatal, avec contexte)
- **Checkpoint** : `deploy/.deploy_checkpoint` — chaque module validé y est
  enregistré. `--resume` reprend exactement là où le run précédent s'est arrêté.

### Stratégie de récupération (`ask_agent`)
En cas d'échec d'un module, menu : `retry` (3 tentatives max + backoff) ·
`skip` · `rollback` · `abort`. Des aides contextuelles couvrent :
port occupé, échec Alembic, FTP instable, `npm ci` en échec…

> En exécution non interactive (CRON/CI), la valeur par défaut est **retry**,
> puis **skip** après 3 tentatives — le déploiement ne bloque jamais.

---

## 10. Vérifications de sécurité intégrées

- Masquage systématique des secrets dans les logs (`***REDACTED***`)
- `.env.production` en **600**, `.deploy-secrets` / `.deploy-jwt-secret` en **600**
- Alerte si `.env` est versionné dans Git
- `DEBUG=false`, CORS restreint à `https://agriintel360.lsgrouptogo.com` (jamais `*`)
- `JWT_SECRET_KEY` aléatoire 64-hex (non par défaut)
- Headers Apache : HSTS, `X-Frame-Options: SAMEORIGIN`, `nosniff`,
  `Referrer-Policy`, `Permissions-Policy` (+ CSP commentée, à affiner)

---

## 11. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `FTP injoignable` | Pare-feu / mode actif | `FTP_PASSIVE=passive` (défaut) ou basculer en `--module D` + option `a` |
| `index.html introuvable` | Build incomplet | `bash deploy-agriintel360.sh --module B` ; vérifier `next.config.js` (`output:'export'`) |
| `alembic upgrade` échoue | Schéma existant diverge | Réponse `alembic_failed` → `alembic stamp head` puis `upgrade` |
| API `502` via proxy | uvicorn arrêté | `bash start-backend.sh` sur LWS puis `bash health-check.sh` |
| `pthread_create failed` | Trop de threads | Déjà géré : `OPENBLAS_NUM_THREADS=1`, `OMP_NUM_THREADS=1` |
| `localhost` refusé | Résolution `::1` | Toujours `127.0.0.1` (déjà appliqué) |
| WebSocket ne passe pas | FPM/FastCGI | Bascule automatique long-polling ; vérifier le log `backend.log` |
| DB injoignable en C | Accès externe restreint | Faire confiance au Module C (exécuté… côté déploiement) ou SSH |

---

## 12. Rappel des identifiants (à conserver hors de tout dépôt Git)

| Ressource | Valeur |
|---|---|
| FTP / FTPS | `ftp.lsgrouptogo.com:21` — `doc@agriintel360.lsgrouptogo.com` |
| PostgreSQL | `127.0.0.1:5432/c2606883c_agriintel360` — `c2606883c_agriintel` |
| SMTP | `agriintel360.lsgrouptogo.com:465` (SSL) — compte email |
| Domaine | `agriintel360.lsgrouptogo.com` |

---

*Suite générée par l'Agent DevOps AgriIntel360 — vérifiez les secrets avant
tout commit et restreignez les permissions (`chmod 600`).*

## Tests de fumée des routes API

Deux niveaux de contrôle, complémentaires :

1. **`deploy-agriintel360.sh` module F, étape F7** — exécutée à la fin de chaque
   déploiement. Pour chaque route, un code attendu différent du code reçu fait
   échouer le module et donc le déploiement.

2. **`health-check.sh`** — utilisable seul, en CRON ou depuis l'écran
   d'administration.

| Route testée | Code attendu | Ce que cela prouve |
| --- | --- | --- |
| `/api/v1/ping` | 200 | le processus FastAPI répond, sans base ni authentification |
| `/api/v1/payments/plans` | 200 | les paiements et la base fonctionnent (route publique) |
| `/api/v1/weather/current?city=Lome` | 200 | le backend sort bien sur Internet (Open-Meteo joignable) |
| `/api/v1/reports` | 200, 401 ou 403 | la route existe : le garde d'authentification fait son travail |
| `/api/v1/search?q=test` | 200, 401 ou 403 | idem pour la recherche globale |
| `/api/v1/market-prices/markets` | 200, 401 ou 403 | idem pour le comparateur de marchés |
| `/api/v1/economics/gdp` | 200, 401 ou 403 | idem pour l'économie (source Banque mondiale) |

> **Règle** : `404` = route absente = déploiement incomplet ⇒ échec. `401/403`
> sur une route protégée = succès, la route est bien montée.
>
> Pourquoi ce distinguo : sans authentification, un endpoint protégé doit
> refuser l'accès. Attendre 200 obligerait à embarquer un compte de test dans les
> scripts serveur, ce qui exposerait des identifiants.

Commandes utiles sur le serveur :

```bash
bash health-check.sh                 # diagnostic complet (9 points)
bash health-check.sh --smoke-only    # uniquement les routes API
bash health-check.sh --auto-restart  # relance uvicorn si muet
bash health-check.sh --email         # alerte en cas d'échec
```

Codes de sortie : `0` tout est vert, `1` au moins une vérification a échoué
(exploitable directement en CRON ou en `&&` dans un script de release).
