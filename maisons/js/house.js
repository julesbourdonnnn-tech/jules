/* Sable & Pierre — fiche d'une maison (lacanau.html, bordeaux.html) */
(function () {
  "use strict";
  const { $, $$, esc, icon, img, photo, srcset, reduced } = window.SP;
  const key = document.body.dataset.house;
  const h = window.HOUSES[key];
  const other = window.HOUSES[key === "lacanau" ? "bordeaux" : "lacanau"];
  const D = window.DESTINATIONS[key];
  const S = window.SITE || {};
  const main = $("#main");
  if (!h || !main) return;

  const gallery = SP.galleryOf(key);
  const idxOf = (n) => Math.max(0, h.photos.findIndex((p) => p[0] === n));
  const capOf = (n) => (h.photos.find((p) => p[0] === n) || [0, ""])[1];
  const fr = (x) => String(x).replace(".", ",");
  const ratingTxt = h.rating % 1 === 0 ? fr(h.rating.toFixed(1)) : fr(h.rating);
  const arrow = icon("arrow");

  /* ======================= Rendu de la page ======================= */
  main.innerHTML = `
  <section class="hero" aria-label="${esc(h.name)}">
    <div class="hero__slides">
      ${h.hero.map((n, i) => `<div class="hero__slide${i === 0 ? " is-active" : ""}"><img src="${photo(key, n, "md")}" srcset="${srcset(key, n)}" sizes="100vw" alt="${esc(capOf(n))}" ${i === 0 ? 'fetchpriority="high"' : 'loading="lazy"'}></div>`).join("")}
    </div>
    <div class="hero__content">
      <div class="wrap">
        <div>
          <p class="hero__kicker"><span>${esc(h.kicker)}</span><span>${esc(h.place)}</span></p>
          <h1><span class="split-line"><span>${esc(h.name.replace(/ (du|de) .*/, ""))}</span></span><span class="split-line"><span><em>${esc(h.name.replace(/^La Maison /, ""))}</em></span></span></h1>
        </div>
        <div class="hero__side">
          <p class="hero__count"><b>${ratingTxt}</b> ★ · ${h.reviewsCount} avis · Coup de cœur voyageurs</p>
          <div class="hero__bars" role="group" aria-label="Choisir une photo">${h.hero.map((n, i) => `<button type="button" aria-label="Photo ${i + 1}"${i === 0 ? ' class="is-active"' : ""}><i></i></button>`).join("")}</div>
          <button type="button" class="btn btn--outline-light" data-open-gallery="0">${icon("grid")} Voir les ${gallery.length} photos</button>
        </div>
      </div>
    </div>
  </section>

  <nav class="sub-nav" aria-label="Sections de la page">
    <div class="wrap">
      <div class="sub-nav__links">
        <a href="#maison">La maison</a><a href="#photos">Photos</a><a href="#chambres">Chambres</a><a href="#equipements">Équipements</a><a href="#avis">Avis</a><a href="#reserver">Disponibilités</a><a href="#quartier">Le quartier</a><a href="#infos">Infos pratiques</a>
      </div>
      <a class="btn btn--accent" href="#reserver">Réserver</a>
    </div>
  </nav>

  <section class="section" id="maison">
    <div class="wrap">
      <div class="intro-grid">
        <div>
          <span class="eyebrow reveal">${esc(h.type)} · ${esc(h.region)}</span>
          <h2 class="h2 reveal" style="margin-top:18px">${esc(h.tagline)}</h2>
          <div class="keyfacts reveal">
            <div><b class="num">${h.guests}</b><span>voyageurs</span></div>
            <div><b class="num">${h.bedrooms}</b><span>chambres</span></div>
            <div><b class="num">${h.beds}</b><span>lits</span></div>
            <div><b class="num">${h.bathrooms}</b><span>salles de bain</span></div>
          </div>
          <p class="lead reveal">${esc(h.teaser)}</p>
          <h3 class="eyebrow eyebrow--plain reveal" style="margin:34px 0 14px">Le mot de vos hôtes</h3>
          <div class="prose readmore reveal" id="desc">
            ${h.description.map((d) => `${d.title ? `<h3>${esc(d.title)}</h3>` : ""}<p>${esc(d.text)}</p>`).join("")}
          </div>
          <button type="button" class="link" id="desc-more" style="margin-top:18px" aria-controls="desc" aria-expanded="false">Lire la suite</button>
        </div>
        <aside>
          <ul class="highlights">
            ${h.highlights.map(([ic, t, s], i) => `<li class="reveal" data-delay="${i}">${icon(ic)}<div><b>${esc(t)}</b><span>${esc(s)}</span></div></li>`).join("")}
          </ul>
          <div class="host-card reveal">
            <span class="avatar" aria-hidden="true">${icon("award")}</span>
            <div><b>Coup de cœur voyageurs</b><span>L'un des logements préférés des voyageurs sur Airbnb · hôte Superhôte</span></div>
          </div>
        </aside>
      </div>
    </div>
  </section>

  <section class="section section--paper" id="photos">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">En images</span><h2 class="h2">Entrez, <em>c'est ouvert</em></h2></div>
        <p>Cliquez sur une photo pour l'agrandir, puis faites défiler avec les flèches du clavier ou en glissant le doigt.</p>
      </div>
      <div class="mosaic">
        ${h.photos.slice(0, 10).map(([n, cap], i) => `<button type="button" class="reveal-img" data-open-gallery="${i}" data-label="${esc(cap)}" aria-label="Agrandir : ${esc(cap)}">${img(key, n, cap, "(max-width: 900px) 100vw, 50vw")}</button>`).join("")}
      </div>
      <div class="mosaic-more"><button type="button" class="btn btn--ghost" data-open-gallery="0">${icon("grid")} Voir les ${gallery.length} photos</button></div>
    </div>
  </section>

  <section class="section" id="chambres">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">Où vous dormirez</span><h2 class="h2">${h.bedrooms} chambres, <em>${h.beds} lits</em></h2></div>
        <p>${key === "lacanau" ? "Deux chambres et une salle de bain de plain-pied, les quatre autres chambres à l'étage." : "Trois chambres, une salle de bain et un WC au rez-de-chaussée ; deux chambres, une salle d'eau et un WC en sous-sol ; la pièce de vie et la terrasse à l'étage."}</p>
      </div>
      <div class="beds">
        ${h.sleeping.map(([name, bed, n], i) => `
          <article class="bed reveal" data-delay="${i % 4}">
            <button type="button" class="bed__img" data-open-gallery="${idxOf(n)}" aria-label="Agrandir la photo : ${esc(name)}">${img(key, n, name, "(max-width: 600px) 100vw, 25vw")}</button>
            <div class="bed__body">${icon("bed")}<b>${esc(name)}</b><span>${esc(bed)}</span></div>
          </article>`).join("")}
      </div>
    </div>
  </section>

  <section class="section section--paper" id="equipements">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">Ce que propose la maison</span><h2 class="h2">Tout est <em>prévu</em></h2></div>
        <p>La liste complète des équipements, telle qu'elle figure sur l'annonce.</p>
      </div>
      <div class="amenities">
        ${h.amenities.map(([g, items], i) => `
          <div class="amenity-group reveal"${i > 3 ? " data-more hidden" : ""}>
            <h3>${esc(g)}</h3>
            <ul>${items.map((t) => `<li>${icon("check")}<span>${esc(t)}</span></li>`).join("")}</ul>
          </div>`).join("")}
      </div>
      ${h.amenities.length > 4 ? `<div class="mosaic-more"><button type="button" class="btn btn--ghost" id="amen-more" aria-expanded="false">Voir tous les équipements</button></div>` : ""}
    </div>
  </section>

  <section class="section" id="avis">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">${h.reviewsCount} avis · note ${ratingTxt} sur 5</span><h2 class="h2">Ils en <em>parlent</em></h2></div>
        <div class="ratings">${h.categoryRatings.map(([l, v]) => `<p class="rating-row"><span>${esc(l)}</span><i style="--v:${Number(v.replace(",", ".")) / 5}"></i><b>${esc(v)}</b></p>`).join("")}</div>
      </div>
      <div class="quote-grid">
        ${(window.REVIEWS[key] || []).map(([q, who, when], i) => `<figure class="quote-card reveal" data-delay="${i % 3}"><blockquote>${esc(q)}</blockquote><figcaption>${esc(who)} · ${esc(when)}</figcaption></figure>`).join("")}
      </div>
      <p class="small" style="margin-top:28px">Extraits d'avis publiés sur Airbnb. <a class="link" href="${h.airbnbUrl}#reviews" target="_blank" rel="noopener">Lire tous les avis ${icon("external")}</a></p>
    </div>
  </section>

  <section class="section section--sand" id="reserver">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">Disponibilités</span><h2 class="h2">Choisissez <em>vos dates</em></h2></div>
        <p>Sélectionnez votre arrivée puis votre départ. Vous réservez ensuite en ligne sur Airbnb, ou vous nous envoyez une demande directe.</p>
      </div>
      <div class="book-grid">
        <div class="cal" id="cal">
          <div class="cal__head">
            <button type="button" class="round-btn" data-cal="-1" aria-label="Mois précédent">${icon("left")}</button>
            <span class="small" id="cal-hint" aria-live="polite">Choisissez votre date d'arrivée</span>
            <button type="button" class="round-btn" data-cal="1" aria-label="Mois suivant">${arrow}</button>
          </div>
          <div class="cal__months" id="cal-months"></div>
          <div class="cal__legend"><span><i style="background:var(--accent)"></i>Votre séjour</span><span><i style="background:rgba(28,26,23,.18)"></i>Indisponible</span><span><i style="background:var(--gold)"></i>Aujourd'hui</span></div>
          <p class="cal__status" id="cal-status"></p>
        </div>
        <aside class="booking" aria-labelledby="book-title">
          <h3 id="book-title">${esc(h.name)}</h3>
          <p class="small">${esc(h.place)} · jusqu'à ${h.guests} voyageurs</p>
          <div class="booking__fields">
            <button type="button" class="booking__field" data-focus-cal><small>Arrivée</small><b id="f-in">Ajouter une date</b></button>
            <button type="button" class="booking__field" data-focus-cal><small>Départ</small><b id="f-out">Ajouter une date</b></button>
            <button type="button" class="booking__field booking__field--full" id="f-guests-btn" aria-expanded="false" aria-controls="guests-pop"><small>Voyageurs</small><b id="f-guests">1 voyageur</b></button>
          </div>
          <div class="guests-pop" id="guests-pop"><div>
            ${stepper("adults", "Adultes", "18 ans et plus")}
            ${stepper("children", "Enfants", "De 2 à 17 ans")}
            ${stepper("infants", "Bébés", key === "bordeaux" ? "La maison ne convient pas aux moins de 2 ans" : "Moins de 2 ans")}
          </div></div>
          <div class="booking__summary" id="summary" hidden></div>
          <a class="btn btn--accent btn--block" id="go-airbnb" href="${h.airbnbUrl}" target="_blank" rel="noopener">Voir le prix et réserver ${icon("external")}</a>
          <div class="booking__alt">
            <button type="button" class="btn btn--ghost btn--block" id="go-direct">${icon("mail")} Demande de réservation directe</button>
          </div>
          <p class="booking__msg" id="book-msg" aria-live="polite"></p>
          <p class="booking__trust">${icon("shield")}<span>Réservation en ligne et paiement sécurisés par Airbnb. Le prix exact s'affiche pour vos dates.</span></p>
        </aside>
      </div>
    </div>
  </section>

  <section class="section" id="quartier">
    <div class="wrap">
      <div class="map-wrap">
        <div>
          <span class="eyebrow">Le quartier</span>
          <h2 class="h2" style="margin-top:18px">${D.title}</h2>
          <p class="lead" style="margin-top:22px">${esc(h.neighbourhood)}</p>
          <p class="prose">${esc(h.gettingAround)}</p>
          <div class="weather" data-weather hidden></div>
          <p class="weather-note" hidden>Météo en direct · Open-Meteo</p>
        </div>
        <div>
          <div class="map" id="map" role="img" aria-label="Carte du quartier de ${esc(h.name)}"></div>
          <p class="map-note">${key === "lacanau" ? "Le cercle indique le secteur de la maison ; l'adresse exacte vous est communiquée à la réservation." : "Emplacement approximatif : l'adresse exacte vous est communiquée à la réservation."}</p>
        </div>
      </div>
      <ol class="dest-list" style="margin-top:72px">
        ${D.places.map(([t, dist, body]) => `<li><details><summary><h4>${esc(t)}</h4><span class="dist">${esc(dist)}</span><span class="plus" aria-hidden="true"></span></summary><p>${esc(body)}</p></details></li>`).join("")}
      </ol>
    </div>
  </section>

  <section class="section section--paper" id="infos">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">Infos pratiques</span><h2 class="h2">Le règlement <em>de la maison</em></h2></div>
        <p>Vous allez séjourner dans une maison de famille : merci d'en prendre soin et de respecter les lieux.</p>
      </div>
      <div class="rules">
        ${Object.entries(h.rules).map(([g, items]) => `<div class="reveal"><h3>${esc(g)}</h3><ul>${items.map((t) => `<li>${esc(t)}</li>`).join("")}</ul></div>`).join("")}
      </div>
      ${h.registration ? `<p class="small" style="margin-top:40px">Numéro d'enregistrement en mairie : ${esc(h.registration)}</p>` : ""}
    </div>
  </section>

  <a class="other" href="${other.page}" data-house="${other.id}">
    <img src="${photo(other.id, other.cover, "md")}" srcset="${srcset(other.id, other.cover)}" sizes="100vw" alt="" loading="lazy" data-parallax="0.1">
    <div class="wrap">
      <span class="eyebrow">L'autre maison · ${esc(other.kicker)}</span>
      <h2 class="display">${esc(other.name.replace(/ (du|de) .*/, ""))} <em>${esc(other.name.replace(/^La Maison /, ""))}</em></h2>
      <span class="link">${esc(other.place)} · ${other.guests} voyageurs ${arrow}</span>
    </div>
  </a>

  <div class="mbar" id="mbar">
    <div><b>${esc(h.name)}</b><span>★ ${ratingTxt} · ${h.reviewsCount} avis · ${h.guests} voyageurs</span></div>
    <a class="btn btn--accent" href="#reserver">Réserver</a>
  </div>

  <div class="dialog" id="dialog" aria-hidden="true">
    <div class="dialog__bg" data-close></div>
    <div class="dialog__box" role="dialog" aria-modal="true" aria-labelledby="dlg-title">
      <button type="button" class="dialog__close" data-close aria-label="Fermer">${icon("close")}</button>
      <div id="dlg-form">
        <span class="eyebrow eyebrow--plain">${esc(h.name)}</span>
        <h2 class="h3" id="dlg-title" style="margin-top:12px">Demande de réservation</h2>
        <p class="small" style="margin-top:10px">Nous vous répondons personnellement avec le prix et la confirmation des dates. Rien n'est réservé ni payé à cette étape.</p>
        <form class="form" id="form" novalidate>
          <p class="form__recap" id="recap"></p>
          <div class="field"><label for="d-name">Nom et prénom</label><input id="d-name" name="nom" autocomplete="name" required maxlength="80"></div>
          <div class="field"><label for="d-phone">Téléphone</label><input id="d-phone" name="telephone" type="tel" autocomplete="tel" maxlength="30"></div>
          <div class="field full"><label for="d-email">E-mail</label><input id="d-email" name="email" type="email" autocomplete="email" required maxlength="254"></div>
          <div class="field full"><label for="d-msg">Votre message</label><textarea id="d-msg" name="message" maxlength="2000" placeholder="L'occasion de votre séjour, vos questions…"></textarea></div>
          <input class="hp" type="text" name="bot-field" tabindex="-1" autocomplete="off" aria-hidden="true">
          <div class="full"><button type="submit" class="btn btn--accent btn--block">Envoyer ma demande</button><p class="booking__msg" id="form-msg" aria-live="polite"></p></div>
        </form>
      </div>
      <div class="form__done" id="dlg-done" hidden>
        ${icon("check")}
        <h2 class="h3">Merci !</h2>
        <p id="done-text" style="margin-top:12px">Votre demande est bien partie. Nous vous répondons très vite.</p>
        <button type="button" class="btn" data-close style="margin-top:18px">Fermer</button>
      </div>
    </div>
  </div>`;

  function stepper(name, label, sub) {
    return `<div class="stepper"><div><b>${label}</b><span>${sub}</span></div>
      <div class="stepper__ctl"><button type="button" data-step="${name}" data-d="-1" aria-label="Retirer : ${label}">−</button><output id="n-${name}" aria-live="polite">0</output><button type="button" data-step="${name}" data-d="1" aria-label="Ajouter : ${label}">+</button></div></div>`;
  }

  /* ======================= Diaporama d'ouverture ======================= */
  const slides = $$(".hero__slide");
  const bars = $$(".hero__bars button");
  let slide = 0;
  let slideTimer = null;
  const goSlide = (i) => {
    slides[slide].classList.remove("is-active");
    bars.forEach((b, j) => { b.classList.remove("is-active"); b.classList.toggle("is-done", j < i); });
    slide = (i + slides.length) % slides.length;
    if (slide === 0) bars.forEach((b) => b.classList.remove("is-done"));
    slides[slide].classList.add("is-active");
    // Relance l'animation de la barre
    const bar = bars[slide];
    bar.classList.remove("is-active");
    void bar.offsetWidth;
    bar.classList.add("is-active");
  };
  const playSlides = () => {
    clearInterval(slideTimer);
    if (!reduced) slideTimer = setInterval(() => !document.hidden && goSlide(slide + 1), 6000);
  };
  bars.forEach((b, i) => b.addEventListener("click", () => { goSlide(i); playSlides(); }));
  playSlides();

  /* ======================= Visionneuse ======================= */
  main.addEventListener("click", (e) => {
    const b = e.target.closest("[data-open-gallery]");
    if (b) SP.openLightbox(gallery, Number(b.dataset.openGallery));
  });

  /* ======================= Lire la suite / équipements ======================= */
  const desc = $("#desc");
  const more = $("#desc-more");
  requestAnimationFrame(() => {
    if (desc.scrollHeight <= desc.clientHeight + 20) {
      desc.classList.add("is-open");
      desc.style.maxHeight = "none";
      more.hidden = true;
    }
  });
  more.addEventListener("click", () => {
    const open = !desc.classList.contains("is-open");
    desc.classList.toggle("is-open", open);
    desc.style.maxHeight = open ? `${desc.scrollHeight}px` : "";
    more.textContent = open ? "Réduire" : "Lire la suite";
    more.setAttribute("aria-expanded", String(open));
  });
  const amenMore = $("#amen-more");
  if (amenMore) amenMore.addEventListener("click", () => {
    const open = amenMore.getAttribute("aria-expanded") !== "true";
    $$("[data-more]").forEach((g) => { g.hidden = !open; if (open) g.classList.add("is-in"); });
    amenMore.setAttribute("aria-expanded", String(open));
    amenMore.textContent = open ? "Voir moins" : "Voir tous les équipements";
  });

  /* ======================= Sous-menu qui suit la lecture ======================= */
  const links = $$(".sub-nav__links a");
  const sections = links.map((a) => $(a.getAttribute("href")));
  if ("IntersectionObserver" in window) {
    const spy = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (!en.isIntersecting) return;
        links.forEach((a) => a.classList.toggle("is-active", a.getAttribute("href") === `#${en.target.id}`));
        const act = links.find((a) => a.classList.contains("is-active"));
        if (act) act.parentElement.scrollTo({ left: act.offsetLeft - 40, behavior: reduced ? "auto" : "smooth" });
      });
    }, { rootMargin: "-45% 0px -50% 0px" });
    sections.forEach((s) => s && spy.observe(s));
  }

  /* ======================= Barre de réservation (mobile) ======================= */
  const mbar = $("#mbar");
  const hero = $(".hero");
  const reserve = $("#reserver");
  document.body.classList.add("has-mbar");
  const mbarUpdate = () => {
    const pastHero = hero.getBoundingClientRect().bottom < 0;
    const r = reserve.getBoundingClientRect();
    const inReserve = r.top < window.innerHeight && r.bottom > 0;
    mbar.classList.toggle("is-visible", pastHero && !inReserve);
  };
  window.addEventListener("scroll", mbarUpdate, { passive: true });
  mbarUpdate();

  /* ======================= Calendrier et réservation ======================= */
  const DAY = 86400000;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const parse = (s) => { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); };
  const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
  const nightsBetween = (a, b) => Math.round((b - a) / DAY);
  const fmt = new Intl.DateTimeFormat("fr-FR", { weekday: "short", day: "numeric", month: "short" });
  const fmtLong = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
  const fmtMonth = new Intl.DateTimeFormat("fr-FR", { month: "long", year: "numeric" });

  const state = { in: null, out: null, adults: 1, children: 0, infants: 0, hover: null };
  const limits = { infants: key === "bordeaux" ? 0 : 5 };
  let booked = new Set(); // nuits occupées (AAAA-MM-JJ)
  let monthOffset = 0;

  // Dates reprises de l'adresse (?arrivee=2026-07-01&depart=2026-07-08&voyageurs=4) ou de la visite précédente
  try {
    const q = new URLSearchParams(location.search);
    const saved = JSON.parse(sessionStorage.getItem(`sp-${key}`) || "{}");
    const a = q.get("arrivee") || saved.in;
    const b = q.get("depart") || saved.out;
    if (a && /^\d{4}-\d{2}-\d{2}$/.test(a) && parse(a) >= today) state.in = parse(a);
    if (state.in && b && /^\d{4}-\d{2}-\d{2}$/.test(b) && parse(b) > state.in) state.out = parse(b);
    const g = Number(q.get("voyageurs") || saved.adults || 1);
    if (g >= 1) state.adults = Math.min(g, h.guests);
    if (!q.get("voyageurs") && saved.children) state.children = Math.min(saved.children, h.guests - state.adults);
    if (!q.get("voyageurs") && saved.infants) state.infants = Math.min(saved.infants, limits.infants);
    if (state.in) monthOffset = Math.max(0, (state.in.getFullYear() - today.getFullYear()) * 12 + state.in.getMonth() - today.getMonth());
  } catch (e) { /* stockage indisponible : on part de zéro */ }

  const isBooked = (d) => booked.has(iso(d));
  const rangeFree = (a, b) => { for (let d = new Date(a); d < b; d = addDays(d, 1)) if (isBooked(d)) return false; return true; };
  const firstBookedAfter = (a) => { for (let i = 1; i < 730; i++) { const d = addDays(a, i); if (isBooked(d)) return d; } return null; };

  const monthsBox = $("#cal-months");
  const hint = $("#cal-hint");
  const renderCal = () => {
    const html = [];
    for (let m = 0; m < 2; m++) {
      const first = new Date(today.getFullYear(), today.getMonth() + monthOffset + m, 1);
      const startDow = (first.getDay() + 6) % 7; // lundi = 0
      const days = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
      const cells = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."].map((d) => `<span class="cal__dow" aria-hidden="true">${d.slice(0, 2)}</span>`);
      for (let i = 0; i < startDow; i++) cells.push("<span></span>");
      const limit = state.in && !state.out ? firstBookedAfter(state.in) : null;
      for (let d = 1; d <= days; d++) {
        const date = new Date(first.getFullYear(), first.getMonth(), d);
        const t = date.getTime();
        const cls = ["cal__day"];
        let disabled = date < today;
        const nightBooked = isBooked(date);
        if (nightBooked) cls.push("is-booked");
        if (t === today.getTime()) cls.push("is-today");
        if (state.in && !state.out) {
          // On choisit le départ : après l'arrivée, jusqu'à la première nuit prise (incluse, jour de départ possible)
          if (date > state.in) disabled = disabled || (limit && date > limit);
          else if (date < state.in) disabled = disabled || nightBooked;
          if (date > state.in && limit && t === limit.getTime()) { disabled = false; cls.push("is-checkout-only"); }
        } else {
          disabled = disabled || nightBooked;
        }
        const end = state.out || (state.in && state.hover && state.hover > state.in ? state.hover : null);
        if (state.in && t === state.in.getTime()) cls.push("is-start");
        if (end && t === end.getTime()) cls.push("is-end");
        if (state.in && end && date > state.in && date < end) cls.push("is-range");
        if (state.in && !end && t === state.in.getTime()) cls.push("is-end");
        const label = `${fmtLong.format(date)}${nightBooked ? ", indisponible" : ""}`;
        cells.push(`<button type="button" class="${cls.join(" ")}" data-date="${iso(date)}" aria-label="${label}"${disabled ? " disabled" : ""}${cls.includes("is-start") || cls.includes("is-end") ? ' aria-pressed="true"' : ""}>${d}</button>`);
      }
      html.push(`<div class="cal__month"><h4>${fmtMonth.format(first)}</h4><div class="cal__grid">${cells.join("")}</div></div>`);
    }
    monthsBox.innerHTML = html.join("");
    $('[data-cal="-1"]').disabled = monthOffset <= 0;
    $('[data-cal="1"]').disabled = monthOffset >= 22;
    hint.textContent = !state.in ? "Choisissez votre date d'arrivée" : !state.out ? "Choisissez votre date de départ" : `${nightsBetween(state.in, state.out)} nuit${nightsBetween(state.in, state.out) > 1 ? "s" : ""} sélectionnée${nightsBetween(state.in, state.out) > 1 ? "s" : ""}`;
  };

  monthsBox.addEventListener("click", (e) => {
    const b = e.target.closest("button[data-date]");
    if (!b || b.disabled) return;
    const d = parse(b.dataset.date);
    if (!state.in || state.out || d <= state.in) {
      if (isBooked(d)) return;
      state.in = d; state.out = null;
    } else if (rangeFree(state.in, d)) {
      state.out = d;
    } else if (!isBooked(d)) {
      state.in = d; state.out = null;
    }
    state.hover = null;
    update();
    // Au clavier, on garde le focus sur le jour choisi (le calendrier est redessiné)
    if (e.detail === 0) {
      const again = $(`button[data-date="${b.dataset.date}"]`, monthsBox);
      if (again) again.focus();
    }
  });
  monthsBox.addEventListener("mouseover", (e) => {
    const b = e.target.closest("button[data-date]");
    if (!b || !state.in || state.out || b.disabled) return;
    const d = parse(b.dataset.date);
    if (state.hover && d.getTime() === state.hover.getTime()) return;
    state.hover = d;
    // Mise à jour légère : uniquement les classes de la plage
    $$("button[data-date]", monthsBox).forEach((x) => {
      const xd = parse(x.dataset.date);
      x.classList.toggle("is-range", d > state.in && xd > state.in && xd < d);
      x.classList.toggle("is-end", d > state.in ? xd.getTime() === d.getTime() : xd.getTime() === state.in.getTime());
    });
  });
  monthsBox.addEventListener("mouseleave", () => { if (state.hover) { state.hover = null; renderCal(); } });
  $$("[data-cal]").forEach((b) => b.addEventListener("click", () => {
    monthOffset = Math.max(0, Math.min(22, monthOffset + Number(b.dataset.cal)));
    renderCal();
  }));
  $$("[data-focus-cal]").forEach((b) => b.addEventListener("click", () => {
    const first = $("button[data-date]:not([disabled])", monthsBox);
    $("#cal").scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "center" });
    if (first) setTimeout(() => first.focus({ preventScroll: true }), 400);
  }));

  // Voyageurs
  const gBtn = $("#f-guests-btn");
  const pop = $("#guests-pop");
  gBtn.addEventListener("click", () => {
    const open = !pop.classList.contains("is-open");
    pop.classList.toggle("is-open", open);
    gBtn.setAttribute("aria-expanded", String(open));
  });
  $$("[data-step]").forEach((b) => b.addEventListener("click", () => {
    const k = b.dataset.step;
    const d = Number(b.dataset.d);
    const v = state[k] + d;
    if (k === "adults" && (v < 1 || v + state.children > h.guests)) return;
    if (k === "children" && (v < 0 || v + state.adults > h.guests)) return;
    if (k === "infants" && (v < 0 || v > limits.infants)) return;
    state[k] = v;
    update();
  }));

  const airbnbLink = () => {
    const u = new URL(h.airbnbUrl);
    if (state.in && state.out) {
      u.searchParams.set("check_in", iso(state.in));
      u.searchParams.set("check_out", iso(state.out));
    }
    u.searchParams.set("adults", state.adults);
    if (state.children) u.searchParams.set("children", state.children);
    if (state.infants) u.searchParams.set("infants", state.infants);
    u.searchParams.set("guests", state.adults + state.children);
    return u.toString();
  };
  const guestsText = () => {
    const n = state.adults + state.children;
    let t = `${n} voyageur${n > 1 ? "s" : ""}`;
    if (state.infants) t += `, ${state.infants} bébé${state.infants > 1 ? "s" : ""}`;
    return t;
  };
  const stayText = () => (state.in && state.out ? `du ${fmtLong.format(state.in)} au ${fmtLong.format(state.out)} (${nightsBetween(state.in, state.out)} nuit${nightsBetween(state.in, state.out) > 1 ? "s" : ""})` : "dates à définir");

  function update() {
    $("#f-in").textContent = state.in ? fmt.format(state.in) : "Ajouter une date";
    $("#f-out").textContent = state.out ? fmt.format(state.out) : "Ajouter une date";
    $("#f-guests").textContent = guestsText();
    ["adults", "children", "infants"].forEach((k) => { $(`#n-${k}`).textContent = state[k]; });
    $$('[data-step="adults"][data-d="-1"]')[0].disabled = state.adults <= 1;
    $$('[data-step="adults"][data-d="1"]')[0].disabled = state.adults + state.children >= h.guests;
    $$('[data-step="children"][data-d="-1"]')[0].disabled = state.children <= 0;
    $$('[data-step="children"][data-d="1"]')[0].disabled = state.adults + state.children >= h.guests;
    $$('[data-step="infants"][data-d="-1"]')[0].disabled = state.infants <= 0;
    $$('[data-step="infants"][data-d="1"]')[0].disabled = state.infants >= limits.infants;
    const sum = $("#summary");
    if (state.in && state.out) {
      const n = nightsBetween(state.in, state.out);
      sum.hidden = false;
      sum.innerHTML = `<p><span>Séjour</span><strong>${n} nuit${n > 1 ? "s" : ""}</strong></p><p><span>Arrivée</span><span>${esc(fmtLong.format(state.in))}${key === "lacanau" ? ", dès 16 h" : ""}</span></p><p><span>Départ</span><span>${esc(fmtLong.format(state.out))}${key === "lacanau" ? ", avant 10 h" : ", avant 12 h"}</span></p>`;
    } else sum.hidden = true;
    $("#go-airbnb").href = airbnbLink();
    $("#book-msg").textContent = state.in && !state.out ? "Choisissez maintenant votre date de départ." : "";
    $("#book-msg").classList.remove("is-error");
    try { sessionStorage.setItem(`sp-${key}`, JSON.stringify({ in: state.in && iso(state.in), out: state.out && iso(state.out), adults: state.adults, children: state.children, infants: state.infants })); } catch (e) { /* ignoré */ }
    renderCal();
  }

  // Disponibilités réelles : lues dans le calendrier Airbnb par le petit serveur du site
  const status = $("#cal-status");
  status.textContent = "Les disponibilités exactes sont confirmées à l'étape suivante.";
  fetch(`api/calendrier/${key}`, { headers: { Accept: "application/json" } })
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (!data || !data.ok || !Array.isArray(data.booked)) return;
      const set = new Set();
      data.booked.forEach(([a, b]) => { for (let d = parse(a); d < parse(b); d = addDays(d, 1)) set.add(iso(d)); });
      booked = set;
      // Si les dates mémorisées ne sont plus libres, on les retire
      if (state.in && (isBooked(state.in) || (state.out && !rangeFree(state.in, state.out)))) { state.in = null; state.out = null; }
      status.textContent = "Disponibilités synchronisées avec le calendrier Airbnb.";
      update();
    })
    .catch(() => {});

  $("#go-airbnb").addEventListener("click", (e) => {
    if (!state.in || !state.out) {
      // Sans dates, on laisse ouvrir l'annonce mais on le signale
      $("#book-msg").textContent = "Astuce : choisissez vos dates pour voir directement le prix exact.";
    }
    return e;
  });

  /* ======================= Demande directe ======================= */
  const dlg = $("#dialog");
  let dlgReturn = null;
  const openDlg = () => {
    if (!state.in || !state.out) {
      const m = $("#book-msg");
      m.textContent = "Choisissez d'abord vos dates d'arrivée et de départ dans le calendrier.";
      m.classList.add("is-error");
      return;
    }
    dlgReturn = document.activeElement;
    $("#recap").innerHTML = `<strong>${esc(h.name)}</strong><br>${esc(stayText())}<br>${esc(guestsText())}`;
    $("#dlg-form").hidden = false;
    $("#dlg-done").hidden = true;
    dlg.classList.add("is-open");
    dlg.setAttribute("aria-hidden", "false");
    document.body.classList.add("is-locked");
    setTimeout(() => $("#d-name").focus(), 80);
  };
  const closeDlg = () => {
    dlg.classList.remove("is-open");
    dlg.setAttribute("aria-hidden", "true");
    document.body.classList.remove("is-locked");
    if (dlgReturn) dlgReturn.focus();
  };
  $("#go-direct").addEventListener("click", openDlg);
  $$("[data-close]", dlg).forEach((b) => b.addEventListener("click", closeDlg));
  dlg.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeDlg();
    if (e.key === "Tab") {
      const f = $$("button, input:not(.hp), textarea", dlg).filter((x) => x.offsetParent !== null);
      if (!f.length) return;
      if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f[f.length - 1].focus(); }
      else if (!e.shiftKey && document.activeElement === f[f.length - 1]) { e.preventDefault(); f[0].focus(); }
    }
  });

  const form = $("#form");
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const msg = $("#form-msg");
    const fd = Object.fromEntries(new FormData(form).entries());
    if (!fd.nom.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(fd.email.trim())) {
      msg.textContent = "Merci d'indiquer votre nom et une adresse e-mail valide.";
      msg.classList.add("is-error");
      (!fd.nom.trim() ? $("#d-name") : $("#d-email")).focus();
      return;
    }
    msg.classList.remove("is-error");
    msg.textContent = "Envoi en cours…";
    const btn = $('button[type="submit"]', form);
    btn.disabled = true;
    const payload = {
      ...fd, maison: h.name, arrivee: iso(state.in), depart: iso(state.out), nuits: nightsBetween(state.in, state.out),
      adultes: state.adults, enfants: state.children, bebes: state.infants, page: location.pathname,
    };
    let sent = false;
    try {
      const r = await fetch("api/demande", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
      sent = r.ok;
    } catch (err) { sent = false; }
    btn.disabled = false;
    msg.textContent = "";
    if (!sent) {
      // Pas de serveur (ou indisponible) : on prépare un e-mail, aucune demande n'est perdue
      const body = `Bonjour,\n\nJe souhaite réserver ${h.name} ${stayText()}, pour ${guestsText()}.\n\n${fd.message ? `${fd.message}\n\n` : ""}${fd.nom}\n${fd.email}${fd.telephone ? `\n${fd.telephone}` : ""}`;
      location.href = `mailto:${S.email}?subject=${encodeURIComponent(`Demande de réservation — ${h.name}`)}&body=${encodeURIComponent(body)}`;
      $("#done-text").textContent = "Votre messagerie s'ouvre avec la demande pré-remplie : il ne vous reste qu'à l'envoyer.";
    } else {
      $("#done-text").textContent = `Votre demande est bien partie. Nous vous répondons très vite à ${fd.email.trim()}.`;
      form.reset();
    }
    $("#dlg-form").hidden = true;
    $("#dlg-done").hidden = false;
    $("#dlg-done .btn").focus();
  });

  update();

  /* ======================= Carte (chargée quand on s'en approche) ======================= */
  const mapBox = $("#map");
  const loadMap = () => {
    const css = document.createElement("link");
    css.rel = "stylesheet";
    css.href = "vendor/leaflet/leaflet.css";
    document.head.appendChild(css);
    const js = document.createElement("script");
    js.src = "vendor/leaflet/leaflet.js";
    js.onload = () => {
      const L = window.L;
      const map = L.map(mapBox, { scrollWheelZoom: false, zoomControl: true, attributionControl: true }).setView([h.lat, h.lng], key === "lacanau" ? 14 : 15);
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 18,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      }).addTo(map);
      const color = getComputedStyle(document.body).getPropertyValue("--accent").trim() || "#12495a";
      L.circle([h.lat, h.lng], { radius: key === "lacanau" ? 250 : 350, color, weight: 1.5, fillColor: color, fillOpacity: 0.18 }).addTo(map);
      mapBox.removeAttribute("role");
    };
    document.head.appendChild(js);
  };
  if ("IntersectionObserver" in window) {
    const mo = new IntersectionObserver((en) => { if (en[0].isIntersecting) { mo.disconnect(); loadMap(); } }, { rootMargin: "400px" });
    mo.observe(mapBox);
  } else loadMap();

  /* Météo */
  const wbox = $("[data-weather]");
  if ("IntersectionObserver" in window) {
    const wo = new IntersectionObserver((en) => { if (en[0].isIntersecting) { wo.disconnect(); SP.weather(wbox, h.weather); } }, { rootMargin: "400px" });
    wo.observe(wbox.parentElement);
  } else SP.weather(wbox, h.weather);

  SP.observe(main);
  SP.parallax();
})();
