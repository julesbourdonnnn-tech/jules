#!/usr/bin/env node
/*
 * Génère les pages statiques du site (bien référencées sur Google) :
 *   hotels/<id>.html        une vraie page par établissement
 *   guides/<slug>.html      les guides thématiques
 *   guides/index.html       la liste des guides
 *   sitemap.xml, robots.txt le plan du site pour les moteurs de recherche
 *   index.html              (blocs « Guides » et « Toutes mes adresses »)
 *
 * Usage : node scripts/build.js      (aucune dépendance à installer)
 * Lancé automatiquement par la GitHub Action « Build » et par Netlify.
 */
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const ROOT = path.resolve(__dirname, "..");
global.window = global;
for (const f of ["js/config.js", "js/hotels.js", "js/guides.js"]) require(path.join(ROOT, f));
const C = require(path.join(ROOT, "js/core.js"));

const { CONFIG, HOTELS, ENVS, TYPES, GUIDES } = C.data();

/* ---------- Équipements et trajets ----------
 * data/hotels-infos.json (équipements vérifiés, gare, trains sourcés) + data/trajets-voiture.json
 * (temps en voiture calculés par la GitHub Action « Trajets »). Joints à chaque fiche et recopiés
 * dans js/hotels.js (window.HOTEL_INFOS) pour les filtres du navigateur. */
