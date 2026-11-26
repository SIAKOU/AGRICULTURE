# Analyse complète — AgriIntel360

État du dépôt au moment de l'analyse, défauts constatés avec leur preuve, actions
appliquées, et ce qui reste à faire. Chaque ligne « vérifié » a été contrôlée par
une commande réelle (indiquée).

## 1. Inventaire

| Zone | Volume | Détail |
| --- | --- | --- |
| `frontend/app` | 13 262 lignes · 59 fichiers | 41 écrans, 3 groupes de routes (`(landing)`, `(auth)`, `(dashboard)`) |
| `frontend/components` | 24 342 lignes · 118 fichiers | 19 dossiers, dont 24 primitives `ui/` |
| `frontend/lib` | 7 681 lignes · 13 fichiers | `api-client`, `i18n`, `utils`, `media-utils`, `map-styles` |
| `frontend/hooks` | 4 461 lignes · 32 fichiers | un hook TanStack Query par domaine |
| `frontend/stores` | 1 691 lignes · 4 fichiers | zustand : auth, ui, filtres, carte |
| `frontend/types` | 9 078 lignes · 11 fichiers | contrats par domaine |
| `backend` | 107 fichiers Python | 25 routeurs agrégés, services, Celery, Alembic, pipeline Airflow |
| `deploy` | 9 fichiers + journaux | FTP/SSH LWS, proxy PHP, rollback, health-check |

Total frontend : **≈ 59 300 lignes** TypeScript/TSX.

## 2. Ce qui est solide

- **Typage strict sans erreur** : `npx tsc --noEmit` → exit 0, 0 erreur, 0
  avertissement (vérifié après refonte).
- **Build de production vert** : `npm run build` → 41 pages statiques générées,
  103 kB de JS partagé, exit 0.
- **Découpage par domaine** cohérent : `hooks/` ↔ `types/` ↔ `components/<domaine>/`
  suivent les mêmes noms, ce qui rend la navigation prévisible.
- **Résilience réseau** centralisée dans `lib/api-client.ts` (disjoncteur, jeton,
  normalisation des erreurs) : aucun `fetch` sauvage dans les composants.
- **Accessibilité déjà prise au sérieux** : lien d'évitement, `aria-current`,
  `prefers-reduced-motion`, `forced-colors`, `prefers-contrast`.
- **Pas de dette signalée** : 0 `TODO`/`FIXME`/`HACK` dans le code applicatif.

## 3. Défauts constatés et corrigés

### 3.1 Organisation

| Défaut | Preuve | Correction |
| --- | --- | --- |
| Dossiers racine avec espaces (`AGRI-INTEL FRONTEND`, `AGRI-INTEL BACKEND`) : cassent les scripts, les chemins `rsync`/`lftp`, les outils CI | `deploy/deploy-config.sh:30-31`, `deploy/lftp-mirror.lftp:48` | Renommés `frontend/` et `backend/`, références mises à jour |
| Deux arbres de code backend en doublon : `services/` et `middleware/` à la racine **et** `src/services/`, `src/middleware/` | `from services.calculations import …` dans `api/routers/v1/sectors.py` | Consolidés dans `src/services/` et `src/middleware/` ; imports corrigés ; syntaxe vérifiée (`compileall` + analyse AST : 0 erreur) |
| Aucune documentation de synthèse (ni racine, ni architecture, ni design) | `docs/` inexistant | `README.md`, `docs/ARCHITECTURE.md`, `docs/DESIGN.md`, ce rapport |

### 3.2 Design et thème

