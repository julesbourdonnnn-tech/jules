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
 *  NOTIFY_TOKEN       (facultatif) jeton d'accès d'un compte ntfy.sh (sinon le quota gratuit, partagé, peut être épuisé)
 *  ICAL_LACANAU / ICAL_BORDEAUX (facultatif) liens iCal d'export Airbnb
 *  RESEND_API_KEY     (facultatif) clé Resend : e-mails automatiques aux voyageurs (confirmation,
 *                     rappel J-7 avec l'adresse, demande d'avis, caution)
 *
 * Chaque matin (Cron Trigger, wrangler.jsonc) : rappels J-7, demandes d'avis, caution
 * (empreinte bancaire la veille de l'arrivée, renouvelée si besoin, libérée 48 h après le départ).
 * Stockage : KV « RESERVATIONS » (wrangler.jsonc).
 */
import "./shim.js";
import "../js/data.js";
import "../js/tarifs.js";
import "../js/tarifs-airbnb.js";
import "../js/prix.js";
import { mailText, mailHtml, hoursOf } from "./mails.js";

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
  if (!r.ok) throw Object.assign(new Error((data.error && data.error.message) || `Stripe ${r.status}`), { code: data.error && (data.error.decline_code || data.error.code) });
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
      // Carte enregistrée chez Stripe (pour l'empreinte de caution la veille de l'arrivée)
      if (pi.customer) b.customer = typeof pi.customer === "string" ? pi.customer : pi.customer.id;
      if (pi.payment_method) b.paymentMethod = typeof pi.payment_method === "string" ? pi.payment_method : pi.payment_method.id;
      await save(env, b);
      b._nouveau = true;
      await sendGuestMail(env, b, "recue");
    } else if (s.status === "expired") {
      b.statut = "expiree";
      await save(env, b);
    }
  } catch (e) { /* on réessaiera */ }
  return b;
}

/* ===================== Codes promo ===================== */
// Stockés dans KV (« promo:CODE »), créés depuis admin.html. Types :
//  - pourcent : −X % sur le total ;  - prix : le séjour coûte X € au total (ex. 1 € pour un essai).
const PROMO_RE = /^[A-Z0-9-]{3,30}$/;
const normCode = (v) => clean(v, 30).toUpperCase().replace(/\s+/g, "");
async function loadPromo(env, code) {
  const kv = store(env);
  if (!kv || !PROMO_RE.test(code)) return null;
  const v = await kv.get(`promo:${code}`);
  const c = v ? JSON.parse(v) : null;
  if (!c || !c.actif) return null;
  if (c.max && (await promoUses(env))[c.code] >= c.max) return null;
  return c;
}
// Utilisations = réservations en cours de paiement, à valider ou confirmées (un paiement abandonné ou refusé ne compte pas)
async function promoUses(env) {
  const n = {};
  for (const b of await allBookings(env)) {
    if (!b.code) continue;
    const live = b.statut === "a_valider" || b.statut === "confirmee" || (b.statut === "paiement" && Date.now() - Date.parse(b.cree) < HOLD_MIN * 60000);
    if (live) n[b.code] = (n[b.code] || 0) + 1;
  }
  return n;
}
// Applique un code à un prix calculé par SP_PRICE (ne descend jamais sous 1 €, minimum Stripe)
function applyPromo(p, c) {
  if (!p.ready || !c) return p;
  const before = p.cents;
  let target = c.type === "prix" ? Math.round(c.valeur * 100) : Math.round(before * (1 - c.valeur / 100));
  target = Math.max(100, Math.min(before, target));
  const off = before - target;
  if (off <= 0) return p;
  const q = Object.assign({}, p, { lines: p.lines.slice() });
  q.lines.push({ label: c.type === "prix" ? `Code ${c.code}` : `Code ${c.code} (−${c.valeur} %)`, cents: -off });
  q.cents = target;
  q.total = target / 100;
  q.code = c.code;
  return q;
}
async function checkPromo(request, env) {
  let d;
  try { d = await request.json(); } catch { return json({ ok: false }, 400); }
  const house = clean(d.maison, 20);
  const M = MSG[langOf(d.lang)];
  const c = await loadPromo(env, normCode(d.code));
  if (!c || (c.maison && c.maison !== house)) return json({ ok: false, message: M.codeShort }, 404);
  const a = clean(d.arrivee, 10), b = clean(d.depart, 10);
  if (!H[house] || !DATE.test(a) || !DATE.test(b)) return json({ ok: false, message: M.dates }, 400);
  const p = applyPromo(PRICE(house, a, b, Math.max(1, parseInt(d.adultes, 10) || 1), await loadTarifs(env)), c);
  return json({ ok: true, code: c.code, price: p.ready ? { lines: p.lines, cents: p.cents } : null });
}
async function adminCodes(request, env, code) {
  const kv = store(env);
  if (request.method === "GET") {
    const page = await kv.list({ prefix: "promo:" });
    const uses = await promoUses(env);
    const list = (await Promise.all(page.keys.map((k) => kv.get(k.name)))).filter(Boolean).map((v) => Object.assign(JSON.parse(v), { utilisations: 0 }));
    list.forEach((c) => { c.utilisations = uses[c.code] || 0; });
    return json({ ok: true, codes: list.sort((x, y) => (x.cree < y.cree ? 1 : -1)) });
  }
  if (request.method === "DELETE" && code) { await kv.delete(`promo:${normCode(code)}`); return json({ ok: true }); }
  if (request.method === "POST") {
    let d;
    try { d = await request.json(); } catch { return json({ ok: false }, 400); }
    const c = {
      code: normCode(d.code), type: d.type === "prix" ? "prix" : "pourcent", valeur: Number(d.valeur),
      maison: KEYS.includes(d.maison) ? d.maison : "", max: Math.max(0, parseInt(d.max, 10) || 0),
      actif: true, cree: new Date().toISOString(),
    };
    if (!PROMO_RE.test(c.code)) return json({ ok: false, message: "Le code doit faire 3 à 30 caractères (lettres, chiffres, tirets)." }, 400);
    if (!(c.valeur > 0) || (c.type === "pourcent" && c.valeur > 100) || (c.type === "prix" && c.valeur < 1)) return json({ ok: false, message: c.type === "prix" ? "Le prix doit être d'au moins 1 €." : "La réduction doit être entre 1 et 100 %." }, 400);
    await kv.put(`promo:${c.code}`, JSON.stringify(c));
    return json({ ok: true, code: c });
  }
  return json({ ok: false }, 405);
}

