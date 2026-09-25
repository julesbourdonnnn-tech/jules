#!/usr/bin/env node
/*
 * Prépare le dossier « dist/ » à mettre en ligne (Cloudflare Pages, Netlify…) :
 * uniquement les fichiers du site, sans les outils internes (_review, data,
 * scripts, captures d'écran…).
 * Usage : node scripts/build.js && node scripts/dist.js
 */
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const OUT = path.join(ROOT, "dist");
const INCLUDE = [
  "index.html", "carte.html", "quiz.html", "jeu.html", "comparer.html", "a-propos.html", "selection.html", "hotel.html", "404.html", "liens.html", "mentions-legales.html",
  "studio.html", "sitemap.xml", "robots.txt", "_headers",
  "css", "js", "vendor", "hotels", "guides", "assets",
];
const SKIP = (rel) => /(^|\/)(source\.json|_done\.json|\.DS_Store)$/.test(rel);

fs.rmSync(OUT, { recursive: true, force: true });
let n = 0;
function copy(rel) {
  const src = path.join(ROOT, rel);
  if (!fs.existsSync(src) || SKIP(rel)) return;
  if (fs.statSync(src).isDirectory()) {
    for (const f of fs.readdirSync(src)) copy(path.join(rel, f));
    return;
  }
  const dest = path.join(OUT, rel);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  n++;
}
INCLUDE.forEach(copy);
console.log(`dist/ prêt : ${n} fichiers.`);