const readJson = (rel, fallback) => { try { return JSON.parse(fs.readFileSync(path.join(ROOT, rel), "utf8")); } catch { return fallback; } };
const INFOS = readJson("data/hotels-infos.json", { hotels: {} }).hotels || {};
const ROUTES = readJson("data/trajets-voiture.json", {});
const CORSE = (i) => /corse/i.test(i.acces || "");
const HOTEL_CITY = Object.fromEntries(HOTELS.concat(global.HOTELS_CLOSED || []).map((h) => [h.id, h.city]));
function compactInfos(id) {
  const i = INFOS[id];
  if (!i) return null;
  const r = ROUTES[id] || {};
  const out = { e: i.equip || [] };
  const t = {};
  for (const c of ["paris", "lyon", "bordeaux"]) {
    const tr = (i.train || {})[c];
    const inTown = tr && tr.min === 0 && (HOTEL_CITY[id] || "") === C.FROM[c];
    if (tr && typeof tr.min === "number") t[c] = [tr.min, !inTown && typeof r.gare === "number" ? r.gare : 0, tr.sur ? 1 : 0];
  }
  if (Object.keys(t).length) out.t = t;
  if (!CORSE(i)) {
    const v = {};
    for (const c of ["paris", "lyon", "bordeaux"]) if (typeof r[c] === "number") v[c] = r[c];
    if (Object.keys(v).length) out.v = v;
  }
  return out;
}
for (const h of HOTELS.concat(global.HOTELS_CLOSED || [])) h.infos = compactInfos(h.id);
function writeInfosBlock() {
  const file = path.join(ROOT, "js/hotels.js");
  const src = fs.readFileSync(file, "utf8");
  const ids = Object.keys(INFOS).sort();
  const obj = {};
  for (const id of ids) { const c = compactInfos(id); if (c) obj[id] = c; }
  const block = `window.HOTEL_INFOS = ${JSON.stringify(obj)};`;
  const next = src.replace(/(\/\* build:infos:end \*\/)/, "$1").replace(/window\.HOTEL_INFOS = [\s\S]*?;\n\/\* build:infos:end \*\//, `${block}\n/* build:infos:end */`);
  if (next !== src) fs.writeFileSync(file, next);
  return next !== src;
}
// Entrée du calcul des temps en voiture (GitHub Action « Trajets »)
function writeRouteInput() {
  const ent = {};
  for (const h of HOTELS.concat(global.HOTELS_CLOSED || []).sort((a, b) => a.id.localeCompare(b.id))) {
    const i = INFOS[h.id] || {};
    ent[h.id] = { lat: h.lat, lng: h.lng, gare: i.gare || null };
  }
  return write("data/trajets-entree.json", JSON.stringify(ent, null, 1) + "\n");
}
const { escapeHtml: e, img, budgetHtml, budgetOf, distanceKm } = C;
const SITE = CONFIG.siteUrl.replace(/\/$/, "");
// Veille des établissements (commis) : date de vérification et actualités affichées sur les fiches
const VEILLE = (() => { try { return JSON.parse(fs.readFileSync(path.join(ROOT, "data", "veille.json"), "utf8")).hotels || {}; } catch { return {}; } })();
const TODAY = new Date().toISOString().slice(0, 10);
const frDate = (iso) => new Date(`${iso}T12:00:00`).toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" });
const NEWS_LABEL = { fermeture: "Fermeture", reouverture: "Réouverture", nouveaute: "Nouveauté", offre: "Offre en cours", evenement: "Événement", info: "Bon à savoir" };
function liveNews(h) {
  const old = new Date(Date.now() - 120 * 864e5).toISOString().slice(0, 10);
  return ((VEILLE[h.id] || {}).news || [])
    .filter((n) => (n.until ? n.until >= TODAY : n.date >= old))
    .sort((a, b) => String(b.date).localeCompare(String(a.date)))
    .slice(0, 4);
}
function newsSection(h) {
  const list = liveNews(h);
  if (!list.length) return "";
  return `
        <section class="hotel-news reveal" aria-label="Actualités de l'établissement">
          <p class="eyebrow dark">Les actualités de l'établissement</p>
          <ul>${list.map((n) => `
            <li><span class="hn-type hn-${e(n.type)}">${e(NEWS_LABEL[n.type] || "Bon à savoir")}</span>
              <p>${e(n.text)}${n.until && n.type !== "fermeture" ? ` <span class="hn-until">Jusqu'au ${e(frDate(n.until))}.</span>` : ""}</p>
              <small>Repéré le ${e(frDate(n.date))} · <a href="${e(n.source)}" target="_blank" rel="noopener nofollow">source</a></small></li>`).join("")}
          </ul>
        </section>`;
}
const abs = (p) => `${SITE}/${p}`;
const absImg = (p) => `${SITE}/${p}`;

function write(rel, content) {
  const file = path.join(ROOT, rel);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const prev = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null;
  if (prev !== content) fs.writeFileSync(file, content);
  return prev !== content;
}
function clip(text, max = 158) {
  const t = text.replace(/\s+/g, " ").trim();
  if (t.length <= max) return t;
  const cut = t.slice(0, max - 1);
  return cut.slice(0, cut.lastIndexOf(" ")).replace(/[,;:.\s]+$/, "") + "…";
}
const jsonLd = (obj) => `<script type="application/ld+json">${JSON.stringify(obj).replace(/</g, "\\u003c")}</script>`;

const FONTS = `
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,300;0,9..144,400;0,9..144,600;1,9..144,300;1,9..144,400&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">`;
const SCRIPTS = (extra = "") => `
  <script src="../js/config.js"></script>
  <script src="../js/hotels.js"></script>
  <script src="../js/guides.js"></script>
  <script src="../js/core.js"></script>
  <script src="../js/common.js"></script>${extra}`;

function head({ title, description, canonical, image, type = "website", ld = [], leaflet = false }) {
  return `<!doctype html>
<html lang="fr" data-root="../">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${e(title)}</title>
  <meta name="description" content="${e(description)}">
  <link rel="canonical" href="${e(canonical)}">
  <meta property="og:site_name" content="${e(CONFIG.siteName)}">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:type" content="${type}">
  <meta property="og:title" content="${e(title)}">
  <meta property="og:description" content="${e(description)}">
  <meta property="og:url" content="${e(canonical)}">
  ${image ? `<meta property="og:image" content="${e(image)}">\n  <meta name="twitter:card" content="summary_large_image">` : ""}
  <meta name="robots" content="max-image-preview:large">
  <meta name="theme-color" content="#0f1a17">
  <link rel="icon" href="/favicon.ico" sizes="48x48">
  <link rel="icon" href="/favicon.svg" type="image/svg+xml">
  <link rel="icon" href="/favicon-192.png" type="image/png" sizes="192x192">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">${FONTS}
  ${leaflet ? `<link rel="stylesheet" href="../vendor/leaflet/leaflet.css">` : ""}
  <link rel="stylesheet" href="../css/style.css">
  ${ld.map(jsonLd).join("\n  ")}
</head>`;
}

const breadcrumbLd = (items) => ({
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  itemListElement: items.map(([name, url], i) => ({ "@type": "ListItem", position: i + 1, name, item: url })),
});

/* ============================================================
   FICHE ÉTABLISSEMENT
   ============================================================ */
function similarTo(h) {
  return HOTELS.filter((x) => x.id !== h.id)
    .map((x) => ({ x, score: (x.type === h.type ? 3 : 0) + (x.env === h.env ? 2 : 0) + (x.region === h.region ? 1 : 0) - distanceKm(h, x) / 1500 }))
    .sort((a, b) => b.score - a.score || a.x.id.localeCompare(b.x.id))
    .slice(0, 6)
    .map(({ x }) => x);
}

/* Questions fréquentes : uniquement à partir d'informations vérifiées de la fiche */
function hotelFaq(h) {
  const T = TYPES[h.type], b = budgetOf(h), tags = C.tagsOf(h);
  const faq = [
    [`Où se trouve ${h.name} ?`, `${h.name} se trouve à ${h.city} (${h.department}, région ${h.region}). Adresse : ${h.address}.`],
    [`Combien coûte une nuit à ${h.name} ?`, `Comptez ${b.range} pour deux personnes, à titre indicatif : le prix varie selon la saison, le jour de la semaine et l'hébergement choisi. Le tarif exact et les disponibilités sont donnés sur le site officiel de l'établissement.`],
    [`Quel type d'hébergement propose ${h.name} ?`, `${T.label} : ${h.rooms.charAt(0).toLowerCase()}${h.rooms.slice(1)}.${h.amenities.length ? ` Sur place : ${h.amenities.slice(0, 5).join(", ").toLowerCase()}.` : ""}`],
    [`Quand réserver ?`, `${C.bookingTip(h)}${h.season ? ` À noter : ${h.season.charAt(0).toLowerCase()}${h.season.slice(1)}.` : ""}`],
  ];
  {
    const tp = C.tripMinutes(h, "paris", "train"), cp = C.tripMinutes(h, "paris", "voiture");
    const I = INFOS[h.id] || {};
    if (tp || cp) faq.splice(1, 0, [`Comment aller à ${h.name} depuis Paris ?`, [
      tp ? `En train, comptez ${(I.train && I.train.paris && I.train.paris.sur) ? "" : "environ "}${C.fmtDuree(tp)} jusqu'à l'établissement (train jusqu'à ${I.gare ? I.gare.nom : "la gare la plus proche"}, puis taxi ou voiture).` : "",
      cp ? `En voiture, environ ${C.fmtDuree(cp)} hors embouteillages.` : "",
      I.acces ? `À noter : ${I.acces.charAt(0).toLowerCase()}${I.acces.slice(1)}.` : "",
    ].filter(Boolean).join(" ")]);
  }
  if (tags.includes("chien")) faq.push([`Les chiens sont-ils acceptés à ${h.name} ?`, "Oui, les chiens sont les bienvenus, généralement avec un supplément par nuit et parfois dans certaines chambres seulement : signalez-le au moment de la réservation."]);
  if (tags.includes("famille")) faq.push([`Peut-on y séjourner en famille ou entre amis ?`, `Oui : ${h.rooms.charAt(0).toLowerCase()}${h.rooms.slice(1)}. Vérifiez la capacité de chaque hébergement et l'âge minimum éventuel au moment de réserver.`]);
  if (tags.includes("train")) faq.push([`Peut-on y aller sans voiture ?`, `Oui, ${h.name} est accessible en train puis en transports en commun (métro, bus, navette ou train de montagne selon le cas). Vérifiez les horaires, surtout le soir.`]);
  if (tags.includes("spa-prive")) faq.push([`Y a-t-il un spa ou un jacuzzi privatif ?`, `Oui : ${h.amenities.filter((a) => /privati/i.test(a)).join(", ").toLowerCase() || "certains hébergements disposent d'un espace de bien-être privatif"}.`]);
  return faq;
}

/* « Sur place » : équipements vérifiés (data/hotels-infos.json) */
function equipBlock(h) {
  const eq = C.equipOf(h);
  if (!eq.length) return "";
  const I = INFOS[h.id] || {};
  return `<div class="equip reveal"><p class="eyebrow dark">Sur place</p><ul>${eq.map((k) => `<li><span aria-hidden="true">${C.EQUIP[k].icon}</span>${e(C.EQUIP[k].label)}${k === "restaurant" && I.restaurant ? ` <small>(${e(I.restaurant)})</small>` : ""}</li>`).join("")}</ul></div>`;
}

/* Équipements du texte de la fiche qui ne répètent pas une pastille « Sur place » */
function amenitiesLeft(h) {
  const eq = C.equipOf(h);
  if (!eq.length) return h.amenities;
  const same = new Set(eq.map((k) => C.EQUIP[k].label.toLowerCase()).concat(eq.includes("sauna") ? ["sauna", "hammam", "sauna et hammam"] : []));
  return h.amenities.filter((a) => !same.has(a.trim().toLowerCase()));
}

/* « Comment venir » : train (durée sourcée + dernier trajet) et voiture, depuis Paris, Lyon, Bordeaux */
function accessSection(h) {
  const I = INFOS[h.id];
  if (!I) return "";
  const r = ROUTES[h.id] || {};
  const g = I.gare && I.gare.nom;
  let filled = 0;
  const rows = Object.entries(C.FROM).map(([c, city]) => {
    const tr = (I.train || {})[c];
    const leg = typeof r.gare === "number" ? r.gare : null;
    let train = "—";
    if (tr && tr.min === 0) {
      train = h.city === city
        ? `<strong>Dans ${e(city)}</strong><small>métro, tram ou taxi</small>`
        : `<strong>${leg ? e(C.fmtDuree(leg)) : `Près de ${e(city)}`}</strong><small>${leg ? `de route depuis la gare de ${e(g)}` : `gare de ${e(g)}`}</small>`;
    } else if (tr && typeof tr.min === "number") {
      const total = tr.min + (leg || 0);
      const toParis = /^paris/i.test(g || "") && c !== "paris";
      const detail = toParis
        ? `${C.fmtDuree(tr.min)} de train jusqu'à Paris${/changement|correspondance/i.test(tr.via || "") ? ", changement de gare compris" : ""}${leg ? `, puis ${C.fmtDuree(leg)} en ville` : ""}`
        : `${C.fmtDuree(tr.min)} de train jusqu'à ${g}${leg ? `, puis ${C.fmtDuree(leg)} de route` : ""}`;
      train = `<strong>${tr.sur ? "" : "environ "}${C.fmtDuree(total)}</strong><small>${e(detail)}</small>`;
    } else if (g && !tr && (h.city === city || (c === "paris" && /^paris/i.test(g)) || (c === "lyon" && /^lyon/i.test(g)) || (c === "bordeaux" && /^bordeaux/i.test(g)))) {
      train = `<strong>Sur place</strong><small>${leg ? `${e(C.fmtDuree(leg))} depuis la gare de ${e(g)}` : `gare de ${e(g)}`}</small>`;
    }
    const car = !CORSE(I) && typeof r[c] === "number" ? (h.city === city ? `<strong>Dans ${e(city)}</strong>` : `<strong>${C.fmtDuree(r[c])}</strong>`) : "—";
    if (train !== "—" || car !== "—") filled++;
    return `<tr><th scope="row">Depuis ${city}</th><td>${train}</td><td>${car}</td></tr>`;
  }).join("");
  const sources = Object.values(I.train || {}).filter((t) => t.source).map((t) => t.source);
  if (!filled && !I.acces) return "";
  return `
        <section id="acces">
          <h2 class="reveal">Comment venir</h2>
          ${I.acces ? `<p class="access-special reveal"><strong>Accès</strong> ${e(I.acces)}</p>` : ""}
          ${filled ? `<div class="table-wrap reveal"><table class="access-table">
            <thead><tr><th></th><th scope="col">🚆 En train</th><th scope="col">🚗 En voiture</th></tr></thead>
            <tbody>${rows}</tbody>
          </table></div>
          <p class="small muted reveal">Train : trajet le plus rapide habituel${g ? ` jusqu'à la gare la plus pratique (${e(g)})` : ""}, correspondances comprises, puis la route jusqu'à l'établissement (taxi ou voiture). Voiture : itinéraire le plus rapide, hors embouteillages. Temps indicatifs${sources.length ? ", vérifiés sur les sites des transporteurs" : ""} : confirmez vos horaires sur SNCF Connect avant de partir.</p>` : ""}
        </section>`;
}

/* « Autour de l'hôtel : mes adresses » : fiches testées uniquement (champ around) */
function aroundSection(h) {
  if (!C.isTested(h) || !(h.around || []).length) return "";
  const ICON = { table: "🍽️", balade: "🥾", visite: "🏛️" };
  const KIND = { table: "Une table", balade: "Une balade", visite: "Une visite" };
  return `
        <section id="autour" class="around reveal">
          <p class="eyebrow dark">Le week-end clé en main</p>
          <h2>Autour de l'hôtel : mes adresses</h2>
          <ul class="around-list">${h.around.map((a) => `
            <li><span class="around-icon" aria-hidden="true">${ICON[a.kind] || "✦"}</span>
              <div><p class="around-kind">${e(KIND[a.kind] || "")}${a.where ? ` · ${e(a.where)}` : ""}</p>
              <h3>${a.url ? `<a href="${e(a.url)}" target="_blank" rel="noopener">${e(a.name)}</a>` : e(a.name)}</h3>
              <p>${e(a.text)}</p></div></li>`).join("")}
          </ul>
        </section>`;
}

/* Avis « Testé » : séjour réel de l'auteur, avec mention obligatoire
 * lorsque le séjour a été offert (loi du 9 juin 2023 sur l'influence). */
function reviewSection(h) {
  if (!C.isTested(h)) return "";
  const R = h.review, score = C.reviewScore(h);
  const scores = C.REVIEW_CRITERIA.filter(([k]) => typeof (R.scores || {})[k] === "number");
  const parts = (R.text || []).map((p) => Array.isArray(p)
    ? `<div class="review-part"><h3>${e(p[0])}</h3><p>${e(p[1])}</p></div>`
    : `<p class="body">${e(p)}</p>`);
  if (R.moment) parts.splice(Math.min(2, parts.length), 0, `<blockquote class="review-moment"><span>Le moment que je retiens</span>« ${e(R.moment)} »</blockquote>`);
  const reco = R.recommend ? [
    ["Pour qui", R.recommend.who], ["Quelle chambre", R.recommend.room], ["Quand venir", R.recommend.when],
    ["Combien de temps", R.recommend.length], ["À ne pas manquer", R.recommend.dontMiss],
  ].filter(([, v]) => v) : [];
  return `
        <section id="avis" class="review reveal">
          <div class="review-head">
            <div>
              <p class="eyebrow dark">✓ Testé · ${e(C.reviewDate(h))}</p>
              <h2>${e(R.title || "L'avis du pro")}</h2>
              ${R.stay ? `<p class="review-stay">Mon séjour : ${e(R.stay)} · ${R.invited ? "offert par l'établissement" : "réservé et payé par mes soins"}</p>` : ""}
            </div>
            ${score != null ? `<p class="review-score"><strong>${C.fmtScore(score)}</strong><span>/10</span></p>` : ""}
          </div>
          ${R.disclosure ? `<p class="review-transparency"><strong>Transparence</strong> ${e(R.disclosure.replace(/^Transparence\s*:\s*/i, ""))}${R.invited ? " Cette nuit m'a été offerte par l'hôtel." : ""}</p>` : ""}
          ${R.lead ? `<p class="review-lead">${e(R.lead)}</p>` : ""}
          <div class="review-body">${parts.join("")}</div>
          ${R.verdict || scores.length ? `
          <div class="review-verdict-box">
            <h3>Mon verdict</h3>
            ${R.verdict ? `<p class="review-verdict">« ${e(R.verdict)} »</p>` : ""}
            ${scores.length ? `<ul class="review-scores">${scores.map(([k, label]) => `<li><span>${e(label)}</span><i style="--v:${R.scores[k] * 10}%"></i><b>${C.fmtScore(R.scores[k])}</b></li>`).join("")}</ul>` : ""}
          </div>` : ""}
          ${(() => {
            const pros = R.pros || [], cons = R.cons || [], know = R.good2know || [];
            const col2 = cons.length ? ["J'ai moins aimé", cons] : know.length ? ["Bon à savoir", know] : null;
            if (!pros.length && !col2) return "";
            return `
          <div class="fit">
            ${pros.length ? `<div class="fit-col fit-yes"><h3>J'ai aimé</h3><ul>${pros.map((x) => `<li>${e(x)}</li>`).join("")}</ul></div>` : ""}
            ${col2 ? `<div class="fit-col fit-no"><h3>${col2[0]}</h3><ul>${col2[1].map((x) => `<li>${e(x)}</li>`).join("")}</ul></div>` : ""}
          </div>${cons.length && know.length ? `
          <p class="review-tip"><strong>Bon à savoir</strong> ${know.map(e).join(" · ")}</p>` : ""}`;
          })()}
          ${reco.length ? `
          <div class="review-reco">
            <h3>Ma recommandation</h3>
            <dl>${reco.map(([k, v]) => `<div><dt>${e(k)}</dt><dd>${e(v)}</dd></div>`).join("")}</dl>
          </div>` : ""}
          ${R.tip ? `<p class="review-tip"><strong>Le conseil du pro</strong> ${e(R.tip)}</p>` : ""}
          <p class="review-disclosure">${R.invited
            ? "Séjour offert par l'établissement. Comme toujours, l'avis est libre : l'établissement ne l'a ni relu ni validé."
            : "Séjour réservé et payé par mes soins, comme un client ordinaire."} <a href="../a-propos.html#charte">Ma charte</a></p>
        </section>`;
}

function hotelPage(h) {
  const T = TYPES[h.type], E = ENVS[h.env], b = budgetOf(h);
  const url = abs(`hotels/${h.id}.html`);
  const book = C.siteLink(h);
  const trk = `data-track="Site officiel" data-hotel="${e(h.id)}" data-book="${e(h.id)}"`;
  const title = `${h.name} (${h.city}) : nuit insolite, ${T.label.toLowerCase()} | ${CONFIG.siteName}`;
  const description = clip(`${h.tagline}. ${h.description[0]}`);
  const allGuides = C.guidesFor(h);
  const guides = allGuides.filter((g) => g.cat !== "ville");
  const cityGuides = allGuides.filter((g) => g.cat === "ville").sort((a, b) => C.distanceKm(a.city, h) - C.distanceKm(b.city, h));
  const tags = C.tagsOf(h);
  const faq = hotelFaq(h);
  const gift = GUIDES.find((g) => g.gift && C.guideHotels(g).length);
  const heroImgs = h.images.slice(0, 3);

  const ld = [
    {
      "@context": "https://schema.org",
      "@type": "Hotel",
      name: h.name,
      description: h.description.join(" "),
      url,
      image: h.images.map(absImg),
      address: { "@type": "PostalAddress", streetAddress: h.address, addressLocality: h.city, addressRegion: h.region, addressCountry: "FR" },
      geo: { "@type": "GeoCoordinates", latitude: h.lat, longitude: h.lng },
      priceRange: `${"€".repeat(h.budget)} (${b.range})`,
      amenityFeature: h.amenities.map((a) => ({ "@type": "LocationFeatureSpecification", name: a, value: true })),
      ...(tags.includes("chien") ? { petsAllowed: true } : {}),
      ...(C.isTested(h) && C.reviewScore(h) != null ? {
        review: {
          "@type": "Review",
          author: { "@type": "Person", name: CONFIG.author.name, url: abs("a-propos.html") },
          datePublished: h.review.published || `${h.review.date}-01`.slice(0, 10),
          reviewRating: { "@type": "Rating", ratingValue: C.reviewScore(h), bestRating: 10, worstRating: 0 },
          ...(h.review.verdict || h.review.lead ? { name: h.review.title || undefined, reviewBody: [h.review.lead, h.review.verdict].filter(Boolean).join(" ") } : {}),
        },
      } : {}),
    },
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      mainEntity: faq.map(([q, a]) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: a } })),
    },
    breadcrumbLd([["Accueil", `${SITE}/`], [E.label, abs(`index.html?env=${h.env}`)], [h.name, url]]),
  ];


  return `${head({ title, description, canonical: url, image: absImg(h.images[0]), type: "place", ld, leaflet: true })}
<body class="detail" data-hotel="${e(h.id)}">
  <a class="skip" href="${C.isTested(h) ? "#avis" : "#experience"}">Aller au contenu</a>
  <header id="site-header" class="site-header on-dark">${C.header()}</header>

  <main id="hotel">
    <section class="d-hero">
      <div class="d-hero-media">
        ${heroImgs.map((src, i) => `<img class="d-hero-bg${i ? "" : " on"}" src="${img(src)}" alt="${i ? "" : e(h.name)}"${i ? ` loading="lazy" aria-hidden="true"` : ` fetchpriority="high"`}>`).join("\n        ")}
      </div>
      <div class="d-hero-veil"></div>
      <div class="container d-hero-inner">
        <nav class="crumbs" aria-label="Fil d'Ariane">
          <a href="../index.html">Accueil</a> ›
          <a href="../index.html?env=${h.env}#explorer">${e(E.label)}</a> ›
          <a href="../index.html?type=${h.type}#explorer">${e(T.label)}</a>
        </nav>
        <p class="card-type light">${T.icon} ${e(T.label)} · ${e(E.label)}</p>
        <h1>${e(h.name)}</h1>
        <p class="d-tagline">${e(h.tagline)}</p>
        ${C.isCoupDeCoeur(h) ? `<a class="d-tested is-heart" href="../guides/coups-de-coeur-de-jules.html">♥ Coup de cœur du moment</a>` : ""}
        ${C.isTested(h) ? `<a class="d-tested" href="#avis">✓ Testé par ${e(CONFIG.author.name)}${C.reviewScore(h) != null ? ` · <strong>${C.fmtScore(C.reviewScore(h))}/10</strong>` : ""}</a>` : ""}
        <div class="d-meta">
          <span>📍 ${e(h.city)}, ${e(h.region)}</span>
          <span class="dist-chip" data-dist hidden></span>
          <span class="d-budget">${budgetHtml(h)} <small>${e(b.range)}</small></span>
        </div>
        ${tags.length ? `<ul class="d-tags" aria-label="Envies">${tags.map((t) => `<li>${C.data().TAGS[t].icon} ${e(C.data().TAGS[t].label)}</li>`).join("")}</ul>` : ""}
        <div class="d-actions">
          <a class="btn btn-primary" href="${e(book)}" target="_blank" rel="noopener" ${trk}>Réserver en direct</a>
          <button type="button" class="btn btn-glass" data-open-gallery>▦ ${h.images.length} photos</button>
          ${C.favButton(h, "fav-lg fav-glass")}
          <button type="button" class="btn-round" data-compare="${e(h.id)}" aria-pressed="false" aria-label="Ajouter ${e(h.name)} au comparateur" title="Comparer">⇄</button>
          <button type="button" class="btn-round" id="share" aria-label="Partager cette page">↗</button>
        </div>
      </div>
    </section>

    <nav class="d-tabs" id="d-tabs" aria-label="Sections de la page">
      <div class="container d-tabs-inner">
        ${C.isTested(h) ? `<a href="#avis" class="on">L'avis du pro</a>` : ""}
        <a href="#experience"${C.isTested(h) ? "" : ` class="on"`}>L'expérience</a>
        <a href="#photos">Photos</a>
        <a href="#pour-qui">Pour qui ?</a>
        <a href="#infos">Infos pratiques</a>
        <a href="#questions">Questions</a>
        <a href="#localisation">Localisation</a>
        <a class="d-tabs-book btn btn-primary" href="${e(book)}" target="_blank" rel="noopener" ${trk}>${h.isClosed ? "Site officiel" : "Réserver en direct"}</a>
      </div>
    </nav>

    <div class="container detail-layout">
      <article class="detail-content">
        ${h.isClosed ? `<p class="closed-banner"><strong>${e(h.closed.label || "Temporairement fermé")}</strong> ${e(h.closed.note || "")}</p>` : ""}
        ${newsSection(h)}
        ${reviewSection(h)}
        ${aroundSection(h)}
        <section id="experience">
          ${C.isTested(h) ? "" : `<p class="scout-note reveal"><strong>Repérage</strong> Je n'y ai pas encore séjourné : fiche rédigée à partir des informations de l'établissement.</p>`}
          <p class="eyebrow dark reveal">Pourquoi je l'ai repéré</p>
          <ul class="highlights">
            ${h.highlights.map((x, i) => `<li class="reveal"><span>${["✦", "☾", "❋", "◈"][i % 4]}</span>${e(x)}</li>`).join("\n            ")}
          </ul>
          <h2 class="reveal">L'expérience</h2>
          ${h.description.map((p, i) => `<p class="${i ? "body" : "lead dropcap"} reveal">${e(p)}</p>`).join("\n          ")}
        </section>

        <section id="photos">
          <h2 class="reveal">En images</h2>
          ${h.photoCredit ? `<p class="photo-credit reveal">${/établissement/.test(h.photoCredit) ? "Photos" : "Photos prises pendant mon séjour"} · © ${e(h.photoCredit)}</p>` : ""}
          <div class="mosaic">
            ${h.images.map((src, i) => `<button type="button" class="m-item reveal" data-i="${i}" aria-label="Agrandir la photo ${i + 1}"><img src="${img(src, i % 3 === 0 ? 1800 : 900)}" alt="${e(h.name)}, photo ${i + 1}" loading="lazy" decoding="async"></button>`).join("\n            ")}
          </div>
        </section>

        ${h.forYou ? `
        <section id="pour-qui">
          <h2 class="reveal">Pour qui ?</h2>
          <div class="fit reveal">
            <div class="fit-col fit-yes">
              <h3>C'est pour vous si…</h3>
              <ul>${h.forYou.map((x) => `<li>${e(x)}</li>`).join("")}</ul>
            </div>
            <div class="fit-col fit-no">
              <h3>Moins pour vous si…</h3>
              <ul>${(h.notForYou || []).map((x) => `<li>${e(x)}</li>`).join("")}</ul>
            </div>
          </div>
        </section>` : ""}

        <section id="infos">
          <h2 class="reveal">Infos pratiques</h2>
          ${equipBlock(h)}
          ${amenitiesLeft(h).length ? `<ul class="amenities reveal">${amenitiesLeft(h).map((a) => `<li>${e(a)}</li>`).join("")}</ul>` : ""}
          <dl class="facts reveal">
            <div><dt>Hébergement</dt><dd>${e(h.rooms)}</dd></div>
            <div><dt>Budget indicatif</dt><dd>${"€".repeat(h.budget)} · ${e(b.range)}</dd></div>
            ${h.season ? `<div><dt>Saison</dt><dd>${e(h.season)}</dd></div>` : ""}
            <div><dt>Adresse</dt><dd>${e(h.address)}</dd></div>
            <div class="fact-wide"><dt>Quand réserver</dt><dd>${e(C.bookingTip(h))}</dd></div>
          </dl>
        </section>

        ${accessSection(h)}

        <section id="questions">
          <h2 class="reveal">Questions fréquentes</h2>
          <div class="faq reveal">
            ${faq.map(([q, a], i) => `<details${i ? "" : " open"}><summary>${e(q)}</summary><p>${e(a)}</p></details>`).join("\n            ")}
          </div>
        </section>

        <section id="localisation">
          <h2 class="reveal">Localisation</h2>
          <div id="mini-map" class="mini-map reveal" data-lat="${h.lat}" data-lng="${h.lng}"></div>
          <p class="small muted"><a href="https://www.google.com/maps/dir/?api=1&amp;destination=${h.lat},${h.lng}" target="_blank" rel="noopener">Itinéraire Google Maps →</a></p>
        </section>

        ${C.questionsBlock(`hotels/${h.id}`, h.name, "cette adresse")}
        ${C.shareBlock({ url, title: `${h.name} : ${h.tagline}`, image: absImg(h.images[0]) })}
        ${guides.length || cityGuides.length ? `
        <section class="in-guides reveal">
          <h2>Cette adresse figure dans mes guides</h2>
          <ul>${guides.map((g) => `<li><a href="${C.guideUrl(g)}">${e(C.guideTitle(g))} →</a></li>`).join("")}</ul>
          ${cityGuides.length ? `<p class="in-cities">Idéal pour un week-end depuis ${cityGuides.map((g) => `<a href="${C.guideUrl(g)}">${e(g.city.name)}</a> <span>(${Math.max(5, Math.round(C.distanceKm(g.city, h) / 5) * 5)} km)</span>`).join(", ")}.</p>` : ""}
        </section>` : ""}

        <div class="nl-inline reveal">
          <h3>${e(CONFIG.newsletter.title)}</h3>
          <p class="muted">${e(CONFIG.newsletter.pitch)}</p>
          ${C.newsletterForm(`fiche-${h.id}`)}
        </div>
      </article>

      <aside class="book-card" id="reserver" aria-label="Réservation">
        <p class="book-price">${budgetHtml(h)} <span>${e(b.range)}</span></p>
        ${h.isClosed
          ? `<p class="book-closed">${e(h.closed.label || "Temporairement fermé")}</p>
        <a class="btn btn-ghost btn-block" href="${e(book)}" target="_blank" rel="noopener" ${trk}>Suivre la réouverture</a>`
          : `<a class="btn btn-primary btn-block" href="${e(book)}" target="_blank" rel="noopener" ${trk}>Réserver en direct</a>`}
        <p class="book-direct">Sur le site officiel de l'établissement : tarifs, disponibilités et conditions à jour.</p>
        ${(VEILLE[h.id] || {}).checked ? `<p class="book-checked">✓ Informations vérifiées le ${e(frDate(VEILLE[h.id].checked))}</p>` : ""}
        <p class="book-tip"><strong>Conseil</strong> ${e(C.bookingTip(h))}</p>
        <ul class="book-perks">
          <li>✓ Réservation directe, sans intermédiaire</li>
          <li>✓ Aucune commission : mes conseils sont libres</li>
          <li>✓ Une question ? L'établissement vous répond lui-même</li>
        </ul>
        ${h.isClosed ? "" : h.giftUrl
          ? `<a class="book-gift" href="${e(h.giftUrl)}" target="_blank" rel="noopener" data-track="Cartes cadeaux" data-hotel="${e(h.id)}">🎁 Envie d'offrir cette nuit ? <span>Les cartes cadeaux de l'établissement →</span></a>`
          : gift ? `<a class="book-gift" href="${C.guideUrl(gift)}">🎁 Envie d'offrir cette nuit ? <span>Mes idées cadeaux →</span></a>` : ""}
      </aside>
    </div>

    <section class="section section-dark similar">
      <div class="container section-head row">
        <div><p class="eyebrow">Continuer le voyage</p><h2>Vous aimerez aussi</h2></div>
        <div class="rail-nav">
          <button type="button" class="rail-btn" data-rail="similar-rail" data-dir="-1" aria-label="Précédent">←</button>
          <button type="button" class="rail-btn" data-rail="similar-rail" data-dir="1" aria-label="Suivant">→</button>
        </div>
      </div>
      <div class="rail rail-cards" id="similar-rail">${similarTo(h).map((x) => C.card(x, { reveal: false })).join("")}</div>
    </section>

    <div class="mobile-book">
      <span>${budgetHtml(h)}<small>${e(b.short || "")}</small></span>
      <a class="btn btn-ghost" href="#reserver" data-scroll-book>Infos</a>
      <a class="btn btn-primary" href="${e(book)}" target="_blank" rel="noopener" ${trk}>Réserver en direct</a>
    </div>
  </main>

  <div class="lightbox" id="lightbox" hidden role="dialog" aria-modal="true" aria-label="Photos de ${e(h.name)}">
    <button class="lb-close" type="button" aria-label="Fermer">×</button>
    <button class="lb-prev" type="button" aria-label="Photo précédente">‹</button>
    <img alt="">
    <button class="lb-next" type="button" aria-label="Photo suivante">›</button>
    <p class="lb-count"></p>
  </div>

  <footer id="site-footer" class="site-footer">${C.footer()}</footer>

  <script src="../vendor/leaflet/leaflet.js"></script>${SCRIPTS(`
  <script src="../js/hotel.js"></script>`)}
