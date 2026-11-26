# Sécurité — AgriIntel360

Ce document décrit les contrôles réellement en place, leur emplacement dans le
code, et la façon de les vérifier. Il ne liste pas des intentions : chaque ligne
renvoie à un fichier ou à une commande.

## 1. Modèle de menace

| Actif | Menace principale | Contre-mesure |
| --- | --- | --- |
| Session utilisateur | Vol de jeton par XSS, vol de cookie | Cookie `HttpOnly` + `SameSite=Lax`, aucun jeton lisible en JS |
| API | Bourrage d'identifiants, énumération, déni de service | Rate limit par IP et par route, verrouillage progressif, 422 explicites |
| Données personnelles | Fuite par cache intermédiaire ou journal | `Cache-Control: no-store` sur les réponses authentifiées, journaux sans secret |
| Site public | Injection de contenu, clickjacking, mixed content | CSP stricte, `frame-ancestors 'none'`, HSTS, `upgrade-insecure-requests` |
| Secrets d'exploitation | Commit accidentel | `.gitignore` racine, retrait de l'index, `Require all denied` sur `.env*` |
| Fichiers téléversés | Exécution, accès direct | Extensions autorisées, listage désactivé, `_frontend-backup-*` bloqué |

## 2. Authentification et session

- Le backend pose un cookie **`HttpOnly`** (`backend/api/routers/auth.py`,
  `set_cookie(..., httponly=True, samesite="lax")`).
- Le frontend **ne stocke aucun jeton lisible** : `frontend/lib/auth-session.ts`
  ne conserve qu'un marqueur d'expiration. `getStoredAccessToken()` renvoie
  `null` sauf si `NEXT_PUBLIC_ALLOW_JS_TOKEN=true` (développement seulement).
- `lib/api-client.ts` envoie `credentials: 'include'` : le cookie authentifie
  l'appel, l'en-tête `Authorization` reste absent en production.
- La déconnexion purge le stockage, le cookie, les caches et le service worker.
- 2FA TOTP disponible (`/api/v1/2fa/*`), codes à usage unique mémorisés dans
  Redis (`src/services/redis.py`).

> Conséquence à connaître : un jeton exfiltré par XSS ne peut plus être rejoué
> depuis un autre onglet, puisque le script n'y a pas accès.

## 3. En-têtes et CSP

Deux couches, car le site et l'API sont servis par le même domaine :

| Couche | Fichier | Contenu |
| --- | --- | --- |
| Apache (site statique) | `deploy/.htaccess` | CSP, HSTS, COOP/CORP, `Permissions-Policy`, `X-Content-Type-Options`, `Cache-Control: no-store` sur `.html` |
| FastAPI (API) | `backend/src/middleware/security.py` | CSP par type de route, mêmes en-têtes, `server` vidé, `no-store` sur réponses authentifiées |

Choix assumé : `script-src` contient `'unsafe-inline'`. L'export statique de
Next.js injecte ses scripts d'amorçage en ligne et il n'existe aucun serveur
Node pour générer un nonce. Toutes les autres directives sont strictes :
`object-src 'none'`, `frame-ancestors 'none'`, `base-uri 'self'`,
`connect-src` limité aux origines réellement appelées.

Vérification manuelle après déploiement :

```bash
curl -sI https://agriintel360.lsgrouptogo.com/ | grep -iE "content-security|strict-transport|permissions|cross-origin"
curl -sI https://agriintel360.lsgrouptogo.com/api/v1/ping | grep -i "content-security"
```

## 4. Protection des entrées et des abus

- **Rate limiting** (`RateLimitMiddleware`) : limite globale paramétrée par
  `RATE_LIMIT_PER_MINUTE`, plafonds plus bas sur `/auth/login`, `/auth/register`
  et `/auth/forgot-password`.
- **CSRF** (`CSRFMiddleware`) : jeton exigé sur les méthodes mutantes, signé avec
  `JWT_SECRET_KEY` ; le client l'obtient via `/auth/csrf` et le renvoie dans
  `X-CSRF-Token`.
- **Validation** : Pydantic sur chaque corps de requête ; les paramètres
  d'énumération sont validés explicitement et renvoient **422 avec la liste des
  valeurs acceptées** (voir `api/routers/indicators.py`), jamais un 500.
- **CORS** : origines explicites (`BACKEND_CORS_ORIGINS`), jamais `*`.
- **Fichiers** : extensions autorisées, taille maximale, `Require all denied`
  sur les sources, journaux et sauvegardes.

## 5. Secrets

- Aucun secret dans le dépôt : `.gitignore` racine couvre `.env*`,
  `deploy/.deploy-secrets`, `deploy/.deploy-jwt-secret`, `deploy/.health-smoke-env`.
- Les scripts de déploiement lisent les secrets depuis des fichiers en mode
  **600** ; `install-cron.sh` recopie les identifiants de fumée dans
  `.health-smoke-env` (600) et ne les écrit jamais dans la crontab.
- `deploy/.deploy-jwt-secret` a été retiré de l'index Git (le fichier reste sur
  le poste). **Si un dépôt distant a déjà reçu ce fichier, la clé doit être
  régénérée** : elle signait les jetons et les jetons CSRF.

## 6. Journalisation et supervision

- `health-check.sh` : 9 vérifications dont 7 tests de fumée API et un parcours
  authentifié ; code de sortie exploitable en CRON (`install-cron.sh`).
- Le journal de santé est en rotation à 5 Mo.
- Aucun mot de passe n'est journalisé : le parcours authentifié masque les
  identifiants et n'affiche que le résultat des requêtes.

## 7. Contrôles automatiques

```bash
python scripts/check-api-contract.py     # aucune route fantôme
python scripts/audit-frontend-data.py    # aucune valeur inventée à l'écran
cd frontend && npx tsc --noEmit && npm test
cd ../backend && python -m compileall -q api src
bash -n deploy/*.sh
```

## 8. Reste à faire (sécurité)

1. **Remplacer `'unsafe-inline'`** en passant à un serveur Node (ou un reverse
   proxy qui injecte un nonce) : seule façon d'avoir une CSP sans exception.
2. **Rotation des clés** après le premier déploiement public : `JWT_SECRET_KEY`,
   `AGRI_ADMIN_PASSWORD`, secrets FTP/SMTP.
3. **Verrouillage de compte progressif** après N échecs consécutifs (partiel via
   rate limit, à rendre persistant en Redis).
4. **Audit des dépendances** : `npm audit` et `pip-audit` en CI (non branchés).
5. **`Subresource Integrity`** sur les rares ressources externes, si un CDN est
   introduit.
