/*
 * Contrat de location saisonnière (PDF), généré à la confirmation d'une réservation directe.
 * Envoyé en pièce jointe de l'e-mail de confirmation et téléchargeable depuis la page de suivi.
 * Générateur PDF minimal (polices Helvetica standard, encodage WinAnsi) : aucune dépendance.
 *
 * contratPdf(b, c) -> Uint8Array
 *   b : la réservation ; c : { maison, url, adresse, owner, email, conditions[], caution, split, regles, registration,
 *        fmt(iso), money(cents), lignes[{label, cents}] }
 */

/* ---------- Texte du contrat, en français, anglais ou espagnol ---------- */
const TXT = {
  fr: {
    title: "Contrat de location saisonnière",
    sub: (b) => `Meublé de tourisme · réservation ${b.id}`,
    parties: "1. Les parties",
    bailleur: "Le bailleur", locataire: "Le locataire",
    logement: "2. Le logement",
    desc: (h) => `Maison meublée de ${h.bedrooms} chambres, ${h.beds} lits et ${h.bathrooms} salles de bain, pour ${h.guests} personnes au maximum. Description détaillée et photos (état descriptif) : `,
    adresse: "Adresse", adresseApres: "communiquée par e-mail 7 jours avant l'arrivée",
    reg: "Numéro d'enregistrement en mairie",
    duree: "3. Durée du séjour",
    arr: "Arrivée", dep: "Départ", nuits: "Durée", voy: "Voyageurs",
    nN: (n) => `${n} nuit${n > 1 ? "s" : ""}`,
    vV: (a, e, k) => `${a} adulte${a > 1 ? "s" : ""}${e ? `, ${e} enfant${e > 1 ? "s" : ""}` : ""}${k ? `, ${k} bébé${k > 1 ? "s" : ""}` : ""}`,
    maintien: "La location est consentie pour une durée déterminée : le locataire ne pourra se prévaloir d'aucun droit au maintien dans les lieux à son expiration.",
    prix: "4. Prix", total: "Total TTC", prixNote: "Le prix comprend la location, le ménage de fin de séjour, les charges (eau, électricité, chauffage, internet) et la taxe de séjour.",
    paiement: "5. Paiement",
    pay1: (m) => `Paiement par carte bancaire via Stripe : ${m}, débité à la confirmation de la réservation.`,
    pay2: (s, m) => `Paiement en deux fois par carte bancaire via Stripe : acompte de ${m(s.acompte)} débité à la confirmation, solde de ${m(s.solde)} prélevé automatiquement le ${s.le}.`,
    caution: "6. Caution",
    cautionTxt: (m) => `Caution de ${m} : la veille de l'arrivée, ce montant est bloqué sur la carte du locataire (empreinte bancaire, rien n'est débité), puis libéré automatiquement 48 heures après le départ. En cas de dégradation, de casse ou de ménage anormal constatés, le coût correspondant peut être prélevé dans la limite de la caution, après information du locataire et sur justificatifs.`,
    annul: "7. Annulation",
    annulNote: "Toute annulation se fait par écrit (e-mail) en indiquant le numéro de réservation.",
    regles: "8. Règlement de la maison et obligations du locataire",
    reglesTxt: "Le locataire s'engage à occuper les lieux paisiblement et en bon père de famille, à respecter la capacité maximale et le règlement de la maison, à ne pas sous-louer ni céder le logement, et à le rendre dans l'état où il l'a trouvé. Il est responsable des dégradations survenues pendant le séjour ; une assurance villégiature (responsabilité civile) est recommandée.",
    accept: "9. Acceptation",
    acceptTxt: (b, d1, d2) => `Contrat conclu à distance, sur le site sable-et-pierre.com : le locataire a accepté les conditions de réservation et le règlement de la maison le ${d1}, puis réglé par carte bancaire. Réservation confirmée par le bailleur le ${d2}.`,
    foot: "Sable & Pierre · sable-et-pierre.com",
    page: (i, n) => `Page ${i} / ${n}`,
  },
  en: {
    title: "Holiday rental agreement",
    sub: (b) => `Furnished holiday home · booking ${b.id}`,
    parties: "1. The parties",
    bailleur: "The owner", locataire: "The guest",
    logement: "2. The property",
    desc: (h) => `Furnished house with ${h.bedrooms} bedrooms, ${h.beds} beds and ${h.bathrooms} bathrooms, for a maximum of ${h.guests} people. Full description and photos: `,
    adresse: "Address", adresseApres: "sent by email 7 days before arrival",
    reg: "Town hall registration number",
    duree: "3. Length of stay",
    arr: "Arrival", dep: "Departure", nuits: "Length", voy: "Guests",
    nN: (n) => `${n} night${n > 1 ? "s" : ""}`,
    vV: (a, e, k) => `${a} adult${a > 1 ? "s" : ""}${e ? `, ${e} child${e > 1 ? "ren" : ""}` : ""}${k ? `, ${k} infant${k > 1 ? "s" : ""}` : ""}`,
    maintien: "The rental is granted for a fixed term: the guest has no right to remain in the property after it ends.",
    prix: "4. Price", total: "Total (incl. VAT)", prixNote: "The price includes the rental, end-of-stay cleaning, utilities (water, electricity, heating, internet) and the tourist tax.",
    paiement: "5. Payment",
    pay1: (m) => `Payment by card via Stripe: ${m}, charged when the booking is confirmed.`,
    pay2: (s, m) => `Payment in two instalments by card via Stripe: a deposit of ${m(s.acompte)} charged on confirmation, and the balance of ${m(s.solde)} charged automatically on ${s.le}.`,
    caution: "6. Security deposit",
    cautionTxt: (m) => `Security deposit of ${m}: the day before arrival, this amount is held on the guest's card (a pre-authorisation, nothing is charged), then released automatically 48 hours after departure. If damage, breakage or unusual cleaning is found, the corresponding cost may be charged up to the amount of the deposit, after informing the guest and with supporting documents.`,
    annul: "7. Cancellation",
    annulNote: "Any cancellation must be made in writing (email), quoting the booking number.",
    regles: "8. House rules and guest obligations",
    reglesTxt: "The guest undertakes to occupy the property peacefully and with care, to respect the maximum capacity and the house rules, not to sublet or transfer the property, and to leave it in the condition in which it was found. The guest is liable for any damage occurring during the stay; holiday liability insurance is recommended.",
    accept: "9. Acceptance",
    acceptTxt: (b, d1, d2) => `Agreement concluded remotely on sable-et-pierre.com: the guest accepted the booking terms and the house rules on ${d1}, then paid by card. Booking confirmed by the owner on ${d2}. French law applies.`,
    foot: "Sable & Pierre · sable-et-pierre.com",
    page: (i, n) => `Page ${i} / ${n}`,
  },
  es: {
    title: "Contrato de alquiler vacacional",
    sub: (b) => `Alojamiento turístico amueblado · reserva ${b.id}`,
    parties: "1. Las partes",
    bailleur: "El propietario", locataire: "El huésped",
    logement: "2. El alojamiento",
    desc: (h) => `Casa amueblada de ${h.bedrooms} dormitorios, ${h.beds} camas y ${h.bathrooms} baños, para un máximo de ${h.guests} personas. Descripción completa y fotos: `,
    adresse: "Dirección", adresseApres: "enviada por correo 7 días antes de la llegada",
    reg: "Número de registro municipal",
    duree: "3. Duración de la estancia",
    arr: "Llegada", dep: "Salida", nuits: "Duración", voy: "Viajeros",
    nN: (n) => `${n} noche${n > 1 ? "s" : ""}`,
    vV: (a, e, k) => `${a} adulto${a > 1 ? "s" : ""}${e ? `, ${e} niño${e > 1 ? "s" : ""}` : ""}${k ? `, ${k} bebé${k > 1 ? "s" : ""}` : ""}`,
    maintien: "El alquiler se concede por un periodo determinado: el huésped no tendrá derecho a permanecer en el alojamiento a su término.",
    prix: "4. Precio", total: "Total (IVA incl.)", prixNote: "El precio incluye el alquiler, la limpieza final, los gastos (agua, electricidad, calefacción, internet) y la tasa turística.",
    paiement: "5. Pago",
    pay1: (m) => `Pago con tarjeta a través de Stripe: ${m}, cobrado al confirmar la reserva.`,
    pay2: (s, m) => `Pago en dos plazos con tarjeta a través de Stripe: anticipo de ${m(s.acompte)} cobrado al confirmar, y el resto de ${m(s.solde)} cobrado automáticamente el ${s.le}.`,
    caution: "6. Fianza",
    cautionTxt: (m) => `Fianza de ${m}: el día antes de la llegada, este importe se bloquea en la tarjeta del huésped (preautorización, no se cobra nada) y se libera automáticamente 48 horas después de la salida. En caso de daños, roturas o limpieza anormal, el coste correspondiente puede cobrarse hasta el importe de la fianza, tras informar al huésped y con justificantes.`,
    annul: "7. Cancelación",
    annulNote: "Cualquier cancelación debe hacerse por escrito (correo electrónico) indicando el número de reserva.",
    regles: "8. Normas de la casa y obligaciones del huésped",
    reglesTxt: "El huésped se compromete a ocupar el alojamiento de forma pacífica y cuidadosa, a respetar la capacidad máxima y las normas de la casa, a no subarrendarlo ni cederlo, y a dejarlo en el estado en que lo encontró. Es responsable de los daños ocurridos durante la estancia; se recomienda un seguro de responsabilidad civil para vacaciones.",
    accept: "9. Aceptación",
    acceptTxt: (b, d1, d2) => `Contrato celebrado a distancia en sable-et-pierre.com: el huésped aceptó las condiciones de reserva y las normas de la casa el ${d1} y pagó con tarjeta. Reserva confirmada por el propietario el ${d2}. Se aplica la ley francesa.`,
    foot: "Sable & Pierre · sable-et-pierre.com",
    page: (i, n) => `Página ${i} / ${n}`,
  },
};

