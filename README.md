# AgriIntel360 — Backend

API REST asynchrone du produit AgriIntel360 : indicateurs agricoles, marchés,
prédictions, alertes, météo, messagerie, communautés, fichiers, paiements.
FastAPI · PostgreSQL · MongoDB · Redis · Elasticsearch · Celery.

> Cette branche contient l'API **et** les scripts d'exploitation (`deploy/`).
> Le site vit sur la branche [`frontend`](../../tree/frontend), la documentation
> sur [`docs`](../../tree/docs).

## Démarrage

```bash
python -m venv .venv
source .venv/bin/activate          # Windows : .venv\Scripts\activate
pip install -r requirements.txt

docker compose up -d postgres mongodb redis elasticsearch
alembic upgrade head

uvicorn src.main:app --reload --port 8000
```

Documentation interactive : `/api/v1/docs`. Sonde de disponibilité : `/api/v1/ping`.

## Organisation

```
src/main.py        création de l'app, middlewares, montage du routeur v1
src/services/      logique métier (auth, marchés, alertes, paiements, IA, fichiers)
src/middleware/    sécurité (CSP, rate limit, CSRF), monitoring, validation
src/tasks/         Celery (synchronisation, notifications)
api/routers/       endpoints HTTP, un module par domaine (25 routeurs, 286 routes)
api/models/sql/    modèles SQLAlchemy
api/schemas/       schémas Pydantic (contrat public)
migrations/        Alembic (001 → 010)
pipeline/          DAGs Airflow et contrôles qualité
deploy/            scripts de déploiement LWS, proxy PHP, santé, CRON
```

## Sources de données réelles

`src/services/external_apis.py` — aucune donnée simulée, cache mémoire TTL 6 h,
délai sortant 8 s :

| Source | Accès | Données |
| --- | --- | --- |
| Banque mondiale | `api.worldbank.org/v2`, sans clé | PIB agricole, inflation, taux de change, emploi agricole, fiches pays |
| Open-Meteo | `api.open-meteo.com`, sans clé | météo courante, prévisions, historique, géocodage |

Si une source ne répond pas : `503` explicite ou champ `source_missing`. Jamais
de chiffres inventés (les anciens replis `source: "demo"` ont été supprimés).

## Sécurité

- Cookie de session **`HttpOnly`** + `SameSite=Lax` ; aucun jeton dans le JSON
  renvoyé au navigateur en plus du cookie.
- CSP par type de route, HSTS, COOP/CORP, `Permissions-Policy`, `server` vidé,
  `Cache-Control: no-store` sur les réponses authentifiées.
- Rate limiting par IP et par route, CSRF signé (`X-CSRF-Token`), CORS à origines
  explicites, validation Pydantic renvoyant **422** avec les valeurs acceptées.
- 2FA TOTP, codes à usage unique mémorisés dans Redis.

Détail : branche `docs`, `docs/SECURITY.md`.

## Exploitation (`deploy/`)

```bash
bash deploy-agriintel360.sh --dry-run       # préflight complet (modules A→F)
bash deploy-agriintel360.sh --step-by-step  # déploiement réel, confirmé par module
bash health-check.sh                        # 9 vérifications dont 7 tests de fumée API
bash install-cron.sh                        # surveillance toutes les 5 min + auto-restart
bash rollback.sh                            # retour arrière vers la sauvegarde précédente
```

Le module F du déploiement teste le contrat des routes (F7) et un parcours
authentifié (F8) ; un écart fait échouer le déploiement.

Secrets attendus hors dépôt, en permissions 600 : `deploy/.deploy-secrets`,
`deploy/.deploy-jwt-secret`, `deploy/.health-smoke-env`.

## Vérifications

```bash
python -m compileall -q api src
alembic upgrade head
curl -s localhost:8000/api/v1/ping
```

## Licence

MIT — voir [LICENSE](./LICENSE).
