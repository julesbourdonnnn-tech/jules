/*
 * Worker Cloudflare du site Sable & Pierre : sert les fichiers du site et le
 * système de réservation directe.
 *
 * Voyageurs
 *  GET  /api/disponibilites/:maison  nuits prises (réservations directes + iCal Airbnb si réglé)
 *  POST /api/reservation             crée une réservation : vérifie les dates, recalcule le
 *                                    prix et renvoie l'adresse du paiement Stripe (empreinte
 *                                    bancaire : rien n'est débité avant ta validation)
 *  GET  /api/reservation/:id?t=…     état d'une réservation (page reservation.html)
 *
 * Propriétaire (mot de passe = secret ADMIN_KEY, page admin.html)
 *  GET  /api/admin/reservations              liste
 *  POST /api/admin/reservations/:id/:action  accepter (débite la carte), refuser, annuler
 *  GET  /api/ical/:maison.ics?k=…            calendrier des réservations directes, à importer
 *                                            dans Airbnb pour bloquer ces dates là-bas
 *
 * Réglages Cloudflare (Workers → lacanau → Settings → Variables and secrets) :
 *  STRIPE_SECRET_KEY  clé secrète Stripe (sk_live_… ou sk_test_… pour essayer)
 *  ADMIN_KEY          ton mot de passe pour admin.html
 *  NOTIFY_URL         (facultatif) alerte sur téléphone : https://ntfy.sh/ton-sujet
 *  ICAL_LACANAU / ICAL_BORDEAUX (facultatif) liens iCal d'export Airbnb
 * Stockage : KV « RESERVATIONS » (wrangler.jsonc).
 */
import "./shim.js";
import "../js/data.js";
import "../js/tarifs.js";
import "../js/tarifs-airbnb.js";
import "../js/prix.js";

