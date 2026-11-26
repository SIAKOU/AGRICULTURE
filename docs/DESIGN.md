# Design system — AgriIntel360

Interface agricole de décision : dense en données, lisible au soleil comme au
bureau, en français, sur un téléphone d'entrée de gamme comme sur un écran large.
La direction visuelle est **éditoriale agraire** : surfaces de papier ivoire en
clair, sous-bois profond en sombre, or comme unique accent, typographie
Playfair Display en italique pour les titres de scène.

## 1. Source unique de vérité

```
frontend/styles/tokens.css     ← couleurs, formes, ombres, mouvement, plans
frontend/tailwind.config.js    ← expose les jetons aux classes utilitaires
frontend/styles/globals.css    ← base HTML + classes composées (.card-base, …)
```

Règle : **aucune valeur littérale dans un composant**. Un composant utilise
`bg-card`, `text-muted-foreground`, `border-border`, `shadow-sm`, jamais
`#0C1810` ni `rgba(15,23,42,0.7)`. Les cas restants (graphiques, PDF, images OG)
utilisent `require('tailwind.config.js').brand`, palette figée indépendante du
thème.

## 2. Jetons

### Couleurs de marque (primitives)

| Jeton | Rôle | Usage |
| --- | --- | --- |
| `--c-foret-900` | sous-bois | fond du thème sombre |
| `--c-sol-50` / `-100` | ivoire | fond du thème clair, surfaces secondaires |
| `--c-or-500/600` | or | accent : titres, chiffres, focus, état actif |
| `--c-laterite-600` | latérite | alertes chaudes, secondaire |
| `--c-lagune-600` | lagune | eau, halieutique, séries de données |
| `--c-sauge-*` | sauge | texte secondaire, éléments inactifs |

### Couleurs sémantiques (suivent le thème)

`background`, `foreground`, `card`, `popover`, `muted`, `primary`, `secondary`,
`accent`, `success`, `warning`, `destructive`, `border`, `input`, `ring`,
`surface-1`, `surface-2`, `surface-glass`, `surface-halo`, plus les quatre
secteurs : `vegetal`, `animal`, `halieutique`, `forestier`.

Un composant écrit une seule fois fonctionne en clair et en sombre : les classes
`bg-card` / `text-foreground` pointent vers des variables qui changent avec la
classe `.dark`.

### Formes et profondeur

- Rayons : `--radius` (0.75rem) et dérivés `rounded-sm|lg|xl`. `rounded-card`,
  `rounded-button`, `rounded-input` restent disponibles.
- Ombres : `--shadow-xs|sm|md|lg` exposées en `shadow-xs|sm|md|lg`. Une carte
  au repos n'utilise que `xs` ou `sm` ; l'ombre `md` signale une interaction.
- Filets : 1 px `border-border`. Pas de bordure en opacité 20 % : elle disparaît
  sur écran de terrain.

### Typographie

| Rôle | Police | Taille |
| --- | --- | --- |
| Titres de scène (landing, auth) | `font-display` (Playfair, italique) | `clamp(1.75rem, 3.5vw, 2.625rem)` |
| Titres d'écran (dashboard) | Inter 700 | `1.5rem`, `tracking -0.01em` |
| Texte courant | Inter | `0.9375rem`, interligne 1.6 |
| Chiffres, identifiants | `font-data` (JetBrains Mono) + `tabular` | selon contexte |
| Étiquette de section | `.landing-eyebrow` / `SectionLabel` | 0.625–0.6875rem, `tracking 0.14–0.2em` |

Les titres `h1…h4` ont une échelle fluide définie dans `globals.css`.
Les utilitaires Tailwind (`text-lg`, …) gardent la priorité en cas de conflit.

### Mouvement

