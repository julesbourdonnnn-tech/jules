/* Sable & Pierre — fiche d'une maison (lacanau.html, bordeaux.html) */
(function () {
  "use strict";
  const { $, $$, esc, icon, img, photo, srcset, reduced } = window.SP;
  const { DAY, today0, iso, parseISO: parse, addDays, nights: nightsBetween } = SP.dates;
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
  const price = h.priceFrom ? `À partir de ${h.priceFrom.toLocaleString("fr-FR")} € la nuit` : "";
  const firstWord = h.name.replace(/ (du|de) .*/, "");
  const lastWords = h.name.replace(/^La Maison /, "");
  const av = SP.availability(key);

  // Catégories de la visite photo, d'après la légende de chaque photo
  const CATS = [
    ["ext", "Extérieur", /piscine|jardin|patio|terrasse|maison et|maison,|ponton|coucher|salon d'extérieur/i],
    ["bed", "Chambres", /chambre/i],
    ["bath", "Salles de bain", /salle de bain|salle d'eau/i],
    ["live", "Pièces de vie", /./],
  ];
  const catOf = (cap) => CATS.find((c) => c[2].test(cap))[0];

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
          <h1><span class="split-line"><span>${esc(firstWord)}</span></span><span class="split-line"><span><em>${esc(lastWords)}</em></span></span></h1>
          <p class="hero__facts">${h.guests} voyageurs · ${h.bedrooms} chambres · ${h.beds} lits · ${h.bathrooms} salles de bain</p>
        </div>
        <div class="hero__side">
          <p class="hero__count"><b>${ratingTxt}</b> ★ · ${h.reviewsCount} avis · Coup de cœur voyageurs</p>
          ${price ? `<p class="hero__price">${esc(price)}</p>` : ""}
          <div class="hero__bars" role="group" aria-label="Choisir une photo">${h.hero.map((n, i) => `<button type="button" aria-label="Photo ${i + 1}"${i === 0 ? ' class="is-active"' : ""}><i></i></button>`).join("")}</div>
          <div class="hero__btns">
            <button type="button" class="btn btn--outline-light" data-open-tour>${icon("grid")} Les ${gallery.length} photos</button>
            <button type="button" class="round-btn round-btn--light" data-share aria-label="Partager cette maison">${icon("share")}</button>
          </div>
        </div>
      </div>
    </div>
  </section>

  <nav class="sub-nav" aria-label="Sections de la page">
    <div class="wrap">
      <div class="sub-nav__links">
        <a href="#maison">La maison</a><a href="#photos">Photos</a><a href="#chambres">Chambres</a><a href="#equipements">Équipements</a><a href="#avis">Avis</a><a href="#reserver">Disponibilités</a><a href="#quartier">Le quartier</a><a href="#quand">Quand venir</a><a href="#infos">Infos pratiques</a>
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

  <section class="section section--paper levels-section" id="niveaux" aria-labelledby="lv-title">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">Plan de la maison</span><h2 class="h2" id="lv-title">Niveau <em>par niveau</em></h2></div>
        <p>Choisissez un niveau pour voir ce qu'il contient.</p>
      </div>
      <div class="levels">
        <div class="levels__plan">${planSvg()}</div>
        <div class="levels__info">
          <div class="levels__tabs" role="tablist" aria-label="Niveaux de la maison">
            ${h.levels.map((l, i) => `<button type="button" role="tab" id="lv-tab-${i}" aria-controls="lv-panel" aria-selected="${i === 0}" data-level="${i}"${i ? ' tabindex="-1"' : ""}>${esc(l.short)}</button>`).join("")}
          </div>
          <div class="levels__panel" id="lv-panel" role="tabpanel" aria-live="polite"></div>
        </div>
      </div>
    </div>
  </section>

  <section class="section" id="photos">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">En images</span><h2 class="h2">Entrez, <em>c'est ouvert</em></h2></div>
        <p>Cliquez sur une photo pour l'agrandir, puis faites défiler avec les flèches du clavier ou en glissant le doigt.</p>
      </div>
      <div class="mosaic">
        ${h.photos.slice(0, 10).map(([n, cap], i) => `<button type="button" class="reveal-img" data-open-gallery="${i}" data-label="${esc(cap)}" aria-label="Agrandir : ${esc(cap)}">${img(key, n, cap, "(max-width: 900px) 100vw, 50vw")}</button>`).join("")}
      </div>
      <div class="mosaic-more"><button type="button" class="btn btn--ghost" data-open-tour>${icon("grid")} Visiter pièce par pièce · ${gallery.length} photos</button></div>
    </div>
  </section>

  <section class="section section--paper" id="chambres">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">Où vous dormirez</span><h2 class="h2">${h.bedrooms} chambres, <em>${h.beds} lits</em></h2></div>
        <p>${key === "lacanau" ? "Deux chambres et une salle de bain de plain-pied, les quatre autres chambres à l'étage." : "Trois chambres, une salle de bain et un WC au rez-de-chaussée ; deux chambres, une salle d'eau et un WC en sous-sol ; la pièce de vie et la terrasse à l'étage."}</p>
      </div>
      <div class="beds">
        ${h.sleeping.map(([name, bed, n], i) => `
          <article class="bed reveal" data-delay="${i % 3}">
            <button type="button" class="bed__img" data-open-gallery="${idxOf(n)}" aria-label="Agrandir la photo : ${esc(name)}">${img(key, n, name, "(max-width: 600px) 100vw, 33vw")}</button>
            <div class="bed__body">${icon("bed")}<b>${esc(name)}</b><span>${esc(bed)}</span></div>
          </article>`).join("")}
      </div>
    </div>
  </section>

  <section class="section" id="equipements">
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

  <section class="section section--paper" id="avis">
    <div class="wrap">
      <div class="reviews-top">
        <div class="score reveal">
          <b class="score__num num">${ratingTxt}</b>
          <span class="score__stars" aria-hidden="true">★★★★★</span>
          <span class="score__count">${h.reviewsCount} avis vérifiés sur Airbnb</span>
          <span class="score__badge">${icon("award")} Coup de cœur voyageurs</span>
        </div>
        <div class="reveal" data-delay="1">
          <h2 class="h3">Les notes en détail</h2>
          <div class="ratings">${h.categoryRatings.map(([l, v]) => `<p class="rating-row"><span>${esc(l)}</span><i style="--v:${Number(v.replace(",", ".")) / 5}"></i><b>${esc(v)}</b></p>`).join("")}</div>
        </div>
        <div class="reveal" data-delay="2">
          <h2 class="h3">Répartition</h2>
          <div class="ratings">${h.ratingDistribution.map((p, i) => `<p class="rating-row rating-row--dist"><span>${5 - i} ★</span><i style="--v:${p / 100}"></i><b>${p} %</b></p>`).join("")}</div>
        </div>
      </div>
      <div class="tags reveal" aria-label="Les sujets dont parlent les voyageurs">
        <span class="small">Ce dont parlent les voyageurs :</span>
        ${h.reviewTags.map(([t, n]) => `<span class="tag">${esc(t)} <b>${n}</b></span>`).join("")}
      </div>
      <div class="quote-grid" id="quote-grid">
        ${(window.REVIEWS[key] || []).map(([q, who, when], i) => `<figure class="quote-card reveal" data-delay="${i % 3}"${i > 5 ? " data-more-review hidden" : ""}><blockquote>${esc(q)}</blockquote><figcaption><span class="avatar-sm" aria-hidden="true">${esc(who.charAt(0))}</span>${esc(who)} · ${esc(when)}</figcaption></figure>`).join("")}
      </div>
      <div class="mosaic-more">
        ${(window.REVIEWS[key] || []).length > 6 ? `<button type="button" class="btn btn--ghost" id="more-reviews">Plus d'avis</button>` : ""}
        <a class="btn btn--ghost" href="${h.airbnbUrl}#reviews" target="_blank" rel="noopener">Les ${h.reviewsCount} avis sur Airbnb ${icon("external")}</a>
      </div>
      <p class="small" style="margin-top:18px;text-align:center">Extraits fidèles d'avis publiés par les voyageurs sur Airbnb (seule l'orthographe a été corrigée).</p>
    </div>
  </section>

  <section class="section section--sand" id="reserver">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">Disponibilités</span><h2 class="h2">Choisissez <em>vos dates</em></h2></div>
        <p>Les dates grisées sont déjà prises. Sélectionnez votre arrivée puis votre départ : vous réservez ensuite en ligne sur Airbnb, ou vous nous envoyez une demande directe.</p>
      </div>
      <div class="book-grid">
        <div class="cal" id="cal">
          <div class="cal__head">
            <button type="button" class="round-btn" data-cal="-1" aria-label="Mois précédent">${icon("left")}</button>
            <span class="cal__hint" id="cal-hint" aria-live="polite">Choisissez votre date d'arrivée</span>
            <button type="button" class="round-btn" data-cal="1" aria-label="Mois suivant">${arrow}</button>
          </div>
          <div class="cal__months" id="cal-months" role="group" aria-label="Calendrier des disponibilités"></div>
          <div class="cal__legend"><span><i class="lg lg--sel"></i>Votre séjour</span><span><i class="lg lg--off"></i>Déjà pris</span><span><i class="lg lg--today"></i>Aujourd'hui</span><span id="cal-min"></span></div>
          <div class="quick" id="quick" hidden><span class="small">Prochains week-ends libres :</span><div class="quick__list" id="quick-list"></div></div>
          <p class="cal__status" id="cal-status"></p>
        </div>
        <aside class="booking" aria-labelledby="book-title">
          <div class="booking__head">
            <h3 id="book-title">${esc(h.name)}</h3>
            <span class="booking__rate">★ ${ratingTxt} · ${h.reviewsCount} avis</span>
          </div>
          <p class="small">${price ? `${esc(price)} · ` : ""}${esc(h.place)} · jusqu'à ${h.guests} voyageurs</p>
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
          <button type="button" class="link booking__clear" id="clear-dates" hidden>Effacer les dates</button>
          <ul class="booking__trust">
            <li>${icon("shield")}<span>Réservation et paiement sécurisés par Airbnb, prix exact affiché pour vos dates</span></li>
            <li>${icon("award")}<span>Hôte Superhôte, logement « Coup de cœur voyageurs »</span></li>
            <li>${icon("calendar")}<span>${key === "lacanau" ? "Arrivée dès 16 h, départ avant 10 h" : "Arrivée autonome et flexible, départ avant 12 h"}</span></li>
          </ul>
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
          <div class="poi-filter" role="group" aria-label="Filtrer les repères"></div>
          <div class="map" id="map" role="img" aria-label="Carte du quartier de ${esc(h.name)}"></div>
          <p class="map-note">${key === "lacanau" ? "Le cercle indique le secteur de la maison : l'adresse exacte vous est communiquée à la réservation." : "Le cercle indique le secteur de la maison (emplacement approximatif) : l'adresse exacte vous est communiquée à la réservation."} Distances à vol d'oiseau.</p>
          <ol class="poi-list" id="poi-list"></ol>
        </div>
      </div>
      <ol class="dest-list" style="margin-top:72px">
        ${D.places.map(([t, dist, body]) => `<li><details><summary><h3>${esc(t)}</h3><span class="dist">${esc(dist)}</span><span class="plus" aria-hidden="true"></span></summary><p>${esc(body)}</p></details></li>`).join("")}
      </ol>
    </div>
  </section>

  <section class="section section--paper" id="quand" data-climate-section aria-labelledby="quand-title">
    <div class="wrap">
      <div class="section-head">
        <div><span class="eyebrow">Quand venir</span><h2 class="h2" id="quand-title">Le temps <em>qu'il fait</em></h2></div>
        <p>Les températures et la pluie mois par mois à ${key === "lacanau" ? "Lacanau, avec la température de l'océan" : "Bordeaux"}, d'après dix ans de relevés. Survolez ou choisissez un mois.</p>
      </div>
      <div class="clim" id="clim"></div>
    </div>
  </section>

  <section class="section" id="infos">
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
    <div><b>${esc(h.name)}</b><span id="mbar-sub">★ ${ratingTxt} · ${h.reviewsCount} avis · ${h.guests} voyageurs</span></div>
    <a class="btn btn--accent" href="#reserver" id="mbar-btn">Voir les dates</a>
  </div>

  <div class="tour" id="tour" role="dialog" aria-modal="true" aria-label="Toutes les photos" hidden>
    <div class="tour__bar">
      <div class="tour__chips" role="group" aria-label="Pièces">
        <button type="button" class="chip" data-cat="all" aria-pressed="true">Tout · ${gallery.length}</button>
        ${CATS.map(([id, name]) => { const n = h.photos.filter((p) => catOf(p[1]) === id).length; return n ? `<button type="button" class="chip" data-cat="${id}" aria-pressed="false">${name} · ${n}</button>` : ""; }).join("")}
      </div>
      <button type="button" class="round-btn" data-close-tour aria-label="Fermer">${icon("close")}</button>
    </div>
    <div class="tour__grid" id="tour-grid">
      ${h.photos.map(([n, cap], i) => `<button type="button" class="tour__item" data-cat="${catOf(cap)}" data-open-gallery="${i}" aria-label="Agrandir : ${esc(cap)}"><img src="${photo(key, n, "md")}" alt="${esc(cap)}" loading="lazy"><span>${esc(cap)}</span></button>`).join("")}
    </div>
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
          <div class="field full"><label for="d-msg">Votre message</label><textarea id="d-msg" name="message" maxlength="2000" placeholder="L'occasion de votre séjour, une arrivée tardive, vos questions…"></textarea></div>
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

  // Coupe de la maison : un étage par niveau, cliquable
  function planSvg() {
    const L = h.levels;
    const ext = L.findIndex((l) => l.short === "Extérieur");
    const RANK = { "Étage": 0, "Rez-de-chaussée": 1, "Sous-sol": 2 };
    const floors = L.map((l, i) => ({ l, i })).filter((x) => x.i !== ext).sort((a, b) => RANK[a.l.short] - RANK[b.l.short]);
    const W = 420;
    const fh = 64;
    const top = 70;
    // Les niveaux sont listés du haut vers le bas
    const rows = floors.map((x, k) => {
      const y = top + k * fh;
      return `<g class="plan__lvl" data-level="${x.i}" tabindex="-1">
        <rect x="70" y="${y}" width="280" height="${fh - 6}" rx="2"/>
        <text x="210" y="${y + fh / 2 + 2}" text-anchor="middle">${esc(x.l.short)}</text></g>`;
    }).join("");
    const groundY = top + floors.length * fh - 6;
    const roof = key === "lacanau"
      ? `<path class="plan__roof" d="M56 ${top - 4} L210 ${top - 58} L364 ${top - 4}"/>`
      : `<path class="plan__roof" d="M70 ${top - 6} H350 M150 ${top - 6} L180 ${top - 40} H300 L330 ${top - 6}"/><text class="plan__note" x="240" y="${top - 16}" text-anchor="middle">verrière</text>`;
    const below = L.some((l) => l.short === "Sous-sol");
    const garden = ext >= 0
      ? `<g class="plan__lvl plan__lvl--ext" data-level="${ext}" tabindex="-1"><path d="M0 ${groundY + 2} H70 M350 ${groundY + 2} H${W}"/><rect x="368" y="${groundY - 22}" width="46" height="18" rx="2" class="plan__pool"/><text x="391" y="${groundY + 22}" text-anchor="middle">jardin</text></g>`
      : "";
    return `<svg viewBox="0 0 ${W} ${groundY + 40}" role="img" aria-label="Coupe schématique de la maison">
      ${roof}${rows}
      <line class="plan__ground" x1="0" x2="${W}" y1="${below ? groundY - fh + 2 : groundY + 2}" y2="${below ? groundY - fh + 2 : groundY + 2}"/>
      ${garden}
    </svg>`;
  }

  /* ======================= Niveaux ======================= */
  const lvTabs = $$(".levels__tabs [role=tab]");
  const lvPanel = $("#lv-panel");
  const showLevel = (i, focus) => {
    const l = h.levels[i];
    lvTabs.forEach((t, j) => { t.setAttribute("aria-selected", String(j === i)); t.tabIndex = j === i ? 0 : -1; });
    $$(".plan__lvl").forEach((g) => g.classList.toggle("is-on", Number(g.dataset.level) === i));
    lvPanel.setAttribute("aria-labelledby", `lv-tab-${i}`);
    lvPanel.innerHTML = `
      ${l.photo ? `<button type="button" class="levels__photo" data-open-gallery="${idxOf(l.photo)}" aria-label="Agrandir : ${esc(capOf(l.photo))}">${img(key, l.photo, capOf(l.photo), "(max-width: 900px) 100vw, 40vw")}</button>` : ""}
      <h3 class="h3">${esc(l.name)}</h3>
      <ul class="levels__list">${l.items.map((t) => `<li>${icon("check")}<span>${esc(t)}</span></li>`).join("")}</ul>`;
    if (focus) lvTabs[i].focus();
  };
  lvTabs.forEach((t, i) => {
    t.addEventListener("click", () => showLevel(i));
    t.addEventListener("keydown", (e) => {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
      e.preventDefault();
      showLevel((i + (e.key === "ArrowRight" ? 1 : -1) + lvTabs.length) % lvTabs.length, true);
    });
  });
  $$(".plan__lvl").forEach((g) => {
    g.addEventListener("click", () => showLevel(Number(g.dataset.level)));
    g.addEventListener("mouseenter", () => showLevel(Number(g.dataset.level)));
  });
  showLevel(0);

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

  /* ======================= Photos : visionneuse et visite ======================= */
  const tour = $("#tour");
  let tourReturn = null;
  const openTour = () => {
    tourReturn = document.activeElement;
    tour.hidden = false;
    requestAnimationFrame(() => tour.classList.add("is-open"));
    document.body.classList.add("is-locked");
    setTimeout(() => $("[data-close-tour]", tour).focus(), 50);
  };
  const closeTour = () => {
    tour.classList.remove("is-open");
    document.body.classList.remove("is-locked");
    setTimeout(() => { tour.hidden = true; }, 350);
    if (tourReturn) tourReturn.focus();
  };
  main.addEventListener("click", (e) => {
    const b = e.target.closest("[data-open-gallery]");
    if (b) {
      const inTour = !!b.closest("#tour");
      if (inTour) {
        // Dans la visite, la visionneuse suit le filtre en cours
        const items = $$(".tour__item", tour).filter((x) => !x.hidden);
        const list = items.map((x) => gallery[Number(x.dataset.openGallery)]);
        SP.openLightbox(list, items.indexOf(b));
      } else SP.openLightbox(gallery, Number(b.dataset.openGallery));
      return;
    }
    if (e.target.closest("[data-open-tour]")) openTour();
    if (e.target.closest("[data-close-tour]")) closeTour();
    if (e.target.closest("[data-share]")) SP.share(`${h.name} — ${h.place}`);
  });
  tour.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !document.querySelector(".lb.is-open")) closeTour();
  });
  $$(".tour__chips .chip", tour).forEach((c) => c.addEventListener("click", () => {
    $$(".tour__chips .chip", tour).forEach((x) => x.setAttribute("aria-pressed", String(x === c)));
    $$(".tour__item", tour).forEach((it) => { it.hidden = c.dataset.cat !== "all" && it.dataset.cat !== c.dataset.cat; });
    $("#tour-grid").scrollTop = 0;
  }));

  /* ======================= Lire la suite / équipements / avis ======================= */
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
  const moreRev = $("#more-reviews");
  if (moreRev) moreRev.addEventListener("click", () => {
    $$("[data-more-review]").forEach((g) => { g.hidden = false; g.classList.add("is-in"); });
    moreRev.remove();
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

  /* ======================= Barre de réservation fixe ======================= */
  const mbar = $("#mbar");
  const hero = $(".hero");
  const reserve = $("#reserver");
  document.body.classList.add("has-mbar");
  const mbarUpdate = () => {
    const pastHero = hero.getBoundingClientRect().bottom < 0;
    const r = reserve.getBoundingClientRect();
    const inReserve = r.top < window.innerHeight * 0.8 && r.bottom > 0;
    const f = document.querySelector(".footer");
    const atFooter = f && f.getBoundingClientRect().top < window.innerHeight;
    mbar.classList.toggle("is-visible", pastHero && !inReserve && !atFooter);
  };
  window.addEventListener("scroll", mbarUpdate, { passive: true });
  mbarUpdate();

  /* ======================= Calendrier et réservation ======================= */
  const today = today0();
  const fmt = new Intl.DateTimeFormat("fr-FR", { weekday: "short", day: "numeric", month: "short" });
  const fmtShort = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short" });
  const fmtLong = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
  const fmtMonth = new Intl.DateTimeFormat("fr-FR", { month: "long", year: "numeric" });
  const plural = (n, w) => `${n} ${w}${n > 1 ? "s" : ""}`;

  const state = { in: null, out: null, adults: 1, children: 0, infants: 0 };
  const limits = { infants: key === "bordeaux" ? 0 : 5 };
  let monthOffset = 0;
  let focusDate = null;

  // Dates reprises de l'adresse (?arrivee=…&depart=…&voyageurs=…) ou de la visite précédente
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
  } catch (e) { /* stockage indisponible : on part de zéro */ }
  const validateState = () => {
    if (state.in && !av.canIn(state.in)) { state.in = null; state.out = null; }
    if (state.in && state.out && av.outProblem(state.in, state.out)) state.out = null;
  };
  validateState();
  if (state.in) monthOffset = Math.max(0, (state.in.getFullYear() - today.getFullYear()) * 12 + state.in.getMonth() - today.getMonth());

  const monthsBox = $("#cal-months");
  const hint = $("#cal-hint");
  const REASON = { taken: "nuit déjà prise dans la période", short: "séjour trop court", long: "séjour trop long", noout: "départ impossible ce jour-là" };
  const renderCal = () => {
    const html = [];
    for (let m = 0; m < 2; m++) {
      const first = new Date(today.getFullYear(), today.getMonth() + monthOffset + m, 1);
      const startDow = (first.getDay() + 6) % 7; // lundi = 0
      const days = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
      const cells = ["lu", "ma", "me", "je", "ve", "sa", "di"].map((d) => `<span class="cal__dow" aria-hidden="true">${d}</span>`);
      for (let i = 0; i < startDow; i++) cells.push("<span></span>");
      const choosingOut = state.in && !state.out;
      for (let d = 1; d <= days; d++) {
        const date = new Date(first.getFullYear(), first.getMonth(), d);
        const t = date.getTime();
        const cls = ["cal__day"];
        let disabled = date < today;
        let why = "";
        const free = av.nightFree(date);
        if (!free) cls.push("is-booked");
        if (t === today.getTime()) cls.push("is-today");
        if (choosingOut && date > state.in) {
          const p = av.outProblem(state.in, date);
          if (p) { disabled = true; why = REASON[p] || ""; if (p === "short") cls.push("is-short"); }
          else if (!free) cls.push("is-checkout-only");
        } else if (!disabled && !av.canIn(date)) {
          disabled = true;
          why = free ? "arrivée impossible ce jour-là" : "déjà pris";
        }
        if (state.in && t === state.in.getTime()) cls.push("is-start");
        if (state.out && t === state.out.getTime()) cls.push("is-end");
        if (state.in && state.out && date > state.in && date < state.out) cls.push("is-range");
        if (choosingOut && t === state.in.getTime()) cls.push("is-end");
        const label = `${fmtLong.format(date)}${why ? `, ${why}` : ""}`;
        const sel = cls.includes("is-start") || cls.includes("is-end");
        cells.push(`<button type="button" class="${cls.join(" ")}" data-date="${iso(date)}" aria-label="${label}" title="${why ? why.charAt(0).toUpperCase() + why.slice(1) : ""}"${disabled ? ' aria-disabled="true" data-off' : ""}${sel ? ' aria-pressed="true"' : ""} tabindex="-1">${d}</button>`);
      }
      html.push(`<div class="cal__month"><h3>${fmtMonth.format(first)}</h3><div class="cal__grid">${cells.join("")}</div></div>`);
    }
    monthsBox.innerHTML = html.join("");
    // Un seul jour atteignable à la tabulation : le jour actif, sinon le premier possible
    const target = (focusDate && $(`[data-date="${iso(focusDate)}"]`, monthsBox)) || $(".cal__day.is-start", monthsBox) || $(".cal__day:not([data-off])", monthsBox) || $(".cal__day", monthsBox);
    if (target) target.tabIndex = 0;
    $('[data-cal="-1"]').disabled = monthOffset <= 0;
    $('[data-cal="1"]').disabled = monthOffset >= 22;
    const minN = state.in ? av.minNights(state.in) : 0;
    hint.textContent = !state.in ? "Choisissez votre date d'arrivée"
      : !state.out ? `Choisissez votre départ${minN > 1 ? ` (${minN} nuits minimum)` : ""}`
        : `${plural(nightsBetween(state.in, state.out), "nuit")} sélectionnée${nightsBetween(state.in, state.out) > 1 ? "s" : ""}`;
  };

  const pick = (d) => {
    if (!state.in || state.out || d <= state.in) {
      if (!av.canIn(d)) return false;
      state.in = d; state.out = null;
    } else if (!av.outProblem(state.in, d)) {
      state.out = d;
    } else if (av.canIn(d)) {
      state.in = d; state.out = null;
    } else return false;
    return true;
  };
  monthsBox.addEventListener("click", (e) => {
    const b = e.target.closest("button[data-date]");
    if (!b) return;
    const d = parse(b.dataset.date);
    if (b.hasAttribute("data-off")) {
      const m = $("#book-msg");
      if (state.in && !state.out && d > state.in && av.outProblem(state.in, d) === "short") m.textContent = `Le séjour minimum est de ${av.minNights(state.in)} nuits à partir de cette date.`;
      else m.textContent = b.title ? `${b.title}.` : "";
      m.classList.add("is-error");
      return;
    }
    if (!pick(d)) return;
    focusDate = d;
    update();
    if (e.detail === 0) { const again = $(`button[data-date="${b.dataset.date}"]`, monthsBox); if (again) again.focus(); }
  });
  // Navigation au clavier dans le calendrier : flèches, début / fin de semaine, mois
  monthsBox.addEventListener("keydown", (e) => {
    const b = e.target.closest("button[data-date]");
    if (!b) return;
    const moves = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 };
    let d = parse(b.dataset.date);
    if (moves[e.key] !== undefined) d = addDays(d, moves[e.key]);
    else if (e.key === "PageDown") d = new Date(d.getFullYear(), d.getMonth() + 1, d.getDate());
    else if (e.key === "PageUp") d = new Date(d.getFullYear(), d.getMonth() - 1, d.getDate());
    else if (e.key === "Home") d = addDays(d, -((d.getDay() + 6) % 7));
    else if (e.key === "End") d = addDays(d, 6 - ((d.getDay() + 6) % 7));
    else return;
    e.preventDefault();
    if (d < today) d = today;
    focusDate = d;
    const off = (d.getFullYear() - today.getFullYear()) * 12 + d.getMonth() - today.getMonth();
    if (off < monthOffset) monthOffset = Math.max(0, off);
    else if (off > monthOffset + 1) monthOffset = Math.min(22, off - 1);
    renderCal();
    const n = $(`button[data-date="${iso(d)}"]`, monthsBox);
    if (n) n.focus();
  });
  monthsBox.addEventListener("mouseover", (e) => {
    const b = e.target.closest("button[data-date]");
    if (!b || !state.in || state.out) return;
    const d = parse(b.dataset.date);
    const ok = !b.hasAttribute("data-off") && d > state.in;
    $$("button[data-date]", monthsBox).forEach((x) => {
      const xd = parse(x.dataset.date);
      x.classList.toggle("is-range", ok && xd > state.in && xd < d);
      x.classList.toggle("is-end", ok ? xd.getTime() === d.getTime() : xd.getTime() === state.in.getTime());
    });
  });
  monthsBox.addEventListener("mouseleave", () => { if (state.in && !state.out) renderCal(); });
  $$("[data-cal]").forEach((b) => b.addEventListener("click", () => {
    monthOffset = Math.max(0, Math.min(22, monthOffset + Number(b.dataset.cal)));
    renderCal();
  }));
  $$("[data-focus-cal]").forEach((b) => b.addEventListener("click", () => {
    $("#cal").scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "center" });
    const first = $(".cal__day[tabindex='0']", monthsBox);
    if (first) setTimeout(() => first.focus({ preventScroll: true }), 400);
  }));
  $("#clear-dates").addEventListener("click", () => { state.in = null; state.out = null; focusDate = null; update(); });

  // Prochains week-ends libres, en un clic
  const quick = av.known ? av.nextWeekends(3) : [];
  if (quick.length) {
    $("#quick").hidden = false;
    $("#quick-list").innerHTML = quick.map(([a, b]) => `<button type="button" class="chip" data-quick="${iso(a)}|${iso(b)}">${fmtShort.format(a)} → ${fmtShort.format(b)}</button>`).join("");
    $("#quick-list").addEventListener("click", (e) => {
      const c = e.target.closest("[data-quick]");
      if (!c) return;
      const [a, b] = c.dataset.quick.split("|").map(parse);
      state.in = a; state.out = b;
      monthOffset = Math.max(0, (a.getFullYear() - today.getFullYear()) * 12 + a.getMonth() - today.getMonth());
      update();
    });
  }

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
    const v = state[k] + Number(b.dataset.d);
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
    let t = plural(n, "voyageur");
    if (state.infants) t += `, ${plural(state.infants, "bébé")}`;
    return t;
  };
  const stayText = () => (state.in && state.out ? `du ${fmtLong.format(state.in)} au ${fmtLong.format(state.out)} (${plural(nightsBetween(state.in, state.out), "nuit")})` : "dates à définir");

  function update() {
    $("#f-in").textContent = state.in ? fmt.format(state.in) : "Ajouter une date";
    $("#f-out").textContent = state.out ? fmt.format(state.out) : "Ajouter une date";
    $("#f-guests").textContent = guestsText();
    ["adults", "children", "infants"].forEach((k) => { $(`#n-${k}`).textContent = state[k]; });
    $('[data-step="adults"][data-d="-1"]').disabled = state.adults <= 1;
    $('[data-step="adults"][data-d="1"]').disabled = state.adults + state.children >= h.guests;
    $('[data-step="children"][data-d="-1"]').disabled = state.children <= 0;
    $('[data-step="children"][data-d="1"]').disabled = state.adults + state.children >= h.guests;
    $('[data-step="infants"][data-d="-1"]').disabled = state.infants <= 0;
    $('[data-step="infants"][data-d="1"]').disabled = state.infants >= limits.infants;
    const sum = $("#summary");
    if (state.in && state.out) {
      const n = nightsBetween(state.in, state.out);
      sum.hidden = false;
      sum.innerHTML = `<p><span>Séjour</span><strong>${plural(n, "nuit")}</strong></p><p><span>Arrivée</span><span>${esc(fmtLong.format(state.in))}${key === "lacanau" ? ", dès 16 h" : ""}</span></p><p><span>Départ</span><span>${esc(fmtLong.format(state.out))}${key === "lacanau" ? ", avant 10 h" : ", avant 12 h"}</span></p>${av.known ? `<p class="ok">${icon("check")}<span>Ces dates sont libres dans le calendrier</span></p>` : ""}`;
    } else sum.hidden = true;
    $("#go-airbnb").href = airbnbLink();
    const msg = $("#book-msg");
    msg.classList.remove("is-error");
    msg.textContent = state.in && !state.out ? `Choisissez maintenant votre date de départ${av.minNights(state.in) > 1 ? ` (${av.minNights(state.in)} nuits minimum)` : ""}.` : "";
    $("#clear-dates").hidden = !state.in;
    // Barre fixe : rappel des dates
    $("#mbar-sub").textContent = state.in && state.out ? `${fmtShort.format(state.in)} → ${fmtShort.format(state.out)} · ${guestsText()}` : `★ ${ratingTxt} · ${h.reviewsCount} avis · ${h.guests} voyageurs`;
    $("#mbar-btn").textContent = state.in && state.out ? "Réserver" : "Voir les dates";
    try { sessionStorage.setItem(`sp-${key}`, JSON.stringify({ in: state.in && iso(state.in), out: state.out && iso(state.out), adults: state.adults, children: state.children, infants: state.infants })); } catch (e) { /* ignoré */ }
    renderCal();
  }

  // État de la synchronisation
  const status = $("#cal-status");
  const setStatus = () => {
    if (av.known && av.updated) {
      const d = new Date(av.updated);
      status.textContent = `Disponibilités synchronisées avec le calendrier Airbnb (mise à jour du ${new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" }).format(d)}). Airbnb confirme vos dates à l'étape suivante.`;
    } else status.textContent = "Airbnb confirme vos dates à l'étape suivante.";
  };
  setStatus();
  const minAll = av.known ? av.minNights(today) : 0;
  if (minAll > 1) $("#cal-min").innerHTML = `<i class="lg lg--min"></i>${minAll} nuits minimum`;
  // Synchronisation iCal du serveur (si elle est réglée) : on l'ajoute
  fetch(`api/calendrier/${key}`, { headers: { Accept: "application/json" } })
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => {
      if (!data || !data.ok || !Array.isArray(data.booked)) return;
      const list = [];
      data.booked.forEach(([a, b]) => { for (let d = parse(a); d < parse(b); d = addDays(d, 1)) list.push(iso(d)); });
      av.addBooked(list);
      validateState();
      update();
    })
    .catch(() => {});

  $("#go-airbnb").addEventListener("click", () => {
    if (!state.in || !state.out) $("#book-msg").textContent = "Astuce : choisissez vos dates pour voir directement le prix exact.";
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
  const trap = (box, e) => {
    if (e.key !== "Tab") return;
    const f = $$("button, a[href], input:not(.hp), textarea", box).filter((x) => x.offsetParent !== null && !x.hidden);
    if (!f.length) return;
    if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f[f.length - 1].focus(); }
    else if (!e.shiftKey && document.activeElement === f[f.length - 1]) { e.preventDefault(); f[0].focus(); }
  };
  dlg.addEventListener("keydown", (e) => { if (e.key === "Escape") closeDlg(); trap(dlg, e); });
  tour.addEventListener("keydown", (e) => trap(tour, e));

  const form = $("#form");
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const msg = $("#form-msg");
    const fd = {};
    new FormData(form).forEach((v, k) => { fd[k] = String(v); });
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
    const payload = Object.assign({}, fd, {
      maison: h.name, arrivee: iso(state.in), depart: iso(state.out), nuits: nightsBetween(state.in, state.out),
      adultes: state.adults, enfants: state.children, bebes: state.infants, page: location.pathname,
    });
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
      $("#done-text").innerHTML = `Votre messagerie s'ouvre avec la demande pré-remplie : il ne vous reste qu'à l'envoyer. Si rien ne s'ouvre, écrivez-nous à <strong>${esc(S.email)}</strong>.`;
    } else {
      $("#done-text").textContent = `Votre demande est bien partie. Nous vous répondons très vite à ${fd.email.trim()}.`;
      form.reset();
    }
    $("#dlg-form").hidden = true;
    $("#dlg-done").hidden = false;
    $("#dlg-done .btn").focus();
  });

  update();

  /* ======================= Carte et repères ======================= */
  const R = 6371;
  const rad = (x) => (x * Math.PI) / 180;
  const dist = (a, b, c, d) => 2 * R * Math.asin(Math.sqrt(Math.sin(rad(c - a) / 2) ** 2 + Math.cos(rad(a)) * Math.cos(rad(c)) * Math.sin(rad(d - b) / 2) ** 2));
  const POI_CATS = { walk: "À pied", beach: "Plages", wine: "Vignobles", city: "Ville", travel: "Gare et aéroport" };
  const POI_ICONS = { walk: "walk", beach: "wave", wine: "leaf", city: "pin", travel: "pin" };
  const pois = h.poi.map(([cat, name, lat, lng], i) => {
    const km = dist(h.lat, h.lng, lat, lng);
    return { i, cat, name, lat, lng, km };
  }).sort((a, b) => a.km - b.km);
  const kmTxt = (km) => (km < 0.95 ? `${Math.round(km * 10) * 100} m` : `${km < 10 ? fr(km.toFixed(1)) : Math.round(km)} km`);
  // Temps de marche indicatif : distance à vol d'oiseau majorée de 20 %, à 5 km/h
  const walkTxt = (km) => (km < 3 ? ` · environ ${Math.max(5, Math.round((km * 1.2) / 5 * 60 / 5) * 5)} min à pied` : "");
  const cats = Object.keys(POI_CATS).filter((c) => pois.some((p) => p.cat === c));
  let poiCat = key === "bordeaux" ? "walk" : "all";
  $(".poi-filter").innerHTML = [`<button type="button" class="chip" data-poi="all" aria-pressed="${poiCat === "all"}">Tout</button>`]
    .concat(cats.map((c) => `<button type="button" class="chip" data-poi="${c}" aria-pressed="${poiCat === c}">${POI_CATS[c]}</button>`)).join("");
  const list = $("#poi-list");
  let map = null;
  let markers = {};
  const renderPois = () => {
    const shown = pois.filter((p) => poiCat === "all" || p.cat === poiCat);
    list.innerHTML = shown.map((p) => `<li><button type="button" data-poi-id="${p.i}">${icon(POI_ICONS[p.cat])}<span>${esc(p.name)}</span><b>${kmTxt(p.km)}${walkTxt(p.km)}</b></button></li>`).join("");
    if (map) {
      Object.values(markers).forEach((m) => m.remove());
      markers = {};
      const L = window.L;
      shown.forEach((p) => {
        markers[p.i] = L.marker([p.lat, p.lng], { icon: L.divIcon({ className: "poi-pin", html: `<span>${icon(POI_ICONS[p.cat])}</span>`, iconSize: [30, 30], iconAnchor: [15, 15] }), title: p.name, keyboard: false })
          .bindTooltip(`${esc(p.name)} · ${kmTxt(p.km)}`, { direction: "top", offset: [0, -14] }).addTo(map);
      });
      const pts = shown.map((p) => [p.lat, p.lng]).concat([[h.lat, h.lng]]);
      map.fitBounds(pts, { padding: [36, 36], maxZoom: 15 });
    }
  };
  $(".poi-filter").addEventListener("click", (e) => {
    const c = e.target.closest("[data-poi]");
    if (!c) return;
    poiCat = c.dataset.poi;
    $$(".poi-filter .chip").forEach((x) => x.setAttribute("aria-pressed", String(x === c)));
    renderPois();
  });
  list.addEventListener("click", (e) => {
    const b = e.target.closest("[data-poi-id]");
    if (!b || !map) return;
    const p = pois.find((x) => x.i === Number(b.dataset.poiId));
    map.flyTo([p.lat, p.lng], Math.max(map.getZoom(), 13), { duration: reduced ? 0 : 0.8 });
    if (markers[p.i]) markers[p.i].openTooltip();
  });
  list.addEventListener("mouseover", (e) => {
    const b = e.target.closest("[data-poi-id]");
    if (b && markers[b.dataset.poiId]) markers[b.dataset.poiId].openTooltip();
  });
  renderPois();

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
      map = L.map(mapBox, { scrollWheelZoom: false, zoomControl: true, attributionControl: true }).setView([h.lat, h.lng], key === "lacanau" ? 14 : 15);
      L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 18,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      }).addTo(map);
      const color = getComputedStyle(document.body).getPropertyValue("--accent").trim() || "#12495a";
      L.circle([h.lat, h.lng], { radius: key === "lacanau" ? 250 : 350, color, weight: 1.5, fillColor: color, fillOpacity: 0.18 }).addTo(map);
      L.marker([h.lat, h.lng], { icon: L.divIcon({ className: "home-pin", html: `<span>${esc(h.name)}</span>`, iconSize: null }), keyboard: false, interactive: false }).addTo(map);
      mapBox.removeAttribute("role");
      renderPois();
    };
    document.head.appendChild(js);
  };
  if ("IntersectionObserver" in window) {
    const mo = new IntersectionObserver((en) => { if (en[0].isIntersecting) { mo.disconnect(); loadMap(); } }, { rootMargin: "400px" });
    mo.observe(mapBox);
  } else loadMap();

  /* Météo en direct et climat */
  const wbox = $("[data-weather]");
  if ("IntersectionObserver" in window) {
    const wo = new IntersectionObserver((en) => { if (en[0].isIntersecting) { wo.disconnect(); SP.weather(wbox, h.weather); } }, { rootMargin: "400px" });
    wo.observe(wbox.parentElement);
  } else SP.weather(wbox, h.weather);
  SP.climate($("#clim"), key, state.in ? state.in.getMonth() : undefined);

  SP.observe(main);
  SP.parallax();
})();
