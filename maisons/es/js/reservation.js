/* Sable & Pierre — suivi d'une réservation (après le paiement, ou lien envoyé au voyageur) */
(function () {
  "use strict";
  const box = document.getElementById("resa");
  const q = new URLSearchParams(location.search);
  const id = q.get("id");
  const t = q.get("t");
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const fmt = (s) => { const [y, m, d] = s.split("-").map(Number); return new Intl.DateTimeFormat("es-ES", { weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(new Date(y, m - 1, d)); };
  const email = (window.SITE && SITE.email) || "";
  const STATES = {
    paiement: ["Pago en curso", "Tu pago aún no se ha completado. Si cerraste la página de pago, vuelve a la ficha de la casa para empezar de nuevo."],
    a_valider: ["Solicitud recibida", "¡Gracias! Estamos comprobando tu reserva y te confirmaremos la estancia por correo, normalmente en 24 horas."],
    confirmee: ["Estancia confirmada", "Tu reserva está confirmada. ¡Estamos deseando recibirte! Te enviaremos la información de llegada por correo antes de la estancia."],
    refusee: ["Reserva no confirmada", "Lamentablemente no podemos confirmar esta estancia. No se ha cobrado nada: la retención en tu tarjeta se ha liberado."],
    annulee: ["Reserva cancelada", "Esta reserva ha sido cancelada."],
    expiree: ["Pago no completado", "Se ha superado el plazo de pago y las fechas se han liberado. Puedes volver a reservar desde la ficha de la casa."],
  };
  const render = (r) => {
    const st = STATES[r.statut] || ["Reserva", ""];
    const note = r.statut === "a_valider" && r.paiement === "autorizado"
      ? "El importe está retenido en tu tarjeta pero aún no se ha cobrado: se cobrará cuando confirmemos."
      : r.statut === "a_valider" && r.paiement !== "autorizado" ? "No se ha pagado nada en este paso: te indicaremos por correo cómo pagar tu estancia." : "";
    document.title = `${st[0]} | Sable & Pierre`;
    box.innerHTML = `
      <span class="eyebrow">Reserva ${esc(r.id)}</span>
      <h1 class="h1 resa__title" style="margin-top:18px">${esc(st[0])}</h1>
      <p class="lead" style="margin-top:20px">${esc(st[1])}</p>
      ${note ? `<p>${esc(note)}</p>` : ""}
      <div class="resa__card">
        <h2 class="h3">${esc(r.nomMaison)}</h2> <dl> <div><dt>Llegada</dt><dd>${esc(fmt(r.arrivee))}</dd></div> <div><dt>Salida</dt><dd>${esc(fmt(r.depart))}</dd></div> <div><dt>Estancia</dt><dd>${r.nuits} noche${r.nuits > 1 ? "s" : ""}</dd></div> <div><dt>Viajeros</dt><dd>${r.adultes + r.enfants}${r.bebes ? ` + ${r.bebes} bebé${r.bebes > 1 ? "s" : ""}` : ""}</dd></div> <div><dt>A nombre de</dt><dd>${esc(r.nom)}</dd></div> <div><dt>Correo electrónico</dt><dd>${esc(r.email)}</dd></div>
        </dl>
        ${r.cents ? `<div class="booking__price">${r.lignes.map((l) => `<p><span>${esc(window.SP_LABEL ? SP_LABEL(l.label) : l.label)}</span><span>${SP_EUR(l.cents)}</span></p>`).join("")}<p class="booking__total"><span>Total</span><strong>${SP_EUR(r.cents)}</strong></p></div>` : ""}
      </div> <p class="small">Guarda esta página: su dirección te permite seguir tu reserva. ¿Alguna pregunta? Escríbenos a <a class="link" href="mailto:${esc(email)}">${esc(email)}</a> indicando el número ${esc(r.id)}.</p>
      <p style="margin-top:36px"><a class="btn btn--ghost" href="${esc(r.page)}">Volver a la casa</a></p>`;
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
        box.innerHTML = `<h1 class="h1">Reserva no encontrada</h1><p class="lead" style="margin-top:20px">Puede que el enlace esté incompleto. Escríbenos a <a class="link" href="mailto:${esc(email)}">${esc(email)}</a>.</p>`;
      });
  };
  if (!id || !t) box.innerHTML = `<h1 class="h1">Reserva no encontrada</h1>`;
  else load(0);
})();
