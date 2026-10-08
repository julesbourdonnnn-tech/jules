/* Sable & Pierre — espace propriétaire : valider ou refuser les réservations directes */
(function () {
  "use strict";
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const fmt = (s) => { const [y, m, d] = s.split("-").map(Number); return new Intl.DateTimeFormat("fr-FR", { weekday: "short", day: "numeric", month: "short", year: "numeric" }).format(new Date(y, m - 1, d)); };
  const when = (s) => new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(s));
  const LABEL = { paiement: "Paiement en cours", a_valider: "À valider", confirmee: "Confirmée", refusee: "Refusée", annulee: "Annulée", expiree: "Abandonnée" };
  let key = "";
  let data = null;
  let filter = "a_valider";
  try { key = sessionStorage.getItem("sp-admin") || ""; } catch (e) { /* ignoré */ }

  const api = (path, method = "GET", body) => fetch(`api/admin/${path}`, { method, headers: Object.assign({ Authorization: `Bearer ${key}` }, body ? { "Content-Type": "application/json" } : {}), body: body ? JSON.stringify(body) : undefined }).then(async (r) => {
    const d = await r.json().catch(() => ({}));
    if (r.status === 401) { logout(d.message); throw new Error("auth"); }
    if (!r.ok || !d.ok) throw new Error(d.message || "Erreur");
    return d;
  });
  const logout = (msg) => {
    key = "";
    try { sessionStorage.removeItem("sp-admin"); } catch (e) { /* ignoré */ }
    $("#admin").hidden = true;
    $("#login").hidden = false;
    $("#login-msg").textContent = msg || "";
    $("#login-msg").classList.toggle("is-error", !!msg);
  };
  const mailto = (b, kind) => {
    const h = HOUSES[b.maison];
    const subject = kind === "ok" ? `Votre séjour à ${h.name} est confirmé (${b.id})` : `Votre demande pour ${h.name} (${b.id})`;
    const body = kind === "ok"
      ? `Bonjour ${b.nom},\n\nNous avons le plaisir de vous confirmer votre séjour à ${h.name}, du ${fmt(b.arrivee)} au ${fmt(b.depart)}.\n${b.cents ? `Le montant de ${SP_EUR(b.cents)} a été débité.\n` : ""}\nArrivée : ${h.checkIn}. Départ : ${h.checkOut}.\nNous vous enverrons l'adresse exacte et les informations d'arrivée quelques jours avant votre venue.\n\nÀ très bientôt,\n${(window.SITE && SITE.owner) || ""}`
      : `Bonjour ${b.nom},\n\nMerci pour votre demande pour ${h.name} du ${fmt(b.arrivee)} au ${fmt(b.depart)}. Nous ne pouvons malheureusement pas confirmer ce séjour.${b.paymentIntent ? " Rien n'a été débité : l'empreinte sur votre carte est libérée." : ""}\n\nBien cordialement,\n${(window.SITE && SITE.owner) || ""}`;
    return `mailto:${encodeURIComponent(b.email)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  };
  const card = (b) => {
    const h = HOUSES[b.maison] || { name: b.maison };
    const actions = b.statut === "a_valider"
      ? `<button type="button" class="btn btn--accent" data-act="accepter" data-id="${b.id}">Accepter${b.paymentIntent ? " et débiter" : ""}</button><button type="button" class="btn btn--ghost" data-act="refuser" data-id="${b.id}">Refuser</button>`
      : b.statut === "confirmee" ? `<a class="btn btn--ghost" href="${mailto(b, "ok")}">Écrire la confirmation</a><button type="button" class="link" data-act="annuler" data-id="${b.id}">Annuler la réservation</button>`
        : b.statut === "refusee" ? `<a class="btn btn--ghost" href="${mailto(b, "no")}">Écrire au voyageur</a>` : "";
    return `<article class="admin-card" id="resa-${esc(b.id)}" data-house="${b.maison}">
      <div class="admin-card__head"><span class="tag admin-tag admin-tag--${b.statut}">${LABEL[b.statut] || b.statut}</span><span class="small">${esc(b.id)} · reçue le ${when(b.cree)}</span></div>
      <h2 class="h3">${esc(h.name)}</h2>
      <p class="admin-card__dates">${fmt(b.arrivee)} → ${fmt(b.depart)} · ${b.nuits} nuit${b.nuits > 1 ? "s" : ""} · ${b.adultes + b.enfants} voyageur${b.adultes + b.enfants > 1 ? "s" : ""}${b.bebes ? ` + ${b.bebes} bébé(s)` : ""}</p>
      <dl class="admin-card__who">
        <div><dt>Voyageur</dt><dd>${esc(b.nom)}${b.pays ? ` (${esc(b.pays)})` : ""}</dd></div>
        <div><dt>E-mail</dt><dd><a class="link" href="mailto:${esc(b.email)}">${esc(b.email)}</a></dd></div>
        <div><dt>Téléphone</dt><dd>${b.telephone ? `<a class="link" href="tel:${esc(b.telephone)}">${esc(b.telephone)}</a>` : "—"}</dd></div>
        <div><dt>Montant</dt><dd>${b.cents ? SP_EUR(b.cents) : "à définir"}${b.code ? ` (code ${esc(b.code)})` : ""}${b.paiement ? ` · ${esc(b.paiement)}` : ""}</dd></div>
      </dl>
      ${b.message ? `<blockquote class="admin-card__msg">${esc(b.message)}</blockquote>` : ""}
      <div class="admin-card__actions">${actions}</div>
      <p class="booking__msg" data-msg="${b.id}" aria-live="polite"></p>
    </article>`;
  };
  const render = () => {
    const list = data.reservations.filter((b) => (filter === "autres" ? ["refusee", "annulee", "expiree", "paiement"].includes(b.statut) : b.statut === filter));
    if (filter === "confirmee") list.sort((a, b) => (a.arrivee < b.arrivee ? -1 : 1));
    const n = data.reservations.filter((b) => b.statut === "a_valider").length;
    $('[data-f="a_valider"]').textContent = `À valider${n ? ` (${n})` : ""}`;
    $("#list").innerHTML = list.length ? list.map(card).join("") : `<p class="lead">Aucune réservation ici pour le moment.</p>`;
    renderCal();
    const alerts = [];
    if (!data.stripe) alerts.push("Le paiement par carte n'est pas encore activé : ajoute la clé STRIPE_SECRET_KEY dans Cloudflare. En attendant, les voyageurs envoient des demandes sans payer.");
    if (!data.notify) alerts.push("Astuce : ajoute NOTIFY_URL dans Cloudflare pour être prévenu sur ton téléphone à chaque nouvelle réservation.");
    $("#alerts").innerHTML = alerts.map((a) => `<p class="admin-alert">${esc(a)}</p>`).join("");
    $("#feeds").innerHTML = Object.keys(data.feeds).map((k) => `<p><strong>${esc(HOUSES[k].name)}</strong><br><input class="admin-feed" readonly value="${esc(data.feeds[k])}" aria-label="Lien du calendrier ${esc(HOUSES[k].name)}"> <button type="button" class="link" data-copy="${esc(data.feeds[k])}">Copier</button></p>`).join("");
  };
  // Codes promo
  const renderCodes = (codes) => {
    $("#codes").innerHTML = codes.length
      ? `<ul class="admin-codes">${codes.map((c) => `<li><strong>${esc(c.code)}</strong><span>${c.type === "prix" ? `séjour à ${SP_EUR(c.valeur * 100)}` : `−${c.valeur} %`} · ${c.maison ? esc(HOUSES[c.maison].name) : "les deux maisons"} · utilisé ${c.utilisations || 0}${c.max ? ` / ${c.max}` : ""} fois${c.max && (c.utilisations || 0) >= c.max ? " (épuisé)" : ""}</span><button type="button" class="link" data-del-code="${esc(c.code)}">Supprimer</button></li>`).join("")}</ul>`
      : `<p class="small">Aucun code pour le moment.</p>`;
  };
  const loadCodes = () => api("codes").then((d) => renderCodes(d.codes)).catch(() => {});
  $("#code-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const msg = $("#code-msg");
    msg.classList.remove("is-error");
    msg.textContent = "Création…";
    try {
      const d = await api("codes", "POST", { code: $("#c-code").value, type: $("#c-type").value, valeur: $("#c-val").value, maison: $("#c-house").value, max: $("#c-max").value });
      msg.textContent = `Code ${d.code.code} créé.`;
      $("#code-form").reset();
      loadCodes();
    } catch (err) {
      if (err.message !== "auth") { msg.textContent = err.message; msg.classList.add("is-error"); }
    }
  });
  document.addEventListener("click", async (e) => {
    const b = e.target.closest("[data-del-code]");
    if (!b || !window.confirm(`Supprimer le code ${b.dataset.delCode} ?`)) return;
    try { await api(`codes/${encodeURIComponent(b.dataset.delCode)}`, "DELETE"); loadCodes(); } catch (err) { /* ignoré */ }
  });

  /* Calendrier : demandes, réservations confirmées et nuits prises sur Airbnb */
  const DAYMS = 86400000;
  const isoOf = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const now = new Date();
  let calMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  let calHouse = "";
  const AV = window.AVAILABILITY || {};
  const airbnbTaken = (k, iso) => {
    const a = AV[k];
    if (!a || !a.flags) return false;
    const [y, m, d] = a.from.split("-").map(Number);
    const [y2, m2, d2] = iso.split("-").map(Number);
    const i = Math.round((Date.UTC(y2, m2 - 1, d2) - Date.UTC(y, m - 1, d)) / DAYMS);
    if (i < 0 || i >= a.flags.length) return false;
    return !(Number(a.flags[i]) & 1);
  };
  const liveStatus = (b) => b.statut === "a_valider" || b.statut === "confirmee" || (b.statut === "paiement" && Date.now() - Date.parse(b.cree) < 35 * 60000);
  const renderCal = () => {
    if (!data) return;
    const houses = calHouse ? [calHouse] : ["lacanau", "bordeaux"];
    const title = new Intl.DateTimeFormat("fr-FR", { month: "long", year: "numeric" }).format(calMonth);
    $("#cal-title").textContent = title.charAt(0).toUpperCase() + title.slice(1);
    const first = new Date(calMonth);
    const start = new Date(first);
    start.setDate(1 - ((first.getDay() + 6) % 7)); // lundi
    const todayIso = isoOf(now);
    const books = data.reservations.filter(liveStatus).filter((b) => houses.includes(b.maison)).sort((a, b) => (a.maison === b.maison ? (a.arrivee < b.arrivee ? -1 : 1) : a.maison < b.maison ? 1 : -1));
    let html = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"].map((d) => `<div class="admin-cal__dow">${d}</div>`).join("");
    for (let i = 0; i < 42; i++) {
      const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
      if (i === 35 && d.getMonth() !== calMonth.getMonth()) break;
      const iso = isoOf(d);
      const monday = d.getDay() === 1;
      const evs = [];
      houses.forEach((k) => {
        const mine = books.filter((b) => b.maison === k && b.arrivee <= iso && iso < b.depart);
        mine.forEach((b) => {
          const label = b.arrivee === iso || monday || d.getDate() === 1;
          evs.push(`<button type="button" class="ev ev--${b.statut}${b.arrivee === iso ? " ev--start" : ""}${isoOf(new Date(d.getTime() + DAYMS)) === b.depart ? " ev--end" : ""}" data-goto="${esc(b.id)}" data-st="${b.statut}" title="${esc(`${HOUSES[k].name} · ${b.nom} · ${fmt(b.arrivee)} → ${fmt(b.depart)} · ${LABEL[b.statut]}`)}"><b class="hl hl--${k}">${k === "lacanau" ? "L" : "B"}</b>${label ? `<span>${esc(b.nom)}</span>` : ""}</button>`);
        });
        if (!mine.length && iso >= todayIso && airbnbTaken(k, iso)) {
          const prev = isoOf(new Date(d.getTime() - DAYMS));
          const label = monday || d.getDate() === 1 || !airbnbTaken(k, prev);
          evs.push(`<span class="ev ev--airbnb" title="${esc(HOUSES[k].name)} : nuit prise sur Airbnb ou bloquée"><b class="hl hl--${k}">${k === "lacanau" ? "L" : "B"}</b>${label ? "<span>Airbnb</span>" : ""}</span>`);
        }
      });
      const other = d.getMonth() !== calMonth.getMonth();
      html += `<div class="admin-cal__day${other ? " is-other" : ""}${iso === todayIso ? " is-today" : ""}${iso < todayIso ? " is-past" : ""}"><span class="admin-cal__num">${d.getDate()}</span>${evs.join("")}</div>`;
    }
    $("#cal-grid").innerHTML = html;
  };
  $("#cal-prev").addEventListener("click", () => { calMonth = new Date(calMonth.getFullYear(), calMonth.getMonth() - 1, 1); renderCal(); });
  $("#cal-next").addEventListener("click", () => { calMonth = new Date(calMonth.getFullYear(), calMonth.getMonth() + 1, 1); renderCal(); });
  $("#cal-today").addEventListener("click", () => { calMonth = new Date(now.getFullYear(), now.getMonth(), 1); renderCal(); });
  $$("[data-ch]").forEach((b) => b.addEventListener("click", () => {
    calHouse = b.dataset.ch;
    $$("[data-ch]").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
    renderCal();
  }));
  // Clic sur une réservation du calendrier : on affiche sa fiche dans la liste
  $("#cal-grid").addEventListener("click", (e) => {
    const ev = e.target.closest("[data-goto]");
    if (!ev) return;
    filter = ev.dataset.st === "confirmee" ? "confirmee" : ev.dataset.st === "a_valider" ? "a_valider" : "autres";
    $$("[data-f]").forEach((x) => x.setAttribute("aria-pressed", String(x.dataset.f === filter)));
    render();
    const card = document.getElementById(`resa-${ev.dataset.goto}`);
    if (card) { card.scrollIntoView({ behavior: "smooth", block: "center" }); card.classList.remove("is-flash"); void card.offsetWidth; card.classList.add("is-flash"); }
  });

  const refresh = () => { loadCodes(); loadStats(); return api("reservations").then((d) => { data = d; render(); }).catch((e) => { if (e.message !== "auth") $("#list").innerHTML = `<p class="booking__msg is-error">${esc(e.message)}</p>`; }); };
  /* Statistiques : visites (anonymes, sans cookie), sources, clics et réservations */
  let statDays = 30;
  const nf = new Intl.NumberFormat("fr-FR");
  const pct = (a, b) => (b ? `${(Math.round((a / b) * 1000) / 10).toLocaleString("fr-FR")} %` : "—");
  const regionName = (() => { try { const dn = new Intl.DisplayNames(["fr"], { type: "region" }); return (c) => (c ? dn.of(c) : "Inconnu"); } catch (e) { return (c) => c || "Inconnu"; } })();
  const SRC = [[/google\./, "Google"], [/bing\./, "Bing"], [/duckduckgo/, "DuckDuckGo"], [/ecosia/, "Ecosia"], [/qwant/, "Qwant"], [/yahoo/, "Yahoo"], [/instagram/, "Instagram"], [/facebook|^fb\b/, "Facebook"], [/airbnb/, "Airbnb"], [/whatsapp|wa\.me/, "WhatsApp"], [/^t\.co$|twitter|x\.com/, "X (Twitter)"], [/linkedin|lnkd/, "LinkedIn"], [/pinterest/, "Pinterest"], [/tiktok/, "TikTok"], [/chatgpt|openai/, "ChatGPT"], [/claude\.ai|perplexity/, "Assistants IA"]];
  const srcName = (h) => { if (!h) return "Accès direct"; const m = SRC.find(([r]) => r.test(h)); return m ? m[1] : h; };
  const PAGE_NAMES = { "/": "Accueil", "/lacanau": "La Maison du Lac (Lacanau)", "/bordeaux": "La Maison de Pierre (Bordeaux)", "/conditions": "Conditions", "/mentions-legales": "Mentions légales", "/vacances-famille-lacanau": "Guide : vacances en famille à Lacanau", "/vacances-famille-bordeaux": "Guide : Bordeaux en famille" };
  const merge = (rows, name) => { const m = new Map(); rows.forEach((r) => { const k = name(r.k); m.set(k, (m.get(k) || 0) + r.v); }); return [...m].map(([k, v]) => ({ k, v })).sort((a, b) => b.v - a.v); };
  const ranked = (title, rows, total) => {
    if (!rows.length) return `<div class="stat-list"><h3>${title}</h3><p class="small">Pas encore de données.</p></div>`;
    const max = Math.max(...rows.map((r) => r.v));
    return `<div class="stat-list"><h3>${title}</h3><ol>${rows.map((r) => `<li><span class="stat-list__k">${esc(r.k)}</span><span class="stat-list__v">${nf.format(r.v)}<small>${pct(r.v, total)}</small></span><i style="width:${Math.max(2, (r.v / max) * 100)}%"></i></li>`).join("")}</ol></div>`;
  };
  const tile = (label, value, sub) => `<div class="stat-tile"><span class="stat-tile__label">${label}</span><strong class="stat-tile__value">${value}</strong>${sub ? `<span class="stat-tile__sub">${sub}</span>` : ""}</div>`;
  const chart = (d) => {
    // Visites par jour (ou par mois sur 12 mois), une seule série
    const byDay = new Map((d.jour || []).map((r) => [r.day, r]));
    let pts = [];
    if (d.jours > 90) {
      const m = new Map();
      (d.jour || []).forEach((r) => { const k = r.day.slice(0, 7); const o = m.get(k) || { v: 0, p: 0 }; o.v += r.v; o.p += r.p; m.set(k, o); });
      const [y0, m0] = d.du.split("-").map(Number);
      for (let i = 0; i < 12; i++) { const dt = new Date(y0, m0 - 1 + i + 1, 1); const k = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}`; const o = m.get(k) || { v: 0, p: 0 }; pts.push({ k, label: new Intl.DateTimeFormat("fr-FR", { month: "short", year: "2-digit" }).format(dt), full: new Intl.DateTimeFormat("fr-FR", { month: "long", year: "numeric" }).format(dt), v: o.v, p: o.p }); }
    } else {
      const [y, mo, da] = d.du.split("-").map(Number);
      for (let i = 0; i < d.jours; i++) { const dt = new Date(y, mo - 1, da + i); const k = isoOf(dt); const o = byDay.get(k) || { v: 0, p: 0 }; pts.push({ k, label: new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short" }).format(dt), full: new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long" }).format(dt), v: o.v, p: o.p }); }
    }
    const max = Math.max(4, ...pts.map((x) => x.v));
    const step = Math.pow(10, Math.floor(Math.log10(max)));
    const top = Math.ceil(max / step) * step;
    // Dessiné à la largeur réelle de l'écran : textes nets et lisibles sur téléphone
    const W = Math.max(280, Math.round(($("#stats-body") || {}).clientWidth || 1000)), H = W < 600 ? 180 : 220, L = 34, B = 26, gap = (W - 34) / pts.length < 8 ? 1 : 2;
    const bw = (W - L) / pts.length;
    const y = (v) => H - B - (v / top) * (H - B - 10);
    const ticks = [0, top / 2, top];
    const every = Math.ceil(pts.length / Math.max(3, Math.floor(W / 110)));
    const bars = pts.map((pt, i) => {
      const x = L + i * bw + gap / 2;
      const h = Math.max(pt.v ? 2 : 0, H - B - y(pt.v));
      const r = Math.min(4, (bw - gap) / 2, h);
      const path = h ? `M${x},${H - B} v${-(h - r)} q0,${-r} ${r},${-r} h${bw - gap - 2 * r} q${r},0 ${r},${r} v${h - r} z` : "";
      return `<g class="bar" data-i="${i}"><rect class="bar__hit" x="${L + i * bw}" y="0" width="${bw}" height="${H - B}"></rect>${path ? `<path d="${path}"></path>` : ""}${i % every === 0 ? `<text x="${x + (bw - gap) / 2}" y="${H - 8}" text-anchor="middle">${esc(pt.label)}</text>` : ""}</g>`;
    }).join("");
    const grid = ticks.map((t) => `<line x1="${L}" x2="${W}" y1="${y(t)}" y2="${y(t)}"></line><text x="${L - 6}" y="${y(t) + 4}" text-anchor="end">${nf.format(t)}</text>`).join("");
    const table = `<details class="stat-table"><summary>Voir les chiffres</summary><table><thead><tr><th>${d.jours > 90 ? "Mois" : "Jour"}</th><th>Visites</th><th>Pages vues</th></tr></thead><tbody>${pts.slice().reverse().map((pt) => `<tr><td>${esc(pt.full)}</td><td>${nf.format(pt.v)}</td><td>${nf.format(pt.p)}</td></tr>`).join("")}</tbody></table></details>`;
    return { html: `<figure class="stat-chart"><figcaption>Visites ${d.jours > 90 ? "par mois" : "par jour"}</figcaption><div class="stat-chart__plot"><svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="Visites ${d.jours > 90 ? "par mois" : "par jour"} sur la période"><g class="grid">${grid}</g>${bars}</svg><div class="stat-tip" hidden></div></div></figure>${table}`, pts };
  };
  const renderStats = (d) => {
    const body = $("#stats-body");
    const r = d.reservations || { demandes: 0, confirmees: 0, chiffre: 0, nuits: 0, parMaison: {} };
    const visits = (d.jour || []).reduce((t, x) => t + x.v, 0);
    const views = (d.jour || []).reduce((t, x) => t + x.p, 0);
    const prev = (d.precedent || {}).v || 0;
    const delta = prev ? Math.round(((visits - prev) / prev) * 100) : null;
    const ev = (name, house) => (d.evenements || []).filter((e) => e.name === name && (!house || e.house === house)).reduce((t, e) => t + e.n, 0);
    const pageV = (path) => ((d.pages || []).find((x) => x.k === path) || { v: 0 }).v;
    const c = chart(d);
    body.innerHTML = `
      ${d.stats ? "" : `<p class="admin-alert">La mesure d'audience n'est pas encore active (base STATS). Elle démarre automatiquement à la prochaine mise à jour du site.</p>`}
      <div class="stat-tiles">
        ${tile("Visites", nf.format(visits), delta == null ? "" : `${delta >= 0 ? "▲" : "▼"} ${Math.abs(delta)} % vs période précédente`)}
        ${tile("Pages vues", nf.format(views), visits ? `${(Math.round((views / visits) * 10) / 10).toLocaleString("fr-FR")} par visite` : "")}
        ${tile("En ce moment", nf.format(d.enCeMoment || 0), "visiteurs, 5 dernières min.")}
        ${tile("Demandes de réservation", nf.format(r.demandes), `taux : ${pct(r.demandes, visits)} des visites`)}
        ${tile("Réservations confirmées", nf.format(r.confirmees), `${nf.format(r.nuits)} nuit${r.nuits > 1 ? "s" : ""}`)}
        ${tile("Chiffre d'affaires direct", SP_EUR(r.chiffre), "réservations confirmées, sans commission")}
      </div>
      ${c.html}
      <div class="stat-funnel">
        <h3>Du clic à la réservation</h3>
        <table><thead><tr><th></th><th>Visites de la fiche</th><th>Clics « Réserver en direct »</th><th>Paiements lancés</th><th>Confirmées</th><th>Clics « Réserver sur Airbnb »</th></tr></thead>
        <tbody>${["lacanau", "bordeaux"].map((k) => `<tr><th>${esc(HOUSES[k].name)}</th><td>${nf.format(pageV(`/${k}`))}</td><td>${nf.format(ev("reserver", k))}</td><td>${nf.format(ev("paiement", k))}</td><td>${nf.format((r.parMaison[k] || {}).confirmees || 0)}</td><td>${nf.format(ev("airbnb", k))}</td></tr>`).join("")}</tbody></table>
      </div>
      <div class="stat-lists">
        ${ranked("D'où viennent les visiteurs", merge(d.sources || [], srcName), visits)}
        ${ranked("Pages les plus vues", (d.pages || []).map((x) => ({ k: PAGE_NAMES[x.k] || x.k, v: x.v })), visits)}
        ${ranked("Pays", merge(d.pays || [], regionName), visits)}
        ${ranked("Appareils", (d.appareils || []).map((x) => ({ k: x.k.charAt(0).toUpperCase() + x.k.slice(1), v: x.v })), visits)}
      </div>
      <p class="small stat-note">Mesure anonyme, sans cookie : un visiteur est compté une fois par jour, sans que l'on puisse savoir qui il est. Les robots et tes propres visites (depuis cet appareil) ne sont pas comptés.</p>`;
    // Info-bulle au survol / au toucher des barres
    const plot = $(".stat-chart__plot", body);
    const tip = $(".stat-tip", body);
    const show = (g) => {
      const pt = c.pts[Number(g.dataset.i)];
      $$(".bar", plot).forEach((x) => x.classList.toggle("is-on", x === g));
      tip.innerHTML = `<strong>${esc(pt.full)}</strong><span>${nf.format(pt.v)} visite${pt.v > 1 ? "s" : ""}</span><span>${nf.format(pt.p)} page${pt.p > 1 ? "s" : ""} vue${pt.p > 1 ? "s" : ""}</span>`;
      tip.hidden = false;
      const box = plot.getBoundingClientRect();
      const gb = g.getBoundingClientRect();
      const left = Math.min(box.width - tip.offsetWidth - 4, Math.max(4, gb.left - box.left + gb.width / 2 - tip.offsetWidth / 2));
      tip.style.left = `${left}px`;
    };
    plot.addEventListener("pointerover", (e) => { const g = e.target.closest(".bar"); if (g) show(g); });
    plot.addEventListener("pointerleave", () => { tip.hidden = true; $$(".bar", plot).forEach((x) => x.classList.remove("is-on")); });
  };
  let lastStats = null;
  let rz;
  window.addEventListener("resize", () => { clearTimeout(rz); rz = setTimeout(() => { if (lastStats) renderStats(lastStats); }, 200); });
  const loadStats = () => api(`stats?jours=${statDays}`).then((d) => { lastStats = d; renderStats(d); }).catch((e) => { if (e.message !== "auth") $("#stats-body").innerHTML = `<p class="booking__msg is-error">${esc(e.message)}</p>`; });
  $$("[data-days]").forEach((b) => b.addEventListener("click", () => {
    statDays = Number(b.dataset.days);
    $$("[data-days]").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
    $("#stats-body").style.opacity = ".5";
    loadStats().then(() => { $("#stats-body").style.opacity = ""; });
  }));

  const enter = () => {
    // Le propriétaire ne compte pas dans les statistiques (sur cet appareil)
    try { document.cookie = "sp_owner=1; max-age=31536000; path=/; SameSite=Lax; Secure"; } catch (e) { /* ignoré */ } $("#login").hidden = true; $("#admin").hidden = false; refresh(); };

  $("#login").addEventListener("submit", (e) => {
    e.preventDefault();
    key = $("#a-key").value.trim();
    try { sessionStorage.setItem("sp-admin", key); } catch (err) { /* ignoré */ }
    enter();
  });
  $("#refresh").addEventListener("click", refresh);
  $("#test-alerts").addEventListener("click", async () => {
    const m = $("#test-msg");
    m.classList.remove("is-error");
    m.textContent = "Envoi des alertes de test…";
    try {
      const d = await api("test-alertes", "POST");
      const r = d.resultat || {};
      m.textContent = `Téléphone : ${r.telephone} · E-mail : ${r.email}`;
      if (/erreur/.test(`${r.telephone} ${r.email}`)) m.classList.add("is-error");
    } catch (err) { if (err.message !== "auth") { m.textContent = err.message; m.classList.add("is-error"); } }
  });
  $$("[data-f]").forEach((b) => b.addEventListener("click", () => {
    filter = b.dataset.f;
    $$("[data-f]").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
    render();
  }));
  document.addEventListener("click", async (e) => {
    const c = e.target.closest("[data-copy]");
    if (c) { try { await navigator.clipboard.writeText(c.dataset.copy); c.textContent = "Copié"; } catch (err) { c.previousElementSibling.select(); } return; }
    const b = e.target.closest("[data-act]");
    if (!b) return;
    const act = b.dataset.act;
    const label = { accepter: "accepter cette réservation (la carte du voyageur sera débitée)", refuser: "refuser cette réservation (l'empreinte bancaire sera libérée)", annuler: "annuler cette réservation confirmée" }[act];
    if (!window.confirm(`Confirmer : ${label} ?`)) return;
    const msg = $(`[data-msg="${b.dataset.id}"]`);
    msg.textContent = "En cours…";
    msg.classList.remove("is-error");
    try {
      const d = await api(`reservations/${b.dataset.id}/${act}`, "POST");
      const i = data.reservations.findIndex((x) => x.id === d.reservation.id);
      data.reservations[i] = d.reservation;
      render();
      if (act === "accepter") window.location.href = mailto(d.reservation, "ok");
    } catch (err) {
      if (err.message !== "auth") { msg.textContent = err.message; msg.classList.add("is-error"); }
    }
  });
  if (key) enter();
})();
