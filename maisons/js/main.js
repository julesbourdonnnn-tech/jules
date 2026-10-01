/*
 * Sable & Pierre — scripts communs à toutes les pages :
 * en-tête, menu, apparitions au défilement, visionneuse de photos, météo.
 */
(function () {
  "use strict";

  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
  const root = document.documentElement;
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const pad = (n) => String(n).padStart(2, "0");

  /* ---------- Icônes (traits fins, couleur du texte) ---------- */
  const P = 'fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"';
  const ICONS = {
    arrow: `<svg viewBox="0 0 24 24" ${P}><path d="M4 12h16M14 6l6 6-6 6"/></svg>`,
    left: `<svg viewBox="0 0 24 24" ${P}><path d="M20 12H4M10 6l-6 6 6 6"/></svg>`,
    close: `<svg viewBox="0 0 24 24" ${P}><path d="M5 5l14 14M19 5L5 19"/></svg>`,
    star: `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.8l2.7 6 6.5.6-4.9 4.3 1.5 6.4L12 16.8 6.2 20.1l1.5-6.4L2.8 9.4l6.5-.6z"/></svg>`,
    guests: `<svg viewBox="0 0 24 24" ${P}><circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.4 2.7-6 6-6s6 2.6 6 6"/><circle cx="17" cy="9" r="2.4"/><path d="M16 14.2c2.8.2 5 2.5 5 5.8"/></svg>`,
    bed: `<svg viewBox="0 0 24 24" ${P}><path d="M3 18V6M3 14h18v4M21 14v-3a3 3 0 0 0-3-3h-7v6"/><circle cx="7" cy="11" r="1.8"/></svg>`,
    bath: `<svg viewBox="0 0 24 24" ${P}><path d="M3 12h18v3a5 5 0 0 1-5 5H8a5 5 0 0 1-5-5zM6 12V5.5A2.5 2.5 0 0 1 8.5 3c1.2 0 2.2.8 2.4 2M7 20l-1 2M17 20l1 2"/></svg>`,
    door: `<svg viewBox="0 0 24 24" ${P}><path d="M5 21V4a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v17M3 21h18"/><circle cx="15" cy="12" r=".8" fill="currentColor"/></svg>`,
    pool: `<svg viewBox="0 0 24 24" ${P}><path d="M2 17c2 0 2-1.4 4-1.4s2 1.4 4 1.4 2-1.4 4-1.4 2 1.4 4 1.4 2-1.4 4-1.4M2 21c2 0 2-1.4 4-1.4s2 1.4 4 1.4 2-1.4 4-1.4 2 1.4 4 1.4 2-1.4 4-1.4M8 14V5a2 2 0 0 1 4 0M16 14V5a2 2 0 0 0-4 0M8 8h8M8 11h8"/></svg>`,
    lake: `<svg viewBox="0 0 24 24" ${P}><path d="M2 15c2.5 0 2.5-1.5 5-1.5s2.5 1.5 5 1.5 2.5-1.5 5-1.5 2.5 1.5 5 1.5M2 19c2.5 0 2.5-1.5 5-1.5s2.5 1.5 5 1.5 2.5-1.5 5-1.5 2.5 1.5 5 1.5M6 11l3-6 3 6M14 11l2.5-4 2.5 4"/></svg>`,
    wave: `<svg viewBox="0 0 24 24" ${P}><path d="M2 16c3 0 3-3 6-3 2.3 0 3 1.6 4.6 1.6C15 14.6 14 9 18.5 9c1.4 0 2.5.6 3.5 1.5M2 20c2.5 0 2.5-1.5 5-1.5s2.5 1.5 5 1.5 2.5-1.5 5-1.5 2.5 1.5 5 1.5"/><circle cx="17" cy="4.5" r="1.8"/></svg>`,
    leaf: `<svg viewBox="0 0 24 24" ${P}><path d="M5 19C5 10 10 4 20 4c0 10-6 15-15 15zM5 19l8-8"/></svg>`,
    key: `<svg viewBox="0 0 24 24" ${P}><circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l2 2M15 8l2 2"/></svg>`,
    walk: `<svg viewBox="0 0 24 24" ${P}><circle cx="13" cy="4" r="1.8"/><path d="M10 21l2-6 3 3v3M9 12l2-4 4 1 2 3M12 15l-1-4M7 11l2-3"/></svg>`,
    sun: `<svg viewBox="0 0 24 24" ${P}><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>`,
    tv: `<svg viewBox="0 0 24 24" ${P}><rect x="2" y="5" width="20" height="13" rx="1"/><path d="M8 21h8M12 18v3"/></svg>`,
    check: `<svg viewBox="0 0 24 24" ${P}><path d="M4 12.5l5 5L20 6.5"/></svg>`,
    pin: `<svg viewBox="0 0 24 24" ${P}><path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.5"/></svg>`,
    shield: `<svg viewBox="0 0 24 24" ${P}><path d="M12 3l8 3v6c0 5-3.4 8-8 9-4.6-1-8-4-8-9V6z"/><path d="M8.5 12l2.5 2.5 4.5-5"/></svg>`,
    award: `<svg viewBox="0 0 24 24" ${P}><circle cx="12" cy="9" r="6"/><path d="M8.5 14L7 22l5-3 5 3-1.5-8"/></svg>`,
    calendar: `<svg viewBox="0 0 24 24" ${P}><rect x="3" y="5" width="18" height="16" rx="1"/><path d="M3 10h18M8 3v4M16 3v4"/></svg>`,
    grid: `<svg viewBox="0 0 24 24" ${P}><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>`,
    mail: `<svg viewBox="0 0 24 24" ${P}><rect x="3" y="5" width="18" height="14" rx="1"/><path d="M3 7l9 6 9-6"/></svg>`,
    phone: `<svg viewBox="0 0 24 24" ${P}><path d="M5 3h4l2 5-2.5 1.5a11 11 0 0 0 6 6L16 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 5a2 2 0 0 1 2-2z"/></svg>`,
    whatsapp: `<svg viewBox="0 0 24 24" ${P}><path d="M3.5 20.5l1.3-4.3A8.5 8.5 0 1 1 8 19.4z"/><path d="M9 8.5c0 3.5 3 6.5 6.5 6.5l1-1.6-2-1-1 .8c-1-.5-2-1.5-2.6-2.6l.8-1-1-2z"/></svg>`,
    external: `<svg viewBox="0 0 24 24" ${P}><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/></svg>`,
    wind: `<svg viewBox="0 0 24 24" ${P}><path d="M3 8h11a3 3 0 1 0-3-3M3 12h16a3 3 0 1 1-3 3M3 16h8"/></svg>`,
  };
  const icon = (name) => ICONS[name] || ICONS.check;

  /* ---------- Photos ---------- */
  const photo = (house, n, size = "md") => `assets/photos/${house}/${pad(n)}-${size}.webp`;
  const srcset = (house, n) => `${photo(house, n, "sm")} 560w, ${photo(house, n, "md")} 1100w, ${photo(house, n, "xl")} 2200w`;
  const img = (house, n, alt, sizes = "100vw", opts = "") =>
    `<img src="${photo(house, n, "md")}" srcset="${srcset(house, n)}" sizes="${sizes}" alt="${esc(alt)}" ${opts || 'loading="lazy" decoding="async"'}>`;

  window.SP = { $, $$, esc, pad, icon, photo, srcset, img, reduced };

  /* ---------- Rideau d'ouverture ---------- */
  const ready = () => root.classList.add("is-ready");
  const fontsReady = document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve();
  Promise.race([fontsReady, new Promise((r) => setTimeout(r, 900))]).then(() => requestAnimationFrame(ready));

  /* ---------- En-tête ---------- */
  const header = $(".header");
  let lastY = window.scrollY;
  const onScroll = () => {
    const y = window.scrollY;
    if (header) {
      const solidAt = header.dataset.solidAt ? Number(header.dataset.solidAt) : 40;
      header.classList.toggle("is-solid", y > solidAt);
      const hide = y > window.innerHeight * 0.9 && y > lastY + 2 && !root.classList.contains("menu-open");
      const show = y < lastY - 2 || y < window.innerHeight * 0.9;
      if (hide) header.classList.add("is-hidden");
      else if (show) header.classList.remove("is-hidden");
      document.body.classList.toggle("header-visible", !header.classList.contains("is-hidden") && y > window.innerHeight * 0.9);
    }
    lastY = y;
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ---------- Menu plein écran ---------- */
  const burger = $(".burger");
  const menu = $(".menu");
  const setMenu = (open) => {
    root.classList.toggle("menu-open", open);
    document.body.classList.toggle("is-locked", open);
    if (burger) {
      burger.setAttribute("aria-expanded", String(open));
      burger.setAttribute("aria-label", open ? "Fermer le menu" : "Ouvrir le menu");
    }
    if (menu) menu.setAttribute("aria-hidden", String(!open));
    if (open && header) header.classList.remove("is-hidden");
  };
  if (burger) burger.addEventListener("click", () => setMenu(!root.classList.contains("menu-open")));
  if (menu) $$("a", menu).forEach((a) => a.addEventListener("click", () => setMenu(false)));
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && root.classList.contains("menu-open")) setMenu(false);
  });
  window.addEventListener("resize", () => {
    if (window.innerWidth > 900 && root.classList.contains("menu-open")) setMenu(false);
  });

  /* ---------- Apparitions au défilement ---------- */
  const io = "IntersectionObserver" in window
    ? new IntersectionObserver((entries) => {
        entries.forEach((en) => {
          if (en.isIntersecting) {
            en.target.classList.add("is-in");
            io.unobserve(en.target);
          }
        });
      }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 })
    : null;
  const observe = (scope = document) => {
    $$(".reveal, .reveal-img", scope).forEach((el) => (io ? io.observe(el) : el.classList.add("is-in")));
  };
  SP.observe = observe;

  /* ---------- Effet de profondeur sur les images ---------- */
  const parallax = () => {
    if (reduced) return;
    const items = $$("[data-parallax]");
    if (!items.length) return;
    let ticking = false;
    const update = () => {
      const vh = window.innerHeight;
      items.forEach((el) => {
        const box = el.parentElement;
        const r = box.getBoundingClientRect();
        if (r.bottom < -50 || r.top > vh + 50) return;
        // Décalage limité à la marge de l'image : jamais de bord visible
        const room = Math.max(0, (el.offsetHeight - box.offsetHeight) / 2);
        const progress = Math.max(-1, Math.min(1, (r.top + r.height / 2 - vh / 2) / (vh / 2 + r.height / 2)));
        el.style.transform = `translate3d(0, calc(-50% + ${(progress * room).toFixed(1)}px), 0)`;
      });
      ticking = false;
    };
    window.addEventListener("scroll", () => {
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(update);
      }
    }, { passive: true });
    window.addEventListener("resize", update);
    window.addEventListener("load", update);
    update();
  };
  SP.parallax = parallax;

  /* ---------- Visionneuse plein écran ---------- */
  let lb = null;
  let lbItems = [];
  let lbIndex = 0;
  let lbReturn = null;
  const buildLightbox = () => {
    lb = document.createElement("div");
    lb.className = "lb";
    lb.setAttribute("role", "dialog");
    lb.setAttribute("aria-modal", "true");
    lb.setAttribute("aria-label", "Photos");
    lb.innerHTML = `
      <div class="lb__top"><span class="lb__count" aria-live="polite"></span>
        <button type="button" class="lb__close" aria-label="Fermer la visionneuse">${icon("close")}</button></div>
      <div class="lb__stage">
        <button type="button" class="round-btn lb__prev" aria-label="Photo précédente">${icon("left")}</button>
        <img class="lb__img" alt="">
        <button type="button" class="round-btn lb__next" aria-label="Photo suivante">${icon("arrow")}</button>
      </div>
      <p class="lb__cap"></p>
      <div class="lb__thumbs" role="list"></div>`;
    document.body.appendChild(lb);
    $(".lb__close", lb).addEventListener("click", closeLightbox);
    $(".lb__prev", lb).addEventListener("click", () => go(-1));
    $(".lb__next", lb).addEventListener("click", () => go(1));
    lb.addEventListener("keydown", (e) => {
      if (e.key === "Escape") closeLightbox();
      else if (e.key === "ArrowLeft") go(-1);
      else if (e.key === "ArrowRight") go(1);
      else if (e.key === "Tab") {
        const f = $$("button", lb).filter((b) => b.offsetParent !== null);
        const first = f[0];
        const last = f[f.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    });
    // Glisser pour changer de photo (doigt ou souris)
    const stage = $(".lb__stage", lb);
    const im = $(".lb__img", lb);
    let x0 = null;
    let y0 = null;
    stage.addEventListener("pointerdown", (e) => { x0 = e.clientX; y0 = e.clientY; });
    stage.addEventListener("pointermove", (e) => {
      if (x0 === null) return;
      const dx = e.clientX - x0;
      if (Math.abs(dx) > Math.abs(e.clientY - y0)) im.style.transform = `translateX(${dx * 0.6}px)`;
    });
    const end = (e) => {
      if (x0 === null) return;
      const dx = e.clientX - x0;
      im.style.transform = "";
      if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(e.clientY - y0)) go(dx < 0 ? 1 : -1);
      x0 = null;
    };
    stage.addEventListener("pointerup", end);
    stage.addEventListener("pointercancel", () => { x0 = null; im.style.transform = ""; });
  };
  const show = (i) => {
    lbIndex = (i + lbItems.length) % lbItems.length;
    const it = lbItems[lbIndex];
    const im = $(".lb__img", lb);
    im.classList.add("is-loading");
    const pre = new Image();
    pre.onload = pre.onerror = () => {
      im.src = it.src;
      im.alt = it.caption || "";
      im.classList.remove("is-loading");
    };
    pre.src = it.src;
    $(".lb__count", lb).textContent = `${lbIndex + 1} / ${lbItems.length}`;
    $(".lb__cap", lb).textContent = it.caption || "";
    $$(".lb__thumbs button", lb).forEach((b, j) => {
      b.setAttribute("aria-current", String(j === lbIndex));
      if (j === lbIndex) b.scrollIntoView({ block: "nearest", inline: "center", behavior: reduced ? "auto" : "smooth" });
    });
    // Précharge les voisines
    [1, -1].forEach((d) => { const n = lbItems[(lbIndex + d + lbItems.length) % lbItems.length]; if (n) new Image().src = n.src; });
  };
  const go = (d) => show(lbIndex + d);
  const openLightbox = (items, index = 0) => {
    if (!lb) buildLightbox();
    lbItems = items;
    lbReturn = document.activeElement;
    $(".lb__thumbs", lb).innerHTML = items
      .map((it, j) => `<button type="button" role="listitem" aria-label="Photo ${j + 1}"><img src="${it.thumb}" alt="" loading="lazy"></button>`)
      .join("");
    $$(".lb__thumbs button", lb).forEach((b, j) => b.addEventListener("click", () => show(j)));
    lb.classList.add("is-open");
    document.body.classList.add("is-locked");
    show(index);
    setTimeout(() => $(".lb__close", lb).focus(), 50);
  };
  function closeLightbox() {
    lb.classList.remove("is-open");
    document.body.classList.remove("is-locked");
    if (lbReturn && lbReturn.focus) lbReturn.focus();
  }
  SP.openLightbox = openLightbox;
  SP.galleryOf = (house) =>
    window.HOUSES[house].photos.map(([n, caption]) => ({ src: photo(house, n, "xl"), thumb: photo(house, n, "sm"), caption, n }));

  /* ---------- Météo en direct (Open-Meteo, gratuit, sans clé) ---------- */
  const WMO = {
    0: "Grand soleil", 1: "Plutôt ensoleillé", 2: "Éclaircies", 3: "Couvert", 45: "Brouillard", 48: "Brouillard givrant",
    51: "Bruine légère", 53: "Bruine", 55: "Bruine dense", 61: "Pluie faible", 63: "Pluie", 65: "Forte pluie",
    66: "Pluie verglaçante", 67: "Pluie verglaçante", 71: "Neige faible", 73: "Neige", 75: "Forte neige", 77: "Grains de neige",
    80: "Averses", 81: "Averses", 82: "Fortes averses", 85: "Averses de neige", 86: "Averses de neige", 95: "Orage", 96: "Orage", 99: "Orage",
  };
  const hm = (iso) => (iso ? iso.slice(11, 16).replace(":", " h ") : "—");
  SP.weather = async (box, w) => {
    if (!box || !w) return;
    const cells = (list) => list.map(([label, value, note]) => `<div class="weather__cell"><span>${label}</span><b class="num">${value}</b>${note ? `<small>${note}</small>` : ""}</div>`).join("");
    try {
      const url = `https://api.open-meteo.com/v1/forecast?latitude=${w.lat}&longitude=${w.lng}&current=temperature_2m,weather_code,wind_speed_10m&daily=temperature_2m_max,sunset&timezone=Europe%2FParis&forecast_days=1`;
      const r = await fetch(url);
      if (!r.ok) throw new Error(r.status);
      const d = await r.json();
      const c = d.current || {};
      const list = [
        [`À ${w.label}, maintenant`, `${Math.round(c.temperature_2m)}°`, WMO[c.weather_code] || ""],
        ["Maximale du jour", `${Math.round(d.daily.temperature_2m_max[0])}°`, ""],
        ["Coucher du soleil", hm(d.daily.sunset[0]), ""],
      ];
      if (w.sea) {
        try {
          const m = await (await fetch(`https://marine-api.open-meteo.com/v1/marine?latitude=${w.sea.lat}&longitude=${w.sea.lng}&current=sea_surface_temperature,wave_height&timezone=Europe%2FParis`)).json();
          const mc = m.current || {};
          if (typeof mc.sea_surface_temperature === "number") list.push(["L'océan", `${Math.round(mc.sea_surface_temperature)}°`, typeof mc.wave_height === "number" ? `Vagues : ${mc.wave_height.toFixed(1).replace(".", ",")} m` : ""]);
        } catch (e) { /* pas de données marines : on n'affiche rien */ }
      } else {
        list.push(["Vent", `${Math.round(c.wind_speed_10m)}`, "km/h"]);
      }
      box.innerHTML = cells(list);
      box.hidden = false;
      const note = box.nextElementSibling;
      if (note && note.classList.contains("weather-note")) note.hidden = false;
    } catch (e) {
      box.hidden = true;
    }
  };

  /* ---------- Coordonnées dans le pied de page ---------- */
  const S = window.SITE || {};
  $$("[data-email]").forEach((a) => { a.href = `mailto:${S.email}`; a.textContent = S.email; });
  $$("[data-phone]").forEach((a) => {
    if (!S.phone) return a.closest("li") ? a.closest("li").remove() : a.remove();
    a.href = `tel:+${S.phone}`;
    a.textContent = `+${S.phone.replace(/^33/, "33 ")}`;
  });
  $$("[data-whatsapp]").forEach((a) => {
    if (!S.whatsapp) return a.closest("li") ? a.closest("li").remove() : a.remove();
    a.href = `https://wa.me/${S.whatsapp}`;
  });
  $$("[data-instagram]").forEach((a) => {
    if (!S.instagram) return a.closest("li") ? a.closest("li").remove() : a.remove();
    a.href = `https://www.instagram.com/${S.instagram}/`;
  });
  $$("[data-year]").forEach((el) => (el.textContent = new Date().getFullYear()));

  document.addEventListener("DOMContentLoaded", () => observe());
  if (document.readyState !== "loading") observe();
})();