/* ===================== Prix (espace propriétaire) ===================== */
// Réglages enregistrés dans le KV (clé « tarifs ») : pour chaque maison, prix automatiques (Airbnb ± x %)
// ou prix fixés à la main, plus des prix pour des dates précises (événements, vacances…).
// Ils sont injectés dans chaque page (globalThis.TARIFS_LIVE) et utilisés par le serveur pour le paiement.
let tarifsCache = { t: 0, v: null };
async function loadTarifs(env) {
  if (Date.now() - tarifsCache.t < 15000 && tarifsCache.v) return tarifsCache.v;
  const kv = store(env);
  let v = {};
  try { v = (kv && JSON.parse((await kv.get("tarifs")) || "{}")) || {}; } catch { v = {}; }
  tarifsCache = { t: Date.now(), v };
  return v;
}
const num = (v, min, max) => { const n = Math.round(Number(v)); return v === "" || v == null || !Number.isFinite(n) ? null : n >= min && n <= max ? n : NaN; };
function checkTarifs(d) {
  const out = { remise: num(d.remise, 0, 50) };
  if (out.remise == null) out.remise = 10;
  if (Number.isNaN(out.remise)) return "La remise doit être entre 0 et 50 %.";
  for (const k of KEYS) {
    const x = d[k] || {};
    const h = {
      mode: x.mode === "manuel" ? "manuel" : "auto",
      ajust: num(x.ajust, -50, 100) ?? 0, nuit: num(x.nuit, 20, 10000), weekend: num(x.weekend, 20, 10000), menage: num(x.menage, 0, 2000),
      caution: num(x.caution, 0, 5000),
      dates: [],
    };
    const name = H[k].name;
    if (Number.isNaN(h.ajust)) return `${name} : l'ajustement doit être entre −50 et +100 %.`;
    if ([h.nuit, h.weekend].some(Number.isNaN)) return `${name} : un prix de nuit doit être entre 20 et 10 000 €.`;
    if (Number.isNaN(h.menage)) return `${name} : le ménage doit être entre 0 et 2 000 €.`;
    if (Number.isNaN(h.caution)) return `${name} : la caution doit être entre 0 et 5 000 €.`;
    if (h.mode === "manuel" && !h.nuit) return `${name} : indique le prix de la nuit (ou repasse en prix automatiques).`;
    const list = Array.isArray(x.dates) ? x.dates.slice(0, 200) : [];
    for (const r of list) {
      const e = { du: clean(r.du, 10), au: clean(r.au, 10), nuit: num(r.nuit, 20, 10000), pct: num(r.pct, -50, 200), nom: clean(r.nom, 80) };
      if (!DATE.test(e.du) || !DATE.test(e.au) || e.au < e.du) return `${name} : dates incorrectes pour « ${e.nom || "prix fixé"} ».`;
      if (Number.isNaN(e.nuit)) return `${name} : le prix pour « ${e.nom || e.du} » doit être entre 20 et 10 000 €.`;
      if (Number.isNaN(e.pct)) return `${name} : la variation pour « ${e.nom || e.du} » doit être entre −50 et +200 %.`;
      if (!e.nuit && !e.pct) return `${name} : indique un prix ou un pourcentage pour « ${e.nom || e.du} ».`;
      if (e.nuit) delete e.pct; else delete e.nuit;
      h.dates.push(e);
    }
    h.dates.sort((a, b) => (a.du < b.du ? -1 : 1));
    out[k] = h;
  }
  out.maj = new Date().toISOString();
  return out;
}
async function adminTarifs(request, env) {
  const kv = store(env);
  if (request.method === "GET") return json({ ok: true, tarifs: await loadTarifs(env), airbnb: globalThis.TARIFS_AIRBNB || {} });
  if (request.method === "POST") {
    let d;
    try { d = await request.json(); } catch { return json({ ok: false }, 400); }
    const t = checkTarifs(d || {});
    if (typeof t === "string") return json({ ok: false, message: t }, 400);
    await kv.put("tarifs", JSON.stringify(t));
    tarifsCache = { t: Date.now(), v: t };
    return json({ ok: true, tarifs: t });
  }
  return json({ ok: false }, 405);
}

