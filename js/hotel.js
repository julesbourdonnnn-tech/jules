/* Fiche établissement : active les éléments interactifs de la page générée. */
(function () {
  const { formatDistance, distanceKm, getUserLocation, img } = window.NS;

  const id = document.body.dataset.hotel;
  const h = window.HOTELS.find((x) => x.id === id);
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function initDistance(loc) {
    const chip = document.querySelector("[data-dist]");
    if (!chip || !loc) return;
    chip.textContent = `à ${formatDistance(distanceKm(loc, h))} de chez vous`;
    chip.hidden = false;
  }

  function initParallax() {
    const media = document.querySelector(".d-hero-media");
    if (!media || reduceMotion) return;
    let ticking = false;
    window.addEventListener("scroll", () => {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        const y = window.scrollY;
        if (y < window.innerHeight) media.style.transform = `translate3d(0, ${y * 0.3}px, 0)`;
        ticking = false;
      });
    }, { passive: true });
  }

  // Diaporama lent en fondu (effet « film ») sur les premières photos
  function initHeroSlides() {
    const slides = [...document.querySelectorAll(".d-hero-bg")];
    if (slides.length < 2 || reduceMotion) return;
    let i = 0, timer;
    const next = () => {
      slides[i].classList.remove("on");
      i = (i + 1) % slides.length;
      slides[i].classList.add("on");
      timer = setTimeout(next, 7000);
    };
    // On attend que la photo suivante soit chargée avant de lancer le fondu
    const start = () => { clearTimeout(timer); timer = setTimeout(next, 7000); };
    slides.slice(1).forEach((im) => { im.loading = "eager"; });
    document.addEventListener("visibilitychange", () => { if (document.hidden) clearTimeout(timer); else start(); });
    start();
  }

  // Boutons « Choisir mes dates » : on descend jusqu'au bloc de réservation
  function initScrollBook() {
    document.addEventListener("click", (e) => {
      const a = e.target.closest("[data-scroll-book]");
      if (!a) return;
      const card = document.getElementById("reserver");
      if (!card) return;
      e.preventDefault();
      card.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "center" });
      card.classList.remove("flash"); void card.offsetWidth; card.classList.add("flash");
      const input = card.querySelector('input[name="checkin"]');
      if (input && !input.value) setTimeout(() => input.focus({ preventScroll: true }), 500);
    });
  }

  function initTabs() {
    const tabs = document.getElementById("d-tabs");
    if (!tabs) return;
    const links = [...tabs.querySelectorAll("a[href^='#']")];
    const sections = links.map((a) => document.querySelector(a.getAttribute("href")));
    const onScroll = () => {
      const y = window.scrollY + 160;
      let current = 0;
      sections.forEach((s, i) => { if (s && s.getBoundingClientRect().top + window.scrollY <= y) current = i; });
      links.forEach((a, i) => a.classList.toggle("on", i === current));
      tabs.classList.toggle("stuck", tabs.getBoundingClientRect().top <= 72);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  function initShare() {
    const btn = document.getElementById("share");
    if (!btn) return;
    btn.addEventListener("click", async () => {
      const data = { title: h.name, text: h.tagline, url: location.href };
      try {
        if (navigator.share) await navigator.share(data);
        else {
          await navigator.clipboard.writeText(location.href);
          btn.textContent = "✓";
          btn.setAttribute("aria-label", "Lien copié");
          setTimeout(() => { btn.textContent = "↗"; btn.setAttribute("aria-label", "Partager cette page"); }, 1600);
        }
      } catch { /* partage annulé */ }
    });
  }

  function initMap(loc) {
    const el = document.getElementById("mini-map");
    if (!el || !window.L) return;
    const map = L.map(el, { scrollWheelZoom: false }).setView([h.lat, h.lng], 10);
    window.NS.baseLayer("plan").addTo(map);
    L.marker([h.lat, h.lng], {
      icon: L.divIcon({ className: "photo-pin big", html: `<span style="background-image:url('${img(h.images[0], 400)}')"></span>`, iconSize: [64, 64], iconAnchor: [32, 32] }),
      alt: h.name,
    }).addTo(map);
    if (loc) {
      L.marker([loc.lat, loc.lng], { icon: L.divIcon({ className: "home-pin", html: "<span>Vous</span>", iconSize: null }) }).addTo(map);
      map.fitBounds([[h.lat, h.lng], [loc.lat, loc.lng]], { padding: [50, 50], maxZoom: 10 });
    }
  }

  function initLightbox() {
    const lb = document.getElementById("lightbox");
    if (!lb) return;
    const photos = h.images.map((p) => img(p));
    const image = lb.querySelector("img");
    let i = 0, x0 = null, lastFocus = null;
    const show = (n) => {
      i = (n + photos.length) % photos.length;
      image.classList.remove("in"); void image.offsetWidth;
      image.src = photos[i];
      image.alt = `${h.name}, photo ${i + 1} sur ${photos.length}`;
      image.classList.add("in");
      lb.querySelector(".lb-count").textContent = `${i + 1} / ${photos.length}`;
      // Précharge la suivante
      const next = new Image(); next.src = photos[(i + 1) % photos.length];
    };
    const open = (n) => {
      lastFocus = document.activeElement;
      show(n);
      lb.hidden = false;
      document.body.classList.add("no-scroll");
      lb.querySelector(".lb-close").focus();
    };
    const close = () => {
      if (lb.hidden) return;
      lb.hidden = true;
      document.body.classList.remove("no-scroll");
      if (lastFocus) lastFocus.focus();
    };
    document.querySelectorAll(".mosaic [data-i]").forEach((b) => b.addEventListener("click", () => open(Number(b.dataset.i))));
    const galleryBtn = document.querySelector("[data-open-gallery]");
    if (galleryBtn) galleryBtn.addEventListener("click", () => open(0));
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
    if (!h) return;
    const loc = getUserLocation();
    initDistance(loc);
    initParallax();
    initHeroSlides();
    initScrollBook();
    initTabs();
    initShare();
    initMap(loc);
    initLightbox();
  });
})();
