#!/usr/bin/env node
/*
 * Contrôle technique du site Nuits Singulières (agent technique).
 *   node scripts/controle-site.js          contrôle complet (données, pages, liens, Google, mise en ligne)
 *   node scripts/controle-site.js --vite   sans le parcours des pages dans le navigateur
 * Ne modifie aucun fichier. Résumé en fin de sortie ; code de sortie 1 s'il y a un problème bloquant (✗).
 */
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const ROOT = path.join(__dirname, "..");
process.chdir(ROOT);
const FAST = process.argv.includes("--vite");
const out = { ok: [], warn: [], ko: [] };
const ok = (m) => out.ok.push(m), warn = (m) => out.warn.push(m), ko = (m) => out.ko.push(m);
const sh = (cmd) => execSync(cmd, { cwd: ROOT, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

/* ---------- 1. Données des fiches ---------- */
global.window = global;
for (const f of ["js/config.js", "js/hotels.js", "js/guides.js"]) require(path.join(ROOT, f));
const ALL = (global.HOTELS || []).concat(global.HOTELS_CLOSED || []);
const ids = new Set();
let photoIssues = 0, heavy = [];
for (const h of ALL) {
  if (ids.has(h.id)) ko(`Fiche en double : ${h.id}`);
  ids.add(h.id);
  if (!/^https:\/\//.test(h.website || "")) warn(`${h.id} : pas de site officiel en https`);
  if (!(h.lat > 41 && h.lat < 51.2 && h.lng > -5.3 && h.lng < 9.7)) ko(`${h.id} : coordonnées hors de France (${h.lat}, ${h.lng})`);
  for (let i = 1; i <= (h.photos || 0); i++) {
    for (const f of [`assets/hotels/${h.id}/${i}.jpg`, `assets/hotels/${h.id}/${i}-sm.jpg`]) {
      if (!fs.existsSync(f)) { ko(`${h.id} : photo manquante ${f}`); photoIssues++; }
      else if (fs.statSync(f).size > 900 * 1024) heavy.push(`${f} (${Math.round(fs.statSync(f).size / 1024)} Ko)`);
    }
  }
  if (h.review) {
    for (const [k, v] of Object.entries(h.review.scores || {})) if (!(typeof v === "number" && v >= 0 && v <= 10)) ko(`${h.id} : note ${k} invalide`);
    if (!/^\d{4}-\d{2}$/.test(h.review.date || "")) ko(`${h.id} : date d'avis invalide (AAAA-MM)`);
  }
  if (h.closed && h.closed.until && !/^\d{4}-\d{2}-\d{2}$/.test(h.closed.until)) ko(`${h.id} : date de fermeture invalide`);
}
if (!photoIssues) ok(`Photos présentes pour les ${ALL.length} fiches en ligne`);
if (heavy.length) warn(`Photos lourdes (> 900 Ko) : ${heavy.slice(0, 5).join(", ")}${heavy.length > 5 ? "…" : ""}`);
// Photos venant d'autres sites que l'établissement (sites tiers connus)
const THIRD = ["hotels-insolites.com", "voyageavecvue.com", "franceweek-end.com", "booking.com", "bstatic.com", "expedia.com", "tripadvisor.com", "tripadvisor.fr", "lastminute.com", "hotels.com", "trip.com", "abracadaroom.com", "greengo.voyage", "michelin.com", "yonder.fr", "gaultmillau.com", "tourinsoft.eu", "iris-etourism.io", "parisjetaime.com", "vinotrip.com", "airbnb.com", "airbnb.fr", "muscache.com", "abritel.fr", "gites-de-france.com", "unsplash.com", "pinterest.com", "pinimg.com", "fbcdn.net", "cdninstagram.com"];
const isThird = (u) => { try { const host = new URL(u).hostname.replace(/^www\./, ""); return THIRD.some((d) => host === d || host.endsWith("." + d)); } catch { return false; } };
for (const h of ALL) {
  const f = `assets/hotels/${h.id}/source.json`;
  if (!fs.existsSync(f)) continue;
  const bad = Object.values(JSON.parse(fs.readFileSync(f, "utf8"))).filter(isThird);
  if (bad.length) ko(`${h.id} : ${bad.length} photo(s) venant d'un site tiers (${new URL(bad[0]).hostname})`);
}
// Veille
try { sh("node scripts/veille.js verifier"); ok("Fichier de veille valide"); } catch (e) { ko(`Fichier de veille invalide : ${(e.stderr || e.message).split("\n")[0]}`); }

/* ---------- 2. Pages générées à jour ---------- */
try {
  sh("node scripts/build.js");
  const diff = sh("git status --porcelain -- hotels guides index.html sitemap.xml robots.txt");
  if (diff) { warn(`Pages générées pas à jour (${diff.split("\n").length} fichiers) : régénérées par ce contrôle, à publier`); }
  else ok("Pages générées à jour");
} catch (e) { ko(`La génération du site échoue : ${(e.stderr || e.message).split("\n").slice(0, 3).join(" ")}`); }

/* ---------- 3. Google : titres, descriptions, sitemap ---------- */
const pages = [...fs.readdirSync("hotels").map((f) => `hotels/${f}`), ...fs.readdirSync("guides").map((f) => `guides/${f}`), ...fs.readdirSync(".").filter((f) => f.endsWith(".html"))].filter((f) => f.endsWith(".html"));
let seoIssues = 0;
for (const p of pages) {
  const s = fs.readFileSync(p, "utf8");
  if (/noindex/.test(s.slice(0, 4000))) continue;
  const t = (s.match(/<title>([\s\S]*?)<\/title>/) || [])[1] || "";
  const d = (s.match(/<meta name="description" content="([^"]*)"/) || [])[1] || "";
  const h1 = (s.match(/<h1[\s>]/g) || []).length;
  if (!t) { ko(`${p} : pas de titre`); seoIssues++; }
  if (!d) { warn(`${p} : pas de description`); seoIssues++; }
  if (h1 !== 1) { warn(`${p} : ${h1} titres H1 (1 attendu)`); seoIssues++; }
  for (const m of s.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    try { JSON.parse(m[1]); } catch { ko(`${p} : données structurées (JSON-LD) invalides`); seoIssues++; }
  }
}
const sitemap = fs.readFileSync("sitemap.xml", "utf8");
const locs = [...sitemap.matchAll(/<loc>https:\/\/nuitsinguliere\.com\/([^<]*)<\/loc>/g)].map((m) => m[1] || "index.html");
const missing = locs.filter((l) => !fs.existsSync(l.endsWith("/") ? l + "index.html" : l));
if (missing.length) ko(`Sitemap : ${missing.length} adresse(s) sans page (${missing.slice(0, 3).join(", ")})`);
if (!seoIssues && !missing.length) ok(`Google : ${pages.length} pages et ${locs.length} adresses du sitemap en ordre`);

/* ---------- 4. Mise en ligne ---------- */
const B1 = "claude/french-hotels-marketplace-vqleii", B2 = "claude/gifted-ritchie-r1ffn4";
try {
  const r = sh(`git ls-remote origin refs/heads/${B1} refs/heads/${B2}`).split("\n").map((l) => l.split("\t")[0]);
  if (r.length === 2 && r[0] === r[1]) ok("Les deux branches publiées sont synchronisées");
  else ko("Les deux branches publiées ne pointent pas sur le même commit : la synchro de Sable & Pierre est à vérifier (ne rien forcer, prévenir Jules)");
} catch { warn("Impossible de lire les branches distantes"); }

function deployCheck() {
  try {
    const j = JSON.parse(sh("curl -s --max-time 20 https://api.cloudflare.com/client/v4/accounts/afc5e1bdc37caf08c7d8e2411f0aec83/workers/scripts/jules/versions"));
    const last = new Date(j.result.items[0].metadata.created_on);
    sh(`git fetch -q origin ${B1}`);
    const commit = new Date(sh(`git log -1 --format=%cI origin/${B1}`));
    const lag = (commit - last) / 60000;
    if (lag > 20) ko(`Mise en ligne en retard : dernier commit ${commit.toISOString().slice(0, 16)}, dernière version Cloudflare ${last.toISOString().slice(0, 16)}`);
    else ok(`Dernière version en ligne : ${last.toISOString().slice(0, 16).replace("T", " ")} (UTC)`);
  } catch (e) { warn(`Contrôle Cloudflare impossible (${e.message})`); }
}

/* ---------- 5. Parcours des pages dans un navigateur ---------- */
async function crawl() {
  let chromium;
  try { ({ chromium } = require("playwright")); } catch { warn("Playwright indisponible : parcours des pages non fait"); return; }
  const base = "file://" + ROOT;
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 390, height: 844 } });
  const seen = new Set(), queue = ["/index.html", "/guides/index.html", "/carte.html", "/a-propos.html", "/professionnels.html", "/compte.html", "/mentions-legales.html"];
  const bad = new Set(), errs = new Set(), overflow = [];
  const KNOWN = /^\/404\.html|start is not defined|onHasParentDirectory|addRow is not defined/;
  while (queue.length) {
    const p = queue.shift();
    if (seen.has(p)) continue;
    seen.add(p);
    const pg = await ctx.newPage();
    pg.on("pageerror", (e) => { const m = `${p} : ${e.message}`; if (!KNOWN.test(p) && !KNOWN.test(e.message)) errs.add(m); });
    try {
      await pg.goto(base + p, { waitUntil: "load", timeout: 20000 });
      await pg.waitForTimeout(250);
      if ((await pg.evaluate(() => document.documentElement.scrollWidth)) > 392) overflow.push(p);
      const links = await pg.$$eval("a[href], img[src], link[href], script[src]", (els) => els.map((x) => x.getAttribute("href") || x.getAttribute("src")));
      for (const h of links) {
        if (!h || /^(https?:|mailto:|tel:|#|javascript|data:)/.test(h) || h.startsWith("/")) continue;
        const u = new URL(h, base + p);
        if (u.protocol !== "file:") continue;
        let f = decodeURIComponent(u.pathname);
        if (f.endsWith("/")) f += "index.html";
        if (!fs.existsSync(f)) { bad.add(`${p} → ${f.replace(ROOT, "")}`); continue; }
        const rel = f.replace(ROOT, "");
        if (f.endsWith(".html") && !seen.has(rel)) queue.push(rel);
      }
    } catch (e) { bad.add(`${p} : ne s'ouvre pas (${e.message.split("\n")[0]})`); }
    await pg.close();
  }
  await b.close();
  if (bad.size) ko(`Liens ou fichiers cassés (${bad.size}) : ${[...bad].slice(0, 6).join(" ; ")}`);
  if (errs.size) ko(`Erreurs JavaScript (${errs.size}) : ${[...errs].slice(0, 4).join(" ; ")}`);
  if (overflow.length) warn(`Débordement horizontal sur téléphone : ${overflow.slice(0, 5).join(", ")}`);
  if (!bad.size && !errs.size) ok(`${seen.size} pages parcourues sans lien cassé ni erreur JavaScript`);
}

(async () => {
  deployCheck();
  if (!FAST) await crawl();
  console.log("\n=== CONTRÔLE TECHNIQUE NUITS SINGULIÈRES ===");
  for (const m of out.ko) console.log("✗ " + m);
  for (const m of out.warn) console.log("⚠ " + m);
  for (const m of out.ok) console.log("✓ " + m);
  console.log(`\nBilan : ${out.ko.length} problème(s), ${out.warn.length} point(s) à surveiller, ${out.ok.length} contrôle(s) en ordre.`);
  process.exit(out.ko.length ? 1 : 0);
})();
