# AgriIntel360 — Documentation et vérifications

Documentation de référence du produit **et** l'outillage qui vérifie ses
promesses. Rien ici n'est décoratif : chaque affirmation renvoie à un fichier ou
à une commande exécutable.

> Cette branche contient la documentation et les scripts de contrôle. Le site
> vit sur [`frontend`](../../tree/frontend), l'API sur [`backend`](../../tree/backend).

## Sommaire

| Document | Contenu |
| --- | --- |
| [`docs/ANALYSE.md`](docs/ANALYSE.md) | Diagnostic complet : inventaire, défauts constatés avec preuve, corrections, reste à faire |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Carte du système, flux de données, sources externes, décisions structurantes |
| [`docs/DESIGN.md`](docs/DESIGN.md) | Design system : jetons, typographie, composants, accessibilité, relief 3D |
| [`docs/SECURITY.md`](docs/SECURITY.md) | Modèle de menace, contrôles en place, procédures de vérification, reste à faire |

## Outillage de vérification

Trois contrôles automatiques, sans base de données ni réseau :

```bash
python scripts/check-api-contract.py     # toute route appelée existe côté API
python scripts/audit-frontend-data.py    # aucune valeur inventée à l'écran
bash -n deploy/*.sh                      # syntaxe des scripts d'exploitation
```

### `check-api-contract.py`

Compare les appels du frontend (`apiClient.*`, `fetch`) aux routes réellement
exposées par `api/routers/router.py` (préfixes d'inclusion et préfixes propres
des routeurs résolus par analyse AST). Comprend les alias d'import, les appels
`fetch`, les gabarits avec segments dynamiques et les expressions ternaires.

État mesuré : **161 routes appelées, 0 écart** pour 286 routes exposées.

### `audit-frontend-data.py`

Refuse trois familles de défauts :

1. **repli inventé** — `d?.total_actors ?? 60` : un chiffre plausible affiché
   quand l'API est muette. Une statistique inconnue doit s'afficher `—`.
2. **série synthétique** — courbe construite avec `Math.random` / `Math.sin`.
3. **écran orphelin** — page sans hook de données ni composant client.

Les replis légitimes (pagination, `staleTime`, progression audio, zoom, valeur
initiale de formulaire) sont explicitement neutralisés pour que le rapport reste
exploitable en intégration continue.

État mesuré : **226 fichiers, 0 défaut bloquant**.

## Décisions qui structurent le produit

1. **Le frontend est un export statique** : pas de serveur Node en production.
   Conséquence : pas de middleware, pas de nonce CSP, chaque route doit être
   déclarée manuellement (navigation, gardes).
2. **Aucune donnée inventée** : une absence s'affiche comme une absence.
3. **Aucun jeton lisible par JavaScript** : cookie `HttpOnly`, l'interface ne
   persiste qu'un marqueur d'expiration.
4. **Le déploiement échoue si une API ne répond pas** : modules F7 (contrat des
   routes) et F8 (parcours authentifié) du script de déploiement.
5. **Un seul jeu de jetons de design** : clair et sombre sont égaux en droit ;
   une couleur en dur dans un composant est un défaut.

## Licence

MIT — voir [LICENSE](./LICENSE).
