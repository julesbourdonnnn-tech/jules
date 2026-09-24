/* Comparateur : jusqu'à 3 lieux côte à côte.
 * Les lieux viennent de l'adresse (comparer.html?ids=a,b,c, pratique à partager)
 * ou, à défaut, de la sélection mémorisée dans le navigateur. */
(function () {
  const NS = window.NS;
  const { escapeHtml: e, img, budgetOf, budgetHtml, distanceKm, formatDistance, getUserLocation, tagsOf } = NS;
  const HOTELS = window.HOTELS, TYPES = window.TYPES, ENVS = window.ENVIRONMENTS, TAGS = window.TAGS;
  const root = document.getElementById("compare-root");
  const find = (id) => HOTELS.find((h) => h.id === id);

  function fromUrl() {
    const p = new URLSearchParams(location.search).get("ids");
    if (!p) return null;
    return p.split(",").map((x) => x.trim()).filter((id) => find(id)).slice(0, 3);
  }

  function empty() {
    const favs = NS.getFavs().filter(find);
    const picks = HOTELS.filter((h) => h.featured).slice(0, 6);
    root.innerHTML = `
      <div class="compare-empty">
        <h2>Votre comparateur est vide</h2>
        <p class="lead">Touchez le bouton <span class="cmp-icon">⇄</span> sur une fiche ou une carte pour ajouter un lieu (trois au maximum).</p>
        ${favs.length >= 2 ? `<button type="button" class="btn btn-primary" data-from-favs>Comparer mes ${Math.min(favs.length, 3)} premiers coups de cœur</button>` : ""}
        <p class="eyebrow dark">Pour commencer, nos coups de cœur</p>
        <div class="grid">${picks.map((h) => NS.card(h, { reveal: false })).join("")}</div>
      </div>`;
    NS.syncCompare();
    const b = root.querySelector("[data-from-favs]");
    if (b) b.addEventListener("click", () => NS.setCompare(favs.slice(0, 3)));
  }

  function row(label, cells, cls = "") {
    return `<tr class="${cls}"><th scope="row">${e(label)}</th>${cells.map((c) => `<td>${c}</td>`).join("")}</tr>`;
  }
  const list = (items) => items.length ? `<ul>${items.map((x) => `<li>${e(x)}</li>`).join("")}</ul>` : `<span class="muted">—</span>`;

  function render() {
    const ids = NS.getCompare();
    if (!ids.length) return empty();
    const hs = ids.map(find);
    const loc = getUserLocation();
    const minBudget = Math.min(...hs.map((h) => h.budget));
    root.innerHTML = `
      <div class="cmp-actions">
        <p><strong>${hs.length} lieu${hs.length > 1 ? "x" : ""}</strong> comparé${hs.length > 1 ? "s" : ""}</p>
        <div>
          <button type="button" class="btn btn-ghost" data-share>↗ Partager la comparaison</button>
          <button type="button" class="btn-text" data-clear>Tout retirer</button>
        </div>
      </div>
      <div class="cmp-scroll">
        <table class="cmp-table cols-${hs.length}">
          <thead>
            <tr>
              <td class="cmp-corner"></td>
              ${hs.map((h) => `
                <th scope="col">
                  <a class="cmp-photo" href="${NS.hotelUrl(h)}"><img src="${img(h.images[0], 900)}" alt="${e(h.name)}"></a>
                  <button type="button" class="cmp-remove" data-remove="${e(h.id)}" aria-label="Retirer ${e(h.name)}">×</button>
                  <p class="card-type">${TYPES[h.type].icon} ${e(TYPES[h.type].label)}</p>
                  <a class="cmp-name" href="${NS.hotelUrl(h)}">${e(h.name)}</a>
                  <p class="cmp-tagline">${e(h.tagline)}</p>
                </th>`).join("")}
              ${hs.length < 3 ? `<td class="cmp-add"><a href="index.html#explorer"><span>＋</span>Ajouter un lieu</a></td>` : ""}
            </tr>
          </thead>
          <tbody>
            ${row("Où", hs.map((h) => `${e(h.city)}<br><span class="muted">${e(h.department)} · ${e(h.region)}</span>${loc ? `<br><span class="cmp-dist">📍 à ${formatDistance(distanceKm(loc, h))} de chez vous</span>` : ""}`))}
            ${row("Ambiance", hs.map((h) => e(ENVS[h.env].label)))}
            ${row("Budget indicatif", hs.map((h) => `${budgetHtml(h)}<br><span class="muted">${e(budgetOf(h).range)}</span>${hs.length > 1 && h.budget === minBudget ? `<br><span class="cmp-best">Le plus doux</span>` : ""}`))}
            ${row("Hébergement", hs.map((h) => e(h.rooms)))}
            ${row("Envies", hs.map((h) => { const t = tagsOf(h); return t.length ? `<ul class="cmp-tags">${t.map((k) => `<li>${TAGS[k].icon} ${e(TAGS[k].short)}</li>`).join("")}</ul>` : `<span class="muted">—</span>`; }))}
            ${row("Pourquoi on l'aime", hs.map((h) => list(h.highlights)))}
            ${row("C'est pour vous si…", hs.map((h) => list(h.forYou || [])))}
            ${row("Moins pour vous si…", hs.map((h) => list(h.notForYou || [])))}
            ${row("Sur place", hs.map((h) => list(h.amenities)))}
            ${hs.some((h) => h.season) ? row("Saison", hs.map((h) => h.season ? e(h.season) : `<span class="muted">—</span>`)) : ""}
            ${row("Réserver", hs.map((h) => `
              <a class="btn btn-primary btn-block" href="${e(NS.bookingLink(h))}" target="_blank" rel="sponsored noopener" data-track="Réservation" data-hotel="${e(h.id)}" data-book="${e(h.id)}">Voir les prix</a>
              <a class="btn btn-ghost btn-block" href="${NS.hotelUrl(h)}">La fiche complète</a>`), "cmp-cta")}
          </tbody>
        </table>
      </div>`;
    root.querySelectorAll("[data-remove]").forEach((b) => b.addEventListener("click", () => NS.setCompare(NS.getCompare().filter((id) => id !== b.dataset.remove))));
    root.querySelector("[data-clear]").addEventListener("click", () => NS.setCompare([]));
    root.querySelector("[data-share]").addEventListener("click", async () => {
      const url = `${location.origin}${location.pathname}?ids=${NS.getCompare().join(",")}`;
      try {
        if (navigator.share) await navigator.share({ title: "Ma comparaison de nuits insolites", url });
        else { await navigator.clipboard.writeText(url); NS.toast("Lien de la comparaison copié !"); }
      } catch { /* partage annulé */ }
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    const ids = fromUrl();
    if (ids && ids.length) NS.setCompare(ids);
    render();
    document.addEventListener("compare:change", render);
  });
})();