/* ---------- Mise en page ---------- */
// Largeurs Helvetica (1/1000 em) des caractères 32 à 126
const W = [278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584];
const SPECIAL = { "€": 0x80, "‚": 0x82, "„": 0x84, "…": 0x85, "‘": 0x91, "’": 0x92, "“": 0x93, "”": 0x94, "•": 0x95, "–": 0x96, "—": 0x97, "œ": 0x9c, "Œ": 0x8c, " ": 0xa0, " ": 0x20, "‑": 0x2d, "−": 0x2d, "→": 0x3e };
const charW = (ch, bold) => {
  const c = ch.charCodeAt(0);
  let w = c >= 32 && c <= 126 ? W[c - 32] : 0;
  if (!w) {
    const base = ch.normalize("NFD")[0];
    const b = base.charCodeAt(0);
    w = b >= 32 && b <= 126 ? W[b - 32] : ch === "—" || ch === "…" ? 1000 : 556;
  }
  return bold ? w * 1.06 : w;
};
const textW = (s, size, bold) => [...s].reduce((t, ch) => t + charW(ch, bold), 0) * size / 1000;
// Texte -> octets WinAnsi, échappés pour un flux PDF
const enc = (s) => [...s].map((ch) => {
  let c = SPECIAL[ch] ?? ch.charCodeAt(0);
  if (c > 255) c = 0x3f;
  const o = String.fromCharCode(c);
  return o === "(" || o === ")" || o === "\\" ? `\\${o}` : o;
}).join("");
function wrap(s, size, bold, max) {
  const out = [];
  for (const para of String(s).split("\n")) {
    let line = "";
    for (const word of para.split(" ")) {
      const t = line ? `${line} ${word}` : word;
      if (textW(t, size, bold) <= max || !line) line = t;
      else { out.push(line); line = word; }
    }
    out.push(line);
  }
  return out;
}

