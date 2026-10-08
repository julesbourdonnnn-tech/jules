/*
 * Calcul du prix d'un séjour.
 * - Si un prix de nuit est saisi dans js/tarifs.js, il est utilisé.
 * - Sinon, le prix est celui d'Airbnb pour ces dates (js/tarifs-airbnb.js,
 *   relevé automatiquement) : nuits, frais du séjour et taxes.
 * La remise « réservation directe » s'applique ensuite.
 * Utilisé à l'identique par le site et par le serveur (worker/index.js) :
 * le montant payé est toujours recalculé côté serveur.
 */
globalThis.SP_PRICE = function (house, arrivee, depart, adultes) {
  const T = (globalThis.TARIFS || {})[house];
  const res = { ready: false, nights: 0, lines: [], total: 0, cents: 0 };
  if (!T) return res;
  const manual = T.nuit != null || (T.saisons || []).some((x) => x && x.nuit != null);
  const A = !manual && (globalThis.TARIFS_AIRBNB || {})[house];
  if (!manual && !(A && A.periodes && A.periodes.length)) return res;
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
    let price;
    if (A) {
      // Prix Airbnb de la quinzaine (la dernière relevée avant cette nuit)
      const iso = `${d.getUTCFullYear()}-${md}`;
      const p = A.periodes.filter((x) => x.du <= iso).pop() || A.periodes[0];
      price = p.nuit;
    } else {
      const s = (T.saisons || []).find((x) => x && x.nuit != null && inSeason(md, x));
      price = s ? s.nuit : T.nuit;
    }
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
  if (A) {
    if (A.fixe > 0) { cents += eur(A.fixe); res.lines.push({ label: "Ménage et frais", cents: eur(A.fixe) }); }
  } else if (T.menage) { cents += eur(T.menage); res.lines.push({ label: "Ménage", cents: eur(T.menage) }); }
  // Remise réservation directe (sur les nuits et le ménage)
  const pct = Number((globalThis.TARIFS || {}).remiseDirecte) || 0;
  res.sansRemise = cents;
  if (pct > 0) {
    const off = Math.round((cents * pct) / 100);
    cents -= off;
    res.remise = off;
    res.lines.push({ label: `Remise réservation directe (−${pct} %)`, cents: -off });
  }
  const ad = Math.max(1, Number(adultes) || 1);
  let taxeSansRemise = 0;
  if (A && A.taxesPct > 0) {
    // Taxe de séjour, proportionnelle au prix comme sur Airbnb
    const tax = Math.round((cents * A.taxesPct) / 100);
    taxeSansRemise = Math.round((res.sansRemise * A.taxesPct) / 100) - tax;
    cents += tax;
    res.lines.push({ label: "Taxe de séjour", cents: tax });
  } else if (!A && T.taxeSejour) {
    const tax = eur(T.taxeSejour) * ad * n;
    cents += tax;
    res.lines.push({ label: `Taxe de séjour (${ad} adulte${ad > 1 ? "s" : ""} × ${n} nuit${n > 1 ? "s" : ""})`, cents: tax });
  }
  res.sansRemiseTotal = cents + (res.remise || 0) + taxeSansRemise; // total sans la remise (prix Airbnb, pour comparer)
  res.source = A ? "airbnb" : "tarifs";
  res.ready = true;
  res.cents = cents;
  res.total = cents / 100;
  return res;
};
globalThis.SP_EUR = (cents) => `${cents < 0 ? "−" : ""}${(Math.abs(cents) / 100).toLocaleString("fr-FR", { minimumFractionDigits: Math.abs(cents) % 100 ? 2 : 0, maximumFractionDigits: 2 })} €`;
// Prix indicatif « à partir de » (par nuit, remise directe déduite) : priceFrom de js/data.js, sinon prix Airbnb relevé
globalThis.SP_FROM = function (house) {
  const h = (globalThis.HOUSES || {})[house] || {};
  if (h.priceFrom) return h.priceFrom;
  const T = (globalThis.TARIFS || {})[house] || {};
  const manual = [T.nuit, ...(T.saisons || []).map((x) => x && x.nuit)].filter((v) => v != null);
  const A = (globalThis.TARIFS_AIRBNB || {})[house];
  const today = new Date().toISOString().slice(0, 10);
  const nights = manual.length ? manual : A && A.periodes ? A.periodes.filter((p, i, all) => !all[i + 1] || all[i + 1].du > today).map((p) => p.nuit) : [];
  if (!nights.length) return null;
  const pct = Number((globalThis.TARIFS || {}).remiseDirecte) || 0;
  return Math.round((Math.min(...nights) * (100 - pct)) / 100);
};
// Libellés du prix renvoyés par le serveur (toujours en français) -> langue de la page.
// Les recherches sont des expressions régulières (non traduites), les remplacements sont traduits avec le site.
globalThis.SP_LABEL = function (s) {
  return String(s)
    .replace(/ × (\d+) nuits?$/, (m, n) => ` × ${n} ${Number(n) > 1 ? "nuits" : "nuit"}`)
    .replace(/^Ménage et frais$/, "Ménage et frais")
    .replace(/^Ménage$/, "Ménage")
    .replace(/^Remise réservation directe/, "Remise réservation directe")
    .replace(/^Taxe de séjour \((\d+) adultes? × (\d+) nuits?\)$/, (m, a, n) => `Taxe de séjour (${a} ${Number(a) > 1 ? "adultes" : "adulte"} × ${n} ${Number(n) > 1 ? "nuits" : "nuit"})`)
    .replace(/^Taxe de séjour$/, "Taxe de séjour")
    .replace(/^Code (\S+)/, (m, c) => `Code ${c}`);
};
