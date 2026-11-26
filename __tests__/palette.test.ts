import {
  CHART_ACCENTS,
  CHART_SERIES,
  EVENT_COLORS,
  KPI_GLOW,
  SECTOR_COLORS,
  hexAlpha,
  rgba,
  sectorColor,
  sectorRgb,
  seriesColor,
} from '@/lib/palette';

/**
 * La palette identitaire est la seule source des couleurs de données. Ces tests
 * verrouillent les propriétés dont dépendent les écrans : une couleur par
 * secteur, un repli quand le backend envoie une clé inconnue, et aucune valeur
 * `undefined` quand un graphique demande plus de séries que la palette n'en
 * compte.
 */
describe('palette identitaire', () => {
  it('donne une couleur et des triplets à chaque secteur', () => {
    for (const [key, value] of Object.entries(SECTOR_COLORS)) {
      const colorIsValid = /^(#[0-9A-Fa-f]{6}|hsl\(var\(--[a-z-]+\)\))$/.test(value.color);
      const rgbIsValid = /^\d{1,3},\d{1,3},\d{1,3}$/.test(value.rgb);
      if (!colorIsValid) throw new Error(`couleur invalide pour ${key} : ${value.color}`);
      if (!rgbIsValid) throw new Error(`triplets invalides pour ${key} : ${value.rgb}`);
    }
  });

  it('retombe sur un gris neutre pour un secteur inconnu', () => {
    expect(sectorColor('cacao')).toBe('hsl(var(--muted-foreground))');
    expect(sectorRgb('cacao')).toBe('125,148,134');
  });

  it('ne produit jamais undefined, quel que soit l’index de série', () => {
    for (const index of [-3, -1, 0, 3, CHART_SERIES.length, CHART_SERIES.length + 5]) {
      const color = seriesColor(index);
      if (typeof color !== 'string') throw new Error(`index ${index} : couleur absente`);
      expect(color).toMatch(/^#[0-9A-Fa-f]{6}$/);
    }
  });

  it('ne répète pas une couleur dans les séries', () => {
    expect(new Set(CHART_SERIES).size).toBe(CHART_SERIES.length);
  });

  it('couvre les grandeurs suivies par les graphiques', () => {
    for (const key of ['production', 'price', 'temperature', 'precipitation'] as const) {
      expect(CHART_ACCENTS[key]).toMatch(/^#[0-9A-Fa-f]{6}$/);
    }
  });

  it('couvre les états des cartes d’indicateurs', () => {
    for (const key of ['success', 'info', 'warning', 'danger'] as const) {
      expect(KPI_GLOW[key]).toMatch(/^#[0-9A-Fa-f]{6}$/);
    }
  });

  it('couvre les actions communautaires affichées', () => {
    for (const key of ['post_created', 'post_liked', 'member_joined'] as const) {
      expect(EVENT_COLORS[key]).toMatch(/^#[0-9A-Fa-f]{6}$/);
    }
  });

  it('compose rgba depuis des triplets et borne l’opacité', () => {
    expect(rgba('74,222,128', 0.12)).toBe('rgba(74,222,128,0.12)');
    expect(rgba('74,222,128', 2)).toBe('rgba(74,222,128,1)');
    expect(rgba('74,222,128', -1)).toBe('rgba(74,222,128,0)');
  });

  it('compose rgba depuis un hexadécimal, court ou long', () => {
    expect(hexAlpha('#FB923C', 0.12)).toBe('rgba(251,146,60,0.12)');
    expect(hexAlpha('#FFF', 0.5)).toBe('rgba(255,255,255,0.5)');
    expect(hexAlpha('FB923C', 1)).toBe('rgba(251,146,60,1)');
  });
});
