/* Fiche détaillée d'un hôtel. */
(function () {
  const {
    escapeHtml, formatDistance, distanceKm, bookingLink, partnerLinks, getUserLocation, img, CONFIG,
    planRank, partnerBadge, newsletterForm, card, budgetHtml, budgetOf, favButton, observeReveal,
  } = window.NS;
  const ENVS = window.ENVIRONMENTS, TYPES = window.TYPES;

  const id = new URLSearchParams(location.search).get("id");
  const h = window.HOTELS.find((x) => x.id === id);
  const root = document.getElementById("hotel");

  function notFound() {
    document.getElementById("site-header").classList.remove("on-dark");
    root.innerHTML = `
      <div class="container not-found">
        <h1>Établissement introuvable</h1>
        <p class="muted">Cette adresse n'existe pas ou n'est plus dans notre sélection.</p>
        <a class="btn btn-primary" href="index.html#explorer">Voir tous les établissements</a>
      </div>`;
  }

  function setMeta() {
    document.title = `${h.name} — ${h.city} | ${CONFIG.siteName}`;
    document.querySelector('meta[name="description"]').content = `${h.tagline}. ${TYPES[h.type].label} à ${h.city} (${h.region}).`;
    const ld = {
      "@context": "https://schema.org",
      "@type": "Hotel",
      name: h.name,
      description: h.description.join(" "),
      image: h.images.map((u) => new URL(u, location.href).href),
      address: { "@type": "PostalAddress", streetAddress: h.address, addressLocality: h.city, addressRegion: h.region, addressCountry: "FR" },
      geo: { "@type": "GeoCoordinates", latitude: h.lat, longitude: h.lng },
      priceRange: "€".repeat(h.budget),
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
    const b = budgetOf(h);

    const similar = window.HOTELS
      .filter((x) => x.id !== h.id)
      .map((x) => ({ x, score: (x.type === h.type ? 3 : 0) + (x.env === h.env ? 2 : 0) + (x.region === h.region ? 1 : 0) - distanceKm(h, x) / 1500 }))
      .sort((a, c) => c.score - a.score)
      .slice(0, 6)
      .map(({ x }) => x);

    root.innerHTML = `
      <section class="d-hero">
        <div class="d-hero-bg" style="background-image:url('${photos[0]}')"></div>
        <div class="d-hero-veil"></div>
        <div class="container d-hero-inner">
          <nav class="crumbs">
            <a href="index.html">Accueil</a> ›
            <a href="index.html?env=${h.env}#explorer">${escapeHtml(ENVS[h.env].label)}</a> ›
            <a href="index.html?type=${h.type}#explorer">${escapeHtml(TYPES[h.type].label)}</a>
          </nav>
          <p class="card-type light">${TYPES[h.type].icon} ${escapeHtml(TYPES[h.type].label)} · ${escapeHtml(ENVS[h.env].label)} ${partnerBadge(h)}</p>
          <h1>${escapeHtml(h.name)}</h1>
          <p class="d-tagline">${escapeHtml(h.tagline)}</p>
          <div class="d-meta">
            <span>📍 ${escapeHtml(h.city)}, ${escapeHtml(h.region)}</span>
            ${dist != null ? `<span class="dist-chip">à ${formatDistance(dist)} de chez vous</span>` : ""}
            <span class="d-budget">${budgetHtml(h)} <small>${escapeHtml(b.range)}</small></span>
          </div>
          <div class="d-actions">
            <a class="btn btn-primary" href="${escapeHtml(book)}" target="_blank" rel="sponsored noopener" ${trk}>Voir les disponibilités</a>
            <button type="button" class="btn btn-glass" data-open-gallery>▦ ${photos.length} photos</button>
            ${favButton(h, "fav-lg fav-glass")}
            <button type="button" class="btn-round" id="share" aria-label="Partager">↗</button>
          </div>
        </div>
      </section>

      <nav class="d-tabs" id="d-tabs">
        <div class="container d-tabs-inner">
          <a href="#experience" class="on">L'expérience</a>
          <a href="#photos">Photos</a>
          <a href="#infos">Infos pratiques</a>
          <a href="#localisation">Localisation</a>
          <a class="d-tabs-book btn btn-primary" href="${escapeHtml(book)}" target="_blank" rel="sponsored noopener" ${trk}>Réserver</a>
        </div>
      </nav>

      <div class="container detail-layout">
        <article class="detail-content">
          <section id="experience">
            <ul class="highlights">
              ${h.highlights.map((x, i) => `<li class="reveal"><span>${["✦", "☾", "❋", "◈"][i % 4]}</span>${escapeHtml(x)}</li>`).join("")}
            </ul>
            <h2 class="reveal">L'expérience</h2>
            ${h.description.map((p, i) => `<p class="${i ? "body" : "lead dropcap"} reveal">${escapeHtml(p)}</p>`).join("")}
          </section>

          <section id="photos">
            <h2 class="reveal">En images</h2>
            <div class="mosaic">
              ${photos.map((src, i) => `
                <button type="button" class="m-item reveal" data-i="${i}" aria-label="Agrandir la photo ${i + 1}">
                  <img src="${img(src, i % 3 === 0 ? 1800 : 900)}" alt="${escapeHtml(h.name)} — photo ${i + 1}" loading="lazy">
                </button>`).join("")}
            </div>
          </section>

          <section id="infos">
            <h2 class="reveal">Infos pratiques</h2>
            ${h.amenities.length ? `<ul class="amenities reveal">${h.amenities.map((a) => `<li>${escapeHtml(a)}</li>`).join("")}</ul>` : ""}
            <dl class="facts reveal">
              <div><dt>Hébergement</dt><dd>${escapeHtml(h.rooms)}</dd></div>
              <div><dt>Budget</dt><dd>${"€".repeat(h.budget)} · ${escapeHtml(b.range)}</dd></div>
              ${h.season ? `<div><dt>Saison</dt><dd>${escapeHtml(h.season)}</dd></div>` : ""}
              <div><dt>Adresse</dt><dd>${escapeHtml(h.address)}</dd></div>
            </dl>
          </section>

          <section id="localisation">
            <h2 class="reveal">Localisation</h2>
            <div id="mini-map" class="mini-map reveal"></div>
            <p class="small muted"><a href="https://www.google.com/maps/dir/?api=1&destination=${h.lat},${h.lng}" target="_blank" rel="noopener">Itinéraire Google Maps →</a></p>
          </section>

          <div class="nl-inline reveal">
            <h3>${escapeHtml(CONFIG.newsletter.title)}</h3>
            <p class="muted">${escapeHtml(CONFIG.newsletter.pitch)}</p>
            ${newsletterForm(`fiche-${h.id}`)}
          </div>
        </article>

        <aside class="book-card">
          <p class="book-price">${budgetHtml(h)} <span>${escapeHtml(b.range)}</span></p>
          <p class="small muted">Budget indicatif pour 2 personnes. Vérifiez les disponibilités et le tarif exact selon vos dates.</p>
          ${paid && h.offer ? `<div class="offer"><strong>Offre spéciale</strong>${escapeHtml(h.offer)}</div>` : ""}
          <a class="btn btn-primary btn-block" href="${escapeHtml(book)}" target="_blank" rel="sponsored noopener" ${trk}>Voir les disponibilités sur Booking.com</a>
          ${others.map((o) => `<a class="btn btn-ghost btn-block" href="${escapeHtml(o.href)}" target="_blank" rel="sponsored noopener" data-track="Partenaire" data-hotel="${escapeHtml(h.id)}">Comparer sur ${escapeHtml(o.name)}</a>`).join("")}
          ${paid && h.website ? `<a class="btn btn-ghost btn-block" href="${escapeHtml(h.website)}" target="_blank" rel="noopener" data-track="Site officiel" data-hotel="${escapeHtml(h.id)}">Site officiel de l'établissement</a>` : ""}
          ${paid && h.phone ? `<a class="book-phone" href="tel:${escapeHtml(h.phone.replace(/\s/g, ""))}" data-track="Téléphone" data-hotel="${escapeHtml(h.id)}">☎ ${escapeHtml(h.phone)}</a>` : ""}
          <ul class="book-perks">
            <li>✓ Réservation sécurisée chez notre partenaire</li>
            <li>✓ Aucun frais supplémentaire</li>
            <li>✓ Annulation selon les conditions de l'offre</li>
          </ul>
        </aside>
      </div>

      ${paid ? "" : `<div class="container"><p class="owner-note">Vous êtes le propriétaire de cet établissement ? <a href="hoteliers.html?hotel=${encodeURIComponent(h.id)}">Mettez votre fiche en avant →</a></p></div>`}

      <section class="section section-dark similar">
        <div class="container section-head row">
          <div><p class="eyebrow">Continuer le voyage</p><h2>Vous aimerez aussi</h2></div>
          <div class="rail-nav">
            <button type="button" class="rail-btn" data-rail="similar-rail" data-dir="-1" aria-label="Précédent">←</button>
            <button type="button" class="rail-btn" data-rail="similar-rail" data-dir="1" aria-label="Suivant">→</button>
          </div>
        </div>
        <div class="rail rail-cards" id="similar-rail">${similar.map((x) => card(x, { reveal: false })).join("")}</div>
      </section>

      <div class="mobile-book">
        <span>${budgetHtml(h)}</span>
        <a class="btn btn-primary" href="${escapeHtml(book)}" target="_blank" rel="sponsored noopener" ${trk}>Réserver</a>
      </div>`;

    initMap(loc);
    initLightbox(photos);
    initTabs();
    initShare();
    document.querySelectorAll("[data-rail]").forEach((btn) => btn.addEventListener("click", () => {
      const rail = document.getElementById(btn.dataset.rail);
      rail.scrollBy({ left: Number(btn.dataset.dir) * rail.clientWidth * 0.8, behavior: "smooth" });
    }));
    // Léger effet de parallaxe sur la photo d'ouverture
    const bg = root.querySelector(".d-hero-bg");
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      window.addEventListener("scroll", () => {
        if (window.scrollY < window.innerHeight) bg.style.transform = `translateY(${window.scrollY * 0.3}px) scale(1.05)`;
      }, { passive: true });
    }
    observeReveal(root);
  }

  function initTabs() {
    const links = [...document.querySelectorAll(".d-tabs-inner a[href^='#']")];
    const sections = links.map((a) => document.querySelector(a.getAttribute("href")));
    const tabs = document.getElementById("d-tabs");
    const onScroll = () => {
      const y = window.scrollY + 140;
      let current = 0;
      sections.forEach((s, i) => { if (s && s.offsetTop <= y) current = i; });
      links.forEach((a, i) => a.classList.toggle("on", i === current));
      tabs.classList.toggle("stuck", tabs.getBoundingClientRect().top <= 70);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  function initShare() {
    document.getElementById("share").addEventListener("click", async (e) => {
      const data = { title: h.name, text: h.tagline, url: location.href };
      try {
        if (navigator.share) await navigator.share(data);
        else { await navigator.clipboard.writeText(location.href); e.target.textContent = "✓"; setTimeout(() => (e.target.textContent = "↗"), 1500); }
      } catch { /* partage annulé */ }
    });
  }

  function initMap(loc) {
    if (!window.L) return;
    const map = L.map("mini-map", { scrollWheelZoom: false }).setView([h.lat, h.lng], 10);
    L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png", {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>',
    }).addTo(map);
    L.marker([h.lat, h.lng], { icon: L.divIcon({ className: "photo-pin big", html: `<span style="background-image:url('${img(h.images[0], 400)}')"></span>`, iconSize: [64, 64], iconAnchor: [32, 32] }) }).addTo(map);
    if (loc) {
      L.marker([loc.lat, loc.lng], { icon: L.divIcon({ className: "home-pin", html: "<span>Vous</span>", iconSize: null }) }).addTo(map);
      map.fitBounds([[h.lat, h.lng], [loc.lat, loc.lng]], { padding: [50, 50], maxZoom: 10 });
    }
  }

  function initLightbox(photos) {
    const lb = document.getElementById("lightbox");
    const image = lb.querySelector("img");
    let i = 0, x0 = null;
    const show = (n) => {
      i = (n + photos.length) % photos.length;
      image.classList.remove("in"); void image.offsetWidth;
      image.src = photos[i];
      image.classList.add("in");
      lb.querySelector(".lb-count").textContent = `${i + 1} / ${photos.length}`;
    };
    const open = (n) => { show(n); lb.hidden = false; document.body.classList.add("no-scroll"); };
    const close = () => { lb.hidden = true; document.body.classList.remove("no-scroll"); };

    root.querySelectorAll("[data-i]").forEach((b) => b.addEventListener("click", () => open(Number(b.dataset.i))));
    root.querySelector("[data-open-gallery]").addEventListener("click", () => open(0));
    lb.querySelector(".lb-close").addEventListener("click", close);
    lb.querySelector(".lb-prev").addEventListener("click", () => show(i - 1));
    lb.querySelector(".lb-next").addEventListener("click", () => show(i + 1));
    lb.addEventListener("click", (e) => { if (e.target === lb) close(); });
    lb.addEventListener("touchstart", (e) => { x0 = e.touches[0].clientX; }, { passive: true });
    lb.addEventListener("touchend", (e) => {
      if (x0 == null) return;
      const dx = e.changedTouches[0].clientX - x0;
      if (Math.abs(dx) > 40) show(i + (dx < 0 ? 1 : -1));
      x0 = null;
    });
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
