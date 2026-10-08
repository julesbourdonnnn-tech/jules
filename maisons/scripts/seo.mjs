/*
 * Référencement : à relancer après une modification de js/data.js ou l'ajout d'une page.
 *   node scripts/seo.mjs
 * 1. Écrit dans lacanau.html et bordeaux.html le contenu complet de la fiche en HTML simple
 *    (entre <!-- seo:debut --> et <!-- seo:fin -->), lisible par tous les moteurs de recherche.
 *    Avec JavaScript, js/house.js remplace ce bloc par la fiche interactive (même contenu).
 * 2. Génère sitemap.xml (plan du site pour Google et Bing).
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const SITE = "https://sable-et-pierre.com";
globalThis.window = globalThis;
await import(path.join(ROOT, "js/data.js"));
const { HOUSES, DESTINATIONS, REVIEWS } = globalThis;

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const para = (t) => esc(t).split("\n").filter(Boolean).map((l) => `<p>${l}</p>`).join("");
const strip = (s) => String(s).replace(/<[^>]+>/g, "");
const GUIDES = {
  lacanau: [["vacances-famille-lacanau", "Vacances en famille à Lacanau : le guide"], ["guide-plages-lacanau", "Les plages de Lacanau en famille"], ["guide-semaine-gironde-famille", "Une semaine en Gironde en famille"]],
  bordeaux: [["vacances-famille-bordeaux", "Bordeaux en famille : le guide"], ["guide-semaine-gironde-famille", "Une semaine en Gironde en famille"]],
};

function houseBlock(k) {
  const h = HOUSES[k];
  const D = DESTINATIONS[k];
  const other = HOUSES[k === "lacanau" ? "bordeaux" : "lacanau"];
  const rating = String(h.rating).replace(".", ",");
  return `
    <div class="prerender page"><div class="wrap wrap--narrow">
      <p class="eyebrow">${esc(h.place)} · ${esc(h.region)}</p>
      <h1 class="h1">${esc(h.name)}</h1>
      <p class="lead">${esc(h.title)}. ${esc(h.teaser)}</p>
      <p>${esc(h.type)} · ${h.guests} voyageurs · ${h.bedrooms} chambres · ${h.beds} lits · ${h.bathrooms} salles de bain · note ${rating} sur 5 (${h.reviewsCount} avis${h.superhost ? ", hôte Superhost" : ""}).</p>
      <p><img src="assets/photos/${k}/${String(h.cover).padStart(2, "0")}-md.webp" alt="${esc(h.name)}" width="1100" height="825"></p>
      <p><a href="#reserver">Voir les disponibilités et réserver en direct (−10 %)</a> · <a href="${esc(h.airbnbUrl)}" rel="noopener">Réserver sur Airbnb</a></p>
      <h2>Les points forts</h2>
      <ul>${h.highlights.map(([, t, d]) => `<li><strong>${esc(t)}</strong> : ${esc(d)}</li>`).join("")}</ul>
      <h2>La maison</h2>
      ${h.description.map((d) => `${d.title ? `<h3>${esc(d.title)}</h3>` : ""}${para(d.text)}`).join("")}
      <h2>Les chambres</h2>
      <ul>${h.sleeping.map(([n, b]) => `<li>${esc(n)} : ${esc(b)}</li>`).join("")}</ul>
      <h2>Équipements</h2>
      ${h.amenities.map(([cat, list]) => `<h3>${esc(cat)}</h3><ul>${list.map((a) => `<li>${esc(a)}</li>`).join("")}</ul>`).join("")}
      ${h.notIncluded && h.notIncluded.length ? `<p>Non disponible : ${h.notIncluded.map(esc).join(", ")}.</p>` : ""}
      <h2>Le quartier et les environs</h2>
      <p>${esc(h.neighbourhood)} ${esc(h.gettingAround)}</p>
      <p>${esc(D.intro)}</p>
      <ul>${D.places.map(([n, dist, t]) => `<li><strong>${esc(n)}</strong> (${esc(dist)}) : ${esc(t)}</li>`).join("")}</ul>
      <p>Nos guides : ${GUIDES[k].map(([u, t]) => `<a href="${u}">${esc(t)}</a>`).join(" · ")}</p>
      <h2>Règlement et informations utiles</h2>
      ${Object.entries(h.rules).map(([cat, list]) => `<h3>${esc(cat)}</h3><ul>${list.map((r) => `<li>${esc(r)}</li>`).join("")}</ul>`).join("")}
      <h2>Avis des voyageurs</h2>
      <p>Note ${rating} sur 5, ${h.reviewsCount} avis.</p>
      ${(REVIEWS[k] || []).map(([t, who, when]) => `<blockquote><p>« ${esc(t)} »</p><footer>${esc(who)}, ${esc(when)}</footer></blockquote>`).join("")}
      ${h.registration ? `<p>Numéro d'enregistrement en mairie : ${esc(h.registration)}</p>` : ""}
      <p>À environ une heure de route : <a href="${other.page}">${esc(other.name)}</a>, notre autre maison.</p>
    </div></div>`;
}

for (const k of ["lacanau", "bordeaux"]) {
  const file = path.join(ROOT, `${k}.html`);
  let html = fs.readFileSync(file, "utf8");
  const block = `<!-- seo:debut (généré par scripts/seo.mjs, ne pas modifier à la main) -->${houseBlock(k)}\n    <!-- seo:fin -->`;
  if (html.includes("<!-- seo:debut")) html = html.replace(/<!-- seo:debut[\s\S]*?<!-- seo:fin -->/, block);
  else html = html.replace(/<noscript>[\s\S]*?<\/noscript>/, block);
  fs.writeFileSync(file, html);
  console.log(`${k}.html : contenu prérendu (${strip(houseBlock(k)).replace(/\s+/g, " ").length} caractères)`);
}

// Plan du site (avec les photos, pour Google Images)
const today = new Date().toISOString().slice(0, 10);
const img = (k, n, cap) => `<image:image><image:loc>${SITE}/assets/photos/${k}/${String(n).padStart(2, "0")}-xl.webp</image:loc><image:title>${esc(`${HOUSES[k].name} — ${cap}`)}</image:title></image:image>`;
const photosOf = (k) => HOUSES[k].photos.map(([n, cap]) => img(k, n, cap)).join("");
const pages = [
  ["/", "1.0", "weekly", img("lacanau", HOUSES.lacanau.cover, "la maison et la piscine") + img("bordeaux", HOUSES.bordeaux.cover, "la pièce de vie")],
  ["/lacanau", "0.9", "weekly", photosOf("lacanau")],
  ["/bordeaux", "0.9", "weekly", photosOf("bordeaux")],
  ...fs.readdirSync(ROOT).filter((f) => /^vacances-.*\.html$|^guide-.*\.html$/.test(f)).sort().map((f) => [`/${f.replace(/\.html$/, "")}`, "0.8", "monthly", ""]),
];
const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
${pages.map(([p, prio, freq, im]) => `  <url><loc>${SITE}${p}</loc><lastmod>${today}</lastmod><changefreq>${freq}</changefreq><priority>${prio}</priority>${im}</url>`).join("\n")}
</urlset>
`;
fs.writeFileSync(path.join(ROOT, "sitemap.xml"), sitemap);
console.log(`sitemap.xml : ${pages.length} pages`);
