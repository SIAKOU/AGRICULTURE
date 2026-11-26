/**
 * Affichage des valeurs chiffrées issues de l'API.
 *
 * Règle du produit : **une statistique inconnue n'est jamais remplacée par un
 * chiffre plausible**. Afficher « 60 acteurs » parce que l'API n'a pas répondu
 * est un mensonge à l'utilisateur ; on affiche un tiret cadratin et l'écran
 * laisse apparaître son état vide ou d'erreur.
 *
 * Ce module est volontairement isolé de `lib/utils.ts` (1 100 lignes) pour être
 * importé par les tableaux de bord sans charger tout le reste.
 */

const EMPTY = '—';

export interface StatFormatOptions {
  /** Nombre de décimales (0 par défaut). */
  decimals?: number;
  /** Suffixe collé au nombre, ex. « % » ou « ha ». */
  suffix?: string;
  /** Préfixe, ex. « + » pour une variation positive. */
  prefix?: string;
  /** Locale de formatage (fr-FR par défaut). */
  locale?: string;
  /** Valeur renvoyée quand la donnée est absente. */
  fallback?: string;
}

/**
 * Formate une statistique d'API.
 *
 * - `null`, `undefined`, `''`, `NaN` → `—` (ou `fallback`)
 * - `0` reste `0` : c'est une information, pas une absence
 * - les chaînes numériques (`"12"`) sont acceptées
 */
export function formatStat(value: unknown, options: StatFormatOptions = {}): string {
  const { decimals = 0, suffix = '', prefix = '', locale = 'fr-FR', fallback = EMPTY } = options;

  if (value === null || value === undefined || value === '') return fallback;

  const numeric = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(numeric)) return fallback;

  const formatted = numeric.toLocaleString(locale, {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });

  return `${prefix}${formatted}${suffix}`;
}

/** Variation signée : `+2,4 %` / `-1,1 %` / `—`. */
export function formatVariation(value: unknown, decimals = 1): string {
  if (value === null || value === undefined || value === '') return EMPTY;
  const numeric = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(numeric)) return EMPTY;
  const sign = numeric > 0 ? '+' : '';
  return formatStat(numeric, { decimals, prefix: sign, suffix: ' %' });
}