| Défaut | Preuve | Correction |
| --- | --- | --- |
| Palette éclatée : 83 `#C4923A`, 45 `#E4DBC8`, 22 `#064E3B`… en dur dans les composants | `grep -roh "#[0-9A-F]\{6\}"` sur `app/` + `components/` | `styles/tokens.css` (primitives + sémantique clair/sombre) et `tailwind.config.js` branché dessus |
| Surfaces de la page publique figées en sombre (`rgba(15,23,42,…)`) : illisibles en thème clair | `.landing-card`, `.landing-hero`, `.landing-feature-card` dans l'ancien `globals.css` | Classes réécrites sur `hsl(var(--…))` ; bandeau de résultats (`stats-bar.tsx`) entièrement re-tokenisé |
| Badges de secteur sans variante sombre (`#ECFCCB` sur fond clair uniquement) | `.badge-vegetal` … `.badge-forestier` | Jetons `--sector-*` + `.badge-sector` qui suivent le thème |
| Trois sources pour la hauteur d'en-tête (64 px) : `--header-height`, `.h-header`, `spacing.header` | `globals.css` + `tailwind.config.js` | Une seule source : `--header-height`, exposée partout |
| Rayons incohérents (`--radius: .5rem` vs `borderRadius.card: 12px`) et ombres en `rgba(0,0,0,…)` identiques en clair et en sombre | ancien `tailwind.config.js` | Rayons et ombres dérivés des jetons, ombres distinctes par thème |
| Utilitaires morts ou dupliqués (`.line-clamp-2/3` fournis par Tailwind, `.landing-hero` inutilisé, `#101E14` hors palette) | `globals.css` | Supprimés |
| Bordures en opacité 20 % (`border-border/20`) invisibles sur écran de terrain | `header.tsx` (ancienne version) | Filets pleins, focus et états homogènes |
| Avatar utilisateur implémenté trois fois (header, sidebar, profil) | `header.tsx`, `sidebar.tsx` | `components/shared/avatar.tsx` |

### 3.3 Fonctionnel

| Défaut | Preuve | Correction |
| --- | --- | --- |
| Six écrans inaccessibles depuis la navigation : `/markets`, `/markets/compare`, `/economics`, `/calendar`, `/reports`, `/payments` | `sidebar.tsx` ne déclarait que 18 entrées pour 41 pages | Navigation réorganisée en 6 groupes ; toutes les routes atteignables ; entrée enfant (`/markets/compare`) ne allume plus le parent |
| Paramètre de retour incohérent : la garde cliente utilise `?next=`, le middleware `?redirect=`, jamais lu par la connexion | `middleware.ts:52` vs `hooks/use-auth.ts:68` | Middleware aligné sur `?next=` |
| Routes protégées incomplètes dans le middleware de développement | `PROTECTED_ROUTES` sans `/markets`, `/payments`, `/reports`, `/calendar`, `/messages` | Liste complétée ; route fantôme `/reset-password` retirée |
| Dépendances non installables : conflit de pairs `@testing-library/cypress@8` ↔ `cypress@15` | `npm ci` → ERESOLVE | `@testing-library/cypress` porté en `^10.1.3` (`peer cypress >=12`) ; `npm install` passe |
| **La suite de tests ne s'exécutait pas** : aucun `jest.config.js`, pas de transform TSX, `jest-environment-jsdom@29` face à `jest@30`, et le seul test échouait sur `Response is not defined` | `npm test` → `SyntaxError: Unexpected token, expected ","` puis 8 échecs | `jest.config.js` (preset `next/jest`), `jest.setup.ts`, `jest-environment-jsdom@^30`, helper `__tests__/helpers/http.ts` ; **9 tests passent** |
| Le test d'API ne testait pas le vrai contrat d'authentification (il écrivait `localStorage.auth_token`, le code lit `sessionStorage.session_token` puis le cookie `access_token`) | `__tests__/api.test.tsx:45` vs `lib/api-client.ts:369` | Tests réécrits sur le contrat réel, avec un cas de repli sur le cookie |
| Réhydratation du store d'auth en échec à chaque prérendu (`Cannot read properties of undefined (reading 'getItem')`) | avertissement répété dans `next build` | `createJSONStorage` gardé par `typeof window`, `skipHydration` côté serveur, stockage inerte |
| Avertissement ESLint bloquant la propreté du build | `community-section.tsx:275` index inutilisé | Corrigé ; build sans avertissement |
| Secret versionnable dans l'index Git (`deploy/.deploy-jwt-secret`) | `git ls-files` | `.gitignore` racine + retrait de l'index (le fichier reste sur le disque) |