const H = globalThis.HOUSES;
const PRICE = globalThis.SP_PRICE;
const EUR = globalThis.SP_EUR;
const KEYS = ["lacanau", "bordeaux"];
const ICAL = { lacanau: "ICAL_LACANAU", bordeaux: "ICAL_BORDEAUX" };
const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const HOLD_MIN = 35; // une réservation en cours de paiement bloque les dates 35 minutes
const DAY = 86400000;
const clean = (v, max) => String(v ?? "").replace(/[\u0000-\u0008\u000b-\u001f<>]/g, "").trim().slice(0, max);
const json = (body, status = 200, extra = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...extra } });
const store = (env) => env.RESERVATIONS || env.DEMANDES || null;
const toDay = (s) => { const [y, m, d] = s.split("-").map(Number); return Date.UTC(y, m - 1, d); };
const isoDay = (t) => new Date(t).toISOString().slice(0, 10);
const todayISO = () => new Date(Date.now() + 2 * 3600000).toISOString().slice(0, 10); // heure de Paris (approx.)
const rand = (n) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => b.toString(16).padStart(2, "0")).join("");
const fmtDate = (s) => new Intl.DateTimeFormat("fr-FR", { weekday: "short", day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(toDay(s)));

/* ===================== Calendrier iCal Airbnb ===================== */
function parseIcal(text) {
  const lines = text.replace(/\r?\n[ \t]/g, "").split(/\r?\n/);
  const out = [];
  let start = null;
  let end = null;
  const day = (v) => { const m = /(\d{4})(\d{2})(\d{2})/.exec(v || ""); return m ? `${m[1]}-${m[2]}-${m[3]}` : null; };
  for (const line of lines) {
    if (line.startsWith("BEGIN:VEVENT")) { start = null; end = null; }
    else if (line.startsWith("DTSTART")) start = day(line.split(":").pop());
    else if (line.startsWith("DTEND")) end = day(line.split(":").pop());
    else if (line.startsWith("END:VEVENT") && start) {
      if (!end || end <= start) end = isoDay(toDay(start) + DAY);
      out.push([start, end]);
    }
  }
  const today = todayISO();
  return out.filter(([, e]) => e > today).sort((a, b) => (a[0] < b[0] ? -1 : 1));
}
async function icalBooked(house, env) {
  const url = env[ICAL[house]];
  if (!url) return [];
  try {
    const r = await fetch(url, { headers: { "User-Agent": "Sable-et-Pierre/1.0 (+calendrier)" }, cf: { cacheTtl: 900, cacheEverything: true } });
    return r.ok ? parseIcal(await r.text()) : [];
  } catch (e) { return []; }
}

/* ===================== Disponibilités Airbnb (js/disponibilites.js) ===================== */
async function airbnbAvailability(env, origin) {
  try {
    const r = await env.ASSETS.fetch(new Request(`${origin}/js/disponibilites.js`));
    const t = await r.text();
    const m = /Object\.assign\((\{[\s\S]*\}),\s*\{\s*updated/.exec(t);
    return m ? JSON.parse(m[1]) : {};
  } catch (e) { return {}; }
}

/* ===================== Réservations (stockage) ===================== */
async function allBookings(env) {
  const kv = store(env);
  if (!kv) return [];
  const out = [];
  let cursor;
  do {
    const page = await kv.list({ prefix: "resa:", cursor });
    const vals = await Promise.all(page.keys.map((k) => kv.get(k.name)));
    vals.forEach((v) => { if (v) out.push(JSON.parse(v)); });
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  return out.sort((a, b) => (a.cree < b.cree ? 1 : -1));
}
const save = (env, b) => { b.maj = new Date().toISOString(); return store(env).put(`resa:${b.id}`, JSON.stringify(b)); };
const load = async (env, id) => { const v = await store(env).get(`resa:${id}`); return v ? JSON.parse(v) : null; };
// Une réservation bloque les dates si elle est confirmée, en attente de validation,
// ou en cours de paiement depuis moins de HOLD_MIN minutes.
const blocking = (b) => b.statut === "confirmee" || b.statut === "a_valider" || (b.statut === "paiement" && Date.now() - Date.parse(b.cree) < HOLD_MIN * 60000);

async function bookedRanges(house, env, skipId) {
  const direct = (await allBookings(env)).filter((b) => b.maison === house && b.id !== skipId && blocking(b)).map((b) => [b.arrivee, b.depart]);
  return direct.concat(await icalBooked(house, env));
}

// Vérifie qu'un séjour est possible : calendrier Airbnb, réservations directes, durées
async function checkStay(house, a, b, env, origin, skipId) {
  if (a < todayISO()) return "passe";
  const n = Math.round((toDay(b) - toDay(a)) / DAY);
  if (n < 1) return "dates";
  const A = (await airbnbAvailability(env, origin))[house];
  if (A) {
    const i0 = Math.round((toDay(a) - toDay(A.from)) / DAY);
    const flag = (i) => (i >= 0 && i < A.flags.length ? Number(A.flags[i]) : 7);
    if (!(flag(i0) & 2) || !(flag(i0) & 1)) return "pris";
    for (let i = i0; i < i0 + n; i++) if (!(flag(i) & 1)) return "pris";
    if (!(flag(i0 + n) & 4)) return "depart";
    const min = i0 >= 0 && i0 < A.min.length ? A.min[i0] : 1;
    const max = i0 >= 0 && i0 < A.max.length ? A.max[i0] : 0;
    if (n < min) return "court";
    if (max && n > max) return "long";
  }
  const ranges = await bookedRanges(house, env, skipId);
  if (ranges.some(([s, e]) => a < e && b > s)) return "pris";
  return null;
}

/* ===================== Stripe ===================== */
function form(obj, prefix = "", out = []) {
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    const key = prefix ? `${prefix}[${k}]` : k;
    if (typeof v === "object") form(v, key, out);
    else out.push(`${encodeURIComponent(key)}=${encodeURIComponent(v)}`);
  }
  return out.join("&");
}
async function stripe(env, method, path, params) {
  const r = await fetch(`https://api.stripe.com/v1/${path}`, {
    method,
    headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`, "Content-Type": "application/x-www-form-urlencoded", "Stripe-Version": "2024-06-20" },
    body: params ? form(params) : undefined,
  });
  const data = await r.json();
  if (!r.ok) throw new Error((data.error && data.error.message) || `Stripe ${r.status}`);
  return data;
}
// Met à jour une réservation d'après Stripe (paiement autorisé, expiré…)
async function syncStripe(env, b) {
  if (!env.STRIPE_SECRET_KEY || !b.stripeSession || b.statut !== "paiement") return b;
  try {
    const s = await stripe(env, "GET", `checkout/sessions/${b.stripeSession}?expand[]=payment_intent`);
    const pi = s.payment_intent;
    if (s.status === "complete" && pi && (pi.status === "requires_capture" || pi.status === "succeeded")) {
      b.statut = "a_valider";
      b.paymentIntent = pi.id;
      b.paiement = pi.status === "succeeded" ? "débité" : "autorisé";
      await save(env, b);
      b._nouveau = true;
    } else if (s.status === "expired") {
      b.statut = "expiree";
      await save(env, b);
    }
  } catch (e) { /* on réessaiera */ }
  return b;
}

/* ===================== Alertes ===================== */
function notify(env, ctx, title, text) {
  if (!env.NOTIFY_URL) return;
  const isDiscord = env.NOTIFY_URL.includes("discord.com");
  const isSlack = env.NOTIFY_URL.includes("hooks.slack.com");
  const body = isDiscord ? JSON.stringify({ content: `**${title}**\n${text}` }) : isSlack ? JSON.stringify({ text: `*${title}*\n${text}` }) : text;
  const headers = isDiscord || isSlack ? { "Content-Type": "application/json" } : { Title: title, Tags: "house", Priority: "high" };
  ctx.waitUntil(fetch(env.NOTIFY_URL, { method: "POST", headers, body }).catch(() => {}));
}
const summary = (b) => `${H[b.maison].name} · du ${fmtDate(b.arrivee)} au ${fmtDate(b.depart)} (${b.nuits} nuits) · ${b.adultes} adulte(s)${b.enfants ? `, ${b.enfants} enfant(s)` : ""}${b.bebes ? `, ${b.bebes} bébé(s)` : ""}\n${b.nom} · ${b.telephone || "pas de tél."} · ${b.email}${b.total ? `\nMontant : ${EUR(b.cents)}` : ""}${b.message ? `\n« ${b.message} »` : ""}`;

/* ===================== Voyageurs ===================== */
const ERR = {
  passe: "La date d'arrivée est déjà passée.",
  dates: "Les dates ne sont pas valides.",
  pris: "Ces dates ne sont plus disponibles. Choisissez d'autres dates.",
  depart: "Le départ n'est pas possible ce jour-là. Choisissez un autre jour.",
  court: "Le séjour est trop court pour ces dates.",
  long: "Le séjour est trop long pour ces dates.",
};
async function createBooking(request, env, ctx, origin) {
  const kv = store(env);
  if (!kv) return json({ ok: false, error: "storage_not_configured" }, 503);
  if (Number(request.headers.get("Content-Length")) > 8192) return json({ ok: false, error: "too_large" }, 413);
  let d;
  try { d = await request.json(); } catch { return json({ ok: false, error: "bad_request" }, 400); }
  if (d["bot-field"]) return json({ ok: false, error: "invalid" }, 400);
  const house = clean(d.maison, 20);
  const h = H[house];
  const b = {
    maison: house, arrivee: clean(d.arrivee, 10), depart: clean(d.depart, 10),
    adultes: Math.max(1, parseInt(d.adultes, 10) || 1), enfants: Math.max(0, parseInt(d.enfants, 10) || 0), bebes: Math.max(0, parseInt(d.bebes, 10) || 0),
    nom: clean(d.nom, 80), email: clean(d.email, 254).toLowerCase(), telephone: clean(d.telephone, 30), message: clean(d.message, 2000),
  };
  if (!h || !DATE.test(b.arrivee) || !DATE.test(b.depart) || b.depart <= b.arrivee || !b.nom || !EMAIL.test(b.email)) return json({ ok: false, error: "invalid", message: "Merci de vérifier vos dates, votre nom et votre e-mail." }, 400);
  if (!d.conditions) return json({ ok: false, error: "conditions", message: "Merci d'accepter les conditions de réservation." }, 400);
  if (b.adultes + b.enfants > h.guests) return json({ ok: false, error: "capacite", message: `Cette maison accueille jusqu'à ${h.guests} voyageurs.` }, 400);
  if (house === "bordeaux" && b.bebes > 0) return json({ ok: false, error: "bebes", message: "La Maison de Pierre ne convient pas aux bébés de moins de 2 ans." }, 400);
  const problem = await checkStay(house, b.arrivee, b.depart, env, origin);
  if (problem) return json({ ok: false, error: problem, message: ERR[problem] }, 409);

  const p = PRICE(house, b.arrivee, b.depart, b.adultes);
  b.nuits = Math.round((toDay(b.depart) - toDay(b.arrivee)) / DAY);
  b.id = `SP${Date.now().toString(36).toUpperCase().slice(-5)}${rand(2).toUpperCase()}`;
  b.token = rand(12);
  b.cree = new Date().toISOString();
  b.pays = (request.cf && request.cf.country) || "";
  if (p.ready) { b.cents = p.cents; b.total = p.total; b.lignes = p.lines; }

  // Paiement en ligne possible : tarifs renseignés et clé Stripe en place
  if (p.ready && env.STRIPE_SECRET_KEY) {
    b.statut = "paiement";
    const back = `${origin}/reservation.html?id=${b.id}&t=${b.token}`;
    try {
      const s = await stripe(env, "POST", "checkout/sessions", {
        mode: "payment",
        locale: "fr",
        customer_email: b.email,
        client_reference_id: b.id,
        expires_at: Math.floor(Date.now() / 1000) + 31 * 60,
        success_url: back,
        cancel_url: `${origin}/${h.page}?arrivee=${b.arrivee}&depart=${b.depart}&voyageurs=${b.adultes + b.enfants}&annule=1#reserver`,
        line_items: { 0: { quantity: 1, price_data: { currency: "eur", unit_amount: b.cents, product_data: { name: `${h.name} — ${b.nuits} nuit${b.nuits > 1 ? "s" : ""}`, description: `Du ${fmtDate(b.arrivee)} au ${fmtDate(b.depart)} · ${b.adultes + b.enfants} voyageur(s) · réservation ${b.id}` } } } },
        // Empreinte bancaire : le montant n'est débité que lorsque tu acceptes la réservation
        payment_intent_data: { capture_method: "manual", description: `Réservation ${b.id} — ${h.name}`, receipt_email: b.email, metadata: { reservation: b.id } },
        metadata: { reservation: b.id, maison: house },
      });
      b.stripeSession = s.id;
      await save(env, b);
      return json({ ok: true, mode: "paiement", url: s.url, id: b.id });
    } catch (e) {
      return json({ ok: false, error: "stripe", message: "Le paiement en ligne est momentanément indisponible. Réessayez dans un instant." }, 502);
    }
  }
  // Sinon : demande de réservation, sans paiement (le prix est confirmé par e-mail)
  b.statut = "a_valider";
  b.paiement = "à organiser";
  await save(env, b);
  notify(env, ctx, "Nouvelle demande de réservation", summary(b));
  return json({ ok: true, mode: "demande", id: b.id, url: `/reservation.html?id=${b.id}&t=${b.token}` });
}

async function bookingStatus(env, ctx, id, token) {
  if (!store(env)) return json({ ok: false }, 503);
  let b = await load(env, id);
  if (!b || b.token !== token) return json({ ok: false, error: "introuvable" }, 404);
  b = await syncStripe(env, b);
  if (b._nouveau) notify(env, ctx, "Réservation à valider (paiement autorisé)", summary(b));
  const h = H[b.maison];
  return json({ ok: true, reservation: {
    id: b.id, maison: b.maison, nomMaison: h.name, page: h.page, statut: b.statut, paiement: b.paiement || "",
    arrivee: b.arrivee, depart: b.depart, nuits: b.nuits, adultes: b.adultes, enfants: b.enfants, bebes: b.bebes,
    nom: b.nom, email: b.email, cents: b.cents || 0, lignes: b.lignes || [],
  } });
}

/* ===================== Propriétaire ===================== */
function authorized(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const key = auth.replace(/^Bearer\s+/i, "");
  if (!env.ADMIN_KEY || key.length !== env.ADMIN_KEY.length) return false;
  let diff = 0;
  for (let i = 0; i < key.length; i++) diff |= key.charCodeAt(i) ^ env.ADMIN_KEY.charCodeAt(i);
  return diff === 0;
}
async function icalToken(env, house) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${env.ADMIN_KEY}:ical:${house}`));
  return Array.from(new Uint8Array(buf), (x) => x.toString(16).padStart(2, "0")).join("").slice(0, 32);
}
async function adminList(env, origin) {
  const list = await allBookings(env);
  for (const b of list) if (b.statut === "paiement") await syncStripe(env, b);
  const feeds = {};
  for (const k of KEYS) feeds[k] = `${origin}/api/ical/${k}.ics?k=${await icalToken(env, k)}`;
  return json({ ok: true, stripe: !!env.STRIPE_SECRET_KEY, notify: !!env.NOTIFY_URL, feeds, reservations: list.map((b) => { const c = Object.assign({}, b); delete c.token; return c; }) });
}
async function adminAction(env, ctx, origin, id, action) {
  const b = await load(env, id);
  if (!b) return json({ ok: false, error: "introuvable" }, 404);
  try {
    if (action === "accepter") {
      if (b.statut !== "a_valider") return json({ ok: false, message: "Cette réservation n'est pas en attente de validation." }, 409);
      const problem = await checkStay(b.maison, b.arrivee, b.depart, env, origin, b.id);
      if (problem === "pris") return json({ ok: false, message: "Attention : ces dates sont désormais prises ailleurs (Airbnb ou autre réservation). Refusez cette demande." }, 409);
      if (b.paymentIntent && env.STRIPE_SECRET_KEY) {
        const pi = await stripe(env, "GET", `payment_intents/${b.paymentIntent}`);
        if (pi.status === "requires_capture") await stripe(env, "POST", `payment_intents/${b.paymentIntent}/capture`, {});
        else if (pi.status !== "succeeded") return json({ ok: false, message: `Le paiement n'est plus valable (état Stripe : ${pi.status}). Contactez le voyageur.` }, 409);
        b.paiement = "débité";
      }
      b.statut = "confirmee";
    } else if (action === "refuser" || action === "annuler") {
      if (b.paymentIntent && env.STRIPE_SECRET_KEY) {
        const pi = await stripe(env, "GET", `payment_intents/${b.paymentIntent}`);
        if (pi.status === "requires_capture") { await stripe(env, "POST", `payment_intents/${b.paymentIntent}/cancel`, {}); b.paiement = "empreinte libérée"; }
        else if (pi.status === "succeeded") b.paiement = "débité — rembourser depuis Stripe si besoin";
      }
      b.statut = action === "refuser" ? "refusee" : "annulee";
    } else return json({ ok: false, error: "action" }, 400);
  } catch (e) {
    return json({ ok: false, message: `Stripe : ${e.message}` }, 502);
  }
  await save(env, b);
  return json({ ok: true, reservation: b });
}
async function icalFeed(env, house, key) {
  if (!env.ADMIN_KEY || key !== (await icalToken(env, house))) return new Response("Not found", { status: 404 });
  const list = (await allBookings(env)).filter((b) => b.maison === house && (b.statut === "confirmee" || b.statut === "a_valider"));
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d+/, "");
  const ev = list.map((b) => [
    "BEGIN:VEVENT", `UID:${b.id}@sable-et-pierre`, `DTSTAMP:${stamp}`,
    `DTSTART;VALUE=DATE:${b.arrivee.replace(/-/g, "")}`, `DTEND;VALUE=DATE:${b.depart.replace(/-/g, "")}`,
    `SUMMARY:Réservation directe ${b.id}`, "END:VEVENT",
  ].join("\r\n"));
  const body = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Sable & Pierre//Reservations//FR", "CALSCALE:GREGORIAN", ...ev, "END:VCALENDAR"].join("\r\n");
  return new Response(body, { headers: { "Content-Type": "text/calendar; charset=utf-8", "Cache-Control": "no-store" } });
}