</body>
</html>
`;
}

/* ============================================================
   GUIDES
   ============================================================ */
function guidePage(g) {
  const list = C.guideHotels(g);
  const n = list.length;
  const title = C.guideTitle(g, n);
  const url = abs(`guides/${g.slug}.html`);
  const cover = list.find((h) => h.id === g.cover) || list[0];
  const others = GUIDES.filter((x) => x !== g && x.cat !== "ville" && C.guideHotels(x).length);
  const cities = GUIDES.filter((x) => x !== g && x.cat === "ville" && C.guideHotels(x).length);
  const ld = [
    {
      "@context": "https://schema.org",
      "@type": "ItemList",
      name: title,
      description: g.description,
      numberOfItems: n,
      itemListElement: list.map((h, i) => ({ "@type": "ListItem", position: i + 1, name: h.name, url: abs(`hotels/${h.id}.html`) })),
    },
    breadcrumbLd([["Accueil", `${SITE}/`], ["Guides", abs("guides/index.html")], [title, url]]),
  ];
  if (g.faq && g.faq.length) ld.push({
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: g.faq.map(([q, a]) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: a } })),
  });

  const items = list.map((h, i) => {
    const T = TYPES[h.type];
    const book = C.siteLink(h);
    return `
      <article class="g-item reveal" id="${e(h.id)}">
        <div class="g-media">
          <a class="g-photo" href="${C.hotelUrl(h)}"><img src="${img(h.images[0])}" alt="${e(h.name)}" loading="${i < 2 ? "eager" : "lazy"}" decoding="async"></a>
          ${h.images[1] ? `<a class="g-photo g-photo-sm" href="${C.hotelUrl(h)}" tabindex="-1" aria-hidden="true"><img src="${img(h.images[1], 900)}" alt="" loading="lazy" decoding="async"></a>` : ""}
          ${C.favButton(h)}
        </div>
        <div class="g-body">
          <p class="g-num">${String(i + 1).padStart(2, "0")}</p>
          <p class="card-type">${T.icon} ${e(T.label)} · ${e(ENVS[h.env].label)} ${C.isTested(h) ? `<a class="g-status g-tested" href="${C.hotelUrl(h)}#avis">✓ Testé${C.reviewScore(h) != null ? ` · ${C.fmtScore(C.reviewScore(h))}/10` : ""}</a>` : `<span class="g-status">Repérage</span>`}</p>
          <h2><a href="${C.hotelUrl(h)}">${e(h.name)}</a></h2>
          <p class="g-place">📍 ${e(h.city)}, ${e(h.department)} · ${budgetHtml(h)}${g.note ? ` · <span class="g-note">${e(g.note(h))}</span>` : ""}</p>
          <p class="g-tagline">${e(h.tagline)}</p>
          <p>${e(h.description[0])}</p>
          <ul class="g-hl">${h.highlights.map((x) => `<li>${e(x)}</li>`).join("")}</ul>
          <div class="g-cta">
            <a class="btn btn-ghost" href="${C.hotelUrl(h)}">Voir la fiche</a>
            <a class="btn btn-primary" href="${e(book)}" target="_blank" rel="noopener" data-track="Site officiel" data-hotel="${e(h.id)}" data-book="${e(h.id)}">Réserver en direct</a>
          </div>
        </div>
      </article>`;
  }).join("");

  return `${head({ title: `${title} | ${CONFIG.siteName}`, description: g.description, canonical: url, image: cover ? absImg(cover.images[0]) : "", type: "article", ld })}
