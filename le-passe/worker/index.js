/*
 * Worker Cloudflare du site Le Passe : sert les fichiers statiques et reçoit
 * les demandes du formulaire « Le bon ».
 *
 *  POST /api/contact          enregistre une demande (stockage KV « LEADS »)
 *                             et prévient Jules sur son téléphone si NOTIFY_URL
 *                             est renseigné (voir README.md).
 *  GET  /api/demandes.csv     export des demandes, protégé par la clé secrète
 *                             LEADS_KEY : https://…/api/demandes.csv?key=…
 *
 * Si le stockage KV n'est pas encore branché, /api/contact répond 503 et le
 * formulaire ouvre à la place un e-mail pré-rempli : aucune demande perdue.
 */
const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,24}$/;
const clean = (v, max) => String(v || "").replace(/[\u0000-\u0008\u000b-\u001f<>]/g, "").trim().slice(0, max);
const FIELDS = { restaurant: 120, ville: 80, nom: 80, telephone: 30, email: 254, type: 60, aujourdhui: 60, offre: 60, rappel: 160, message: 2000, page: 80 };

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } });

async function contact(request, env, ctx) {
  if (!env.LEADS) return json({ ok: false, error: "storage_not_configured" }, 503);
  if (Number(request.headers.get("Content-Length")) > 8192) return json({ ok: false, error: "too_large" }, 413);
  let data;
  try { data = await request.json(); } catch { return json({ ok: false, error: "bad_request" }, 400); }
  if (data["bot-field"]) return json({ ok: true });
  const lead = {};
  for (const [k, max] of Object.entries(FIELDS)) lead[k] = clean(data[k], max);
  lead.email = lead.email.toLowerCase();
  if (!lead.restaurant || !lead.nom || !EMAIL.test(lead.email)) return json({ ok: false, error: "invalid" }, 400);
  lead.date = new Date().toISOString();
  lead.pays = (request.cf && request.cf.country) || "";
  await env.LEADS.put(`lead:${lead.date}:${crypto.randomUUID().slice(0, 8)}`, JSON.stringify(lead));

  // Notification sur téléphone (facultative) : ntfy.sh, Discord, Slack…
  if (env.NOTIFY_URL) {
    const text = `Nouveau bon : ${lead.restaurant}${lead.ville ? ` (${lead.ville})` : ""}\n${lead.nom} · ${lead.telephone || "pas de tél."} · ${lead.email}\nOffre : ${lead.offre || "—"} · Rappel : ${lead.rappel || "—"}\n${lead.message}`;
    const isDiscord = env.NOTIFY_URL.includes("discord.com");
    const isSlack = env.NOTIFY_URL.includes("hooks.slack.com");
    const body = isDiscord ? JSON.stringify({ content: text }) : isSlack ? JSON.stringify({ text }) : text;
    const headers = isDiscord || isSlack ? { "Content-Type": "application/json" } : { Title: "Le Passe : nouveau bon", Tags: "bell" };
    ctx.waitUntil(fetch(env.NOTIFY_URL, { method: "POST", headers, body }).catch(() => {}));
  }
  return json({ ok: true });
}

async function exportCsv(url, env) {
  if (!env.LEADS || !env.LEADS_KEY || url.searchParams.get("key") !== env.LEADS_KEY) return new Response("Not found", { status: 404 });
  const cols = ["date", ...Object.keys(FIELDS).filter((k) => k !== "page"), "pays"];
  const rows = [cols];
  let cursor;
  do {
    const page = await env.LEADS.list({ prefix: "lead:", cursor });
    for (const k of page.keys) {
      const v = JSON.parse((await env.LEADS.get(k.name)) || "{}");
      rows.push(cols.map((c) => v[c] || ""));
    }
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  const csv = "﻿" + rows.map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(";")).join("\n");
  return new Response(csv, {
    headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": 'attachment; filename="demandes-le-passe.csv"', "Cache-Control": "no-store" },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/api/contact") {
      if (request.method !== "POST") return json({ ok: false, error: "method" }, 405);
      return contact(request, env, ctx);
    }
    if (url.pathname === "/api/demandes.csv") return exportCsv(url, env);
    if (url.pathname.startsWith("/api/")) return new Response("Not found", { status: 404 });
    return env.ASSETS.fetch(request);
  },
};