/* ===================== Mesure d'audience (sans cookie, anonyme) ===================== */
// Base D1 « STATS ». Un visiteur = empreinte du jour (adresse IP + navigateur + date, hachées avec un secret) :
// rien ne permet de retrouver qui il est, et elle change chaque jour. Pas de cookie, pas de bandeau.
const BOT = /bot|crawl|spider|slurp|facebookexternalhit|whatsapp|telegram|preview|headless|lighthouse|python|curl|wget|monitor|uptime|scan|fetch|http-client|axios|go-http|java\//i;
const parisDay = (t = Date.now()) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Paris", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(t));
async function visitorId(request, env, day) {
  const raw = `${day}|${request.headers.get("CF-Connecting-IP") || ""}|${request.headers.get("User-Agent") || ""}|${env.ADMIN_KEY || "sable-et-pierre"}`;
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw));
  return Array.from(new Uint8Array(buf).slice(0, 8), (x) => x.toString(16).padStart(2, "0")).join("");
}
const skipStats = (request) => {
  const ua = request.headers.get("User-Agent") || "";
  if (!ua || BOT.test(ua)) return true;
  if (/(?:^|;\s*)sp_owner=1/.test(request.headers.get("Cookie") || "")) return true; // le propriétaire ne se compte pas
  const purpose = request.headers.get("Sec-Purpose") || request.headers.get("Purpose") || "";
  return /prefetch|prerender/i.test(purpose);
};
const PAGES = { "/guide-plages-lacanau": "/guide-plages-lacanau", "/guide-plages-lacanau.html": "/guide-plages-lacanau", "/guide-semaine-gironde-famille": "/guide-semaine-gironde-famille", "/guide-semaine-gironde-famille.html": "/guide-semaine-gironde-famille", "/vacances-famille-lacanau": "/vacances-famille-lacanau", "/vacances-famille-lacanau.html": "/vacances-famille-lacanau", "/vacances-famille-bordeaux": "/vacances-famille-bordeaux", "/vacances-famille-bordeaux.html": "/vacances-famille-bordeaux", "/": "/", "/index.html": "/", "/lacanau": "/lacanau", "/lacanau.html": "/lacanau", "/bordeaux": "/bordeaux", "/bordeaux.html": "/bordeaux", "/conditions": "/conditions", "/conditions.html": "/conditions", "/mentions-legales": "/mentions-legales", "/mentions-legales.html": "/mentions-legales" };
async function trackHit(request, env, url) {
  if (!env.STATS || request.method !== "GET" || skipStats(request)) return;
  const lm = /^\/(en|es)(\/.*)$/.exec(url.pathname); // versions anglaise et espagnole
  const base = PAGES[lm ? lm[2] : url.pathname];
  if (!base) return;
  const path = lm ? `/${lm[1]}${base === "/" ? "/" : base}` : base;
  let src = clean(url.searchParams.get("utm_source") || "", 40).toLowerCase();
  if (!src) {
    try {
      const ref = new URL(request.headers.get("Referer") || "");
      if (ref.hostname.replace(/^www\./, "") === url.hostname.replace(/^www\./, "")) src = "="; // navigation interne
      else if (ref.hostname) src = ref.hostname.replace(/^www\.|^m\.|^l\.|^lm\./, "");
    } catch (e) { /* accès direct */ }
  }
  const ua = request.headers.get("User-Agent") || "";
  const device = /iPad|Tablet/i.test(ua) ? "tablette" : /Mobi|Android|iPhone/i.test(ua) ? "mobile" : "ordinateur";
  const day = parisDay();
  const vid = await visitorId(request, env, day);
  await env.STATS.prepare("INSERT INTO hits (day, ts, path, src, country, device, vid) VALUES (?, ?, ?, ?, ?, ?, ?)")
    .bind(day, Date.now(), path, src, (request.cf && request.cf.country) || "", device, vid).run();
}
const EVENTS = ["reserver", "airbnb", "paiement"];
async function trackEvent(request, env) {
  if (!env.STATS || skipStats(request)) return new Response(null, { status: 204 });
  let d;
  try { d = JSON.parse(await request.text()); } catch { return new Response(null, { status: 204 }); }
  const name = String(d.e || "");
  const house = KEYS.includes(d.h) ? d.h : "";
  if (!EVENTS.includes(name)) return new Response(null, { status: 204 });
  const day = parisDay();
  await env.STATS.prepare("INSERT INTO events (day, ts, name, house, vid) VALUES (?, ?, ?, ?, ?)").bind(day, Date.now(), name, house, await visitorId(request, env, day)).run();
  return new Response(null, { status: 204 });
}
async function adminStats(env, ctx, url) {
  const days = Math.min(400, Math.max(1, parseInt(url.searchParams.get("jours"), 10) || 30));
  const today = parisDay();
  const since = parisDay(Date.now() - (days - 1) * DAY);
  const before = parisDay(Date.now() - (2 * days - 1) * DAY);
  const out = { ok: true, jours: days, du: since, au: today, stats: !!env.STATS };
  if (env.STATS) {
    const q = (sql, ...args) => env.STATS.prepare(sql).bind(...args);
    const [daily, prev, pages, sources, countries, devices, events, live] = await env.STATS.batch([
      q("SELECT day, COUNT(DISTINCT vid) AS v, COUNT(*) AS p FROM hits WHERE day >= ? GROUP BY day ORDER BY day", since),
      q("SELECT COUNT(DISTINCT day || vid) AS v, COUNT(*) AS p FROM hits WHERE day >= ? AND day < ?", before, since),
      q("SELECT path AS k, COUNT(DISTINCT day || vid) AS v, COUNT(*) AS p FROM hits WHERE day >= ? GROUP BY path ORDER BY v DESC LIMIT 10", since),
      q("SELECT src AS k, COUNT(DISTINCT day || vid) AS v FROM hits WHERE day >= ? AND src != '=' GROUP BY src ORDER BY v DESC LIMIT 12", since),
      q("SELECT country AS k, COUNT(DISTINCT day || vid) AS v FROM hits WHERE day >= ? GROUP BY country ORDER BY v DESC LIMIT 10", since),
      q("SELECT device AS k, COUNT(DISTINCT day || vid) AS v FROM hits WHERE day >= ? GROUP BY device ORDER BY v DESC", since),
      q("SELECT name, house, COUNT(DISTINCT day || vid) AS n FROM events WHERE day >= ? GROUP BY name, house", since),
      q("SELECT COUNT(DISTINCT vid) AS v FROM hits WHERE ts > ?", Date.now() - 5 * 60000),
    ]);
    out.jour = daily.results;
    out.precedent = prev.results[0] || { v: 0, p: 0 };
    out.pages = pages.results;
    out.sources = sources.results;
    out.pays = countries.results;
    out.appareils = devices.results;
    out.evenements = events.results;
    out.enCeMoment = (live.results[0] || {}).v || 0;
    // Ménage : on ne garde que 13 mois de relevés
    ctx.waitUntil(env.STATS.batch([q("DELETE FROM hits WHERE day < ?", parisDay(Date.now() - 400 * DAY)), q("DELETE FROM events WHERE day < ?", parisDay(Date.now() - 400 * DAY))]).catch(() => {}));
  }
  // Réservations directes sur la période
  const list = (await allBookings(env)).filter((b) => parisDay(Date.parse(b.cree)) >= since);
  const demandes = list.filter((b) => b.statut !== "paiement" && b.statut !== "expiree");
  const conf = list.filter((b) => b.statut === "confirmee");
  out.reservations = {
    demandes: demandes.length, confirmees: conf.length, abandonnees: list.filter((b) => b.statut === "expiree").length,
    chiffre: conf.reduce((t, b) => t + (b.cents || 0), 0),
    nuits: conf.reduce((t, b) => t + (b.nuits || 0), 0),
    parMaison: Object.fromEntries(KEYS.map((k) => [k, { demandes: demandes.filter((b) => b.maison === k).length, confirmees: conf.filter((b) => b.maison === k).length, chiffre: conf.filter((b) => b.maison === k).reduce((t, b) => t + (b.cents || 0), 0) }])),
  };
  return json(out);
}

