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
  const c = await loadPromo(env, normCode(d.code));
  if (!c || (c.maison && c.maison !== house)) return json({ ok: false, message: "Ce code n'est pas valable." }, 404);
  const a = clean(d.arrivee, 10), b = clean(d.depart, 10);
  if (!H[house] || !DATE.test(a) || !DATE.test(b)) return json({ ok: false, message: "Choisissez d'abord vos dates." }, 400);
  const p = applyPromo(PRICE(house, a, b, Math.max(1, parseInt(d.adultes, 10) || 1)), c);
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
const PAGES = { "/": "/", "/index.html": "/", "/lacanau": "/lacanau", "/lacanau.html": "/lacanau", "/bordeaux": "/bordeaux", "/bordeaux.html": "/bordeaux", "/conditions": "/conditions", "/conditions.html": "/conditions", "/mentions-legales": "/mentions-legales", "/mentions-legales.html": "/mentions-legales" };
async function trackHit(request, env, url) {
  if (!env.STATS || request.method !== "GET" || skipStats(request)) return;
  const path = PAGES[url.pathname];
  if (!path) return;
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
const summary = (b) => `${H[b.maison].name} · du ${fmtDate(b.arrivee)} au ${fmtDate(b.depart)} (${b.nuits} nuits) · ${b.adultes} adulte(s)${b.enfants ? `, ${b.enfants} enfant(s)` : ""}${b.bebes ? `, ${b.bebes} bébé(s)` : ""}\n${b.nom} · ${b.telephone || "pas de tél."} · ${b.email}${b.total ? `\nMontant : ${EUR(b.cents)}${b.code ? ` (code ${b.code})` : ""}` : ""}${b.message ? `\n« ${b.message} »` : ""}`;

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

  let p = PRICE(house, b.arrivee, b.depart, b.adultes);
  const codeIn = normCode(d.code);
  let promo = null;
  if (codeIn) {
    promo = await loadPromo(env, codeIn);
    if (!promo || (promo.maison && promo.maison !== house)) return json({ ok: false, error: "code", message: "Ce code promo n'est pas valable." }, 400);
    p = applyPromo(p, promo);
    if (p.code) b.code = p.code;
  }
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
  notify(env, ctx, "Nouvelle demande de réservation", summary(b), `${origin}/admin.html`);
  return json({ ok: true, mode: "demande", id: b.id, url: `/reservation.html?id=${b.id}&t=${b.token}` });
}

async function bookingStatus(env, ctx, origin, id, token) {
  if (!store(env)) return json({ ok: false }, 503);
  let b = await load(env, id);
  if (!b || b.token !== token) return json({ ok: false, error: "introuvable" }, 404);
  b = await syncStripe(env, b);
  if (b._nouveau) notify(env, ctx, "Réservation à valider (paiement autorisé)", summary(b), `${origin}/admin.html`);
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
      return new HTMLRewriter()
        .on('meta[property="og:image"]', { element(el) { el.setAttribute("content", abs(el.getAttribute("content"))); } })
        .on("head", { element(el) { el.append(`<meta property="og:url" content="${origin}${p}">`, { html: true }); } })
        .transform(res);
    }
    return res;
  },
};