<body class="guide">
  <a class="skip" href="#liste">Aller au contenu</a>
  <header id="site-header" class="site-header on-dark">${C.header()}</header>
  <main>
    <section class="g-hero">
      ${cover ? `<img class="g-hero-bg" src="${img(cover.images[0])}" alt="" fetchpriority="high">` : ""}
      <div class="d-hero-veil"></div>
      <div class="container g-hero-inner">
        <nav class="crumbs" aria-label="Fil d'Ariane"><a href="../index.html">Accueil</a> › <a href="index.html">Guides</a></nav>
        <p class="eyebrow">${e(g.kicker)} · ${n} adresse${n > 1 ? "s" : ""}</p>
        <h1>${e(title)}</h1>
      </div>
    </section>

    <div class="container g-layout">
      <div class="g-intro">
        ${g.intro.map((p, i) => `<p class="${i ? "body" : "lead dropcap"}">${e(p)}</p>`).join("\n        ")}
        ${g.slug === "coups-de-coeur-de-jules" ? `<p class="g-account">♡ Touchez le cœur d'une adresse pour la garder dans vos favoris. Avec un <a href="../compte.html">compte gratuit</a>, vous les retrouvez sur tous vos appareils.</p>` : ""}
      </div>
      <nav class="g-toc" aria-label="Sommaire">
        <p class="eyebrow dark">Au sommaire</p>
        <ol>${list.map((h) => `<li><a href="#${e(h.id)}">${e(h.name)}</a> <span>${e(h.city)}</span></li>`).join("")}</ol>
      </nav>
    </div>


    <section class="container g-list" id="liste">${items}
    </section>
