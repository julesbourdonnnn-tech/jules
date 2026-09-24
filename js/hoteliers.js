/* Page « Espace hôteliers » : offres, tarifs et formulaire de candidature. */
(function () {
  const { escapeHtml, formatPrice, CONFIG } = window.NS;
  const $ = (sel) => document.querySelector(sel);

  document.addEventListener("DOMContentLoaded", () => {
    const plans = Object.entries(CONFIG.plans);

    $("#plans").innerHTML = plans.map(([key, p]) => `
      <div class="plan ${p.highlight ? "plan-hl" : ""}">
        ${p.highlight ? `<span class="plan-tag">Le plus choisi</span>` : ""}
        <h3>${escapeHtml(p.name)}</h3>
        <p class="muted">${escapeHtml(p.pitch)}</p>
        <p class="plan-price">${p.price ? `${formatPrice(p.price)}<span>${escapeHtml(p.period)}</span>` : "Gratuit"}</p>
        <ul>${p.features.map((f) => `<li>${escapeHtml(f)}</li>`).join("")}</ul>
        <a class="btn ${p.highlight ? "btn-primary" : "btn-ghost"} btn-block" href="#candidature" data-plan="${key}">
          ${p.price ? "Choisir " + escapeHtml(p.name) : "Proposer mon lieu"}
        </a>
        ${p.paymentLink ? `<a class="plan-pay" href="${escapeHtml(p.paymentLink)}" target="_blank" rel="noopener">Candidature validée ? Payer en ligne →</a>` : ""}
      </div>`).join("");

    $("#extras").innerHTML = CONFIG.extras
      .map((x) => `<li><span>${escapeHtml(x.name)}</span><strong>${formatPrice(x.price)}</strong></li>`)
      .join("");

    const select = $("#offre");
    select.innerHTML = plans
      .map(([key, p]) => `<option value="${key}">${escapeHtml(p.name)}${p.price ? ` — ${p.price} €${escapeHtml(p.period)}` : " — gratuit"}</option>`)
      .join("") + CONFIG.extras.map((x) => `<option value="${escapeHtml(x.name)}">${escapeHtml(x.name)} — ${x.price} €</option>`).join("");

    // Pré-remplissage depuis l'URL : hoteliers.html?plan=premium&hotel=id-de-la-fiche
    const params = new URLSearchParams(location.search);
    const preset = params.get("plan") || (params.get("hotel") ? "partenaire" : "premium");
    if (CONFIG.plans[preset]) select.value = preset;
    const hotel = window.HOTELS.find((h) => h.id === params.get("hotel"));
    if (hotel) {
      $("#fiche").value = hotel.id;
      document.querySelector('[name="etablissement"]').value = hotel.name;
      document.querySelector('[name="ville"]').value = hotel.city;
    }

    document.addEventListener("click", (e) => {
      const a = e.target.closest("[data-plan]");
      if (a) select.value = a.dataset.plan;
    });

    $("#pay-note").textContent = "Après validation, vous recevez un lien de paiement sécurisé. Aucun paiement n'est demandé à la candidature.";
  });
})();
