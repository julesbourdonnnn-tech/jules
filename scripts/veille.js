#!/usr/bin/env node
/*
 * Outil des commis (veille des établissements).
 *   node scripts/veille.js lot [n]     les n établissements à vérifier aujourd'hui (les moins récemment vérifiés)
 *   node scripts/veille.js verifier    contrôle data/veille.json (à lancer avant chaque publication)
 *   node scripts/veille.js etat        résumé : établissements vérifiés, actualités en cours
 */
const fs = require("fs");
const path = require("path");
const ROOT = path.join(__dirname, "..");
global.window = global;
for (const f of ["js/config.js", "js/hotels.js"]) require(path.join(ROOT, f));
const ALL = (global.HOTELS || []).concat(global.HOTELS_CLOSED || []);
const FILE = path.join(ROOT, "data", "veille.json");
const V = JSON.parse(fs.readFileSync(FILE, "utf8"));
V.hotels = V.hotels || {};
const TYPES = ["fermeture", "reouverture", "nouveaute", "offre", "evenement", "info"];
const ISO = /^\d{4}-\d{2}-\d{2}$/;
const today = new Date().toISOString().slice(0, 10);
const [cmd = "etat", arg] = process.argv.slice(2);

if (cmd === "lot") {
  const n = Number(arg) || 10;
  const lot = ALL.slice()
    .sort((a, b) => String((V.hotels[a.id] || {}).checked || "").localeCompare(String((V.hotels[b.id] || {}).checked || "")) || a.name.localeCompare(b.name, "fr"))
    .slice(0, n)
    .map((h) => ({
      id: h.id, name: h.name, city: h.city, region: h.region, website: h.website || "",
      fermeture_en_cours: h.closed || null,
      derniere_verification: (V.hotels[h.id] || {}).checked || "jamais",
      actualites_en_cours: ((V.hotels[h.id] || {}).news || []),
    }));
  console.log(JSON.stringify(lot, null, 2));
} else if (cmd === "verifier") {
  const errors = [];
  const ids = new Set(ALL.map((h) => h.id));
  for (const [id, entry] of Object.entries(V.hotels)) {
    if (!ids.has(id)) errors.push(`${id} : établissement inconnu (vérifier l'id dans js/hotels.js)`);
    if (entry.checked && !ISO.test(entry.checked)) errors.push(`${id} : checked doit être au format AAAA-MM-JJ`);
    if (entry.checked > today) errors.push(`${id} : checked est dans le futur`);
    (entry.news || []).forEach((n, i) => {
      const where = `${id} › actualité ${i + 1}`;
      if (!TYPES.includes(n.type)) errors.push(`${where} : type inconnu (${n.type}) ; types : ${TYPES.join(", ")}`);
      if (!ISO.test(n.date || "")) errors.push(`${where} : date manquante ou mal écrite (AAAA-MM-JJ)`);
      if (n.until && !ISO.test(n.until)) errors.push(`${where} : until mal écrit (AAAA-MM-JJ)`);
      if (n.until && n.date && n.until < n.date) errors.push(`${where} : until avant la date`);
      if (n.type === "offre" && !n.until) errors.push(`${where} : une offre doit avoir une date de fin (until)`);
      if (!/^https:\/\//.test(n.source || "")) errors.push(`${where} : source obligatoire (lien https)`);
      if (!n.text || n.text.length < 15 || n.text.length > 240) errors.push(`${where} : texte de 15 à 240 caractères`);
      if (/[<>]/.test(n.text || "")) errors.push(`${where} : pas de HTML dans le texte`);
    });
  }
  if (errors.length) { console.error("✗ " + errors.join("\n✗ ")); process.exit(1); }
  console.log(`✓ data/veille.json valide (${Object.keys(V.hotels).length} établissements suivis)`);
} else {
  const checked = ALL.filter((h) => (V.hotels[h.id] || {}).checked);
  const live = Object.entries(V.hotels).flatMap(([id, e]) => (e.news || []).filter((n) => (n.until ? n.until >= today : true)).map((n) => `${id} · ${n.type} · ${n.text}`));
  console.log(`${checked.length}/${ALL.length} établissements déjà vérifiés`);
  console.log(`Fermés en ce moment : ${(global.HOTELS_CLOSED || []).map((h) => h.id).join(", ") || "aucun"}`);
  console.log(`Actualités en cours :\n${live.join("\n") || "aucune"}`);
}
