// Rendu PNG des instantanés JSON (tools/screens/capture.luau) avec les vraies polices, rapports de
// contrôle par écran et planche contact.
//
//   node tools/screens/render.mjs --in <dossier JSON> --out <dossier de sortie> [--filter upgrades]
//        [--folders tv1080-fr,phone-en] [--jobs 4] [--no-png]
//
// Sorties (dans --out) :
//   <appareil>-<langue>/<écran>.png              capture à la résolution de l'appareil
//   <appareil>-<langue>/<écran>.billboards.png   panneaux du monde (BillboardGui), s'il y en a
//   <appareil>-<langue>/<écran>.report.json      problèmes relevés sur ce qui a été dessiné
//   thumbs/<appareil>-<langue>/<écran>.jpg        vignette de la planche contact
//   summary.json                                  totaux par type, pires problèmes, problèmes groupés
//   index.html                                    planche contact (filtres, vignettes, rapports)
// Le dessin et les contrôles sont dans tools/screens/renderer.js (exécuté dans Chromium).

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { FONTS, FALLBACK_STACK, launch, fontPage, ensureFonts } from './fonts.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

function parseArgs(argv) {
  const out = { jobs: 4, png: true };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--no-png') out.png = false;
    else if (a.startsWith('--')) {
      out[a.slice(2)] = argv[i + 1];
      i++;
    }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
if (!args.in || !args.out) {
  console.error('usage : node tools/screens/render.mjs --in <dossier JSON> --out <dossier>');
  process.exit(2);
}
const IN = path.resolve(args.in);
const OUT = path.resolve(args.out);
const JOBS = Math.max(1, Number(args.jobs) || 4);
const onlyFolders = args.folders ? new Set(String(args.folders).split(',')) : null;

// tables Lua vides → {} en JSON : on les relit comme des listes
const arr = (x) => (Array.isArray(x) ? x : x && typeof x === 'object' ? Object.values(x) : []);

function normalize(dump) {
  dump.nodes = arr(dump.nodes);
  dump.guis = arr(dump.guis);
  dump.luauIssues = arr(dump.luauIssues);
  dump.billboards = arr(dump.billboards).map((b) => ({ ...b, nodes: arr(b.nodes) }));
  const fix = (n) => {
    if (n.text && n.text.fit) {
      n.text.fit.lines = arr(n.text.fit.lines);
      n.text.fit.issues = arr(n.text.fit.issues);
      n.text.fit.pad = arr(n.text.fit.pad);
    }
    if (n.grad) {
      n.grad.colors = arr(n.grad.colors);
      n.grad.trans = arr(n.grad.trans);
    }
  };
  dump.nodes.forEach(fix);
  dump.billboards.forEach((b) => b.nodes.forEach(fix));
  return dump;
}

function textsOf(dump) {
  let s = '';
  for (const n of dump.nodes) if (n.text) s += n.text.shown || '';
  for (const b of dump.billboards) for (const n of b.nodes) if (n.text) s += n.text.shown || '';
  return s;
}

const WEIGHT = {
  rawKey: 6,
  placeholder: 6,
  defaultText: 5,
  overflow: 5,
  clipped: 4,
  offscreen: 4,
  question: 3,
  splitWord: 3,
  overlap: 3,
  unsafe: 3,
  small: 3,
  empty: 2,
  contrast: 2,
  tinted: 3,
  truncated: 1,
  smallFixed: 1,
  capRisk: 0,
  selection: 4,
  noChange: 1,
};
function score(it) {
  let s = WEIGHT[it.kind] ?? 1;
  if (it.kind === 'truncated' && it.severe) s = 4;
  if ((it.kind === 'small' || it.kind === 'smallFixed') && it.size) s += Math.max(0, 3 - it.size / 6);
  if (it.kind === 'contrast' && it.ratio) s += 3 - it.ratio;
  return s;
}

function mkdirp(p) {
  fs.mkdirSync(p, { recursive: true });
}

function writeDataUrl(file, dataUrl) {
  const b64 = dataUrl.slice(dataUrl.indexOf(',') + 1);
  fs.writeFileSync(file, Buffer.from(b64, 'base64'));
}

async function main() {
  const manifest = JSON.parse(fs.readFileSync(path.join(IN, 'manifest.json'), 'utf8'));
  let cases = arr(manifest.cases);
  if (onlyFolders) cases = cases.filter((c) => onlyFolders.has(c.folder));
  if (args.filter) cases = cases.filter((c) => c.screen.includes(args.filter));
  mkdirp(OUT);

  const browser = await launch();
  const context = await browser.newContext();
  const sample =
    'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz0123456789 .,;:!?«»’\'"()[]+-×/%€$£' +
    'éèêëàâäîïôöùûüçÉÈÊÀÂÎÔÙÛÇœŒ…—–·★☆✦✧✕○□△◆●↑↓←→▲▼◀▶✓✔✗☄☁✺⚡♥❤⏱⌛∞';
  const pages = [];
  for (let i = 0; i < JOBS; i++) {
    const page = await fontPage(context);
    await ensureFonts(page, sample);
    await page.addScriptTag({ path: path.join(HERE, 'renderer.js') });
    await page.evaluate(({ fonts, fallback }) => window.CC.init(fonts, fallback), {
      fonts: FONTS,
      fallback: FALLBACK_STACK,
    });
    pages.push(page);
  }

  const results = [];
  let next = 0;
  let done = 0;
  const t0 = Date.now();
  async function worker(page) {
    while (next < cases.length) {
      const c = cases[next++];
      const file = path.join(IN, c.folder, `${c.screen}.json`);
      let dump;
      try {
        dump = normalize(JSON.parse(fs.readFileSync(file, 'utf8')));
      } catch (e) {
        console.error(`✗ ${c.folder}/${c.screen} : ${e.message}`);
        continue;
      }
      await ensureFonts(page, textsOf(dump));
      const r = await page.evaluate(
        ({ dump, png, capMode }) => {
          const main = window.CC.render(dump, { png, thumb: 360, capMode });
          const bb = window.CC.renderBillboards(dump);
          return { main, bb };
        },
        { dump, png: args.png, capMode: args.cap || 'layout' },
      );
      const dir = path.join(OUT, c.folder);
      const tdir = path.join(OUT, 'thumbs', c.folder);
      mkdirp(dir);
      mkdirp(tdir);
      if (r.main.png) writeDataUrl(path.join(dir, `${c.screen}.png`), r.main.png);
      if (r.main.thumb) writeDataUrl(path.join(tdir, `${c.screen}.jpg`), r.main.thumb);
      if (r.bb && r.bb.png && args.png) writeDataUrl(path.join(dir, `${c.screen}.billboards.png`), r.bb.png);
      const items = [...r.main.items, ...((r.bb && r.bb.items) || [])].map((it) => ({ ...it, score: +score(it).toFixed(2) }));
      items.sort((a, b) => b.score - a.score);
      const counts = {};
      for (const it of items) counts[it.kind] = (counts[it.kind] || 0) + 1;
      const report = {
        id: c.screen,
        folder: c.folder,
        profile: dump.profile,
        profileLabel: dump.profileLabel,
        lang: dump.lang,
        state: dump.state,
        viewport: dump.viewport,
        rootScale: dump.rootScale,
        minReadablePx: +((dump.minReadable || 28) * (dump.rootScale || 1)).toFixed(2),
        selected: dump.selected ? dump.selected.path : null,
        captureError: dump.error || null,
        texts: r.main.textCount,
        calibration: r.main.calib,
        counts,
        items,
        png: `${c.screen}.png`,
        billboards: r.bb ? `${c.screen}.billboards.png` : null,
      };
      fs.writeFileSync(path.join(dir, `${c.screen}.report.json`), JSON.stringify(report, null, 1));
      results.push(report);
      done++;
      if (done % 50 === 0 || done === cases.length)
        console.log(`${String(done).padStart(5)} / ${cases.length} écrans rendus (${((Date.now() - t0) / 1000).toFixed(0)} s)`);
    }
  }
  await Promise.all(pages.map(worker));
  await browser.close();

  // ---------------------------------------------------------------- synthèse
  results.sort((a, b) => (a.folder + a.id).localeCompare(b.folder + b.id));
  const totals = {};
  for (const r of results) for (const [k, v] of Object.entries(r.counts)) totals[k] = (totals[k] || 0) + v;
  // problèmes groupés : même type, même objet (indices de listes neutralisés), tous formats
  const groups = new Map();
  const norm = (p) => p.replace(/\d+/g, '#');
  for (const r of results) {
    for (const it of r.items) {
      if (it.kind === 'capRisk') continue;
      const key = `${it.kind}|${norm(it.path)}`;
      let g = groups.get(key);
      if (!g) {
        g = { kind: it.kind, path: norm(it.path), count: 0, score: 0, formats: new Set(), screens: new Set(), example: null };
        groups.set(key, g);
      }
      g.count++;
      g.formats.add(r.folder);
      g.screens.add(r.id);
      if (!g.example || it.score > g.example.score) g.example = { ...it, folder: r.folder, screen: r.id };
      g.score = Math.max(g.score, it.score);
    }
  }
  const grouped = [...groups.values()]
    .map((g) => ({ ...g, formats: [...g.formats].sort(), screens: [...g.screens].sort() }))
    .sort((a, b) => b.score * Math.log2(1 + b.count) - a.score * Math.log2(1 + a.count));
  const worst = results
    .flatMap((r) => r.items.filter((i) => i.kind !== 'capRisk').map((i) => ({ ...i, folder: r.folder, screen: r.id })))
    .sort((a, b) => b.score - a.score)
    .slice(0, 200);
  const calibration = { n: 0, same: 0, off1: 0, off2: 0, max: 0 };
  for (const r of results) {
    const c = r.calibration || {};
    calibration.n += c.n || 0;
    calibration.same += c.same || 0;
    calibration.off1 += c.off1 || 0;
    calibration.off2 += c.off2 || 0;
    calibration.max = Math.max(calibration.max, c.max || 0);
  }
  const summary = {
    generated: new Date().toISOString(),
    capMode: args.cap || 'layout',
    calibration,
    screens: [...new Set(results.map((r) => r.id))],
    formats: [...new Set(results.map((r) => r.folder))],
    rendered: results.length,
    totals,
    grouped: grouped.slice(0, 400),
    worst,
    perScreen: results.map((r) => ({ folder: r.folder, id: r.id, counts: r.counts, texts: r.texts, error: r.captureError })),
  };
  fs.writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(summary, null, 1));
  fs.writeFileSync(path.join(OUT, 'index.html'), indexHtml(summary));
  console.log(`\n${results.length} écrans → ${OUT}`);
  console.log('Totaux par type :', totals);
  console.log(
    `Calibrage TextScaled Luau/navigateur : ${calibration.same} identiques, ${calibration.off1} à 1 px, ${calibration.off2} au-delà (max ${calibration.max}) sur ${calibration.n}`,
  );
  console.log(`Planche contact : ${path.join(OUT, 'index.html')}`);
}

