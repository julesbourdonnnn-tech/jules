// Génère tests/harness/TextMetrics.luau depuis le navigateur (vraies polices de Google Fonts).
//   node tools/screens/metrics.mjs          (depuis la racine du projet)
//
// Pour chaque police (tools/screens/fonts.mjs) : la largeur d'avance de chaque caractère utilisé
// par le jeu, mesurée À LA TAILLE ROBLOX 100 (une ligne de 100 px de haut, voir fonts.mjs), plus
// le rapport hauteur de ligne / cadratin et la part de la ligne au-dessus de la ligne de base.
// Caractères mesurés : ASCII imprimable, tous les caractères non ASCII des fichiers de src/ (dont
// Localization/Strings.luau, EN et FR), espaces insécables, symboles et replis des glyphes de
// manette. Approximation assumée : le crénage (kerning) est ignoré, chaque caractère est mesuré
// seul ; une chaîne mesure la somme de ses caractères (écart typique < 2 % avec le rendu réel).

import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';
import { FONTS, launch, fontPage, ensureFonts, canvasFont } from './fonts.mjs';

const ROOT = process.cwd();
const OUT = path.join(ROOT, 'tests/harness/TextMetrics.luau');

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, out);
    else if (/\.luau?$/.test(e.name)) out.push(full);
  }
  return out;
}

function collectCodepoints() {
  const set = new Set();
  for (let c = 0x20; c <= 0x7e; c++) set.add(c);
  // espaces insécables, ponctuation française et typographique, glyphes de repli (losange, flèches)
  for (const ch of '   «»’‘“”…—–·×÷≈±°%€$£✕○□△◆◇●◉↑↓←→★☆✦✧✓✔✗☄☁✺⚡♥❤⏱⌛∞™®©') {
    set.add(ch.codePointAt(0));
  }
  for (const file of walk(path.join(ROOT, 'src'), [])) {
    const text = fs.readFileSync(file, 'utf8');
    for (const ch of text) {
      const cp = ch.codePointAt(0);
      if (cp >= 0xa0) set.add(cp);
    }
  }
  // caractères invisibles ou de contrôle exclus (sélecteurs de variante : largeur nulle)
  return [...set].filter((cp) => !(cp >= 0xd800 && cp <= 0xdfff)).sort((a, b) => a - b);
}

const codepoints = collectCodepoints();
const sample = String.fromCodePoint(...codepoints);

const browser = await launch();
const page = await fontPage(browser);
await ensureFonts(page, sample);

const fonts = {};
for (const key of Object.keys(FONTS)) {
  const ref = canvasFont(key, 100);
  const result = await page.evaluate(
    ({ ref, key, codepoints, specFor }) => {
      const ctx = document.createElement('canvas').getContext('2d');
      ctx.fontKerning = 'none';
      ctx.font = ref;
      const m = ctx.measureText('Hg');
      const asc = m.fontBoundingBoxAscent;
      const desc = m.fontBoundingBoxDescent;
      const lineRatio = (asc + desc) / 100;
      // taille CSS pour une ligne Roblox de 100 px
      const css = 100 / lineRatio;
      ctx.font = specFor.replace('__PX__', String(css));
      const widths = {};
      let total = 0;
      let n = 0;
      for (const cp of codepoints) {
        const w = ctx.measureText(String.fromCodePoint(cp)).width;
        widths[cp] = Math.round(w * 100) / 100;
        if (cp >= 0x61 && cp <= 0x7a) {
          total += w;
          n += 1;
        }
      }
      return { lineRatio, ascent: asc / (asc + desc), widths, avg: total / n, key };
    },
    { ref, key, codepoints, specFor: canvasFont(key, '__PX__') },
  );
  fonts[key] = { css: FONTS[key].css, weight: FONTS[key].weight, ...result };
  console.log(
    `${key.padEnd(20)} ${FONTS[key].css.padEnd(14)} ligne/cadratin ${result.lineRatio.toFixed(3)}  ` +
      `moyenne a-z ${result.avg.toFixed(1)} px à la taille 100`,
  );
}
await browser.close();

const lines = [];
lines.push('--!nocheck');
lines.push('-- GÉNÉRÉ par tools/screens/metrics.mjs (node tools/screens/metrics.mjs) : ne pas modifier à la main.');
lines.push('-- Largeur d\'avance de chaque caractère, en px, à la TAILLE ROBLOX 100 (TextSize = hauteur d\'une');
lines.push('-- ligne : la taille CSS mesurée vaut 100 / lineRatio), mesurée dans Chromium avec les polices de');
lines.push('-- Google Fonts (Montserrat remplace Gotham, non libre). Crénage ignoré (caractères mesurés seuls).');
lines.push('-- lineRatio : (ascendante + descendante) / cadratin ; ascent : part de la ligne au-dessus de la');
lines.push('-- ligne de base ; avg : largeur moyenne des minuscules a-z (repli des caractères inconnus).');
lines.push('return {');
lines.push('\tsize = 100,');
lines.push('\tfonts = {');
for (const [key, f] of Object.entries(fonts)) {
  lines.push(`\t\t["${key}"] = {`);
  lines.push(`\t\t\tcss = "${f.css}",`);
  lines.push(`\t\t\tweight = ${f.weight},`);
  lines.push(`\t\t\tlineRatio = ${f.lineRatio.toFixed(4)},`);
  lines.push(`\t\t\tascent = ${f.ascent.toFixed(4)},`);
  lines.push(`\t\t\tavg = ${f.avg.toFixed(2)},`);
  lines.push('\t\t\twidths = {');
  for (const cp of codepoints) {
    lines.push(`\t\t\t\t[${cp}] = ${f.widths[cp]},`);
  }
  lines.push('\t\t\t},');
  lines.push('\t\t},');
}
lines.push('\t},');
lines.push('}');
fs.writeFileSync(OUT, lines.join('\n') + '\n');

// formatage StyLua (le fichier fait partie de tests/, vérifié par ./scripts/check.sh)
const stylua = path.join(process.env.HOME || '', '.cargo/bin/stylua');
try {
  execFileSync(fs.existsSync(stylua) ? stylua : 'stylua', [OUT], { stdio: 'inherit' });
} catch (e) {
  console.warn('StyLua introuvable : formater tests/harness/TextMetrics.luau à la main');
}
console.log(`${codepoints.length} caractères × ${Object.keys(fonts).length} polices → ${path.relative(ROOT, OUT)}`);