/* ===================== Alertes ===================== */
// Alerte téléphone (ntfy, Discord ou Slack via NOTIFY_URL) + e-mail au propriétaire (Cloudflare Email Routing, binding MAILER)
async function sendAlerts(env, title, text, link) {
  const out = {};
  const url = (env.NOTIFY_URL || "").trim();
  if (url) {
    try {
      let r;
      if (url.includes("discord.com")) r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ content: `**${title}**\n${text}${link ? `\n${link}` : ""}` }) });
      else if (url.includes("hooks.slack.com")) r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text: `*${title}*\n${text}${link ? `\n${link}` : ""}` }) });
      else {
        // ntfy : envoi en JSON (les accents ne passent pas dans les en-têtes). Accepte « https://ntfy.sh/sujet », « ntfy.sh/sujet » ou « sujet ».
        const u = new URL(/^https?:\/\//.test(url) ? url : url.includes("/") ? `https://${url}` : `https://ntfy.sh/${url}`);
        const topic = u.pathname.replace(/^\/+|\/+$/g, "");
        // NOTIFY_TOKEN (jeton d'un compte ntfy gratuit) : le quota devient celui du compte, pas celui de l'adresse partagée de Cloudflare
        const auth = env.NOTIFY_TOKEN ? { Authorization: `Bearer ${env.NOTIFY_TOKEN.trim()}` } : {};
        r = await fetch(`${u.origin}/`, { method: "POST", headers: { "Content-Type": "application/json", ...auth }, body: JSON.stringify({ topic, title, message: text, tags: ["house"], priority: 4, ...(link ? { click: link } : {}) }) });
      }
      out.telephone = r.ok ? "envoyée" : `erreur ${r.status} : ${(await r.text()).slice(0, 160)}`;
    } catch (e) { out.telephone = `erreur : ${e.message}`; }
  } else out.telephone = "NOTIFY_URL non réglé";
  if (env.MAILER) {
    try {
      const { EmailMessage } = await import("cloudflare:email");
      const from = env.EMAIL_FROM || "reservations@sable-et-pierre.com";
      const to = env.EMAIL_TO || (globalThis.SITE && globalThis.SITE.email) || "contact.sablepierre@gmail.com";
      const b64 = (str) => { const bytes = new TextEncoder().encode(str); let bin = ""; bytes.forEach((x) => { bin += String.fromCharCode(x); }); return btoa(bin); };
      const raw = [
        `From: "Sable et Pierre" <${from}>`, `To: ${to}`, `Subject: =?UTF-8?B?${b64(title)}?=`,
        `Message-ID: <${rand(8)}@${from.split("@")[1]}>`, `Date: ${new Date().toUTCString()}`,
        "MIME-Version: 1.0", "Content-Type: text/plain; charset=UTF-8", "Content-Transfer-Encoding: base64", "",
        b64(`${text}${link ? `\n\n${link}` : ""}\n`).replace(/.{76}/g, "$&\r\n"),
      ].join("\r\n");
      await env.MAILER.send(new EmailMessage(from, to, raw));
      out.email = `envoyé à ${to}`;
    } catch (e) { out.email = `erreur : ${e.message}`; }
  } else out.email = "envoi d'e-mails pas encore activé";
  return out;
}
function notify(env, ctx, title, text, link) {
  ctx.waitUntil(sendAlerts(env, title, text, link).catch(() => {}));
}
const summary = (b) => `${b.lang && b.lang !== "fr" ? `[${b.lang === "en" ? "anglais" : "espagnol"}] ` : ""}${H[b.maison].name} · du ${fmtDate(b.arrivee)} au ${fmtDate(b.depart)} (${b.nuits} nuits) · ${b.adultes} adulte(s)${b.enfants ? `, ${b.enfants} enfant(s)` : ""}${b.bebes ? `, ${b.bebes} bébé(s)` : ""}\n${b.nom} · ${b.telephone || "pas de tél."} · ${b.email}${b.total ? `\nMontant : ${EUR(b.cents)}${b.code ? ` (code ${b.code})` : ""}` : ""}${b.message ? `\n« ${b.message} »` : ""}`;

