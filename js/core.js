/*
 * Briques d'affichage communes, utilisées à la fois :
 *  - par le navigateur (accueil, cartes, en-tête…) ;
 *  - par le générateur de pages statiques (scripts/build.js) pour les fiches
 *    hôtels et les guides.
 * Ce fichier ne touche jamais au DOM : il ne fait que produire du HTML.
 */
(function (global, factory) {
  const api = factory(global);
  if (typeof module === "object" && module.exports) module.exports = api;
  else global.NSCore = api;
})(typeof window !== "undefined" ? window : globalThis, function (global) {
  const data = () => ({
    CONFIG: global.SITE_CONFIG,
    HOTELS: global.HOTELS || [],
    ENVS: global.ENVIRONMENTS,
    TYPES: global.TYPES,
    BUDGETS: global.BUDGETS,
    TAGS: global.TAGS || {},
    GUIDES: global.GUIDES || [],
  });

  /* ---------- Chemins ----------
   * Les pages situées dans un sous-dossier (hotels/, guides/) portent
   * <html data-root="../"> : tous les liens et images sont préfixés. */
  let forcedRoot = null;
  const setRoot = (r) => { forcedRoot = r; };
  const root = () => {
    if (forcedRoot !== null) return forcedRoot;
    if (typeof document !== "undefined") return document.documentElement.getAttribute("data-root") || "";
    return "";
  };
  const page = (p) => root() + p;
  const hotelUrl = (h) => `${root()}hotels/${h.id}.html`;
  const guideUrl = (g) => `${root()}guides/${g.slug}.html`;

  const escapeHtml = (s = "") =>
    String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  const formatPrice = (n) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR", maximumFractionDigits: 0 }).format(n);
  const formatDistance = (km) => (km < 10 ? `${km.toFixed(1).replace(".", ",")} km` : `${Math.round(km)} km`);

  // Distance à vol d'oiseau (formule de haversine)
  function distanceKm(a, b) {
    const R = 6371, rad = (d) => (d * Math.PI) / 180;
    const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
    const x = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(x));
  }

  /* ---------- Photos ----------
   * Deux tailles par photo : 1.jpg (grande) et 1-sm.jpg (vignette). */
  const FALLBACK = "data:image/svg+xml;utf8," + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#24392f"/><stop offset="1" stop-color="#c29a5b"/></linearGradient></defs><rect width="800" height="600" fill="url(#g)"/><text x="400" y="315" font-family="Georgia,serif" font-size="34" fill="#f4efe6" text-anchor="middle" opacity=".85">Nuits Singulières</text></svg>`
  );
  function img(url, w) {
    if (!url) return FALLBACK;
    if (/^(https?:|data:)/.test(url)) return url;
    const local = /^assets\/hotels\/.+\/\d+\.jpg$/.test(url);
    return root() + (local && w && w <= 900 ? url.replace(/\.jpg$/, "-sm.jpg") : url);
  }

  /* ---------- Fonds de carte (gratuits, sans clé) ----------
   * plan : OpenStreetMap · satellite : Esri World Imagery · nuit : Esri Dark Gray.
   * Renvoie un calque Leaflet (ou un groupe de calques pour « nuit »). */
  const OSM = '&copy; <a href="https://www.openstreetmap.org/copyright">contributeurs OpenStreetMap</a>';
  const ESRI = "https://server.arcgisonline.com/ArcGIS/rest/services";
  function baseLayer(style = "plan") {
    const L = global.L;
    if (style === "satellite") {
      return L.tileLayer(`${ESRI}/World_Imagery/MapServer/tile/{z}/{y}/{x}`, { attribution: "Imagerie &copy; Esri, Maxar, Earthstar Geographics", maxZoom: 18 });
    }
    if (style === "nuit") {
      return L.layerGroup([
        L.tileLayer(`${ESRI}/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}`, { attribution: `&copy; Esri, HERE, Garmin, ${OSM}`, maxZoom: 16 }),
        L.tileLayer(`${ESRI}/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}`, { maxZoom: 16 }),
      ]);
    }
    return L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", { attribution: OSM, maxZoom: 19, className: "tiles-plan" });
  }

  /* ---------- Budget ---------- */
  const budgetOf = (h) => data().BUDGETS[h.budget] || data().BUDGETS[2];
  const budgetHtml = (h) =>
    `<span class="budget" title="${escapeHtml(budgetOf(h).range)}">${"€".repeat(h.budget)}<span class="budget-off">${"€".repeat(4 - h.budget)}</span></span>`;

  /* ---------- Envies (filtres) ----------
   * Certaines se déduisent des équipements (spa privatif, bien-être), les
   * autres sont renseignées à la main dans hotels.js (champ `tags`). */
  const PRIVATE_SPA = /(jacuzzi|spa|sauna|bain nordique|bains nordiques|bain finlandais|bain à remous).*privati|privati.*(jacuzzi|spa|sauna|bain)/i;
  const WELLNESS = /spa|jacuzzi|sauna|hammam|bain nordique|bains nordiques|bain finlandais|massage/i;
  function tagsOf(h) {
    const t = new Set(h.tags || []);
    const am = (h.amenities || []).join(" · ");
    if (PRIVATE_SPA.test(am)) t.add("spa-prive");
    if (WELLNESS.test(am)) t.add("bien-etre");
    const TAGS = global.TAGS || {};
    return Object.keys(TAGS).filter((k) => t.has(k));
  }

  /* ---------- Séjour (dates et voyageurs) ----------
   * { checkin: "2026-10-10", checkout: "2026-10-12", adults: 2 } : ajouté aux
   * liens de réservation pour arriver directement sur les bons tarifs. */
  const ISO = /^\d{4}-\d{2}-\d{2}$/;
  const todayIso = () => {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  };
  function addDays(iso, n) {
    const [y, m, d] = iso.split("-").map(Number);
    const t = new Date(Date.UTC(y, m - 1, d + n));
    return t.toISOString().slice(0, 10);
  }
  const nightsOf = (stay) => Math.round((Date.parse(stay.checkout) - Date.parse(stay.checkin)) / 864e5);
  // Renvoie un séjour valide (dates futures, départ après l'arrivée) ou null
  function cleanStay(stay) {
    if (!stay) return null;
    const adults = Math.min(Math.max(parseInt(stay.adults, 10) || 2, 1), 12);
    if (!ISO.test(stay.checkin || "") || !ISO.test(stay.checkout || "")) return { checkin: "", checkout: "", adults };
    if (stay.checkin < todayIso() || stay.checkout <= stay.checkin || nightsOf(stay) > 30) return { checkin: "", checkout: "", adults };
    return { checkin: stay.checkin, checkout: stay.checkout, adults };
  }
  const hasDates = (stay) => !!(stay && stay.checkin && stay.checkout);

  /* ---------- Liens de réservation ---------- */
  function bookingLink(h, src = "", stay = null) {
    const { CONFIG } = data();
    let url;
    try { url = new URL(h.bookingUrl); } catch { url = null; }
    if (!url) {
      url = new URL("https://www.booking.com/searchresults.fr.html");
      url.searchParams.set("ss", `${h.name}, ${h.city}`);
    }
    if (CONFIG.booking.aid) url.searchParams.set("aid", CONFIG.booking.aid);
    if (CONFIG.booking.label) url.searchParams.set("label", [CONFIG.booking.label, src, h.id].filter(Boolean).join("-"));
    const s = cleanStay(stay);
    if (s) {
      if (hasDates(s)) {
        url.searchParams.set("checkin", s.checkin);
        url.searchParams.set("checkout", s.checkout);
      }
      url.searchParams.set("group_adults", String(s.adults));
      url.searchParams.set("no_rooms", "1");
      url.searchParams.set("group_children", "0");
    }
    return url.toString();
  }
  /* Autres sites de réservation, pour comparer. Ne s'affichent que lorsque ton
   * identifiant d'affiliation est renseigné dans config.js (sinon ces liens ne
   * te rapporteraient rien) ou qu'un lien direct est donné pour l'établissement. */
  function partnerLinks(h, stay = null) {
    const { CONFIG } = data();
    const s = cleanStay(stay);
    const out = [];
    for (const [key, p] of Object.entries(CONFIG.partners || {})) {
      const direct = h.partners && h.partners[key];
      let href = "";
      if (direct) {
        const sep = direct.includes("?") ? "&" : "?";
        href = p.param ? `${direct}${sep}${p.param}` : direct;
      } else if (p.search && p.param) {
        const u = new URL(p.search);
        u.searchParams.set("destination", `${h.name}, ${h.city}`);
        if (hasDates(s)) { u.searchParams.set("startDate", s.checkin); u.searchParams.set("endDate", s.checkout); }
        u.searchParams.set("adults", String(s ? s.adults : 2));
        href = `${u}&${p.param}`;
      }
      if (href) out.push({ key, name: p.name, href });
    }
    return out;
  }

  /* ---------- Conseil de réservation ----------
   * Déduit de la capacité de l'établissement et de sa saison. */
  function capacity(h) {
    const m = String(h.rooms || "").match(/^(\d+)\s/);
    return m ? Number(m[1]) : null;
  }
  function bookingTip(h) {
    if (h.bookingTip) return h.bookingTip;
    const n = capacity(h);
    if (n && n <= 6) return `Seulement ${n} hébergement${n > 1 ? "s" : ""} : les week-ends et les vacances partent vite, réservez dès que vos dates sont fixées.`;
    if (h.budget >= 4) return "Adresse très demandée : pour un week-end ou un pont, réservez un à deux mois à l'avance.";
    return "Les week-ends et les vacances scolaires partent en premier : en semaine, vous aurez plus de choix et souvent de meilleurs prix.";
  }

  /* ---------- Estimation indicative du séjour ---------- */
  function stayEstimate(h, nights) {
    const b = data().BUDGETS[h.budget];
    if (!b || !b.perNight || !nights) return "";
    const [min, max] = b.perNight;
    const f = (n) => formatPrice(n * nights);
    if (min == null) return `moins de ${f(max)}`;
    if (max == null) return `plus de ${f(min)}`;
    return `${f(min)} à ${f(max)}`;
  }

  /* ---------- Petits composants ---------- */
  const HEART = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s-7.5-4.6-9.6-9.3C.9 8.3 3 4.5 6.7 4.5c2.1 0 3.6 1.2 4.3 2.4.7-1.2 2.2-2.4 4.3-2.4 3.7 0 5.8 3.8 4.3 7.2C19.5 16.4 12 21 12 21z"/></svg>`;
  const favButton = (h, extra = "", on = false) => `
    <button type="button" class="fav ${extra} ${on ? "on" : ""}" data-fav="${escapeHtml(h.id)}"
      aria-pressed="${on}" aria-label="Ajouter ${escapeHtml(h.name)} à mes coups de cœur">${HEART}</button>`;

  function card(h, { dist = null, reveal = true, fav = false } = {}) {
    const { ENVS, TYPES } = data();
    const url = hotelUrl(h);
    const photos = h.images.slice(0, 5);
    return `
      <article class="card ${reveal ? "reveal" : ""}" data-id="${escapeHtml(h.id)}">
        <div class="card-media">
          <a class="card-slides" href="${url}" tabindex="-1" aria-hidden="true">
            ${photos.map((src, i) => `<img src="${img(src, 900)}" alt="" loading="lazy" decoding="async" draggable="false"${i ? "" : ` width="900" height="675"`}>`).join("")}
          </a>
          ${photos.length > 1 ? `
            <button type="button" class="card-nav prev" data-slide="-1" aria-label="Photo précédente">‹</button>
            <button type="button" class="card-nav next" data-slide="1" aria-label="Photo suivante">›</button>
            <div class="card-dots">${photos.map((_, i) => `<span class="${i ? "" : "on"}"></span>`).join("")}</div>` : ""}
          <span class="badge">${escapeHtml(ENVS[h.env].label)}</span>
          ${favButton(h, "", fav)}
          <button type="button" class="card-compare" data-compare="${escapeHtml(h.id)}" aria-pressed="false" aria-label="Comparer ${escapeHtml(h.name)}" title="Ajouter au comparateur">⇄</button>
          ${dist != null ? `<span class="card-dist">📍 ${formatDistance(dist)}</span>` : ""}
        </div>
        <a class="card-body" href="${url}">
          <p class="card-type">${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)}</p>
          <h3>${escapeHtml(h.name)}</h3>
          <p class="card-place">${escapeHtml(h.city)} · ${escapeHtml(h.region)}</p>
          <p class="card-tagline">${escapeHtml(h.tagline)}</p>
          <p class="card-foot"><span class="card-price">${budgetHtml(h)}<small>${escapeHtml(budgetOf(h).short || "")}</small></span><span class="card-more">Découvrir →</span></p>
        </a>
      </article>`;
  }

  function newsletterForm(origin, variant = "") {
    const { CONFIG } = data();
    return `
      <form class="nl-form ${variant}" name="newsletter" data-nl>
        <input type="hidden" name="origine" value="${escapeHtml(origin)}">
        <p class="nl-hp"><label>Ne pas remplir <input name="bot-field" tabindex="-1" autocomplete="off"></label></p>
        <input type="email" name="email" required placeholder="Votre adresse e-mail" aria-label="Votre adresse e-mail" autocomplete="email">
        <button class="btn btn-primary" type="submit">Je m'abonne</button>
        <p class="nl-msg" role="status"></p>
        <p class="nl-legal">Gratuit, 1 e-mail par semaine, désinscription en un clic. Votre adresse n'est jamais revendue (<a href="${page("mentions-legales.html")}">données personnelles</a>).</p>
      </form>`;
  }

  const SOCIAL_URL = {
    instagram: (h) => `https://www.instagram.com/${h}/`,
    tiktok: (h) => `https://www.tiktok.com/@${h}`,
    pinterest: (h) => `https://www.pinterest.fr/${h}/`,
  };
  const socialLinks = () => Object.entries(data().CONFIG.social || {})
    .filter(([k, v]) => typeof v === "string" && v && SOCIAL_URL[k])
    .map(([k, v]) => ({ name: k[0].toUpperCase() + k.slice(1), handle: v, href: SOCIAL_URL[k](v) }));

  /* ---------- Guides ---------- */
  function guideHotels(g) {
    const { HOTELS } = data();
    let list = g.ids ? g.ids.map((id) => HOTELS.find((h) => h.id === id)).filter(Boolean) : HOTELS.filter(g.match);
    if (g.sort) list = list.slice().sort(g.sort);
    return list;
  }
  const guideTitle = (g, n = guideHotels(g).length) => (typeof g.title === "function" ? g.title(n) : g.title);
  const guidesFor = (h) => data().GUIDES.filter((g) => guideHotels(g).some((x) => x.id === h.id));

  function guideCard(g) {
    const list = guideHotels(g);
    const cover = list.find((h) => h.id === g.cover) || list[0];
    if (!cover) return "";
    return `
      <a class="guide-card reveal" href="${guideUrl(g)}">
        <img src="${img(cover.images[0], 900)}" alt="" loading="lazy" decoding="async">
        <span class="guide-card-text">
          <small>${escapeHtml(g.kicker)} · ${list.length} adresse${list.length > 1 ? "s" : ""}</small>
          <strong>${escapeHtml(guideTitle(g, list.length))}</strong>
          <em>Lire le guide →</em>
        </span>
      </a>`;
  }

  /* ---------- Partage (Pinterest, WhatsApp, Facebook, lien) ---------- */
  function shareBlock({ url, title, image, heading = "Partager cette adresse" }) {
    const u = encodeURIComponent(url), t = encodeURIComponent(title);
    const links = [
      ["pinterest", "Pinterest", `https://pinterest.com/pin/create/button/?url=${u}&media=${encodeURIComponent(image || "")}&description=${t}`],
      ["whatsapp", "WhatsApp", `https://wa.me/?text=${encodeURIComponent(`${title} ${url}`)}`],
      ["facebook", "Facebook", `https://www.facebook.com/sharer/sharer.php?u=${u}`],
      ["email", "E-mail", `mailto:?subject=${t}&body=${encodeURIComponent(`Regarde ça : ${url}`)}`],
    ];
    return `
        <div class="share-block">
          <p class="share-title">${escapeHtml(heading)}</p>
          <div class="share-links">${links.map(([k, label, href]) => `<a class="share-${k}" href="${escapeHtml(href)}" target="_blank" rel="noopener" data-track="Partage" data-hotel="${k}">${label}</a>`).join("")}<button type="button" class="share-copy" data-copy-link="${escapeHtml(url)}">Copier le lien</button></div>
        </div>`;
  }

  /* ---------- En-tête et pied de page ---------- */
  function header() {
    const { CONFIG } = data();
    const links = [
      ["index.html#destinations", "Ambiances"],
      ["carte.html", "La carte"],
      ["guides/index.html", "Guides"],
      ["quiz.html", "Le quiz"],
      ["index.html#explorer", "Tous les lieux"],
    ];
    return `
      <a class="brand" href="${page("index.html")}">
        <span class="brand-mark">✦</span>
        <span>${escapeHtml(CONFIG.siteName)}</span>
      </a>
      <nav class="nav" aria-label="Navigation principale">
        ${links.map(([href, label]) => `<a href="${page(href)}">${label}</a>`).join("\n        ")}
        <button type="button" class="nav-icon" data-surprise title="Un lieu au hasard" aria-label="Un lieu au hasard">🎲</button>
        <button type="button" class="nav-icon" id="fav-open" title="Mes coups de cœur" aria-label="Mes coups de cœur">♡<span class="fav-count" hidden></span></button>
        <a href="${page("index.html#explorer")}" class="nav-cta" data-open-near>Près de chez moi</a>
        <button type="button" class="nav-icon nav-menu" id="menu-open" aria-label="Ouvrir le menu" aria-expanded="false" aria-controls="menu-sheet"><span></span></button>
      </nav>
      <div class="menu-sheet" id="menu-sheet" hidden>
        <nav class="menu-panel" aria-label="Menu">
          ${links.map(([href, label]) => `<a href="${page(href)}">${label}</a>`).join("\n          ")}
          <a href="${page("comparer.html")}">Le comparateur</a>
          <a href="${page("index.html#explorer")}" data-open-near>📍 Près de chez moi</a>
          <a href="${page("a-propos.html")}" class="menu-small">Qui sommes-nous ?</a>
        </nav>
      </div>`;
  }

  function footer() {
    const { CONFIG, ENVS, GUIDES } = data();
    const envLinks = Object.entries(ENVS)
      .map(([k, e]) => `<li><a href="${page(`index.html?env=${k}#explorer`)}">Hôtels insolites ${e.inLabel}</a></li>`).join("");
    const guideLinks = GUIDES.filter((g) => guideHotels(g).length)
      .slice(0, 7).map((g) => `<li><a href="${guideUrl(g)}">${escapeHtml(g.short || guideTitle(g))}</a></li>`).join("");
    const socials = socialLinks()
      .map((s) => `<li><a href="${escapeHtml(s.href)}" target="_blank" rel="noopener">${escapeHtml(s.name)} · @${escapeHtml(s.handle)}</a></li>`).join("");
    return `
      <div class="footer-news">
        <div>
          <h3>${escapeHtml(CONFIG.newsletter.title)}</h3>
          <p class="muted">${escapeHtml(CONFIG.newsletter.pitch)}</p>
        </div>
        ${newsletterForm("pied-de-page", "on-dark")}
      </div>
      <div class="footer-grid">
        <div>
          <a class="brand" href="${page("index.html")}"><span class="brand-mark">✦</span><span>${escapeHtml(CONFIG.siteName)}</span></a>
          <p class="muted">${escapeHtml(CONFIG.tagline)}. Une sélection d'adresses rares, choisies une à une.</p>
        </div>
        <div><h4>Ambiances</h4><ul>${envLinks}</ul></div>
        <div><h4>Nos guides</h4><ul>${guideLinks}<li><a href="${page("guides/index.html")}">Tous les guides →</a></li><li><a href="${page("carte.html")}">La carte interactive →</a></li></ul></div>
        <div><h4>Nuits Singulières</h4><ul><li><a href="${page("quiz.html")}">Le quiz : trouver ma nuit</a></li><li><a href="${page("comparer.html")}">Le comparateur</a></li><li><a href="${page("a-propos.html")}">Qui sommes-nous ?</a></li>${socials}<li><a href="mailto:${escapeHtml(CONFIG.contactEmail)}">${escapeHtml(CONFIG.contactEmail)}</a></li><li><a href="${page("mentions-legales.html")}">Mentions légales</a></li></ul></div>
      </div>
      <p class="disclosure">Ce site contient des liens affiliés : si vous réservez via nos liens, nous percevons une commission du site de réservation, sans aucun surcoût pour vous. Notre sélection est indépendante : aucun établissement ne paie pour y figurer. Les niveaux de budget sont indicatifs ; le tarif final est celui du site de réservation. Photos : © les établissements.</p>
      <p class="muted small">© ${new Date().getFullYear()} ${escapeHtml(CONFIG.siteName)}</p>`;
  }

  return {
    data, setRoot, root, page, hotelUrl, guideUrl, escapeHtml, formatPrice, formatDistance, distanceKm,
    FALLBACK, img, budgetOf, budgetHtml, bookingLink, partnerLinks, bookingTip, stayEstimate, capacity,
    todayIso, addDays, nightsOf, cleanStay, hasDates, tagsOf,
    favButton, card, newsletterForm, socialLinks, guideHotels, guideTitle, guidesFor, guideCard, shareBlock,
    header, footer, baseLayer,
  };
});
