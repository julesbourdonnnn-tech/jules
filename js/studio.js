/* Studio : génère visuels Instagram, légendes, newsletter et rapports hôteliers. */
(function () {
  const { CONFIG, escapeHtml, formatPrice, img, planRank } = window.NS;
  const HOTELS = window.HOTELS, ENVS = window.ENVIRONMENTS, TYPES = window.TYPES;
  const $ = (sel) => document.querySelector(sel);
  const byId = (id) => HOTELS.find((h) => h.id === id);
  const siteUrl = CONFIG.siteUrl.replace(/\/$/, "");
  const hotelUrl = (h, src) => `${siteUrl}/hotel.html?id=${encodeURIComponent(h.id)}&src=${src}`;
  const ig = CONFIG.social.instagram;

  const COLORS = { ink: "#1d2420", cream: "#f6f1e9", forest: "#2f4a3a", terracotta: "#c0673f", gold: "#b8925a", sand: "#f3d9b1" };
  const SERIF = "Fraunces, Georgia, serif";
  const SANS = "Inter, system-ui, sans-serif";

  const hotelOptions = () => HOTELS
    .slice()
    .sort((a, b) => planRank(b) - planRank(a) || a.name.localeCompare(b.name, "fr"))
    .map((h) => `<option value="${h.id}">${planRank(h) ? "★ " : ""}${escapeHtml(h.name)} — ${escapeHtml(h.city)}</option>`)
    .join("");

  async function copy(text, btn) {
    try { await navigator.clipboard.writeText(text); }
    catch {
      const t = document.createElement("textarea");
      t.value = text; document.body.appendChild(t); t.select(); document.execCommand("copy"); t.remove();
    }
    if (btn) { const old = btn.textContent; btn.textContent = "Copié ✓"; setTimeout(() => (btn.textContent = old), 1500); }
  }

  /* ============================================================
     INSTAGRAM — visuels dessinés dans un <canvas>
     ============================================================ */
  const imageCache = new Map();
  function loadImage(url) {
    if (!imageCache.has(url)) {
      imageCache.set(url, new Promise((resolve) => {
        const im = new Image();
        im.crossOrigin = "anonymous"; // nécessaire pour pouvoir exporter l'image
        im.onload = () => resolve(im);
        im.onerror = () => resolve(null);
        im.src = img(url, 1600);
      }));
    }
    return imageCache.get(url);
  }

  function drawCover(ctx, im, W, H) {
    if (!im) {
      const g = ctx.createLinearGradient(0, 0, W, H);
      g.addColorStop(0, COLORS.forest); g.addColorStop(1, COLORS.gold);
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
      return;
    }
    const r = Math.max(W / im.width, H / im.height);
    const w = im.width * r, h = im.height * r;
    ctx.drawImage(im, (W - w) / 2, (H - h) / 2, w, h);
  }

  function shade(ctx, W, H, from = 0.35) {
    const g = ctx.createLinearGradient(0, H * from, 0, H);
    g.addColorStop(0, "rgba(10,16,12,0)");
    g.addColorStop(1, "rgba(10,16,12,.85)");
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
    const top = ctx.createLinearGradient(0, 0, 0, 220);
    top.addColorStop(0, "rgba(10,16,12,.45)"); top.addColorStop(1, "rgba(10,16,12,0)");
    ctx.fillStyle = top; ctx.fillRect(0, 0, W, 220);
  }

  function wrap(ctx, text, maxWidth) {
    const words = text.split(/\s+/), lines = [];
    let line = "";
    for (const w of words) {
      const test = line ? `${line} ${w}` : w;
      if (ctx.measureText(test).width > maxWidth && line) { lines.push(line); line = w; }
      else line = test;
    }
    if (line) lines.push(line);
    return lines;
  }

  function pill(ctx, text, x, y, { bg, fg, size = 26, align = "left" }) {
    ctx.font = `600 ${size}px ${SANS}`;
    const w = ctx.measureText(text).width + size * 1.4, h = size * 1.9;
    const left = align === "right" ? x - w : x;
    ctx.fillStyle = bg;
    ctx.beginPath(); ctx.roundRect(left, y, w, h, h / 2); ctx.fill();
    ctx.fillStyle = fg; ctx.textBaseline = "middle";
    ctx.fillText(text, left + size * 0.7, y + h / 2 + 1);
    ctx.textBaseline = "alphabetic";
  }

  function brandMark(ctx, W, color = "#fff") {
    ctx.fillStyle = color;
    ctx.font = `500 28px ${SANS}`;
    ctx.letterSpacing = "6px";
    ctx.fillText(`✦ ${CONFIG.siteName.toUpperCase()}`, 64, 96);
    ctx.letterSpacing = "0px";
  }

  // Dessine un bloc de texte aligné en bas et renvoie la position haute
  function bottomBlock(ctx, W, H, h, { showPrice, footer }) {
    const x = 64, maxW = W - 128;
    let y = H - 90;
    if (footer) {
      ctx.font = `500 30px ${SANS}`; ctx.fillStyle = "rgba(255,255,255,.9)";
      ctx.fillText(footer, x, y); y -= 64;
    }
    ctx.font = `400 34px ${SANS}`; ctx.fillStyle = "rgba(255,255,255,.88)";
    const place = `${h.city} · ${h.department}${showPrice ? `  —  dès ${formatPrice(h.price)} / nuit` : ""}`;
    ctx.fillText(place, x, y); y -= 70;
    ctx.font = `400 92px ${SERIF}`; ctx.fillStyle = "#fff";
    const lines = wrap(ctx, h.name, maxW);
    for (let i = lines.length - 1; i >= 0; i--) { ctx.fillText(lines[i], x, y); y -= 100; }
    ctx.font = `600 28px ${SANS}`; ctx.fillStyle = COLORS.sand; ctx.letterSpacing = "4px";
    ctx.fillText(`${TYPES[h.type].label.toUpperCase()}`, x, y + 22);
    ctx.letterSpacing = "0px";
  }

  async function slideCover(h, W, H, sponsored, story) {
    const c = canvas(W, H), ctx = c.getContext("2d");
    drawCover(ctx, await loadImage(h.images[0]), W, H);
    shade(ctx, W, H);
    brandMark(ctx, W);
    if (sponsored) pill(ctx, "Collaboration commerciale", W - 64, 58, { bg: "rgba(255,255,255,.92)", fg: COLORS.ink, align: "right", size: 24 });
    bottomBlock(ctx, W, H, h, { showPrice: story, footer: story ? "Réservation : lien en bio ✦" : "Glisse pour découvrir  →" });
    return c;
  }

  async function slidePhoto(h, W, H, url, text, index, total, sponsored) {
    const c = canvas(W, H), ctx = c.getContext("2d");
    drawCover(ctx, await loadImage(url), W, H);
    shade(ctx, W, H, 0.5);
    brandMark(ctx, W);
    if (sponsored) pill(ctx, "Collaboration commerciale", W - 64, 58, { bg: "rgba(255,255,255,.92)", fg: COLORS.ink, align: "right", size: 24 });
    ctx.font = `italic 400 64px ${SERIF}`; ctx.fillStyle = "#fff";
    const lines = wrap(ctx, text, W - 128);
    let y = H - 110 - (lines.length - 1) * 76;
    ctx.fillStyle = COLORS.sand; ctx.fillRect(64, y - 100, 60, 4);
    ctx.fillStyle = "#fff";
    lines.forEach((l) => { ctx.fillText(l, 64, y); y += 76; });
    ctx.font = `500 26px ${SANS}`; ctx.fillStyle = "rgba(255,255,255,.7)";
    ctx.textAlign = "right"; ctx.fillText(`${index} / ${total}`, W - 64, 96); ctx.textAlign = "left";
    return c;
  }

  async function slideInfo(h, W, H) {
    const c = canvas(W, H), ctx = c.getContext("2d");
    ctx.fillStyle = COLORS.cream; ctx.fillRect(0, 0, W, H);
    brandMark(ctx, W, COLORS.gold);
    let y = 250;
    ctx.fillStyle = COLORS.terracotta; ctx.font = `600 28px ${SANS}`; ctx.letterSpacing = "4px";
    ctx.fillText("EN PRATIQUE", 64, y); ctx.letterSpacing = "0px"; y += 100;
    ctx.fillStyle = COLORS.ink; ctx.font = `400 76px ${SERIF}`;
    wrap(ctx, h.name, W - 128).forEach((l) => { ctx.fillText(l, 64, y); y += 86; });
    y += 30;
    const rows = [
      ["📍", `${h.city}, ${h.department}`],
      ["🛏", h.rooms],
      ["💶", `dès ${formatPrice(h.price)} / nuit`],
      ...h.highlights.slice(0, 3).map((x) => ["✦", x]),
    ];
    ctx.font = `400 38px ${SANS}`;
    rows.forEach(([icon, text]) => {
      ctx.fillStyle = COLORS.ink;
      ctx.fillText(icon, 64, y);
      wrap(ctx, text, W - 200).forEach((l, i) => { ctx.fillText(l, 130, y + i * 50); y += i ? 50 : 0; });
      y += 74;
    });
    const boxY = H - 300;
    ctx.fillStyle = COLORS.forest;
    ctx.beginPath(); ctx.roundRect(64, boxY, W - 128, 200, 28); ctx.fill();
    ctx.fillStyle = "#fff"; ctx.textAlign = "center";
    ctx.font = `400 50px ${SERIF}`; ctx.fillText("Réservez via le lien en bio", W / 2, boxY + 92);
    ctx.font = `500 30px ${SANS}`; ctx.fillStyle = COLORS.sand;
    ctx.fillText(ig ? `@${ig}` : CONFIG.siteName, W / 2, boxY + 148);
    ctx.textAlign = "left";
    return c;
  }

  function canvas(W, H) {
    const c = document.createElement("canvas");
    c.width = W; c.height = H;
    return c;
  }

  let currentSlides = [];
  async function renderInstagram() {
    const h = byId($("#ig-hotel").value);
    const story = $("#ig-format").value === "story";
    const sponsored = $("#ig-sponsored").checked;
    const W = 1080, H = story ? 1920 : 1350;
    $("#ig-msg").textContent = "Création des visuels…";

    await Promise.all([
      document.fonts.load(`400 92px Fraunces`), document.fonts.load(`italic 400 64px Fraunces`),
      document.fonts.load(`600 28px Inter`), document.fonts.load(`400 34px Inter`),
    ]).catch(() => {});

    const slides = [await slideCover(h, W, H, sponsored, story)];
    if (!story) {
      const extra = h.images.slice(1, 4);
      const texts = h.highlights.concat(h.amenities);
      for (let i = 0; i < extra.length; i++) {
        slides.push(await slidePhoto(h, W, H, extra[i], texts[i] || h.tagline, i + 2, extra.length + 2, sponsored));
      }
      slides.push(await slideInfo(h, W, H));
    }
    currentSlides = slides.map((c, i) => ({ canvas: c, name: `${h.id}-${story ? "story" : i + 1}.png` }));

    const wrapEl = $("#ig-slides");
    wrapEl.className = `studio-preview slides ${story ? "is-story" : ""}`;
    wrapEl.innerHTML = "";
    currentSlides.forEach((s, i) => {
      const fig = document.createElement("figure");
      fig.appendChild(s.canvas);
      const cap = document.createElement("figcaption");
      cap.innerHTML = `<span>${i + 1}</span><button type="button" class="btn-text">Télécharger</button>`;
      cap.querySelector("button").addEventListener("click", () => download(s));
      fig.appendChild(cap);
      wrapEl.appendChild(fig);
    });

    $("#ig-caption").value = caption(h, sponsored, story);
    $("#ig-link").value = hotelUrl(h, "instagram");
    $("#ig-msg").textContent = `${slides.length} visuel${slides.length > 1 ? "s" : ""} prêt${slides.length > 1 ? "s" : ""}. Pense à ajouter « ${h.id} » en tête de social.bioHotels dans config.js.`;
  }

  function download(slide) {
    try {
      slide.canvas.toBlob((blob) => {
        const a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = slide.name;
        a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 2000);
      }, "image/png");
    } catch {
      $("#ig-msg").textContent = "Export impossible : le site qui héberge cette photo n'autorise pas sa réutilisation. Héberge la photo dans le dossier assets/ du site.";
    }
  }

  /* ---------- Légende ---------- */
  const tag = (s) => "#" + s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-zA-Z0-9]/g, "").toLowerCase();
  const TYPE_TAGS = {
    cabane: "#cabaneperchee", bulle: "#bulleinsolite", chateau: "#chateaudefrance", troglodyte: "#troglodyte",
    phare: "#phare", igloo: "#igloo", chalet: "#chaletdeluxe", eau: "#nuitsurleau", yourte: "#glamping",
    historique: "#patrimoine", design: "#hoteldesign", atypique: "#hebergementinsolite",
  };
  const ENV_TAGS = { ville: "#citybreak", campagne: "#campagnefrancaise", mer: "#bordsdemer", montagne: "#montagne" };

  function caption(h, sponsored, story) {
    // Quelques hashtags ciblés (Instagram en limite le nombre) : type, niche, région, ambiance
    const tags = [TYPE_TAGS[h.type], "#hotelinsolite", "#weekendinsolite", tag(h.region), ENV_TAGS[h.env]];
    const lines = [];
    if (sponsored) lines.push(`Collaboration commerciale avec ${h.name}`, "");
    lines.push(`${TYPES[h.type].icon} ${h.name} — ${h.tagline}`, "");
    lines.push(h.description[0], "");
    h.highlights.forEach((x) => lines.push(`✦ ${x}`));
    lines.push("", `📍 ${h.city}, ${h.department}`, `💶 dès ${h.price} € la nuit`);
    if (planRank(h) && h.offer) lines.push(`🎁 ${h.offer}`);
    lines.push("", story ? "👉 Réservation : lien en story" : "👉 Réservation : lien en bio, adresse n°1");
    lines.push("💾 Enregistre ce post pour ton prochain week-end", "💬 Tague la personne avec qui tu y dormirais", "");
    lines.push(tags.join(" "));
    return lines.join("\n");
  }

  /* ============================================================
     NEWSLETTER — e-mail HTML compatible Brevo / Mailchimp
     ============================================================ */
  function newsletterHtml(hotels, intro, subject) {
    const esc = escapeHtml;
    const blocks = hotels.map((h) => `
      <tr><td style="padding:0 0 40px">
        <a href="${esc(hotelUrl(h, "newsletter"))}"><img src="${esc(img(h.images[0], 1200))}" width="560" alt="${esc(h.name)}" style="display:block;width:100%;max-width:560px;height:auto;border-radius:12px;border:0"></a>
        <p style="margin:18px 0 6px;font:600 12px Arial,sans-serif;letter-spacing:2px;text-transform:uppercase;color:${COLORS.terracotta}">${esc(TYPES[h.type].label)} · ${esc(h.city)}${planRank(h) ? ` <span style="color:#7b847e">· Partenaire</span>` : ""}</p>
        <h2 style="margin:0 0 8px;font:400 28px Georgia,serif;color:${COLORS.ink}">${esc(h.name)}</h2>
        <p style="margin:0 0 12px;font:italic 17px Georgia,serif;color:#4a544e">${esc(h.tagline)}</p>
        <p style="margin:0 0 16px;font:15px/1.6 Arial,sans-serif;color:#4a544e">${esc(h.description[0])}</p>
        ${planRank(h) && h.offer ? `<p style="margin:0 0 16px;padding:12px 16px;background:#fbeee6;border-radius:8px;font:14px Arial,sans-serif;color:${COLORS.ink}">🎁 <strong>Offre lecteurs :</strong> ${esc(h.offer)}</p>` : ""}
        <table role="presentation" cellpadding="0" cellspacing="0"><tr>
          <td style="background:${COLORS.terracotta};border-radius:999px"><a href="${esc(hotelUrl(h, "newsletter"))}" style="display:inline-block;padding:12px 24px;font:600 15px Arial,sans-serif;color:#fff;text-decoration:none">Découvrir · dès ${h.price} € / nuit</a></td>
        </tr></table>
      </td></tr>`).join("");

    const igLine = ig ? `<a href="https://www.instagram.com/${esc(ig)}/" style="color:${COLORS.forest}">Instagram @${esc(ig)}</a> · ` : "";
    return `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${esc(subject)}</title></head>
<body style="margin:0;background:${COLORS.cream}">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${COLORS.cream}"><tr><td align="center" style="padding:32px 16px">
  <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#fffdf9;border-radius:16px">
    <tr><td style="padding:36px 20px 8px;text-align:center">
      <p style="margin:0;font:500 13px Arial,sans-serif;letter-spacing:4px;color:${COLORS.gold}">✦ ${esc(CONFIG.siteName.toUpperCase())}</p>
      <h1 style="margin:14px 0 0;font:400 30px Georgia,serif;color:${COLORS.ink}">${esc(CONFIG.newsletter.title)}</h1>
    </td></tr>
    <tr><td style="padding:20px 20px 32px;font:16px/1.6 Arial,sans-serif;color:#4a544e">${esc(intro).replace(/\n/g, "<br>")}</td></tr>
    <tr><td style="padding:0 20px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0">${blocks}</table></td></tr>
    <tr><td style="padding:8px 20px 32px;text-align:center">
      <a href="${esc(siteUrl)}/?src=newsletter#explorer" style="font:600 15px Arial,sans-serif;color:${COLORS.forest}">Voir toute la sélection →</a>
    </td></tr>
  </table>
  <p style="max-width:560px;margin:24px auto 0;font:12px/1.6 Arial,sans-serif;color:#7b847e;text-align:center">
    ${igLine}<a href="${esc(siteUrl)}/hoteliers.html" style="color:#7b847e">Vous êtes hôtelier ?</a><br>
    Liens affiliés : nous percevons une commission sur les réservations, sans surcoût pour vous. Les établissements « Partenaire » ont souscrit une offre de visibilité.<br>
    <a href="{{ unsubscribe }}" style="color:#7b847e">Se désinscrire</a>
  </p>
</td></tr></table>
</body></html>`;
  }

  function selectedNlHotels() {
    return [...document.querySelectorAll("#nl-hotels input:checked")].map((i) => byId(i.value));
  }
  function renderNewsletter() {
    const html = newsletterHtml(selectedNlHotels(), $("#nl-intro").value, $("#nl-subject").value);
    $("#nl-frame").srcdoc = html;
    return html;
  }

  /* ============================================================
     RAPPORT MENSUEL pour les hôteliers partenaires
     ============================================================ */
  function renderReport() {
    const h = byId($("#rp-hotel").value);
    const n = (id) => Number($(id).value) || 0;
    const views = n("#rp-views"), book = n("#rp-book"), site = n("#rp-site"), phone = n("#rp-phone"), reach = n("#rp-ig");
    const clicks = book + site + phone;
    const rate = views ? Math.round((clicks / views) * 1000) / 10 : 0;
    const month = $("#rp-month").value
      ? new Date($("#rp-month").value + "-01").toLocaleDateString("fr-FR", { month: "long", year: "numeric" })
      : "ce mois-ci";
    const plan = CONFIG.plans[h.plan];
    $("#rp-text").value = [
      `Objet : ${h.name} — vos résultats ${month} sur ${CONFIG.siteName}`,
      "",
      "Bonjour,",
      "",
      `Voici le bilan de votre fiche ${h.name} pour ${month}${plan ? ` (offre ${plan.name})` : ""} :`,
      "",
      `• ${views} visites de votre fiche`,
      `• ${book} clics vers la réservation Booking.com`,
      `• ${site} clics vers votre site officiel (réservations sans commission)`,
      `• ${phone} clics sur votre numéro de téléphone`,
      reach ? `• ${reach} personnes touchées sur Instagram` : null,
      "",
      `Au total, ${clicks} clics vers une réservation, soit ${String(rate).replace(".", ",")} clics pour 100 visites de votre fiche.`,
      "",
      h.offer ? `Votre offre spéciale actuelle : « ${h.offer} ». N'hésitez pas à m'en proposer une nouvelle pour le mois prochain, cela relance l'intérêt.` : "Petite suggestion : une offre réservée à nos lecteurs (un petit-déjeuner, une bouteille, -10 % en direct) augmente nettement les clics.",
      "",
      "Belle journée,",
      "",
      CONFIG.siteName,
      CONFIG.contactEmail,
    ].filter((l) => l !== null).join("\n");
  }

  /* ============================================================
     Initialisation
     ============================================================ */
  document.addEventListener("DOMContentLoaded", () => {
    // Onglets
    document.querySelectorAll("[data-tab]").forEach((b) => b.addEventListener("click", () => {
      document.querySelectorAll("[data-tab]").forEach((x) => x.classList.toggle("active", x === b));
      document.querySelectorAll("[data-panel]").forEach((p) => (p.hidden = p.dataset.panel !== b.dataset.tab));
      if (b.dataset.tab === "nl") renderNewsletter();
    }));
    document.querySelectorAll("[data-copy]").forEach((b) =>
      b.addEventListener("click", () => copy($("#" + b.dataset.copy).value, b)));

    // Instagram
    $("#ig-hotel").innerHTML = hotelOptions();
    // Les hôtels Premium ont une publication incluse : mention « Collaboration commerciale » cochée par défaut
    const presetSponsored = () => { $("#ig-sponsored").checked = byId($("#ig-hotel").value).plan === "premium"; };
    $("#ig-hotel").addEventListener("change", () => { presetSponsored(); renderInstagram(); });
    ["#ig-format", "#ig-sponsored"].forEach((s) => $(s).addEventListener("change", renderInstagram));
    presetSponsored();
    $("#ig-download").addEventListener("click", () => currentSlides.forEach((s, i) => setTimeout(() => download(s), i * 400)));
    renderInstagram();

    // Newsletter : Premium en premier, puis coups de cœur
    const picks = HOTELS.filter((h) => h.plan === "premium").concat(HOTELS.filter((h) => h.plan !== "premium" && h.featured)).slice(0, 3).map((h) => h.id);
    $("#nl-hotels").innerHTML = HOTELS.map((h) => `
      <label class="check"><input type="checkbox" value="${h.id}" ${picks.includes(h.id) ? "checked" : ""}> ${planRank(h) ? "★ " : ""}${escapeHtml(h.name)} <small class="muted">${escapeHtml(h.city)}</small></label>`).join("");
    const first = byId(picks[0]);
    $("#nl-subject").value = first ? `${TYPES[first.type].icon} Cette semaine : ${first.name} et 2 autres pépites` : "3 nuits extraordinaires pour ce week-end";
    $("#nl-intro").value = "Bonjour,\n\nCette semaine, on vous emmène dormir là où personne ne pense à dormir. Trois adresses rares, choisies une à une, pour s'offrir une vraie parenthèse.";
    ["#nl-subject", "#nl-intro"].forEach((s) => $(s).addEventListener("input", renderNewsletter));
    $("#nl-hotels").addEventListener("change", renderNewsletter);
    $("#nl-copy").addEventListener("click", (e) => copy(renderNewsletter(), e.target));
    $("#nl-download").addEventListener("click", () => {
      const blob = new Blob([renderNewsletter()], { type: "text/html" });
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `newsletter-${new Date().toISOString().slice(0, 10)}.html`;
      a.click();
    });

    // Rapport hôtelier : partenaires en premier
    $("#rp-hotel").innerHTML = hotelOptions();
    $("#rp-month").value = new Date(Date.now() - 15 * 864e5).toISOString().slice(0, 7);
    document.querySelectorAll('[data-panel="report"] input, [data-panel="report"] select')
      .forEach((el) => el.addEventListener("input", renderReport));
    renderReport();
  });
})();
