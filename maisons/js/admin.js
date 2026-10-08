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

  const refresh = () => { loadCodes(); return api("reservations").then((d) => { data = d; render(); }).catch((e) => { if (e.message !== "auth") $("#list").innerHTML = `<p class="booking__msg is-error">${esc(e.message)}</p>`; }); };
  const enter = () => { $("#login").hidden = true; $("#admin").hidden = false; refresh(); };

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
