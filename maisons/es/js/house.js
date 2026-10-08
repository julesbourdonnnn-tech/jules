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
  const pct = Number((window.TARIFS || {}).remiseDirecte) || 0;
  const from = window.SP_FROM ? window.SP_FROM(key) : h.priceFrom;
  const price = from ? `Desde ${from.toLocaleString("es-ES")} € la noche reservando directamente` : "";
  const firstWord = h.name.replace(/ (du|de) .*/, "");
  const lastWords = h.name.replace(/^La Maison /, "");
  const av = SP.availability(key);

  // Catégories de la visite photo, d'après la légende de chaque photo
  const CATS = [
    ["ext", "Exterior", /piscine|jardin|patio|terrasse|maison et|maison,|ponton|coucher|salon d'extérieur/i],
    ["bed", "Dormitorios", /chambre/i],
    ["bath", "Baños", /salle de bain|salle d'eau/i],
    ["live", "Zonas de estar", /./],
  ];
  // (3e élément de la photo : catégorie déjà calculée, pour les versions traduites)
  const catOf = (cap, cat) => cat || CATS.find((c) => c[2].test(cap))[0];

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
          <p class="hero__facts">${h.guests} viajeros · ${h.bedrooms} dormitorios · ${h.beds} camas · ${h.bathrooms} baños</p> </div> <div class="hero__side"> <p class="hero__count"><b>${ratingTxt}</b> ★ · ${h.reviewsCount} reseñas · Favorito de los viajeros</p>
          ${price ? `<p class="hero__price">${esc(price)}</p>` : ""}
          <div class="hero__bars" role="group" aria-label="Elegir una foto">${h.hero.map((n, i) => `<button type="button" aria-label="Photo ${i + 1}"${i === 0 ? ' class="is-active"' : ""}><i></i></button>`).join("")}</div>
          <div class="hero__btns">
            <button type="button" class="btn btn--outline-light" data-open-tour>${icon("grid")} Las ${gallery.length} fotos</button> <button type="button" class="round-btn round-btn--light" data-share aria-label="Compartir esta casa">${icon("share")}</button> </div> </div> </div> </div> </section> <nav class="sub-nav" aria-label="Secciones de la página"> <div class="wrap"> <div class="sub-nav__links"> <a href="#maison">La casa</a><a href="#photos">Fotos</a><a href="#chambres">Dormitorios</a><a href="#equipements">Equipamiento</a><a href="#avis">Reseñas</a><a href="#reserver">Disponibilidad</a><a href="#quartier">El barrio</a><a href="#quand">Cuándo venir</a><a href="#infos">Información práctica</a> </div> <a class="btn btn--accent" href="#reserver">Reservar</a> </div> </nav> <section class="section" id="maison"> <div class="wrap"> <div class="intro-grid"> <div> <span class="eyebrow reveal">${esc(h.type)} · ${esc(h.region)}</span>
          <h2 class="h2 reveal" style="margin-top:18px">${esc(h.tagline)}</h2>
          <div class="keyfacts reveal">
            <div><b class="num">${h.guests}</b><span>viajeros</span></div> <div><b class="num">${h.bedrooms}</b><span>dormitorios</span></div> <div><b class="num">${h.beds}</b><span>camas</span></div> <div><b class="num">${h.bathrooms}</b><span>baños</span></div> </div> <p class="lead reveal">${esc(h.teaser)}</p> <h3 class="eyebrow eyebrow--plain reveal" style="margin:34px 0 14px">Unas palabras de tus anfitriones</h3> <div class="prose readmore reveal" id="desc">
            ${h.description.map((d) => `${d.title ? `<h3>${esc(d.title)}</h3>` : ""}<p>${esc(d.text)}</p>`).join("")}
          </div> <button type="button" class="link" id="desc-more" style="margin-top:18px" aria-controls="desc" aria-expanded="false">Leer más</button> </div> <aside> <ul class="highlights">
            ${h.highlights.map(([ic, t, s], i) => `<li class="reveal" data-delay="${i}">${icon(ic)}<div><b>${esc(t)}</b><span>${esc(s)}</span></div></li>`).join("")}
          </ul>
          <div class="host-card reveal">
            <span class="avatar" aria-hidden="true">${icon("award")}</span> <div><b>Favorito de los viajeros</b><span>Uno de los alojamientos favoritos de los viajeros en Airbnb · Superanfitrión</span></div> </div> </aside> </div> </div> </section> <section class="section section--paper levels-section" id="niveaux" aria-labelledby="lv-title"> <div class="wrap"> <div class="section-head"> <div><span class="eyebrow">Plano de la casa</span><h2 class="h2" id="lv-title">Planta <em>por planta</em></h2></div> <p>Elige una planta para ver qué hay en ella.</p> </div> <div class="levels"> <div class="levels__plan">${planSvg()}</div> <div class="levels__info"> <div class="levels__tabs" role="tablist" aria-label="Plantas de la casa">
            ${h.levels.map((l, i) => `<button type="button" role="tab" id="lv-tab-${i}" aria-controls="lv-panel" aria-selected="${i === 0}" data-level="${i}"${i ? ' tabindex="-1"' : ""}>${esc(l.short)}</button>`).join("")}
          </div> <div class="levels__panel" id="lv-panel" role="tabpanel" aria-live="polite"></div> </div> </div> </div> </section> <section class="section" id="photos"> <div class="wrap"> <div class="section-head"> <div><span class="eyebrow">En imágenes</span><h2 class="h2">Pasa, <em>está abierto</em></h2></div> <p>Haz clic en una foto para ampliarla y desplázate con las flechas del teclado o deslizando el dedo.</p> </div> <div class="mosaic">
        ${h.photos.slice(0, 10).map(([n, cap], i) => `<button type="button" class="reveal-img" data-open-gallery="${i}" data-label="${esc(cap)}" aria-label="Ampliar: ${esc(cap)}">${img(key, n, cap, "(max-width: 900px) 100vw, 50vw")}</button>`).join("")}
      </div>
      <div class="mosaic-more"><button type="button" class="btn btn--ghost" data-open-tour>${icon("grid")} Visita estancia por estancia · ${gallery.length} fotos</button></div> </div> </section> <section class="section section--paper" id="chambres"> <div class="wrap"> <div class="section-head"> <div><span class="eyebrow">Dónde dormirás</span><h2 class="h2">${h.bedrooms} dormitorios, <em>${h.beds} camas</em></h2></div> <p>${key === "lacanau" ? "Dos dormitorios y un baño en la planta baja, los otros cuatro dormitorios en la planta superior." : "Tres dormitorios, un baño y un aseo en la planta baja; dos dormitorios, un baño con ducha y un aseo en el semisótano; la sala de estar y la terraza en la planta superior."}</p>
      </div>
      <div class="beds">
        ${h.sleeping.map(([name, bed, n], i) => `
          <article class="bed reveal" data-delay="${i % 3}">
            <button type="button" class="bed__img" data-open-gallery="${idxOf(n)}" aria-label="Ampliar la foto: ${esc(name)}">${img(key, n, name, "(max-width: 600px) 100vw, 33vw")}</button>
            <div class="bed__body">${icon("bed")}<b>${esc(name)}</b><span>${esc(bed)}</span></div>
          </article>`).join("")}
      </div> </div> </section> <section class="section" id="equipements"> <div class="wrap"> <div class="section-head"> <div><span class="eyebrow">Lo que ofrece la casa</span><h2 class="h2">Todo está <em>previsto</em></h2></div> <p>La lista completa del equipamiento, tal como figura en el anuncio.</p> </div> <div class="amenities">
        ${h.amenities.map(([g, items], i) => `
          <div class="amenity-group reveal"${i > 3 ? " data-more hidden" : ""}>
            <h3>${esc(g)}</h3>
            <ul>${items.map((t) => `<li>${icon("check")}<span>${esc(t)}</span></li>`).join("")}</ul>
          </div>`).join("")}
      </div>
      ${h.amenities.length > 4 ? `<div class="mosaic-more"><button type="button" class="btn btn--ghost" id="amen-more" aria-expanded="false">Ver todo el equipamiento</button></div>` : ""}
    </div>
  </section>

  <section class="section section--paper" id="avis">
    <div class="wrap">
      <div class="reviews-top">
        <div class="score reveal">
          <b class="score__num num">${ratingTxt}</b>
          <span class="score__stars" aria-hidden="true">★★★★★</span>
          <span class="score__count">${h.reviewsCount} reseñas verificadas en Airbnb</span> <span class="score__badge">${icon("award")} Favorito de los viajeros</span> </div> <div class="reveal" data-delay="1"> <h2 class="h3">Las puntuaciones en detalle</h2> <div class="ratings">${h.categoryRatings.map(([l, v]) => `<p class="rating-row"><span>${esc(l)}</span><i style="--v:${Number(v.replace(",", ".")) / 5}"></i><b>${esc(v)}</b></p>`).join("")}</div> </div> <div class="reveal" data-delay="2"> <h2 class="h3">Distribución</h2> <div class="ratings">${h.ratingDistribution.map((p, i) => `<p class="rating-row rating-row--dist"><span>${5 - i} ★</span><i style="--v:${p / 100}"></i><b>${p} %</b></p>`).join("")}</div> </div> </div> <div class="tags reveal" aria-label="Los temas que mencionan los viajeros"> <span class="small">Lo que mencionan los viajeros:</span>
        ${h.reviewTags.map(([t, n]) => `<span class="tag">${esc(t)} <b>${n}</b></span>`).join("")}
      </div>
      <div class="quote-grid" id="quote-grid">
        ${(window.REVIEWS[key] || []).map(([q, who, when], i) => `<figure class="quote-card reveal" data-delay="${i % 3}"${i > 5 ? " data-more-review hidden" : ""}><blockquote>${esc(q)}</blockquote><figcaption><span class="avatar-sm" aria-hidden="true">${esc(who.charAt(0))}</span>${esc(who)} · ${esc(when)}</figcaption></figure>`).join("")}
      </div>
      <div class="mosaic-more">
        ${(window.REVIEWS[key] || []).length > 6 ? `<button type="button" class="btn btn--ghost" id="more-reviews">Más reseñas</button>` : ""}
        <a class="btn btn--ghost" href="${h.airbnbUrl}#reviews" target="_blank" rel="noopener">Leer las ${h.reviewsCount} reseñas ${icon("external")}</a> </div> <p class="small" style="margin-top:18px;text-align:center">Extractos de reseñas publicadas por los viajeros en Airbnb (traducidas).</p> </div> </section> <section class="section section--sand" id="reserver"> <div class="wrap"> <div class="section-head"> <div><span class="eyebrow">Disponibilidad</span><h2 class="h2">Elige <em>tus fechas</em></h2></div> <p>Las fechas en gris ya están reservadas. Selecciona tu llegada y luego tu salida: aparece el precio y reservas directamente aquí, sin comisiones de plataforma.</p> </div> <div class="book-grid"> <div class="cal" id="cal"> <div class="cal__head"> <button type="button" class="round-btn" data-cal="-1" aria-label="Mes anterior">${icon("left")}</button> <span class="cal__hint" id="cal-hint" aria-live="polite">Elige tu fecha de llegada</span> <button type="button" class="round-btn" data-cal="1" aria-label="Mes siguiente">${arrow}</button> </div> <div class="cal__months" id="cal-months" role="group" aria-label="Calendario de disponibilidad"></div> <div class="cal__legend"><span><i class="lg lg--sel"></i>Tu estancia</span><span><i class="lg lg--off"></i>Ya reservado</span><span><i class="lg lg--today"></i>Hoy</span><span id="cal-min"></span></div> <div class="quick" id="quick" hidden><span class="small">Próximos fines de semana libres:</span><div class="quick__list" id="quick-list"></div></div> <p class="cal__status" id="cal-status"></p> </div> <aside class="booking" aria-labelledby="book-title"> <div class="booking__head"> <h3 id="book-title">${esc(h.name)}</h3>
            <span class="booking__rate">★ ${ratingTxt} · ${h.reviewsCount} reseñas</span> </div> <p class="small">${price ? `${esc(price)} · ` : ""}${esc(h.place)} · hasta ${h.guests} viajeros</p> <div class="booking__fields"> <button type="button" class="booking__field" data-focus-cal><small>Llegada</small><b id="f-in">Añadir una fecha</b></button> <button type="button" class="booking__field" data-focus-cal><small>Salida</small><b id="f-out">Añadir una fecha</b></button> <button type="button" class="booking__field booking__field--full" id="f-guests-btn" aria-expanded="false" aria-controls="guests-pop"><small>Viajeros</small><b id="f-guests">1 viajero</b></button> </div> <div class="guests-pop" id="guests-pop"><div>
            ${stepper("adults", "Adultos", "18 años o más")}
            ${stepper("children", "Niños", "De 2 a 17 años")}
            ${stepper("infants", "Bebés", key === "bordeaux" ? "La casa no es adecuada para menores de 2 años" : "Menores de 2 años")}
          </div></div>
          <div class="booking__summary" id="summary" hidden></div>
          <div class="booking__price" id="price" hidden></div>
          ${pct ? `<p class="deal">${icon("award")}<span><strong>−${pct} % reservando directamente</strong> en toda la estancia</span></p>` : ""}
          <button type="button" class="btn btn--accent btn--block" id="go-book">Reservar directamente</button> <div class="booking__or"><span>o</span></div> <a class="btn btn--ghost btn--block" id="go-airbnb" href="${h.airbnbUrl}" target="_blank" rel="noopener">Reservar en Airbnb ${icon("external")}</a> <p class="booking__msg" id="book-msg" aria-live="polite"></p> <button type="button" class="link booking__clear" id="clear-dates" hidden>Borrar las fechas</button> <ul class="booking__trust"> <li>${icon("shield")}<span>Reserva directa: pago seguro con tarjeta, no se cobra nada hasta nuestra confirmación</span></li> <li>${icon("award")}<span>Superanfitrión, alojamiento «Favorito de los viajeros»</span></li> <li>${icon("calendar")}<span>${key === "lacanau" ? "Llegada desde las 16 h, salida antes de las 10 h" : "Llegada autónoma y flexible, salida antes de las 12 h"}</span></li> </ul> </aside> </div> </div> </section> <section class="section" id="quartier"> <div class="wrap"> <div class="map-wrap"> <div> <span class="eyebrow">El barrio</span> <h2 class="h2" style="margin-top:18px">${D.title}</h2>
          <p class="lead" style="margin-top:22px">${esc(h.neighbourhood)}</p>
          <p class="prose">${esc(h.gettingAround)}</p> <div class="weather" data-weather hidden></div> <p class="weather-note" hidden>Tiempo en directo · Open-Meteo</p> </div> <div> <div class="poi-filter" role="group" aria-label="Filtrar los puntos de interés"></div> <div class="map" id="map" role="img" aria-label="Mapa de la zona de ${esc(h.name)}"></div>
          <p class="map-note">${key === "lacanau" ? "El círculo indica la zona de la casa: la dirección exacta se comunica al reservar." : "El círculo indica la zona de la casa (ubicación aproximada): la dirección exacta se comunica al reservar."} Distancias en línea recta.</p> <ol class="poi-list" id="poi-list"></ol> </div> </div> <ol class="dest-list" style="margin-top:72px">
        ${D.places.map(([t, dist, body]) => `<li><details><summary><h3>${esc(t)}</h3><span class="dist">${esc(dist)}</span><span class="plus" aria-hidden="true"></span></summary><p>${esc(body)}</p></details></li>`).join("")}
      </ol> </div> </section> <section class="section section--paper" id="quand" data-climate-section aria-labelledby="quand-title"> <div class="wrap"> <div class="section-head"> <div><span class="eyebrow">Cuándo venir</span><h2 class="h2" id="quand-title">El tiempo <em>que hace</em></h2></div> <p>Temperaturas y lluvia mes a mes en ${key === "lacanau" ? "Lacanau, con la temperatura del océano" : "Burdeos"}, según diez años de datos. Pasa el ratón o elige un mes.</p> </div> <div class="clim" id="clim"></div> </div> </section> <section class="section" id="infos"> <div class="wrap"> <div class="section-head"> <div><span class="eyebrow">Información práctica</span><h2 class="h2">Las normas <em>de la casa</em></h2></div> <p>Vas a alojarte en una casa familiar: cuídala y respeta el lugar, por favor.</p> </div> <div class="rules">
        ${Object.entries(h.rules).map(([g, items]) => `<div class="reveal"><h3>${esc(g)}</h3><ul>${items.map((t) => `<li>${esc(t)}</li>`).join("")}</ul></div>`).join("")}
      </div>
      ${h.registration ? `<p class="small" style="margin-top:40px">Número de registro municipal: ${esc(h.registration)}</p>` : ""}
    </div>
  </section>

  <a class="other" href="${other.page}" data-house="${other.id}">
    <img src="${photo(other.id, other.cover, "md")}" srcset="${srcset(other.id, other.cover)}" sizes="100vw" alt="" loading="lazy" data-parallax="0.1"> <div class="wrap"> <span class="eyebrow">La otra casa · ${esc(other.kicker)}</span>
      <h2 class="display">${esc(other.name.replace(/ (du|de) .*/, ""))} <em>${esc(other.name.replace(/^La Maison /, ""))}</em></h2>
      <span class="link">${esc(other.place)} · ${other.guests} viajeros ${arrow}</span>
    </div>
  </a>

  <div class="mbar" id="mbar">
    <div><b>${esc(h.name)}</b><span id="mbar-sub">★ ${ratingTxt} · ${h.reviewsCount} reseñas · ${h.guests} viajeros</span></div> <a class="btn btn--accent" href="#reserver" id="mbar-btn">Ver fechas</a> </div> <div class="tour" id="tour" role="dialog" aria-modal="true" aria-label="Todas las fotos" hidden> <div class="tour__bar"> <div class="tour__chips" role="group" aria-label="Estancias"> <button type="button" class="chip" data-cat="all" aria-pressed="true">Todo · ${gallery.length}</button>
        ${CATS.map(([id, name]) => { const n = h.photos.filter((p) => catOf(p[1], p[2]) === id).length; return n ? `<button type="button" class="chip" data-cat="${id}" aria-pressed="false">${name} · ${n}</button>` : ""; }).join("")}
      </div> <button type="button" class="round-btn" data-close-tour aria-label="Cerrar">${icon("close")}</button>
    </div>
    <div class="tour__grid" id="tour-grid">
      ${h.photos.map(([n, cap, cat], i) => `<button type="button" class="tour__item" data-cat="${catOf(cap, cat)}" data-open-gallery="${i}" aria-label="Ampliar: ${esc(cap)}"><img src="${photo(key, n, "md")}" alt="${esc(cap)}" loading="lazy"><span>${esc(cap)}</span></button>`).join("")}
    </div> </div> <div class="dialog" id="dialog" aria-hidden="true"> <div class="dialog__bg" data-close></div> <div class="dialog__box" role="dialog" aria-modal="true" aria-labelledby="dlg-title"> <button type="button" class="dialog__close" data-close aria-label="Cerrar">${icon("close")}</button>
      <div id="dlg-form">
        <span class="eyebrow eyebrow--plain">${esc(h.name)}</span> <h2 class="h3" id="dlg-title" style="margin-top:12px">Tu reserva</h2> <div class="form__recap" id="recap"></div> <form class="form" id="form" novalidate> <div class="field"><label for="d-name">Nombre y apellidos</label><input id="d-name" name="nom" autocomplete="name" required maxlength="80"></div> <div class="field"><label for="d-phone">Teléfono</label><input id="d-phone" name="telephone" type="tel" autocomplete="tel" maxlength="30"></div> <div class="field full"><label for="d-email">Correo electrónico</label><input id="d-email" name="email" type="email" autocomplete="email" required maxlength="254"></div> <div class="field full"><label for="d-msg">Unas palabras para nosotros (opcional)</label><textarea id="d-msg" name="message" maxlength="2000" placeholder="El motivo de tu estancia, la hora de llegada, tus preguntas…"></textarea></div> <div class="field full promo" id="promo-box"><label for="d-code">Código promocional (opcional)</label><div class="promo__row"><input id="d-code" name="code" autocomplete="off" autocapitalize="characters" spellcheck="false" maxlength="30"><button type="button" class="btn btn--small" id="d-code-go">Aplicar</button></div><p class="small promo__msg" id="d-code-msg" aria-live="polite"></p></div> <label class="check full"><input type="checkbox" id="d-cgv" name="conditions" required> <span>Acepto las <a href="conditions.html" target="_blank" rel="noopener">condiciones de reserva</a> y las normas de la casa.</span></label> <input class="hp" type="text" name="bot-field" tabindex="-1" autocomplete="off" aria-hidden="true"> <div class="full"><button type="submit" class="btn btn--accent btn--block" id="d-submit">Continuar</button><p class="booking__msg" id="form-msg" aria-live="polite"></p><p class="small" id="d-note" style="margin-top:12px"></p></div> </form> </div> <div class="form__done" id="dlg-done" hidden>
        ${icon("check")}
        <h2 class="h3">¡Gracias!</h2> <p id="done-text" style="margin-top:12px">Tu solicitud se ha enviado. Te responderemos muy pronto.</p> <button type="button" class="btn" data-close style="margin-top:18px">Cerrar</button> </div> </div> </div>`;

  function stepper(name, label, sub) {
    return `<div class="stepper"><div><b>${label}</b><span>${sub}</span></div>
      <div class="stepper__ctl"><button type="button" data-step="${name}" data-d="-1" aria-label="Quitar: ${label}">−</button><output id="n-${name}" aria-live="polite">0</output><button type="button" data-step="${name}" data-d="1" aria-label="Añadir: ${label}">+</button></div></div>`;
  }

  // Coupe de la maison : un étage par niveau, cliquable
  function planSvg() {
    const L = h.levels;
    const ext = L.findIndex((l) => l.short === "Exterior");
    const RANK = { "Planta superior": 0, "Planta baja": 1, "Semisótano": 2 };
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
      : `<path class="plan__roof" d="M70 ${top - 6} H350 M150 ${top - 6} L180 ${top - 40} H300 L330 ${top - 6}"/><text class="plan__note" x="240" y="${top - 16}" text-anchor="middle">cristalera</text>`;
    const below = L.some((l) => l.short === "Semisótano");
    const garden = ext >= 0
      ? `<g class="plan__lvl plan__lvl--ext" data-level="${ext}" tabindex="-1"><path d="M0 ${groundY + 2} H70 M350 ${groundY + 2} H${W}"/><rect x="368" y="${groundY - 22}" width="46" height="18" rx="2" class="plan__pool"/><text x="391" y="${groundY + 22}" text-anchor="middle">jardín</text></g>`
      : "";
    return `<svg viewBox="0 0 ${W} ${groundY + 40}" role="img" aria-label="Sección esquemática de la casa">
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
      ${l.photo ? `<button type="button" class="levels__photo" data-open-gallery="${idxOf(l.photo)}" aria-label="Ampliar: ${esc(capOf(l.photo))}">${img(key, l.photo, capOf(l.photo), "(max-width: 900px) 100vw, 40vw")}</button>` : ""}
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
    more.textContent = open ? "Mostrar menos" : "Leer más";
    more.setAttribute("aria-expanded", String(open));
  });
  const amenMore = $("#amen-more");
  if (amenMore) amenMore.addEventListener("click", () => {
    const open = amenMore.getAttribute("aria-expanded") !== "true";
    $$("[data-more]").forEach((g) => { g.hidden = !open; if (open) g.classList.add("is-in"); });
    amenMore.setAttribute("aria-expanded", String(open));
    amenMore.textContent = open ? "Ver menos" : "Ver todo el equipamiento";
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
  const fmt = new Intl.DateTimeFormat("es-ES", { weekday: "short", day: "numeric", month: "short" });
  const fmtShort = new Intl.DateTimeFormat("es-ES", { day: "numeric", month: "short" });
  const fmtLong = new Intl.DateTimeFormat("es-ES", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
  const fmtMonth = new Intl.DateTimeFormat("es-ES", { month: "long", year: "numeric" });
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
    const g = Number(q.get("viajeros") || saved.adults || 1);
    if (g >= 1) state.adults = Math.min(g, h.guests);
    if (!q.get("viajeros") && saved.children) state.children = Math.min(saved.children, h.guests - state.adults);
    if (!q.get("viajeros") && saved.infants) state.infants = Math.min(saved.infants, limits.infants);
  } catch (e) { /* stockage indisponible : on part de zéro */ }
  const validateState = () => {
    if (state.in && !av.canIn(state.in)) { state.in = null; state.out = null; }
    if (state.in && state.out && av.outProblem(state.in, state.out)) state.out = null;
  };
  validateState();
  if (state.in) monthOffset = Math.max(0, (state.in.getFullYear() - today.getFullYear()) * 12 + state.in.getMonth() - today.getMonth());

  const monthsBox = $("#cal-months");
  const hint = $("#cal-hint");
  const REASON = { taken: "una noche del periodo ya está reservada", short: "estancia demasiado corta", long: "estancia demasiado larga", noout: "no se puede salir este día" };
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
          why = free ? "no se puede llegar este día" : "ya reservado";
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
    hint.textContent = !state.in ? "Elige tu fecha de llegada"
      : !state.out ? `Elige tu salida${minN > 1 ? ` (${minN} noches mínimo)` : ""}`
        : `${plural(nightsBetween(state.in, state.out), "noche")} ${nightsBetween(state.in, state.out) > 1 ? "seleccionadas" : "seleccionada"}`;
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
      if (state.in && !state.out && d > state.in && av.outProblem(state.in, d) === "short") m.textContent = `La estancia mínima es de ${av.minNights(state.in)} noches a partir de esta fecha.`;
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

  // Prix du séjour (js/tarifs.js) : affiché ici, recalculé par le serveur au paiement
  const priceOf = () => (state.in && state.out && window.SP_PRICE ? window.SP_PRICE(key, iso(state.in), iso(state.out), state.adults) : null);
  const EUR = (c) => window.SP_EUR(c);
  const airbnbLink = () => {
    const u = new URL(h.airbnbUrl);
    if (state.in && state.out) { u.searchParams.set("check_in", iso(state.in)); u.searchParams.set("check_out", iso(state.out)); }
    u.searchParams.set("adults", state.adults);
    if (state.children) u.searchParams.set("children", state.children);
    if (state.infants) u.searchParams.set("infants", state.infants);
    return u.toString();
  };
  const guestsText = () => {
    const n = state.adults + state.children;
    let t = plural(n, "viajero");
    if (state.infants) t += `, ${plural(state.infants, "bebé")}`;
    return t;
  };
  const stayText = () => (state.in && state.out ? `du ${fmtLong.format(state.in)} au ${fmtLong.format(state.out)} (${plural(nightsBetween(state.in, state.out), "noche")})` : "fechas por definir");

  function update() {
    $("#f-in").textContent = state.in ? fmt.format(state.in) : "Añadir una fecha";
    $("#f-out").textContent = state.out ? fmt.format(state.out) : "Añadir una fecha";
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
      sum.innerHTML = `<p><span>Estancia</span><strong>${plural(n, "noche")}</strong></p><p><span>Llegada</span><span>${esc(fmtLong.format(state.in))}${key === "lacanau" ? ", desde las 16 h" : ""}</span></p><p><span>Salida</span><span>${esc(fmtLong.format(state.out))}${key === "lacanau" ? ", antes de las 10 h" : ", antes de las 12 h"}</span></p>${av.known ? `<p class="ok">${icon("check")}<span>Estas fechas están libres en el calendario</span></p>` : ""}`;
    } else sum.hidden = true;
    const pr = $("#price");
    const p = priceOf();
    if (p && p.ready) {
      pr.hidden = false;
      pr.innerHTML = `${p.lines.map((l) => `<p${l.cents < 0 ? ' class="is-off"' : ""}><span>${esc(window.SP_LABEL ? SP_LABEL(l.label) : l.label)}</span><span>${EUR(l.cents)}</span></p>`).join("")}<p class="booking__total"><span>Total directo</span><strong>${p.remise ? `<s title="Precio en Airbnb">${EUR(p.sansRemiseTotal)}</s> ` : ""}${EUR(p.cents)}</strong></p>${p.remise ? `<p class="booking__save">Ahorras ${EUR(p.sansRemiseTotal - p.cents)} ${p.source === "airbnb" ? "respecto al precio de Airbnb" : "reservando aquí"}</p>` : ""}`;
    } else if (state.in && state.out) {
      pr.hidden = false;
      pr.innerHTML = `<p class="small">El precio de esta estancia se te confirmará por correo con tu reserva.</p>`;
    } else pr.hidden = true;
    $("#go-book").textContent = state.in && state.out ? (p && p.ready ? `Reservar directamente · ${EUR(p.cents)}` : `Reservar directamente${pct ? ` (−${pct} %)` : ""}`) : "Elegir mis fechas";
    $("#go-airbnb").href = airbnbLink();
    const msg = $("#book-msg");
    msg.classList.remove("is-error");
    msg.textContent = state.in && !state.out ? `Ahora elige tu fecha de salida${av.minNights(state.in) > 1 ? ` (${av.minNights(state.in)} noches mínimo)` : ""}.` : "";
    $("#clear-dates").hidden = !state.in;
    // Barre fixe : rappel des dates
    $("#mbar-sub").textContent = state.in && state.out ? `${fmtShort.format(state.in)} → ${fmtShort.format(state.out)} · ${guestsText()}` : `★ ${ratingTxt} · ${h.reviewsCount} reseñas · ${h.guests} viajeros`;
    $("#mbar-btn").textContent = state.in && state.out ? "Reservar" : "Ver fechas";
    try { sessionStorage.setItem(`sp-${key}`, JSON.stringify({ in: state.in && iso(state.in), out: state.out && iso(state.out), adults: state.adults, children: state.children, infants: state.infants })); } catch (e) { /* ignoré */ }
    renderCal();
  }

  // État de la synchronisation
  const status = $("#cal-status");
  const setStatus = () => {
    if (av.known && av.updated) {
      const d = new Date(av.updated);
      status.textContent = `Disponibilidad actualizada el ${new Intl.DateTimeFormat("es-ES", { day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" }).format(d)}. Tus fechas se vuelven a comprobar al reservar.`;
    } else status.textContent = "Tus fechas se comprueban al reservar.";
  };
  setStatus();
  const minAll = av.known ? av.minNights(today) : 0;
  if (minAll > 1) $("#cal-min").innerHTML = `<i class="lg lg--min"></i>${minAll} noches mínimo`;
  // Synchronisation iCal du serveur (si elle est réglée) : on l'ajoute
  fetch(`../api/disponibilites/${key}`, { headers: { Accept: "application/json" } })
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

  // Retour depuis le paiement annulé
  if (/[?&]annule=1/.test(location.search)) {
    const m = $("#book-msg");
    m.textContent = "El pago se ha cancelado: no se ha cobrado nada. Tus fechas siguen seleccionadas.";
  }

  /* ======================= Demande directe ======================= */
  const dlg = $("#dialog");
  let dlgReturn = null;
  const openDlg = () => {
    if (!state.in || !state.out) {
      const m = $("#book-msg");
      m.textContent = "Elige primero tus fechas de llegada y salida en el calendario.";
      m.classList.add("is-error");
      return;
    }
    dlgReturn = document.activeElement;
    const p = priceOf();
    renderRecap();
    $("#promo-box").hidden = !(p && p.ready);
    $("#d-note").textContent = p && p.ready
      ? "Serás redirigido a la página de pago segura de Stripe. No se cobra a tu tarjeta de inmediato: el importe solo se retiene y se cobra cuando confirmamos tu estancia (en 24 h). Sin confirmación, se libera."
      : `Te responderemos personalmente por correo en 24 h con el precio${pct ? ` (con un descuento del ${pct} % incluido)` : ""} y la confirmación. No se paga nada en este paso.`;
    $("#dlg-form").hidden = false;
    $("#dlg-done").hidden = true;
    dlg.classList.add("is-open");
    dlg.setAttribute("aria-hidden", "false");
    document.body.classList.add("is-locked");
    setTimeout(() => $("#d-name").focus(), 80);
  };
  // Code promo : vérifié par le serveur, qui recalcule le prix
  let promo = null; // { code, price, stay }
  const stayKey = () => `${iso(state.in)}|${iso(state.out)}|${state.adults}`;
  const shownPrice = () => {
    const p = priceOf();
    if (promo && promo.stay === stayKey() && promo.price) return Object.assign({}, p, promo.price, { ready: true });
    return p;
  };
  function renderRecap() {
    const p = shownPrice();
    $("#recap").innerHTML = `<p><strong>${esc(h.name)}</strong></p><p>${esc(stayText())}</p><p>${esc(guestsText())}</p>${p && p.ready ? `<div class="recap__price">${p.lines.map((l) => `<p${l.cents < 0 ? ' class="is-off"' : ""}><span>${esc(window.SP_LABEL ? SP_LABEL(l.label) : l.label)}</span><span>${EUR(l.cents)}</span></p>`).join("")}<p class="booking__total"><span>Total</span><strong>${EUR(p.cents)}</strong></p></div>` : ""}`;
    $("#d-submit").textContent = p && p.ready ? `Continuar al pago · ${EUR(p.cents)}` : "Enviar mi solicitud";
  }
  async function applyCode() {
    const input = $("#d-code");
    const out = $("#d-code-msg");
    const code = input.value.trim().toUpperCase();
    out.classList.remove("is-error");
    if (!code) { promo = null; out.textContent = ""; renderRecap(); return true; }
    out.textContent = "Comprobando…";
    try {
      const r = await fetch("../api/promo", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code, maison: key, arrivee: iso(state.in), depart: iso(state.out), adultes: state.adults, lang: document.documentElement.lang }) });
      const res = await r.json().catch(() => null);
      if (r.ok && res && res.ok) {
        promo = { code: res.code, price: res.price, stay: stayKey() };
        out.textContent = `Código ${res.code} aplicado.`;
        renderRecap();
        return true;
      }
      promo = null;
      out.textContent = (res && res.message) || "Este código no es válido.";
    } catch (err) {
      promo = null;
      out.textContent = "No se puede comprobar el código en este momento.";
    }
    out.classList.add("is-error");
    renderRecap();
    return false;
  }
  $("#d-code-go").addEventListener("click", applyCode);
  $("#d-code").addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); applyCode(); } });

  const closeDlg = () => {
    dlg.classList.remove("is-open");
    dlg.setAttribute("aria-hidden", "true");
    document.body.classList.remove("is-locked");
    if (dlgReturn) dlgReturn.focus();
  };
  // Mesure d'audience anonyme : intérêt pour la réservation (affiché dans l'espace propriétaire)
  const track = (e) => { try { navigator.sendBeacon("../api/evt", new Blob([JSON.stringify({ e, h: key })], { type: "application/json" })); } catch (err) { /* ignoré */ } };
  $("#go-airbnb").addEventListener("click", () => track("airbnb"));
  $("#go-book").addEventListener("click", () => {
    if (state.in && state.out) track("reserver");
    if (!state.in || !state.out) {
      $("#cal").scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "center" });
      const m = $("#book-msg");
      m.textContent = state.in ? "Ahora elige tu fecha de salida." : "Elige tu fecha de llegada en el calendario.";
      return;
    }
    openDlg();
  });
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
      msg.textContent = "Indica tu nombre y un correo electrónico válido.";
      msg.classList.add("is-error");
      (!fd.nom.trim() ? $("#d-name") : $("#d-email")).focus();
      return;
    }
    msg.classList.remove("is-error");
    msg.textContent = "Enviando…";
    const btn = $('button[type="submit"]', form);
    btn.disabled = true;
    if (!$("#d-cgv").checked) {
      btn.disabled = false;
      msg.textContent = "Acepta las condiciones de reserva.";
      msg.classList.add("is-error");
      $("#d-cgv").focus();
      return;
    }
    const typed = (fd.code || "").trim().toUpperCase();
    if (typed && !(promo && promo.code === typed && promo.stay === stayKey())) {
      if (!(await applyCode())) { btn.disabled = false; msg.textContent = ""; $("#d-code").focus(); return; }
    }
    const payload = Object.assign({}, fd, {
      maison: key, arrivee: iso(state.in), depart: iso(state.out), conditions: true, lang: document.documentElement.lang,
      adultes: state.adults, enfants: state.children, bebes: state.infants,
    });
    let res = null;
    let net = true;
    try {
      const r = await fetch("../api/reservation", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
      res = await r.json().catch(() => null);
      if (r.status === 404 || r.status === 503 || r.status === 405) net = false;
    } catch (err) { net = false; }
    btn.disabled = false;
    if (res && res.ok) track("paiement");
    if (res && res.ok && res.mode === "paiement" && res.url) {
      msg.textContent = "Redirigiendo al pago seguro…";
      location.href = res.url;
      return;
    }
    if (res && res.ok) {
      location.href = res.url;
      return;
    }
    if (net && res && res.message) {
      msg.textContent = res.message;
      msg.classList.add("is-error");
      if (res.error === "pris") { av.addBooked([]); }
      return;
    }
    msg.textContent = "";
    // Serveur indisponible (ex. site ouvert depuis l'ordinateur) : e-mail pré-rempli, rien n'est perdu
    const body = `Hola:\n\nMe gustaría reservar ${h.name} ${stayText()}, para ${guestsText()}.\n\n${fd.message ? `${fd.message}\n\n` : ""}${fd.nom}\n${fd.email}${fd.telephone ? `\n${fd.telephone}` : ""}`;
    location.href = `mailto:${S.email}?subject=${encodeURIComponent(`Solicitud de reserva — ${h.name}`)}&body=${encodeURIComponent(body)}`;
    $("#done-text").innerHTML = `Tu aplicación de correo se abre con la solicitud ya rellenada: solo tienes que enviarla. Si no se abre nada, escríbenos a <strong>${esc(S.email)}</strong>.`;
    $("#dlg-form").hidden = true;
    $("#dlg-done").hidden = false;
    $("#dlg-done .btn").focus();
  });

  update();

  /* ======================= Carte et repères ======================= */
  const R = 6371;
  const rad = (x) => (x * Math.PI) / 180;
  const dist = (a, b, c, d) => 2 * R * Math.asin(Math.sqrt(Math.sin(rad(c - a) / 2) ** 2 + Math.cos(rad(a)) * Math.cos(rad(c)) * Math.sin(rad(d - b) / 2) ** 2));
  const POI_CATS = { walk: "A pie", beach: "Playas", wine: "Viñedos", city: "Ciudad", travel: "Estación y aeropuerto" };
  const POI_ICONS = { walk: "walk", beach: "wave", wine: "leaf", city: "pin", travel: "pin" };
  const pois = h.poi.map(([cat, name, lat, lng], i) => {
    const km = dist(h.lat, h.lng, lat, lng);
    return { i, cat, name, lat, lng, km };
  }).sort((a, b) => a.km - b.km);
  const kmTxt = (km) => (km < 0.95 ? `${Math.round(km * 10) * 100} m` : `${km < 10 ? fr(km.toFixed(1)) : Math.round(km)} km`);
  // Temps de marche indicatif : distance à vol d'oiseau majorée de 20 %, à 5 km/h
  const walkTxt = (km) => (km < 3 ? ` · unos ${Math.max(5, Math.round((km * 1.2) / 5 * 60 / 5) * 5)} min a pie` : "");
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
