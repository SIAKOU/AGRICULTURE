# AgriIntel360 — Frontend

Application web d'intelligence agricole : tableaux de bord, cartographie 3D,
messagerie, prédictions et communautés. Next.js 15.5 en **export statique** —
aucun serveur Node en production, le build est servi par Apache.

> Cette branche contient uniquement le site. L'API vit sur la branche
> [`backend`](../../tree/backend), la documentation sur [`docs`](../../tree/docs).

## Démarrage

```bash
npm install
npm run dev        # http://localhost:3000
```

Variables d'environnement (`.env.local`) :

| Variable | Rôle |
| --- | --- |
| `NEXT_PUBLIC_API_URL` | base de l'API en développement (proxy `next dev`) |
| `NEXT_PUBLIC_API_PREFIX` | préfixe des routes (`/api/v1`) |
| `NEXT_PUBLIC_WS_URL` | WebSocket temps réel |
| `NEXT_PUBLIC_ALLOW_JS_TOKEN` | **développement uniquement** : jeton en sessionStorage quand il n'y a pas de proxy |

Aucun secret ne doit porter le préfixe `NEXT_PUBLIC_` : ces valeurs partent dans
le bundle client.

## Scripts

```bash
npm run build        # export statique dans out/
npm start            # serveur local sur le build
npm test             # Jest (preset next/jest)
npm run lint
npx tsc --noEmit     # typage strict
```

## Organisation

```
app/            écrans (landing, auth, dashboard) — App Router
components/     ui/ (design system), layout/ (shell), shared/, par domaine
hooks/          un hook TanStack Query par domaine
lib/            api-client (disjoncteur, erreurs), i18n, formatage, carte
stores/         zustand : auth, ui, filtres, carte
styles/         tokens.css (source unique des couleurs) + globals.css
types/          contrats TypeScript alignés sur les schémas Pydantic
__tests__/      tests unitaires et helpers
```

## Conventions

- **Aucune couleur en dur** : tout passe par `styles/tokens.css` (clair et sombre).
- **Aucune donnée inventée** : une statistique absente s'affiche `—`
  (`lib/format-display.ts`), jamais une valeur plausible.
- **Aucun jeton lisible en JS** : l'API pose un cookie `HttpOnly`, le client
  envoie `credentials: 'include'` (`lib/auth-session.ts`).
- Toute page ajoutée doit être déclarée dans `components/layout/sidebar.tsx`,
  sinon elle reste inaccessible (export statique, pas de route serveur).

## Relief 3D

- Cartes à relief au pointeur : `components/ui/tilt-card.tsx` (`Surface3D`,
  `DepthLayers`), désactivées sous `prefers-reduced-motion` et sur tactile.
- Carte géographique avec **relief réel** : MapLibre + MNT public
  (`components/map/interactive-map.tsx`, `setTerrain`), sans clé d'API.

## Licence

MIT — voir [LICENSE](./LICENSE).
