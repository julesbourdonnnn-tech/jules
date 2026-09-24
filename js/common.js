/* Fonctions partagées entre toutes les pages. */
(function () {
  const CONFIG = window.SITE_CONFIG;

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

  /* ---------- Provenance du visiteur ----------
   * Les liens publiés sur Instagram / dans la newsletter portent ?src=instagram
   * ou ?src=newsletter. On la mémorise pour la session et on l'ajoute au
   * libellé Booking : ton tableau de bord Booking montre alors quel canal rapporte. */
  const SRC_KEY = "ns-source";
  (function captureSource() {
    const p = new URLSearchParams(location.search);
    const src = (p.get("src") || p.get("utm_source") || "").toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 30);
    if (src) try { sessionStorage.setItem(SRC_KEY, src); } catch { /* navigation privée */ }
  })();
  function getSource() {
    try { return sessionStorage.getItem(SRC_KEY) || ""; } catch { return ""; }
  }

  // Lien de réservation Booking.com avec l'identifiant d'affiliation
  function bookingLink(hotel) {
    let url;
    try { url = new URL(hotel.bookingUrl); } catch { url = null; }
    if (!url) {
      url = new URL("https://www.booking.com/searchresults.fr.html");
      url.searchParams.set("ss", `${hotel.name}, ${hotel.city}`);
    }
    if (CONFIG.booking.aid) url.searchParams.set("aid", CONFIG.booking.aid);
    if (CONFIG.booking.label) {
      const src = getSource();
      url.searchParams.set("label", [CONFIG.booking.label, src, hotel.id].filter(Boolean).join("-"));
    }
    return url.toString();
  }

  /* ---------- Statistiques (Plausible) ---------- */
  if (CONFIG.analytics && CONFIG.analytics.plausibleDomain) {
    const s = document.createElement("script");
    s.defer = true;
    s.dataset.domain = CONFIG.analytics.plausibleDomain;
    s.src = "https://plausible.io/js/script.outbound-links.js";
    document.head.appendChild(s);
    window.plausible = window.plausible || function () { (window.plausible.q = window.plausible.q || []).push(arguments); };
  }
  function track(event, props) {
    if (typeof window.plausible === "function") window.plausible(event, { props });
  }
  // Tout clic sur un lien marqué data-track est compté (ex. "Réservation", hôtel = …)
  document.addEventListener("click", (e) => {
    const a = e.target.closest("[data-track]");
    if (a) track(a.dataset.track, { hotel: a.dataset.hotel || "", source: getSource() || "direct" });
  });

  /* ---------- Offres payantes ---------- */
  const PLAN_RANK = { premium: 2, partenaire: 1 };
  const planRank = (h) => PLAN_RANK[h.plan] || 0;
  const partnerBadge = (h) => (planRank(h) ? `<span class="badge-partner" title="Établissement ayant souscrit une offre de mise en avant">Partenaire</span>` : "");

  /* ---------- Newsletter ----------
   * Envoi vers Netlify Forms (le formulaire caché "newsletter" dans index.html
   * permet à Netlify de le détecter au déploiement). */
  async function submitForm(form) {
    const body = new URLSearchParams(new FormData(form)).toString();
    const res = await fetch("/", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
    if (!res.ok) throw new Error(String(res.status));
  }
  function newsletterForm(origin, variant = "") {
    const nl = CONFIG.newsletter;
    return `
      <form class="nl-form ${variant}" name="newsletter" data-nl>
        <input type="hidden" name="form-name" value="newsletter">
        <input type="hidden" name="origine" value="${escapeHtml(origin)}">
        <p class="nl-hp"><label>Ne pas remplir <input name="bot-field" tabindex="-1" autocomplete="off"></label></p>
        <input type="email" name="email" required placeholder="Votre adresse e-mail" aria-label="Votre adresse e-mail">
        <button class="btn btn-primary" type="submit">Je m'abonne</button>
        <p class="nl-msg" role="status"></p>
        <p class="nl-legal">Gratuit, 1 e-mail par semaine, désinscription en un clic. ${escapeHtml(nl.title)}.</p>
      </form>`;
  }
  document.addEventListener("submit", async (e) => {
    const form = e.target.closest("[data-nl], [data-netlify-form]");
    if (!form) return;
    e.preventDefault();
    const msg = form.querySelector(".nl-msg, .form-msg");
    const btn = form.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await submitForm(form);
      form.classList.add("sent");
      msg.textContent = form.dataset.success || "Merci ! Vous êtes bien inscrit·e. À dimanche ✦";
      track(form.name === "newsletter" ? "Newsletter" : "Formulaire", { form: form.name, source: getSource() || "direct" });
      form.reset();
    } catch {
      msg.textContent = "Oups, l'envoi a échoué. Réessayez dans un instant.";
    } finally {
      btn.disabled = false;
    }
  });

  const socialUrl = {
    instagram: (h) => `https://www.instagram.com/${h}/`,
    tiktok: (h) => `https://www.tiktok.com/@${h}`,
    pinterest: (h) => `https://www.pinterest.fr/${h}/`,
  };
  const socialLinks = () => Object.entries(CONFIG.social || {})
    .filter(([k, v]) => v && socialUrl[k])
    .map(([k, v]) => ({ name: k[0].toUpperCase() + k.slice(1), handle: v, href: socialUrl[k](v) }));

  // Liens vers les autres partenaires renseignés sur la fiche
  function partnerLinks(hotel) {
    return Object.entries(hotel.partners || {})
      .filter(([key, href]) => href && CONFIG.partners[key])
      .map(([key, href]) => {
        const p = CONFIG.partners[key];
        const sep = href.includes("?") ? "&" : "?";
        return { name: p.name, href: p.param ? `${href}${sep}${p.param}` : href };
      });
  }

  /* ---------- Position de l'utilisateur (mémorisée entre les pages) ---------- */
  const LOC_KEY = "ns-user-location";
  function getUserLocation() {
    try { return JSON.parse(localStorage.getItem(LOC_KEY)) || null; } catch { return null; }
  }
  function setUserLocation(loc) {
    try { loc ? localStorage.setItem(LOC_KEY, JSON.stringify(loc)) : localStorage.removeItem(LOC_KEY); } catch { /* navigation privée */ }
  }

  // Géocodage d'adresses françaises via le service public de l'IGN (gratuit, sans clé)
  const GEOCODERS = [
    "https://data.geopf.fr/geocodage/search",
    "https://api-adresse.data.gouv.fr/search/",
  ];
  async function geocode(query, limit = 5) {
    for (const base of GEOCODERS) {
      try {
        const res = await fetch(`${base}?q=${encodeURIComponent(query)}&limit=${limit}`);
        if (!res.ok) continue;
        const data = await res.json();
        return (data.features || []).map((f) => ({
          label: f.properties.label,
          city: f.properties.city,
          lat: f.geometry.coordinates[1],
          lng: f.geometry.coordinates[0],
        }));
      } catch { /* on essaie le service suivant */ }
    }
    return [];
  }

  function locateBrowser() {
    return new Promise((resolve, reject) => {
      if (!navigator.geolocation) return reject(new Error("Géolocalisation non disponible"));
      navigator.geolocation.getCurrentPosition(
        (p) => resolve({ label: "Ma position actuelle", lat: p.coords.latitude, lng: p.coords.longitude }),
        () => reject(new Error("Impossible d'obtenir votre position")),
        { timeout: 10000 }
      );
    });
  }

  /* ---------- Photos : image de secours si une photo ne charge pas ---------- */
  const FALLBACK = "data:image/svg+xml;utf8," + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2f4a3a"/><stop offset="1" stop-color="#b8925a"/></linearGradient></defs><rect width="800" height="600" fill="url(#g)"/><text x="400" y="315" font-family="Georgia,serif" font-size="34" fill="#f6f1e9" text-anchor="middle" opacity=".85">Nuits Singulières</text></svg>`
  );
  document.addEventListener("error", (e) => {
    const img = e.target;
    if (img.tagName === "IMG" && img.src !== FALLBACK) img.src = FALLBACK;
  }, true);

  /* ---------- En-tête et pied de page ---------- */
  function renderChrome() {
    const header = document.getElementById("site-header");
    if (header) {
      header.innerHTML = `
        <a class="brand" href="index.html">
          <span class="brand-mark">✦</span>
          <span>${escapeHtml(CONFIG.siteName)}</span>
        </a>
        <nav class="nav">
          <a href="index.html#destinations">Destinations</a>
          <a href="index.html#explorer">Tous les hôtels</a>
          <a href="hoteliers.html">Hôteliers</a>
          <a href="index.html#explorer" class="nav-cta" data-open-near>Près de chez moi</a>
        </nav>`;
      const onScroll = () => header.classList.toggle("scrolled", window.scrollY > 40);
      window.addEventListener("scroll", onScroll, { passive: true });
      onScroll();
    }
    const footer = document.getElementById("site-footer");
    if (footer) {
      const envLinks = Object.entries(window.ENVIRONMENTS)
        .map(([k, e]) => `<li><a href="index.html?env=${k}#explorer">Hôtels ${e.inLabel}</a></li>`)
        .join("");
      const typeLinks = Object.entries(window.TYPES).slice(0, 6)
        .map(([k, t]) => `<li><a href="index.html?type=${k}#explorer">${escapeHtml(t.label)}</a></li>`)
        .join("");
      const socials = socialLinks()
        .map((s) => `<li><a href="${escapeHtml(s.href)}" target="_blank" rel="noopener">${escapeHtml(s.name)} · @${escapeHtml(s.handle)}</a></li>`)
        .join("");
      footer.innerHTML = `
        <div class="footer-news">
          <div>
            <h3>${escapeHtml(CONFIG.newsletter.title)}</h3>
            <p class="muted">${escapeHtml(CONFIG.newsletter.pitch)}</p>
          </div>
          ${newsletterForm("pied-de-page", "on-dark")}
        </div>
        <div class="footer-grid">
          <div>
            <a class="brand" href="index.html"><span class="brand-mark">✦</span><span>${escapeHtml(CONFIG.siteName)}</span></a>
            <p class="muted">${escapeHtml(CONFIG.tagline)}. Une sélection d'adresses rares, choisies une à une.</p>
          </div>
          <div><h4>Ambiances</h4><ul>${envLinks}</ul></div>
          <div><h4>Expériences</h4><ul>${typeLinks}</ul></div>
          <div><h4>Nous suivre</h4><ul>${socials}<li><a href="hoteliers.html">Espace hôteliers</a></li><li><a href="mailto:${escapeHtml(CONFIG.contactEmail)}">${escapeHtml(CONFIG.contactEmail)}</a></li><li><a href="mentions-legales.html">Mentions légales</a></li></ul></div>
        </div>
        <p class="disclosure">Ce site contient des liens affiliés : si vous réservez via nos liens, nous percevons une commission du site partenaire, sans aucun surcoût pour vous. Les établissements marqués « Partenaire » ont souscrit une offre de mise en avant payante, qui améliore leur position dans le tri « Recommandés ». Les prix affichés sont indicatifs (« à partir de ») ; le tarif final est celui du site de réservation.</p>
        <p class="muted small">© ${new Date().getFullYear()} ${escapeHtml(CONFIG.siteName)}</p>`;
    }
  }

  window.NS = {
    CONFIG, escapeHtml, formatPrice, formatDistance, distanceKm,
    bookingLink, partnerLinks, getUserLocation, setUserLocation,
    geocode, locateBrowser, renderChrome, getSource, track,
    planRank, partnerBadge, newsletterForm, socialLinks,
    // Redimensionne les photos Unsplash ; les autres URLs sont laissées telles quelles
    img: (url, w) => (w && url.includes("images.unsplash.com") ? url.replace(/w=\d+/, `w=${w}`) : url),
  };
  document.addEventListener("DOMContentLoaded", renderChrome);
})();