function indexHtml(summary) {
  const data = JSON.stringify({
    totals: summary.totals,
    formats: summary.formats,
    perScreen: summary.perScreen,
    grouped: summary.grouped.slice(0, 120).map((g) => ({
      kind: g.kind,
      path: g.path,
      count: g.count,
      formats: g.formats,
      screens: g.screens.slice(0, 12),
      example: g.example,
    })),
  }).replace(/</g, '\\u003c');
  return `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Captures Raise a Squishy</title>
<style>
:root{--bg:#14121c;--panel:#1e1b29;--text:#ece9f5;--dim:#a39cb8;--accent:#ffcf5a;--bad:#ff6b7a;--ok:#6be3a4}
body{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 system-ui,sans-serif}
header{padding:16px;position:sticky;top:0;background:var(--bg);z-index:2;border-bottom:1px solid #2c2840}
h1{margin:0 0 8px;font-size:20px}
.totals span{display:inline-block;margin:2px 6px 2px 0;padding:2px 8px;border-radius:10px;background:var(--panel)}
.controls{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}
select,input{background:var(--panel);color:var(--text);border:1px solid #3a3550;border-radius:6px;padding:6px}
main{padding:16px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px}
.card{background:var(--panel);border-radius:8px;overflow:hidden}
.card img{width:100%;display:block;background:#000}
.card .meta{padding:6px 8px;font-size:12px}
.card a{color:var(--text);text-decoration:none}
.badge{display:inline-block;margin:2px 3px 0 0;padding:0 6px;border-radius:8px;background:#3a2030;color:var(--bad);font-size:11px}
.clean{color:var(--ok);font-size:11px}
details{margin:12px 0;background:var(--panel);border-radius:8px;padding:8px 12px}
table{border-collapse:collapse;width:100%;font-size:12px}
td,th{border-bottom:1px solid #2c2840;padding:4px;text-align:left;vertical-align:top}
code{color:var(--accent);word-break:break-all}
@media (max-width:600px){.grid{grid-template-columns:1fr 1fr}}
</style></head><body>
<header><h1>Captures hors moteur : Raise a Squishy</h1>
<div class="totals" id="totals"></div>
<div class="controls">
<select id="fmt"><option value="">Tous les formats</option></select>
<input id="q" placeholder="filtre d'écran (upgrades, shop…)">
<select id="only"><option value="">Tous les écrans</option><option value="bad">Avec problèmes</option></select>
<select id="kind"><option value="">Tous les types</option></select>
</div></header>
<main>
<details><summary>Problèmes groupés (même objet, tous formats) : les plus graves d'abord</summary>
<table id="grouped"><thead><tr><th>type</th><th>objet</th><th>nb</th><th>formats</th><th>exemple</th></tr></thead><tbody></tbody></table></details>
<div class="grid" id="grid"></div>
</main>
<script>
const D=${data};
const $=s=>document.querySelector(s);
const HELP={overflow:"texte plus grand que sa boîte à la taille qu'utiliserait Roblox",clipped:"texte coupé par un parent (ClipsDescendants, CanvasGroup)",truncated:"« … » : texte tronqué",small:"texte sous le minimum lisible (28 px de référence × échelle de Root)",smallFixed:"taille fixe sous le minimum lisible",splitWord:"mot coupé en deux par le retour à la ligne",orphan:"ponctuation seule sur sa ligne",offscreen:"objet hors de l'écran",unsafe:"hors de la zone sûre TV (5 %)",overlap:"chevauchement de textes ou de boutons",contrast:"contraste < 3",tinted:"texte teinté par l'UIGradient d'un CanvasGroup",empty:"boîte visible sans texte",rawKey:"clé de traduction affichée",placeholder:"variable {x} affichée",question:"« ? » à la place d'une donnée",defaultText:"texte jamais posé (« Label »)",noChange:"« 60 → 60 » : flèche sans changement",capRisk:"information : taille qui dépend de l'ordre bornes TextScaled / UIScale (à vérifier sur console)",selection:"curseur de sélection invisible, hors écran ou caché par un parent"};
$('#totals').innerHTML=Object.entries(D.totals).sort((a,b)=>(a[0]==='capRisk')-(b[0]==='capRisk')||b[1]-a[1]).map(([k,v])=>'<span title="'+(HELP[k]||'')+'">'+k+(k==='capRisk'?' (info)':'')+' : '+v+'</span>').join('');
for(const f of D.formats){const o=document.createElement('option');o.value=f;o.textContent=f;$('#fmt').appendChild(o);}
for(const k of Object.keys(D.totals).sort()){const o=document.createElement('option');o.value=k;o.textContent=k;$('#kind').appendChild(o);}
const esc=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
$('#grouped tbody').innerHTML=D.grouped.map(g=>'<tr><td>'+g.kind+'</td><td><code>'+esc(g.path)+'</code></td><td>'+g.count+'</td><td>'+g.formats.length+' : '+esc(g.formats.join(', '))+'</td><td><a href="'+g.example.folder+'/'+g.example.screen+'.png" target="_blank">'+esc(g.example.folder+'/'+g.example.screen)+'</a><br>'+esc(g.example.text?('« '+g.example.text.slice(0,60)+' » '):'')+esc(g.example.message)+'</td></tr>').join('');
function draw(){
 const f=$('#fmt').value,q=$('#q').value.trim(),only=$('#only').value,kind=$('#kind').value;
 const rows=D.perScreen.filter(s=>(!f||s.folder===f)&&(!q||s.id.includes(q))&&(!only||Object.keys(s.counts).some(k=>k!=='capRisk'))&&(!kind||s.counts[kind]));
 $('#grid').innerHTML=rows.map(s=>{const b=Object.entries(s.counts).filter(([k])=>k!=='capRisk').map(([k,v])=>'<span class="badge">'+k+' '+v+'</span>').join('');
  return '<div class="card"><a href="'+s.folder+'/'+s.id+'.png" target="_blank"><img loading="lazy" src="thumbs/'+s.folder+'/'+s.id+'.jpg" alt="'+esc(s.id)+'"></a><div class="meta"><a href="'+s.folder+'/'+s.id+'.report.json" target="_blank"><b>'+esc(s.id)+'</b> · '+s.folder+'</a><br>'+(b||'<span class="clean">aucun problème</span>')+(s.error?'<br><span class="badge">erreur de capture</span>':'')+'</div></div>';}).join('');
}
for(const id of ['#fmt','#q','#only','#kind'])$(id).addEventListener('input',draw);
draw();
</script></body></html>`;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
