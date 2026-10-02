/* Sable & Pierre — page d'accueil */
(function () {
  "use strict";
  const { $, $$, esc, icon, img, reduced } = window.SP;
  const H = window.HOUSES;

  /* Prix indicatif « à partir de » (si renseigné dans js/data.js) */
  ["lacanau", "bordeaux"].forEach((k) => {
    if (!H[k].priceFrom) return;
    const ul = $(`.house-feature[data-house="${k}"] .facts`);
    if (ul) ul.insertAdjacentHTML("beforeend", `<li data-icon="calendar">À partir de ${H[k].priceFrom.toLocaleString("fr-FR")} € la nuit</li>`);
  });

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
        <button type="button" data-house="${h}" data-index="${i}" aria-label="Agrandir : ${esc(cap)}, ${esc(H[h].name)}">${img(h, n, cap, "(max-width: 600px) 76vw, 30vw")}</button>
        <figcaption><span>${esc(cap)}</span><span>${h === "lacanau" ? "Lacanau" : "Bordeaux"}</span></figcaption>
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
          <div class="weather" data-weather="${k}" hidden></div>
          <p class="weather-note" hidden>Météo en direct · Open-Meteo</p>
          <a class="btn btn--accent" style="margin-top:32px" href="${H[k].page}">${esc(H[k].name)}</a>
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
    dots.innerHTML = all.map((r, i) => `<button type="button" aria-label="Avis ${i + 1} sur ${all.length}" aria-current="${i === 0}"></button>`).join("");
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


  /* Recherche de dates : disponibilités des deux maisons en direct */
  const sForm = $("#search");
  if (sForm) {
    const { today0, iso, parseISO, addDays, nights } = SP.dates;
    const today = today0();
    const sIn = $("#s-in");
    const sOut = $("#s-out");
    const sHouse = $("#s-house");
    const sGuests = $("#s-guests");
    const out = $("#search-results");
    const fmt = new Intl.DateTimeFormat("fr-FR", { weekday: "short", day: "numeric", month: "short" });
    const maxG = Math.max(H.lacanau.guests, H.bordeaux.guests);
    sGuests.innerHTML = Array.from({ length: maxG }, (_, i) => `<option value="${i + 1}"${i === 1 ? " selected" : ""}>${i + 1}</option>`).join("");
    sIn.min = iso(today);
    sOut.min = iso(addDays(today, 1));
    sIn.addEventListener("change", () => {
      const a = sIn.value && parseISO(sIn.value);
      if (!a) return;
      sOut.min = iso(addDays(a, 1));
      if (!sOut.value || parseISO(sOut.value) <= a) sOut.value = iso(addDays(a, 3));
    });
    const plural = (n, w) => `${n} ${w}${n > 1 ? "s" : ""}`;
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
    const check = (k, a, b, g) => {
      const av = SP.availability(k);
      const url = (x, y) => `${H[k].page}?arrivee=${iso(x)}&depart=${iso(y)}&voyageurs=${Math.min(g, H[k].guests)}#reserver`;
      if (g > H[k].guests) return card(k, false, `Jusqu'à ${H[k].guests} voyageurs dans cette maison.`, `${H[k].page}#reserver`, "Voir la maison");
      if (!av.canIn(a)) {
        const alt = nextFrom(av, a, nights(a, b));
        return card(k, false, `Arrivée impossible le ${fmt.format(a)}.${alt ? ` Prochaine possibilité : du ${fmt.format(alt[0])} au ${fmt.format(alt[1])}.` : ""}`, alt ? url(alt[0], alt[1]) : `${H[k].page}#reserver`, alt ? "Voir ces dates" : "Voir le calendrier");
      }
      const p = av.outProblem(a, b);
      if (p === "short") return card(k, false, `Séjour de ${av.minNights(a)} nuits minimum à ces dates.`, url(a, addDays(a, av.minNights(a))), `Voir ${av.minNights(a)} nuits`);
      if (p) {
        const alt = nextFrom(av, a, nights(a, b));
        return card(k, false, `Ces dates ne sont pas toutes libres.${alt ? ` Prochaine possibilité : du ${fmt.format(alt[0])} au ${fmt.format(alt[1])}.` : ""}`, alt ? url(alt[0], alt[1]) : `${H[k].page}#reserver`, alt ? "Voir ces dates" : "Voir le calendrier");
      }
      return card(k, true, `Libre du ${fmt.format(a)} au ${fmt.format(b)} · ${plural(nights(a, b), "nuit")} · ${plural(g, "voyageur")}${H[k].priceFrom ? ` · à partir de ${H[k].priceFrom.toLocaleString("fr-FR")} € la nuit` : ""}`, url(a, b), "Réserver ces dates");
    };
    // Premier séjour de même durée possible après la date demandée
    function nextFrom(av, a, n) {
      for (let i = 1; i < 120; i++) {
        const x = addDays(a, i);
        if (!av.canIn(x)) continue;
        const len = Math.max(n, av.minNights(x));
        const y = addDays(x, len);
        if (!av.outProblem(x, y)) return [x, y];
      }
      return null;
    }
    sForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const a = /^\d{4}-\d{2}-\d{2}$/.test(sIn.value) ? parseISO(sIn.value) : null;
      const b = /^\d{4}-\d{2}-\d{2}$/.test(sOut.value) ? parseISO(sOut.value) : null;
      if (!a || !b || b <= a || a < today) {
        out.innerHTML = `<p class="search__error">Choisissez une date d'arrivée (à partir d'aujourd'hui) puis une date de départ plus tardive.</p>`;
        (!a || a < today ? sIn : sOut).focus();
        return;
      }
      const g = Number(sGuests.value) || 1;
      const keys = sHouse.value === "all" ? ["lacanau", "bordeaux"] : [sHouse.value];
      out.innerHTML = keys.map((k) => check(k, a, b, g)).join("");
      try { sessionStorage.setItem("sp-search", JSON.stringify({ a: sIn.value, b: sOut.value, g, h: sHouse.value })); } catch (err) { /* ignoré */ }
    });
    try {
      const prev = JSON.parse(sessionStorage.getItem("sp-search") || "null");
      if (prev && prev.a && parseISO(prev.a) >= today) {
        sIn.value = prev.a; sOut.value = prev.b; sGuests.value = String(prev.g); sHouse.value = prev.h;
      }
    } catch (err) { /* ignoré */ }
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