/* ===================== Voyageurs ===================== */
const ERR = {
  passe: "La date d'arrivée est déjà passée.",
  dates: "Les dates ne sont pas valides.",
  pris: "Ces dates ne sont plus disponibles. Choisissez d'autres dates.",
  depart: "Le départ n'est pas possible ce jour-là. Choisissez un autre jour.",
  court: "Le séjour est trop court pour ces dates.",
  long: "Le séjour est trop long pour ces dates.",
};
/* Messages aux voyageurs selon la langue de la page (fr, en, es) */
const LANGS = ["fr", "en", "es"];
const langOf = (v) => (LANGS.includes(v) ? v : "fr");
const prefixOf = (lang) => (lang === "fr" ? "" : `${lang}/`);
const MSG = {
  fr: { invalid: "Merci de vérifier vos dates, votre nom et votre e-mail.", conditions: "Merci d'accepter les conditions de réservation.", capacite: (n) => `Cette maison accueille jusqu'à ${n} voyageurs.`, bebes: "La Maison de Pierre ne convient pas aux bébés de moins de 2 ans.", code: "Ce code promo n'est pas valable.", codeShort: "Ce code n'est pas valable.", dates: "Choisissez d'abord vos dates.", stripe: "Le paiement en ligne est momentanément indisponible. Réessayez dans un instant.", ...ERR, nights: (n) => `${n} nuit${n > 1 ? "s" : ""}`, line: (a, b, g, id) => `Du ${a} au ${b} · ${g} voyageur(s) · réservation ${id}` },
  en: { invalid: "Please check your dates, your name and your email address.", conditions: "Please accept the booking terms.", capacite: (n) => `This house sleeps up to ${n} guests.`, bebes: "La Maison de Pierre is not suitable for babies under 2.", code: "This promo code is not valid.", codeShort: "This code is not valid.", dates: "Please choose your dates first.", stripe: "Online payment is temporarily unavailable. Please try again in a moment.", passe: "The arrival date has already passed.", pris: "These dates are no longer available. Please choose other dates.", depart: "Departure is not possible on that day. Please choose another day.", court: "The stay is too short for these dates.", long: "The stay is too long for these dates.", nights: (n) => `${n} night${n > 1 ? "s" : ""}`, line: (a, b, g, id) => `From ${a} to ${b} · ${g} guest(s) · booking ${id}` },
  es: { invalid: "Comprueba tus fechas, tu nombre y tu correo electrónico.", conditions: "Acepta las condiciones de reserva.", capacite: (n) => `Esta casa tiene capacidad para ${n} viajeros como máximo.`, bebes: "La Maison de Pierre no es adecuada para bebés menores de 2 años.", code: "Este código promocional no es válido.", codeShort: "Este código no es válido.", dates: "Elige primero tus fechas.", stripe: "El pago en línea no está disponible en este momento. Vuelve a intentarlo dentro de un instante.", passe: "La fecha de llegada ya ha pasado.", pris: "Estas fechas ya no están disponibles. Elige otras fechas.", depart: "No es posible salir ese día. Elige otro día.", court: "La estancia es demasiado corta para estas fechas.", long: "La estancia es demasiado larga para estas fechas.", nights: (n) => `${n} noche${n > 1 ? "s" : ""}`, line: (a, b, g, id) => `Del ${a} al ${b} · ${g} viajero(s) · reserva ${id}` },
};
// Dates « 21 août 2027 » dans la langue du voyageur
const fmtDateL = (s, lang) => new Intl.DateTimeFormat({ fr: "fr-FR", en: "en-GB", es: "es-ES" }[lang], { weekday: "short", day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(toDay(s)));

async function createBooking(request, env, ctx, origin) {
  const kv = store(env);
  if (!kv) return json({ ok: false, error: "storage_not_configured" }, 503);
  if (Number(request.headers.get("Content-Length")) > 8192) return json({ ok: false, error: "too_large" }, 413);
  let d;
  try { d = await request.json(); } catch { return json({ ok: false, error: "bad_request" }, 400); }
  if (d["bot-field"]) return json({ ok: false, error: "invalid" }, 400);
  const house = clean(d.maison, 20);
  const h = H[house];
  const lang = langOf(d.lang);
  const M = MSG[lang];
  const b = {
    lang,
    maison: house, arrivee: clean(d.arrivee, 10), depart: clean(d.depart, 10),
    adultes: Math.max(1, parseInt(d.adultes, 10) || 1), enfants: Math.max(0, parseInt(d.enfants, 10) || 0), bebes: Math.max(0, parseInt(d.bebes, 10) || 0),
    nom: clean(d.nom, 80), email: clean(d.email, 254).toLowerCase(), telephone: clean(d.telephone, 30), message: clean(d.message, 2000),
  };
  if (!h || !DATE.test(b.arrivee) || !DATE.test(b.depart) || b.depart <= b.arrivee || !b.nom || !EMAIL.test(b.email)) return json({ ok: false, error: "invalid", message: M.invalid }, 400);
  if (!d.conditions) return json({ ok: false, error: "conditions", message: M.conditions }, 400);
  if (b.adultes + b.enfants > h.guests) return json({ ok: false, error: "capacite", message: M.capacite(h.guests) }, 400);
  if (house === "bordeaux" && b.bebes > 0) return json({ ok: false, error: "bebes", message: M.bebes }, 400);
  const problem = await checkStay(house, b.arrivee, b.depart, env, origin);
  if (problem) return json({ ok: false, error: problem, message: M[problem] || ERR[problem] }, 409);

  let p = PRICE(house, b.arrivee, b.depart, b.adultes, await loadTarifs(env));
  const codeIn = normCode(d.code);
  let promo = null;
  if (codeIn) {
    promo = await loadPromo(env, codeIn);
    if (!promo || (promo.maison && promo.maison !== house)) return json({ ok: false, error: "code", message: M.code }, 400);
    p = applyPromo(p, promo);
    if (p.code) b.code = p.code;
  }
  b.nuits = Math.round((toDay(b.depart) - toDay(b.arrivee)) / DAY);
  b.id = `SP${Date.now().toString(36).toUpperCase().slice(-5)}${rand(2).toUpperCase()}`;
  b.token = rand(12);
  b.cree = new Date().toISOString();
  b.pays = (request.cf && request.cf.country) || "";
  if (p.ready) { b.cents = p.cents; b.total = p.total; b.lignes = p.lines; }
  b.cautionMontant = await cautionOf(env, house);

  // Paiement en ligne possible : tarifs renseignés et clé Stripe en place
  if (p.ready && env.STRIPE_SECRET_KEY) {
    b.statut = "paiement";
    const back = `${origin}/${prefixOf(lang)}reservation.html?id=${b.id}&t=${b.token}`;
    try {
      const s = await stripe(env, "POST", "checkout/sessions", {
        mode: "payment",
        locale: lang,
        customer_email: b.email,
        client_reference_id: b.id,
        expires_at: Math.floor(Date.now() / 1000) + 31 * 60,
        success_url: back,
        cancel_url: `${origin}/${prefixOf(lang)}${h.page}?arrivee=${b.arrivee}&depart=${b.depart}&voyageurs=${b.adultes + b.enfants}&annule=1#reserver`,
        line_items: { 0: { quantity: 1, price_data: { currency: "eur", unit_amount: b.cents, product_data: { name: `${h.name} — ${M.nights(b.nuits)}`, description: M.line(fmtDateL(b.arrivee, lang), fmtDateL(b.depart, lang), b.adultes + b.enfants, b.id) } } } },
        // Empreinte bancaire : le montant n'est débité que lorsque tu acceptes la réservation
        payment_intent_data: { capture_method: "manual", description: `Réservation ${b.id} — ${h.name}`, receipt_email: b.email, metadata: { reservation: b.id },
          // Carte gardée par Stripe pour l'empreinte de caution (la veille de l'arrivée)
          setup_future_usage: b.cautionMontant ? "off_session" : undefined },
        customer_creation: b.cautionMontant ? "always" : undefined,
        metadata: { reservation: b.id, maison: house },
      });
      b.stripeSession = s.id;
      await save(env, b);
      return json({ ok: true, mode: "paiement", url: s.url, id: b.id });
    } catch (e) {
      return json({ ok: false, error: "stripe", message: M.stripe }, 502);
    }
  }
  // Sinon : demande de réservation, sans paiement (le prix est confirmé par e-mail)
  b.statut = "a_valider";
  b.paiement = "à organiser";
  await save(env, b);
  notify(env, ctx, "Nouvelle demande de réservation", summary(b), `${origin}/admin.html`);
  ctx.waitUntil(sendGuestMail(env, b, "recue").catch(() => {}));
  return json({ ok: true, mode: "demande", id: b.id, url: `/${prefixOf(lang)}reservation.html?id=${b.id}&t=${b.token}` });
}

async function bookingStatus(env, ctx, origin, id, token) {
  if (!store(env)) return json({ ok: false }, 503);
  let b = await load(env, id);
  if (!b || b.token !== token) return json({ ok: false, error: "introuvable" }, 404);
  b = await syncStripe(env, b);
  if (b._nouveau) notify(env, ctx, "Réservation à valider (paiement autorisé)", summary(b), `${origin}/admin.html`);
  if (b.caution && b.caution.etat === "lien") await syncCautionLink(env, ctx, b);
  const h = H[b.maison];
  const c = b.caution || {};
  return json({ ok: true, reservation: {
    id: b.id, maison: b.maison, nomMaison: h.name, page: h.page, statut: b.statut, paiement: b.paiement || "",
    arrivee: b.arrivee, depart: b.depart, nuits: b.nuits, adultes: b.adultes, enfants: b.enfants, bebes: b.bebes,
    nom: b.nom, email: b.email, cents: b.cents || 0, lignes: b.lignes || [],
    caution: b.cautionMontant ? { montant: b.cautionMontant, etat: c.etat || "a_venir", url: c.etat === "lien" ? c.url : undefined } : null,
  } });
}

/* ===================== Séjour : e-mails automatiques et caution ===================== */
const SITE = "https://sable-et-pierre.com";
const REPLY = "contact.sablepierre@gmail.com";
const CAUTION_JOURS = 2; // la caution est libérée 2 jours après le départ
const daysBetween = (a, b) => Math.round((toDay(b) - toDay(a)) / DAY);
const money = (cents, lang) => new Intl.NumberFormat({ fr: "fr-FR", en: "en-GB", es: "es-ES" }[lang] || "fr-FR", { style: "currency", currency: "EUR", maximumFractionDigits: cents % 100 ? 2 : 0 }).format(cents / 100);
const statusLink = (b) => `${SITE}/${prefixOf(langOf(b.lang))}reservation.html?id=${b.id}&t=${b.token}`;

// Montant de la caution d'une maison : réglé dans l'espace propriétaire (Prix), sinon js/tarifs.js
async function cautionOf(env, house) {
  const t = (await loadTarifs(env))[house] || {};
  const v = t.caution != null ? t.caution : (globalThis.TARIFS[house] || {}).caution;
  return Math.max(0, Math.round(Number(v) || 0));
}
// Informations d'arrivée (privées : jamais affichées sur le site, envoyées 7 jours avant)
async function loadInfos(env) {
  try { return JSON.parse((await store(env).get("infos")) || "{}") || {}; } catch { return {}; }
}
async function adminInfos(request, env) {
  if (request.method === "GET") return json({ ok: true, infos: await loadInfos(env), mails: !!env.RESEND_API_KEY });
  if (request.method !== "POST") return json({ ok: false }, 405);
  let d;
  try { d = await request.json(); } catch { return json({ ok: false }, 400); }
  const out = { avisUrl: clean(d.avisUrl, 300) };
  if (out.avisUrl && !/^https:\/\//.test(out.avisUrl)) return json({ ok: false, message: "Le lien pour les avis doit commencer par https://" }, 400);
  for (const k of KEYS) {
    const x = d[k] || {};
    const txt = (v) => String(v ?? "").replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "").trim().slice(0, 4000);
    out[k] = { adresse: clean(x.adresse, 200), fr: txt(x.fr), en: txt(x.en), es: txt(x.es) };
  }
  await store(env).put("infos", JSON.stringify(out));
  return json({ ok: true, infos: out });
}

async function sendMail(env, to, subject, text) {
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: env.MAIL_FROM || "Sable & Pierre <reservations@sable-et-pierre.com>", to: [to], reply_to: REPLY, subject, text, html: mailHtml(text) }),
  });
  if (!r.ok) throw new Error(`Resend ${r.status} : ${(await r.text()).slice(0, 200)}`);
}
// E-mail au voyageur (une seule fois par type, noté dans la réservation). Renvoie "envoyé", "déjà envoyé", "désactivé" ou l'erreur.
async function sendGuestMail(env, b, type, extra = {}) {
  if (!type) return "";
  if (!env.RESEND_API_KEY) return "désactivé";
  b.mails = b.mails || {};
  if (b.mails[type] && !extra.encore) return "déjà envoyé";
  const lang = langOf(b.lang);
  const h = H[b.maison];
  const infos = type === "rappel" ? await loadInfos(env) : {};
  const I = infos[b.maison] || {};
  const hrs = hoursOf(b.maison, lang, h);
  const x = {
    maison: h.name, du: fmtDateL(b.arrivee, lang), au: fmtDateL(b.depart, lang), lien: statusLink(b),
    montant: b.cents ? money(b.cents, lang) : "", caution: b.cautionMontant ? money(b.cautionMontant * 100, lang) : "",
    arrivee: hrs.arrivee, depart: hrs.depart, adresse: I.adresse || "",
    infos: I[lang] || (lang === "es" && I.en) || I.fr || "", avisUrl: infos.avisUrl || (await loadInfos(env)).avisUrl || "",
    cautionUrl: (b.caution || {}).url || "",
  };
  const m = mailText(type, b, x);
  try {
    await sendMail(env, b.email, m.subject, m.text);
    b.mails[type] = new Date().toISOString();
    delete b.mailErreur;
    await save(env, b);
    return "envoyé";
  } catch (e) {
    b.mailErreur = `${type} : ${e.message}`;
    await save(env, b);
    return `erreur (${e.message})`;
  }
}
async function testMail(env) {
  if (!env.RESEND_API_KEY) return json({ ok: false, message: "Ajoute d'abord le secret RESEND_API_KEY dans Cloudflare." }, 400);
  const m = mailText("test", { nom: "Jules", lang: "fr" }, {});
  try { await sendMail(env, REPLY, m.subject, m.text); } catch (e) { return json({ ok: false, message: e.message }, 502); }
  return json({ ok: true, message: `E-mail de test envoyé à ${REPLY}.` });
}

