/* Page d'accueil : diaporama, ambiances, expériences, coups de cœur, exploration, carte. */
(function () {
  const {
    escapeHtml, formatDistance, distanceKm, getUserLocation, setUserLocation, geocode, locateBrowser,
    img, planRank, newsletterForm, socialLinks, card, budgetHtml, budgetOf, observeReveal, favButton,
  } = window.NS;
  const HOTELS = window.HOTELS, ENVS = window.ENVIRONMENTS, TYPES = window.TYPES, BUDGETS = window.BUDGETS;
  const $ = (sel) => document.querySelector(sel);
  const url = (h) => `hotel.html?id=${encodeURIComponent(h.id)}`;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const state = { q: "", env: "", type: "", budget: "", sort: "featured", radius: "", view: "grid", loc: getUserLocation() };

  // Sélection mise en avant : Premium, puis coups de cœur éditoriaux
  const FEATURED = HOTELS.filter((h) => h.plan === "premium")
    .concat(HOTELS.filter((h) => h.featured && h.plan !== "premium"));
  const firstOf = (key, val) => FEATURED.find((h) => h[key] === val) || HOTELS.find((h) => h[key] === val);
  const count = (key, val) => HOTELS.filter((h) => h[key] === val).length;

  /* ---------- Filtres dans l'URL (liens partageables) ---------- */
  function readUrl() {
    const p = new URLSearchParams(location.search);
    state.q = p.get("q") || "";
    state.env = ENVS[p.get("env")] ? p.get("env") : "";
    state.type = TYPES[p.get("type")] ? p.get("type") : "";
    state.budget = BUDGETS[p.get("budget")] ? p.get("budget") : "";
    state.sort = p.get("sort") || (state.loc ? "distance" : "featured");
  }
  function writeUrl() {
    const p = new URLSearchParams();
    ["q", "env", "type", "budget"].forEach((k) => state[k] && p.set(k, state[k]));
    if (state.sort !== "featured" && state.sort !== "distance") p.set("sort", state.sort);
    const qs = p.toString();
    history.replaceState(null, "", `${location.pathname}${qs ? "?" + qs : ""}${location.hash}`);
  }

  /* ============================================================
     HERO : diaporama plein écran
     ============================================================ */
  function initHero() {
    // Diaporama : les établissements marqués « hero » (dans l'ordre), sinon la sélection
    const heroes = HOTELS.filter((h) => h.hero).sort((a, b) => a.hero - b.hero);
    const slides = (heroes.length ? heroes : FEATURED).slice(0, 6);
    const box = $("#hero-slides"), prog = $("#hero-progress"), cap = $("#hero-caption");
    box.innerHTML = slides.map((h, i) => `<div class="hero-slide ${i ? "" : "on"}" style="background-image:url('${h.images[0]}')"></div>`).join("");
    prog.innerHTML = slides.map((h, i) => `<button type="button" data-i="${i}" aria-label="${escapeHtml(h.name)}"><i></i></button>`).join("");
    let i = 0, timer;
    const DURATION = 6500;
    const show = (n) => {
      i = (n + slides.length) % slides.length;
      box.querySelectorAll(".hero-slide").forEach((s, k) => s.classList.toggle("on", k === i));
      prog.querySelectorAll("button").forEach((b, k) => { b.classList.toggle("on", k === i); b.classList.toggle("done", k < i); });
      const h = slides[i];
      cap.href = url(h);
      cap.innerHTML = `<span>${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)}</span><strong>${escapeHtml(h.name)}</strong><em>${escapeHtml(h.city)} · ${escapeHtml(h.region)} →</em>`;
      cap.classList.remove("swap"); void cap.offsetWidth; cap.classList.add("swap");
      clearTimeout(timer);
      if (!reduceMotion) timer = setTimeout(() => show(i + 1), DURATION);
    };
    prog.addEventListener("click", (e) => { const b = e.target.closest("button"); if (b) show(Number(b.dataset.i)); });
    document.addEventListener("visibilitychange", () => { if (document.hidden) clearTimeout(timer); else show(i); });
    // Précharge les images suivantes
    slides.slice(1).forEach((h) => { const im = new Image(); im.src = h.images[0]; });
    show(0);

    // Recherche avec suggestions (hôtels, villes, régions)
    const input = $("#hero-q"), list = $("#hero-suggestions");
    const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    input.addEventListener("input", () => {
      const q = norm(input.value.trim());
      if (q.length < 2) { list.classList.remove("open"); return; }
      const hotels = HOTELS.filter((h) => norm(`${h.name} ${h.city}`).includes(q)).slice(0, 5);
      const regions = [...new Set(HOTELS.map((h) => h.region))].filter((r) => norm(r).includes(q)).slice(0, 3);
      const items = [
        ...regions.map((r) => `<li data-q="${escapeHtml(r)}"><span class="sg-icon">🗺</span><span><strong>${escapeHtml(r)}</strong><small>${HOTELS.filter((h) => h.region === r).length} établissements</small></span></li>`),
        ...hotels.map((h) => `<li data-href="${url(h)}"><img src="${img(h.images[0], 400)}" alt=""><span><strong>${escapeHtml(h.name)}</strong><small>${escapeHtml(h.city)} · ${escapeHtml(TYPES[h.type].label)}</small></span></li>`),
      ];
      list.innerHTML = items.join("") || `<li class="none">Rien trouvé… essayez « Bretagne » ou « cabane »</li>`;
      list.classList.add("open");
    });
    list.addEventListener("mousedown", (e) => {
      const li = e.target.closest("li");
      if (!li || li.classList.contains("none")) return;
      e.preventDefault();
      if (li.dataset.href) location.href = li.dataset.href;
      else { input.value = li.dataset.q; list.classList.remove("open"); $("#hero-search").requestSubmit(); }
    });
    input.addEventListener("blur", () => setTimeout(() => list.classList.remove("open"), 150));

    $("#hero-env").insertAdjacentHTML("beforeend", Object.entries(ENVS).map(([k, e]) => `<option value="${k}">${escapeHtml(e.label)}</option>`).join(""));
    $("#hero-budget").insertAdjacentHTML("beforeend", Object.entries(BUDGETS).map(([k, b]) => `<option value="${k}">${"€".repeat(k)} — ${escapeHtml(b.range)}</option>`).join(""));
    $("#hero-search").addEventListener("submit", (e) => {
      e.preventDefault();
      const f = new FormData(e.target);
      Object.assign(state, { q: f.get("q") || "", env: f.get("env") || "", budget: f.get("budget") || "", type: "" });
      render();
      $("#explorer").scrollIntoView({ behavior: "smooth" });
    });
  }

  /* ============================================================
     SECTIONS DE DÉCOUVERTE
     ============================================================ */
  function renderDiscovery() {
    // Bandeau défilant
    const words = Object.values(TYPES).map((t) => `<span>${t.icon} ${escapeHtml(t.label)}</span><i>✦</i>`).join("");
    $("#marquee").innerHTML = words + words;

    // Ambiances en accordéon
    $("#env-grid").innerHTML = Object.entries(ENVS).map(([k, e], i) => {
      const h = HOTELS.find((x) => x.id === e.cover) || firstOf("env", k);
      return `
        <a class="env-panel ${i === 0 ? "active" : ""}" href="?env=${k}#explorer" data-env="${k}">
          <img src="${h ? h.images[0] : ""}" alt="" loading="lazy">
          <div class="env-panel-text">
            <span class="env-count">${count("env", k)} adresses</span>
            <h3>${escapeHtml(e.label)}</h3>
            <p>${escapeHtml(e.desc)}</p>
            <span class="env-go">Explorer →</span>
          </div>
        </a>`;
    }).join("");
    document.querySelectorAll(".env-panel").forEach((p) => p.addEventListener("mouseenter", () => {
      document.querySelectorAll(".env-panel").forEach((x) => x.classList.toggle("active", x === p));
    }));

    // Rail des expériences
    $("#type-rail").innerHTML = Object.entries(TYPES).filter(([k]) => count("type", k)).map(([k, t]) => {
      const h = firstOf("type", k);
      return `
        <a class="type-card" href="?type=${k}#explorer" data-type="${k}">
          <img src="${img(h.images[0], 900)}" alt="" loading="lazy">
          <div class="type-card-text">
            <span class="type-card-icon">${t.icon}</span>
            <h3>${escapeHtml(t.label)}</h3>
            <p>${count("type", k)} lieu${count("type", k) > 1 ? "x" : ""} · ${escapeHtml(h.name)}${count("type", k) > 1 ? "…" : ""}</p>
          </div>
        </a>`;
    }).join("");
    document.querySelectorAll("[data-rail]").forEach((b) => b.addEventListener("click", () => {
      const rail = document.getElementById(b.dataset.rail);
      rail.scrollBy({ left: Number(b.dataset.dir) * rail.clientWidth * 0.8, behavior: "smooth" });
    }));

    // Projecteur sur les coups de cœur
    initSpotlight();

    // Newsletter
    const nl = window.SITE_CONFIG.newsletter;
    $("#nl-title").textContent = nl.title;
    $("#nl-pitch").textContent = nl.pitch;
    $("#nl-slot").innerHTML = newsletterForm("accueil");

    // Instagram
    const ig = socialLinks().find((x) => x.name === "Instagram");
    if (!ig) $("#instagram").hidden = true;
    else {
      $("#ig-handle").textContent = `@${ig.handle}`;
      $("#ig-follow").href = ig.href;
      const picks = FEATURED.concat(HOTELS).filter((h, i, a) => a.indexOf(h) === i).slice(0, 6);
      $("#ig-grid").innerHTML = picks.map((h, i) => `
        <a class="ig-tile" href="${escapeHtml(ig.href)}" target="_blank" rel="noopener" aria-label="${escapeHtml(h.name)} sur Instagram">
          <img src="${img(h.images[Math.min(1, h.images.length - 1)] || h.images[0], 600)}" alt="" loading="lazy">
          <span>${escapeHtml(h.name)}</span>
        </a>`).join("");
    }
  }

  function initSpotlight() {
    const list = FEATURED.slice(0, 6);
    const box = $("#spotlight-box");
    box.innerHTML = `
      <div class="spot-media">${list.map((h, i) => `<img class="${i ? "" : "on"}" src="${h.images[0]}" alt="${escapeHtml(h.name)}" loading="lazy">`).join("")}</div>
      <div class="spot-body">
        <div class="spot-text" aria-live="polite"></div>
        <div class="spot-thumbs">${list.map((h, i) => `
          <button type="button" class="${i ? "" : "on"}" data-i="${i}" aria-label="${escapeHtml(h.name)}">
            <img src="${img(h.images[0], 400)}" alt=""><i></i>
          </button>`).join("")}</div>
      </div>`;
    let i = 0, timer;
    const show = (n) => {
      i = (n + list.length) % list.length;
      const h = list[i];
      box.querySelectorAll(".spot-media img").forEach((im, k) => im.classList.toggle("on", k === i));
      box.querySelectorAll(".spot-thumbs button").forEach((b, k) => b.classList.toggle("on", k === i));
      box.querySelector(".spot-text").innerHTML = `
        <p class="card-type">${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)} · ${escapeHtml(ENVS[h.env].label)}</p>
        <h3>${escapeHtml(h.name)}</h3>
        <p class="spot-place">📍 ${escapeHtml(h.city)}, ${escapeHtml(h.region)}</p>
        <p class="spot-desc">${escapeHtml(h.description[0])}</p>
        <ul class="spot-hl">${h.highlights.slice(0, 3).map((x) => `<li>${escapeHtml(x)}</li>`).join("")}</ul>
        <div class="spot-cta">
          <a class="btn btn-primary" href="${url(h)}">Découvrir</a>
          ${favButton(h, "fav-lg")}
          ${budgetHtml(h)}
        </div>`;
      const t = box.querySelector(".spot-text");
      t.classList.remove("swap"); void t.offsetWidth; t.classList.add("swap");
      clearTimeout(timer);
      if (!reduceMotion) timer = setTimeout(() => show(i + 1), 8000);
    };
    box.querySelector(".spot-thumbs").addEventListener("click", (e) => { const b = e.target.closest("button"); if (b) show(Number(b.dataset.i)); });
    box.addEventListener("mouseenter", () => { clearTimeout(timer); box.classList.add("paused"); });
    box.addEventListener("mouseleave", () => { box.classList.remove("paused"); show(i); });
    show(0);
  }

  /* ============================================================
     EXPLORATION : filtres, galerie, carte
     ============================================================ */
  const normalize = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

  function filtered() {
    const q = normalize(state.q.trim());
    let list = HOTELS.map((h) => ({ h, dist: state.loc ? distanceKm(state.loc, h) : null }));
    list = list.filter(({ h, dist }) =>
      (!state.env || h.env === state.env) &&
      (!state.type || h.type === state.type) &&
      (!state.budget || String(h.budget) === state.budget) &&
      (!q || normalize([h.name, h.city, h.department, h.region, h.tagline, TYPES[h.type].label, ENVS[h.env].label].join(" ")).includes(q)) &&
      (!state.loc || !state.radius || dist <= Number(state.radius))
    );
    const sorters = {
      // « Recommandés » : offres payantes d'abord (Premium, puis Partenaire), puis coups de cœur
      featured: (a, b) => planRank(b.h) - planRank(a.h) || (b.h.featured ? 1 : 0) - (a.h.featured ? 1 : 0),
      "budget-asc": (a, b) => a.h.budget - b.h.budget,
      "budget-desc": (a, b) => b.h.budget - a.h.budget,
      distance: (a, b) => (a.dist ?? 0) - (b.dist ?? 0),
      name: (a, b) => a.h.name.localeCompare(b.h.name, "fr"),
    };
    return list.sort(sorters[state.sort] || sorters.featured);
  }

  function renderFilterControls() {
    $("#f-env").innerHTML = `<button type="button" data-env="">Tout</button>` +
      Object.entries(ENVS).map(([k, e]) => `<button type="button" data-env="${k}">${escapeHtml(e.label)}</button>`).join("");
    $("#f-budget").innerHTML = `<button type="button" data-budget="">Tout budget</button>` +
      Object.entries(BUDGETS).map(([k, b]) => `<button type="button" data-budget="${k}" title="${escapeHtml(b.range)}">${"€".repeat(k)}</button>`).join("");
    $("#f-type").innerHTML = Object.entries(TYPES).filter(([k]) => count("type", k))
      .map(([k, t]) => `<button type="button" data-type="${k}">${t.icon} ${escapeHtml(t.label)}</button>`).join("");
  }

  function syncControls(n) {
    $("#f-q").value = state.q;
    $("#f-sort").value = state.sort;
    $("#f-sort").querySelector('[value="distance"]').disabled = !state.loc;
    document.querySelectorAll("#f-env button").forEach((b) => b.classList.toggle("active", b.dataset.env === state.env));
    document.querySelectorAll("#f-budget button").forEach((b) => b.classList.toggle("active", b.dataset.budget === state.budget));
    document.querySelectorAll("#f-type button").forEach((b) => b.classList.toggle("active", b.dataset.type === state.type));
    $("#near-radius").value = state.radius;
    $("#near-radius").disabled = !state.loc;
    $("#near-clear").hidden = !state.loc;
    if (state.loc) $("#near-input").value = state.loc.label;
    $("#near-status").textContent = state.loc
      ? `Triés par distance depuis : ${state.loc.label}`
      : "Indiquez votre adresse ou votre ville : on trie tout par distance.";
    $("#near-box").classList.toggle("active", !!state.loc);
    const active = state.q || state.env || state.type || state.budget || state.radius;
    $("#reset-top").hidden = !active;
    $("#results-count").innerHTML = `<strong>${n}</strong> établissement${n > 1 ? "s" : ""} extraordinaire${n > 1 ? "s" : ""}` +
      (state.type ? ` · ${escapeHtml(TYPES[state.type].label)}` : "") + (state.env ? ` · ${escapeHtml(ENVS[state.env].label)}` : "");
  }

  let lastKey = "";
  function render() {
    const list = filtered();
    syncControls(list.length);
    writeUrl();
    $("#empty").hidden = list.length > 0;
    $("#results").hidden = state.view !== "grid";
    $("#map-wrap").hidden = state.view !== "map";

    // On ne reconstruit la galerie que si le résultat a changé (préserve les diaporamas en cours)
    const key = list.map(({ h, dist }) => h.id + (dist != null ? Math.round(dist) : "")).join("|") + state.view;
    if (key === lastKey) return;
    lastKey = key;
    if (state.view === "grid") {
      const grid = $("#results");
      grid.classList.remove("refresh"); void grid.offsetWidth; grid.classList.add("refresh");
      grid.innerHTML = list.map(({ h, dist }) => card(h, { dist, reveal: false })).join("");
    } else renderMap(list);
  }

  /* ---------- Carte interactive : liste + carte synchronisées ---------- */
  let map, markers = {};
  function renderMap(list) {
    $("#split-list").innerHTML = list.map(({ h, dist }) => `
      <a class="split-item" href="${url(h)}" data-id="${h.id}">
        <img src="${img(h.images[0], 400)}" alt="" loading="lazy">
        <span>
          <small>${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)}</small>
          <strong>${escapeHtml(h.name)}</strong>
          <em>${escapeHtml(h.city)}${dist != null ? ` · ${formatDistance(dist)}` : ""} · ${"€".repeat(h.budget)}</em>
        </span>
      </a>`).join("");
    if (!window.L) return;
    if (!map) {
      map = L.map("map", { scrollWheelZoom: true, zoomControl: true }).setView([46.6, 2.4], 6);
      L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png", {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>',
        maxZoom: 18,
      }).addTo(map);
    }
    setTimeout(() => map.invalidateSize(), 60);
    Object.values(markers).forEach((m) => m.remove());
    markers = {};
    const bounds = [];
    list.forEach(({ h }) => {
      const icon = L.divIcon({ className: "photo-pin", html: `<span style="background-image:url('${img(h.images[0], 400)}')"></span>`, iconSize: [46, 46], iconAnchor: [23, 23] });
      const m = L.marker([h.lat, h.lng], { icon, riseOnHover: true }).addTo(map).bindPopup(`
        <a class="map-pop" href="${url(h)}">
          <img src="${img(h.images[0], 400)}" alt="">
          <strong>${escapeHtml(h.name)}</strong>
          <span>${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)} · ${escapeHtml(h.city)}</span>
        </a>`, { closeButton: false });
      m.on("mouseover", () => highlight(h.id, true));
      m.on("mouseout", () => highlight(h.id, false));
      m.on("click", () => document.querySelector(`.split-item[data-id="${h.id}"]`)?.scrollIntoView({ block: "nearest", behavior: "smooth" }));
      markers[h.id] = m;
      bounds.push([h.lat, h.lng]);
    });
    if (state.loc) {
      markers.__home = L.marker([state.loc.lat, state.loc.lng], { icon: L.divIcon({ className: "home-pin", html: "<span>Vous</span>", iconSize: null }) }).addTo(map);
      bounds.push([state.loc.lat, state.loc.lng]);
    }
    if (bounds.length) map.fitBounds(bounds, { padding: [50, 50], maxZoom: 10 });
    document.querySelectorAll(".split-item").forEach((el) => {
      el.addEventListener("mouseenter", () => { highlight(el.dataset.id, true); markers[el.dataset.id]?.openPopup(); });
      el.addEventListener("mouseleave", () => highlight(el.dataset.id, false));
    });
  }
  function highlight(id, on) {
    markers[id]?.getElement()?.classList.toggle("hot", on);
    document.querySelector(`.split-item[data-id="${id}"]`)?.classList.toggle("hot", on);
  }

  /* ---------- « Près de chez moi » ---------- */
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
    const hl = () => list.querySelectorAll("li").forEach((li, i) => li.classList.toggle("active", i === active));

    input.addEventListener("input", () => {
      clearTimeout(timer);
      const q = input.value.trim();
      if (q.length < 3) return close();
      timer = setTimeout(async () => {
        items = await geocode(q);
        list.innerHTML = items.length
          ? items.map((it, i) => `<li role="option" data-i="${i}">${escapeHtml(it.label)}</li>`).join("")
          : `<li class="none">Aucune adresse trouvée</li>`;
        list.classList.add("open");
      }, 250);
    });
    input.addEventListener("keydown", async (e) => {
      if (e.key === "ArrowDown") { active = Math.min(active + 1, items.length - 1); hl(); e.preventDefault(); }
      else if (e.key === "ArrowUp") { active = Math.max(active - 1, 0); hl(); e.preventDefault(); }
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
    document.addEventListener("click", (e) => {
      if (!e.target.closest("[data-open-near]")) return;
      e.preventDefault();
      $("#explorer").scrollIntoView({ behavior: "smooth" });
      setTimeout(() => input.focus({ preventScroll: true }), 600);
    });
  }

  function initFilters() {
    let t;
    $("#f-q").addEventListener("input", (e) => { clearTimeout(t); t = setTimeout(() => { state.q = e.target.value; render(); }, 120); });
    $("#f-sort").addEventListener("change", (e) => { state.sort = e.target.value; render(); });
    $("#filters").addEventListener("click", (e) => {
      const b = e.target.closest("button");
      if (!b) return;
      if ("env" in b.dataset) state.env = b.dataset.env;
      if ("budget" in b.dataset) state.budget = b.dataset.budget;
      if ("type" in b.dataset) state.type = state.type === b.dataset.type ? "" : b.dataset.type;
      render();
    });
    document.querySelectorAll(".view-toggle button").forEach((b) => b.addEventListener("click", () => {
      state.view = b.dataset.view;
      document.querySelectorAll(".view-toggle button").forEach((x) => x.classList.toggle("active", x === b));
      render();
    }));
    const reset = () => { Object.assign(state, { q: "", env: "", type: "", budget: "", radius: "", sort: state.loc ? "distance" : "featured" }); render(); };
    $("#reset").addEventListener("click", reset);
    $("#reset-top").addEventListener("click", reset);

    // Ambiances et expériences : on filtre sans recharger la page
    document.addEventListener("click", (e) => {
      const a = e.target.closest(".env-panel, .type-card");
      if (!a) return;
      e.preventDefault();
      Object.assign(state, { env: a.dataset.env || "", type: a.dataset.type || "", q: "", budget: "" });
      render();
      $("#explorer").scrollIntoView({ behavior: "smooth" });
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    readUrl();
    initHero();
    renderDiscovery();
    renderFilterControls();
    initFilters();
    initNear();
    render();
    observeReveal();
  });
})();
