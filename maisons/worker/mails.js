/*
 * E-mails envoyés automatiquement aux voyageurs, dans leur langue (celle de la page où ils ont réservé).
 * mailText(type, b, x) -> { subject, text }
 *   type : recue | confirmee | refusee | annulee | rappel | avis | caution_lien | test
 *   b    : la réservation
 *   x    : { maison, lien, montant, caution, adresse, infos, avisUrl, cautionUrl, arrivee, depart }
 */
const HOURS = {
  lacanau: { en: ["from 4 pm", "before 10 am"], es: ["a partir de las 16 h", "antes de las 10 h"] },
  bordeaux: { en: ["self check-in, flexible time", "before 12 noon"], es: ["llegada autónoma, horario flexible", "antes de las 12 h"] },
};
const SIGN = "Sable & Pierre\nhttps://sable-et-pierre.com";

const T = {
  fr: {
    hello: (b) => `Bonjour ${b.nom},`,
    hours: (x) => `Arrivée : ${x.arrivee}. Départ : ${x.depart}.`,
    caution: (x) => `Caution : ${x.caution} seront bloqués sur votre carte (empreinte bancaire, rien n'est débité) la veille de votre arrivée, puis libérés automatiquement 48 heures après votre départ.`,
    follow: (x) => `Suivre votre réservation : ${x.lien}`,
    bye: "À très bientôt,",
    recue: (b, x) => [`Votre demande pour ${x.maison} est bien reçue (${b.id})`,
      `Merci pour votre réservation à ${x.maison}, du ${x.du} au ${x.au} (${x.nuits}, ${x.voyageurs}).`,
      b.paiement === "autorisé" ? (x.acompte ? `L'acompte de ${x.acompte} est réservé sur votre carte mais pas encore débité : il ne le sera qu'au moment où nous confirmons votre séjour, en général sous 24 heures. Le solde de ${x.solde} sera prélevé automatiquement le ${x.soldeLe}.` : `Le montant de ${x.montant} est réservé sur votre carte mais pas encore débité : il ne le sera qu'au moment où nous confirmons votre séjour, en général sous 24 heures.`) : "Nous revenons vers vous très vite pour confirmer votre séjour et vous indiquer comment le régler."],
    confirmee: (b, x) => [`Votre séjour à ${x.maison} est confirmé (${b.id})`,
      `Nous avons le plaisir de vous confirmer votre séjour à ${x.maison}, du ${x.du} au ${x.au}.`,
      x.acompte && b.paiement === "acompte débité" ? `L'acompte de ${x.acompte} a été débité. Le solde de ${x.solde} sera prélevé automatiquement le ${x.soldeLe} sur la même carte.` : x.montant && b.paiement === "débité" ? `Le montant de ${x.montant} a été débité.` : "",
      "Votre contrat de location est joint à cet e-mail. Nous vous enverrons l'adresse exacte et les informations d'arrivée quelques jours avant votre venue."],
    refusee: (b, x) => [`Votre demande pour ${x.maison} (${b.id})`,
      `Merci pour votre demande pour ${x.maison} du ${x.du} au ${x.au}. Nous ne pouvons malheureusement pas confirmer ce séjour.`,
      b.paymentIntent ? "Rien n'a été débité : l'empreinte sur votre carte est libérée (elle peut rester visible quelques jours selon votre banque)." : ""],
    annulee: (b, x) => [`Votre réservation ${b.id} est annulée`,
      `Votre réservation à ${x.maison} du ${x.du} au ${x.au} est annulée.`,
      "Si un remboursement est prévu par les conditions d'annulation, il sera versé sur la carte utilisée, sous quelques jours."],
    rappel: (b, x) => [`Votre arrivée à ${x.maison} le ${x.du}`,
      `Plus que quelques jours avant votre séjour à ${x.maison} ! Voici les informations pour votre arrivée.`,
      x.adresse ? `Adresse : ${x.adresse}` : "",
      x.infos || ""],
    avis: (b, x) => [`Merci pour votre séjour à ${x.maison}`,
      `Merci d'avoir séjourné à ${x.maison}. Nous espérons que vous en gardez un beau souvenir.`,
      x.avisUrl ? `Si vous avez une minute, votre avis nous aiderait beaucoup : ${x.avisUrl}` : "Si vous avez une minute, répondez simplement à cet e-mail pour nous dire ce que vous en avez pensé : chaque retour compte.",
      x.fidelite ? `Pour vous remercier, voici un code de ${x.fidelitePct} % de réduction sur votre prochain séjour, à saisir en réservant directement sur https://sable-et-pierre.com : ${x.fidelite} (valable 2 ans, une utilisation).` : "Pour un prochain séjour, réservez directement sur https://sable-et-pierre.com : c'est toujours au meilleur prix."],
    solde_lien: (b, x) => [`Solde de votre séjour à ${x.maison} : une validation est nécessaire`,
      `Le solde de ${x.solde} pour votre séjour du ${x.du} au ${x.au} n'a pas pu être prélevé automatiquement : votre banque demande une confirmation.`,
      `Merci de le régler ici : ${x.soldeUrl}`],
    solde_ok: (b, x) => [`Solde de votre séjour à ${x.maison} réglé`,
      `Le solde de ${x.solde} pour votre séjour du ${x.du} au ${x.au} a bien été prélevé. Votre séjour est entièrement réglé, merci !`],
    caution_lien: (b, x) => [`Caution pour votre séjour à ${x.maison} : une validation est nécessaire`,
      `Votre banque demande une confirmation pour l'empreinte de caution de ${x.caution} (montant bloqué, rien n'est débité, libéré 48 heures après votre départ).`,
      `Merci de la valider ici avant votre arrivée : ${x.cautionUrl}`],
    test: () => ["E-mail de test Sable & Pierre", "Si vous lisez ceci, les e-mails automatiques fonctionnent."],
  },
  en: {
    hello: (b) => `Hello ${b.nom},`,
    hours: (x) => `Check-in: ${x.arrivee}. Check-out: ${x.depart}.`,
    caution: (x) => `Security deposit: ${x.caution} will be held on your card (a pre-authorisation, nothing is charged) the day before you arrive, and released automatically 48 hours after you leave.`,
    follow: (x) => `Your booking: ${x.lien}`,
    bye: "See you very soon,",
    recue: (b, x) => [`We have received your request for ${x.maison} (${b.id})`,
      `Thank you for booking ${x.maison}, from ${x.du} to ${x.au} (${x.nuits}, ${x.voyageurs}).`,
      b.paiement === "autorisé" ? (x.acompte ? `The deposit of ${x.acompte} is held on your card but not yet charged: it will only be charged when we confirm your stay, usually within 24 hours. The balance of ${x.solde} will be charged automatically on ${x.soldeLe}.` : `The amount of ${x.montant} is held on your card but not yet charged: it will only be charged when we confirm your stay, usually within 24 hours.`) : "We will get back to you very soon to confirm your stay and explain how to pay."],
    confirmee: (b, x) => [`Your stay at ${x.maison} is confirmed (${b.id})`,
      `We are delighted to confirm your stay at ${x.maison}, from ${x.du} to ${x.au}.`,
      x.acompte && b.paiement === "acompte débité" ? `The deposit of ${x.acompte} has been charged. The balance of ${x.solde} will be charged automatically on ${x.soldeLe} to the same card.` : x.montant && b.paiement === "débité" ? `The amount of ${x.montant} has been charged.` : "",
      "Your rental agreement is attached to this email. We will send you the exact address and arrival information a few days before your stay."],
    refusee: (b, x) => [`Your request for ${x.maison} (${b.id})`,
      `Thank you for your request for ${x.maison} from ${x.du} to ${x.au}. Unfortunately we are unable to confirm this stay.`,
      b.paymentIntent ? "Nothing has been charged: the hold on your card has been released (it may remain visible for a few days depending on your bank)." : ""],
    annulee: (b, x) => [`Your booking ${b.id} has been cancelled`,
      `Your booking at ${x.maison} from ${x.du} to ${x.au} has been cancelled.`,
      "If a refund is due under the cancellation terms, it will be paid back to your card within a few days."],
    rappel: (b, x) => [`Your arrival at ${x.maison} on ${x.du}`,
      `Only a few days to go before your stay at ${x.maison}! Here is everything you need for your arrival.`,
      x.adresse ? `Address: ${x.adresse}` : "",
      x.infos || ""],
    avis: (b, x) => [`Thank you for staying at ${x.maison}`,
      `Thank you for staying at ${x.maison}. We hope you have wonderful memories of it.`,
      x.avisUrl ? `If you have a minute, a review would help us a lot: ${x.avisUrl}` : "If you have a minute, simply reply to this email and tell us what you thought: every comment counts.",
      x.fidelite ? `To thank you, here is a ${x.fidelitePct}% discount code for your next stay, to use when booking directly on https://sable-et-pierre.com/en/: ${x.fidelite} (valid for 2 years, single use).` : "For your next stay, book directly on https://sable-et-pierre.com/en/ for the best price."],
    solde_lien: (b, x) => [`Balance for your stay at ${x.maison}: please confirm the payment`,
      `The balance of ${x.solde} for your stay from ${x.du} to ${x.au} could not be charged automatically: your bank needs a confirmation.`,
      `Please pay it here: ${x.soldeUrl}`],
    solde_ok: (b, x) => [`Balance paid for your stay at ${x.maison}`,
      `The balance of ${x.solde} for your stay from ${x.du} to ${x.au} has been charged. Your stay is now fully paid, thank you!`],
    caution_lien: (b, x) => [`Security deposit for your stay at ${x.maison}: please confirm`,
      `Your bank needs a confirmation for the ${x.caution} security deposit (an amount held on your card, nothing is charged, released 48 hours after you leave).`,
      `Please confirm it here before you arrive: ${x.cautionUrl}`],
    test: () => ["Sable & Pierre test email", "If you can read this, automatic emails are working."],
  },
  es: {
    hello: (b) => `Hola, ${b.nom}:`,
    hours: (x) => `Llegada: ${x.arrivee}. Salida: ${x.depart}.`,
    caution: (x) => `Fianza: se bloquearán ${x.caution} en tu tarjeta (una preautorización, no se cobra nada) el día antes de tu llegada, y se liberarán automáticamente 48 horas después de tu salida.`,
    follow: (x) => `Tu reserva: ${x.lien}`,
    bye: "¡Hasta muy pronto!",
    recue: (b, x) => [`Hemos recibido tu solicitud para ${x.maison} (${b.id})`,
      `Gracias por tu reserva en ${x.maison}, del ${x.du} al ${x.au} (${x.nuits}, ${x.voyageurs}).`,
      b.paiement === "autorisé" ? (x.acompte ? `El anticipo de ${x.acompte} está retenido en tu tarjeta pero aún no se ha cobrado: solo se cobrará cuando confirmemos tu estancia, normalmente en 24 horas. El resto, ${x.solde}, se cobrará automáticamente el ${x.soldeLe}.` : `El importe de ${x.montant} está retenido en tu tarjeta pero aún no se ha cobrado: solo se cobrará cuando confirmemos tu estancia, normalmente en 24 horas.`) : "Te responderemos muy pronto para confirmar tu estancia e indicarte cómo pagarla."],
    confirmee: (b, x) => [`Tu estancia en ${x.maison} está confirmada (${b.id})`,
      `Nos complace confirmarte tu estancia en ${x.maison}, del ${x.du} al ${x.au}.`,
      x.acompte && b.paiement === "acompte débité" ? `Se ha cobrado el anticipo de ${x.acompte}. El resto, ${x.solde}, se cobrará automáticamente el ${x.soldeLe} en la misma tarjeta.` : x.montant && b.paiement === "débité" ? `Se ha cobrado el importe de ${x.montant}.` : "",
      "Tu contrato de alquiler va adjunto a este correo. Te enviaremos la dirección exacta y la información de llegada unos días antes de tu estancia."],
    refusee: (b, x) => [`Tu solicitud para ${x.maison} (${b.id})`,
      `Gracias por tu solicitud para ${x.maison} del ${x.du} al ${x.au}. Lamentablemente no podemos confirmar esta estancia.`,
      b.paymentIntent ? "No se ha cobrado nada: la retención en tu tarjeta se ha liberado (puede seguir visible unos días según tu banco)." : ""],
    annulee: (b, x) => [`Tu reserva ${b.id} ha sido cancelada`,
      `Tu reserva en ${x.maison} del ${x.du} al ${x.au} ha sido cancelada.`,
      "Si las condiciones de cancelación prevén un reembolso, se abonará en la tarjeta utilizada en unos días."],
    rappel: (b, x) => [`Tu llegada a ${x.maison} el ${x.du}`,
      `¡Quedan pocos días para tu estancia en ${x.maison}! Aquí tienes la información para tu llegada.`,
      x.adresse ? `Dirección: ${x.adresse}` : "",
      x.infos || ""],
    avis: (b, x) => [`Gracias por tu estancia en ${x.maison}`,
      `Gracias por alojarte en ${x.maison}. Esperamos que guardes un bonito recuerdo.`,
      x.avisUrl ? `Si tienes un minuto, tu opinión nos ayudaría mucho: ${x.avisUrl}` : "Si tienes un minuto, responde simplemente a este correo y cuéntanos qué te pareció: cada comentario cuenta.",
      x.fidelite ? `Para darte las gracias, aquí tienes un código del ${x.fidelitePct} % de descuento para tu próxima estancia, al reservar directamente en https://sable-et-pierre.com/es/: ${x.fidelite} (válido 2 años, un solo uso).` : "Para tu próxima estancia, reserva directamente en https://sable-et-pierre.com/es/ al mejor precio."],
    solde_lien: (b, x) => [`Resto del pago de tu estancia en ${x.maison}: confirmación necesaria`,
      `El resto del pago, ${x.solde}, para tu estancia del ${x.du} al ${x.au} no se ha podido cobrar automáticamente: tu banco necesita una confirmación.`,
      `Págalo aquí: ${x.soldeUrl}`],
    solde_ok: (b, x) => [`Estancia en ${x.maison} pagada`,
      `Se ha cobrado el resto del pago, ${x.solde}, para tu estancia del ${x.du} al ${x.au}. Tu estancia está totalmente pagada, ¡gracias!`],
    caution_lien: (b, x) => [`Fianza para tu estancia en ${x.maison}: confirmación necesaria`,
      `Tu banco necesita una confirmación para la fianza de ${x.caution} (importe bloqueado, no se cobra nada, se libera 48 horas después de tu salida).`,
      `Confírmala aquí antes de tu llegada: ${x.cautionUrl}`],
    test: () => ["Correo de prueba de Sable & Pierre", "Si lees esto, los correos automáticos funcionan."],
  },
};

