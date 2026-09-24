/* Quiz « Quelle nuit insolite est faite pour vous ? »
 * Chaque réponse donne des points aux lieux qui y correspondent ; les trois
 * meilleurs sont proposés avec les raisons du choix. */
(function () {
  const NS = window.NS;
  const { escapeHtml: e, img, budgetOf, budgetHtml, tagsOf } = NS;
  const HOTELS = window.HOTELS, TYPES = window.TYPES, ENVS = window.ENVIRONMENTS;
  const $ = (id) => document.getElementById(id);
  const find = (id) => HOTELS.find((h) => h.id === id);
  const cover = (...ids) => { const h = ids.map(find).find(Boolean) || HOTELS[0]; return img(h.images[0], 900); };
  const has = (h, t) => tagsOf(h).includes(t);
  const GASTRO = /gastronomique|étoil|michelin|ducasse|darroze|passédat|deux étoiles/i;
  const WILD = ["cabane", "bulle", "eau", "etoiles", "chalet", "igloo", "phare", "troglodyte", "train", "moulin"];

  const QUESTIONS = [
    {
      key: "who", q: "Avec qui partez-vous ?",
      options: [
        { v: "deux", label: "À deux", sub: "Une parenthèse rien qu'à nous", img: () => cover("bulles-de-savoie", "attrap-reves-allauch") },
        { v: "famille", label: "En famille", sub: "Des souvenirs pour les enfants", img: () => cover("phare-de-kerbel") },
        { v: "amis", label: "Entre amis", sub: "Une aventure à partager", img: () => cover("ile-louet", "cabanes-des-grands-lacs") },
        { v: "chien", label: "Avec mon chien", sub: "Il fait partie du voyage", img: () => cover("domaine-des-etangs") },
      ],
    },
    {
      key: "env", q: "Quel décor vous fait rêver ?",
      options: [
        ...Object.entries(ENVS).map(([k, en]) => ({ v: k, label: en.label, sub: en.desc, img: () => cover(en.cover) })),
        { v: "", label: "Peu importe", sub: "Surprenez-moi !", img: () => cover("pic-du-midi") },
      ],
    },
    {
      key: "exp", q: "Quelle expérience vous tente le plus ?",
      options: [
        { v: "arbres", label: "Dans les arbres", sub: "Cabanes perchées et lodges", types: ["cabane"], img: () => cover("pella-roca") },
        { v: "etoiles", label: "Sous les étoiles", sub: "Bulles, observatoire, igloo", types: ["bulle", "etoiles", "igloo"], img: () => cover("attrap-reves-allauch") },
        { v: "eau", label: "Au fil de l'eau", sub: "Phares, bateaux, moulins", types: ["eau", "moulin", "phare", "mer"], img: () => cover("toue-cabanee-canal-de-bourgogne") },
        { v: "histoire", label: "Dans l'histoire", sub: "Châteaux, abbayes, troglodytes", types: ["chateau", "historique", "troglodyte", "train"], img: () => cover("fontevraud-l-ermitage") },
        { v: "design", label: "Design & art de vivre", sub: "Architecture, vignobles, chalets", types: ["design", "vignoble", "chalet"], img: () => cover("la-coorniche") },
      ],
    },
    {
      key: "must", q: "Votre indispensable ?",
      options: [
        { v: "spa", label: "Un bain chaud rien qu'à nous", sub: "Jacuzzi, sauna ou bain nordique privatif", img: () => cover("pella-roca") },
        { v: "table", label: "Une grande table", sub: "Dîner gastronomique sur place", img: () => cover("chateau-de-la-treyne", "domaine-des-etangs") },
        { v: "calme", label: "Déconnecter vraiment", sub: "Nature, silence et ciel étoilé", img: () => cover("loire-valley-lodges") },
        { v: "train", label: "Y aller sans voiture", sub: "En train et en transports", img: () => cover("refuge-du-montenvers") },
        { v: "", label: "Rien de spécial", sub: "Juste l'insolite", img: () => cover("gare-de-guiscriff", "hotel-le-corbusier") },
      ],
    },
    {
      key: "budget", q: "Votre budget pour une nuit à deux ?",
      options: [
        ...Object.entries(window.BUDGETS).map(([k, b]) => ({ v: k, label: b.range.replace(" la nuit", "").replace(/^./, (c) => c.toUpperCase()), sub: "€".repeat(k), img: null })),
        { v: "", label: "Peu importe", sub: "Pour une fois, on se fait plaisir", img: null },
      ],
    },
  ];

  /* ---------- Score ---------- */
  function score(h, a) {
    let pts = 0, max = 0;
    const why = [];
    // Avec qui
    max += 25;
    if (a.who === "deux") {
      const cosy = has(h, "spa-prive") || ["bulle", "cabane", "phare", "eau"].includes(h.type) || /deux|amoureux|romanti|intimit/i.test((h.forYou || []).join(" "));
      pts += cosy ? 25 : 12;
      if (cosy) why.push("Idéal à deux");
    } else if (a.who === "famille" || a.who === "amis") {
      if (has(h, "famille")) { pts += 25; why.push(a.who === "famille" ? "Parfait en famille" : "Pour toute la bande"); }
      else pts -= 15;
    } else if (a.who === "chien") {
      if (has(h, "chien")) { pts += 25; why.push("Votre chien est le bienvenu"); }
      else pts -= 60;
    }
    // Décor
    max += 20;
    if (!a.env) pts += 10;
    else if (h.env === a.env) { pts += 20; why.push(ENVS[a.env].inLabel[0].toUpperCase() + ENVS[a.env].inLabel.slice(1)); }
    // Expérience
    max += 25;
    const exp = QUESTIONS[2].options.find((o) => o.v === a.exp);
    if (exp && exp.types.includes(h.type)) { pts += 25; why.push(TYPES[h.type].label); }
    // Indispensable
    max += 20;
    if (!a.must) pts += 10;
    else if (a.must === "spa" && has(h, "spa-prive")) { pts += 20; why.push("Spa privatif"); }
    else if (a.must === "spa" && has(h, "bien-etre")) { pts += 10; why.push("Spa sur place"); }
    else if (a.must === "table" && (h.amenities.concat(h.highlights).some((x) => GASTRO.test(x)))) { pts += 20; why.push("Grande table"); }
    else if (a.must === "calme" && h.env !== "ville" && WILD.includes(h.type)) { pts += 20; why.push("Nature et silence"); }
    else if (a.must === "train" && has(h, "train")) { pts += 20; why.push("Accessible en train"); }
    // Budget
    max += 20;
    if (!a.budget) pts += 12;
    else {
      const d = Math.abs(h.budget - Number(a.budget));
      if (d === 0) { pts += 20; why.push("Dans votre budget"); }
      else if (d === 1) pts += 6;
      else pts -= 12;
    }
    return { h, pts, pct: Math.max(0, Math.min(99, Math.round((pts / max) * 100))), why };
  }
  function best(a) {
    return HOTELS.map((h) => score(h, a))
      .sort((x, y) => y.pts - x.pts || (y.h.featured ? 1 : 0) - (x.h.featured ? 1 : 0) || x.h.name.localeCompare(y.h.name, "fr"))
      .slice(0, 3);
  }

  /* ---------- Affichage ---------- */
  const answers = {};
  let step = 0;

  function setBg(src) {
    const bg = $("quiz-bg");
    if (!src) return;
    const layer = document.createElement("div");
    layer.style.backgroundImage = `url('${src}')`;
    bg.appendChild(layer);
    requestAnimationFrame(() => layer.classList.add("on"));
    while (bg.children.length > 2) bg.firstChild.remove();
  }

  function showStep() {
    const Q = QUESTIONS[step];
    $("quiz-intro").hidden = true;
    $("quiz-results").hidden = true;
    $("quiz-step").hidden = false;
    $("quiz-count").textContent = `Question ${step + 1} sur ${QUESTIONS.length}`;
    $("quiz-bar").style.width = `${((step + 1) / QUESTIONS.length) * 100}%`;
    $("quiz-back").style.visibility = step ? "visible" : "hidden";
    const q = $("quiz-question");
    q.textContent = Q.q;
    const box = $("quiz-options");
    box.className = `quiz-options ${Q.options[0].img ? "with-img" : "plain"} n${Q.options.length}`;
    box.setAttribute("aria-label", Q.q);
    box.innerHTML = Q.options.map((o, i) => `
      <button type="button" class="quiz-opt${answers[Q.key] === o.v ? " on" : ""}" data-i="${i}" style="--i:${i}">
        ${o.img ? `<img src="${o.img()}" alt="" loading="lazy">` : ""}
        <span class="quiz-opt-text"><strong>${e(o.label)}</strong><small>${e(o.sub)}</small></span>
      </button>`).join("");
    const first = Q.options.find((o) => o.img);
    if (first) setBg(first.img());
    q.focus({ preventScroll: true });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  function choose(i) {
    const Q = QUESTIONS[step];
    answers[Q.key] = Q.options[i].v;
    NS.track("Quiz", { hotel: `${Q.key}:${Q.options[i].v || "tout"}` });
    const btn = $("quiz-options").children[i];
    btn.classList.add("on");
    setTimeout(() => {
      if (step < QUESTIONS.length - 1) { step++; showStep(); }
      else showResults(best(answers), true);
    }, 260);
  }

  function showResults(res, fromQuiz) {
    $("quiz-intro").hidden = true;
    $("quiz-step").hidden = true;
    const box = $("quiz-results");
    box.hidden = false;
    if (res[0]) setBg(img(res[0].h.images[0]));
    const ids = res.map((r) => r.h.id).join(",");
    box.innerHTML = `
      <p class="eyebrow">${fromQuiz ? "Votre résultat" : "Une sélection partagée avec vous"}</p>
      <h2>${fromQuiz ? "Vos trois nuits idéales" : "Trois nuits insolites à découvrir"}</h2>
      <div class="quiz-cards">
        ${res.map((r, i) => `
          <article class="quiz-card" style="--i:${i}">
            <a class="quiz-card-media" href="${NS.hotelUrl(r.h)}">
              <img src="${img(r.h.images[0], 900)}" alt="${e(r.h.name)}">
              ${fromQuiz ? `<span class="quiz-match">${i === 0 ? "✦ " : ""}${r.pct} % pour vous</span>` : ""}
            </a>
            <div class="quiz-card-body">
              <p class="card-type">${TYPES[r.h.type].icon} ${e(TYPES[r.h.type].label)} · ${e(r.h.city)}</p>
              <h3><a href="${NS.hotelUrl(r.h)}">${e(r.h.name)}</a></h3>
              <p>${e(r.h.tagline)}</p>
              ${r.why.length ? `<ul class="quiz-why">${r.why.slice(0, 4).map((w) => `<li>✓ ${e(w)}</li>`).join("")}</ul>` : ""}
              <p class="quiz-budget">${budgetHtml(r.h)} <span>${e(budgetOf(r.h).range)}</span></p>
              <div class="quiz-card-cta">
                <a class="btn btn-primary" href="${NS.hotelUrl(r.h)}">Découvrir</a>
                <a class="btn btn-ghost" href="${e(NS.bookingLink(r.h))}" target="_blank" rel="sponsored noopener" data-track="Réservation" data-hotel="${e(r.h.id)}" data-book="${e(r.h.id)}">Voir les prix</a>
              </div>
            </div>
          </article>`).join("")}
      </div>
      <div class="quiz-after">
        <button type="button" class="btn btn-light" data-restart>${fromQuiz ? "↺ Refaire le quiz" : "Faire le quiz moi aussi"}</button>
        ${fromQuiz ? `<button type="button" class="btn btn-glass" data-share="${e(ids)}">↗ Partager mes résultats</button>
        <a class="btn btn-glass" href="comparer.html?ids=${e(ids)}">⇄ Les comparer</a>` : ""}
      </div>
      <div class="quiz-nl">
        <h3>Recevez chaque semaine des idées comme celles-ci</h3>
        ${NS.newsletterForm("quiz", "on-dark")}
      </div>`;
    NS.observeReveal(box);
    box.querySelector("[data-restart]").addEventListener("click", () => {
      Object.keys(answers).forEach((k) => delete answers[k]);
      step = 0;
      history.replaceState(null, "", location.pathname);
      showStep();
    });
    const share = box.querySelector("[data-share]");
    if (share) share.addEventListener("click", async () => {
      const url = `${location.origin}${location.pathname}?r=${share.dataset.share}`;
      try {
        if (navigator.share) await navigator.share({ title: "Mes nuits insolites idéales", text: "J'ai fait le quiz Nuits Singulières, voici mes trois nuits idéales :", url });
        else { await navigator.clipboard.writeText(url); NS.toast("Lien de vos résultats copié !"); }
      } catch { /* partage annulé */ }
    });
    box.querySelector("h2").setAttribute("tabindex", "-1");
    box.querySelector("h2").focus({ preventScroll: true });
    window.scrollTo({ top: 0, behavior: "smooth" });
    if (fromQuiz) NS.track("Quiz terminé", { hotel: ids });
  }

  document.addEventListener("DOMContentLoaded", () => {
    setBg(cover("attrap-reves-allauch"));
    $("quiz-start").addEventListener("click", () => { step = 0; showStep(); });
    $("quiz-back").addEventListener("click", () => { if (step > 0) { step--; showStep(); } });
    $("quiz-options").addEventListener("click", (ev) => {
      const b = ev.target.closest(".quiz-opt");
      if (b) choose(Number(b.dataset.i));
    });
    // Résultats partagés : quiz.html?r=id1,id2,id3
    const shared = (new URLSearchParams(location.search).get("r") || "").split(",").map(find).filter(Boolean).slice(0, 3);
    if (shared.length) showResults(shared.map((h) => ({ h, pct: 0, why: [] })), false);
  });
})();
