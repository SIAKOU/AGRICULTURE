# AgriIntel360 — Intelligence Agricole pour l'Afrique

[![CI](https://github.com/SIAKOU/AGRICULTURE/actions/workflows/ci.yml/badge.svg)](https://github.com/SIAKOU/AGRICULTURE/actions/workflows/ci.yml)

Plateforme de décision agricole pour l'Afrique de l'Ouest : données de marché et
d'indicateurs, prédictions, alertes, météo, cartographie 3D, messagerie et
communautés, pour les filières **végétal, animal, halieutique et forestier**.

Ce dépôt est organisé **en branches** : chaque composant du produit vit sur sa
propre branche, ce qui permet de cloner, versionner et déployer indépendamment
le site, l'API et la documentation.

| Branche | Contenu | Cloner |
| --- | --- | --- |
| [`frontend`](../../tree/frontend) | Application web Next.js 15 / React 19 / Tailwind 4 (export statique) | `git clone -b frontend https://github.com/SIAKOU/AGRICULTURE.git` |
| [`backend`](../../tree/backend) | API FastAPI, services, migrations Alembic, scripts de déploiement | `git clone -b backend https://github.com/SIAKOU/AGRICULTURE.git` |
| [`docs`](../../tree/docs) | Analyse, architecture, design system, sécurité, outillage de vérification | `git clone -b docs https://github.com/SIAKOU/AGRICULTURE.git` |
| `main` | Ce document : carte du produit et mode d'emploi | `git clone https://github.com/SIAKOU/AGRICULTURE.git` |

## Le produit en une page

| Domaine | Ce que fait la plateforme |
| --- | --- |
| Production | Suivi des indicateurs par filière (végétal, animal, halieutique, forestier), surfaces, rendements, acteurs |
| Marchés | Relevés de prix, comparateur inter-marchés, indices réels calculés sur les séries de la Banque mondiale |
| Analyse | Tableaux de bord, corrélations, export PDF/CSV/Excel |
| Prédictions | Rendement, production, prix, météo — modèles servis par l'API |
| Terrain | Météo temps réel (Open-Meteo), alertes, calendrier cultural, carte 3D avec relief |
| Collaboration | Messagerie temps réel, groupes communautaires, partage de fichiers |
| Compte | Abonnements, moyens de paiement, 2FA, gestion des sessions |

## Sources de données réelles

Aucune donnée n'est simulée à l'écran. Les écrans qui n'ont pas encore de flux
affichent un état explicite (`—`, « aucun relevé collecté ») plutôt qu'un chiffre
plausible.

| Source | Accès | Données |
| --- | --- | --- |
| Banque mondiale | `api.worldbank.org/v2` — sans clé | PIB agricole, inflation, taux de change, emploi agricole, fiches pays |
| Open-Meteo | `api.open-meteo.com` — sans clé | Météo courante, prévisions, historique, géocodage |
| MapLibre + MNT public | `demotiles.maplibre.org` — sans clé | Fond de carte 3D avec relief réel |

## Démarrage rapide

```bash
# Site web
git clone -b frontend https://github.com/SIAKOU/AGRICULTURE.git site
cd site && npm install && npm run dev        # http://localhost:3000

# API
git clone -b backend https://github.com/SIAKOU/AGRICULTURE.git api
cd api && python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
docker compose up -d postgres mongodb redis elasticsearch
alembic upgrade head
uvicorn src.main:app --reload --port 8000
```

Variables d'environnement côté site : `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_WS_URL`,
`NEXT_PUBLIC_API_PREFIX`. Aucune valeur secrète ne porte le préfixe
`NEXT_PUBLIC_` : ces variables partent dans le bundle client.

## Intégration continue

Le workflow [`.github/workflows/ci.yml`](.github/workflows/ci.yml) tourne sur les
quatre branches et sur chaque pull request vers `main`. Trois travaux, aucun
secret, aucune base de données :

| Travail | Ce qu'il vérifie |
| --- | --- |
| **Contrat API et intégrité des données** | les 4 branches sont récupérées, puis `check-api-contract.py` et `audit-frontend-data.py` : aucune route fantôme, aucune valeur inventée |
| **Frontend (types, tests, build)** | `npm ci`, `tsc --noEmit` en mode strict, tests Jest, export statique, présence des pages générées |
| **Backend (syntaxe et imports)** | `compileall`, analyse AST des 25 routeurs, chaîne des migrations Alembic (une seule tête, aucun parent manquant) |

Les quatre branches sont **protégées** : trois vérifications obligatoires, branche
à jour exigée avant fusion, force-push et suppression interdits.

## Qualité et vérifications

Quatre contrôles automatiques accompagnent le produit (branche `docs`) :

```bash
python scripts/check-api-contract.py     # aucune route appelée ne manque côté API
python scripts/audit-frontend-data.py    # aucune valeur inventée à l'écran
cd frontend && npx tsc --noEmit && npm test
cd ../backend && python -m compileall -q api src
```

État mesuré : **0 écart de contrat** sur 162 routes appelées, **0 donnée
fabriquée** sur 226 fichiers, 0 erreur TypeScript en mode strict, build de
production à 41 pages, tests unitaires au vert.

## Sécurité

- Aucun jeton lisible par JavaScript : le backend pose un cookie `HttpOnly`, le
  frontend n'en conserve pas de copie (une XSS ne peut pas rejouer la session).
- CSP stricte, HSTS, COOP/CORP, `Permissions-Policy` côté Apache **et** côté API.
- Rate limiting, CSRF signé, validation Pydantic avec erreurs 422 explicites.
- Aucun secret dans le dépôt ; fichiers de secrets en mode 600 hors du dépôt.

Détail complet et procédures de vérification : branche `docs`,
[`docs/SECURITY.md`](../../tree/docs/docs/SECURITY.md).

## Stack

**Frontend** — Next.js 15.5 (export statique), React 19, TypeScript strict,
Tailwind CSS 4, TanStack Query 5, Zustand, Radix UI, Recharts, MapLibre GL 4
(relief 3D), Framer Motion.

**Backend** — FastAPI, Python 3.12, SQLAlchemy 2 + Alembic, PostgreSQL, MongoDB,
Redis, Elasticsearch, Celery, MLflow, Airflow.

**Exploitation** — Apache + PHP pour le proxy API, déploiement FTP/SSH LWS
scripté, surveillance CRON avec tests de fumée et parcours authentifié.

## Licence

Voir [LICENSE](./LICENSE).
