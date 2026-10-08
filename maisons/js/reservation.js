/* Sable & Pierre — suivi d'une réservation (après le paiement, ou lien envoyé au voyageur) */
(function () {
  "use strict";
  const box = document.getElementById("resa");
  const q = new URLSearchParams(location.search);
  const id = q.get("id");
  const t = q.get("t");
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const fmt = (s) => { const [y, m, d] = s.split("-").map(Number); return new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(new Date(y, m - 1, d)); };
  const email = (window.SITE && SITE.email) || "";
  const STATES = {
    paiement: ["Paiement en cours", "Votre paiement n'a pas encore été finalisé. Si vous avez fermé la page de paiement, revenez sur la fiche de la maison pour recommencer."],
    a_valider: ["Demande reçue", "Merci ! Nous vérifions votre réservation et vous confirmons votre séjour par e-mail, en général sous 24 heures."],
    confirmee: ["Séjour confirmé", "Votre réservation est confirmée. Nous avons hâte de vous accueillir ! Les informations d'arrivée vous sont envoyées par e-mail avant le séjour."],
    refusee: ["Réservation non confirmée", "Nous ne pouvons malheureusement pas confirmer ce séjour. Rien n'a été débité : l'empreinte sur votre carte est libérée."],
    annulee: ["Réservation annulée", "Cette réservation a été annulée."],
    expiree: ["Paiement non finalisé", "Le délai de paiement est dépassé et les dates ont été libérées. Vous pouvez refaire une réservation depuis la fiche de la maison."],
  };
  const render = (r) => {
    const st = STATES[r.statut] || ["Réservation", ""];
    const note = r.statut === "a_valider" && r.paiement === "autorisé"
      ? "Le montant est réservé sur votre carte mais pas encore débité : il le sera au moment de notre confirmation."
      : r.statut === "a_valider" && r.paiement !== "autorisé" ? "Rien n'a été payé à cette étape : nous vous indiquons par e-mail comment régler votre séjour." : "";
    document.title = `${st[0]} | Sable & Pierre`;
    box.innerHTML = `
      <span class="eyebrow">Réservation ${esc(r.id)}</span>
      <h1 class="h1 resa__title" style="margin-top:18px">${esc(st[0])}</h1>
      <p class="lead" style="margin-top:20px">${esc(st[1])}</p>
      ${note ? `<p>${esc(note)}</p>` : ""}
      <div class="resa__card">
        <h2 class="h3">${esc(r.nomMaison)}</h2>
        <dl>
          <div><dt>Arrivée</dt><dd>${esc(fmt(r.arrivee))}</dd></div>
          <div><dt>Départ</dt><dd>${esc(fmt(r.depart))}</dd></div>
          <div><dt>Séjour</dt><dd>${r.nuits} nuit${r.nuits > 1 ? "s" : ""}</dd></div>
          <div><dt>Voyageurs</dt><dd>${r.adultes + r.enfants}${r.bebes ? ` + ${r.bebes} bébé${r.bebes > 1 ? "s" : ""}` : ""}</dd></div>
          <div><dt>Au nom de</dt><dd>${esc(r.nom)}</dd></div>
          <div><dt>E-mail</dt><dd>${esc(r.email)}</dd></div>
        </dl>
        ${r.cents ? `<div class="booking__price">${r.lignes.map((l) => `<p><span>${esc(window.SP_LABEL ? SP_LABEL(l.label) : l.label)}</span><span>${SP_EUR(l.cents)}</span></p>`).join("")}<p class="booking__total"><span>Total</span><strong>${SP_EUR(r.cents)}</strong></p></div>` : ""}
      </div>
      <p class="small">Gardez cette page : son adresse vous permet de suivre votre réservation. Une question ? Écrivez-nous à <a class="link" href="mailto:${esc(email)}">${esc(email)}</a> en indiquant le numéro ${esc(r.id)}.</p>
      <p style="margin-top:36px"><a class="btn btn--ghost" href="${esc(r.page)}">Revoir la maison</a></p>`;
  };
  const load = (tries) => {
    fetch(`api/reservation/${encodeURIComponent(id)}?t=${encodeURIComponent(t)}`)
      .then((r) => r.json())
      .then((d) => {
        if (!d.ok) throw new Error();
        render(d.reservation);
        // Juste après le paiement, Stripe peut mettre quelques secondes à confirmer
        if (d.reservation.statut === "paiement" && tries < 6) setTimeout(() => load(tries + 1), 2500);
      })
      .catch(() => {
        box.innerHTML = `<h1 class="h1">Réservation introuvable</h1><p class="lead" style="margin-top:20px">Le lien est peut-être incomplet. Écrivez-nous à <a class="link" href="mailto:${esc(email)}">${esc(email)}</a>.</p>`;
      });
  };
  if (!id || !t) box.innerHTML = `<h1 class="h1">Réservation introuvable</h1>`;
  else load(0);
})();