export function hoursOf(house, lang, h) {
  const v = (HOURS[house] || {})[lang];
  return v ? { arrivee: v[0], depart: v[1] } : { arrivee: h.checkIn, depart: h.checkOut };
}

const COUNT = {
  fr: (n, g) => [`${n} nuit${n > 1 ? "s" : ""}`, `${g} voyageur${g > 1 ? "s" : ""}`],
  en: (n, g) => [`${n} night${n > 1 ? "s" : ""}`, `${g} guest${g > 1 ? "s" : ""}`],
  es: (n, g) => [`${n} noche${n > 1 ? "s" : ""}`, `${g} viajero${g > 1 ? "s" : ""}`],
};

export function mailText(type, b, x) {
  const L = T[b.lang] || T.fr;
  const [nuits, voyageurs] = (COUNT[b.lang] || COUNT.fr)(b.nuits || 0, (b.adultes || 0) + (b.enfants || 0));
  x = Object.assign({ nuits, voyageurs }, x);
  const [subject, ...body] = L[type](b, x);
  const parts = [L.hello(b), ...body.filter(Boolean)];
  if (type === "confirmee" || type === "rappel") parts.push(L.hours(x));
  if ((type === "confirmee" || type === "rappel") && x.caution) parts.push(L.caution(x));
  if (type !== "test" && type !== "avis" && x.lien) parts.push(L.follow(x));
  parts.push(`${L.bye}\n${SIGN}`);
  return { subject, text: parts.join("\n\n") };
}

// Version HTML simple (paragraphes, liens cliquables)
export function mailHtml(text) {
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const body = text.split("\n\n").map((p) => `<p style="margin:0 0 16px">${esc(p).replace(/(https:\/\/[^\s<]+)/g, '<a href="$1" style="color:#12495a">$1</a>').replace(/\n/g, "<br>")}</p>`).join("");
  return `<div style="font-family:Helvetica,Arial,sans-serif;font-size:15px;line-height:1.55;color:#1c1a17;max-width:560px">${body}</div>`;
}