## 4. Reste à faire (par ordre de valeur)

1. **Découper les quatre fichiers monolithes** : `components/predictions/prediction-panel.tsx`
   (1 253 l.), `app/(auth)/register/page.tsx` (1 204 l.), `app/(dashboard)/messages/page.tsx`
   (1 192 l.), `lib/utils.ts` (1 168 l.). Cible : `lib/utils.ts` éclaté en
   `format/`, `sectors/`, `severity/`, `files/`, `text/` — c'est le fichier le plus
   importé du projet, donc le plus rentable à séparer.
2. **Réduire `any`** : 20 occurrences concentrées dans `hooks/use-community.ts` (11),
   `hooks/use-notifications.ts` (3), `hooks/use-settings.ts`, `hooks/use-auth.ts`,
   `components/map/interactive-map.tsx`. Les contrats `types/community.ts` existent
   déjà.
3. **Étendre les tests** : 9 tests couvrent désormais `lib/api-client.ts`. Prochaines
   cibles, sans infrastructure : `lib/utils.ts` (formatage), `stores/auth-store.ts`
   (hydratation, déconnexion), `lib/validators.ts` (schémas). Cypress ne contient
   encore que le parcours d'authentification (2 specs).
4. **Tokeniser les 5 derniers écrans** listés en fin de `docs/DESIGN.md`.
5. **Retirer `console.log`** résiduels (`components/shared/service-worker-register.tsx`,
   `stores/filter-store.ts`).
6. **Vérifier le dernier déploiement** : `deploy/logs/deploy-error-2026-08-02-085955.log`
   existe, donc une étape a échoué lors du dernier envoi.
7. **Rotation du secret JWT** si l'index Git a déjà été poussé sur un dépôt distant :
   le fichier n'était pas encore commité localement, mais il faut confirmer l'état
   distant avant de conclure.

## 5. Commandes de vérification utilisées

```bash
# Frontend
cd frontend && npx tsc --noEmit        # exit 0
cd frontend && npm run build           # exit 0, 41 pages statiques
cd frontend && npm test                # 9/9 tests passent
grep -o "--surface-glass" out/_next/static/css/*.css | wc -l   # jetons présents dans le CSS livré

# Contrôle visuel (Chromium via Playwright)
captures clair / sombre / mobile de `/` et de `/login` — titre du héros lisible
dans les deux thèmes après correction des jetons

# Backend
cd backend && python -m compileall -q src api config
python - <<'PY' … ast.parse …          # 0 erreur de syntaxe sur 107 fichiers
PY

# Structure
grep -rn "from services\b|from middleware\b" backend   # 0 résultat
```

Non vérifié : exécution réelle de l'API (base de données et Redis non démarrés
dans cet environnement) et rendu visuel dans un navigateur.

## 6. Branchement réel des API (passe du 2026-11-26)

### 6.1 Contrôle de contrat automatisé

Nouveau script : `scripts/check-api-contract.py`. Il compare, sans base de
données, les appels du frontend (`apiClient.*`, `fetch`) aux routes réellement
exposées par `api/routers/router.py`.

```bash
python scripts/check-api-contract.py            # 0 = tout est branché
python scripts/check-api-contract.py --verbose  # + routes backend jamais appelées
```

État initial : **18 routes appelées sans équivalent backend**.
État final : **161 routes appelées, toutes servies** par 285 routes backend.

### 6.2 Routes ajoutées côté backend (avec leur justification)

