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
 *  POST /api/question         « Une question pour Jules ? » : question d'un lecteur,
 *                             enregistrée en attente de réponse (KV, préfixe « q: »)
 *  GET  /api/questions?page=  questions publiées d'une page, avec la réponse de Jules
 *  GET  /api/admin?key=…      page privée où Jules répond, publie ou supprime
 *                             (clé : secret ADMIN_KEY, ou à défaut NEWSLETTER_KEY)
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
const EVENTS = new Set(["vue", "Site officiel", "Question", "Newsletter", "Réservation", "Partenaire", "Coffret", "Partage", "Comparateur", "Dates", "Favori", "Quiz", "Quiz terminé", "Surprise"]);
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


/* ============================================================
   QUESTIONS DES LECTEURS (« Une question pour Jules ? »)
   Stockage KV « NEWSLETTER », préfixe « q:<page>|<id> ». Rien n'est
   publié sans la réponse de Jules : les questions arrivent « en attente ».
   ============================================================ */
const PAGE = /^(hotels|guides)\/[a-z0-9-]{1,80}$/;
const adminKey = (env) => env.ADMIN_KEY || env.NEWSLETTER_KEY || "";
const isAdmin = (env, key) => !!adminKey(env) && key === adminKey(env);
const escHtml = (s) => String(s || "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const cleanText = (v, max) => String(v || "").replace(/[\u0000-\u0008\u000b-\u001f]/g, "").replace(/\r\n?/g, "\n").trim().slice(0, max);

async function listQuestions(env, prefix) {
  const out = [];
  let cursor;
  do {
    const page = await env.NEWSLETTER.list({ prefix, cursor });
    for (const k of page.keys) {
      const v = await env.NEWSLETTER.get(k.name);
      if (v) out.push({ key: k.name, ...JSON.parse(v) });
    }
    cursor = page.list_complete ? null : page.cursor;
  } while (cursor);
  return out.sort((a, b) => (b.date || "").localeCompare(a.date || ""));
}

async function askQuestion(request, env) {
  if (request.headers.get("Content-Length") > 6000) return json({ ok: false, error: "too_large" }, 413);
  let data;
  try { data = await readForm(request); } catch { return json({ ok: false, error: "bad_request" }, 400); }
  if (data["bot-field"]) return json({ ok: true });
  const page = clean(data.page, 100);
  const prenom = clean(data.prenom, 40);
  const question = cleanText(data.question, 1200);
  const email = clean(data.email, 254).toLowerCase();
  if (!PAGE.test(page)) return json({ ok: false, error: "bad_page" }, 400);
  if (prenom.length < 2) return json({ ok: false, error: "prenom" }, 400);
  if (question.length < 10) return json({ ok: false, error: "question" }, 400);
  if (email && !EMAIL.test(email)) return json({ ok: false, error: "invalid_email" }, 400);
  // Limite : une question par minute et par adresse IP
  const ip = request.headers.get("CF-Connecting-IP") || "";
  if (ip) {
    const rl = `rl:q:${ip}`;
    if (await env.NEWSLETTER.get(rl)) return json({ ok: false, error: "slow_down" }, 429);
    await env.NEWSLETTER.put(rl, "1", { expirationTtl: 60 });
  }
  const id = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;
  await env.NEWSLETTER.put(`q:${page}|${id}`, JSON.stringify({
    id, page, title: clean(data.title, 140), prenom, question, email,
    date: new Date().toISOString(), status: "pending", answer: "", answeredAt: "",
  }));
  return json({ ok: true });
}

async function publicQuestions(url, env) {
  const page = clean(url.searchParams.get("page"), 100);
  if (!PAGE.test(page)) return json({ ok: false, error: "bad_page" }, 400);
  const list = (await listQuestions(env, `q:${page}|`))
    .filter((q) => q.status === "published" && q.answer)
    .map((q) => ({ prenom: q.prenom, question: q.question, answer: q.answer, date: q.date, answeredAt: q.answeredAt }));
  return new Response(JSON.stringify({ ok: true, questions: list }), {
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "public, max-age=60" },
  });
}

async function adminAction(request, env) {
  let data;
  try { data = await readForm(request); } catch { return new Response("Requête invalide", { status: 400 }); }
  const key = String(data.key || "");
  if (!isAdmin(env, key)) return new Response("Not found", { status: 404 });
  const qkey = String(data.qkey || "");
  if (!qkey.startsWith("q:")) return new Response("Question introuvable", { status: 400 });
  const back = new Response(null, { status: 303, headers: { Location: `/api/admin?key=${encodeURIComponent(key)}&ok=1#${encodeURIComponent(qkey)}` } });
  if (data.action === "delete") { await env.NEWSLETTER.delete(qkey); return back; }
  const raw = await env.NEWSLETTER.get(qkey);
  if (!raw) return back;
  const q = JSON.parse(raw);
  q.answer = cleanText(data.answer, 3000);
  if (data.action === "publish" && q.answer) { q.status = "published"; q.answeredAt = q.answeredAt || new Date().toISOString(); }
  if (data.action === "unpublish") q.status = "pending";
  await env.NEWSLETTER.put(qkey, JSON.stringify(q));
  return back;
}

