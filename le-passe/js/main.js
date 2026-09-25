/*
 * Le Passe — interactions du site :
 * en-tête, menu mobile, apparitions, calculette « L'addition », bon de commande.
 */
(() => {
  "use strict";
  const C = window.LP_CONFIG || {};
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const eur = (n) => new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR", maximumFractionDigits: 0 }).format(n);
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  /* ---------- En-tête et menu mobile ---------- */
  const header = $(".site-header");
  const floatCta = $("#float-cta");
  const bon = $("#bon");
  const onScroll = () => {
    header.classList.toggle("scrolled", scrollY > 10);
    if (floatCta && bon) {
      const r = bon.getBoundingClientRect();
      floatCta.classList.toggle("show", scrollY > innerHeight * 0.9 && r.top > innerHeight);
    }
  };
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  const menuBtn = $(".menu-btn");
  const closeMenu = () => { document.body.classList.remove("menu-open"); menuBtn.setAttribute("aria-expanded", "false"); };
  menuBtn.addEventListener("click", () => {
    const open = document.body.classList.toggle("menu-open");
    menuBtn.setAttribute("aria-expanded", String(open));
    menuBtn.setAttribute("aria-label", open ? "Fermer le menu" : "Ouvrir le menu");
  });
  $$(".nav-links a").forEach((a) => a.addEventListener("click", closeMenu));
  addEventListener("keydown", (e) => { if (e.key === "Escape") closeMenu(); });

  /* ---------- Lien actif dans le menu ---------- */
  const links = new Map($$('.nav-links a[href^="#"]').map((a) => [a.getAttribute("href").slice(1), a]));
  if ("IntersectionObserver" in window) {
    const spy = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (!e.isIntersecting) return;
        links.forEach((a) => a.classList.remove("active"));
        const a = links.get(e.target.id);
        if (a && !a.classList.contains("btn")) a.classList.add("active");
      });
    }, { rootMargin: "-45% 0px -50% 0px" });
    $$("main section[id]").forEach((s) => spy.observe(s));

    /* Apparition au défilement */
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.06 });
    $$(".reveal, .step").forEach((el) => io.observe(el));
  } else {
    $$(".reveal").forEach((el) => el.classList.add("in"));
  }

  /* ---------- Bandeau défilant ---------- */
  const kinds = ["Bistrots", "Brasseries", "Tables gastronomiques", "Pizzerias", "Bars à vin", "Crêperies", "Food trucks", "Salons de thé", "Traiteurs", "Cuisines du monde", "Caves à manger", "Guinguettes"];
  const track = $("#marquee");
  if (track) track.innerHTML = [...kinds, ...kinds].map((k) => `<span>${k}</span>`).join("");

  /* ---------- Numéro de bon et heure ---------- */
  const now = new Date();
  const bonNo = String(((now.getMonth() + 1) * 100 + now.getDate()) * 7 % 10000).padStart(4, "0");
  $$("[data-bon-no]").forEach((el) => (el.textContent = bonNo));
  $$("[data-bon-time]").forEach((el) => (el.textContent = now.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })));
  $$("[data-bon-date]").forEach((el) => (el.textContent = now.toLocaleDateString("fr-FR", { weekday: "long", day: "numeric", month: "long" })));
  $$("[data-year]").forEach((el) => (el.textContent = now.getFullYear()));

  /* ---------- Coordonnées (depuis js/config.js) ---------- */
  const icon = {
    mail: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/></svg>',
    phone: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2"/></svg>',
    wa: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 21l1.7-5A9 9 0 1 1 8 19.3z"/><path d="M9 10c.5 2 2 3.5 4 4l1.2-1.2 2 1-.7 1.7C12 15.5 8.5 12 8.3 8.5L10 7.8l1 2z"/></svg>',
    ig: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.5" cy="6.5" r="1" fill="#fff"/></svg>',
  };
  const lines = [];
  const foot = [];
  if (C.email) {
    lines.push(`<li><a href="mailto:${esc(C.email)}"><span class="ci">${icon.mail}</span><span>${esc(C.email)}<small>Réponse sous 24 h</small></span></a></li>`);
    foot.push(`<li><a href="mailto:${esc(C.email)}">${esc(C.email)}</a></li>`);
  }
  if (C.phone) {
    lines.push(`<li><a href="tel:${esc(C.phone.replace(/\s/g, ""))}"><span class="ci">${icon.phone}</span><span>${esc(C.phone)}<small>Hors service, de préférence 15 h – 18 h</small></span></a></li>`);
    foot.push(`<li><a href="tel:${esc(C.phone.replace(/\s/g, ""))}">${esc(C.phone)}</a></li>`);
  }
  if (C.whatsapp) {
    const wa = `https://wa.me/${encodeURIComponent(C.whatsapp)}?text=${encodeURIComponent("Bonjour Jules, je vous écris pour le site de mon restaurant.")}`;
    lines.push(`<li><a href="${wa}" target="_blank" rel="noopener"><span class="ci">${icon.wa}</span><span>WhatsApp<small>Une photo de votre carte suffit pour commencer</small></span></a></li>`);
  }
  if (C.instagram) {
    lines.push(`<li><a href="https://instagram.com/${esc(C.instagram)}" target="_blank" rel="noopener"><span class="ci">${icon.ig}</span><span>@${esc(C.instagram)}<small>Les coulisses des sites en cours</small></span></a></li>`);
    foot.push(`<li><a href="https://instagram.com/${esc(C.instagram)}" target="_blank" rel="noopener">Instagram</a></li>`);
  }
  const cl = $("#contact-lines");
  if (cl) cl.innerHTML = lines.join("");
  const fc = $("#foot-contact");
  if (fc) fc.insertAdjacentHTML("beforeend", foot.join(""));
  if (C.zone) {
    const z = $("[data-zone]");
    if (z) z.textContent = `Je me déplace en personne sur ${C.zone}, en dehors du service bien sûr. Ailleurs en France, tout se fait par téléphone ou en visio, aux heures qui conviennent à un restaurateur.`;
  }

  /* ---------- Choix d'une offre depuis la carte ---------- */
  const offerMap = { amuse: "L'amuse-bouche (audit offert)", ardoise: "L'Ardoise", plat: "Le Plat du chef", degustation: "Le Menu dégustation" };
  $$("[data-offer]").forEach((a) => a.addEventListener("click", () => {
    const v = offerMap[a.dataset.offer];
    const input = $$('input[name="offre"]').find((i) => i.value === v);
    if (input) input.checked = true;
  }));

  /* ---------- Calculette « L'addition » ---------- */
  const OFFERS = {
    resa: { name: "Le Plat du chef + 12 mois de service", price: 1690 + 12 * 29 },
    livraison: { name: "Plat du chef + emporter + 12 mois de service", price: 1690 + 590 + 12 * 29 },
  };
  let mode = "resa";
  const val = (id) => parseFloat($("#" + id).value);
  const fmt = {
    "c-resa": (v) => `${v} / mois`, "c-couverts": (v) => String(v).replace(".", ","),
    "c-cmd": (v) => `${v} / mois`, "c-panier": (v) => eur(v), "c-com": (v) => `${v} %`, "c-part": (v) => `${v} %`,
  };
  const feeFmt = (v) => new Intl.NumberFormat("fr-FR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(v) + " €";
  function paint(input) {
    const p = ((input.value - input.min) / (input.max - input.min)) * 100;
    input.style.setProperty("--p", p + "%");
    const out = $("#o-" + input.id.slice(2));
    if (out) out.textContent = input.id === "c-fee" ? feeFmt(+input.value) : fmt[input.id](+input.value);
  }
  function compute() {
    let yearly;
    if (mode === "resa") yearly = val("c-resa") * val("c-couverts") * val("c-fee") * 12;
    else yearly = val("c-cmd") * val("c-panier") * (val("c-com") / 100) * 12;
    const direct = yearly * (val("c-part") / 100);
    const offer = OFFERS[mode];
    const year2 = direct - 12 * 29;
    $("#r-today").textContent = eur(yearly);
    $("#r-direct").textContent = eur(direct);
    $("#r-offer-name").textContent = offer.name;
    $("#r-offer").textContent = eur(offer.price);
    $("#r-save").textContent = year2 > 0 ? eur(year2) + " / an" : "—";
    const monthly = direct / 12 - 29;
    const big = $("#r-months");
    const cap = $("#r-caption");
    if (monthly <= 0) {
      big.textContent = "À voir ensemble";
      cap.innerHTML = "Avec ces chiffres, le site se justifie surtout par les <strong>nouveaux clients</strong> qu'il vous apporte, pas par les commissions évitées. Parlons-en autour de l'amuse-bouche offert.";
    } else {
      const months = Math.ceil((offer.price - 12 * 29) / monthly);
      big.textContent = months <= 1 ? "Rentabilisé en 1 mois" : months > 36 ? "Rentabilisé en plus de 3 ans" : `Rentabilisé en ${months} mois`;
      cap.innerHTML = `Rien qu'avec les commissions évitées, votre site est payé en <strong>${months > 36 ? "plus de 3 ans" : months + " mois"}</strong>. Tout client nouveau qu'il vous amène, c'est du bonus.`;
    }
  }
  const sliders = $$(".calc input[type=range]");
  sliders.forEach((s) => { paint(s); s.addEventListener("input", () => { paint(s); compute(); }); });
  $$(".calc-tabs button").forEach((b) => b.addEventListener("click", () => {
    mode = b.dataset.mode;
    $$(".calc-tabs button").forEach((x) => x.setAttribute("aria-selected", String(x === b)));
    $$("[data-panel]").forEach((p) => (p.hidden = p.dataset.panel !== mode));
    compute();
  }));
  if (sliders.length) compute();

  /* ---------- Le bon de commande ---------- */
  const form = $("#bon-form");
  if (!form) return;
  const err = $("#bon-error");
  const showError = (msg) => { err.textContent = msg; err.hidden = false; };

  function done(data, viaMail) {
    $("[data-form-body]", form).hidden = true;
    const d = $("[data-form-done]", form);
    d.hidden = false;
    $("[data-done-name]", form).textContent = data.nom || "chef";
    const when = data.rappel ? ` (${data.rappel.toLowerCase()})` : "";
    $("[data-done-text]", form).textContent = viaMail
      ? "Votre messagerie s'est ouverte avec le bon pré-rempli : il ne reste qu'à cliquer sur « Envoyer ». Je vous réponds sous 24 h."
      : `Je vous rappelle sous 24 h, au moment que vous avez choisi${when}.`;
    form.scrollIntoView({ behavior: "smooth", block: "center" });
  }

  function mailto(data) {
    const body = [
      `Restaurant : ${data.restaurant}`, `Ville : ${data.ville || "—"}`, `Prénom : ${data.nom}`,
      `Téléphone : ${data.telephone || "—"}`, `E-mail : ${data.email}`, `Type : ${data.type || "—"}`,
      `Aujourd'hui en ligne : ${data.aujourdhui || "—"}`, `Offre : ${data.offre || "—"}`, `Rappel : ${data.rappel || "—"}`,
      "", data.message || "",
    ].join("\n");
    location.href = `mailto:${C.email}?subject=${encodeURIComponent(`Bon de commande — ${data.restaurant}`)}&body=${encodeURIComponent(body)}`;
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    err.hidden = true;
    const fd = new FormData(form);
    if (fd.get("bot-field")) return;
    const data = {
      restaurant: (fd.get("restaurant") || "").trim(), ville: (fd.get("ville") || "").trim(), nom: (fd.get("nom") || "").trim(),
      telephone: (fd.get("telephone") || "").trim(), email: (fd.get("email") || "").trim(), type: fd.get("type") || "",
      aujourdhui: fd.get("aujourdhui") || "", offre: fd.get("offre") || "", rappel: fd.getAll("rappel").join(", "),
      message: (fd.get("message") || "").trim(), page: location.pathname,
    };
    if (!data.restaurant || !data.nom) return showError("Il manque le nom du restaurant ou votre prénom.");
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(data.email)) return showError("L'adresse e-mail ne semble pas complète.");
    const btn = $("button[type=submit]", form);
    btn.disabled = true;
    btn.firstChild.textContent = "Envoi… ";
    try {
      if (!C.api || location.protocol === "file:") throw new Error("local");
      const res = await fetch(C.api, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) });
      const json = await res.json().catch(() => ({}));
      if (!res.ok || !json.ok) throw new Error(json.error || "http");
      done(data, false);
    } catch {
      if (C.email) { mailto(data); done(data, true); }
      else showError("L'envoi n'a pas fonctionné. Réessayez dans un instant.");
    } finally {
      btn.disabled = false;
      btn.firstChild.textContent = "Envoyer au passe ";
    }
  });
})();
