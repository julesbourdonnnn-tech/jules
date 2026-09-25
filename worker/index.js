/*
 * Worker Cloudflare du site : sert les fichiers statiques et enregistre les
 * inscriptions à la newsletter.
 *
 *  POST /api/newsletter       enregistre une adresse (stockage KV « NEWSLETTER »)
 *  GET  /api/newsletter.csv   export des inscrits, protégé par la clé secrète
 *                             NEWSLETTER_KEY (à créer dans Cloudflare :
 *                             Workers → jules → Paramètres → Variables et secrets)
 *                             ex. https://nuitsinguliere.com/api/newsletter.csv?key=…
 *  POST /api/hit              mesure d'audience sans cookie (base D1 « STATS ») :
 *                             pages vues, provenance, clics vers les réservations
 * Tout le reste est servi tel quel depuis les fichiers du site.
 */
const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
const clean = (v, max) => String(v || "").replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, max);

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } });

async function readForm(request) {
  const type = request.headers.get("Content-Type") || "";
  if (type.includes("application/json")) return await request.json();
  const form = await request.formData();
  return Object.fromEntries(form.entries());
}

async function subscribe(request, env) {
  if (request.headers.get("Content-Length") > 4096) return json({ ok: false, error: "too_large" }, 413);
  let data;
  try { data = await readForm(request); } catch { return json({ ok: false, error: "bad_request" }, 400); }
  // Piège à robots : ce champ est invisible pour les humains
  if (data["bot-field"]) return json({ ok: true });
  const email = clean(data.email, 254).toLowerCase();
  if (!EMAIL.test(email)) return json({ ok: false, error: "invalid_email" }, 400);
  const key = `sub:${email}`;
  if (await env.NEWSLETTER.get(key)) return json({ ok: true, already: true });
  await env.NEWSLETTER.put(key, JSON.stringify({
    email,
    origine: clean(data.origine, 80),
    source: clean(data.source, 40),
    date: new Date().toISOString(),
    pays: (request.cf && request.cf.country) || "",
  }));
  try { await record(env, request, { type: "Newsletter", path: clean(data.origine, 200), source: clean(data.source, 40) }); } catch { /* sans conséquence */ }
  return json({ ok: true });
}

// Événements acceptés pour la mesure d'audience (le reste est ignoré)
const EVENTS = new Set(["vue", "Réservation", "Partenaire", "Coffret", "Partage", "Comparateur", "Dates", "Favori", "Quiz", "Quiz terminé", "Surprise"]);
const BOT = /bot|crawl|spider|slurp|preview|headless|lighthouse|facebookexternalhit|pingdom|monitor/i;

async function record(env, request, row) {
  if (!env.STATS) return;
  const now = new Date();
  const cf = request.cf || {};
  await env.STATS.prepare(
    "INSERT INTO events (ts, day, type, path, hotel, ref, source, country, device, visit) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  ).bind(now.toISOString(), now.toISOString().slice(0, 10), row.type, row.path || "", row.hotel || "", row.ref || "", row.source || "",
    cf.country || "", row.device || "", row.visit ? 1 : 0).run();
}

async function hit(request, env) {
  const ok = new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });
  if (request.headers.get("Content-Length") > 2048 || BOT.test(request.headers.get("User-Agent") || "")) return ok;
  let d;
  try { d = JSON.parse(await request.text()); } catch { return ok; }
  const type = clean(d.t, 30);
  if (!EVENTS.has(type)) return ok;
  const w = Number(d.w) || 0;
  try {
    await record(env, request, {
      type,
      path: clean(d.p, 200),
      hotel: clean(d.h, 80),
      ref: clean(d.r, 100).toLowerCase(),
      source: clean(d.s, 40),
      device: w ? (w < 760 ? "mobile" : w < 1100 ? "tablette" : "ordinateur") : "",
      visit: d.v === 1,
    });
  } catch { /* la mesure d'audience ne doit jamais gêner le site */ }
  return ok;
}

async function exportCsv(url, env) {
  if (!env.NEWSLETTER_KEY || url.searchParams.get("key") !== env.NEWSLETTER_KEY) return new Response("Not found", { status: 404 });
  const rows = [["email", "date", "origine", "source", "pays"]];
  let cursor;
  do {
    const page = await env.NEWSLETTER.list({ prefix: "sub:", cursor });
    for (const k of page.keys) {
      const v = JSON.parse((await env.NEWSLETTER.get(k.name)) || "{}");
      rows.push([v.email || k.name.slice(4), v.date || "", v.origine || "", v.source || "", v.pays || ""]);
    }
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  const csv = rows.map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(",")).join("\n");
  return new Response(csv, {
    headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": 'attachment; filename="newsletter.csv"', "Cache-Control": "no-store" },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/newsletter") {
      if (request.method !== "POST") return json({ ok: false, error: "method" }, 405);
      return subscribe(request, env);
    }
    if (url.pathname === "/api/newsletter.csv") return exportCsv(url, env);
    if (url.pathname === "/api/hit") return request.method === "POST" ? hit(request, env) : new Response("Not found", { status: 404 });
    if (url.pathname.startsWith("/api/")) return new Response("Not found", { status: 404 });
    return env.ASSETS.fetch(request);
  },
};