// Caution : empreinte bancaire (montant bloqué, non débité) sur la carte enregistrée lors du paiement.
async function placeCaution(env, ctx, b, renew) {
  const h = H[b.maison];
  const lang = langOf(b.lang);
  const old = b.caution || {};
  try {
    if (!b.customer || !b.paymentMethod) throw Object.assign(new Error("pas de carte enregistrée"), { code: "no_card" });
    const pi = await stripe(env, "POST", "payment_intents", {
      amount: b.cautionMontant * 100, currency: "eur", customer: b.customer, payment_method: b.paymentMethod,
      off_session: "true", confirm: "true", capture_method: "manual",
      description: `Caution ${b.id} — ${h.name}`, metadata: { reservation: b.id, caution: "1" },
    });
    if (pi.status !== "requires_capture") throw new Error(`état ${pi.status}`);
    if (renew && old.pi) await stripe(env, "POST", `payment_intents/${old.pi}/cancel`, {}).catch(() => {});
    b.caution = { montant: b.cautionMontant, etat: "bloquee", pi: pi.id, le: new Date().toISOString(), renouvelee: renew ? (old.renouvelee || 0) + 1 : 0 };
    await save(env, b);
    return "bloquée";
  } catch (e) {
    if (renew) {
      // L'ancienne empreinte reste valable encore un jour : on prévient le propriétaire
      notify(env, ctx, "Caution : renouvellement impossible", `${summary(b)}\nL'empreinte de caution n'a pas pu être renouvelée (${e.message}). Elle expire bientôt : décide si tu la gardes (encaisser) ou la libères.`, `${SITE}/admin.html`);
      b.caution.alerte = e.message;
      await save(env, b);
      return "renouvellement impossible";
    }
    // La banque veut une validation du voyageur : on lui envoie un lien de paiement Stripe (empreinte seulement)
    try {
      const sess = await stripe(env, "POST", "checkout/sessions", {
        mode: "payment", locale: lang, customer: b.customer || undefined, customer_email: b.customer ? undefined : b.email,
        expires_at: Math.floor(Date.now() / 1000) + 23 * 3600,
        success_url: statusLink(b), cancel_url: statusLink(b),
        line_items: { 0: { quantity: 1, price_data: { currency: "eur", unit_amount: b.cautionMontant * 100, product_data: { name: `Caution — ${h.name}`, description: `${b.id} · ${fmtDateL(b.arrivee, lang)} → ${fmtDateL(b.depart, lang)}` } } } },
        payment_intent_data: { capture_method: "manual", description: `Caution ${b.id} — ${h.name}`, metadata: { reservation: b.id, caution: "1" } },
        metadata: { reservation: b.id, caution: "1" },
      });
      b.caution = { montant: b.cautionMontant, etat: "lien", session: sess.id, url: sess.url, le: new Date().toISOString(), essais: (old.essais || 0) + 1, raison: e.message };
      await save(env, b);
      await sendGuestMail(env, b, "caution_lien", { encore: true });
      notify(env, ctx, "Caution : le voyageur doit la valider", `${summary(b)}\nSa banque demande une confirmation : un lien lui a été envoyé${env.RESEND_API_KEY ? " par e-mail" : " (e-mails automatiques non activés : envoie-lui ce lien toi-même)"}.\n${sess.url}`, `${SITE}/admin.html`);
      return "lien envoyé";
    } catch (e2) {
      b.caution = { montant: b.cautionMontant, etat: "echec", le: new Date().toISOString(), raison: `${e.message} / ${e2.message}` };
      await save(env, b);
      notify(env, ctx, "Caution impossible", `${summary(b)}\nL'empreinte de caution n'a pas pu être faite (${e2.message}).`, `${SITE}/admin.html`);
      return "échec";
    }
  }
}
// Le voyageur a-t-il validé le lien de caution ?
async function syncCautionLink(env, ctx, b) {
  const c = b.caution;
  if (!c || c.etat !== "lien" || !c.session || !env.STRIPE_SECRET_KEY) return b;
  try {
    const sess = await stripe(env, "GET", `checkout/sessions/${c.session}?expand[]=payment_intent`);
    const pi = sess.payment_intent;
    if (sess.status === "complete" && pi && pi.status === "requires_capture") {
      b.caution = { montant: c.montant, etat: "bloquee", pi: pi.id, le: new Date().toISOString(), renouvelee: 0, parLien: true };
      if (pi.payment_method) b.paymentMethod = typeof pi.payment_method === "string" ? pi.payment_method : pi.payment_method.id;
      if (pi.customer) b.customer = typeof pi.customer === "string" ? pi.customer : pi.customer.id;
      await save(env, b);
    } else if (sess.status === "expired") {
      c.etat = "expire";
      await save(env, b);
    }
  } catch (e) { /* on réessaiera */ }
  return b;
}
async function releaseCaution(env, b, label) {
  const c = b.caution;
  if (!c || c.etat !== "bloquee") return;
  try {
    const pi = await stripe(env, "GET", `payment_intents/${c.pi}`);
    if (pi.status === "requires_capture") await stripe(env, "POST", `payment_intents/${c.pi}/cancel`, {});
  } catch (e) { /* déjà expirée ou annulée */ }
  b.caution = Object.assign({}, c, { etat: "liberee", libereeLe: new Date().toISOString(), note: label });
  await save(env, b);
}
// Propriétaire : encaisser tout ou partie de la caution, ou la libérer tout de suite
async function adminCaution(request, env, id) {
  const b = await load(env, id);
  if (!b) return json({ ok: false, error: "introuvable" }, 404);
  let d;
  try { d = await request.json(); } catch { d = {}; }
  const c = b.caution;
  if (!c || c.etat !== "bloquee") return json({ ok: false, message: "Aucune caution bloquée pour cette réservation." }, 409);
  try {
    if (d.action === "liberer") await releaseCaution(env, b, "libérée par le propriétaire");
    else if (d.action === "encaisser") {
      const cents = Math.round(Number(d.montant) * 100);
      if (!(cents >= 100 && cents <= c.montant * 100)) return json({ ok: false, message: `Le montant doit être entre 1 et ${c.montant} €.` }, 400);
      await stripe(env, "POST", `payment_intents/${c.pi}/capture`, { amount_to_capture: cents });
      b.caution = Object.assign({}, c, { etat: "encaissee", encaisse: cents, encaisseeLe: new Date().toISOString() });
      await save(env, b);
    } else return json({ ok: false }, 400);
  } catch (e) {
    return json({ ok: false, message: `Stripe : ${e.message}` }, 502);
  }
  return json({ ok: true, reservation: b });
}

