/* Fiche détaillée d'un hôtel. */
(function () {
  const { escapeHtml, formatPrice, formatDistance, distanceKm, bookingLink, partnerLinks, getUserLocation, img, CONFIG, planRank, partnerBadge, newsletterForm } = window.NS;
  const ENVS = window.ENVIRONMENTS, TYPES = window.TYPES;

  const id = new URLSearchParams(location.search).get("id");
  const h = window.HOTELS.find((x) => x.id === id);
  const root = document.getElementById("hotel");

  function notFound() {
    root.innerHTML = `
      <div class="not-found">
        <h1>Hôtel introuvable</h1>
        <p class="muted">Cette adresse n'existe pas ou n'est plus dans notre sélection.</p>
        <a class="btn btn-primary" href="index.html#explorer">Voir tous les hôtels</a>
      </div>`;
  }

  function setMeta() {
    document.title = `${h.name} — ${h.city} | ${CONFIG.siteName}`;
    document.querySelector('meta[name="description"]').content = `${h.tagline}. ${TYPES[h.type].label} à ${h.city} (${h.department}), dès ${h.price} € la nuit.`;
    const ld = {
      "@context": "https://schema.org",
      "@type": "Hotel",
      name: h.name,
      description: h.description.join(" "),
      image: h.images,
      address: { "@type": "PostalAddress", streetAddress: h.address, addressLocality: h.city, addressRegion: h.region, addressCountry: "FR" },
      geo: { "@type": "GeoCoordinates", latitude: h.lat, longitude: h.lng },
      priceRange: `dès ${h.price} €`,
      amenityFeature: h.amenities.map((a) => ({ "@type": "LocationFeatureSpecification", name: a, value: true })),
    };
    const s = document.createElement("script");
    s.type = "application/ld+json";
    s.textContent = JSON.stringify(ld);
    document.head.appendChild(s);
  }

  function render() {
    const loc = getUserLocation();
    const dist = loc ? distanceKm(loc, h) : null;
    const book = bookingLink(h);
    const others = partnerLinks(h);
    const photos = h.images;
    const paid = planRank(h) > 0;
    const trk = `data-track="Réservation" data-hotel="${escapeHtml(h.id)}"`;

    const similar = window.HOTELS
      .filter((x) => x.id !== h.id)
      .map((x) => ({ x, score: (x.type === h.type ? 2 : 0) + (x.env === h.env ? 1 : 0) - distanceKm(h, x) / 1000 }))
      .sort((a, b) => b.score - a.score)
      .slice(0, 3)
      .map(({ x }) => x);

    root.innerHTML = `
      <nav class="crumbs">
        <a href="index.html">Accueil</a> ›
        <a href="index.html?env=${h.env}#explorer">${escapeHtml(ENVS[h.env].label)}</a> ›
        <a href="index.html?type=${h.type}#explorer">${escapeHtml(TYPES[h.type].label)}</a> ›
        <span>${escapeHtml(h.name)}</span>
      </nav>

      <header class="detail-head">
        <p class="card-type">${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)} · ${escapeHtml(ENVS[h.env].label)} ${partnerBadge(h)}</p>
        <h1>${escapeHtml(h.name)}</h1>
        <p class="detail-tagline">${escapeHtml(h.tagline)}</p>
        <p class="detail-place">📍 ${escapeHtml(h.city)}, ${escapeHtml(h.department)} — ${escapeHtml(h.region)}
          ${dist != null ? `<span class="dist-chip">à ${formatDistance(dist)} de chez vous</span>` : ""}</p>
      </header>

      <section class="gallery count-${Math.min(photos.length, 5)}">
        ${photos.slice(0, 5).map((src, i) => `
          <button type="button" class="g-item" data-i="${i}" aria-label="Agrandir la photo ${i + 1}">
            <img src="${img(src, i === 0 ? 1800 : 900)}" alt="${escapeHtml(h.name)} — photo ${i + 1}" ${i ? 'loading="lazy"' : ""}>
          </button>`).join("")}
        ${photos.length > 1 ? `<button type="button" class="g-all" data-i="0">Voir les ${photos.length} photos</button>` : ""}
      </section>

      <div class="detail-layout">
        <article class="detail-content">
          <ul class="highlights">
            ${h.highlights.map((x) => `<li>✦ ${escapeHtml(x)}</li>`).join("")}
          </ul>

          <h2>L'expérience</h2>
          ${h.description.map((p) => `<p class="lead">${escapeHtml(p)}</p>`).join("")}

          <h2>Équipements & services</h2>
          <ul class="amenities">${h.amenities.map((a) => `<li>${escapeHtml(a)}</li>`).join("")}</ul>

          <h2>Infos pratiques</h2>
          <dl class="facts">
            <div><dt>Hébergement</dt><dd>${escapeHtml(h.rooms)}</dd></div>
            <div><dt>Arrivée</dt><dd>${escapeHtml(h.checkIn)}</dd></div>
            <div><dt>Départ</dt><dd>${escapeHtml(h.checkOut)}</dd></div>
            <div><dt>Adresse</dt><dd>${escapeHtml(h.address)}</dd></div>
          </dl>

          <h2>Localisation</h2>
          <div id="mini-map" class="mini-map"></div>
          <p class="small muted"><a href="https://www.google.com/maps/dir/?api=1&destination=${h.lat},${h.lng}" target="_blank" rel="noopener">Itinéraire Google Maps →</a></p>

          <div class="nl-inline">
            <h3>${escapeHtml(CONFIG.newsletter.title)}</h3>
            <p class="muted">${escapeHtml(CONFIG.newsletter.pitch)}</p>
            ${newsletterForm(`fiche-${h.id}`)}
          </div>
        </article>

        <aside class="book-card">
          <p class="book-price">dès <strong>${formatPrice(h.price)}</strong> <span>/ nuit</span></p>
          <p class="small muted">Prix indicatif. Vérifiez les disponibilités et le tarif exact selon vos dates.</p>
          ${paid && h.offer ? `<div class="offer"><strong>Offre spéciale</strong>${escapeHtml(h.offer)}</div>` : ""}
          <a class="btn btn-primary btn-block" href="${escapeHtml(book)}" target="_blank" rel="sponsored noopener" ${trk}>Voir les disponibilités sur Booking.com</a>
          ${others.map((o) => `<a class="btn btn-ghost btn-block" href="${escapeHtml(o.href)}" target="_blank" rel="sponsored noopener" data-track="Partenaire" data-hotel="${escapeHtml(h.id)}">Comparer sur ${escapeHtml(o.name)}</a>`).join("")}
          ${paid && h.website ? `<a class="btn btn-ghost btn-block" href="${escapeHtml(h.website)}" target="_blank" rel="noopener" data-track="Site officiel" data-hotel="${escapeHtml(h.id)}">Réserver en direct sur le site de l'hôtel</a>` : ""}
          ${paid && h.phone ? `<a class="book-phone" href="tel:${escapeHtml(h.phone.replace(/\s/g, ""))}" data-track="Téléphone" data-hotel="${escapeHtml(h.id)}">☎ ${escapeHtml(h.phone)}</a>` : ""}
          <ul class="book-perks">
            <li>✓ Réservation sécurisée chez notre partenaire</li>
            <li>✓ Aucun frais supplémentaire</li>
            <li>✓ Annulation selon les conditions de l'offre</li>
          </ul>
        </aside>
      </div>

      ${paid ? "" : `<p class="owner-note">Vous êtes le propriétaire de cet établissement ? <a href="hoteliers.html?hotel=${encodeURIComponent(h.id)}">Mettez votre fiche en avant →</a></p>`}

      <section class="similar">
        <h2>Vous aimerez aussi</h2>
        <div class="grid">
          ${similar.map((x) => `
            <a class="card" href="hotel.html?id=${encodeURIComponent(x.id)}">
              <div class="card-media"><img src="${img(x.images[0], 900)}" alt="${escapeHtml(x.name)}" loading="lazy"><span class="badge">${escapeHtml(ENVS[x.env].label)}</span></div>
              <div class="card-body">
                <p class="card-type">${TYPES[x.type].icon} ${escapeHtml(TYPES[x.type].label)}</p>
                <h3>${escapeHtml(x.name)}</h3>
                <p class="card-place">${escapeHtml(x.city)} · ${escapeHtml(x.department)}</p>
                <p class="card-price">dès <strong>${formatPrice(x.price)}</strong> / nuit</p>
              </div>
            </a>`).join("")}
        </div>
      </section>

      <div class="mobile-book">
        <span>dès <strong>${formatPrice(h.price)}</strong> / nuit</span>
        <a class="btn btn-primary" href="${escapeHtml(book)}" target="_blank" rel="sponsored noopener" ${trk}>Réserver</a>
      </div>`;

    initMap(loc);
    initLightbox(photos);
  }

  function initMap(loc) {
    if (!window.L) return;
    const map = L.map("mini-map", { scrollWheelZoom: false }).setView([h.lat, h.lng], 11);
    L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>',
    }).addTo(map);
    L.marker([h.lat, h.lng], { icon: L.divIcon({ className: "price-pin", html: `<span>${escapeHtml(h.name)}</span>`, iconSize: null }) }).addTo(map);
    if (loc) {
      L.marker([loc.lat, loc.lng], { icon: L.divIcon({ className: "home-pin", html: "<span>Vous</span>", iconSize: null }) }).addTo(map);
      map.fitBounds([[h.lat, h.lng], [loc.lat, loc.lng]], { padding: [40, 40], maxZoom: 11 });
    }
  }

  function initLightbox(photos) {
    const lb = document.getElementById("lightbox");
    const image = lb.querySelector("img");
    let i = 0;
    const show = (n) => {
      i = (n + photos.length) % photos.length;
      image.src = img(photos[i], 2000);
      lb.querySelector(".lb-count").textContent = `${i + 1} / ${photos.length}`;
    };
    const open = (n) => { show(n); lb.hidden = false; document.body.style.overflow = "hidden"; };
    const close = () => { lb.hidden = true; document.body.style.overflow = ""; };

    root.querySelectorAll("[data-i]").forEach((b) => b.addEventListener("click", () => open(Number(b.dataset.i))));
    lb.querySelector(".lb-close").addEventListener("click", close);
    lb.querySelector(".lb-prev").addEventListener("click", () => show(i - 1));
    lb.querySelector(".lb-next").addEventListener("click", () => show(i + 1));
    lb.addEventListener("click", (e) => { if (e.target === lb) close(); });
    document.addEventListener("keydown", (e) => {
      if (lb.hidden) return;
      if (e.key === "Escape") close();
      if (e.key === "ArrowLeft") show(i - 1);
      if (e.key === "ArrowRight") show(i + 1);
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    if (!h) return notFound();
    setMeta();
    render();
  });
})();
