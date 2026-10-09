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
  // E-mail au voyageur, dans sa langue (celle de la page où il a réservé)
  const fmtL = (iso, lang) => { const [y, m, d] = iso.split("-").map(Number); return new Intl.DateTimeFormat({ en: "en-GB", es: "es-ES" }[lang] || "fr-FR", { weekday: "short", day: "numeric", month: "short", year: "numeric" }).format(new Date(y, m - 1, d)); };
  const mailto = (b, kind) => {
    const h = HOUSES[b.maison];
    const lang = b.lang === "en" || b.lang === "es" ? b.lang : "fr";
    const sign = (window.SITE && SITE.owner) || "Sable & Pierre";
    const a = fmtL(b.arrivee, lang);
    const z = fmtL(b.depart, lang);
    const amount = b.cents ? SP_EUR(b.cents) : "";
    const T = {
      fr: {
        okS: `Votre séjour à ${h.name} est confirmé (${b.id})`, noS: `Votre demande pour ${h.name} (${b.id})`,
        ok: `Bonjour ${b.nom},\n\nNous avons le plaisir de vous confirmer votre séjour à ${h.name}, du ${a} au ${z}.\n${amount ? `Le montant de ${amount} a été débité.\n` : ""}\nArrivée : ${h.checkIn}. Départ : ${h.checkOut}.\nNous vous enverrons l'adresse exacte et les informations d'arrivée quelques jours avant votre venue.\n\nÀ très bientôt,\n${sign}`,
        no: `Bonjour ${b.nom},\n\nMerci pour votre demande pour ${h.name} du ${a} au ${z}. Nous ne pouvons malheureusement pas confirmer ce séjour.${b.paymentIntent ? " Rien n'a été débité : l'empreinte sur votre carte est libérée." : ""}\n\nBien cordialement,\n${sign}`,
      },
      en: {
        okS: `Your stay at ${h.name} is confirmed (${b.id})`, noS: `Your request for ${h.name} (${b.id})`,
        ok: `Hello ${b.nom},\n\nWe are delighted to confirm your stay at ${h.name}, from ${a} to ${z}.\n${amount ? `The amount of ${amount} has been charged.\n` : ""}\nCheck-in: ${b.maison === "lacanau" ? "from 4 pm" : "self check-in, flexible"}. Check-out: ${b.maison === "lacanau" ? "before 10 am" : "before 12 noon"}.\nWe will send you the exact address and arrival information a few days before your stay.\n\nSee you very soon,\n${sign}`,
        no: `Hello ${b.nom},\n\nThank you for your request for ${h.name} from ${a} to ${z}. Unfortunately we are unable to confirm this stay.${b.paymentIntent ? " Nothing has been charged: the hold on your card has been released." : ""}\n\nKind regards,\n${sign}`,
      },
      es: {
        okS: `Tu estancia en ${h.name} está confirmada (${b.id})`, noS: `Tu solicitud para ${h.name} (${b.id})`,
        ok: `Hola, ${b.nom}:\n\nNos complace confirmarte tu estancia en ${h.name}, del ${a} al ${z}.\n${amount ? `Se ha cobrado el importe de ${amount}.\n` : ""}\nLlegada: ${b.maison === "lacanau" ? "a partir de las 16 h" : "autónoma, horario flexible"}. Salida: ${b.maison === "lacanau" ? "antes de las 10 h" : "antes de las 12 h"}.\nTe enviaremos la dirección exacta y la información de llegada unos días antes de tu estancia.\n\n¡Hasta muy pronto!\n${sign}`,
        no: `Hola, ${b.nom}:\n\nGracias por tu solicitud para ${h.name} del ${a} al ${z}. Lamentablemente no podemos confirmar esta estancia.${b.paymentIntent ? " No se ha cobrado nada: la retención en tu tarjeta se ha liberado." : ""}\n\nUn cordial saludo,\n${sign}`,
      },
    }[lang];
    const subject = kind === "ok" ? T.okS : T.noS;
    const body = kind === "ok" ? T.ok : T.no;
    return `mailto:${encodeURIComponent(b.email)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  };
  const MAIL_NAMES = { recue: "demande reçue", confirmee: "confirmation", refusee: "refus", annulee: "annulation", rappel: "infos d'arrivée", avis: "demande d'avis", caution_lien: "lien de caution" };
  const isoPlus = (iso, n) => { const [y, m, d] = iso.split("-").map(Number); return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10); };
  const cautionTxt = (b) => {
    const c = b.caution || {};
    if (c.etat === "bloquee") return `bloquée sur sa carte le ${when(c.le)}, libérée automatiquement le ${fmt(isoPlus(b.depart, 2))} (sauf si tu l'encaisses)${c.alerte ? ` · <span class="is-error">${esc(c.alerte)}</span>` : ""}`;
    if (c.etat === "lien") return `sa banque demande une validation : lien envoyé au voyageur le ${when(c.le)} <button type="button" class="link" data-copy="${esc(c.url)}">copier le lien</button>`;
    if (c.etat === "liberee") return `libérée le ${when(c.libereeLe)}`;
    if (c.etat === "encaissee") return `${SP_EUR(c.encaisse)} encaissés le ${when(c.encaisseeLe)}`;
    if (c.etat === "expire") return "le voyageur n'a pas validé le lien : nouvel essai demain matin";
    if (c.etat === "echec") return `<span class="is-error">impossible : ${esc(c.raison || "")}</span>`;
    return `sera bloquée automatiquement le ${fmt(isoPlus(b.arrivee, -1))} (veille de l'arrivée)`;
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
        <div><dt>Voyageur</dt><dd>${esc(b.nom)}${b.pays ? ` (${esc(b.pays)})` : ""}${b.lang && b.lang !== "fr" ? ` · parle ${b.lang === "en" ? "anglais" : "espagnol"}` : ""}</dd></div>
        <div><dt>E-mail</dt><dd><a class="link" href="mailto:${esc(b.email)}">${esc(b.email)}</a></dd></div>
        <div><dt>Téléphone</dt><dd>${b.telephone ? `<a class="link" href="tel:${esc(b.telephone)}">${esc(b.telephone)}</a>` : "—"}</dd></div>
        <div><dt>Montant</dt><dd>${b.cents ? SP_EUR(b.cents) : "à définir"}${b.code ? ` (code ${esc(b.code)})` : ""}${b.paiement ? ` · ${esc(b.paiement)}` : ""}</dd></div>
      </dl>
      ${b.message ? `<blockquote class="admin-card__msg">${esc(b.message)}</blockquote>` : ""}
      ${b.cautionMontant && (b.statut === "confirmee" || b.statut === "a_valider") ? `<p class="admin-card__caution"><strong>Caution ${b.cautionMontant.toLocaleString("fr-FR")} €</strong> · ${cautionTxt(b)}</p>` : ""}
      ${b.mails || b.mailErreur ? `<p class="small">E-mails envoyés : ${Object.entries(b.mails || {}).map(([k, v]) => `${MAIL_NAMES[k] || k} (${when(v)})`).join(", ") || "aucun"}${b.mailErreur ? ` · <span class="is-error">échec ${esc(b.mailErreur)}</span>` : ""}</p>` : ""}
      <div class="admin-card__actions">${actions}${b.caution && b.caution.etat === "bloquee" ? `<button type="button" class="btn btn--ghost" data-cau="encaisser" data-id="${b.id}">Encaisser la caution…</button><button type="button" class="link" data-cau="liberer" data-id="${b.id}">Libérer la caution</button>` : ""}</div>
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

  /* Prix : automatiques (Airbnb ± x %) ou fixés à la main, prix pour des dates précises, événements */
  let px = null; // réglages en cours de modification
  let pxSaved = ""; // dernière version enregistrée
  let pxHouse = "lacanau";
  let pxMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  let pxSel = null; // dates choisies dans le calendrier des prix : { du, au, picking }
  const pxDef = () => ({ mode: "auto", ajust: 0, nuit: null, weekend: null, menage: null, caution: null, dates: [] });
  const isoAdd = (iso, n) => { const [y, m, d] = iso.split("-").map(Number); return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10); };
  const dShort = (iso) => { const [y, m, d] = iso.split("-").map(Number); return new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short", year: y !== now.getFullYear() ? "numeric" : undefined }).format(new Date(y, m - 1, d)); };
  const nNights = (du, au) => Math.round((Date.parse(au) - Date.parse(du)) / DAYMS) + 1;
  const plural = (n, w) => `${n} ${w}${n > 1 ? "s" : ""}`;
  const pxNight = (iso) => SP_NIGHT(pxHouse, iso, px); // prix de la nuit avant remise
  const pxGuest = (v) => (v > 0 ? Math.round((v * (100 - SP_REMISE(px))) / 100) : null); // payé par le voyageur
  const pxAirbnb = (iso) => { const A = (window.TARIFS_AIRBNB || {})[pxHouse]; if (!A || !A.periodes || !A.periodes.length) return null; return (A.periodes.filter((x) => x.du <= iso).pop() || A.periodes[0]).nuit; };
  const pxEvents = (iso) => (window.EVENEMENTS || []).filter((e) => e.maisons.includes(pxHouse) && e.du <= iso && iso <= e.au);
  const pxRule = (iso) => px[pxHouse].dates.find((x) => x.du <= iso && iso <= x.au && (x.nuit > 0 || x.pct));
  const ruleTxt = (r) => (r.nuit ? `${r.nuit.toLocaleString("fr-FR")} € la nuit` : `${r.pct > 0 ? "+" : "−"}${Math.abs(r.pct)} %`);
  const dots = (n) => `<span class="px-impact px-impact--${n}" title="${["", "Un peu plus de demande", "Forte demande", "Très forte demande"][n]}">${"●".repeat(n)}${"○".repeat(3 - n)}</span>`;
  const range = (du, au) => { const v = []; for (let d = du; d <= au; d = isoAdd(d, 1)) v.push(pxGuest(pxNight(d))); const ok = v.filter((x) => x > 0); if (!ok.length) return "prix sur demande"; const a = Math.min(...ok), b = Math.max(...ok); return a === b ? `${a.toLocaleString("fr-FR")} €` : `${a.toLocaleString("fr-FR")} à ${b.toLocaleString("fr-FR")} €`; };

  const renderPrix = () => {
    if (!px) return;
    const H = px[pxHouse];
    const todayIso = isoOf(now);
    const rem = SP_REMISE(px);
    const dirty = JSON.stringify(px) !== pxSaved;
    const A = window.TARIFS_AIRBNB || {};
    const auto = H.mode !== "manuel";
    const hint = (v) => (v > 0 ? `<span class="px-hint">soit ${pxGuest(v).toLocaleString("fr-FR")} € la nuit sur ton site</span>` : "");
    let html = `<div class="px-top">
      <label class="px-switch"><input type="checkbox" id="px-auto"${auto ? " checked" : ""}><span class="px-switch__ui" aria-hidden="true"></span>
        <span><strong>Prix automatiques</strong><span class="small">${auto ? `Basés sur les prix Airbnb, relevés chaque jour${A.updated ? ` (dernier relevé : ${dShort(A.updated)})` : ""}.` : "Désactivés : tu fixes toi-même le prix de la nuit."}</span></span></label>
      <div class="px-top__fields"><div class="field px-remise"><label for="px-rem">Remise réservation directe</label><div class="px-unit"><input id="px-rem" type="number" min="0" max="50" step="1" inputmode="numeric" value="${rem}"><span>%</span></div></div>
      <div class="field px-remise"><label for="px-cau">Caution ${pxHouse === "lacanau" ? "Lacanau" : "Bordeaux"}</label><div class="px-unit"><input id="px-cau" type="number" min="0" max="5000" step="50" inputmode="numeric" value="${SP_CAUTION(pxHouse, px)}"><span>€</span></div></div></div>
    </div>`;
    if (auto) {
      html += `<div class="px-panel"><p class="px-label">Ajustement par rapport à Airbnb</p>
        <div class="admin-tabs px-adj">${[-15, -10, -5, 0, 5, 10, 15, 20].map((v) => `<button type="button" class="chip" data-adj="${v}" aria-pressed="${Number(H.ajust) === v}">${v > 0 ? "+" : v < 0 ? "−" : ""}${Math.abs(v)} %</button>`).join("")}
        <div class="px-unit px-unit--sm"><input id="px-adj" type="number" min="-50" max="100" step="1" inputmode="numeric" value="${Number(H.ajust) || 0}" aria-label="Ajustement personnalisé en %"><span>%</span></div></div>
        <p class="small">Le prix de chaque nuit suit Airbnb${Number(H.ajust) ? ` ${H.ajust > 0 ? "+" : "−"}${Math.abs(H.ajust)} %` : ""}, puis la remise de ${rem} % s'applique. Ménage et taxe de séjour : comme sur Airbnb.</p></div>`;
    } else {
      html += `<div class="px-panel px-manual">
        <div class="field"><label for="px-nuit">Prix de la nuit (dimanche → jeudi)</label><div class="px-unit"><input id="px-nuit" type="number" min="20" step="5" inputmode="numeric" value="${H.nuit || ""}" required><span>€</span></div>${hint(H.nuit)}</div>
        <div class="field"><label for="px-we">Nuits du vendredi et du samedi</label><div class="px-unit"><input id="px-we" type="number" min="20" step="5" inputmode="numeric" value="${H.weekend || ""}" placeholder="${H.nuit || ""}"><span>€</span></div>${hint(H.weekend || H.nuit)}</div>
        <div class="field"><label for="px-men">Ménage et frais (par séjour)</label><div class="px-unit"><input id="px-men" type="number" min="0" step="5" inputmode="numeric" value="${H.menage != null ? H.menage : ""}" placeholder="${(A[pxHouse] || {}).fixe || ""}"><span>€</span></div></div>
        <p class="small">Prix avant la remise de ${rem} %. Les prix fixés pour des dates précises (plus bas) passent toujours en priorité.${(() => { const v = Array.from({ length: 365 }, (x, i) => pxAirbnb(isoAdd(todayIso, i + 1))).filter(Boolean); return v.length ? ` <strong>Repère : sur Airbnb, la nuit va de ${Math.min(...v).toLocaleString("fr-FR")} à ${Math.max(...v).toLocaleString("fr-FR")} € selon la saison</strong> — pense à monter les prix de l'été et des vacances (bouton « Augmenter » ou dates précises).` : ""; })()}</p></div>`;
    }
    // Calendrier des prix
    const title = new Intl.DateTimeFormat("fr-FR", { month: "long", year: "numeric" }).format(pxMonth);
    const first = new Date(pxMonth);
    const start = new Date(first);
    start.setDate(1 - ((first.getDay() + 6) % 7));
    let grid = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"].map((d) => `<div class="admin-cal__dow">${d}</div>`).join("");
    for (let i = 0; i < 42; i++) {
      const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
      if (i === 35 && d.getMonth() !== pxMonth.getMonth()) break;
      const iso = isoOf(d);
      const past = iso < todayIso;
      const v = pxGuest(pxNight(iso));
      const evs = pxEvents(iso);
      const imp = Math.max(0, ...evs.map((e) => e.impact));
      const rule = pxRule(iso);
      const sel = pxSel && pxSel.du <= iso && iso <= pxSel.au;
      const tip = [`${dShort(iso)} : ${v ? `${v} € la nuit sur ton site` : "prix sur demande"}`, pxAirbnb(iso) ? `Airbnb : ${pxAirbnb(iso)} €` : "", rule ? `Prix fixé : ${rule.nom || ruleTxt(rule)}` : "", ...evs.map((e) => e.nom)].filter(Boolean).join("\n");
      grid += `<button type="button" class="px-day${d.getMonth() !== pxMonth.getMonth() ? " is-other" : ""}${past ? " is-past" : ""}${iso === todayIso ? " is-today" : ""}${rule ? " is-fixed" : ""}${sel ? " is-sel" : ""}${imp ? ` is-hot${imp}` : ""}" data-pxday="${iso}"${past ? " disabled" : ""} title="${esc(tip)}">
        <span class="admin-cal__num">${d.getDate()}</span><strong>${v ? v.toLocaleString("fr-FR") : "—"}</strong>${evs.length ? `<i class="px-evdot">${esc(evs.sort((a, b) => b.impact - a.impact || nNights(a.du, a.au) - nNights(b.du, b.au))[0].nom)}</i>` : ""}</button>`;
    }
    html += `<div class="px-cal">
      <div class="admin-cal__nav"><button type="button" class="admin-cal__arrow" data-pxm="-1" aria-label="Mois précédent">‹</button><h3 class="h3">${title.charAt(0).toUpperCase() + title.slice(1)}</h3><button type="button" class="admin-cal__arrow" data-pxm="1" aria-label="Mois suivant">›</button></div>
      <p class="small">Prix d'une nuit payé sur ton site (remise déduite, hors ménage et taxe). Touche une date puis une autre pour changer le prix de ces nuits.</p>
      <div class="admin-cal__grid px-grid">${grid}</div>
      <ul class="admin-cal__legend"><li><i class="px-lg px-lg--hot1"></i>Un peu plus de demande</li><li><i class="px-lg px-lg--hot2"></i>Forte demande</li><li><i class="px-lg px-lg--hot3"></i>Très forte demande</li><li><i class="px-lg px-lg--fixed"></i>Prix fixé par toi</li></ul>
    </div>`;
    // Sélection : changer le prix de ces nuits
    if (pxSel) {
      const evs = (window.EVENEMENTS || []).filter((e) => e.maisons.includes(pxHouse) && e.du <= pxSel.au && pxSel.du <= e.au);
      html += `<form class="px-selform" id="px-selform">
        <p><strong>${pxSel.du === pxSel.au ? `Nuit du ${dShort(pxSel.du)}` : `Du ${dShort(pxSel.du)} au ${dShort(pxSel.au)} (${plural(nNights(pxSel.du, pxSel.au), "nuit")}, départ le ${dShort(isoAdd(pxSel.au, 1))})`}</strong>
        <span class="small">${pxSel.picking ? "Touche la dernière nuit pour choisir plusieurs dates. " : ""}Aujourd'hui : ${range(pxSel.du, pxSel.au)} la nuit sur ton site${evs.length ? ` · ${evs.map((e) => esc(e.nom)).join(", ")}` : ""}.</span></p>
        <div class="px-selform__row">
          <div class="field"><label for="px-s-type">Changer</label><select id="px-s-type"><option value="pct">de x %</option><option value="nuit">pour un prix fixe</option></select></div>
          <div class="field"><label for="px-s-val">Valeur</label><div class="px-unit"><input id="px-s-val" type="number" step="1" inputmode="numeric" required placeholder="ex. 20"><span id="px-s-unit">%</span></div></div>
          <div class="field"><label for="px-s-nom">Nom (facultatif)</label><input id="px-s-nom" maxlength="80" value="${esc(evs[0] ? evs[0].nom : "")}"></div>
          <button class="btn btn--accent" type="submit">Appliquer</button>
          <button class="link" type="button" id="px-s-cancel">Annuler</button>
        </div>
      </form>`;
    }
    // Prix fixés pour des dates précises
    const rules = H.dates.map((r, i) => ({ r, i })).filter(({ r }) => r.au >= todayIso);
    html += `<div class="px-block"><h3 class="h3">Prix pour des dates précises</h3>${rules.length ? `<ul class="admin-codes">${rules.map(({ r, i }) => `<li><strong>${esc(r.nom || "Prix fixé")}</strong><span>${dShort(r.du)} → ${dShort(isoAdd(r.au, 1))} (${plural(nNights(r.du, r.au), "nuit")}) · ${ruleTxt(r)} · ${range(r.du, r.au)} la nuit sur ton site</span><button type="button" class="link" data-pxdel="${i}">Retirer</button></li>`).join("")}</ul>` : `<p class="small">Aucun pour l'instant : choisis des dates dans le calendrier, ou applique une hausse sur un événement ci-dessous.</p>`}</div>`;
    // Événements
    const evs = (window.EVENEMENTS || []).map((e, i) => ({ e, i })).filter(({ e }) => e.maisons.includes(pxHouse) && e.au >= todayIso);
    html += `<div class="px-block"><h3 class="h3">Moments où il y a du monde</h3><p class="small">Vacances, ponts et grands événements ${pxHouse === "lacanau" ? "à Lacanau et dans le Médoc" : "à Bordeaux"}. La hausse proposée s'ajoute au prix habituel de ces nuits.</p>
      <ul class="px-events">${evs.map(({ e, i }) => {
        const done = H.dates.find((r) => r.du === e.du && r.au === e.au);
        return `<li class="px-ev"><div class="px-ev__head">${dots(e.impact)}<strong>${esc(e.nom)}</strong>${e.confirme ? "" : `<span class="tag">dates à confirmer</span>`}</div>
          <span class="small">${dShort(e.du)} → ${dShort(isoAdd(e.au, 1))} · ${plural(nNights(e.du, e.au), "nuit")} · aujourd'hui ${range(e.du, e.au)}${e.info ? ` · ${esc(e.info)}` : ""}</span>
          ${done ? `<span class="px-ev__done">Appliqué : ${ruleTxt(done)}</span>` : `<button type="button" class="btn btn--ghost" data-pxev="${i}">Augmenter de ${e.hausse} %</button>`}</li>`;
      }).join("")}</ul></div>`;
    html += `<div class="px-save${dirty ? " is-dirty" : ""}"><span>${dirty ? "Modifications pas encore en ligne" : "Ces prix sont en ligne"}</span><button type="button" class="btn btn--accent" id="px-save"${dirty ? "" : " disabled"}>Enregistrer et mettre en ligne</button><p class="booking__msg" id="px-msg" aria-live="polite"></p></div>`;
    $("#px-body").innerHTML = html;
  };
  const loadPrix = () => api("tarifs").then((d) => {
    const t = d.tarifs || {};
    px = { remise: t.remise != null ? t.remise : SP_REMISE({}), lacanau: Object.assign(pxDef(), t.lacanau), bordeaux: Object.assign(pxDef(), t.bordeaux) };
    if (t.maj) px.maj = t.maj;
    pxSaved = JSON.stringify(px);
    renderPrix();
  }).catch((e) => { if (e.message !== "auth") $("#px-body").innerHTML = `<p class="booking__msg is-error">${esc(e.message)}</p>`; });
  $$("[data-px]").forEach((b) => b.addEventListener("click", () => {
    pxHouse = b.dataset.px;
    pxSel = null;
    $$("[data-px]").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
    renderPrix();
  }));
  const pxVal = (v) => (v === "" ? null : Number(v));
  $("#px-body").addEventListener("change", (e) => {
    const H = px[pxHouse];
    const t = e.target;
    if (t.id === "px-auto") {
      H.mode = t.checked ? "auto" : "manuel";
      if (H.mode === "manuel" && !H.nuit) {
        // On part des prix Airbnb des prochaines semaines
        const soon = Array.from({ length: 30 }, (x, i) => pxAirbnb(isoAdd(isoOf(now), i + 1))).filter(Boolean);
        if (soon.length) H.nuit = Math.round(Math.min(...soon) / 5) * 5;
        if (H.menage == null && (window.TARIFS_AIRBNB || {})[pxHouse]) H.menage = TARIFS_AIRBNB[pxHouse].fixe || null;
      }
    } else if (t.id === "px-rem") px.remise = Math.max(0, Math.min(50, Number(t.value) || 0));
    else if (t.id === "px-cau") H.caution = Math.max(0, Math.min(5000, Math.round(Number(t.value) || 0)));
    else if (t.id === "px-adj") H.ajust = Math.max(-50, Math.min(100, Math.round(Number(t.value) || 0)));
    else if (t.id === "px-nuit") H.nuit = pxVal(t.value);
    else if (t.id === "px-we") H.weekend = pxVal(t.value);
    else if (t.id === "px-men") H.menage = pxVal(t.value);
    else if (t.id === "px-s-type") { $("#px-s-unit").textContent = t.value === "nuit" ? "€" : "%"; $("#px-s-val").placeholder = t.value === "nuit" ? "ex. 550" : "ex. 20"; return; } else return;
    renderPrix();
  });
  $("#px-body").addEventListener("click", (e) => {
    const H = px[pxHouse];
    const t = e.target.closest("button");
    if (!t) return;
    if (t.dataset.adj != null) { H.ajust = Number(t.dataset.adj); renderPrix(); return; }
    if (t.dataset.pxm) { pxMonth = new Date(pxMonth.getFullYear(), pxMonth.getMonth() + Number(t.dataset.pxm), 1); renderPrix(); return; }
    if (t.dataset.pxday) {
      const iso = t.dataset.pxday;
      if (pxSel && pxSel.picking) pxSel = { du: iso < pxSel.du ? iso : pxSel.du, au: iso < pxSel.du ? pxSel.du : iso, picking: false };
      else pxSel = { du: iso, au: iso, picking: true };
      renderPrix();
      const f = $("#px-selform");
      if (f && !pxSel.picking) f.scrollIntoView({ behavior: "smooth", block: "nearest" });
      return;
    }
    if (t.id === "px-s-cancel") { pxSel = null; renderPrix(); return; }
    if (t.dataset.pxdel != null) { H.dates.splice(Number(t.dataset.pxdel), 1); renderPrix(); return; }
    if (t.dataset.pxev != null) {
      const ev = EVENEMENTS[Number(t.dataset.pxev)];
      H.dates.push({ du: ev.du, au: ev.au, pct: ev.hausse, nom: ev.nom });
      H.dates.sort((a, b) => (a.du < b.du ? -1 : 1));
      renderPrix();
      return;
    }
    if (t.id === "px-save") {
      const m = $("#px-msg");
      t.disabled = true;
      m.classList.remove("is-error");
      m.textContent = "Enregistrement…";
      api("tarifs", "POST", px).then((d) => {
        const s = d.tarifs;
        px = { remise: s.remise, lacanau: Object.assign(pxDef(), s.lacanau), bordeaux: Object.assign(pxDef(), s.bordeaux), maj: s.maj };
        pxSaved = JSON.stringify(px);
        renderPrix();
        $("#px-msg").textContent = "C'est en ligne : les voyageurs voient les nouveaux prix (moins d'une minute).";
      }).catch((err) => { if (err.message !== "auth") { m.textContent = err.message; m.classList.add("is-error"); t.disabled = false; } });
    }
  });
  $("#px-body").addEventListener("submit", (e) => {
    if (e.target.id !== "px-selform") return;
    e.preventDefault();
    const type = $("#px-s-type").value;
    const val = Math.round(Number($("#px-s-val").value));
    if (!val) return;
    const H = px[pxHouse];
    // Les dates choisies remplacent les prix déjà fixés sur ces nuits
    const out = [];
    H.dates.forEach((r) => {
      if (r.au < pxSel.du || r.du > pxSel.au) { out.push(r); return; }
      if (r.du < pxSel.du) out.push(Object.assign({}, r, { au: isoAdd(pxSel.du, -1) }));
      if (r.au > pxSel.au) out.push(Object.assign({}, r, { du: isoAdd(pxSel.au, 1) }));
    });
    out.push(Object.assign({ du: pxSel.du, au: pxSel.au, nom: $("#px-s-nom").value.trim() }, type === "nuit" ? { nuit: val } : { pct: val }));
    H.dates = out.sort((a, b) => (a.du < b.du ? -1 : 1));
    pxSel = null;
    renderPrix();
  });
  window.addEventListener("beforeunload", (e) => { if (px && JSON.stringify(px) !== pxSaved) { e.preventDefault(); e.returnValue = ""; } });

  /* E-mails aux voyageurs : adresse et infos d'arrivée (envoyées 7 jours avant), lien pour les avis */
  let infos = null;
  const renderInfos = (mails) => {
    const I = infos;
    const house = (k) => {
      const x = I[k] || {};
      return `<fieldset class="inf-house"><legend class="h3">${esc(HOUSES[k].name)}</legend>
        <div class="field"><label for="inf-${k}-adr">Adresse exacte</label><input id="inf-${k}-adr" data-inf="${k}.adresse" maxlength="200" value="${esc(x.adresse || "")}" placeholder="${k === "lacanau" ? "ex. 12 allée des Pins, 33680 Lacanau" : "ex. 8 rue Notre-Dame, 33000 Bordeaux"}"></div>
        <div class="field"><label for="inf-${k}-fr">Infos d'arrivée (français)</label><textarea id="inf-${k}-fr" data-inf="${k}.fr" maxlength="4000" placeholder="Boîte à clés, code, parking, wifi, poubelles, numéro à appeler…">${esc(x.fr || "")}</textarea></div>
        <details class="inf-more"${x.en || x.es ? " open" : ""}><summary>Versions anglaise et espagnole (facultatif)</summary>
          <div class="field"><label for="inf-${k}-en">Anglais</label><textarea id="inf-${k}-en" data-inf="${k}.en" maxlength="4000">${esc(x.en || "")}</textarea></div>
          <div class="field"><label for="inf-${k}-es">Espagnol</label><textarea id="inf-${k}-es" data-inf="${k}.es" maxlength="4000">${esc(x.es || "")}</textarea></div>
          <p class="small">Sans traduction, les voyageurs étrangers reçoivent le texte anglais (ou français s'il n'y en a pas).</p>
        </details></fieldset>`;
    };
    $("#infos-body").innerHTML = `
      <p class="inf-status ${mails ? "is-on" : "is-off"}">${mails ? "E-mails automatiques activés." : "E-mails automatiques pas encore activés : ajoute la clé RESEND_API_KEY dans Cloudflare (voir le mode d'emploi). En attendant, rien n'est envoyé automatiquement : utilise les boutons « Écrire » des réservations."}</p>
      <p class="small">Envoyés tout seuls, dans la langue du voyageur : demande reçue, confirmation (quand tu acceptes), refus ou annulation, <strong>infos d'arrivée 7 jours avant</strong> (avec l'adresse et le texte ci-dessous), lien de caution si sa banque le demande, et <strong>demande d'avis</strong> le lendemain du départ. Les réponses arrivent sur contact.sablepierre@gmail.com.</p>
      <div class="inf-grid">${house("lacanau")}${house("bordeaux")}</div>
      <div class="field"><label for="inf-avis">Lien pour laisser un avis (facultatif)</label><input id="inf-avis" data-inf="avisUrl" maxlength="300" value="${esc(I.avisUrl || "")}" placeholder="ex. lien de ta fiche Google · sans lien, le voyageur répond par e-mail"></div>
      <div class="inf-actions"><button type="button" class="btn btn--accent" id="inf-save">Enregistrer</button><button type="button" class="btn btn--ghost" id="inf-test"${mails ? "" : " disabled"}>M'envoyer un e-mail de test</button></div>
      <p class="booking__msg" id="inf-msg" aria-live="polite"></p>`;
  };
  const loadInfos = () => api("infos").then((d) => { infos = d.infos || {}; renderInfos(d.mails); }).catch((e) => { if (e.message !== "auth") $("#infos-body").innerHTML = `<p class="booking__msg is-error">${esc(e.message)}</p>`; });
  $("#infos-body").addEventListener("input", (e) => {
    const f = e.target.dataset.inf;
    if (!f) return;
    const [k, field] = f.split(".");
    if (field) { infos[k] = infos[k] || {}; infos[k][field] = e.target.value; } else infos[k] = e.target.value;
  });
  $("#infos-body").addEventListener("click", async (e) => {
    const m = $("#inf-msg");
    const say = (t, err) => { m.textContent = t; m.classList.toggle("is-error", !!err); };
    if (e.target.id === "inf-save") {
      say("Enregistrement…");
      try { const d = await api("infos", "POST", infos); infos = d.infos; say("Enregistré. Ces informations ne sont jamais affichées sur le site : elles partent seulement par e-mail, 7 jours avant l'arrivée."); } catch (err) { if (err.message !== "auth") say(err.message, true); }
    } else if (e.target.id === "inf-test") {
      say("Envoi…");
      try { const d = await api("test-mail", "POST"); say(d.message); } catch (err) { if (err.message !== "auth") say(err.message, true); }
    }
  });

  const refresh = () => { loadCodes(); loadStats(); if (!px || JSON.stringify(px) === pxSaved) loadPrix(); if (!infos) loadInfos(); return api("reservations").then((d) => { data = d; render(); }).catch((e) => { if (e.message !== "auth") $("#list").innerHTML = `<p class="booking__msg is-error">${esc(e.message)}</p>`; }); };
  /* Statistiques : visites (anonymes, sans cookie), sources, clics et réservations */
  let statDays = 30;
  const nf = new Intl.NumberFormat("fr-FR");
  const pct = (a, b) => (b ? `${(Math.round((a / b) * 1000) / 10).toLocaleString("fr-FR")} %` : "—");
  const regionName = (() => { try { const dn = new Intl.DisplayNames(["fr"], { type: "region" }); return (c) => (c ? dn.of(c) : "Inconnu"); } catch (e) { return (c) => c || "Inconnu"; } })();
  const SRC = [[/google\./, "Google"], [/bing\./, "Bing"], [/duckduckgo/, "DuckDuckGo"], [/ecosia/, "Ecosia"], [/qwant/, "Qwant"], [/yahoo/, "Yahoo"], [/instagram/, "Instagram"], [/facebook|^fb\b/, "Facebook"], [/airbnb/, "Airbnb"], [/whatsapp|wa\.me/, "WhatsApp"], [/^t\.co$|twitter|x\.com/, "X (Twitter)"], [/linkedin|lnkd/, "LinkedIn"], [/pinterest/, "Pinterest"], [/tiktok/, "TikTok"], [/chatgpt|openai/, "ChatGPT"], [/claude\.ai|perplexity/, "Assistants IA"]];
  const srcName = (h) => { if (!h) return "Accès direct"; const m = SRC.find(([r]) => r.test(h)); return m ? m[1] : h; };
  const PAGE_NAMES = { "/": "Accueil", "/lacanau": "La Maison du Lac (Lacanau)", "/bordeaux": "La Maison de Pierre (Bordeaux)", "/conditions": "Conditions", "/mentions-legales": "Mentions légales", "/vacances-famille-lacanau": "Guide : vacances en famille à Lacanau", "/vacances-famille-bordeaux": "Guide : Bordeaux en famille", "/guide-plages-lacanau": "Guide : les plages de Lacanau", "/guide-semaine-gironde-famille": "Guide : une semaine en Gironde" };
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
        ${ranked("Pages les plus vues", (d.pages || []).map((x) => { const m = /^\/(en|es)(\/.*)$/.exec(x.k); const n = PAGE_NAMES[m ? m[2] : x.k] || x.k; return { k: m ? `${n} (${m[1] === "en" ? "anglais" : "espagnol"})` : n, v: x.v }; }), visits)}
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
    if (c) { try { await navigator.clipboard.writeText(c.dataset.copy); c.textContent = "Copié"; } catch (err) { const i = c.previousElementSibling; if (i && i.select) i.select(); } return; }
    const cb = e.target.closest("[data-cau]");
    if (cb) {
      const r = data.reservations.find((x) => x.id === cb.dataset.id);
      const body = { action: cb.dataset.cau };
      if (body.action === "encaisser") {
        const v = window.prompt(`Montant à encaisser sur la caution (jusqu'à ${r.caution.montant} €). Le reste sera libéré.`, String(r.caution.montant));
        if (v == null) return;
        body.montant = Number(String(v).replace(",", ".").replace(/[^\d.]/g, ""));
        if (!window.confirm(`Encaisser ${body.montant} € sur la carte de ${r.nom} ?`)) return;
      } else if (!window.confirm("Libérer la caution maintenant ?")) return;
      const m = $(`[data-msg="${cb.dataset.id}"]`);
      try {
        const d = await api(`reservations/${cb.dataset.id}/caution`, "POST", body);
        data.reservations[data.reservations.findIndex((x) => x.id === d.reservation.id)] = d.reservation;
        render();
      } catch (err) { if (err.message !== "auth" && m) { m.textContent = err.message; m.classList.add("is-error"); } }
      return;
    }
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
      const m2 = $(`[data-msg="${b.dataset.id}"]`);
      if (d.mail === "envoyé") { if (m2) m2.textContent = "C'est fait : le voyageur a reçu un e-mail automatique."; }
      else if (act === "accepter") window.location.href = mailto(d.reservation, "ok");
    } catch (err) {
      if (err.message !== "auth") { msg.textContent = err.message; msg.classList.add("is-error"); }
    }
  });
  if (key) enter();
})();
