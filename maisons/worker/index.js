/*
 * Worker Cloudflare du site Sable & Pierre : sert les fichiers du site et
 * deux petites adresses :
 *
 *  GET  /api/calendrier/lacanau   nuits déjà réservées, lues dans le calendrier
 *  GET  /api/calendrier/bordeaux  Airbnb (lien iCal secret, voir README.md).
 *                                 Réponse : { ok, booked: [["AAAA-MM-JJ","AAAA-MM-JJ"], …] }
 *                                 (date de départ exclue). Mise en cache 30 min.
 *
 *  POST /api/demande              demande de réservation directe : enregistrée
 *                                 (stockage KV « DEMANDES ») et envoyée sur ton
 *                                 téléphone si NOTIFY_URL est renseigné.
 *  GET  /api/demandes.csv?key=…   export des demandes (clé secrète DEMANDES_KEY).
 *
 * Sans réglage, /api/calendrier répond { ok: false } (le calendrier reste
 * utilisable, les dates sont vérifiées sur Airbnb) et /api/demande répond 503
 * (le formulaire ouvre alors un e-mail pré-rempli : aucune demande perdue).
 */
const HOUSES = { lacanau: "ICAL_LACANAU", bordeaux: "ICAL_BORDEAUX" };
const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const clean = (v, max) => String(v ?? "").replace(/[\u0000-\u0008\u000b-\u001f<>]/g, "").trim().slice(0, max);
const FIELDS = { maison: 60, arrivee: 10, depart: 10, nuits: 4, adultes: 3, enfants: 3, bebes: 3, nom: 80, email: 254, telephone: 30, message: 2000, page: 80 };

const json = (body, status = 200, extra = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...extra } });

/* ---------- Calendrier ---------- */
// Lit les événements d'un fichier iCal (Airbnb : une réservation ou un blocage par VEVENT)
function parseIcal(text) {
  const lines = text.replace(/\r?\n[ \t]/g, "").split(/\r?\n/);
  const out = [];
  let start = null;
  let end = null;
  const day = (v) => {
    const m = /(\d{4})(\d{2})(\d{2})/.exec(v || "");
    return m ? `${m[1]}-${m[2]}-${m[3]}` : null;
  };
  for (const line of lines) {
    if (line.startsWith("BEGIN:VEVENT")) { start = null; end = null; }
    else if (line.startsWith("DTSTART")) start = day(line.split(":").pop());
    else if (line.startsWith("DTEND")) end = day(line.split(":").pop());
    else if (line.startsWith("END:VEVENT") && start) {
      if (!end || end <= start) {
        // Sans fin : une seule nuit
        const d = new Date(`${start}T00:00:00Z`);
        d.setUTCDate(d.getUTCDate() + 1);
        end = d.toISOString().slice(0, 10);
      }
      out.push([start, end]);
    }
  }
  const today = new Date().toISOString().slice(0, 10);
  return out.filter(([, e]) => e > today).sort((a, b) => (a[0] < b[0] ? -1 : 1));
}

async function calendar(house, env, ctx, request) {
  const url = env[HOUSES[house]];
  if (!url) return json({ ok: false, error: "not_configured" }, 200, { "Cache-Control": "public, max-age=300" });
  const cache = caches.default;
  const cacheKey = new Request(new URL(`/api/calendrier/${house}`, request.url).toString());
  const hit = await cache.match(cacheKey);
  if (hit) return hit;
  try {
    const r = await fetch(url, { headers: { "User-Agent": "Sable-et-Pierre/1.0 (+calendrier)" }, cf: { cacheTtl: 900 } });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const booked = parseIcal(await r.text());
    const res = json({ ok: true, booked, updated: new Date().toISOString() }, 200, { "Cache-Control": "public, max-age=1800" });
    ctx.waitUntil(cache.put(cacheKey, res.clone()));
    return res;
  } catch (e) {
    return json({ ok: false, error: "fetch_failed" }, 200, { "Cache-Control": "public, max-age=120" });
  }
}

/* ---------- Demandes de réservation ---------- */
async function request_(request, env, ctx) {
  if (!env.DEMANDES) return json({ ok: false, error: "storage_not_configured" }, 503);
  if (Number(request.headers.get("Content-Length")) > 8192) return json({ ok: false, error: "too_large" }, 413);
  let data;
  try { data = await request.json(); } catch { return json({ ok: false, error: "bad_request" }, 400); }
  if (data["bot-field"]) return json({ ok: true });
  const d = {};
  for (const [k, max] of Object.entries(FIELDS)) d[k] = clean(data[k], max);
  d.email = d.email.toLowerCase();
  if (!d.nom || !EMAIL.test(d.email) || !DATE.test(d.arrivee) || !DATE.test(d.depart) || d.depart <= d.arrivee) {
    return json({ ok: false, error: "invalid" }, 400);
  }
  d.date = new Date().toISOString();
  d.pays = (request.cf && request.cf.country) || "";
  await env.DEMANDES.put(`demande:${d.date}:${crypto.randomUUID().slice(0, 8)}`, JSON.stringify(d));

  // Alerte sur téléphone (facultative) : ntfy.sh, Discord ou Slack
  if (env.NOTIFY_URL) {
    const voyageurs = `${d.adultes} adulte(s)${Number(d.enfants) ? `, ${d.enfants} enfant(s)` : ""}${Number(d.bebes) ? `, ${d.bebes} bébé(s)` : ""}`;
    const text = `Demande : ${d.maison}\nDu ${d.arrivee} au ${d.depart} (${d.nuits} nuits) · ${voyageurs}\n${d.nom} · ${d.telephone || "pas de tél."} · ${d.email}\n${d.message}`;
    const isDiscord = env.NOTIFY_URL.includes("discord.com");
    const isSlack = env.NOTIFY_URL.includes("hooks.slack.com");
    const body = isDiscord ? JSON.stringify({ content: text }) : isSlack ? JSON.stringify({ text }) : text;
    const headers = isDiscord || isSlack ? { "Content-Type": "application/json" } : { Title: "Sable & Pierre : nouvelle demande", Tags: "house" };
    ctx.waitUntil(fetch(env.NOTIFY_URL, { method: "POST", headers, body }).catch(() => {}));
  }
  return json({ ok: true });
}

async function exportCsv(url, env) {
  if (!env.DEMANDES || !env.DEMANDES_KEY || url.searchParams.get("key") !== env.DEMANDES_KEY) return new Response("Not found", { status: 404 });
  const cols = ["date", ...Object.keys(FIELDS).filter((k) => k !== "page"), "pays"];
  const rows = [cols];
  let cursor;
  do {
    const page = await env.DEMANDES.list({ prefix: "demande:", cursor });
    for (const k of page.keys) {
      const v = JSON.parse((await env.DEMANDES.get(k.name)) || "{}");
      rows.push(cols.map((c) => v[c] || ""));
    }
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  const csv = "﻿" + rows.map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(";")).join("\n");
  return new Response(csv, {
    headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": 'attachment; filename="demandes-sable-et-pierre.csv"', "Cache-Control": "no-store" },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const cal = /^\/api\/calendrier\/(lacanau|bordeaux)$/.exec(url.pathname);
    if (cal) return calendar(cal[1], env, ctx, request);
    if (url.pathname === "/api/demande") {
      if (request.method !== "POST") return json({ ok: false, error: "method" }, 405);
      return request_(request, env, ctx);
    }
    if (url.pathname === "/api/demandes.csv") return exportCsv(url, env);
    if (url.pathname.startsWith("/api/")) return new Response("Not found", { status: 404 });
    return env.ASSETS.fetch(request);
  },
};
