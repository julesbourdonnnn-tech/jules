/* Comportements partagés par toutes les pages (navigateur). */
(function () {
  const C = window.NSCore;
  const CONFIG = window.SITE_CONFIG;
  const { escapeHtml, img } = C;

  // Une seule adresse pour Google : www.nuitsinguliere.com → nuitsinguliere.com
  if (location.hostname.startsWith("www.")) {
    location.replace(location.href.replace("//www.", "//"));
    return;
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
  const bookingLink = (h) => C.bookingLink(h, getSource());

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

  /* ---------- Formulaires (Netlify Forms) ---------- */
  async function submitForm(form) {
    if (location.protocol === "file:") throw new Error("hors ligne");
    const body = new URLSearchParams(new FormData(form)).toString();
    const res = await fetch("/", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body });
    if (!res.ok) throw new Error(String(res.status));
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
      track(form.getAttribute("name") === "newsletter" ? "Newsletter" : "Formulaire", { source: getSource() || "direct" });
      form.reset();
    } catch {
      msg.textContent = location.protocol === "file:"
        ? "Les formulaires fonctionneront une fois le site mis en ligne."
        : "Oups, l'envoi a échoué. Réessayez dans un instant.";
    } finally {
      btn.disabled = false;
    }
  });

  /* ---------- Position de l'utilisateur (mémorisée entre les pages) ---------- */
  const LOC_KEY = "ns-user-location";
  function getUserLocation() {
    try { return JSON.parse(localStorage.getItem(LOC_KEY)) || null; } catch { return null; }
  }
  function setUserLocation(loc) {
    try { loc ? localStorage.setItem(LOC_KEY, JSON.stringify(loc)) : localStorage.removeItem(LOC_KEY); } catch { /* navigation privée */ }
  }

  // Géocodage d'adresses françaises via le service public de l'IGN (gratuit, sans clé)
  const GEOCODERS = ["https://data.geopf.fr/geocodage/search", "https://api-adresse.data.gouv.fr/search/"];
  async function geocode(query, limit = 5) {
    for (const base of GEOCODERS) {
      try {
        const res = await fetch(`${base}?q=${encodeURIComponent(query)}&limit=${limit}`);
        if (!res.ok) continue;
        const json = await res.json();
        return (json.features || []).map((f) => ({
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

  /* ---------- Photo de secours si une image ne charge pas ---------- */
  document.addEventListener("error", (e) => {
    const t = e.target;
    if (t && t.tagName === "IMG" && t.src !== C.FALLBACK) t.src = C.FALLBACK;
  }, true);

  /* ---------- Favoris (mémorisés dans le navigateur) ---------- */
  const FAV_KEY = "ns-favs";
  function getFavs() {
    try { return JSON.parse(localStorage.getItem(FAV_KEY)) || []; } catch { return []; }
  }
  const isFav = (id) => getFavs().includes(id);
  function toggleFav(id) {
    const favs = getFavs();
    const i = favs.indexOf(id);
    if (i >= 0) favs.splice(i, 1); else favs.unshift(id);
    try { localStorage.setItem(FAV_KEY, JSON.stringify(favs)); } catch { /* navigation privée */ }
    document.dispatchEvent(new CustomEvent("favs:change", { detail: { id, on: i < 0 } }));
    if (i < 0) track("Favori", { hotel: id });
  }
  const favButton = (h, extra = "") => C.favButton(h, extra, isFav(h.id));
  const card = (h, opts = {}) => C.card(h, { ...opts, fav: isFav(h.id) });
  function syncFavButtons(scope = document) {
    const favs = getFavs();
    scope.querySelectorAll("[data-fav]").forEach((b) => {
      const on = favs.includes(b.dataset.fav);
      b.classList.toggle("on", on);
      b.setAttribute("aria-pressed", on);
    });
  }
  document.addEventListener("click", (e) => {
    const b = e.target.closest("[data-fav]");
    if (!b) return;
    e.preventDefault();
    e.stopPropagation();
    toggleFav(b.dataset.fav);
  });
  document.addEventListener("favs:change", ({ detail }) => {
    document.querySelectorAll("[data-fav]").forEach((b) => {
      if (b.dataset.fav !== detail.id) return;
      b.classList.toggle("on", detail.on);
      b.setAttribute("aria-pressed", detail.on);
      if (detail.on) { b.classList.remove("pop"); void b.offsetWidth; b.classList.add("pop"); }
    });
    updateFavCount();
    renderFavDrawer();
  });

  /* ---------- Mini-diaporama des cartes ---------- */
  document.addEventListener("click", (e) => {
    const b = e.target.closest("[data-slide]");
    if (!b) return;
    e.preventDefault();
    const slides = b.closest(".card-media").querySelector(".card-slides");
    const n = slides.children.length;
    const i = Math.round(slides.scrollLeft / slides.clientWidth);
    slides.scrollTo({ left: ((i + Number(b.dataset.slide) + n) % n) * slides.clientWidth, behavior: "smooth" });
  });
  document.addEventListener("scroll", (e) => {
    const t = e.target;
    if (!(t instanceof Element) || !t.classList.contains("card-slides")) return;
    const i = Math.round(t.scrollLeft / t.clientWidth);
    t.parentElement.querySelectorAll(".card-dots span").forEach((d, k) => d.classList.toggle("on", k === i));
  }, true);

  /* ---------- Rails horizontaux (flèches) ---------- */
  document.addEventListener("click", (e) => {
    const b = e.target.closest("[data-rail]");
    if (!b) return;
    const rail = document.getElementById(b.dataset.rail);
    if (rail) rail.scrollBy({ left: Number(b.dataset.dir) * rail.clientWidth * 0.8, behavior: "smooth" });
  });

  /* ---------- Apparition au défilement ---------- */
  const revealObserver = "IntersectionObserver" in window
    ? new IntersectionObserver((entries) => entries.forEach((en) => {
        if (en.isIntersecting) { en.target.classList.add("in"); revealObserver.unobserve(en.target); }
      }), { rootMargin: "0px 0px -6% 0px", threshold: 0.06 })
    : null;
  function observeReveal(scope = document) {
    scope.querySelectorAll(".reveal:not(.in)").forEach((el, i) => {
      el.style.setProperty("--d", `${Math.min(i % 6, 5) * 70}ms`);
      if (revealObserver) revealObserver.observe(el); else el.classList.add("in");
    });
  }

  /* ---------- Menus déroulants sur mesure ----------
   * Remplace l'apparence des <select data-fancy> tout en gardant le vrai
   * <select> (caché) : les formulaires et le code existant continuent de
   * fonctionner, et le clavier (flèches, Entrée, Échap, lettres) est géré. */
  const CHEVRON = `<svg class="select-chevron" viewBox="0 0 20 20" aria-hidden="true"><path d="M5 7.5l5 5 5-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  let selectUid = 0;
  function enhanceSelect(sel) {
    if (sel.dataset.enhanced) return;
    sel.dataset.enhanced = "1";
    const uid = `sel-${++selectUid}`;
    const wrap = document.createElement("div");
    wrap.className = `select ${sel.dataset.fancy || ""}`.trim();
    sel.parentNode.insertBefore(wrap, sel);
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "select-btn";
    btn.setAttribute("aria-haspopup", "listbox");
    btn.setAttribute("aria-expanded", "false");
    btn.setAttribute("aria-controls", `${uid}-list`);
    const label = sel.getAttribute("aria-label");
    if (label) btn.setAttribute("aria-label", label);
    btn.innerHTML = `<span class="select-value"></span>${CHEVRON}`;
    const list = document.createElement("ul");
    list.className = "select-list";
    list.id = `${uid}-list`;
    list.setAttribute("role", "listbox");
    list.hidden = true;
    wrap.append(btn, list);
    wrap.appendChild(sel);
    sel.classList.add("select-native");
    sel.tabIndex = -1;
    sel.setAttribute("aria-hidden", "true");

    let active = -1;
    const options = () => [...sel.options];
    const refresh = () => {
      const o = sel.options[sel.selectedIndex];
      btn.querySelector(".select-value").textContent = o ? o.textContent : "";
      btn.disabled = sel.disabled;
      wrap.classList.toggle("is-disabled", sel.disabled);
      wrap.classList.toggle("has-value", !!sel.value);
    };
    const renderList = () => {
      list.innerHTML = options().map((o, i) => `
        <li role="option" id="${uid}-${i}" data-i="${i}" aria-selected="${o.selected}" class="${o.disabled ? "is-disabled" : ""}${o.selected ? " is-selected" : ""}"${o.disabled ? ' aria-disabled="true"' : ""}>
          <span>${escapeHtml(o.textContent)}</span>
        </li>`).join("");
    };
    const highlight = (i) => {
      active = i;
      list.querySelectorAll("li").forEach((li, k) => li.classList.toggle("is-active", k === i));
      const li = list.children[i];
      if (li) { btn.setAttribute("aria-activedescendant", li.id); li.scrollIntoView({ block: "nearest" }); }
    };
    const move = (dir) => {
      const opts = options();
      let i = active;
      for (let n = 0; n < opts.length; n++) {
        i = (i + dir + opts.length) % opts.length;
        if (!opts[i].disabled) return highlight(i);
      }
    };
    const open = () => {
      if (sel.disabled || !list.hidden) return;
      document.querySelectorAll(".select.is-open").forEach((w) => w !== wrap && w._close && w._close());
      renderList();
      list.hidden = false;
      wrap.classList.add("is-open");
      btn.setAttribute("aria-expanded", "true");
      const r = btn.getBoundingClientRect();
      const need = Math.min(list.scrollHeight, 320) + 12;
      wrap.classList.toggle("drop-up", r.bottom + need > window.innerHeight && r.top > need);
      highlight(sel.selectedIndex);
    };
    const close = () => {
      if (list.hidden) return;
      list.hidden = true;
      wrap.classList.remove("is-open", "drop-up");
      btn.setAttribute("aria-expanded", "false");
      btn.removeAttribute("aria-activedescendant");
    };
    wrap._close = close;
    const choose = (i) => {
      const o = sel.options[i];
      if (!o || o.disabled) return;
      const changed = sel.selectedIndex !== i;
      sel.selectedIndex = i;
      refresh();
      close();
      btn.focus();
      if (changed) {
        sel.dispatchEvent(new Event("input", { bubbles: true }));
        sel.dispatchEvent(new Event("change", { bubbles: true }));
      }
    };

    btn.addEventListener("click", (e) => {
      e.preventDefault();
      if (list.hidden) open(); else close();
    });
    list.addEventListener("mousedown", (e) => e.preventDefault()); // garde le focus sur le bouton
    list.addEventListener("click", (e) => {
      e.preventDefault(); // évite qu'un <label> parent ne rouvre le menu
      e.stopPropagation();
      const li = e.target.closest("li[data-i]");
      if (li) choose(Number(li.dataset.i));
    });
    list.addEventListener("mousemove", (e) => {
      const li = e.target.closest("li[data-i]");
      if (li && Number(li.dataset.i) !== active && !li.classList.contains("is-disabled")) highlight(Number(li.dataset.i));
    });
    let typed = "", typedTimer;
    btn.addEventListener("keydown", (e) => {
      const isOpen = !list.hidden;
      if (["ArrowDown", "ArrowUp"].includes(e.key)) {
        e.preventDefault();
        if (!isOpen) open(); else move(e.key === "ArrowDown" ? 1 : -1);
      } else if (e.key === "Home" && isOpen) { e.preventDefault(); active = -1; move(1); }
      else if (e.key === "End" && isOpen) { e.preventDefault(); active = options().length; move(-1); }
      else if ((e.key === "Enter" || e.key === " ") && isOpen) { e.preventDefault(); choose(active); }
      else if (e.key === "Escape" && isOpen) { e.preventDefault(); e.stopPropagation(); close(); }
      else if (e.key === "Tab") close();
      else if (e.key.length === 1 && /\S/.test(e.key)) {
        clearTimeout(typedTimer);
        typed += e.key.toLowerCase();
        typedTimer = setTimeout(() => (typed = ""), 600);
        const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/^[^a-z0-9€]+/, "");
        const i = options().findIndex((o) => !o.disabled && norm(o.textContent).startsWith(norm(typed)));
        if (i >= 0) { if (isOpen) highlight(i); else choose(i); }
      }
    });
    document.addEventListener("click", (e) => { if (!wrap.contains(e.target)) close(); });
    window.addEventListener("resize", close);

    // Mise à jour quand le code modifie la valeur, l'état ou les options du <select>
    const proto = HTMLSelectElement.prototype;
    for (const prop of ["value", "selectedIndex", "disabled"]) {
      const d = Object.getOwnPropertyDescriptor(proto, prop);
      Object.defineProperty(sel, prop, {
        configurable: true,
        get() { return d.get.call(this); },
        set(v) { d.set.call(this, v); refresh(); },
      });
    }
    new MutationObserver(refresh).observe(sel, { childList: true, subtree: true, attributes: true, attributeFilter: ["disabled", "selected"] });
    sel.addEventListener("change", refresh);
    refresh();
  }
  const enhanceSelects = (scope = document) => scope.querySelectorAll("select[data-fancy]").forEach(enhanceSelect);

  /* ---------- « Surprenez-moi » ---------- */
  function surprise() {
    const list = window.HOTELS;
    let box = document.getElementById("surprise");
    if (!box) {
      box = document.createElement("div");
      box.id = "surprise";
      box.className = "surprise";
      box.hidden = true;
      box.innerHTML = `
        <div class="surprise-card" role="dialog" aria-modal="true" aria-label="Un lieu au hasard">
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
    const sCard = box.querySelector(".surprise-card");
    const image = box.querySelector("img");
    const cta = box.querySelector("a.btn");
    sCard.classList.add("rolling");
    cta.setAttribute("aria-disabled", "true");
    let pick = list[Math.floor(Math.random() * list.length)];
    if (list.length > 1 && pick.id === box.dataset.pick) pick = list[(list.indexOf(pick) + 1) % list.length];
    box.dataset.pick = pick.id;
    // Défilement rapide de photos qui ralentit, comme une machine à sous
    let step = 0;
    const steps = 14;
    clearTimeout(box._timer);
    const spin = () => {
      const h = step < steps ? list[Math.floor(Math.random() * list.length)] : pick;
      image.src = img(h.images[0], 900);
      if (step++ < steps) box._timer = setTimeout(spin, 45 + step * step * 1.1);
      else {
        const T = window.TYPES[pick.type];
        sCard.classList.remove("rolling");
        box.querySelector(".card-type").textContent = `${T.icon} ${T.label}`;
        box.querySelector("h3").textContent = pick.name;
        box.querySelector(".card-place").textContent = `${pick.city} · ${pick.region}`;
        box.querySelector(".surprise-tagline").textContent = pick.tagline;
        cta.href = C.hotelUrl(pick);
        cta.removeAttribute("aria-disabled");
      }
    };
    spin();
    track("Surprise", {});
  }
  function closeSurprise() {
    const box = document.getElementById("surprise");
    if (!box || box.hidden) return;
    clearTimeout(box._timer);
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
            <a href="${C.hotelUrl(h)}"><img src="${img(h.images[0], 400)}" alt=""></a>
            <a href="${C.hotelUrl(h)}"><strong>${escapeHtml(h.name)}</strong><span>${escapeHtml(h.city)} · ${escapeHtml(window.TYPES[h.type].label)}</span></a>
            ${favButton(h, "fav-mini")}
          </div>`).join("")
      : `<p class="muted fav-empty">Touchez le ♡ d'un lieu pour le garder ici. Pratique pour comparer et partager vos envies.</p>`;
  }
  function toggleDrawer(open) {
    const d = document.getElementById("fav-drawer");
    if (!d) return;
    if (open) {
      renderFavDrawer();
      d.hidden = false;
      requestAnimationFrame(() => d.classList.add("open"));
      document.body.classList.add("no-scroll");
      setTimeout(() => d.querySelector(".drawer-close").focus(), 50);
    } else if (!d.hidden) {
      d.classList.remove("open");
      document.body.classList.remove("no-scroll");
      setTimeout(() => (d.hidden = true), 300);
    }
  }

  /* ---------- En-tête et pied de page ----------
   * Les pages générées (fiches, guides) les contiennent déjà : on ne fait
   * alors qu'activer leurs comportements. */
  function renderChrome() {
    const header = document.getElementById("site-header");
    if (header) {
      if (!header.children.length) header.innerHTML = C.header();
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
      const favOpen = header.querySelector("#fav-open");
      if (favOpen) favOpen.addEventListener("click", () => toggleDrawer(true));
      drawer.addEventListener("click", (e) => { if (e.target === drawer || e.target.closest(".drawer-close")) toggleDrawer(false); });
      updateFavCount();
    }
    const footer = document.getElementById("site-footer");
    if (footer && !footer.children.length) footer.innerHTML = C.footer();

    // Liens Booking des pages générées : on y ajoute la provenance du visiteur
    if (getSource()) {
      document.querySelectorAll("a[data-book]").forEach((a) => {
        const h = window.HOTELS.find((x) => x.id === a.dataset.book);
        if (h) a.href = bookingLink(h);
      });
    }
    syncFavButtons();
    enhanceSelects();
    observeReveal();
  }

  window.NS = {
    ...C,
    CONFIG, getSource, track, bookingLink, getUserLocation, setUserLocation, geocode, locateBrowser,
    getFavs, isFav, toggleFav, favButton, card, syncFavButtons, observeReveal, enhanceSelects, surprise,
  };
  document.addEventListener("DOMContentLoaded", renderChrome);
})();
