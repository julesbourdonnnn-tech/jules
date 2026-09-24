/* Page d'accueil : catégories, filtres, recherche par proximité, carte. */
(function () {
  const { escapeHtml, formatPrice, formatDistance, distanceKm, getUserLocation, setUserLocation, geocode, locateBrowser, img, planRank, partnerBadge, newsletterForm, socialLinks } = window.NS;
  const HOTELS = window.HOTELS, ENVS = window.ENVIRONMENTS, TYPES = window.TYPES;
  const MAX_PRICE = 400;
  const $ = (sel) => document.querySelector(sel);

  const state = {
    q: "", env: "", type: "", max: MAX_PRICE, sort: "featured", radius: "",
    view: "grid", loc: getUserLocation(),
  };

  /* ---------- Lecture / écriture des filtres dans l'URL (liens partageables) ---------- */
  function readUrl() {
    const p = new URLSearchParams(location.search);
    state.q = p.get("q") || "";
    state.env = ENVS[p.get("env")] ? p.get("env") : "";
    state.type = TYPES[p.get("type")] ? p.get("type") : "";
    state.max = Math.min(Number(p.get("max")) || MAX_PRICE, MAX_PRICE);
    state.sort = p.get("sort") || (state.loc ? "distance" : "featured");
  }
  function writeUrl() {
    const p = new URLSearchParams();
    if (state.q) p.set("q", state.q);
    if (state.env) p.set("env", state.env);
    if (state.type) p.set("type", state.type);
    if (state.max < MAX_PRICE) p.set("max", state.max);
    if (state.sort !== "featured") p.set("sort", state.sort);
    const qs = p.toString();
    history.replaceState(null, "", `${location.pathname}${qs ? "?" + qs : ""}${location.hash}`);
  }

  /* ---------- Carte d'un hôtel ---------- */
  function card(h) {
    const dist = state.loc ? `<span class="card-dist">📍 ${formatDistance(h._dist)}</span>` : "";
    return `
      <a class="card" href="hotel.html?id=${encodeURIComponent(h.id)}">
        <div class="card-media">
          <img src="${img(h.images[0], 900)}" alt="${escapeHtml(h.name)}" loading="lazy">
          <span class="badge">${escapeHtml(ENVS[h.env].label)}</span>
          ${partnerBadge(h)}
          ${dist}
        </div>
        <div class="card-body">
          <p class="card-type">${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)}</p>
          <h3>${escapeHtml(h.name)}</h3>
          <p class="card-place">${escapeHtml(h.city)} · ${escapeHtml(h.department)}</p>
          <p class="card-tagline">${escapeHtml(h.tagline)}</p>
          <p class="card-price">dès <strong>${formatPrice(h.price)}</strong> / nuit</p>
        </div>
      </a>`;
  }

  /* ---------- Sections statiques ---------- */
  function renderStatic() {
    const counts = (key, val) => HOTELS.filter((h) => h[key] === val).length;

    $("#env-grid").innerHTML = Object.entries(ENVS).map(([k, e]) => `
      <a class="env-tile" href="?env=${k}#explorer" data-env="${k}">
        <img src="https://images.unsplash.com/${e.image}?auto=format&fit=crop&w=900&q=80" alt="" loading="lazy">
        <div class="env-tile-text">
          <h3>${escapeHtml(e.label)}</h3>
          <p>${escapeHtml(e.desc)}</p>
          <span>${counts("env", k)} adresses →</span>
        </div>
      </a>`).join("");

    $("#type-grid").innerHTML = Object.entries(TYPES)
      .filter(([k]) => counts("type", k) > 0)
      .map(([k, t]) => `
        <a class="type-chip" href="?type=${k}#explorer" data-type="${k}">
          <span class="type-icon">${t.icon}</span>
          <span><strong>${escapeHtml(t.label)}</strong><small>${counts("type", k)} hôtel${counts("type", k) > 1 ? "s" : ""}</small></span>
        </a>`).join("");

    // Coups de cœur : les hôtels Premium d'abord, puis la sélection éditoriale
    const featured = HOTELS.filter((h) => h.plan === "premium")
      .concat(HOTELS.filter((h) => h.featured && h.plan !== "premium"));
    $("#featured").innerHTML = featured.slice(0, 6).map((h, i) => `
      <a class="feature ${i === 0 ? "feature-lg" : ""}" href="hotel.html?id=${encodeURIComponent(h.id)}">
        <img src="${img(h.images[0], i === 0 ? 1600 : 900)}" alt="${escapeHtml(h.name)}" loading="lazy">
        ${partnerBadge(h)}
        <div class="feature-text">
          <p class="card-type">${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)} · ${escapeHtml(h.city)}</p>
          <h3>${escapeHtml(h.name)}</h3>
          <p class="feature-price">dès ${formatPrice(h.price)} / nuit</p>
        </div>
      </a>`).join("");

    const envOpts = Object.entries(ENVS).map(([k, e]) => `<option value="${k}">${escapeHtml(e.label)}</option>`).join("");
    $("#hero-env").insertAdjacentHTML("beforeend", envOpts);
    $("#f-type").insertAdjacentHTML("beforeend",
      Object.entries(TYPES).map(([k, t]) => `<option value="${k}">${t.icon} ${escapeHtml(t.label)}</option>`).join(""));
    $("#f-env").innerHTML = `<button type="button" data-env="">Tout</button>` +
      Object.entries(ENVS).map(([k, e]) => `<button type="button" data-env="${k}">${escapeHtml(e.label)}</button>`).join("");

    // Newsletter
    const nl = window.SITE_CONFIG.newsletter;
    $("#nl-title").textContent = nl.title;
    $("#nl-pitch").textContent = nl.pitch;
    $("#nl-slot").innerHTML = newsletterForm("accueil");

    // Instagram
    const ig = socialLinks().find((x) => x.name === "Instagram");
    const igSection = $("#instagram");
    if (!ig) igSection.hidden = true;
    else {
      $("#ig-handle").textContent = `@${ig.handle}`;
      $("#ig-follow").href = ig.href;
      $("#ig-grid").innerHTML = featured.concat(HOTELS).filter((h, i, a) => a.indexOf(h) === i).slice(0, 6).map((h) => `
        <a class="ig-tile" href="${escapeHtml(ig.href)}" target="_blank" rel="noopener" aria-label="${escapeHtml(h.name)} sur Instagram">
          <img src="${img(h.images[0], 600)}" alt="" loading="lazy">
          <span>${escapeHtml(h.city)}</span>
        </a>`).join("");
    }
  }

  /* ---------- Filtrage ---------- */
  const normalize = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

  function filtered() {
    const q = normalize(state.q.trim());
    let list = HOTELS.map((h) => ({ ...h, _dist: state.loc ? distanceKm(state.loc, h) : null }));
    list = list.filter((h) =>
      (!state.env || h.env === state.env) &&
      (!state.type || h.type === state.type) &&
      h.price <= state.max &&
      (!q || normalize([h.name, h.city, h.department, h.region, h.tagline, TYPES[h.type].label].join(" ")).includes(q)) &&
      (!state.loc || !state.radius || h._dist <= Number(state.radius))
    );
    const sorters = {
      // « Recommandés » : offres payantes d'abord (Premium, puis Partenaire), puis coups de cœur
      featured: (a, b) => planRank(b) - planRank(a) || (b.featured ? 1 : 0) - (a.featured ? 1 : 0),
      "price-asc": (a, b) => a.price - b.price,
      "price-desc": (a, b) => b.price - a.price,
      distance: (a, b) => (a._dist ?? 0) - (b._dist ?? 0),
    };
    return list.sort(sorters[state.sort] || sorters.featured);
  }

  function syncControls() {
    $("#f-q").value = state.q;
    $("#f-type").value = state.type;
    $("#f-max").value = state.max;
    $("#f-max-label").textContent = state.max >= MAX_PRICE ? "Tous prix" : formatPrice(state.max);
    $("#f-sort").value = state.sort;
    $("#f-sort").querySelector('[value="distance"]').disabled = !state.loc;
    document.querySelectorAll("#f-env button").forEach((b) => b.classList.toggle("active", b.dataset.env === state.env));
    $("#near-radius").value = state.radius;
    $("#near-radius").disabled = !state.loc;
    $("#near-clear").hidden = !state.loc;
    $("#near-input").value = state.loc ? state.loc.label : $("#near-input").value;
    $("#near-status").textContent = state.loc
      ? `Hôtels triés par distance depuis : ${state.loc.label}`
      : "Indiquez votre adresse ou votre ville pour trier les hôtels par distance.";
    $("#near-box").classList.toggle("active", !!state.loc);
  }

  function render() {
    const list = filtered();
    syncControls();
    writeUrl();
    $("#results").innerHTML = list.map(card).join("");
    $("#results-count").innerHTML = `<strong>${list.length}</strong> hôtel${list.length > 1 ? "s" : ""} extraordinaire${list.length > 1 ? "s" : ""}`;
    $("#empty").hidden = list.length > 0;
    $("#results").hidden = state.view !== "grid";
    $("#map-wrap").hidden = state.view !== "map";
    if (state.view === "map") renderMap(list);
  }

  /* ---------- Carte interactive (Leaflet + OpenStreetMap) ---------- */
  let map, markersLayer;
  function renderMap(list) {
    if (!window.L) return;
    if (!map) {
      map = L.map("map", { scrollWheelZoom: false }).setView([46.6, 2.4], 6);
      L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png", {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>',
        maxZoom: 18,
      }).addTo(map);
      markersLayer = L.layerGroup().addTo(map);
    }
    setTimeout(() => map.invalidateSize(), 50);
    markersLayer.clearLayers();
    const bounds = [];
    list.forEach((h) => {
      const icon = L.divIcon({ className: "price-pin", html: `<span>${formatPrice(h.price)}</span>`, iconSize: null });
      L.marker([h.lat, h.lng], { icon }).addTo(markersLayer).bindPopup(`
        <a class="map-pop" href="hotel.html?id=${encodeURIComponent(h.id)}">
          <img src="${img(h.images[0], 500)}" alt="">
          <strong>${escapeHtml(h.name)}</strong>
          <span>${escapeHtml(h.city)} · dès ${formatPrice(h.price)}</span>
        </a>`);
      bounds.push([h.lat, h.lng]);
    });
    if (state.loc) {
      L.marker([state.loc.lat, state.loc.lng], { icon: L.divIcon({ className: "home-pin", html: "<span>Vous</span>", iconSize: null }) }).addTo(markersLayer);
      bounds.push([state.loc.lat, state.loc.lng]);
    }
    if (bounds.length) map.fitBounds(bounds, { padding: [40, 40], maxZoom: 10 });
  }

  /* ---------- « Près de chez moi » : adresse avec autocomplétion ---------- */
  function setLocation(loc) {
    state.loc = loc;
    setUserLocation(loc);
    state.sort = loc ? "distance" : "featured";
    if (!loc) state.radius = "";
    render();
  }

  function initNear() {
    const input = $("#near-input"), list = $("#near-suggestions");
    let timer, items = [], active = -1;

    const close = () => { list.innerHTML = ""; list.classList.remove("open"); active = -1; };
    const choose = (i) => { if (items[i]) { input.value = items[i].label; close(); setLocation(items[i]); } };
    const highlight = () => list.querySelectorAll("li").forEach((li, i) => li.classList.toggle("active", i === active));

    input.addEventListener("input", () => {
      clearTimeout(timer);
      const q = input.value.trim();
      if (q.length < 3) return close();
      timer = setTimeout(async () => {
        items = await geocode(q);
        if (!items.length) {
          list.innerHTML = `<li class="none">Aucune adresse trouvée</li>`;
          list.classList.add("open");
          return;
        }
        list.innerHTML = items.map((it, i) => `<li role="option" data-i="${i}">${escapeHtml(it.label)}</li>`).join("");
        list.classList.add("open");
      }, 250);
    });
    input.addEventListener("keydown", async (e) => {
      if (e.key === "ArrowDown") { active = Math.min(active + 1, items.length - 1); highlight(); e.preventDefault(); }
      else if (e.key === "ArrowUp") { active = Math.max(active - 1, 0); highlight(); e.preventDefault(); }
      else if (e.key === "Escape") close();
      else if (e.key === "Enter") {
        e.preventDefault();
        if (active >= 0) return choose(active);
        const q = input.value.trim();
        if (!q) return;
        const res = await geocode(q, 1);
        if (res[0]) { input.value = res[0].label; close(); setLocation(res[0]); }
        else $("#near-status").textContent = "Adresse introuvable, essayez avec une ville ou un code postal.";
      }
    });
    list.addEventListener("mousedown", (e) => {
      const li = e.target.closest("li[data-i]");
      if (li) { e.preventDefault(); choose(Number(li.dataset.i)); }
    });
    input.addEventListener("blur", () => setTimeout(close, 150));

    $("#near-locate").addEventListener("click", async () => {
      $("#near-status").textContent = "Localisation en cours…";
      try { setLocation(await locateBrowser()); }
      catch (err) { $("#near-status").textContent = err.message + ". Saisissez plutôt votre adresse."; }
    });
    $("#near-clear").addEventListener("click", () => { input.value = ""; setLocation(null); });
    $("#near-radius").addEventListener("change", (e) => { state.radius = e.target.value; render(); });

    // Boutons « Près de chez moi » (en-tête, hero)
    document.addEventListener("click", (e) => {
      if (!e.target.closest("[data-open-near]")) return;
      e.preventDefault();
      $("#explorer").scrollIntoView({ behavior: "smooth" });
      setTimeout(() => input.focus({ preventScroll: true }), 500);
    });
  }

  /* ---------- Événements des filtres ---------- */
  function initFilters() {
    $("#f-q").addEventListener("input", (e) => { state.q = e.target.value; render(); });
    $("#f-type").addEventListener("change", (e) => { state.type = e.target.value; render(); });
    $("#f-max").addEventListener("input", (e) => { state.max = Number(e.target.value); render(); });
    $("#f-sort").addEventListener("change", (e) => { state.sort = e.target.value; render(); });
    $("#f-env").addEventListener("click", (e) => {
      const b = e.target.closest("button"); if (!b) return;
      state.env = b.dataset.env; render();
    });
    document.querySelectorAll(".view-toggle button").forEach((b) => b.addEventListener("click", () => {
      state.view = b.dataset.view;
      document.querySelectorAll(".view-toggle button").forEach((x) => x.classList.toggle("active", x === b));
      render();
    }));
    $("#reset").addEventListener("click", () => {
      Object.assign(state, { q: "", env: "", type: "", max: MAX_PRICE, radius: "", sort: state.loc ? "distance" : "featured" });
      render();
    });

    // Catégories : on filtre sans recharger la page
    document.addEventListener("click", (e) => {
      const a = e.target.closest("[data-env].env-tile, [data-type].type-chip");
      if (!a) return;
      e.preventDefault();
      if (a.dataset.env) { state.env = a.dataset.env; state.type = ""; }
      if (a.dataset.type) { state.type = a.dataset.type; state.env = ""; }
      render();
      $("#explorer").scrollIntoView({ behavior: "smooth" });
    });

    $("#hero-search").addEventListener("submit", (e) => {
      e.preventDefault();
      const f = new FormData(e.target);
      state.q = f.get("q") || "";
      state.env = f.get("env") || "";
      state.max = Number(f.get("max")) || MAX_PRICE;
      render();
      $("#explorer").scrollIntoView({ behavior: "smooth" });
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    readUrl();
    renderStatic();
    initFilters();
    initNear();
    render();
  });
})();
