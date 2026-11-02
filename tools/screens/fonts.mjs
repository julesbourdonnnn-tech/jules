// Polices du rendu hors jeu (tools/screens) : correspondance entre les familles Roblox et les
// polices de Google Fonts, chargement dans la page Chromium, mesures communes.
//
// Correspondance (documentée dans README.md) :
//   FredokaOne   → « Fredoka One »   (la même police, libre)
//   LuckiestGuy  → « Luckiest Guy »  (la même police, libre)
//   GothamSSm    → « Montserrat »    (Gotham n'est pas libre : Montserrat, graisse 700 pour
//                                      GothamBold, est la remplaçante libre la plus proche)
//   SourceSansPro→ « Source Sans 3 », LegacyArial → « Arimo » (métriques d'Arial)
// Les caractères absents de la police (☄ ✦ ★ ✕ ○ emojis…) passent par une pile de repli Noto,
// comme Roblox qui a lui aussi sa pile de repli (pas la même : écart documenté).
//
// Règle de taille de Roblox : TextSize est la HAUTEUR D'UNE LIGNE (ascendante + descendante de la
// police), pas la taille du cadratin CSS. Pour dessiner un texte Roblox de taille S, on prend donc
// une taille CSS de S / lineRatio, où lineRatio = (ascendante + descendante) / cadratin.

import { createRequire } from 'module';

export const require = createRequire(import.meta.url);

export const FALLBACK_STACK =
  '"Noto Sans Symbols 2", "Noto Sans Symbols", "Noto Sans Math", "Noto Color Emoji", "Noto Sans", "DejaVu Sans", sans-serif';

// clé TextMetrics → police CSS
export const FONTS = {
  'FredokaOne@400': { css: 'Fredoka One', weight: 400 },
  'LuckiestGuy@400': { css: 'Luckiest Guy', weight: 400 },
  'GothamSSm@400': { css: 'Montserrat', weight: 400 },
  'GothamSSm@500': { css: 'Montserrat', weight: 500 },
  'GothamSSm@700': { css: 'Montserrat', weight: 700 },
  'GothamSSm@900': { css: 'Montserrat', weight: 900 },
  'SourceSansPro@400': { css: 'Source Sans 3', weight: 400 },
  'SourceSansPro@700': { css: 'Source Sans 3', weight: 700 },
  'LegacyArial@400': { css: 'Arimo', weight: 400 },
  'BuilderSans@400': { css: 'Montserrat', weight: 400 },
  'BuilderSans@700': { css: 'Montserrat', weight: 700 },
};
export const DEFAULT_FONT = 'GothamSSm@400';

export const GOOGLE_CSS =
  'https://fonts.googleapis.com/css2?family=Fredoka+One&family=Luckiest+Guy' +
  '&family=Montserrat:wght@400;500;700;900&family=Source+Sans+3:wght@400;700&family=Arimo' +
  '&family=Noto+Sans:wght@400;700&family=Noto+Sans+Symbols&family=Noto+Sans+Symbols+2' +
  '&family=Noto+Sans+Math&family=Noto+Color+Emoji&display=block';

const WEIGHTS = {
  Thin: 100,
  ExtraLight: 200,
  Light: 300,
  Regular: 400,
  Medium: 500,
  SemiBold: 600,
  Bold: 700,
  ExtraBold: 800,
  Heavy: 900,
};

// { family: "rbxasset://fonts/families/FredokaOne.json", weight: "Bold" | 700, style } → clé
export function fontKey(face) {
  if (!face) return DEFAULT_FONT;
  const m = /([A-Za-z0-9]+)\.json$/.exec(face.family || '');
  const base = m ? m[1] : 'GothamSSm';
  const w = typeof face.weight === 'number' ? face.weight : WEIGHTS[face.weight] || 400;
  const exact = `${base}@${w}`;
  if (FONTS[exact]) return exact;
  // graisse la plus proche disponible pour cette famille
  let best = null;
  for (const k of Object.keys(FONTS)) {
    if (k.startsWith(base + '@')) {
      const kw = Number(k.split('@')[1]);
      if (best === null || Math.abs(kw - w) < Math.abs(Number(best.split('@')[1]) - w)) best = k;
    }
  }
  if (best) return best;
  // famille inconnue : Montserrat à la graisse la plus proche
  return w >= 600 ? 'GothamSSm@700' : DEFAULT_FONT;
}

export function cssFamily(key) {
  const f = FONTS[key] || FONTS[DEFAULT_FONT];
  return `"${f.css}", ${FALLBACK_STACK}`;
}

// Déclaration canvas : « [italic] 700 37.2px "Montserrat", … »
export function canvasFont(key, cssPx, italic = false, bold = false) {
  const f = FONTS[key] || FONTS[DEFAULT_FONT];
  const weight = bold ? Math.max(700, f.weight) : f.weight;
  return `${italic ? 'italic ' : ''}${weight} ${cssPx}px ${cssFamily(key)}`;
}

export async function launch() {
  const { chromium } = require('playwright');
  return chromium.launch();
}

// Page vide avec les polices Google déclarées ; attend leur chargement pour `sample`
export async function fontPage(owner, viewport) {
  // owner : Browser (page dans un nouveau contexte) ou BrowserContext (polices en cache partagé)
  const page =
    typeof owner.contexts === 'function'
      ? await owner.newPage({ viewport: viewport || { width: 800, height: 600 } })
      : await owner.newPage();
  await page.setContent(
    `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="${GOOGLE_CSS}"></head>` +
      '<body style="margin:0;background:#000"></body></html>',
    { waitUntil: 'networkidle' },
  );
  return page;
}

// Charge dans la page toutes les sous-parties des polices nécessaires à `text`
export async function ensureFonts(page, text) {
  const specs = Object.keys(FONTS).map((k) => canvasFont(k, 50));
  await page.evaluate(
    async ({ specs, text }) => {
      await Promise.all(specs.map((s) => document.fonts.load(s, text || 'A')));
      await document.fonts.ready;
    },
    { specs, text },
  );
}
