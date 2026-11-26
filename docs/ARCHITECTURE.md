# Architecture — AgriIntel360

## 1. Vue d'ensemble

```
Navigateur
   │  (SPA Next.js exportée statiquement, React 19)
   ▼
Apache (LWS) ── proxy /api/v1 + /ws ──► FastAPI (Passenger, Python 3.12)
   │                                        │
   └── fichiers statiques (out/)            ├── PostgreSQL  (données métier, SQLAlchemy + Alembic)
                                            ├── MongoDB     (documents bruts, séries)
                                            ├── Redis       (cache, sessions, files Celery, WebSocket)
                                            ├── Elasticsearch (recherche)
                                            └── MLflow + Celery (modèles, tâches planifiées)
```

Contraintes structurantes :

- **Frontend en export statique** (`output: 'export'`). Il n'y a pas de serveur
  Node en production : pas de middleware, pas de route handler, pas d'ISR.
  Conséquences directes :
  - l'authentification est cliente (`stores/auth-store.ts`, jeton persisté) ;
  - les redirections protégées se font dans les layouts React ;
  - `middleware.ts` ne sert qu'au mode développement ;
  - toute nouvelle route doit être déclarée manuellement (navigation, gardes).
- **Le proxy est le point de contrat** : `deploy/proxy-api.php` et
  `deploy/.htaccess` font office de reverse proxy vers l'API et le WebSocket.

## 2. Frontend (`frontend/`)

```
app/
  (landing)/     page publique, contact, mentions légales
  (auth)/        connexion, inscription, mot de passe oublié, vérification e-mail
  (dashboard)/   44 écrans protégés (production, marchés, analyses, terrain, collaboration)
  layout.tsx     racine : polices locales, métadonnées, providers
components/
  ui/            primitives shadcn/ui + Surface (design system)
  layout/        shell : sidebar, header, mobile-nav, page-shell, breadcrumb
  shared/        avatar, états (vide/erreur/chargement), badges, recherche, palette
  landing/       sections de la page publique
  <domaine>/     un dossier par domaine fonctionnel (actors, alerts, community, …)
hooks/           32 hooks TanStack Query (un par domaine) + hooks d'interface
lib/             api-client (résilience), i18n, formatage, validators, carte, PDF
stores/          zustand : auth, ui, filtres, carte
types/           contrats TypeScript par domaine
styles/          tokens.css (jetons) + globals.css (base et classes composées)
```

Flux de données : `page` → `hook` (TanStack Query) → `lib/api-client` → API.
L'`api-client` porte le jeton, applique un disjoncteur et normalise les erreurs ;
aucun composant n'appelle `fetch` directement.

Décisions notables :

- **Pas de SSR** : les écrans sont marqués `'use client'` quand ils ont besoin du
  state ou du jeton, sinon ils sont rendus statiquement.
- **Polices locales** (`fonts/`) plutôt que Google Fonts : performance et
  souveraineté réseau.
- **TanStack Query** est la seule couche de cache ; pas de cache parallèle.

## 3. Backend (`backend/`)

```
src/main.py          création de l'app, middlewares, montage du routeur v1
src/services/        logique métier (auth, marchés, alertes, paiements, fichiers, IA)
src/middleware/      sécurité (en-têtes, rate limit, CSRF), monitoring, validation
src/tasks/           Celery (synchronisation d'indicateurs, notifications)
api/routers/         endpoints HTTP, un module par domaine
api/routers/v1/      endpoints versionnés (secteurs)
api/models/sql/      modèles SQLAlchemy
api/schemas/         schémas Pydantic (contrat d'entrée/sortie)
migrations/          Alembic
pipeline/            DAGs Airflow et contrôles qualité
config/              réglages, base de données, journalisation
```

Règles :

- Un routeur ne contient pas de logique métier : il valide, appelle un service,
  sérialise.
- Les schémas Pydantic sont le contrat public ; le frontend `types/` doit rester
  aligné dessus.
- Migrations Alembic uniquement ; pas de `create_all` en production.

## 3 bis. Sources de données externes

| Source | Accès | Contenu | Cache |
| --- | --- | --- | --- |
| Banque mondiale | `api.worldbank.org/v2`, sans clé | PIB agricole, inflation, taux de change, emploi agricole, fiches pays | mémoire, TTL 6 h (`src/services/external_apis.py`) |
| Open-Meteo | `api.open-meteo.com`, sans clé | météo courante, prévisions, historique, géocodage | aucun (données temps réel) |

Règles :

1. **Aucune valeur de démonstration.** Si la source ne répond pas, la réponse
   porte un code 503 ou `source_missing`, jamais des chiffres inventés.
2. Les appels sortent avec un délai de 8 s maximum ; un écran ne doit pas
   attendre une source externe plus longtemps que son propre timeout.
3. Les indicateurs de la Banque mondiale sont annuels : le comparateur de
   marchés expose donc un **indice base 100** (`is_index: true`), pas un prix au
   kilo. Le libellé de l'écran doit le dire.

## 4. Déploiement (`deploy/`)

| Fichier | Rôle |
| --- | --- |
| `deploy-config.sh` | chemins locaux, hôte distant, options (source de vérité) |
| `deploy-agriintel360.sh` | orchestrateur : build, sauvegarde, envoi, vérifications |
| `lftp-mirror.lftp` | miroir du build statique (`frontend/out`) |
| `proxy-api.php`, `.htaccess` | reverse proxy vers l'API et le WebSocket |
| `rollback.sh`, `health-check.sh` | retour arrière, contrôle de santé |
| `logs/` | journaux de déploiement |

Les secrets (`deploy/.deploy-secrets`, `deploy/.deploy-jwt-secret`) restent hors
du dépôt (voir `.gitignore` racine).

## 5. Décisions à connaître avant de coder

1. **Toute page ajoutée doit être déclarée trois fois** : le fichier dans `app/`,
   l'entrée de navigation (`components/layout/sidebar.tsx`) et, en développement,
   la garde de `middleware.ts`. Oublier l'une des trois casse l'accès.
2. **Le thème clair et le thème sombre sont égaux en droit** : un composant qui
   code une couleur sombre en dur est un bug, pas un choix.
3. **La page publique est la vitrine** : elle doit rester rendue statiquement et
   sous 200 kB de JS initial (budget actuel : ~103 kB partagés).
4. **Les graphiques Recharts** reçoivent `require('tailwind.config.js').brand`
   plutôt que des hexadécimaux locaux, pour rester alignés sur la palette.
