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

  // Lien de réservation Booking.com avec l'identifiant d'affiliation
  function bookingLink(hotel) {
    let url;
    try { url = new URL(hotel.bookingUrl); } catch { url = null; }
    if (!url) {
      url = new URL("https://www.booking.com/searchresults.fr.html");
      url.searchParams.set("ss", `${hotel.name}, ${hotel.city}`);
    }
    if (CONFIG.booking.aid) url.searchParams.set("aid", CONFIG.booking.aid);
    if (CONFIG.booking.label) url.searchParams.set("label", `${CONFIG.booking.label}-${hotel.id}`);
    return url.toString();
  }

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
      footer.innerHTML = `
        <div class="footer-grid">
          <div>
            <a class="brand" href="index.html"><span class="brand-mark">✦</span><span>${escapeHtml(CONFIG.siteName)}</span></a>
            <p class="muted">${escapeHtml(CONFIG.tagline)}. Une sélection d'adresses rares, choisies une à une.</p>
          </div>
          <div><h4>Ambiances</h4><ul>${envLinks}</ul></div>
          <div><h4>Expériences</h4><ul>${typeLinks}</ul></div>
          <div><h4>Contact</h4><ul><li><a href="mailto:${escapeHtml(CONFIG.contactEmail)}">${escapeHtml(CONFIG.contactEmail)}</a></li><li><a href="mentions-legales.html">Mentions légales</a></li></ul></div>
        </div>
        <p class="disclosure">Ce site contient des liens affiliés : si vous réservez via nos liens, nous percevons une commission du site partenaire, sans aucun surcoût pour vous. Les prix affichés sont indicatifs (« à partir de ») ; le tarif final est celui du site de réservation.</p>
        <p class="muted small">© ${new Date().getFullYear()} ${escapeHtml(CONFIG.siteName)}</p>`;
    }
  }

  window.NS = {
    CONFIG, escapeHtml, formatPrice, formatDistance, distanceKm,
    bookingLink, partnerLinks, getUserLocation, setUserLocation,
    geocode, locateBrowser, renderChrome,
    img: (url, w) => (w ? url.replace(/w=\d+/, `w=${w}`) : url),
  };
  document.addEventListener("DOMContentLoaded", renderChrome);
})();
