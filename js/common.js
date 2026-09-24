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

  /* ---------- Photos ----------
   * Les photos locales existent en 2 tailles : 1.jpg (grande) et 1-sm.jpg (vignette). */
  function img(url, w) {
    if (!url) return FALLBACK;
    if (w && w <= 900 && /^assets\/hotels\/.+\/\d+\.jpg$/.test(url)) return url.replace(/\.jpg$/, "-sm.jpg");
    if (w && url.includes("images.unsplash.com")) return url.replace(/w=\d+/, `w=${w}`);
    return url;
  }
  const budgetOf = (h) => window.BUDGETS[h.budget] || window.BUDGETS[2];
  const budgetHtml = (h) => {
    const b = budgetOf(h);
    return `<span class="budget" title="${escapeHtml(b.range)}">${"€".repeat(h.budget)}<span class="budget-off">${"€".repeat(4 - h.budget)}</span></span>`;
  };

  /* ---------- Favoris (mémorisés dans le navigateur) ---------- */
  const FAV_KEY = "ns-favs";
  function getFavs() {
    try { return JSON.parse(localStorage.getItem(FAV_KEY)) || []; } catch { return []; }
  }
  function toggleFav(id) {
    const favs = getFavs();
    const i = favs.indexOf(id);
    i >= 0 ? favs.splice(i, 1) : favs.unshift(id);
    try { localStorage.setItem(FAV_KEY, JSON.stringify(favs)); } catch { /* navigation privée */ }
    document.dispatchEvent(new CustomEvent("favs:change", { detail: { id, on: i < 0 } }));
    if (i < 0) track("Favori", { hotel: id });
    return i < 0;
  }
  const isFav = (id) => getFavs().includes(id);
  const favButton = (h, extra = "") => `
    <button type="button" class="fav ${extra} ${isFav(h.id) ? "on" : ""}" data-fav="${escapeHtml(h.id)}"
      aria-pressed="${isFav(h.id)}" aria-label="Ajouter ${escapeHtml(h.name)} à mes coups de cœur">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s-7.5-4.6-9.6-9.3C.9 8.3 3 4.5 6.7 4.5c2.1 0 3.6 1.2 4.3 2.4.7-1.2 2.2-2.4 4.3-2.4 3.7 0 5.8 3.8 4.3 7.2C19.5 16.4 12 21 12 21z"/></svg>
    </button>`;
  document.addEventListener("click", (e) => {
    const b = e.target.closest("[data-fav]");
    if (!b) return;
    e.preventDefault();
    e.stopPropagation();
    toggleFav(b.dataset.fav);
  });
  document.addEventListener("favs:change", ({ detail }) => {
    document.querySelectorAll(`[data-fav="${CSS.escape(detail.id)}"]`).forEach((b) => {
      b.classList.toggle("on", detail.on);
      b.setAttribute("aria-pressed", detail.on);
      if (detail.on) { b.classList.remove("pop"); void b.offsetWidth; b.classList.add("pop"); }
    });
    updateFavCount();
    renderFavDrawer();
  });

  /* ---------- Carte d'hôtel avec mini-diaporama (partagée par toutes les pages) ---------- */
  function card(h, { dist = null, reveal = true } = {}) {
    const ENVS = window.ENVIRONMENTS, TYPES = window.TYPES;
    const url = `hotel.html?id=${encodeURIComponent(h.id)}`;
    const photos = h.images.slice(0, 5);
    return `
      <article class="card ${reveal ? "reveal" : ""}" data-id="${escapeHtml(h.id)}">
        <div class="card-media">
          <a class="card-slides" href="${url}" tabindex="-1" aria-hidden="true">
            ${photos.map((src, i) => `<img src="${img(src, 900)}" alt="" loading="lazy" draggable="false" ${i ? 'decoding="async"' : ""}>`).join("")}
          </a>
          ${photos.length > 1 ? `
            <button type="button" class="card-nav prev" data-slide="-1" aria-label="Photo précédente">‹</button>
            <button type="button" class="card-nav next" data-slide="1" aria-label="Photo suivante">›</button>
            <div class="card-dots">${photos.map((_, i) => `<span class="${i ? "" : "on"}"></span>`).join("")}</div>` : ""}
          <span class="badge">${escapeHtml(ENVS[h.env].label)}</span>
          ${partnerBadge(h)}
          ${favButton(h)}
          ${dist != null ? `<span class="card-dist">📍 ${formatDistance(dist)}</span>` : ""}
        </div>
        <a class="card-body" href="${url}">
          <p class="card-type">${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)}</p>
          <h3>${escapeHtml(h.name)}</h3>
          <p class="card-place">${escapeHtml(h.city)} · ${escapeHtml(h.region)}</p>
          <p class="card-tagline">${escapeHtml(h.tagline)}</p>
          <p class="card-foot">${budgetHtml(h)}<span class="card-more">Découvrir →</span></p>
        </a>
      </article>`;
  }
  // Flèches et points du mini-diaporama
  document.addEventListener("click", (e) => {
    const b = e.target.closest("[data-slide]");
    if (!b) return;
    e.preventDefault();
    const track = b.closest(".card-media").querySelector(".card-slides");
    const n = track.children.length;
    const i = Math.round(track.scrollLeft / track.clientWidth);
    const next = (i + Number(b.dataset.slide) + n) % n;
    track.scrollTo({ left: next * track.clientWidth, behavior: "smooth" });
  });
  document.addEventListener("scroll", (e) => {
    const t = e.target;
    if (!(t instanceof Element) || !t.classList.contains("card-slides")) return;
    const i = Math.round(t.scrollLeft / t.clientWidth);
    t.parentElement.querySelectorAll(".card-dots span").forEach((d, k) => d.classList.toggle("on", k === i));
  }, true);

  /* ---------- Apparition au défilement ---------- */
  const revealObserver = "IntersectionObserver" in window
    ? new IntersectionObserver((entries) => entries.forEach((en) => {
        if (en.isIntersecting) { en.target.classList.add("in"); revealObserver.unobserve(en.target); }
      }), { rootMargin: "0px 0px -8% 0px", threshold: 0.08 })
    : null;
  function observeReveal(root = document) {
    root.querySelectorAll(".reveal:not(.in)").forEach((el, i) => {
      el.style.setProperty("--d", `${Math.min(i % 6, 5) * 70}ms`);
      revealObserver ? revealObserver.observe(el) : el.classList.add("in");
    });
  }

  /* ---------- « Surprenez-moi » ---------- */
  function surprise() {
    const list = window.HOTELS;
    let box = document.getElementById("surprise");
    if (!box) {
      box = document.createElement("div");
      box.id = "surprise";
      box.className = "surprise";
      box.innerHTML = `
        <div class="surprise-card" role="dialog" aria-modal="true" aria-label="Un hôtel au hasard">
          <button type="button" class="surprise-close" aria-label="Fermer">×</button>
          <div class="surprise-media"><img alt=""></div>
          <div class="surprise-body">
            <p class="card-type"></p>
            <h3></h3>
            <p class="card-place"></p>
            <p class="surprise-tagline"></p>
            <div class="surprise-actions">
              <a class="btn btn-primary" href="#">Découvrir ce lieu</a>
              <button type="button" class="btn btn-ghost" data-surprise>🎲 Relancer</button>
            </div>
          </div>
        </div>`;
      document.body.appendChild(box);
      box.addEventListener("click", (e) => { if (e.target === box || e.target.closest(".surprise-close")) closeSurprise(); });
    }
    box.hidden = false;
    document.body.classList.add("no-scroll");
    requestAnimationFrame(() => box.classList.add("open"));
    const card = box.querySelector(".surprise-card");
    const image = box.querySelector("img");
    card.classList.add("rolling");
    const pick = list[Math.floor(Math.random() * list.length)];
    // Défilement rapide de photos qui ralentit, comme une machine à sous
    let step = 0;
    const steps = 14;
    const spin = () => {
      const h = step < steps ? list[Math.floor(Math.random() * list.length)] : pick;
      image.src = img(h.images[0], 900);
      if (step++ < steps) setTimeout(spin, 45 + step * step * 1.1);
      else {
        const T = window.TYPES[pick.type];
        card.classList.remove("rolling");
        box.querySelector(".card-type").textContent = `${T.icon} ${T.label}`;
        box.querySelector("h3").textContent = pick.name;
        box.querySelector(".card-place").textContent = `${pick.city} · ${pick.region}`;
        box.querySelector(".surprise-tagline").textContent = pick.tagline;
        box.querySelector("a.btn").href = `hotel.html?id=${encodeURIComponent(pick.id)}`;
      }
    };
    spin();
    track("Surprise", {});
  }
  function closeSurprise() {
    const box = document.getElementById("surprise");
    if (!box) return;
    box.classList.remove("open");
    document.body.classList.remove("no-scroll");
    setTimeout(() => (box.hidden = true), 250);
  }
  document.addEventListener("click", (e) => {
    if (e.target.closest("[data-surprise]")) { e.preventDefault(); surprise(); }
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") { closeSurprise(); toggleDrawer(false); }
  });

  /* ---------- Tiroir des favoris ---------- */
  function updateFavCount() {
    const n = getFavs().length;
    document.querySelectorAll(".fav-count").forEach((el) => { el.textContent = n; el.hidden = !n; });
  }
  function renderFavDrawer() {
    const list = document.getElementById("fav-list");
    if (!list) return;
    const favs = getFavs().map((id) => window.HOTELS.find((h) => h.id === id)).filter(Boolean);
    list.innerHTML = favs.length
      ? favs.map((h) => `
          <div class="fav-item">
            <a href="hotel.html?id=${encodeURIComponent(h.id)}"><img src="${img(h.images[0], 400)}" alt=""></a>
            <a href="hotel.html?id=${encodeURIComponent(h.id)}"><strong>${escapeHtml(h.name)}</strong><span>${escapeHtml(h.city)} · ${escapeHtml(window.TYPES[h.type].label)}</span></a>
            ${favButton(h, "fav-mini")}
          </div>`).join("")
      : `<p class="muted fav-empty">Touchez le ♡ d'un hôtel pour le garder ici. Pratique pour comparer et partager vos envies.</p>`;
  }
  function toggleDrawer(open) {
    const d = document.getElementById("fav-drawer");
    if (!d) return;
    if (open) { renderFavDrawer(); d.hidden = false; requestAnimationFrame(() => d.classList.add("open")); document.body.classList.add("no-scroll"); }
    else if (!d.hidden) { d.classList.remove("open"); document.body.classList.remove("no-scroll"); setTimeout(() => (d.hidden = true), 300); }
  }

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
          <a href="index.html#destinations">Ambiances</a>
          <a href="index.html#explorer">Tous les hôtels</a>
          <a href="hoteliers.html">Hôteliers</a>
          <button type="button" class="nav-icon" data-surprise title="Un hôtel au hasard" aria-label="Un hôtel au hasard">🎲</button>
          <button type="button" class="nav-icon" id="fav-open" title="Mes coups de cœur" aria-label="Mes coups de cœur">♡<span class="fav-count" hidden></span></button>
          <a href="index.html#explorer" class="nav-cta" data-open-near>Près de chez moi</a>
        </nav>`;
      const onScroll = () => header.classList.toggle("scrolled", window.scrollY > 40);
      window.addEventListener("scroll", onScroll, { passive: true });
      onScroll();

      const drawer = document.createElement("aside");
      drawer.id = "fav-drawer";
      drawer.className = "drawer";
      drawer.hidden = true;
      drawer.innerHTML = `
        <div class="drawer-panel" role="dialog" aria-modal="true" aria-label="Mes coups de cœur">
          <div class="drawer-head"><h3>Mes coups de cœur</h3><button type="button" class="drawer-close" aria-label="Fermer">×</button></div>
          <div id="fav-list" class="fav-list"></div>
        </div>`;
      document.body.appendChild(drawer);
      header.querySelector("#fav-open").addEventListener("click", () => toggleDrawer(true));
      drawer.addEventListener("click", (e) => { if (e.target === drawer || e.target.closest(".drawer-close")) toggleDrawer(false); });
      updateFavCount();
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
        <p class="disclosure">Ce site contient des liens affiliés : si vous réservez via nos liens, nous percevons une commission du site partenaire, sans aucun surcoût pour vous. Les établissements marqués « Partenaire » ont souscrit une offre de mise en avant payante, qui améliore leur position dans le tri « Recommandés ». Les niveaux de budget sont indicatifs ; le tarif final est celui du site de réservation. Photos : © les établissements.</p>
        <p class="muted small">© ${new Date().getFullYear()} ${escapeHtml(CONFIG.siteName)}</p>`;
    }
    observeReveal();
  }

  window.NS = {
    CONFIG, escapeHtml, formatPrice, formatDistance, distanceKm,
    bookingLink, partnerLinks, getUserLocation, setUserLocation,
    geocode, locateBrowser, renderChrome, getSource, track,
    planRank, partnerBadge, newsletterForm, socialLinks,
    img, budgetOf, budgetHtml, card, favButton, getFavs, isFav, toggleFav,
    observeReveal, surprise,
  };
  document.addEventListener("DOMContentLoaded", renderChrome);
})();
