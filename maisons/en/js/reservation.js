/* Sable & Pierre — suivi d'une réservation (après le paiement, ou lien envoyé au voyageur) */
(function () {
  "use strict";
  const box = document.getElementById("resa");
  const q = new URLSearchParams(location.search);
  const id = q.get("id");
  const t = q.get("t");
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const fmt = (s) => { const [y, m, d] = s.split("-").map(Number); return new Intl.DateTimeFormat("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(new Date(y, m - 1, d)); };
  const email = (window.SITE && SITE.email) || "";
  const STATES = {
    paiement: ["Payment in progress", "Your payment has not been completed yet. If you closed the payment page, go back to the house page to start again."],
    a_valider: ["Request received", "Thank you! We are checking your booking and will confirm your stay by email, usually within 24 hours."],
    confirmee: ["Stay confirmed", "Your booking is confirmed. We look forward to welcoming you! Arrival information will be emailed to you before your stay."],
    refusee: ["Booking not confirmed", "Unfortunately we cannot confirm this stay. Nothing has been charged: the hold on your card has been released."],
    annulee: ["Booking cancelled", "This booking has been cancelled."],
    expiree: ["Payment not completed", "The payment time limit has passed and the dates have been released. You can book again from the house page."],
  };
  const render = (r) => {
    const st = STATES[r.statut] || ["Booking", ""];
    const note = r.statut === "a_valider" && r.paiement === "authorised"
      ? "The amount is held on your card but not yet charged: it will be charged when we confirm."
      : r.statut === "a_valider" && r.paiement !== "authorised" ? "Nothing has been paid at this stage: we will email you how to pay for your stay." : "";
    document.title = `${st[0]} | Sable & Pierre`;
    box.innerHTML = `
      <span class="eyebrow">Booking ${esc(r.id)}</span>
      <h1 class="h1 resa__title" style="margin-top:18px">${esc(st[0])}</h1>
      <p class="lead" style="margin-top:20px">${esc(st[1])}</p>
      ${note ? `<p>${esc(note)}</p>` : ""}
      <div class="resa__card">
        <h2 class="h3">${esc(r.nomMaison)}</h2> <dl> <div><dt>Arrival</dt><dd>${esc(fmt(r.arrivee))}</dd></div> <div><dt>Departure</dt><dd>${esc(fmt(r.depart))}</dd></div> <div><dt>Stay</dt><dd>${r.nuits} night${r.nuits > 1 ? "s" : ""}</dd></div> <div><dt>Guests</dt><dd>${r.adultes + r.enfants}${r.bebes ? ` + ${r.bebes} infant${r.bebes > 1 ? "s" : ""}` : ""}</dd></div> <div><dt>Name</dt><dd>${esc(r.nom)}</dd></div> <div><dt>Email</dt><dd>${esc(r.email)}</dd></div>
        </dl>
        ${r.cents ? `<div class="booking__price">${r.lignes.map((l) => `<p><span>${esc(window.SP_LABEL ? SP_LABEL(l.label) : l.label)}</span><span>${SP_EUR(l.cents)}</span></p>`).join("")}<p class="booking__total"><span>Total</span><strong>${SP_EUR(r.cents)}</strong></p></div>` : ""}
      </div>
      ${r.caution && (r.statut === "confirmee" || r.statut === "a_valider") ? `<div class="resa__caution"> <h2 class="h3">Security deposit: ${SP_EUR(r.caution.montant * 100)}</h2>
        <p>${r.caution.etat === "bloquee" ? "The security deposit is held on your card (a pre-authorisation, nothing is charged). It will be released automatically 48 hours after you leave." : r.caution.etat === "liberee" ? "The security deposit has been released." : r.caution.etat === "lien" ? "Your bank needs a confirmation for the security deposit: please confirm it before you arrive (nothing is charged)." : "The security deposit is held on your card the day before you arrive (a pre-authorisation, nothing is charged), then released automatically 48 hours after you leave."}</p>
        ${r.caution.url ? `<p><a class="btn btn--accent" href="${esc(r.caution.url)}">Confirm the deposit</a></p>` : ""}
      </div>` : ""}
      <p class="small">Keep this page: its address lets you follow your booking. Any questions? Write to us at <a class="link" href="mailto:${esc(email)}">${esc(email)}</a> quoting the reference ${esc(r.id)}.</p>
      <p style="margin-top:36px"><a class="btn btn--ghost" href="${esc(r.page)}">Back to the house</a></p>`;
  };
  const load = (tries) => {
    fetch(`../api/reservation/${encodeURIComponent(id)}?t=${encodeURIComponent(t)}`)
      .then((r) => r.json())
      .then((d) => {
        if (!d.ok) throw new Error();
        render(d.reservation);
        // Juste après le paiement, Stripe peut mettre quelques secondes à confirmer
        if (d.reservation.statut === "paiement" && tries < 6) setTimeout(() => load(tries + 1), 2500);
      })
      .catch(() => {
        box.innerHTML = `<h1 class="h1">Booking not found</h1><p class="lead" style="margin-top:20px">The link may be incomplete. Write to us at <a class="link" href="mailto:${esc(email)}">${esc(email)}</a>.</p>`;
      });
  };
  if (!id || !t) box.innerHTML = `<h1 class="h1">Booking not found</h1>`;
  else load(0);
})();