${g.gift ? giftBlock() : ""}

    ${g.faq && g.faq.length ? `
    <section class="container g-faq reveal">
      <h2>Questions fréquentes</h2>
      <div class="faq">${g.faq.map(([q, a], i) => `<details${i ? "" : " open"}><summary>${e(q)}</summary><p>${e(a)}</p></details>`).join("")}</div>
    </section>` : ""}

    <section class="container g-tips reveal">
      <h2>Mes conseils</h2>
      <ul>${g.tips.map((t) => `<li>${e(t)}</li>`).join("")}</ul>
      ${C.shareBlock({ url, title, image: cover ? absImg(cover.images[0]) : "", heading: "Partager ce guide" })}
      <p class="small muted">Les informations de ce guide sont données à titre indicatif : vérifiez les tarifs, les dates d'ouverture et les conditions directement auprès des établissements.</p>
    </section>

    <div class="container g-ask">
      ${C.questionsBlock(`guides/${g.slug}`, title, "ce guide ou l'une de ces adresses")}
    </div>

    ${others.length ? `
    <section class="section section-tint">
      <div class="container">
        <div class="section-head"><p class="eyebrow dark">Continuer la lecture</p><h2>Mes autres guides</h2></div>
        <div class="guide-grid">${others.slice(0, 6).map(C.guideCard).join("")}</div>
        ${cities.length ? `<p class="city-links"><strong>Nuits insolites près de :</strong> ${cities.map((x) => `<a href="${C.guideUrl(x)}">${e(x.city.name)}</a>`).join(" · ")}</p>` : ""}
      </div>
    </section>` : ""}
  </main>
  <footer id="site-footer" class="site-footer">${C.footer()}</footer>${SCRIPTS()}
