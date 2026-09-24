/* Carte interactive de tous les établissements (carte.html). */
(function () {
  const {
    escapeHtml, img, hotelUrl, budgetHtml, budgetOf, favButton, distanceKm, formatDistance,
    getUserLocation, setUserLocation, locateBrowser,
  } = window.NS;
  const HOTELS = window.HOTELS, ENVS = window.ENVIRONMENTS, TYPES = window.TYPES;
  const $ = (s) => document.querySelector(s);
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const isMobile = () => window.matchMedia("(max-width: 760px)").matches;

  const FRANCE = [[41.3, -5.2], [51.2, 9.6]];
  const state = { q: "", env: "", type: "", tag: "", selected: null, loc: getUserLocation() };

  /* ---------- Fonds de carte : voir baseLayer() dans core.js ---------- */
  const LAYERS = { plan: () => window.NS.baseLayer("plan"), satellite: () => window.NS.baseLayer("satellite"), nuit: () => window.NS.baseLayer("nuit") };

  let map, cluster, base, homeMarker;
  const markers = new Map();

  const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  function visible() {
    const q = norm(state.q.trim());
    let list = HOTELS.filter((h) =>
      (!state.env || h.env === state.env) &&
      (!state.type || h.type === state.type) &&
      (!state.tag || window.NS.tagsOf(h).includes(state.tag)) &&
      (!q || norm([h.name, h.city, h.department, h.region, h.tagline, TYPES[h.type].label, ENVS[h.env].label].join(" ")).includes(q)));
    if (state.loc) list = list.slice().sort((a, b) => distanceKm(state.loc, a) - distanceKm(state.loc, b));
    else list = list.slice().sort((a, b) => a.name.localeCompare(b.name, "fr"));
    return list;
  }

  /* ---------- Repères : la photo du lieu dans un médaillon ---------- */
  function pinIcon(h) {
    return L.divIcon({
      className: "atlas-pin",
      html: `<span class="atlas-pin-photo" style="background-image:url('${img(h.images[0], 400)}')"></span><span class="atlas-pin-label">${escapeHtml(h.name)}</span>`,
      iconSize: [52, 52],
      iconAnchor: [26, 26],
    });
  }
  function clusterIcon(c) {
    const children = c.getAllChildMarkers();
    const photos = children.slice(0, 3).map((m) => `<i style="background-image:url('${img(m.options.hotel.images[0], 400)}')"></i>`).join("");
    const n = c.getChildCount();
    const size = n < 5 ? 62 : n < 10 ? 70 : 80;
    return L.divIcon({
      className: "atlas-cluster",
      html: `<span class="atlas-cluster-photos">${photos}</span><b>${n}</b>`,
      iconSize: [size, size],
      iconAnchor: [size / 2, size / 2],
    });
  }

  function buildMap() {
    map = L.map("atlas-map", {
      zoomControl: false,
      minZoom: 4,
      maxBounds: [[35, -15], [56, 20]],
      maxBoundsViscosity: 0.8,
      worldCopyJump: false,
      tap: true,
    });
    L.control.zoom({ position: "bottomright", zoomInTitle: "Zoomer", zoomOutTitle: "Dézoomer" }).addTo(map);
    L.control.scale({ position: "bottomleft", imperial: false }).addTo(map);
    base = LAYERS.plan().addTo(map);
    fitFrance(false);

    cluster = L.markerClusterGroup({
      showCoverageOnHover: false,
      spiderfyOnMaxZoom: true,
      maxClusterRadius: 48,
      iconCreateFunction: clusterIcon,
      animate: !reduceMotion,
    });
    HOTELS.forEach((h) => {
      const m = L.marker([h.lat, h.lng], { icon: pinIcon(h), hotel: h, title: h.name, alt: h.name, riseOnHover: true, keyboard: true });
      m.on("click", () => select(h.id, { fly: true }));
      m.on("mouseover", () => hoverList(h.id, true));
      m.on("mouseout", () => hoverList(h.id, false));
      markers.set(h.id, m);
    });
    map.addLayer(cluster);
    map.on("click", () => { if (state.selected) deselect(); });
    map.on("zoomend", () => $("#atlas-map").classList.toggle("show-labels", map.getZoom() >= 9));
    if (state.loc) showHome();
  }

  function fitFrance(animate = true) {
    const pad = isMobile() ? [30, 30] : [40, 40];
    const leftPad = !isMobile() && document.getElementById("atlas-panel") ? 420 : 0;
    map.fitBounds(FRANCE, { paddingTopLeft: [pad[0] + leftPad, pad[1]], paddingBottomRight: pad, animate });
  }

  function showHome() {
    if (homeMarker) homeMarker.remove();
    if (!state.loc) return;
    homeMarker = L.marker([state.loc.lat, state.loc.lng], {
      icon: L.divIcon({ className: "home-pin", html: "<span>Vous</span>", iconSize: null }),
      interactive: false,
      zIndexOffset: 1000,
    }).addTo(map);
  }

  /* ---------- Liste et filtres ---------- */
  function renderFilters() {
    $("#atlas-env").innerHTML = `<button type="button" data-env="">Tout</button>` +
      Object.entries(ENVS).map(([k, e]) => `<button type="button" data-env="${k}">${escapeHtml(e.label)}</button>`).join("");
    const used = new Set(HOTELS.map((h) => h.type));
    $("#atlas-types").innerHTML = Object.entries(TYPES).filter(([k]) => used.has(k))
      .map(([k, t]) => `<button type="button" data-type="${k}">${t.icon} ${escapeHtml(t.label)}</button>`).join("") +
      Object.entries(window.TAGS).filter(([k]) => HOTELS.some((h) => window.NS.tagsOf(h).includes(k)))
        .map(([k, t]) => `<button type="button" class="is-tag" data-tag="${k}">${t.icon} ${escapeHtml(t.short)}</button>`).join("");
  }
  function syncFilters() {
    document.querySelectorAll("#atlas-env button").forEach((b) => b.classList.toggle("active", b.dataset.env === state.env));
    document.querySelectorAll("#atlas-types button[data-type]").forEach((b) => b.classList.toggle("active", b.dataset.type === state.type));
    document.querySelectorAll("#atlas-types button[data-tag]").forEach((b) => b.classList.toggle("active", b.dataset.tag === state.tag));
  }

  function render({ refit = false } = {}) {
    const list = visible();
    syncFilters();
    $("#atlas-count").textContent = `${list.length} lieu${list.length > 1 ? "x" : ""} extraordinaire${list.length > 1 ? "s" : ""}${state.loc ? " · triés par distance" : ""}`;
    $("#atlas-list").innerHTML = list.length
      ? list.map((h) => `
        <li>
          <a class="atlas-item${h.id === state.selected ? " active" : ""}" href="${hotelUrl(h)}" data-id="${h.id}">
            <img src="${img(h.images[0], 400)}" alt="" loading="lazy" decoding="async">
            <span>
              <small>${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)}</small>
              <strong>${escapeHtml(h.name)}</strong>
              <em>${escapeHtml(h.city)}${state.loc ? ` · ${formatDistance(distanceKm(state.loc, h))}` : ` · ${escapeHtml(h.region)}`}</em>
            </span>
          </a>
        </li>`).join("")
      : `<li class="atlas-empty">Aucun lieu ne correspond. <button type="button" class="btn-text" id="atlas-clear">Tout afficher</button></li>`;

    const ids = new Set(list.map((h) => h.id));
    cluster.clearLayers();
    cluster.addLayers(list.map((h) => markers.get(h.id)));
    if (state.selected && !ids.has(state.selected)) deselect();
    if (refit && list.length) {
      const bounds = L.latLngBounds(list.map((h) => [h.lat, h.lng]));
      const leftPad = isMobile() ? 0 : 420;
      map.flyToBounds(bounds, { paddingTopLeft: [40 + leftPad, 60], paddingBottomRight: [40, 60], maxZoom: 9, duration: reduceMotion ? 0 : 0.9 });
    }
  }

  function hoverList(id, on) {
    const el = document.querySelector(`.atlas-item[data-id="${id}"]`);
    if (el) el.classList.toggle("hot", on);
  }
  function hoverPin(id, on) {
    const m = markers.get(id);
    const el = m && m.getElement();
    if (el) el.classList.toggle("hot", on);
  }

  /* ---------- Sélection d'un lieu ---------- */
  function select(id, { fly = true } = {}) {
    const h = HOTELS.find((x) => x.id === id);
    if (!h) return;
    state.selected = id;
    document.querySelectorAll(".atlas-pin.selected").forEach((el) => el.classList.remove("selected"));
    document.querySelectorAll(".atlas-item.active").forEach((el) => el.classList.remove("active"));
    const item = document.querySelector(`.atlas-item[data-id="${id}"]`);
    if (item) { item.classList.add("active"); item.scrollIntoView({ block: "nearest", behavior: reduceMotion ? "auto" : "smooth" }); }

    const marker = markers.get(id);
    const T = TYPES[h.type];
    const card = $("#atlas-card");
    card.innerHTML = `
      <button type="button" class="atlas-card-close" aria-label="Fermer l'aperçu">×</button>
      <a class="atlas-card-media" href="${hotelUrl(h)}">
        <img src="${img(h.images[0], 900)}" alt="${escapeHtml(h.name)}">
        <span class="badge">${escapeHtml(ENVS[h.env].label)}</span>
      </a>
      ${favButton(h)}
      <div class="atlas-card-body">
        <p class="card-type">${T.icon} ${escapeHtml(T.label)}</p>
        <h2>${escapeHtml(h.name)}</h2>
        <p class="card-place">📍 ${escapeHtml(h.city)}, ${escapeHtml(h.region)}${state.loc ? ` · à ${formatDistance(distanceKm(state.loc, h))}` : ""}</p>
        <p class="atlas-card-tagline">${escapeHtml(h.tagline)}</p>
        <div class="atlas-card-foot">
          <span>${budgetHtml(h)} <small>${escapeHtml(budgetOf(h).range)}</small></span>
          <a class="btn btn-primary" href="${hotelUrl(h)}">Découvrir</a>
        </div>
      </div>`;
    card.hidden = false;
    card.classList.remove("in"); void card.offsetWidth; card.classList.add("in");
    card.querySelector(".atlas-card-close").addEventListener("click", deselect);

    const go = () => {
      const el = marker.getElement();
      if (el) el.classList.add("selected");
    };
    if (fly) {
      const zoom = Math.max(map.getZoom(), 10);
      const target = map.project([h.lat, h.lng], zoom);
      // Décale le centre pour que le lieu ne soit pas caché par le panneau ou l'aperçu
      // Sur mobile, le lieu se place dans la zone libre au-dessus de l'aperçu
      const offset = isMobile() ? L.point(0, Math.round(map.getSize().y * 0.2)) : L.point(-190, 0);
      const center = map.unproject(target.add(offset), zoom);
      map.flyTo(center, zoom, { duration: reduceMotion ? 0 : 1.1 });
      map.once("moveend", () => cluster.zoomToShowLayer(marker, go));
    } else cluster.zoomToShowLayer(marker, go);
    if (isMobile()) { $(".atlas").classList.remove("open"); $(".atlas").classList.add("peek"); }
    const url = new URL(location.href);
    url.searchParams.set("h", id);
    history.replaceState(null, "", url);
  }
  function deselect() {
    state.selected = null;
    const card = $("#atlas-card");
    card.hidden = true;
    $(".atlas").classList.remove("peek");
    document.querySelectorAll(".atlas-pin.selected").forEach((el) => el.classList.remove("selected"));
    document.querySelectorAll(".atlas-item.active").forEach((el) => el.classList.remove("active"));
    const url = new URL(location.href);
    url.searchParams.delete("h");
    history.replaceState(null, "", url);
  }

  /* ---------- Événements ---------- */
  function initEvents() {
    let t;
    $("#atlas-q").addEventListener("input", (e) => {
      clearTimeout(t);
      t = setTimeout(() => { state.q = e.target.value; render({ refit: true }); }, 180);
    });
    $("#atlas-env").addEventListener("click", (e) => {
      const b = e.target.closest("button"); if (!b) return;
      state.env = b.dataset.env; render({ refit: true });
    });
    $("#atlas-types").addEventListener("click", (e) => {
      const b = e.target.closest("button"); if (!b) return;
      if ("tag" in b.dataset) state.tag = state.tag === b.dataset.tag ? "" : b.dataset.tag;
      else state.type = state.type === b.dataset.type ? "" : b.dataset.type;
      render({ refit: true });
    });
    $("#atlas-list").addEventListener("click", (e) => {
      if (e.target.closest("#atlas-clear")) {
        Object.assign(state, { q: "", env: "", type: "", tag: "" });
        $("#atlas-q").value = "";
        render({ refit: true });
        return;
      }
      const a = e.target.closest(".atlas-item");
      if (!a) return;
      // Un premier clic montre le lieu sur la carte, un second ouvre sa fiche
      if (state.selected !== a.dataset.id) { e.preventDefault(); select(a.dataset.id); }
    });
    $("#atlas-list").addEventListener("mouseover", (e) => {
      const a = e.target.closest(".atlas-item");
      if (a) hoverPin(a.dataset.id, true);
    });
    $("#atlas-list").addEventListener("mouseout", (e) => {
      const a = e.target.closest(".atlas-item");
      if (a) hoverPin(a.dataset.id, false);
    });
    $("#atlas-layers").addEventListener("click", (e) => {
      const b = e.target.closest("button[data-layer]"); if (!b) return;
      map.removeLayer(base);
      base = LAYERS[b.dataset.layer]().addTo(map);
      document.querySelectorAll("#atlas-layers button").forEach((x) => { x.classList.toggle("active", x === b); x.setAttribute("aria-checked", x === b); });
      $("#atlas-map").dataset.layer = b.dataset.layer;
    });
    $("#atlas-reset").addEventListener("click", () => { deselect(); fitFrance(true); });
    $("#atlas-locate").addEventListener("click", async () => {
      const btn = $("#atlas-locate");
      btn.classList.add("busy");
      try {
        const loc = state.loc || await locateBrowser();
        state.loc = loc;
        setUserLocation(loc);
        showHome();
        render();
        map.flyTo([loc.lat, loc.lng], 7, { duration: reduceMotion ? 0 : 1 });
      } catch (err) {
        $("#atlas-count").textContent = `${err.message}. Vous pouvez indiquer votre adresse sur la page d'accueil.`;
      } finally {
        btn.classList.remove("busy");
      }
    });
    $("#atlas-handle").addEventListener("click", () => {
      const atlas = $(".atlas");
      if (atlas.classList.contains("peek")) { atlas.classList.remove("peek"); return; }
      atlas.classList.toggle("open");
    });
    document.addEventListener("keydown", (e) => { if (e.key === "Escape" && state.selected) deselect(); });
    // Le bouton « Surprenez-moi » de la carte montre le lieu tiré au sort sur la carte
    document.addEventListener("click", (e) => {
      const go = e.target.closest("#surprise a.btn");
      if (!go || !document.body.classList.contains("map-page")) return;
      const id = document.getElementById("surprise").dataset.pick;
      if (!id) return;
      e.preventDefault();
      document.getElementById("surprise").querySelector(".surprise-close").click();
      Object.assign(state, { q: "", env: "", type: "" });
      $("#atlas-q").value = "";
      render();
      select(id);
    }, true);
    window.addEventListener("resize", () => map.invalidateSize());
  }

  document.addEventListener("DOMContentLoaded", () => {
    if (!window.L || !L.markerClusterGroup) {
      $("#atlas-map").innerHTML = `<p class="atlas-error">La carte n'a pas pu se charger. Rechargez la page.</p>`;
      return;
    }
    const p = new URLSearchParams(location.search);
    if (ENVS[p.get("env")]) state.env = p.get("env");
    if (TYPES[p.get("type")]) state.type = p.get("type");
    buildMap();
    renderFilters();
    initEvents();
    render({ refit: !!(state.env || state.type) });
    const id = p.get("h");
    if (id && HOTELS.some((h) => h.id === id)) setTimeout(() => select(id), 300);
  });
})();