| Route | Motif |
| --- | --- |
| `GET /search` | Palette de commandes et barre de recherche : aucune route n'existait. Recherche réelle sur acteurs, publications et fichiers visibles par l'utilisateur |
| `GET /market-prices/compare` + `GET /market-prices/markets` | L'écran Comparateur appelait une route inexistante (404 permanent) |
| `POST /contact` | Le formulaire de contact de la page publique n'avait pas de destinataire |
| `GET /ping` (et `/api/v1/ping`) | Sonde utilisée par l'écran d'administration |
| `GET /reports`, `GET /reports/{id}` | Liste et détail des rapports (seuls `/history`, `/download`, `DELETE` existaient) |
| `GET/POST/DELETE /payments/methods`, `POST /payments/change-plan` | L'écran Abonnement gérait des moyens de paiement sans route ni table |
| `GET /payments/subscription`, `GET /payments/billing`, `POST /payments/cancel` | Alias exacts des noms utilisés par `hooks/use-payments.ts` |
| `PATCH /files/{id}/rename`, `PATCH /files/{id}/move` | Le gestionnaire de fichiers appelait deux routes 404 |
| `POST /community/posts/{id}/comments` | Commentaire par URL REST (le corps seul était accepté) |
| `GET /economics/exchange-rates`, `GET /economics/countries/live` | Accès direct aux séries réelles (taux de change, fiches pays) |

Table créée : `payment_methods` (migration `010_add_payment_methods.py`),
sans aucune donnée de carte en clair (type, `last4`, expiration, référence
fournisseur).

### 6.3 Sources externes réelles — aucune donnée simulée

Nouveau service : `backend/src/services/external_apis.py`. Toutes les sources
sont gratuites et sans clé, vérifiées par appel HTTP le 2026-11-26.

| Source | Données | Utilisée par |
| --- | --- | --- |
| Banque mondiale (`api.worldbank.org/v2`) | PIB agricole, PIB, inflation, taux de change officiel, emploi agricole, production alimentaire, fiches pays | `/economics/*`, `/market-prices/compare` |
| Open-Meteo | météo courante, prévisions, historique, géocodage | `/weather/*` (déjà branché) |

Les replis « mock »/`source: "demo"` de `api/routers/economics.py` ont été
**supprimés** : en cas d'indisponibilité, la réponse porte `source_missing` ou
un code 503 explicite, jamais des chiffres inventés.

### 6.4 Défauts d'interface corrigés après captures navigateur

| Défaut | Cause | Correction |
| --- | --- | --- |
| Contenu du dashboard passant **sous** la barre latérale | variable CSS auto-référente `--sidebar-width: var(--sidebar-width)` : cycle ⇒ déclaration invalide ⇒ `padding-left` nul | variable locale `--sidebar-offset` |
| En-tête pleine largeur recouvrant la navigation | même cycle sur `lg:left-[var(--sidebar-width)]` | `--sidebar-offset` avec repli |
| Notifications recouvrant le menu de compte | `Toaster position="top-right"` | ancrage en bas à droite, ombre de la nouvelle échelle |
| Utilisateur connecté renvoyé sur `/login` au rechargement | la garde s'exécutait avant la réhydratation zustand | attente de `hydrationState === 'complete'` |
| Comparateur affichant un « prix » alors que la source est un indice | libellé et symbole monétaire inadéquats | `unit`, `is_index`, `source` affichés ; « points d'indice » au lieu d'une devise |

Vérifications : `npx tsc --noEmit` (0 erreur), `npm run build` (41 pages),
`npm test` (9/9), `python -m compileall` (0 erreur), contrat API (0 écart).

## 7. Garde-fou de déploiement (passe suivante)

Un déploiement pouvait réussir en laissant une API muette : le module F ne
testait que `/health` et l'endpoint de connexion.

Ajouts :

- `deploy/health-check.sh` réécrit : 9 vérifications dont **7 tests de fumée**
  sur les routes réellement branchées (`/ping`, `/weather/current`,
  `/economics/gdp`, `/search`, `/market-prices/markets`, `/payments/plans`,
  `/reports`). Code de sortie 1 dès qu'une vérification échoue, donc utilisable
  en CRON ou en garde de release. Mode `--smoke-only` pour ne tester que l'API.