</body>
</html>
`;
}

/* Bloc « comment offrir » du guide cadeau */
function giftBlock() {
  return `
    <section class="container g-gift reveal">
      <div>
        <p class="eyebrow dark">Trois façons d'offrir</p>
        <h2>Comment offrir une nuit insolite</h2>
      </div>
      <ol class="gift-ways">
        <li><strong>Réserver des dates</strong><span>Vous connaissez ses disponibilités ? Réservez directement l'hébergement à votre nom : c'est le plus simple et le plus fort.</span></li>
        <li><strong>Un bon cadeau de l'établissement</strong><span>Beaucoup de lieux insolites vendent des bons cadeaux, parfois sur leur site : demandez-leur directement.</span></li>
        <li><strong>Un coffret à choisir</strong><span>Pour laisser le choix du lieu et des dates, optez pour un coffret « séjour insolite ».</span></li>
      </ol>
    </section>`;
}

function guidesIndexPage() {
  const visible = GUIDES.filter((g) => C.guideHotels(g).length);
  const url = abs("guides/index.html");
  const cover = HOTELS.find((h) => h.hero === 1) || HOTELS[0];
  const title = `Guides des hôtels insolites en France | ${CONFIG.siteName}`;
  const description = "Cabanes perchées, hôtels troglodytes, nuits en amoureux, week-ends près de Paris, bord de mer, montagne : tous mes guides des hébergements insolites en France.";
  const ld = [
    {
      "@context": "https://schema.org",
      "@type": "ItemList",
      name: "Guides des hôtels insolites en France",
      itemListElement: visible.map((g, i) => ({ "@type": "ListItem", position: i + 1, name: C.guideTitle(g), url: abs(`guides/${g.slug}.html`) })),
    },
    breadcrumbLd([["Accueil", `${SITE}/`], ["Guides", url]]),
  ];
  return `${head({ title, description, canonical: url, image: absImg(cover.images[0]), ld })}
<body class="guide">
  <header id="site-header" class="site-header on-dark">${C.header()}</header>
  <main>
    <section class="g-hero g-hero-sm">
      <img class="g-hero-bg" src="${img(cover.images[0])}" alt="" fetchpriority="high">
      <div class="d-hero-veil"></div>
      <div class="container g-hero-inner">
        <nav class="crumbs" aria-label="Fil d'Ariane"><a href="../index.html">Accueil</a></nav>
        <p class="eyebrow">${visible.length} guides</p>
        <h1>Mes guides des nuits insolites</h1>
        <p class="d-tagline">Des sélections thématiques pour trouver le lieu parfait, selon l'envie, la saison ou la région.</p>
      </div>
    </section>
    <section class="section container guides-index">
      <p class="lead guides-lead">Hôtels insolites, cabanes perchées, bulles, phares, châteaux ou refuges d'altitude : mes guides rassemblent les adresses les plus extraordinaires de France par envie, par type de lieu et par région, avec des conseils pour bien choisir et bien réserver.</p>
      ${[["envie", "Par envie et par occasion"], ["lieu", "Par type de lieu"], ["region", "Par région"], ["trajet", "Selon votre temps de trajet"], ["ville", "Près de chez vous"]].map(([k, label]) => {
        const list = visible.filter((g) => (g.cat || "envie") === k);
        return list.length ? `
      <h2 class="guides-cat">${label}</h2>
      <div class="guide-grid">${list.map(C.guideCard).join("")}</div>` : "";
      }).join("")}
    </section>
  </main>
  <footer id="site-footer" class="site-footer">${C.footer()}</footer>${SCRIPTS()}
