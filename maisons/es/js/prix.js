/*
 * Calcul du prix d'un séjour.
 * - Réglages de l'espace propriétaire (admin.html → Prix) : prix automatiques
 *   (Airbnb, ± ajustement) ou prix fixés à la main, et prix pour des dates précises.
 * - Sinon, si un prix de nuit est saisi dans js/tarifs.js, il est utilisé.
 * - Sinon, le prix est celui d'Airbnb pour ces dates (js/tarifs-airbnb.js,
 *   relevé automatiquement) : nuits, frais du séjour et taxes.
 * La remise « réservation directe » s'applique ensuite.
 * Utilisé à l'identique par le site et par le serveur (worker/index.js) :
 * le montant payé est toujours recalculé côté serveur.
 */
// Prix d'une nuit (date ISO de la nuit), avant remise : prix pour ces dates > mode manuel > Airbnb (± ajustement) > js/tarifs.js
// « live » = réglages de l'espace propriétaire (enregistrés sur le serveur, injectés dans les pages).
globalThis.SP_NIGHT = function (house, iso, live) {
  const L = (live || globalThis.TARIFS_LIVE || {})[house];
  if (L) {
    // Prix pour des dates précises : un montant (nuit) ou une hausse/baisse en % du prix habituel (pct)
    const fixed = (L.dates || []).find((x) => x.du <= iso && iso <= x.au && (x.nuit > 0 || x.pct));
    if (fixed) {
      if (fixed.nuit > 0) return fixed.nuit;
      const base = globalThis.SP_NIGHT(house, iso, Object.assign({}, live || globalThis.TARIFS_LIVE, { [house]: Object.assign({}, L, { dates: [] }) }));
      return base > 0 ? Math.round((base * (100 + Number(fixed.pct))) / 500) * 5 : base;
    }
    if (L.mode === "manuel" && L.nuit > 0) {
      const [y, m, d] = iso.split("-").map(Number);
      const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
      return (dow === 5 || dow === 6) && L.weekend > 0 ? L.weekend : L.nuit;
    }
  }
  const T = (globalThis.TARIFS || {})[house] || {};
  const manual = T.nuit != null || (T.saisons || []).some((x) => x && x.nuit != null);
  const A = (globalThis.TARIFS_AIRBNB || {})[house];
  if (!manual && A && A.periodes && A.periodes.length) {
    // Prix Airbnb de la quinzaine (la dernière relevée avant cette nuit), ajusté de ± x % si demandé
    const p = A.periodes.filter((x) => x.du <= iso).pop() || A.periodes[0];
    const adj = L && L.mode !== "manuel" ? Number(L.ajust) || 0 : 0;
    return adj ? Math.round((p.nuit * (100 + adj)) / 500) * 5 : p.nuit;
  }
  const md = iso.slice(5);
  const inSeason = (s) => (s.du <= s.au ? md >= s.du && md <= s.au : md >= s.du || md <= s.au);
  const s = (T.saisons || []).find((x) => x && x.nuit != null && inSeason(x));
  return s ? s.nuit : T.nuit;
};
globalThis.SP_REMISE = function (live) {
  const L = live || globalThis.TARIFS_LIVE || {};
  return L.remise != null ? Number(L.remise) || 0 : Number((globalThis.TARIFS || {}).remiseDirecte) || 0;
};
globalThis.SP_PRICE = function (house, arrivee, depart, adultes, live) {
  live = live || globalThis.TARIFS_LIVE || {};
  const T = (globalThis.TARIFS || {})[house];
  const res = { ready: false, nights: 0, lines: [], total: 0, cents: 0 };
  if (!T) return res;
  const L = live[house] || {};
  const A = (globalThis.TARIFS_AIRBNB || {})[house];
  const manualT = T.nuit != null || (T.saisons || []).some((x) => x && x.nuit != null);
  const hasA = !manualT && !!(A && A.periodes && A.periodes.length); // prix Airbnb utilisés (ménage, taxe)
  if (L.mode !== "manuel" && !manualT && !hasA) return res;
  const parse = (s) => { const [y, m, d] = s.split("-").map(Number); return Date.UTC(y, m - 1, d); };
  const DAY = 86400000;
  const a = parse(arrivee);
  const b = parse(depart);
  const n = Math.round((b - a) / DAY);
  if (!(n > 0)) return res;
  res.nights = n;
  const groups = [];
  for (let i = 0; i < n; i++) {
    const price = globalThis.SP_NIGHT(house, new Date(a + i * DAY).toISOString().slice(0, 10), live);
    if (!(price > 0)) return res; // tarif manquant : prix sur demande
    const last = groups[groups.length - 1];
    if (last && last.price === price) last.count++;
    else groups.push({ price, count: 1 });
  }
  const eur = (v) => Math.round(v * 100);
  let cents = 0;
  groups.forEach((g) => {
    const amount = eur(g.price) * g.count;
    cents += amount;
    res.lines.push({ label: `${g.price.toLocaleString("es-ES")} € × ${g.count} noche${g.count > 1 ? "s" : ""}`, cents: amount });
  });
  // Ménage : celui saisi dans l'espace propriétaire (mode manuel), sinon les frais Airbnb, sinon js/tarifs.js
  const fixe = L.mode === "manuel" && L.menage != null ? Number(L.menage) || 0 : hasA ? A.fixe || 0 : 0;
  if (L.mode === "manuel" || hasA) {
    if (fixe > 0) { cents += eur(fixe); res.lines.push({ label: "Limpieza y gastos", cents: eur(fixe) }); }
  } else if (T.menage) { cents += eur(T.menage); res.lines.push({ label: "Limpieza", cents: eur(T.menage) }); }
  // Remise réservation directe (sur les nuits et le ménage)
  const pct = globalThis.SP_REMISE(live);
  res.sansRemise = cents;
  if (pct > 0) {
    const off = Math.round((cents * pct) / 100);
    cents -= off;
    res.remise = off;
    res.lines.push({ label: `Descuento por reserva directa (−${pct} %)`, cents: -off });
  }
  const ad = Math.max(1, Number(adultes) || 1);
  let taxeSansRemise = 0;
  if (hasA && A.taxesPct > 0) {
    // Taxe de séjour, proportionnelle au prix comme sur Airbnb
    const tax = Math.round((cents * A.taxesPct) / 100);
    taxeSansRemise = Math.round((res.sansRemise * A.taxesPct) / 100) - tax;
    cents += tax;
    res.lines.push({ label: "Tasa turística", cents: tax });
  } else if (T.taxeSejour) {
    const tax = eur(T.taxeSejour) * ad * n;
    cents += tax;
    res.lines.push({ label: `Tasa turística (${ad} adulto${ad > 1 ? "s" : ""} × ${n} noche${n > 1 ? "s" : ""})`, cents: tax });
  }
  res.sansRemiseTotal = cents + (res.remise || 0) + taxeSansRemise; // total sans la remise (pour comparer)
  res.source = L.mode === "manuel" ? "manuel" : hasA ? "airbnb" : "tarifs";
  res.ready = true;
  res.cents = cents;
  res.total = cents / 100;
  return res;
};
globalThis.SP_EUR = (cents) => `${cents < 0 ? "−" : ""}${(Math.abs(cents) / 100).toLocaleString("es-ES", { minimumFractionDigits: Math.abs(cents) % 100 ? 2 : 0, maximumFractionDigits: 2 })} €`;
// Prix indicatif « à partir de » (par nuit, remise directe déduite) : priceFrom de js/data.js, sinon prix Airbnb relevé
globalThis.SP_FROM = function (house) {
  const h = (globalThis.HOUSES || {})[house] || {};
  if (h.priceFrom) return h.priceFrom;
  const DAY = 86400000;
  const t0 = Date.parse(new Date().toISOString().slice(0, 10));
  let min = null;
  for (let i = 1; i <= 365; i++) {
    const v = globalThis.SP_NIGHT(house, new Date(t0 + i * DAY).toISOString().slice(0, 10));
    if (v > 0 && (min == null || v < min)) min = v;
  }
  if (min == null) return null;
  return Math.round((min * (100 - globalThis.SP_REMISE())) / 100);
};
// Libellés du prix renvoyés par le serveur (toujours en français) -> langue de la page.
// Les recherches sont des expressions régulières (non traduites), les remplacements sont traduits avec le site.
globalThis.SP_LABEL = function (s) {
  return String(s)
    .replace(/ × (\d+) nuits?$/, (m, n) => ` × ${n} ${Number(n) > 1 ? "noches" : "noche"}`)
    .replace(/^Ménage et frais$/, "Limpieza y gastos")
    .replace(/^Ménage$/, "Limpieza")
    .replace(/^Remise réservation directe/, "Descuento por reserva directa")
    .replace(/^Taxe de séjour \((\d+) adultes? × (\d+) nuits?\)$/, (m, a, n) => `Tasa turística (${a} ${Number(a) > 1 ? "adultos" : "adulto"} × ${n} ${Number(n) > 1 ? "noches" : "noche"})`)
    .replace(/^Taxe de séjour$/, "Tasa turística")
    .replace(/^Code (\S+)/, (m, c) => `Código ${c}`);
};