// Passage du matin (Cron Trigger) : paiements en attente, rappels J-7, caution, demandes d'avis
async function morning(env, ctx) {
  const today = todayISO();
  const log = [];
  for (let b of await allBookings(env)) {
    try {
      if (b.statut === "paiement") {
        b = await syncStripe(env, b);
        if (b._nouveau) { notify(env, ctx, "Réservation à valider (paiement autorisé)", summary(b), `${SITE}/admin.html`); delete b._nouveau; }
      }
      if (b.statut !== "confirmee") continue;
      const toArrival = daysBetween(today, b.arrivee);
      const sinceDeparture = daysBetween(b.depart, today);
      if (toArrival >= 0 && toArrival <= 7 && !(b.mails || {}).rappel) log.push(`${b.id} rappel : ${await sendGuestMail(env, b, "rappel")}`);
      // Caution
      if (b.cautionMontant && env.STRIPE_SECRET_KEY) {
        const c = b.caution || {};
        if (c.etat === "lien") { await syncCautionLink(env, ctx, b); }
        const c2 = b.caution || {};
        if (c2.etat === "bloquee") {
          if (sinceDeparture >= CAUTION_JOURS) { await releaseCaution(env, b, "libérée automatiquement"); log.push(`${b.id} caution libérée`); }
          else if (daysBetween(c2.le.slice(0, 10), today) >= 6) log.push(`${b.id} caution renouvelée : ${await placeCaution(env, ctx, b, true)}`);
        } else if ((!c2.etat || (c2.etat === "expire" && (c2.essais || 0) < 3)) && toArrival <= 1 && sinceDeparture < CAUTION_JOURS) {
          log.push(`${b.id} caution : ${await placeCaution(env, ctx, b, false)}`);
        }
      }
      if (sinceDeparture >= 1 && sinceDeparture <= 10 && !(b.mails || {}).avis) log.push(`${b.id} avis : ${await sendGuestMail(env, b, "avis")}`);
    } catch (e) {
      log.push(`${b.id} erreur : ${e.message}`);
    }
  }
  return log;
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
async function adminList(env, ctx, origin) {
  const list = await allBookings(env);
  for (const b of list) if (b.statut === "paiement") { await syncStripe(env, b); if (b._nouveau) { notify(env, ctx, "Réservation à valider (paiement autorisé)", summary(b), `${origin}/admin.html`); delete b._nouveau; } }
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
      if (b.caution && b.caution.etat === "bloquee") await releaseCaution(env, b, "libérée (réservation annulée)");
    } else return json({ ok: false, error: "action" }, 400);
  } catch (e) {
    return json({ ok: false, message: `Stripe : ${e.message}` }, 502);
  }
  await save(env, b);
  const sent = await sendGuestMail(env, b, { accepter: "confirmee", refuser: "refusee", annuler: "annulee" }[action]);
  return json({ ok: true, reservation: b, mail: sent });
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
  async scheduled(event, env, ctx) {
    ctx.waitUntil(morning(env, ctx).catch((e) => sendAlerts(env, "Erreur du passage du matin", String(e && e.message), `${SITE}/admin.html`)));
  },
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.hostname.startsWith("www.")) {
      url.hostname = url.hostname.slice(4);
      return Response.redirect(url.toString(), 301);
    }
    const p = url.pathname;
    const origin = url.origin;
    let m;
    if ((m = /^\/api\/(?:disponibilites|calendrier)\/(lacanau|bordeaux)$/.exec(p))) {
      return json({ ok: true, booked: await bookedRanges(m[1], env), updated: new Date().toISOString() }, 200, { "Cache-Control": "public, max-age=60" });
    }
    if (p === "/api/reservation" && request.method === "POST") return createBooking(request, env, ctx, origin);
    if ((m = /^\/api\/reservation\/([A-Z0-9]{4,20})$/.exec(p))) return bookingStatus(env, ctx, origin, m[1], url.searchParams.get("t") || "");
    if (p === "/api/promo" && request.method === "POST") return checkPromo(request, env);
    if (p === "/api/evt" && request.method === "POST") return trackEvent(request, env).catch(() => new Response(null, { status: 204 }));
    if ((m = /^\/api\/ical\/(lacanau|bordeaux)\.ics$/.exec(p))) return icalFeed(env, m[1], url.searchParams.get("k") || "");
    if (p.startsWith("/api/admin/")) {
      if (!store(env)) return json({ ok: false, message: "Stockage non configuré." }, 503);
      if (!authorized(request, env)) return json({ ok: false, error: "auth", message: env.ADMIN_KEY ? "Mot de passe incorrect." : "Ajoute d'abord le secret ADMIN_KEY dans Cloudflare." }, 401);
      if (p === "/api/admin/reservations" && request.method === "GET") return adminList(env, ctx, origin);
      if (p === "/api/admin/stats" && request.method === "GET") return adminStats(env, ctx, url);
      if (p === "/api/admin/test-alertes" && request.method === "POST") return json({ ok: true, resultat: await sendAlerts(env, "Test des alertes Sable & Pierre", "Si tu lis ceci, les alertes de réservation fonctionnent.", `${origin}/admin.html`) });
      if (p === "/api/admin/tarifs") return adminTarifs(request, env);
      if (p === "/api/admin/infos") return adminInfos(request, env);
      if (p === "/api/admin/test-mail" && request.method === "POST") return testMail(env);
      if (p === "/api/admin/matin" && request.method === "POST") return json({ ok: true, journal: await morning(env, ctx) });
      if ((m = /^\/api\/admin\/reservations\/([A-Z0-9]{4,20})\/caution$/.exec(p)) && request.method === "POST") return adminCaution(request, env, m[1]);
      if ((m = /^\/api\/admin\/codes(?:\/([A-Za-z0-9-]{1,30}))?$/.exec(p))) return adminCodes(request, env, m[1]);
      if ((m = /^\/api\/admin\/reservations\/([A-Z0-9]{4,20})\/(accepter|refuser|annuler)$/.exec(p)) && request.method === "POST") return adminAction(env, ctx, origin, m[1], m[2]);
      return json({ ok: false }, 404);
    }
    if (p === "/api/demande" && request.method === "POST") return legacyRequest(request, env, ctx);
    if (p.startsWith("/api/")) return new Response("Not found", { status: 404 });

    const res = await env.ASSETS.fetch(request);
    if (res.status === 200) ctx.waitUntil(trackHit(request, env, url).catch(() => {}));
    // Pages : adresses complètes pour les aperçus de partage (WhatsApp, Facebook…)
    if ((res.headers.get("Content-Type") || "").includes("text/html")) {
      const abs = (v) => (v && !/^https?:/.test(v) ? new URL(v, `${origin}/`).toString() : v);
      // Prix réglés dans l'espace propriétaire, lus par js/prix.js
      const live = `globalThis.TARIFS_LIVE=${JSON.stringify(await loadTarifs(env)).replace(/</g, "\\u003c")};`;
      return new HTMLRewriter()
        .on('meta[property="og:image"]', { element(el) { el.setAttribute("content", abs(el.getAttribute("content"))); } })
        .on("head", { element(el) { el.append(`<script>${live}</script>`, { html: true }); } })
        .transform(res);
    }
    return res;
  },
};