/* ===================== Ancienne demande simple (sans réservation) ===================== */
async function legacyRequest(request, env, ctx) {
  const kv = store(env);
  if (!kv) return json({ ok: false, error: "storage_not_configured" }, 503);
  let data;
  try { data = await request.json(); } catch { return json({ ok: false, error: "bad_request" }, 400); }
  if (data["bot-field"]) return json({ ok: true });
  const d = {};
  for (const [k, max] of Object.entries({ maison: 60, arrivee: 10, depart: 10, nom: 80, email: 254, telephone: 30, message: 2000 })) d[k] = clean(data[k], max);
  if (!d.nom || !EMAIL.test(d.email)) return json({ ok: false, error: "invalid" }, 400);
  d.date = new Date().toISOString();
  await kv.put(`demande:${d.date}:${rand(4)}`, JSON.stringify(d));
  notify(env, ctx, "Nouveau message", `${d.maison} ${d.arrivee || ""} → ${d.depart || ""}\n${d.nom} · ${d.email} · ${d.telephone}\n${d.message}`);
  return json({ ok: true });
}

/* ===================== Routage ===================== */
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const p = url.pathname;
    const origin = url.origin;
    let m;
    if ((m = /^\/api\/(?:disponibilites|calendrier)\/(lacanau|bordeaux)$/.exec(p))) {
      return json({ ok: true, booked: await bookedRanges(m[1], env), updated: new Date().toISOString() }, 200, { "Cache-Control": "public, max-age=60" });
    }
    if (p === "/api/reservation" && request.method === "POST") return createBooking(request, env, ctx, origin);
    if ((m = /^\/api\/reservation\/([A-Z0-9]{4,20})$/.exec(p))) return bookingStatus(env, ctx, m[1], url.searchParams.get("t") || "");
    if ((m = /^\/api\/ical\/(lacanau|bordeaux)\.ics$/.exec(p))) return icalFeed(env, m[1], url.searchParams.get("k") || "");
    if (p.startsWith("/api/admin/")) {
      if (!store(env)) return json({ ok: false, message: "Stockage non configuré." }, 503);
      if (!authorized(request, env)) return json({ ok: false, error: "auth", message: env.ADMIN_KEY ? "Mot de passe incorrect." : "Ajoute d'abord le secret ADMIN_KEY dans Cloudflare." }, 401);
      if (p === "/api/admin/reservations" && request.method === "GET") return adminList(env, origin);
      if ((m = /^\/api\/admin\/reservations\/([A-Z0-9]{4,20})\/(accepter|refuser|annuler)$/.exec(p)) && request.method === "POST") return adminAction(env, ctx, origin, m[1], m[2]);
      return json({ ok: false }, 404);
    }
    if (p === "/api/demande" && request.method === "POST") return legacyRequest(request, env, ctx);
    if (p.startsWith("/api/")) return new Response("Not found", { status: 404 });

    const res = await env.ASSETS.fetch(request);
    // Pages : adresses complètes pour les aperçus de partage (WhatsApp, Facebook…)
    if ((res.headers.get("Content-Type") || "").includes("text/html")) {
      const abs = (v) => (v && !/^https?:/.test(v) ? new URL(v, `${origin}/`).toString() : v);
      return new HTMLRewriter()
        .on('meta[property="og:image"]', { element(el) { el.setAttribute("content", abs(el.getAttribute("content"))); } })
        .on("head", { element(el) { el.append(`<meta property="og:url" content="${origin}${p}">`, { html: true }); } })
        .transform(res);
    }
    return res;
  },
};