`--dur-fast 140ms`, `--dur-base 220ms`, `--dur-slow 420ms`,
`--ease-out-expo` pour les entrées, `--ease-in-out-soft` pour les transitions
d'état. `prefers-reduced-motion` neutralise toutes les animations.
Une animation sert à expliquer un changement d'état, jamais à décorer une carte.

### Plans

`z-sticky 20`, `z-drawer 30`, `z-header 40`, `z-overlay 50`, `z-popover 60`,
`z-toast 70` — exposés en `z-sticky|drawer|header|overlay|popover|toast`.
La barre supérieure passe au-dessus du tiroir mobile ; la navigation latérale
reste sous l'en-tête.

## 3. Composants de référence

| Composant | Fichier | À utiliser pour |
| --- | --- | --- |
| `Surface`, `SurfaceHeader`, `SectionLabel` | `components/ui/surface.tsx` | toute carte, tout panneau, toute étiquette de groupe |
| `UserAvatar` | `components/shared/avatar.tsx` | avatar utilisateur (photo ou initiale) |
| `PageShell` | `components/layout/page-shell.tsx` | gabarit d'écran du dashboard |
| `EmptyState`, `ErrorState`, `LoadingScreen` | `components/shared/` | états non nominaux |
| `SectorBadge`, `SeverityBadge` | `components/shared/` | étiquettes de domaine et de gravité |

Variantes de `Surface` : `flat` (défaut), `elevated`, `glass`, `interactive`.

## 4. Règles d'écriture d'un écran

1. `PageShell` fournit fil d'Ariane, titre, description, actions et états.
2. Le contenu se compose de `Surface` ; une seule carte `elevated` par écran.
3. Espacement : gouttière `4` sur mobile, `6` à partir de `sm`, jamais de marge
   manuelle supérieure à `8`.
4. Une action principale par écran, en `primary` ; le reste en `outline`/`ghost`.
5. Tableau de données : en-tête `text-xs uppercase tracking-wide
   text-muted-foreground`, chiffres en `font-data tabular`.
6. Couleurs de secteur : uniquement `vegetal|animal|halieutique|forestier`.
7. Tout texte doit atteindre le contraste AA sur sa surface : le texte secondaire
   est `text-muted-foreground`, jamais une opacité `< 0.7`.

## 5. Accessibilité

- Cible de focus unique : 2 px `--ring`, décalage 2 px, visible sur clair/sombre.
- Cibles tactiles : 44 px minimum en pointeur grossier.
- Contrastes renforcés : `prefers-contrast: more` épaissit les filets et le focus.
- Couleurs forcées : `forced-colors: active` pose des bordures `CanvasText`.
- Le dashboard fournit un lien « Aller au contenu principal » et des
  `aria-current="page"` sur la navigation.

## 6. État de la migration

Tokenisés et refondus : `styles/`, `tailwind.config.js`, shell du dashboard
(`app/(dashboard)/layout.tsx`, `sidebar`, `header`, `page-shell`), page publique
(`hero-section`, `stats-bar`), avatars.

Reste à tokeniser (couleurs encore littérales, sans impact fonctionnel) :
`app/(auth)/login`, `app/(landing)/contact`, `components/dashboard/production-chart`,
`components/shared/command-palette`, `components/landing/pricing-cards`.
Méthode : remplacer la valeur par la classe sémantique équivalente, vérifier en
clair **et** en sombre, puis supprimer l'import de couleur inutilisé.


## 7. Migration des couleurs littérales — état mesuré

Migration menée par passes mécaniques successives, chacune vérifiée par
`tsc --noEmit`, `npm run build` et `npm test` avant la suivante.

| Passe | Périmètre | Occurrences |
| --- | --- | --- |
| départ | tous les `.tsx` | 704 dans 57 fichiers |
| 1 | 4 écrans listés initialement (login, contact, pricing, auth-shell) | 704 → 513 |
| 2 | `style={{ }}`, propriétés CSS, classes `bg-[…]` | 513 → 282 |
| 3 | affectations impératives, ternaires JSX | 282 → 234 |
| 4 | `*Color`, dégradés, `accent-[…]` | 234 → 212 |