</body>
</html>
`;
}

/* ============================================================
   ACCUEIL : blocs statiques (bons pour le référencement)
   ============================================================ */
function homeGuides() {
  C.setRoot("");
  const html = GUIDES.filter((g) => C.guideHotels(g).length).slice(0, 6).map(C.guideCard).join("");
  C.setRoot("../");
  return html;
}
function homeDirectory() {
  C.setRoot("");
  const regions = [...new Set(HOTELS.map((h) => h.region))].sort((a, b) => a.localeCompare(b, "fr"));
  const html = regions.map((r) => {
    const list = HOTELS.filter((h) => h.region === r).sort((a, b) => a.name.localeCompare(b.name, "fr"));
    return `
        <div class="dir-col">
          <h3>${e(r)} <span>${list.length}</span></h3>
          <ul>${list.map((h) => `<li><a href="${C.hotelUrl(h)}">${e(h.name)}</a> <small>${e(h.city)} · ${e(TYPES[h.type].label)}</small></li>`).join("")}</ul>
        </div>`;
  }).join("");
  C.setRoot("../");
  return html;
}
/* Accueil : texte « à savoir » et questions fréquentes (mêmes textes pour la
 * page et pour les données structurées FAQPage lues par Google). */
function homeFaqData() {
  const n = HOTELS.length;
  const small = HOTELS.filter((h) => h.budget === 1).length;
  const regions = new Set(HOTELS.map((h) => h.region)).size;
  const g = (slug) => GUIDES.find((x) => x.slug === slug);
  const link = (slug, label) => (g(slug) && C.guideHotels(g(slug)).length ? `<a href="guides/${slug}.html">${e(label)}</a>` : e(label));
  return [
    {
      q: "Qu'est-ce qu'un hôtel insolite ?",
      a: `Un hôtel insolite, ou hébergement hors du commun, est un lieu où l'on dort d'une façon qu'on n'oublie pas : dans une cabane perchée, une bulle transparente sous les étoiles, un phare, un château, une chambre creusée dans la roche, un igloo, un refuge d'altitude ou un bateau. Ma sélection réunit ${n} de ces lieux extraordinaires, dans ${regions} régions de France.`,
      html: `Un hôtel insolite, ou hébergement hors du commun, est un lieu où l'on dort d'une façon qu'on n'oublie pas : dans une ${link("cabanes-perchees", "cabane perchée")}, une ${link("nuit-sous-les-etoiles", "bulle transparente sous les étoiles")}, un phare, un ${link("dormir-dans-un-chateau", "château")}, une ${link("hotels-troglodytes", "chambre creusée dans la roche")}, un igloo, un ${link("dormir-en-altitude", "refuge d'altitude")} ou un bateau. Ma sélection réunit ${n} de ces lieux extraordinaires, dans ${regions} régions de France.`,
    },
    {
      q: "Combien coûte une nuit insolite en France ?",
      a: `Tous les budgets existent : ${small} de mes adresses coûtent moins de 150 € la nuit pour deux (cabanes sur l'eau, wagon-lit de 1926, chambres troglodytes), tandis que les lieux d'exception dépassent 450 €. Chaque fiche indique une fourchette de prix ; le tarif exact est donné sur le site de l'établissement.`,
      html: `Tous les budgets existent : ${small} de mes adresses coûtent moins de 150 € la nuit pour deux (cabanes sur l'eau, wagon-lit de 1926, chambres troglodytes), tandis que les lieux d'exception dépassent 450 €. Chaque fiche indique une fourchette de prix ; le tarif exact est donné sur le site de l'établissement. Voir aussi mon guide des ${link("nuits-insolites-petit-budget", "nuits insolites à petit budget")}.`,
    },
    {
      q: "Où dormir dans un lieu insolite près de chez moi ?",
      a: "Indiquez votre adresse dans « Près de chez moi » : tous les lieux sont triés par distance, avec un filtre de rayon. La carte interactive montre aussi l'ensemble de la sélection, de la Bretagne à la Corse.",
      html: `Indiquez votre adresse dans <a href="#explorer">« Près de chez moi »</a> : tous les lieux sont triés par distance, avec un filtre de rayon. La <a href="carte.html">carte interactive</a> montre aussi l'ensemble de la sélection, de la Bretagne à la Corse. Depuis Paris, voir mes ${link("week-end-insolite-pres-de-paris", "week-ends insolites près de Paris")}.`,
    },
    {
      q: "Quels sont les hôtels les plus extraordinaires de France ?",
      a: "Parmi les plus étonnants : l'observatoire du Pic du Midi, où l'on dort à 2 877 mètres, le Phare de Kerbel, dont on occupe le sommet, une voiture-lits de 1926 en gare de Guiscriff, les cabanes sur pilotis du lac de la Ramade qu'on rejoint en canoë, ou encore une île privée dans la baie de Morlaix.",
      html: `Parmi les plus étonnants : <a href="hotels/pic-du-midi.html">l'observatoire du Pic du Midi</a>, où l'on dort à 2 877 mètres, le <a href="hotels/phare-de-kerbel.html">Phare de Kerbel</a>, dont on occupe le sommet, une <a href="hotels/gare-de-guiscriff.html">voiture-lits de 1926</a> en gare de Guiscriff, les <a href="hotels/cabanes-lacustra.html">cabanes sur pilotis</a> qu'on rejoint en canoë, ou encore une <a href="hotels/ile-louet.html">île privée dans la baie de Morlaix</a>. Pas d'idée précise ? Faites mon <a href="quiz.html">quiz en 5 questions</a>.`,
    },
    {
      q: "Quand réserver une nuit insolite ?",
      a: "Le plus tôt possible pour les week-ends, les ponts et les vacances scolaires : beaucoup de lieux insolites ne comptent que quelques cabanes ou chambres. En semaine, le choix est plus large et les prix souvent plus doux.",
      html: "Le plus tôt possible pour les week-ends, les ponts et les vacances scolaires : beaucoup de lieux insolites ne comptent que quelques cabanes ou chambres. En semaine, le choix est plus large et les prix souvent plus doux.",
    },
    {
      q: "Nuits Singulières touche-t-il une commission ?",
      a: "Non. Nuits Singulières est un site de conseil indépendant, tenu par un professionnel de l'hôtellerie : aucun établissement ne paie pour y figurer, et je ne touche rien sur les réservations. Les boutons « Réserver en direct » mènent au site officiel de chaque lieu.",
      html: `Non. Nuits Singulières est un site de conseil indépendant, tenu par un professionnel de l'hôtellerie : aucun établissement ne paie pour y figurer, et je ne touche rien sur les réservations. Les boutons « Réserver en direct » mènent au site officiel de chaque lieu (<a href="a-propos.html">ma charte</a>).`,
    },
  ];
}
function homeFaq() {
  const faq = homeFaqData();
  return `
    <div class="home-seo-grid">
      <div class="home-seo-intro reveal">
        <p class="eyebrow dark">À savoir</p>
        <h2>Hôtels insolites en France : mes conseils pour une nuit hors du commun</h2>
        <p class="lead">Dormir dans un lieu extraordinaire, c'est offrir à un week-end la saveur d'un vrai voyage. Cabane dans les arbres, bulle face aux étoiles, phare battu par les vents ou château au-dessus d'une rivière : chaque adresse de Nuits Singulières a été choisie pour ce qu'elle a d'unique, du petit budget au grand luxe.</p>
        <p>Ville, campagne, mer ou montagne : explorez par <a href="#destinations">ambiance</a>, par <a href="#experiences">expérience</a> ou par <a href="guides/index.html">guide thématique</a>, comparez jusqu'à trois lieux et réservez au meilleur prix, sans frais supplémentaires.</p>
      </div>
      <div class="faq home-faq reveal">
        ${faq.map((f, i) => `<details${i ? "" : " open"}><summary>${e(f.q)}</summary><p>${f.html}</p></details>`).join("\n        ")}
      </div>
    </div>`;
}
function homeHead() {
  const cover = HOTELS.find((h) => h.hero === 1) || HOTELS[0];
  return `
  <link rel="canonical" href="${e(SITE)}/">
  <meta property="og:url" content="${e(SITE)}/">
  <meta property="og:image" content="${e(absImg(cover.images[0]))}">
  ${jsonLd({
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: CONFIG.siteName,
    url: `${SITE}/`,
    description: "Les hôtels les plus singuliers de France, choisis un à un, repérés et testés.",
    inLanguage: "fr-FR",
    potentialAction: { "@type": "SearchAction", target: `${SITE}/index.html?q={search_term_string}#explorer`, "query-input": "required name=search_term_string" },
  })}
  ${jsonLd({
    "@context": "https://schema.org",
    "@type": "Organization",
    name: CONFIG.siteName,
    url: `${SITE}/`,
    logo: `${SITE}/favicon-512.png`,
    founder: { "@type": "Person", name: CONFIG.author.name, url: `${SITE}/a-propos.html` },
  })}
  ${jsonLd({
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: homeFaqData().map((f) => ({ "@type": "Question", name: f.q, acceptedAnswer: { "@type": "Answer", text: f.a } })),
  })}
  `;
}
function inject(file, marker, html) {
  const p = path.join(ROOT, file);
  const src = fs.readFileSync(p, "utf8");
  const re = new RegExp(`(<!-- build:${marker}:start -->)[\\s\\S]*?(<!-- build:${marker}:end -->)`);
  if (!re.test(src)) throw new Error(`Marqueur build:${marker} introuvable dans ${file}`);
  return write(file, src.replace(re, (m, a, b) => `${a}${html.replace(/\s+$/, "")}\n  ${b}`));
}

/* ============================================================
   SITEMAP & ROBOTS
   ============================================================ */
// Date de dernière modification réelle de chaque page (pour Google) :
// on garde l'empreinte de chaque fichier dans data/lastmod.json et la date
// ne change que si le contenu de la page a vraiment changé.
const LASTMOD_FILE = path.join(ROOT, "data", "lastmod.json");
function lastmods(files) {
  const prev = fs.existsSync(LASTMOD_FILE) ? JSON.parse(fs.readFileSync(LASTMOD_FILE, "utf8")) : {};
  const today = new Date().toISOString().slice(0, 10);
  const next = {};
  for (const f of files) {
    const hash = crypto.createHash("sha1").update(fs.readFileSync(path.join(ROOT, f))).digest("hex").slice(0, 12);
    next[f] = prev[f] && prev[f].hash === hash ? prev[f] : { hash, date: today };
  }
  write("data/lastmod.json", JSON.stringify(next, null, 1) + "\n");
  return next;
}

function sitemap() {
  const guides = GUIDES.filter((g) => C.guideHotels(g).length);
  const pages = [
    ["index.html", `${SITE}/`, []],
    ["carte.html", abs("carte.html"), []],
    ["quiz.html", abs("quiz.html"), []],
    ["professionnels.html", abs("professionnels.html"), []],
    ["a-propos.html", abs("a-propos.html"), []],
    ["guides/index.html", abs("guides/index.html"), []],
    ...guides.map((g) => {
      const list = C.guideHotels(g);
      const cover = list.find((h) => h.id === g.cover) || list[0];
      return [`guides/${g.slug}.html`, abs(`guides/${g.slug}.html`), [[cover.images[0], C.guideTitle(g, list.length)]]];
    }),
    ...HOTELS.map((h) => [`hotels/${h.id}.html`, abs(`hotels/${h.id}.html`), h.images.slice(0, 6).map((src) => [src, `${h.name}, ${h.city}`])]),
  ];
  const mods = lastmods(pages.map(([f]) => f));
  const imageXml = (imgs) => imgs.map(([src]) => `\n    <image:image><image:loc>${e(absImg(src))}</image:loc></image:image>`).join("");
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
${pages.map(([f, u, imgs]) => `  <url><loc>${e(u)}</loc><lastmod>${mods[f].date}</lastmod>${imageXml(imgs)}${imgs.length ? "\n  " : ""}</url>`).join("\n")}
</urlset>
`;
}
const robots = () => `User-agent: *
Allow: /
Disallow: /studio.html
Disallow: /signature.html
Disallow: /compte.html
Disallow: /comparer.html
Disallow: /selection.html
Disallow: /_review/

Sitemap: ${SITE}/sitemap.xml
`;

