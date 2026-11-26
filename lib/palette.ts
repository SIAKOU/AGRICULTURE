/**
 * Palette identitaire — les couleurs qui encodent une DONNÉE, pas une surface.
 *
 * Règle du projet (docs/DESIGN.md §7) : un jeton sémantique de `tokens.css`
 * décrit l'habillage (fond, texte, bordure, focus) et suit le thème clair ou
 * sombre. Une couleur identitaire décrit une catégorie — un secteur, une série
 * de graphique, un type d'événement — et doit rester stable dans les deux
 * thèmes, sinon la même série change de couleur quand l'utilisateur bascule.
 *
 * Deux raisons techniques empêchent d'utiliser `hsl(var(--…))` partout ici :
 * Recharts écrit des attributs SVG `fill`/`stroke`, et Canvas attend une valeur
 * de couleur résolue ; ni l'un ni l'autre ne sait résoudre `var()`.
 *
 * Ce module est la seule source de ces valeurs : aucun composant ne doit
 * porter un code hexadécimal en propre.
 */

/** Triplets « r,g,b » d'une couleur hexadécimale, sans passer par le DOM. */
function hexRgb(hex: string): string {
  const clean = hex.replace('#', '');
  const full =
    clean.length === 3
      ? clean
          .split('')
          .map((c) => c + c)
          .join('')
      : clean;
  return [0, 2, 4].map((i) => parseInt(full.slice(i, i + 2), 16)).join(',');
}

/**
 * Couleurs de secteur : une seule teinte par secteur, partagée par les cartes
 * du tableau de bord et les séries de graphiques. Deux variantes de teintes
 * différentes (un vert ici, un brun là) donnaient deux identités au même
 * secteur — « Forestier » apparaissait vert en carte et brun en légende.
 *
 * La forme littérale est retenue : ces teintes identifient une catégorie et ne
 * doivent pas changer avec le thème.
 */
export const SECTOR_COLORS = {
  vegetal: { color: '#16A34A', rgb: '22,163,74' },
  animal: { color: '#D97706', rgb: '217,119,6' },
  halieutique: { color: '#0891B2', rgb: '8,145,178' },
  forestier: { color: '#92400E', rgb: '146,64,14' },
} as const;

export type SectorKey = keyof typeof SECTOR_COLORS;

/** Couleurs d'action communautaire : la teinte distingue le geste, pas le rang. */
export const EVENT_COLORS = {
  post_created: '#60A5FA',
  post_liked: '#34D399',
  post_commented: '#F59E0B',
  post_shared: '#A78BFA',
  member_joined: '#34D399',
  member_promoted: '#A78BFA',
  poll_voted: '#F59E0B',
  event_joined: '#60A5FA',
  post_bookmarked: '#F87171',
} as const;

export type EventKey = keyof typeof EVENT_COLORS;

/** Séries catégorielles des graphiques, dans l'ordre d'attribution. */
export const CHART_SERIES = [
  '#16A34A',
  '#D97706',
  '#0891B2',
  '#7C3AED',
  '#DC2626',
  '#EC4899',
  '#6366F1',
  '#14B8A6',
] as const;

/** Teinte d'une grandeur suivie : production, prix, température, pluie. */
export const CHART_ACCENTS = {
  production: '#16A34A',
  price: '#D97706',
  temperature: '#F97316',
  precipitation: '#0EA5E9',
  yield: '#7C3AED',
  volume: '#0891B2',
} as const;

export type ChartAccent = keyof typeof CHART_ACCENTS;

/** Halo des cartes d'indicateurs, aligné sur les états sémantiques. */
export const KPI_GLOW = {
  success: '#34D399',
  info: '#60A5FA',
  warning: '#FBBF24',
  danger: '#F87171',
  critical: '#FB923C',
} as const;

export type KpiGlow = keyof typeof KPI_GLOW;

/**
 * Série attendue par index, avec repli cyclique : un graphique qui reçoit plus
 * de séries que la palette n'en compte ne produit jamais de couleur `undefined`.
 */
export function seriesColor(index: number): string {
  const size = CHART_SERIES.length;
  const safe = ((index % size) + size) % size;
  return CHART_SERIES[safe];
}

/** `rgba()` depuis des triplets « r,g,b » — utilisé par les fonds translucides. */
export function rgba(triplets: string, alpha: number): string {
  const clamped = Math.min(1, Math.max(0, alpha));
  return `rgba(${triplets.trim()},${clamped})`;
}

/** `rgba()` depuis un hexadécimal de la palette identitaire. */
export function hexAlpha(hex: string, alpha: number): string {
  const clean = hex.replace('#', '');
  const full =
    clean.length === 3
      ? clean
          .split('')
          .map((c) => c + c)
          .join('')
      : clean;
  const r = parseInt(full.slice(0, 2), 16);
  const g = parseInt(full.slice(2, 4), 16);
  const b = parseInt(full.slice(4, 6), 16);
  return rgba(`${r},${g},${b}`, alpha);
}

/** Teinte de secteur, avec repli neutre si la clé est inconnue du backend. */
export function sectorColor(key: string): string {
  return (SECTOR_COLORS as Record<string, { color: string }>)[key]?.color ?? 'hsl(var(--muted-foreground))';
}

/** Teinte d'une action communautaire, avec repli neutre pour un type inconnu. */
export function eventColor(key: string): string {
  return (EVENT_COLORS as Record<string, string>)[key] ?? 'hsl(var(--muted-foreground))';
}

/** Triplets de secteur, pour les fonds translucides. */
export function sectorRgb(key: string): string {
  const entry = (SECTOR_COLORS as Record<string, { rgb: string }>)[key];
  return entry?.rgb ?? hexRgb(SECTOR_CHART_COLORS.minier);
}

/**
 * Variante littérale des couleurs de secteur, pour les contextes qui ne savent
 * pas résoudre `var()` : séries Recharts, canvas, peintures MapLibre.
 * Elle couvre deux secteurs de plus que `SECTOR_COLORS` (mines, industrie),
 * présents dans le référentiel métier mais absents du tableau de bord.
 */
export const SECTOR_CHART_COLORS = {
  vegetal: SECTOR_COLORS.vegetal.color,
  animal: SECTOR_COLORS.animal.color,
  halieutique: SECTOR_COLORS.halieutique.color,
  forestier: SECTOR_COLORS.forestier.color,
  minier: '#6B7280',
  industriel: '#4F46E5',
} as const;

/** Niveaux de gravité d'une alerte, du plus anodin au plus urgent. */
export const SEVERITY_COLORS = {
  info: '#3B82F6',
  warning: '#EAB308',
  critical: '#F97316',
  emergency: '#DC2626',
} as const;

/** Échelle de robustesse d'un mot de passe, du plus faible au meilleur. */
export const PASSWORD_STRENGTH_COLORS = [
  '#DC2626',
  '#F97316',
  '#EAB308',
  '#22C55E',
  '#16A34A',
  '#15803D',
] as const;
