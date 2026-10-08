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
// « node scripts/seo.mjs --bloc en » : renvoie seulement le contenu prérendu traduit (utilisé par scripts/i18n.py)
const BLOC = process.argv[2] === "--bloc" ? process.argv[3] : null;
await import(path.join(ROOT, BLOC ? `${BLOC}/js/data.js` : "js/data.js"));
const { HOUSES, DESTINATIONS, REVIEWS } = globalThis;
const LABELS = {
  fr: { g: "voyageurs", ch: "chambres", li: "lits", sdb: "salles de bain", note: (r, n) => `note ${r} sur 5 (${n} avis`, sh: ", hôte Superhost", book: "Voir les disponibilités et réserver en direct (−10 %)", airbnb: "Réserver sur Airbnb", forts: "Les points forts", maison: "La maison", chambres: "Les chambres", equip: "Équipements", nondispo: "Non disponible :", quartier: "Le quartier et les environs", guides: "Nos guides :", regles: "Règlement et informations utiles", avis: "Avis des voyageurs", noteAvis: (r, n) => `Note ${r} sur 5, ${n} avis.`, q: ["« ", " »"], enreg: "Numéro d'enregistrement en mairie :", autre: (a) => `À environ une heure de route : ${a}, notre autre maison.`, dec: "," , sep: " : ",
    guidesT: { "vacances-famille-lacanau": "Vacances en famille à Lacanau : le guide", "guide-plages-lacanau": "Les plages de Lacanau en famille", "guide-semaine-gironde-famille": "Une semaine en Gironde en famille", "vacances-famille-bordeaux": "Bordeaux en famille : le guide" } },
  en: { g: "guests", ch: "bedrooms", li: "beds", sdb: "bathrooms", note: (r, n) => `rated ${r} out of 5 (${n} reviews`, sh: ", Superhost", book: "See availability and book direct (10% off)", airbnb: "Book on Airbnb", forts: "Highlights", maison: "The house", chambres: "Bedrooms", equip: "Amenities", nondispo: "Not available:", quartier: "The area and surroundings", guides: "Our guides:", regles: "House rules and useful information", avis: "Guest reviews", noteAvis: (r, n) => `Rated ${r} out of 5, ${n} reviews.`, q: ["“", "”"], enreg: "Town hall registration number:", autre: (a) => `About an hour's drive away: ${a}, our other house.`, dec: ".", sep: ": ",
    guidesT: { "vacances-famille-lacanau": "Family holidays in Lacanau: the guide", "guide-plages-lacanau": "Lacanau's beaches with children", "guide-semaine-gironde-famille": "A week in the Gironde with the family", "vacances-famille-bordeaux": "Bordeaux with the family: the guide" } },
  es: { g: "viajeros", ch: "dormitorios", li: "camas", sdb: "baños", note: (r, n) => `valoración de ${r} sobre 5 (${n} reseñas`, sh: ", Superanfitrión", book: "Ver la disponibilidad y reservar directamente (−10 %)", airbnb: "Reservar en Airbnb", forts: "Lo mejor", maison: "La casa", chambres: "Los dormitorios", equip: "Equipamiento", nondispo: "No disponible:", quartier: "El barrio y los alrededores", guides: "Nuestras guías:", regles: "Normas de la casa e información útil", avis: "Reseñas de los viajeros", noteAvis: (r, n) => `Valoración de ${r} sobre 5, ${n} reseñas.`, q: ["«", "»"], enreg: "Número de registro municipal:", autre: (a) => `A aproximadamente una hora en coche: ${a}, nuestra otra casa.`, dec: ",", sep: ": ",
    guidesT: { "vacances-famille-lacanau": "Vacaciones en familia en Lacanau: la guía", "guide-plages-lacanau": "Las playas de Lacanau en familia", "guide-semaine-gironde-famille": "Una semana en familia en la Gironda", "vacances-famille-bordeaux": "Burdeos en familia: la guía" } },
};
const L = LABELS[BLOC || "fr"];

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
  const rating = (Number.isInteger(h.rating) && L.dec === "." ? h.rating.toFixed(1) : String(h.rating)).replace(".", L.dec);
  const [qo, qc] = L.q;
  return `
    <div class="prerender page"><div class="wrap wrap--narrow">
      <p class="eyebrow">${esc(h.place)} · ${esc(h.region)}</p>
      <h1 class="h1">${esc(h.name)}</h1>
      <p class="lead">${esc(h.title)}. ${esc(h.teaser)}</p>
      <p>${esc(h.type)} · ${h.guests} ${L.g} · ${h.bedrooms} ${L.ch} · ${h.beds} ${L.li} · ${h.bathrooms} ${L.sdb} · ${L.note(rating, h.reviewsCount)}${h.superhost ? L.sh : ""}).</p>
      <p><img src="assets/photos/${k}/${String(h.cover).padStart(2, "0")}-md.webp" alt="${esc(h.name)}" width="1100" height="825"></p>
      <p><a href="#reserver">${L.book}</a> · <a href="${esc(h.airbnbUrl)}" rel="noopener">${L.airbnb}</a></p>
      <h2>${L.forts}</h2>
      <ul>${h.highlights.map(([, t, d]) => `<li><strong>${esc(t)}</strong>${L.sep}${esc(d)}</li>`).join("")}</ul>
      <h2>${L.maison}</h2>
      ${h.description.map((d) => `${d.title ? `<h3>${esc(d.title)}</h3>` : ""}${para(d.text)}`).join("")}
      <h2>${L.chambres}</h2>
      <ul>${h.sleeping.map(([n, b]) => `<li>${esc(n)}${L.sep}${esc(b)}</li>`).join("")}</ul>
      <h2>${L.equip}</h2>
      ${h.amenities.map(([cat, list]) => `<h3>${esc(cat)}</h3><ul>${list.map((a) => `<li>${esc(a)}</li>`).join("")}</ul>`).join("")}
      ${h.notIncluded && h.notIncluded.length ? `<p>${L.nondispo} ${h.notIncluded.map(esc).join(", ")}.</p>` : ""}
      <h2>${L.quartier}</h2>
      <p>${esc(h.neighbourhood)} ${esc(h.gettingAround)}</p>
      <p>${esc(strip(D.intro))}</p>
      <ul>${D.places.map(([n, dist, t]) => `<li><strong>${esc(n)}</strong> (${esc(dist)})${L.sep}${esc(t)}</li>`).join("")}</ul>
      <p>${L.guides} ${GUIDES[k].map(([u]) => `<a href="${u}">${esc(L.guidesT[u])}</a>`).join(" · ")}</p>
      <h2>${L.regles}</h2>
      ${Object.entries(h.rules).map(([cat, list]) => `<h3>${esc(cat)}</h3><ul>${list.map((r) => `<li>${esc(r)}</li>`).join("")}</ul>`).join("")}
      <h2>${L.avis}</h2>
      <p>${L.noteAvis(rating, h.reviewsCount)}</p>
      ${(REVIEWS[k] || []).map(([t, who, when]) => `<blockquote><p>${qo}${esc(t)}${qc}</p><footer>${esc(who)}, ${esc(when)}</footer></blockquote>`).join("")}
      ${h.registration ? `<p>${L.enreg} ${esc(h.registration)}</p>` : ""}
      <p>${L.autre(`<a href="${other.page}">${esc(other.name)}</a>`)}</p>
    </div></div>`;
}

if (BLOC) {
  process.stdout.write(JSON.stringify({ lacanau: houseBlock("lacanau"), bordeaux: houseBlock("bordeaux") }));
  process.exit(0);
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
// Versions anglaise et espagnole (générées par scripts/i18n.py) : chaque page indique ses traductions
const LANGS = ["fr", ...["en", "es"].filter((l) => fs.existsSync(path.join(ROOT, l, "index.html")))];
const loc = (l, p) => `${SITE}${l === "fr" ? "" : `/${l}`}${p}`;
const alts = (p) => LANGS.map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${loc(l, p)}"/>`).join("") + `<xhtml:link rel="alternate" hreflang="x-default" href="${loc("fr", p)}"/>`;
const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${LANGS.flatMap((l) => pages.map(([p, prio, freq, im]) => `  <url><loc>${loc(l, p)}</loc><lastmod>${today}</lastmod><changefreq>${freq}</changefreq><priority>${prio}</priority>${LANGS.length > 1 ? alts(p) : ""}${im}</url>`)).join("\n")}
</urlset>
`;
fs.writeFileSync(path.join(ROOT, "sitemap.xml"), sitemap);
console.log(`sitemap.xml : ${pages.length} pages × ${LANGS.length} langues`);
