#!/usr/bin/env node
/*
 * Génère les pages statiques du site (bien référencées sur Google) :
 *   hotels/<id>.html        une vraie page par établissement
 *   guides/<slug>.html      les guides thématiques
 *   guides/index.html       la liste des guides
 *   sitemap.xml, robots.txt le plan du site pour les moteurs de recherche
 *   index.html              (blocs « Guides » et « Toutes nos adresses »)
 *
 * Usage : node scripts/build.js      (aucune dépendance à installer)
 * Lancé automatiquement par la GitHub Action « Build » et par Netlify.
 */
"use strict";
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
global.window = global;
for (const f of ["js/config.js", "js/hotels.js", "js/guides.js"]) require(path.join(ROOT, f));
const C = require(path.join(ROOT, "js/core.js"));

const { CONFIG, HOTELS, ENVS, TYPES, GUIDES } = C.data();
const { escapeHtml: e, img, budgetHtml, budgetOf, partnerBadge, planRank, distanceKm } = C;
const SITE = CONFIG.siteUrl.replace(/\/$/, "");
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
  <meta name="theme-color" content="#0f1a17">
  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>✦</text></svg>">${FONTS}
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

function hotelPage(h) {
  const T = TYPES[h.type], E = ENVS[h.env], b = budgetOf(h);
  const url = abs(`hotels/${h.id}.html`);
  const book = C.bookingLink(h);
  const others = C.partnerLinks(h);
  const paid = planRank(h) > 0;
  const trk = `data-track="Réservation" data-hotel="${e(h.id)}" data-book="${e(h.id)}"`;
  const title = `${h.name} : ${T.label.toLowerCase()} à ${h.city} | ${CONFIG.siteName}`;
  const description = clip(`${h.tagline}. ${h.description[0]}`);
  const guides = C.guidesFor(h);

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
      priceRange: "€".repeat(h.budget),
      amenityFeature: h.amenities.map((a) => ({ "@type": "LocationFeatureSpecification", name: a, value: true })),
    },
    breadcrumbLd([["Accueil", `${SITE}/`], [E.label, abs(`index.html?env=${h.env}`)], [h.name, url]]),
  ];

  return `${head({ title, description, canonical: url, image: absImg(h.images[0]), type: "place", ld, leaflet: true })}
<body class="detail" data-hotel="${e(h.id)}">
  <a class="skip" href="#experience">Aller au contenu</a>
  <header id="site-header" class="site-header on-dark">${C.header()}</header>

  <main id="hotel">
    <section class="d-hero">
      <img class="d-hero-bg" src="${img(h.images[0])}" alt="${e(h.name)}" fetchpriority="high">
      <div class="d-hero-veil"></div>
      <div class="container d-hero-inner">
        <nav class="crumbs" aria-label="Fil d'Ariane">
          <a href="../index.html">Accueil</a> ›
          <a href="../index.html?env=${h.env}#explorer">${e(E.label)}</a> ›
          <a href="../index.html?type=${h.type}#explorer">${e(T.label)}</a>
        </nav>
        <p class="card-type light">${T.icon} ${e(T.label)} · ${e(E.label)} ${partnerBadge(h)}</p>
        <h1>${e(h.name)}</h1>
        <p class="d-tagline">${e(h.tagline)}</p>
        <div class="d-meta">
          <span>📍 ${e(h.city)}, ${e(h.region)}</span>
          <span class="dist-chip" data-dist hidden></span>
          <span class="d-budget">${budgetHtml(h)} <small>${e(b.range)}</small></span>
        </div>
        <div class="d-actions">
          <a class="btn btn-primary" href="${e(book)}" target="_blank" rel="sponsored noopener" ${trk}>Voir les disponibilités</a>
          <button type="button" class="btn btn-glass" data-open-gallery>▦ ${h.images.length} photos</button>
          ${C.favButton(h, "fav-lg fav-glass")}
          <button type="button" class="btn-round" id="share" aria-label="Partager cette page">↗</button>
        </div>
      </div>
    </section>

    <nav class="d-tabs" id="d-tabs" aria-label="Sections de la page">
      <div class="container d-tabs-inner">
        <a href="#experience" class="on">L'expérience</a>
        <a href="#photos">Photos</a>
        <a href="#infos">Infos pratiques</a>
        <a href="#localisation">Localisation</a>
        <a class="d-tabs-book btn btn-primary" href="${e(book)}" target="_blank" rel="sponsored noopener" ${trk}>Réserver</a>
      </div>
    </nav>

    <div class="container detail-layout">
      <article class="detail-content">
        <section id="experience">
          <ul class="highlights">
            ${h.highlights.map((x, i) => `<li class="reveal"><span>${["✦", "☾", "❋", "◈"][i % 4]}</span>${e(x)}</li>`).join("\n            ")}
          </ul>
          <h2 class="reveal">L'expérience</h2>
          ${h.description.map((p, i) => `<p class="${i ? "body" : "lead dropcap"} reveal">${e(p)}</p>`).join("\n          ")}
        </section>

        <section id="photos">
          <h2 class="reveal">En images</h2>
          <div class="mosaic">
            ${h.images.map((src, i) => `<button type="button" class="m-item reveal" data-i="${i}" aria-label="Agrandir la photo ${i + 1}"><img src="${img(src, i % 3 === 0 ? 1800 : 900)}" alt="${e(h.name)}, photo ${i + 1}" loading="lazy" decoding="async"></button>`).join("\n            ")}
          </div>
        </section>

        <section id="infos">
          <h2 class="reveal">Infos pratiques</h2>
          ${h.amenities.length ? `<ul class="amenities reveal">${h.amenities.map((a) => `<li>${e(a)}</li>`).join("")}</ul>` : ""}
          <dl class="facts reveal">
            <div><dt>Hébergement</dt><dd>${e(h.rooms)}</dd></div>
            <div><dt>Budget indicatif</dt><dd>${"€".repeat(h.budget)} · ${e(b.range)}</dd></div>
            ${h.season ? `<div><dt>Saison</dt><dd>${e(h.season)}</dd></div>` : ""}
            <div><dt>Adresse</dt><dd>${e(h.address)}</dd></div>
          </dl>
        </section>

        <section id="localisation">
          <h2 class="reveal">Localisation</h2>
          <div id="mini-map" class="mini-map reveal" data-lat="${h.lat}" data-lng="${h.lng}"></div>
          <p class="small muted"><a href="https://www.google.com/maps/dir/?api=1&amp;destination=${h.lat},${h.lng}" target="_blank" rel="noopener">Itinéraire Google Maps →</a></p>
        </section>

        ${guides.length ? `
        <section class="in-guides reveal">
          <h2>Cette adresse figure dans nos guides</h2>
          <ul>${guides.map((g) => `<li><a href="${C.guideUrl(g)}">${e(C.guideTitle(g))} →</a></li>`).join("")}</ul>
        </section>` : ""}

        <div class="nl-inline reveal">
          <h3>${e(CONFIG.newsletter.title)}</h3>
          <p class="muted">${e(CONFIG.newsletter.pitch)}</p>
          ${C.newsletterForm(`fiche-${h.id}`)}
        </div>
      </article>

      <aside class="book-card" aria-label="Réservation">
        <p class="book-price">${budgetHtml(h)} <span>${e(b.range)}</span></p>
        <p class="small muted">Budget indicatif pour 2 personnes. Vérifiez les disponibilités et le tarif exact selon vos dates.</p>
        ${paid && h.offer ? `<div class="offer"><strong>Offre spéciale</strong>${e(h.offer)}</div>` : ""}
        <a class="btn btn-primary btn-block" href="${e(book)}" target="_blank" rel="sponsored noopener" ${trk}>Voir les disponibilités sur Booking.com</a>
        ${others.map((o) => `<a class="btn btn-ghost btn-block" href="${e(o.href)}" target="_blank" rel="sponsored noopener" data-track="Partenaire" data-hotel="${e(h.id)}">Comparer sur ${e(o.name)}</a>`).join("")}
        ${paid && h.website ? `<a class="btn btn-ghost btn-block" href="${e(h.website)}" target="_blank" rel="noopener" data-track="Site officiel" data-hotel="${e(h.id)}">Réserver en direct sur le site de l'hôtel</a>` : ""}
        ${paid && h.phone ? `<a class="book-phone" href="tel:${e(h.phone.replace(/\s/g, ""))}" data-track="Téléphone" data-hotel="${e(h.id)}">☎ ${e(h.phone)}</a>` : ""}
        <ul class="book-perks">
          <li>✓ Réservation sécurisée chez notre partenaire</li>
          <li>✓ Aucun frais supplémentaire</li>
          <li>✓ Annulation selon les conditions de l'offre</li>
        </ul>
      </aside>
    </div>

    ${paid ? "" : `<div class="container"><p class="owner-note">Vous êtes le propriétaire de cet établissement ? <a href="../hoteliers.html?hotel=${encodeURIComponent(h.id)}">Mettez votre fiche en avant →</a></p></div>`}

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
      <span>${budgetHtml(h)}</span>
      <a class="btn btn-primary" href="${e(book)}" target="_blank" rel="sponsored noopener" ${trk}>Réserver</a>
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
  const others = GUIDES.filter((x) => x !== g && C.guideHotels(x).length);
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

  const items = list.map((h, i) => {
    const T = TYPES[h.type];
    const book = C.bookingLink(h);
    return `
      <article class="g-item reveal" id="${e(h.id)}">
        <div class="g-media">
          <a class="g-photo" href="${C.hotelUrl(h)}"><img src="${img(h.images[0])}" alt="${e(h.name)}" loading="${i < 2 ? "eager" : "lazy"}" decoding="async"></a>
          ${h.images[1] ? `<a class="g-photo g-photo-sm" href="${C.hotelUrl(h)}" tabindex="-1" aria-hidden="true"><img src="${img(h.images[1], 900)}" alt="" loading="lazy" decoding="async"></a>` : ""}
          ${C.favButton(h)}
        </div>
        <div class="g-body">
          <p class="g-num">${String(i + 1).padStart(2, "0")}</p>
          <p class="card-type">${T.icon} ${e(T.label)} · ${e(ENVS[h.env].label)} ${partnerBadge(h)}</p>
          <h2><a href="${C.hotelUrl(h)}">${e(h.name)}</a></h2>
          <p class="g-place">📍 ${e(h.city)}, ${e(h.department)} · ${budgetHtml(h)}${g.note ? ` · <span class="g-note">${e(g.note(h))}</span>` : ""}</p>
          <p class="g-tagline">${e(h.tagline)}</p>
          <p>${e(h.description[0])}</p>
          <ul class="g-hl">${h.highlights.map((x) => `<li>${e(x)}</li>`).join("")}</ul>
          <div class="g-cta">
            <a class="btn btn-ghost" href="${C.hotelUrl(h)}">Voir la fiche</a>
            <a class="btn btn-primary" href="${e(book)}" target="_blank" rel="sponsored noopener" data-track="Réservation" data-hotel="${e(h.id)}" data-book="${e(h.id)}">Voir les disponibilités</a>
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
      </div>
      <nav class="g-toc" aria-label="Sommaire">
        <p class="eyebrow dark">Au sommaire</p>
        <ol>${list.map((h) => `<li><a href="#${e(h.id)}">${e(h.name)}</a> <span>${e(h.city)}</span></li>`).join("")}</ol>
      </nav>
    </div>

    <section class="container g-list" id="liste">${items}
    </section>

    <section class="container g-tips reveal">
      <h2>Nos conseils</h2>
      <ul>${g.tips.map((t) => `<li>${e(t)}</li>`).join("")}</ul>
      <p class="small muted">Les informations de ce guide sont données à titre indicatif : vérifiez les tarifs, les dates d'ouverture et les conditions directement auprès des établissements ou sur le site de réservation.</p>
    </section>

    ${others.length ? `
    <section class="section section-tint">
      <div class="container">
        <div class="section-head"><p class="eyebrow dark">Continuer la lecture</p><h2>Nos autres guides</h2></div>
        <div class="guide-grid">${others.slice(0, 6).map(C.guideCard).join("")}</div>
      </div>
    </section>` : ""}
  </main>
  <footer id="site-footer" class="site-footer">${C.footer()}</footer>${SCRIPTS()}
</body>
</html>
`;
}

function guidesIndexPage() {
  const visible = GUIDES.filter((g) => C.guideHotels(g).length);
  const url = abs("guides/index.html");
  const cover = HOTELS.find((h) => h.hero === 1) || HOTELS[0];
  const title = `Guides des hôtels insolites en France | ${CONFIG.siteName}`;
  const description = "Cabanes perchées, hôtels troglodytes, nuits en amoureux, week-ends près de Paris, bord de mer, montagne : tous nos guides des hébergements insolites en France.";
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
        <h1>Nos guides des nuits insolites</h1>
        <p class="d-tagline">Des sélections thématiques pour trouver le lieu parfait, selon l'envie, la saison ou la région.</p>
      </div>
    </section>
    <section class="section container">
      <div class="guide-grid">${visible.map(C.guideCard).join("")}</div>
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
    description: CONFIG.tagline,
    inLanguage: "fr-FR",
    potentialAction: { "@type": "SearchAction", target: `${SITE}/index.html?q={search_term_string}#explorer`, "query-input": "required name=search_term_string" },
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
function sitemap() {
  const urls = [
    `${SITE}/`,
    abs("carte.html"),
    abs("guides/index.html"),
    ...GUIDES.filter((g) => C.guideHotels(g).length).map((g) => abs(`guides/${g.slug}.html`)),
    ...HOTELS.map((h) => abs(`hotels/${h.id}.html`)),
    abs("hoteliers.html"),
  ];
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((u) => `  <url><loc>${e(u)}</loc></url>`).join("\n")}
</urlset>
`;
}
const robots = () => `User-agent: *
Allow: /
Disallow: /studio.html
Disallow: /_review/

Sitemap: ${SITE}/sitemap.xml
`;

/* ============================================================ */
function main() {
  C.setRoot("../");
  const changed = [];
  const note = (file, did) => { if (did) changed.push(file); };

  // Nettoie les pages d'établissements qui n'existent plus
  const wanted = new Set(HOTELS.map((h) => `${h.id}.html`));
  const hotelsDir = path.join(ROOT, "hotels");
  if (fs.existsSync(hotelsDir)) {
    for (const f of fs.readdirSync(hotelsDir)) if (f.endsWith(".html") && !wanted.has(f)) { fs.unlinkSync(path.join(hotelsDir, f)); changed.push(`hotels/${f} (supprimé)`); }
  }
  for (const h of HOTELS) note(`hotels/${h.id}.html`, write(`hotels/${h.id}.html`, hotelPage(h)));

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
  note("sitemap.xml", write("sitemap.xml", sitemap()));
  note("robots.txt", write("robots.txt", robots()));

  console.log(`${HOTELS.length} fiches, ${wantedGuides.size - 1} guides. ${changed.length ? `Modifié : ${changed.length} fichier(s).` : "Rien à changer."}`);
  if (SITE.includes("exemple.fr")) console.log("⚠️  Pense à mettre ton vrai nom de domaine dans js/config.js (siteUrl) : il sert aux liens pour Google.");
}
main();