- `deploy/deploy-agriintel360.sh`, module F : nouvelle étape **F7** qui rejoue
  ces routes et fait échouer le déploiement en cas d'écart. Le `--dry-run`
  annonce les routes testées.

Principe retenu : sur une route protégée, `401/403` est un **succès** (la route
existe et le garde fonctionne), `404` un **échec** (route non déployée). Cela
évite d'embarquer un compte de test dans les scripts serveur.

Vérifié : `bash -n` sur les deux scripts, et exécution du module contre un
serveur factice — les codes 200/401 sont acceptés, un 404 est bien signalé en
échec avec code de sortie 1.

## 8. Surveillance et parcours authentifié

### 8.1 `deploy/install-cron.sh` (nouveau)

Installe la surveillance toutes les 5 minutes : `health-check.sh --auto-restart
--email`. Propriétés retenues :

- **idempotent** — la tâche porte le marqueur `# agriintel360-health`, donc une
  réexécution met à jour la ligne au lieu de la dupliquer ;
- **sauvegarde** la crontab avant modification (`logs/crontab-backup-*.txt`, 600) ;
- **pas de secret dans la crontab** : les identifiants du parcours authentifié
  sont écrits dans `.health-smoke-env` (600) depuis `.deploy-secrets`, fichier
  lui-même ignoré par Git ;
- **dégradation propre** : sans binaire `crontab` (mutualisé LWS), le script
  affiche la ligne à coller dans le panneau CRON et sort en code 1 ;
- rotation du journal au-delà de 5 Mo.

### 8.2 Parcours authentifié dans `health-check.sh`

Les tests de fumée précédents s'arrêtaient au code HTTP : un `401` prouvait
seulement que la route existe. Ils ne vérifiaient pas qu'un utilisateur réel
obtient ses données.

