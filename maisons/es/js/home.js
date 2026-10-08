/* Sable & Pierre — page d'accueil */
(function () {
  "use strict";
  const { $, $$, esc, icon, img, reduced } = window.SP;
  const H = window.HOUSES;

  /* Prix indicatif « à partir de » en réservation directe (js/data.js, sinon prix Airbnb relevé) */
  const from = (k) => (window.SP_FROM ? window.SP_FROM(k) : H[k].priceFrom);
  ["lacanau", "bordeaux"].forEach((k) => {
    if (!from(k)) return;
    const ul = $(`.house-feature[data-house="${k}"] .facts`);
    if (ul) ul.insertAdjacentHTML("beforeend", `<li data-icon="calendar">Desde ${from(k).toLocaleString("es-ES")} € la noche reservando directamente</li>`);
  });

  /* Remise réservation directe (js/tarifs.js) */
  const deal = $(".search__deal");
  if (deal) {
    const pct = Number((window.TARIFS || {}).remiseDirecte) || 0;
    if (pct) deal.innerHTML = `<strong>−${pct} % en toda la estancia</strong> reservando directamente en esta web.`;
    else deal.remove();
  }

  /* Icônes des listes « facts » */
  $$("[data-icon]").forEach((li) => li.insertAdjacentHTML("afterbegin", icon(li.dataset.icon)));

  /* Manifeste : les mots s'allument au fil du défilement */
  const text = $("[data-words]");
  if (text) {
    text.innerHTML = text.textContent.trim().split(/\s+/).map((w) => `<span class="w">${esc(w)}</span>`).join(" ");
    const words = $$(".w", text);
    const light = () => {
      const r = text.getBoundingClientRect();
      const vh = window.innerHeight;
      const p = Math.min(1, Math.max(0, (vh * 0.85 - r.top) / (r.height + vh * 0.35)));
      const n = Math.round(p * words.length);
      words.forEach((w, i) => w.classList.toggle("on", i < n));
    };
    if (reduced) words.forEach((w) => w.classList.add("on"));
    else {
      window.addEventListener("scroll", () => requestAnimationFrame(light), { passive: true });
      light();
    }
  }

  /* Galerie à faire glisser : les plus belles photos des deux maisons */
  const reel = $("#reel");
  if (reel) {
    const picks = [
      ["lacanau", 18], ["bordeaux", 2], ["lacanau", 27], ["bordeaux", 7], ["lacanau", 4], ["bordeaux", 4],
      ["lacanau", 22], ["bordeaux", 8], ["lacanau", 6], ["bordeaux", 18], ["lacanau", 21], ["bordeaux", 13],
      ["lacanau", 23], ["bordeaux", 10],
    ];
    reel.innerHTML = picks.map(([h, n]) => {
      const list = H[h].photos;
      const i = list.findIndex((p) => p[0] === n);
      const cap = list[i] ? list[i][1] : "";
      return `<figure class="reel__item">
        <button type="button" data-house="${h}" data-index="${i}" aria-label="Ampliar: ${esc(cap)}, ${esc(H[h].name)}">${img(h, n, cap, "(max-width: 600px) 76vw, 30vw")}</button>
        <figcaption><span>${esc(cap)}</span><span>${h === "lacanau" ? "Lacanau" : "Burdeos"}</span></figcaption>
      </figure>`;
    }).join("");

    // Glisser à la souris (le doigt fait défiler nativement)
    let down = false;
    let moved = false;
    let x0 = 0;
    let s0 = 0;
    reel.addEventListener("pointerdown", (e) => {
      if (e.pointerType !== "mouse") return;
      down = true; moved = false; x0 = e.clientX; s0 = reel.scrollLeft;
    });
    window.addEventListener("pointermove", (e) => {
      if (!down) return;
      const dx = e.clientX - x0;
      if (Math.abs(dx) > 5) { moved = true; reel.classList.add("is-dragging"); }
      reel.scrollLeft = s0 - dx;
    });
    window.addEventListener("pointerup", () => {
      if (!down) return;
      down = false;
      reel.classList.remove("is-dragging");
    });
    reel.addEventListener("click", (e) => {
      const b = e.target.closest("button[data-house]");
      if (!b) return;
      if (moved) { e.preventDefault(); moved = false; return; }
      SP.openLightbox(SP.galleryOf(b.dataset.house), Number(b.dataset.index));
    });

    const prev = $('[data-reel="-1"]');
    const next = $('[data-reel="1"]');
    prev.innerHTML = icon("left");
    next.innerHTML = icon("arrow");
    const step = () => (reel.firstElementChild ? reel.firstElementChild.offsetWidth + 18 : 300) * 2;
    prev.addEventListener("click", () => reel.scrollBy({ left: -step(), behavior: reduced ? "auto" : "smooth" }));
    next.addEventListener("click", () => reel.scrollBy({ left: step(), behavior: reduced ? "auto" : "smooth" }));
    const bar = $(".reel__progress i");
    const progress = () => {
      const max = reel.scrollWidth - reel.clientWidth;
      const p = max > 0 ? reel.scrollLeft / max : 1;
      bar.style.width = `${Math.max(8, p * 100)}%`;
      prev.disabled = reel.scrollLeft < 4;
      next.disabled = reel.scrollLeft > max - 4;
    };
    reel.addEventListener("scroll", progress, { passive: true });
    window.addEventListener("resize", progress);
    progress();
  }

  /* Les environs : onglets Lacanau / Bordeaux */
  const panels = $("#dest-panels");
  if (panels) {
    const D = window.DESTINATIONS;
    panels.innerHTML = ["lacanau", "bordeaux"].map((k, idx) => `
      <div class="dest-panel${idx === 0 ? " is-in" : ""}" id="panel-${k}" role="tabpanel" aria-labelledby="tab-${k}" data-house="${k}"${idx ? " hidden" : ""}>
        <div class="dest-intro">
          <h3 class="h3">${D[k].title}</h3>
          <p style="margin-top:22px">${esc(D[k].intro)}</p>
          <div class="weather" data-weather="${k}" hidden></div> <p class="weather-note" hidden>Tiempo en directo · Open-Meteo</p> <a class="btn btn--accent" style="margin-top:32px" href="${H[k].page}">${esc(H[k].name)}</a>
        </div>
        <ol class="dest-list">
          ${D[k].places.map(([t, dist, body], i) => `
            <li><details${i === 0 ? " open" : ""}>
              <summary><h4>${esc(t)}</h4><span class="dist">${esc(dist)}</span><span class="plus" aria-hidden="true"></span></summary>
              <p>${esc(body)}</p>
            </details></li>`).join("")}
        </ol>
      </div>`).join("");

    const tabs = $$('#destinations [role="tab"]');
    const pill = $("#destinations .dest-tabs__pill");
    const section = $("#destinations");
    const weatherDone = {};
    const loadWeather = (k) => {
      if (weatherDone[k]) return;
      weatherDone[k] = true;
      SP.weather($(`[data-weather="${k}"]`), H[k].weather);
    };
    const select = (tab, focus) => {
      tabs.forEach((t) => {
        const on = t === tab;
        t.setAttribute("aria-selected", String(on));
        t.tabIndex = on ? 0 : -1;
        const p = $(`#${t.getAttribute("aria-controls")}`);
        p.hidden = !on;
        p.classList.toggle("is-in", on);
      });
      section.dataset.house = tab.dataset.tab;
      pill.style.width = `${tab.offsetWidth}px`;
      pill.style.transform = `translateX(${tab.offsetLeft - 5}px)`;
      loadWeather(tab.dataset.tab);
      if (focus) tab.focus();
    };
    tabs.forEach((t, i) => {
      t.addEventListener("click", () => select(t));
      t.addEventListener("keydown", (e) => {
        if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
          e.preventDefault();
          select(tabs[(i + (e.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length], true);
        }
      });
    });
    const init = () => select(tabs.find((t) => t.getAttribute("aria-selected") === "true") || tabs[0]);
    window.addEventListener("resize", init);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(init);
    init();
  }

  /* Avis : un à la fois, qui défilent tout seuls */
  const stage = $("#quotes");
  if (stage) {
    const R = window.REVIEWS;
    const all = [];
    const max = Math.max(R.lacanau.length, R.bordeaux.length);
    for (let i = 0; i < max; i++) {
      if (R.lacanau[i]) all.push(["lacanau", ...R.lacanau[i]]);
      if (R.bordeaux[i]) all.push(["bordeaux", ...R.bordeaux[i]]);
    }
    stage.innerHTML = all.map(([h, q, who, when], i) => `
      <figure class="quote${i === 0 ? " is-active" : ""}" ${i ? 'aria-hidden="true"' : ""}>
        <blockquote>${esc(q)}</blockquote>
        <figcaption>${esc(who)} · ${esc(when)} · ${esc(H[h].name)}</figcaption>
      </figure>`).join("");
    const dots = $("#quote-dots");
    dots.innerHTML = all.map((r, i) => `<button type="button" aria-label="Reseñas ${i + 1} de ${all.length}" aria-current="${i === 0}"></button>`).join("");
    const quotes = $$(".quote", stage);
    const btns = $$("button", dots);
    let cur = 0;
    let timer = null;
    const show = (i) => {
      cur = (i + quotes.length) % quotes.length;
      quotes.forEach((q, j) => { q.classList.toggle("is-active", j === cur); q.setAttribute("aria-hidden", String(j !== cur)); });
      btns.forEach((b, j) => b.setAttribute("aria-current", String(j === cur)));
    };
    const play = () => {
      clearInterval(timer);
      if (!reduced) timer = setInterval(() => show(cur + 1), 7000);
    };
    btns.forEach((b, j) => b.addEventListener("click", () => { show(j); play(); }));
    stage.addEventListener("mouseenter", () => clearInterval(timer));
    stage.addEventListener("mouseleave", play);
    play();
  }


  /* Recherche de dates : calendrier sur mesure et disponibilités des deux maisons */
  const sForm = $("#search");
  if (sForm) {
    const { today0, iso, parseISO, addDays, nights } = SP.dates;
    const today = today0();
    const sHouse = $("#s-house");
    const bIn = $("#s-in");
    const bOut = $("#s-out");
    const bGuests = $("#s-guests");
    const dp = $("#dp");
    const gp = $("#gp");
    const out = $("#search-results");
    const fmt = new Intl.DateTimeFormat("es-ES", { weekday: "short", day: "numeric", month: "short" });
    const fmtLong = new Intl.DateTimeFormat("es-ES", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
    const fmtMonth = new Intl.DateTimeFormat("es-ES", { month: "long", year: "numeric" });
    const plural = (n, w) => `${n} ${w}${n > 1 ? "s" : ""}`;
    const maxG = Math.max(H.lacanau.guests, H.bordeaux.guests);
    const st = { a: null, b: null, adults: 2, children: 0, month: 0, phase: "in", hover: null };

    // Règles de disponibilité selon la maison choisie (« les deux » : au moins une maison possible)
    const avs = { lacanau: SP.availability("lacanau"), bordeaux: SP.availability("bordeaux") };
    const houses = () => (sHouse.value === "all" ? ["lacanau", "bordeaux"] : [sHouse.value]);
    const canIn = (d) => houses().some((k) => avs[k].canIn(d));
    const canStay = (a, b) => houses().some((k) => avs[k].canIn(a) && !avs[k].outProblem(a, b));
    const minN = (a) => Math.min(...houses().filter((k) => avs[k].canIn(a)).map((k) => avs[k].minNights(a)).concat([99]));

    /* --- Calendrier --- */
    const render = () => {
      const months = [];
      const narrow = window.innerWidth < 700;
      for (let m = 0; m < (narrow ? 1 : 2); m++) {
        const first = new Date(today.getFullYear(), today.getMonth() + st.month + m, 1);
        const pad0 = (first.getDay() + 6) % 7;
        const n = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
        const cells = ["lu", "ma", "me", "je", "ve", "sa", "di"].map((x) => `<span class="dp__dow" aria-hidden="true">${x}</span>`);
        for (let i = 0; i < pad0; i++) cells.push("<span></span>");
        for (let d = 1; d <= n; d++) {
          const date = new Date(first.getFullYear(), first.getMonth(), d);
          const t = date.getTime();
          const cls = ["dp__day"];
          let off = date < today;
          let why = "";
          if (!off) {
            if (st.phase === "out" && st.a && date > st.a) {
              if (!canStay(st.a, date)) {
                off = true;
                const probs = houses().filter((k) => avs[k].canIn(st.a)).map((k) => avs[k].outProblem(st.a, date));
                if (probs.every((p) => p === "short")) { why = `estancia de ${minN(st.a)} noches mínimo`; cls.push("is-short"); }
                else if (probs.every((p) => p === "long")) why = `estancia de ${Math.max(...houses().map((k) => avs[k].maxNights(st.a)))} noches máximo`;
                else why = "indisponible";
              }
            } else if (!canIn(date)) { off = true; why = "ya reservado"; }
          }
          if (off) cls.push("is-off");
          if (t === today.getTime()) cls.push("is-today");
          const end = st.b || (st.phase === "out" && st.hover && st.a && st.hover > st.a ? st.hover : null);
          if (st.a && t === st.a.getTime()) cls.push("is-a");
          if (end && t === end.getTime()) cls.push("is-b");
          if (st.a && end && date > st.a && date < end) cls.push("is-in");
          if (st.a && end) cls.push("has-range");
          cells.push(`<button type="button" class="${cls.join(" ")}" data-d="${iso(date)}" aria-label="${fmtLong.format(date)}${why ? `, ${why}` : ""}"${off ? ' aria-disabled="true"' : ""}${why ? ` title="${why.charAt(0).toUpperCase() + why.slice(1)}"` : ""} tabindex="-1">${d}</button>`);
        }
        months.push(`<div class="dp__month"><h3>${fmtMonth.format(first)}</h3><div class="dp__grid">${cells.join("")}</div></div>`);
      }
      const n = st.a && st.b ? nights(st.a, st.b) : 0;
      dp.innerHTML = `
        <div class="dp__head"> <button type="button" class="round-btn" data-nav="-1" aria-label="Mes anterior"${st.month <= 0 ? " disabled" : ""}>${icon("left")}</button>
          <p class="dp__hint" aria-live="polite">${st.phase === "in" ? "Elige tu llegada" : st.b ? `${plural(n, "noche")} · ${fmt.format(st.a)} → ${fmt.format(st.b)}` : `Elige tu salida${minN(st.a) > 1 && minN(st.a) < 99 ? ` · ${minN(st.a)} noches mínimo` : ""}`}</p> <button type="button" class="round-btn" data-nav="1" aria-label="Mes siguiente"${st.month >= 22 ? " disabled" : ""}>${icon("arrow")}</button>
        </div>
        <div class="dp__months">${months.join("")}</div> <div class="dp__foot"> <span class="dp__legend"><i class="dp__k dp__k--off"></i>Ya reservado${sHouse.value === "all" ? " en las dos casas" : ""}</span> <div class="dp__actions"> <button type="button" class="link" data-clear>Borrar</button> <button type="button" class="btn btn--accent" data-done${st.a && st.b ? "" : " disabled"}>Aceptar</button> </div> </div>`;
      const focusEl = $(".dp__day.is-b", dp) || $(".dp__day.is-a", dp) || $(".dp__day:not(.is-off)", dp);
      if (focusEl) focusEl.tabIndex = 0;
    };
    const syncFields = () => {
      bIn.textContent = st.a ? fmt.format(st.a) : "Añadir una fecha";
      bOut.textContent = st.b ? fmt.format(st.b) : "Añadir una fecha";
      bIn.classList.toggle("is-set", !!st.a);
      bOut.classList.toggle("is-set", !!st.b);
      bIn.closest(".search__field").classList.toggle("is-active", !dp.hidden && st.phase === "in");
      bOut.closest(".search__field").classList.toggle("is-active", !dp.hidden && st.phase === "out");
    };
    let lastTrigger = null;
    const openDp = (phase, trigger) => {
      closeGp();
      st.phase = phase === "out" && st.a ? "out" : "in";
      if (st.a) st.month = Math.max(0, (st.a.getFullYear() - today.getFullYear()) * 12 + st.a.getMonth() - today.getMonth());
      lastTrigger = trigger || bIn;
      dp.hidden = false;
      bIn.setAttribute("aria-expanded", "true");
      bOut.setAttribute("aria-expanded", "true");
      render();
      syncFields();
      requestAnimationFrame(() => dp.classList.add("is-open"));
      const f = $(".dp__day[tabindex='0']", dp);
      if (f) f.focus({ preventScroll: true });
    };
    const closeDp = (restore) => {
      if (dp.hidden) return;
      dp.classList.remove("is-open");
      dp.hidden = true;
      bIn.setAttribute("aria-expanded", "false");
      bOut.setAttribute("aria-expanded", "false");
      syncFields();
      if (restore && lastTrigger) lastTrigger.focus();
    };
    bIn.addEventListener("click", () => (dp.hidden || st.phase !== "in" ? openDp("in", bIn) : closeDp()));
    bOut.addEventListener("click", () => (dp.hidden || st.phase !== "out" ? openDp("out", bOut) : closeDp()));
    dp.addEventListener("click", (e) => {
      const nav = e.target.closest("[data-nav]");
      if (nav) { st.month = Math.max(0, Math.min(22, st.month + Number(nav.dataset.nav))); render(); return; }
      if (e.target.closest("[data-clear]")) { st.a = null; st.b = null; st.phase = "in"; render(); syncFields(); return; }
      if (e.target.closest("[data-done]")) { closeDp(true); return; }
      const day = e.target.closest("[data-d]");
      if (!day || day.getAttribute("aria-disabled") === "true") return;
      const d = parseISO(day.dataset.d);
      if (st.phase === "in" || !st.a || d <= st.a) {
        st.a = d; st.b = null; st.phase = "out";
      } else {
        st.b = d;
        render(); syncFields();
        setTimeout(() => closeDp(true), 260);
        return;
      }
      render(); syncFields();
      const again = $(`[data-d="${day.dataset.d}"]`, dp);
      if (again && e.detail === 0) again.focus();
    });
    dp.addEventListener("mouseover", (e) => {
      const day = e.target.closest("[data-d]");
      if (!day || st.phase !== "out" || !st.a || st.b || day.getAttribute("aria-disabled") === "true") return;
      const d = parseISO(day.dataset.d);
      if (st.hover && st.hover.getTime() === d.getTime()) return;
      st.hover = d;
      $$(".dp__day", dp).forEach((x) => {
        const xd = parseISO(x.dataset.d);
        x.classList.toggle("is-in", d > st.a && xd > st.a && xd < d);
        x.classList.toggle("is-b", d > st.a && xd.getTime() === d.getTime());
        x.classList.toggle("has-range", d > st.a);
      });
    });
    dp.addEventListener("keydown", (e) => {
      if (e.key === "Escape") { closeDp(true); return; }
      const day = e.target.closest("[data-d]");
      const mv = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[e.key];
      if (!day || mv === undefined) return;
      e.preventDefault();
      let d = addDays(parseISO(day.dataset.d), mv);
      if (d < today) d = today;
      const off = (d.getFullYear() - today.getFullYear()) * 12 + d.getMonth() - today.getMonth();
      const span = window.innerWidth < 700 ? 0 : 1;
      if (off < st.month) st.month = off; else if (off > st.month + span) st.month = off - span;
      render();
      const n = $(`[data-d="${iso(d)}"]`, dp);
      if (n) { $$(".dp__day", dp).forEach((x) => { x.tabIndex = -1; }); n.tabIndex = 0; n.focus(); }
    });
    sHouse.addEventListener("change", () => {
      // Si les dates ne conviennent plus à la maison choisie, on les retire
      if (st.a && !canIn(st.a)) { st.a = null; st.b = null; }
      else if (st.a && st.b && !canStay(st.a, st.b)) st.b = null;
      syncFields();
      if (!dp.hidden) render();
    });

    /* --- Voyageurs --- */
    const guestsText = () => plural(st.adults + st.children, "viajero");
    const renderGp = () => {
      const tot = st.adults + st.children;
      gp.innerHTML = `
        <div class="stepper"><div><b>Adultos</b><span>18 años o más</span></div><div class="stepper__ctl"><button type="button" data-g="adults" data-v="-1" aria-label="Quitar un adulto"${st.adults <= 1 ? " disabled" : ""}>−</button><output>${st.adults}</output><button type="button" data-g="adults" data-v="1" aria-label="Añadir un adulto"${tot >= maxG ? " disabled" : ""}>+</button></div></div> <div class="stepper"><div><b>Niños</b><span>De 2 a 17 años</span></div><div class="stepper__ctl"><button type="button" data-g="children" data-v="-1" aria-label="Quitar un niño"${st.children <= 0 ? " disabled" : ""}>−</button><output>${st.children}</output><button type="button" data-g="children" data-v="1" aria-label="Añadir un niño"${tot >= maxG ? " disabled" : ""}>+</button></div></div> <p class="gp__note">La Maison du Lac tiene capacidad para ${H.lacanau.guests} viajeros, la Maison de Pierre para ${H.bordeaux.guests}.</p>`;
      bGuests.textContent = guestsText();
    };
    function closeGp(restore) {
      if (gp.hidden) return;
      gp.hidden = true;
      bGuests.setAttribute("aria-expanded", "false");
      bGuests.closest(".search__field").classList.remove("is-active");
      if (restore) bGuests.focus();
    }
    bGuests.addEventListener("click", () => {
      if (!gp.hidden) return closeGp();
      closeDp();
      renderGp();
      gp.hidden = false;
      bGuests.setAttribute("aria-expanded", "true");
      bGuests.closest(".search__field").classList.add("is-active");
      const f = $("button:not([disabled])", gp);
      if (f) f.focus();
    });
    gp.addEventListener("click", (e) => {
      const b = e.target.closest("[data-g]");
      if (!b || b.disabled) return;
      const k = b.dataset.g;
      const v = st[k] + Number(b.dataset.v);
      if (v < (k === "adults" ? 1 : 0) || (Number(b.dataset.v) > 0 && st.adults + st.children >= maxG)) return;
      st[k] = v;
      renderGp();
      const again = $(`[data-g="${k}"][data-v="${b.dataset.v}"]`, gp);
      if (again && !again.disabled) again.focus();
    });
    gp.addEventListener("keydown", (e) => { if (e.key === "Escape") closeGp(true); });

    // Fermer en cliquant ailleurs
    document.addEventListener("click", (e) => {
      if (!e.target.isConnected) return; // élément redessiné pendant le clic : on reste dans le calendrier
      if (!dp.hidden && !dp.contains(e.target) && !e.target.closest("[data-dp]")) closeDp();
      if (!gp.hidden && !gp.contains(e.target) && e.target !== bGuests) closeGp();
    });
    window.addEventListener("resize", () => { if (!dp.hidden) render(); });

    /* --- Résultats --- */
    const card = (k, ok, text, link, label) => `
      <article class="result${ok ? " is-ok" : ""}" data-house="${k}">
        <img src="${SP.photo(k, H[k].cover, "sm")}" alt="" loading="lazy">
        <div class="result__body">
          <span class="eyebrow eyebrow--plain">${esc(H[k].place)}</span>
          <h3>${esc(H[k].name)}</h3>
          <p class="result__state">${icon(ok ? "check" : "calendar")}<span>${text}</span></p>
        </div>
        <a class="btn ${ok ? "btn--accent" : "btn--ghost"}" href="${link}">${label}</a>
      </article>`;
    function nextFrom(av, a, n) {
      for (let i = 1; i < 120; i++) {
        const x = addDays(a, i);
        if (!av.canIn(x)) continue;
        const y = addDays(x, Math.max(n, av.minNights(x)));
        if (!av.outProblem(x, y)) return [x, y];
      }
      return null;
    }
    const check = (k, a, b, g) => {
      const av = avs[k];
      const url = (x, y) => `${H[k].page}?arrivee=${iso(x)}&depart=${iso(y)}&voyageurs=${Math.min(g, H[k].guests)}#reserver`;
      if (g > H[k].guests) return card(k, false, `Hasta ${H[k].guests} viajeros en esta casa.`, `${H[k].page}#reserver`, "Ver la casa");
      if (!av.canIn(a)) {
        const alt = nextFrom(av, a, nights(a, b));
        return card(k, false, `No es posible llegar el ${fmt.format(a)}.${alt ? ` Próxima opción: del ${fmt.format(alt[0])} au ${fmt.format(alt[1])}.` : ""}`, alt ? url(alt[0], alt[1]) : `${H[k].page}#reserver`, alt ? "Ver estas fechas" : "Ver el calendario");
      }
      const p = av.outProblem(a, b);
      if (p === "short") return card(k, false, `Estancia de ${av.minNights(a)} noches mínimo en estas fechas.`, url(a, addDays(a, av.minNights(a))), `Ver ${av.minNights(a)} noches`);
      if (p) {
        const alt = nextFrom(av, a, nights(a, b));
        return card(k, false, `No todas estas fechas están libres.${alt ? ` Próxima opción: del ${fmt.format(alt[0])} au ${fmt.format(alt[1])}.` : ""}`, alt ? url(alt[0], alt[1]) : `${H[k].page}#reserver`, alt ? "Ver estas fechas" : "Ver el calendario");
      }
      const pct = Number((window.TARIFS || {}).remiseDirecte) || 0;
      return card(k, true, `Libre del ${fmt.format(a)} au ${fmt.format(b)} · ${plural(nights(a, b), "noche")} · ${plural(g, "viajero")}${pct ? ` · −${pct} % reservando directamente` : ""}${from(k) ? ` · desde ${from(k).toLocaleString("es-ES")} € la noche` : ""}`, url(a, b), "Reservar estas fechas");
    };
    sForm.addEventListener("submit", (e) => {
      e.preventDefault();
      closeDp(); closeGp();
      if (!st.a || !st.b) {
        out.innerHTML = `<p class="search__error">Elige primero tus fechas de llegada y salida.</p>`;
        openDp(st.a ? "out" : "in", st.a ? bOut : bIn);
        return;
      }
      const g = st.adults + st.children;
      out.innerHTML = houses().map((k) => check(k, st.a, st.b, g)).join("");
      try { sessionStorage.setItem("sp-search", JSON.stringify({ a: iso(st.a), b: iso(st.b), ad: st.adults, ch: st.children, h: sHouse.value })); } catch (err) { /* ignoré */ }
    });
    try {
      const prev = JSON.parse(sessionStorage.getItem("sp-search") || "null");
      if (prev && prev.a && parseISO(prev.a) >= today) {
        st.a = parseISO(prev.a); st.b = parseISO(prev.b); st.adults = prev.ad || 2; st.children = prev.ch || 0; sHouse.value = prev.h || "all";
      }
    } catch (err) { /* ignoré */ }
    renderGp();
    syncFields();
  }

  /* Quand venir : climat de Lacanau ou de Bordeaux */
  const climBox = $("#clim");
  if (climBox) {
    const ctabs = $$("[data-ctab]");
    const cpill = $(".dest-tabs--clim .dest-tabs__pill");
    let month;
    const csel = (t, focus) => {
      ctabs.forEach((x) => { const on = x === t; x.setAttribute("aria-selected", String(on)); x.tabIndex = on ? 0 : -1; });
      $("#quand").dataset.house = t.dataset.ctab;
      climBox.setAttribute("aria-labelledby", t.id);
      cpill.style.width = `${t.offsetWidth}px`;
      cpill.style.transform = `translateX(${t.offsetLeft - 5}px)`;
      const sel = climBox.querySelector('.clim__months [aria-selected="true"]');
      if (sel) month = Number(sel.dataset.m);
      SP.climate(climBox, t.dataset.ctab, month);
      if (focus) t.focus();
    };
    ctabs.forEach((t, i) => {
      t.addEventListener("click", () => csel(t));
      t.addEventListener("keydown", (e) => {
        if (e.key === "ArrowRight" || e.key === "ArrowLeft") { e.preventDefault(); csel(ctabs[(i + 1) % 2], true); }
      });
    });
    const cinit = () => csel(ctabs.find((t) => t.getAttribute("aria-selected") === "true") || ctabs[0]);
    window.addEventListener("resize", () => {
      const t = ctabs.find((x) => x.getAttribute("aria-selected") === "true");
      cpill.style.width = `${t.offsetWidth}px`;
      cpill.style.transform = `translateX(${t.offsetLeft - 5}px)`;
    });
    cinit();
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => {
      const t = ctabs.find((x) => x.getAttribute("aria-selected") === "true");
      cpill.style.width = `${t.offsetWidth}px`;
      cpill.style.transform = `translateX(${t.offsetLeft - 5}px)`;
    });
  }

  SP.parallax();
})();