function pdf(blocks, foot, pageLabel) {
  const PW = 595.28, PH = 841.89, M = 56, MAXW = PW - 2 * M, BOTTOM = 70;
  const pages = [[]];
  let y = PH - M;
  const put = (op) => pages[pages.length - 1].push(op);
  const need = (h) => { if (y - h < BOTTOM) { pages.push([]); y = PH - M; } };
  const text = (s, x, size, bold, color) => put(`BT /${bold ? "F2" : "F1"} ${size} Tf ${color || "0.11 0.10 0.09"} rg ${x.toFixed(2)} ${y.toFixed(2)} Td (${enc(s)}) Tj ET`);
  for (const b of blocks) {
    if (b.t === "title") { need(40); text(b.s, M, 19, true); y -= 20; }
    else if (b.t === "sub") { text(b.s, M, 10, false, "0.40 0.37 0.34"); y -= 12; put(`0.71 0.54 0.29 RG 1 w ${M} ${y.toFixed(2)} m ${PW - M} ${y.toFixed(2)} l S`); y -= 18; }
    else if (b.t === "h") { need(36); y -= 8; text(b.s, M, 11.5, true, "0.07 0.29 0.35"); y -= 17; }
    else if (b.t === "p" || b.t === "li") {
      const x = b.t === "li" ? M + 12 : M;
      const lines = wrap(b.s, 9.5, false, MAXW - (x - M));
      lines.forEach((l, i) => { need(13.5); if (b.t === "li" && i === 0) text("•", M + 2, 9.5, false); text(l, x, 9.5, false); y -= 13.5; });
      y -= 3;
    } else if (b.t === "row") {
      const lines = wrap(b.v, 9.5, false, MAXW - 170);
      const keys = wrap(b.k, 9.5, true, 160);
      need(13.5 * Math.max(lines.length, keys.length));
      const y0 = y;
      keys.forEach((l) => { text(l, M, 9.5, true, "0.40 0.37 0.34"); y -= 13.5; });
      const y1 = y;
      y = y0;
      lines.forEach((l) => { text(l, M + 170, 9.5, false); y -= 13.5; });
      y = Math.min(y, y1);
    } else if (b.t === "money") {
      need(14);
      text(b.k, M, b.bold ? 10.5 : 9.5, !!b.bold);
      text(b.v, PW - M - textW(b.v, b.bold ? 10.5 : 9.5, !!b.bold), b.bold ? 10.5 : 9.5, !!b.bold);
      y -= b.bold ? 17 : 13.5;
      if (b.rule) { put(`0.80 0.78 0.75 RG 0.5 w ${M} ${(y + 9).toFixed(2)} m ${PW - M} ${(y + 9).toFixed(2)} l S`); }
    } else if (b.t === "gap") y -= b.h || 8;
  }
  // Pied de page
  pages.forEach((ops, i) => {
    const lbl = pageLabel(i + 1, pages.length);
    ops.push(`BT /F1 8 Tf 0.40 0.37 0.34 rg ${M} 40 Td (${enc(foot)}) Tj ET`);
    ops.push(`BT /F1 8 Tf 0.40 0.37 0.34 rg ${(PW - M - textW(lbl, 8, false)).toFixed(2)} 40 Td (${enc(lbl)}) Tj ET`);
  });
  // Assemblage
  const objs = [];
  const n = pages.length;
  objs[1] = "<< /Type /Catalog /Pages 2 0 R >>";
  objs[2] = `<< /Type /Pages /Count ${n} /Kids [${pages.map((p, i) => `${5 + i * 2} 0 R`).join(" ")}] >>`;
  objs[3] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>";
  objs[4] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>";
  pages.forEach((ops, i) => {
    const content = ops.join("\n");
    objs[5 + i * 2] = `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${PW} ${PH}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${6 + i * 2} 0 R >>`;
    objs[6 + i * 2] = `<< /Length ${content.length} >>\nstream\n${content}\nendstream`;
  });
  let out = "%PDF-1.4\n%\xe2\xe3\xcf\xd3\n";
  const offs = [];
  for (let i = 1; i < objs.length; i++) { offs[i] = out.length; out += `${i} 0 obj\n${objs[i]}\nendobj\n`; }
  const xref = out.length;
  out += `xref\n0 ${objs.length}\n0000000000 65535 f \n${offs.slice(1).map((o) => `${String(o).padStart(10, "0")} 00000 n \n`).join("")}`;
  out += `trailer\n<< /Size ${objs.length} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Uint8Array.from(out, (ch) => ch.charCodeAt(0) & 255);
}

export function contratPdf(b, c) {
  const L = TXT[b.lang] || TXT.fr;
  const h = c.house;
  const B = [];
  B.push({ t: "title", s: L.title }, { t: "sub", s: `${L.sub(b)} · ${c.maison}` });
  B.push({ t: "h", s: L.parties },
    { t: "row", k: L.bailleur, v: `${c.owner} · ${c.email}` },
    { t: "row", k: L.locataire, v: `${b.nom} · ${b.email}${b.telephone ? ` · ${b.telephone}` : ""}` });
  B.push({ t: "h", s: L.logement },
    { t: "p", s: `${c.maison}. ${L.desc(h)}${c.url}` },
    { t: "row", k: L.adresse, v: c.adresse || `${h.place || ""} (${L.adresseApres})` });
  if (c.registration) B.push({ t: "row", k: L.reg, v: c.registration });
  B.push({ t: "h", s: L.duree },
    { t: "row", k: L.arr, v: `${c.fmt(b.arrivee)} · ${c.hours.arrivee}` },
    { t: "row", k: L.dep, v: `${c.fmt(b.depart)} · ${c.hours.depart}` },
    { t: "row", k: L.nuits, v: L.nN(b.nuits) },
    { t: "row", k: L.voy, v: L.vV(b.adultes, b.enfants, b.bebes) },
    { t: "gap", h: 4 }, { t: "p", s: L.maintien });
  B.push({ t: "h", s: L.prix });
  (c.lignes || []).forEach((l) => B.push({ t: "money", k: l.label, v: c.money(l.cents) }));
  B.push({ t: "gap", h: 2 }, { t: "money", k: L.total, v: c.money(b.cents || 0), bold: true, rule: true }, { t: "gap", h: 4 }, { t: "p", s: L.prixNote });
  B.push({ t: "h", s: L.paiement }, { t: "p", s: c.split ? L.pay2(c.split, c.money) : L.pay1(c.money(b.cents || 0)) });
  if (b.cautionMontant) B.push({ t: "h", s: L.caution }, { t: "p", s: L.cautionTxt(c.money(b.cautionMontant * 100)) });
  B.push({ t: "h", s: L.annul });
  (c.conditions || []).forEach((x) => B.push({ t: "li", s: x }));
  B.push({ t: "p", s: L.annulNote });
  B.push({ t: "h", s: L.regles }, { t: "p", s: L.reglesTxt });
  (c.regles || []).forEach((x) => B.push({ t: "li", s: x }));
  B.push({ t: "h", s: L.accept }, { t: "p", s: L.acceptTxt(b, c.fmt(b.cree.slice(0, 10)), c.fmt((b.confirmeeLe || b.maj || b.cree).slice(0, 10))) });
  return pdf(B, L.foot, L.page);
}

export const pdfBase64 = (bytes) => { let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(s); };