Ajout : si `SMOKE_EMAIL`/`SMOKE_PASSWORD` sont fournis (variables
d'environnement ou `.health-smoke-env`), le script se connecte sur
`POST /auth/login`, extrait le jeton, puis exige **200** sur `GET /auth/me`,
`/reports`, `/search?q=test` et `/notifications`. Sans identifiants : section
ignorée avec un avertissement, jamais un faux échec.

### 8.3 Étape F8 du déploiement

`deploy-agriintel360.sh`, module F : **F8 « Parcours connecté »** rejoue ce
scénario avec `ADMIN_EMAIL`/`ADMIN_PASSWORD`, déjà résolus depuis
`.deploy-secrets`. Un échec incrémente le compteur d'échecs du module, donc le
déploiement se termine en erreur.

### 8.4 Vérifié

| Contrôle | Résultat |
| --- | --- |
| `bash -n` sur `health-check.sh`, `install-cron.sh`, `deploy-agriintel360.sh` | 0 erreur |
| Parcours authentifié, bons identifiants (serveur factice) | 4 routes → 200, code de sortie 0 |
| Parcours authentifié, mauvais identifiants | échec explicite, code de sortie 1 |
| Parcours authentifié, identifiants absents | avertissement, code de sortie 0 |
| `install-cron.sh --dry-run` / `--show` / installation | comportement conforme, code 1 sans `crontab` |
| F8 du script de déploiement (bon et mauvais mot de passe) | pass/fail corrects |

Un défaut a été trouvé et corrigé pendant cette passe : l'extraction du jeton
utilisait une référence arrière `sed` qui se corrompait à l'écriture du fichier
(`\001` au lieu de `\1`) ; remplacée par un découpage `tr`/`cut` sans expression
régulière, robuste au copier-coller.

## 9. Intégrité des données affichées

### 9.1 Défauts trouvés

Le frontend était globalement branché (contrôle de contrat à 0 écart), mais
plusieurs écrans **fabriquaient** des valeurs lorsque l'API ne répondait pas :

| Emplacement | Ce qui était affiché | Correction |
| --- | --- | --- |
| `app/(dashboard)/actors/page.tsx` | « Acteurs totaux : **60** » quand l'API est muette | `formatStat()` → `—` |
| `components/analytics/analytics-overview.tsx` | « Indicateurs : **36** », « Pays couverts : **14** », « Alertes (7j) : **7** » | `—` |
| `app/(dashboard)/indicators/page.tsx` | 4 courbes générées avec `Math.sin(i) + Math.random()`, dont trois variantes dérivées (×0,3 ; ×0,5 ; ×0,7) | séries réelles issues de `by_sector` et `health_distribution` de `/indicators/overview` ; vignettes sans série réelle : pas de courbe |
| `app/(dashboard)/markets/page.tsx` | « +0,0 % » affiché quand la variation était inconnue | `VariationBadge` affiche `—` |

### 9.2 Défaut bloquant côté backend

L'écran Marchés appelait `/indicators?category=market_price`. Cette valeur
n'existe pas dans l'énumération `CategorieIndicateurEnum` : `FastAPI` levait une
`ValueError` d'énumération, donc une **erreur 500 à chaque chargement**.

- Validation explicite des paramètres `sector` et `category` → **422** avec la
  liste des valeurs acceptées, au lieu d'un 500 opaque.
- Nouvel endpoint `GET /market-prices` : contrat explicite, `available: false`
  motivé et connecteurs prévus (WFP/HDX, ESOKO, FAO GIEWS) tant qu'aucun relevé
  n'est collecté. L'écran affiche un état vide qui dit la vérité au lieu de
  présenter des indicateurs macroéconomiques comme des prix au kilo.
- `hooks/use-markets.ts` pointe sur ce nouvel endpoint.

### 9.3 Garde-fou outillé

Nouveau script `scripts/audit-frontend-data.py` (225 fichiers analysés) qui
refuse, en connaissance de cause :

1. un repli chiffré non nul sur une valeur d'API affichée (`d?.x ?? 60`) ;
2. une série de graphique générée (`Math.random`, `Math.sin` dans `Array.from`) ;
3. un écran sans aucune source de données (avertissement).

Les replis de confort (pagination, `staleTime`, progression audio, `zoom`,
densité d'écran, valeur initiale de formulaire) sont explicitement neutralisés
pour que le rapport reste exploitable.

État actuel : **0 défaut bloquant**, 4 avis (3 pages légales statiques, 1 valeur
initiale de formulaire).


## 10. Intégration continue et protection des branches

Le dépôt distant est organisé en quatre branches (`main`, `frontend`, `backend`,
`docs`). Deux conséquences ont dû être traitées :

1. **Les scripts de contrôle ont besoin des deux côtés du contrat.** Le travail
   `contract` récupère donc trois branches (`docs` à la racine, `frontend` et
   `backend` dans des dossiers temporaires) puis reconstitue l'arborescence
   attendue (`frontend/`, `backend/`) avant de lancer les deux vérifications.
2. **Un workflow n'existe que sur la branche où il est commité.** Le fichier
   `.github/workflows/ci.yml` est donc présent sur les quatre branches ; les
   événements `push` en déclenchent une exécution partout, `pull_request` protège
   les fusions vers `main`.

### Travaux

| Travail | Outils | Ce qu'il prouve |
| --- | --- | --- |
| `contract` | Python 3.12, `check-api-contract.py`, `audit-frontend-data.py` | aucune route appelée n'est absente, aucune statistique n'est inventée |
| `frontend` | Node 20, `npm ci`, `tsc --noEmit`, `npm test`, `npm run build` | typage strict, tests au vert, build d'export statique complet (présence de `index.html` et `dashboard.html`) |
| `backend` | Python 3.12, `compileall`, analyse AST | modules compilables, 25 routeurs parsables, migrations Alembic avec une seule tête et sans parent manquant |

### Protection

Les quatre branches exigent ces trois vérifications (`strict: true`), interdisent
le force-push et la suppression, et la `main` exige en plus la résolution des
conversations avant fusion.

Première exécution : **3 travaux au vert**, 1 min 46 s à 2 min 22 s selon la
branche (le travail frontend domine : installation et build).


## 11. Mise en production du 26/11 : les douze causes d'échec

Le déploiement a d'abord échoué en cascade. Chaque cause a été isolée par une
observation, pas par une supposition.

### Côté poste de travail

| Symptôme | Cause | Correctif |
| --- | --- | --- |
| `$'': command not found` | scripts en CRLF lancés par WSL | conversion LF + `bash -n` sur les 6 scripts |
| `&&` refusé | commande collée dans PowerShell 5.1 | commandes Git Bash fournies en remplacement |
| `ftps://` injoignable | lftp bascule sur le port 990 (FTPS implicite) | `ftp://` + `set ftp:ssl-force yes` sur le port 21 |
| `530 Login authentication failed` | mot de passe contenant `#`, pris pour un commentaire par `lftp -u` | identifiants écrits dans un script lftp temporaire en 600 |
| `source: ... No such file or directory` | ce build Windows de lftp n'ouvre pas un chemin absolu avec `-f` | exécution depuis le dossier du script, chemin relatif |
| `mirror: ... No such file or directory` | lftp ne résout pas les chemins MSYS `/s/...` | chemins relatifs calculés avec `realpath --relative-to` |
| `Invalid preceding regular expression` | `--exclude *.pyc` (glob) au lieu d'une regex | `--exclude \.pyc$` |
| `python-multipart` / `fastapi[all]` | épingles incompatibles | extras choisis explicitement, `python-multipart==0.0.20` |
| `Failed to build 'blis'` | `spacy` sans wheel Python 3.12 Windows | pile ML sortie vers `requirements-ml.txt` (aucun import dans le code) |
| `Failed to build 'ecdsa'` | 0.18 sans wheel | `ecdsa==0.19.1` |
| `NameError: get_db` | `market_prices.py` utilisait un import absent | `from config.database import get_db` |
| `EBUSY ... rmdir out` | un serveur de test servait `out/` | arrêt des serveurs avant build |

### Côté serveur

| Symptôme | Cause | Correctif |
| --- | --- | --- |
| site figé sur l'ancienne version | `REMOTE_ROOT` pointait sur `/agriintel360.lsgrouptogo.com`, dossier jamais servi | racine FTP = `/home/c2606883c/public_html/agriintel360` → backend dans `/api` |
| `404` sur toutes les routes API | `proxy-api.php` retirait le préfixe `/api` | chemin transmis tel quel, cohérent avec `ws-tunnel.php` |
| code neuf ignoré | `mirror` comparait taille et date, fichiers de même taille non renvoyés | `--ignore-time` |
| ancien code malgré fichiers neufs | `.pyc` en cache de juillet | purge `__pycache__` + redémarrage |
| `Multiple head revisions` | `010_add_geo_divisions.py` resté d'un déploiement précédent | suppression du fichier orphelin |
| migration 008 en échec | identifiant de 37 caractères > `alembic_version.version_num(32)` | révision renommée `008` |
| admin impossible à créer | `duplicate key users_username_key` : compte `admin` existant avec un autre e-mail | `admin_seed` cherche aussi par nom d'utilisateur et met l'e-mail à jour |
| 403 sur tout le site | `.htaccess` du dépôt refusé par Apache | `.htaccess` plus déployé par défaut (option `AGRI_REPLACE_HTACCESS=true`) |
| smoke tests en 403 | le middleware CSRF exige `X-Requested-With`, absent des `curl` de test | en-tête ajouté aux tests F3/F8 |

### Résultat final

```
F1 Frontend statique  ✅ 200      F5 Email / SMTP     ✅ OK
F2 API health         ✅ OK       F6 WebSocket        ⚠️ incertain
F3 Auth endpoint      ✅ 401      F7 Routes branchées ✅ 7/7
F4 Base de données    ✅ OK       F8 Parcours connecté ✅ 3/3
RÉSULTAT : 7 OK | 0 ÉCHEC | 1 AVERT
```

Le build servi est identique au build local (même empreinte MD5 sur `index.html`).