async function adminPage(url, env) {
  const key = url.searchParams.get("key") || "";
  if (!isAdmin(env, key)) return new Response("Not found", { status: 404 });
  const all = await listQuestions(env, "q:");
  const pending = all.filter((q) => q.status !== "published");
  const done = all.filter((q) => q.status === "published");
  const date = (d) => d ? new Date(d).toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" }) : "";
  const card = (q) => `
    <article class="q ${q.status}" id="${escHtml(q.key)}">
      <p class="meta"><strong>${escHtml(q.prenom)}</strong> · ${date(q.date)} · <a href="/${escHtml(q.page)}.html" target="_blank">${escHtml(q.title || q.page)}</a>
        ${q.email ? ` · <a href="mailto:${escHtml(q.email)}?subject=${encodeURIComponent("Votre question sur Nuits Singulières")}">${escHtml(q.email)}</a>` : ""}</p>
      <blockquote>${escHtml(q.question).replace(/\n/g, "<br>")}</blockquote>
      <form method="post" action="/api/admin">
        <input type="hidden" name="key" value="${escHtml(key)}"><input type="hidden" name="qkey" value="${escHtml(q.key)}">
        <label>Ma réponse<textarea name="answer" rows="5" placeholder="Votre réponse, publiée sous la question">${escHtml(q.answer)}</textarea></label>
        <div class="actions">
          <button name="action" value="publish" class="primary">${q.status === "published" ? "Mettre à jour" : "Publier la réponse"}</button>
          <button name="action" value="save">Enregistrer sans publier</button>
          ${q.status === "published" ? `<button name="action" value="unpublish">Retirer du site</button>` : ""}
          <button name="action" value="delete" class="danger" onclick="return confirm('Supprimer définitivement cette question ?')">Supprimer</button>
        </div>
      </form>
    </article>`;
  const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow"><title>Questions des lecteurs · Nuits Singulières</title>
<style>
  :root { --ink:#16201c; --soft:#46514b; --line:#e4ddd0; --bg:#f4efe6; --card:#fbf8f2; --accent:#c2643c; --forest:#24392f; }
  body { margin:0; background:var(--bg); color:var(--ink); font:16px/1.55 system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width:820px; margin:0 auto; padding:28px 18px 60px; }
  h1 { font:400 2rem Georgia, serif; margin:0 0 6px; } h2 { font:400 1.4rem Georgia, serif; margin:36px 0 12px; }
  .lead { color:var(--soft); margin:0 0 10px; } .ok { background:#eef3ee; border:1px solid #d5e2d7; padding:10px 14px; border-radius:10px; }
  .q { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:18px; margin:0 0 14px; }
  .q.pending { border-left:4px solid var(--accent); } .meta { margin:0 0 8px; font-size:.9rem; color:var(--soft); } .meta a { color:var(--soft); }
  blockquote { margin:0 0 14px; padding:10px 14px; background:#fff; border-radius:10px; }
  label { display:grid; gap:6px; font-size:.85rem; font-weight:600; } textarea { font:inherit; font-weight:400; padding:10px 12px; border:1px solid var(--line); border-radius:10px; resize:vertical; }
  .actions { display:flex; flex-wrap:wrap; gap:8px; margin-top:10px; }
  button { font:inherit; font-size:.9rem; padding:8px 14px; border-radius:999px; border:1px solid var(--line); background:#fff; cursor:pointer; }
  button.primary { background:var(--forest); color:#fff; border-color:var(--forest); } button.danger { color:#a33; }
  .empty { color:var(--soft); font-style:italic; }
</style></head><body><main>
  <h1>Questions des lecteurs</h1>
  <p class="lead">Les questions arrivent ici, en attente. Rien n'est publié tant que vous n'avez pas répondu et cliqué sur « Publier la réponse ». Gardez cette page dans vos favoris : son adresse contient votre clé, ne la partagez pas.</p>
  ${url.searchParams.get("ok") ? `<p class="ok">C'est enregistré. Sur le site, la mise à jour peut prendre une minute.</p>` : ""}
  <h2>En attente (${pending.length})</h2>
  ${pending.map(card).join("") || `<p class="empty">Aucune question en attente.</p>`}
  <h2>Publiées (${done.length})</h2>
  ${done.map(card).join("") || `<p class="empty">Aucune réponse publiée pour l'instant.</p>`}
</main></body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Robots-Tag": "noindex" } });
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
    if (url.pathname === "/api/question") {
      if (request.method !== "POST") return json({ ok: false, error: "method" }, 405);
      return askQuestion(request, env);
    }
    if (url.pathname === "/api/questions") return publicQuestions(url, env);
    if (url.pathname === "/api/admin") return request.method === "POST" ? adminAction(request, env) : adminPage(url, env);
    if (url.pathname.startsWith("/api/")) return new Response("Not found", { status: 404 });
    return env.ASSETS.fetch(request);
  },
};