/* ============================================================ */
function main() {
  C.setRoot("../");
  const changed = [];
  const note = (file, did) => { if (did) changed.push(file); };
  note("js/hotels.js (équipements et trajets)", writeInfosBlock());
  note("data/trajets-entree.json", writeRouteInput());

  // Nettoie les pages d'établissements qui n'existent plus
  const PAGES = HOTELS.concat(global.HOTELS_CLOSED || []); // fiches des lieux temporairement fermés incluses
  const wanted = new Set(PAGES.map((h) => `${h.id}.html`));
  const hotelsDir = path.join(ROOT, "hotels");
  if (fs.existsSync(hotelsDir)) {
    for (const f of fs.readdirSync(hotelsDir)) if (f.endsWith(".html") && !wanted.has(f)) { fs.unlinkSync(path.join(hotelsDir, f)); changed.push(`hotels/${f} (supprimé)`); }
  }
  for (const h of PAGES) note(`hotels/${h.id}.html`, write(`hotels/${h.id}.html`, hotelPage(h)));

  const wantedGuides = new Set(["index.html", ...GUIDES.filter((g) => C.guideHotels(g).length).map((g) => `${g.slug}.html`)]);
  const guidesDir = path.join(ROOT, "guides");
  if (fs.existsSync(guidesDir)) {
    for (const f of fs.readdirSync(guidesDir)) if (f.endsWith(".html") && !wantedGuides.has(f)) { fs.unlinkSync(path.join(guidesDir, f)); changed.push(`guides/${f} (supprimé)`); }
  }
  for (const g of GUIDES) if (C.guideHotels(g).length) note(`guides/${g.slug}.html`, write(`guides/${g.slug}.html`, guidePage(g)));
  note("guides/index.html", write("guides/index.html", guidesIndexPage()));

  note("index.html (en-tête)", inject("index.html", "head", homeHead()));
  note("index.html (guides)", inject("index.html", "guides", homeGuides()));
  note("index.html (annuaire)", inject("index.html", "directory", homeDirectory()));
  C.setRoot("");
  note("index.html (à savoir)", inject("index.html", "faq", homeFaq()));
  C.setRoot("../");
  note("sitemap.xml", write("sitemap.xml", sitemap()));
  note("robots.txt", write("robots.txt", robots()));

  console.log(`${HOTELS.length} fiches, ${wantedGuides.size - 1} guides. ${changed.length ? `Modifié : ${changed.length} fichier(s).` : "Rien à changer."}`);
  if (SITE.includes("exemple.fr")) console.log("⚠️  Pense à mettre ton vrai nom de domaine dans js/config.js (siteUrl) : il sert aux liens pour Google.");
}
main();
