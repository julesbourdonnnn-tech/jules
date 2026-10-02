/*
 * Calcul du prix d'un séjour, à partir de js/tarifs.js.
 * Utilisé à l'identique par le site et par le serveur (worker/index.js) :
 * le montant payé est toujours recalculé côté serveur.
 */
globalThis.SP_PRICE = function (house, arrivee, depart, adultes) {
  const T = (globalThis.TARIFS || {})[house];
  const res = { ready: false, nights: 0, lines: [], total: 0, cents: 0 };
  if (!T) return res;
  const parse = (s) => { const [y, m, d] = s.split("-").map(Number); return Date.UTC(y, m - 1, d); };
  const DAY = 86400000;
  const a = parse(arrivee);
  const b = parse(depart);
  const n = Math.round((b - a) / DAY);
  if (!(n > 0)) return res;
  res.nights = n;
  // Prix de chaque nuit selon la saison
  const inSeason = (md, s) => (s.du <= s.au ? md >= s.du && md <= s.au : md >= s.du || md <= s.au);
  const groups = [];
  for (let i = 0; i < n; i++) {
    const d = new Date(a + i * DAY);
    const md = `${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
    const s = (T.saisons || []).find((x) => x && x.nuit != null && inSeason(md, x));
    const price = s ? s.nuit : T.nuit;
    if (price == null) return res; // tarif manquant : prix sur demande
    const last = groups[groups.length - 1];
    if (last && last.price === price) last.count++;
    else groups.push({ price, count: 1 });
  }
  const eur = (v) => Math.round(v * 100);
  let cents = 0;
  groups.forEach((g) => {
    const amount = eur(g.price) * g.count;
    cents += amount;
    res.lines.push({ label: `${g.price.toLocaleString("fr-FR")} € × ${g.count} nuit${g.count > 1 ? "s" : ""}`, cents: amount });
  });
  if (T.menage) { cents += eur(T.menage); res.lines.push({ label: "Ménage", cents: eur(T.menage) }); }
  const ad = Math.max(1, Number(adultes) || 1);
  if (T.taxeSejour) {
    const tax = eur(T.taxeSejour) * ad * n;
    cents += tax;
    res.lines.push({ label: `Taxe de séjour (${ad} adulte${ad > 1 ? "s" : ""} × ${n} nuit${n > 1 ? "s" : ""})`, cents: tax });
  }
  res.ready = true;
  res.cents = cents;
  res.total = cents / 100;
  return res;
};
globalThis.SP_EUR = (cents) => `${(cents / 100).toLocaleString("fr-FR", { minimumFractionDigits: cents % 100 ? 2 : 0, maximumFractionDigits: 2 })} €`;