**212 occurrences restantes, et c'est volontaire.** Elles ne décrivent plus de
l'habillage mais des **identités de données** :

| Catégorie | Exemple | Pourquoi le littéral est correct |
| --- | --- | --- |
| Couleurs de secteur | `iconColor: '#FB923C'` pour Élevage | un secteur garde sa couleur en thème clair comme sombre |
| Séries de graphiques | `COLORS = ['#C4923A', …]` pour Recharts | Recharts écrit des attributs SVG `fill`/`stroke`, où `var()` ne se résout pas |
| Types d'événement | `post_created: '#60A5FA'` | la couleur encode la catégorie, pas la hiérarchie visuelle |
| Logos de fournisseurs | `#EA4335` de Google | couleur de marque, imposée |
| Couches de carte | peintures MapLibre | expressions évaluées par WebGL, hors CSS |

Règle qui en découle : **un jeton sémantique décrit une surface d'interface, une
couleur littérale décrit une donnée.** Toute couleur d'habillage passe par
`tokens.css` ; toute couleur identitaire reste littérale, mais doit être
centralisée (prochaine étape : `lib/palette.ts` pour les secteurs et les séries,
afin qu'aucun composant ne porte la valeur en propre).

Vérification finale de cette passe : `tsc` 0 erreur, `npm test` 8/8,
`npm run build` 41 pages, `audit-frontend-data.py` 0 défaut bloquant.


## 8. `lib/palette.ts` — la source unique des couleurs identitaires

Les couleurs qui encodent une donnée (secteur, série, gravité, robustesse d'un
mot de passe) étaient recopiées dans les écrans. Elles vivent désormais dans un
seul module :

| Export | Usage |
| --- | --- |
| `SECTOR_COLORS`, `SECTOR_CHART_COLORS` | une teinte par secteur, en variante jeton ou littérale |
| `CHART_SERIES`, `seriesColor(i)` | séries catégorielles, avec repli cyclique — jamais `undefined` |
| `CHART_ACCENTS` | production, prix, température, pluie, rendement, volume |
| `SEVERITY_COLORS` | info, avertissement, critique, urgence |
| `KPI_GLOW` | halo des cartes d'indicateurs |
| `EVENT_COLORS`, `eventColor(k)` | actions communautaires |
| `PASSWORD_STRENGTH_COLORS` | échelle de robustesse d'un mot de passe |
| `rgba`, `hexAlpha`, `sectorColor`, `sectorRgb` | composition et replis neutres |

Deux variantes coexistent volontairement : la forme jeton (`hsl(var(--…))`) pour
l'habillage, la forme littérale pour les contextes qui ne résolvent pas `var()`.

`__tests__/palette.test.ts` verrouille 9 propriétés : couverture des secteurs,
repli neutre sur une clé inconnue, absence d'`undefined` quel que soit l'index de
série, unicité des séries, bornes d'opacité, conversion `#rgb` et `#rrggbb`.

### Contrôle automatisé

`scripts/audit-frontend-data.py` signale désormais toute couleur de la palette
recopiée dans un composant. État de la migration : **82 recopies restantes**
(contre 111 avant cette passe), concentrées dans les écrans de contenu —
`app/(dashboard)/weather`, `markets/compare`, `admin`, `predictions`,
`hooks/use-calendar`, `lib/export-pdf` (couleurs d'impression, hors thème).

## 9. Repli inventé supprimé sur la carte

`hooks/use-geolocation.ts` injectait trois marqueurs de démonstration (Dakar,
Lomé, Accra) quand l'appel `/actors/` échouait : l'utilisateur voyait trois
acteurs qui n'existent pas. Le repli est supprimé et `map-page-client.tsx`
affiche un état vide explicite. Les couleurs de secteur viennent de la palette.
