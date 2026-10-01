/* ============================================================
   AlliaForm — interactions du site
   Les tarifs sont dans la constante ROOMS ci-dessous (et dans le
   tableau « Tous nos tarifs » de index.html).
   ============================================================ */
(function () {
  "use strict";

  // ---------- Tarifs (HT, la journée) ----------
  var ROOMS = {
    s12: { name: "Salle 12 places", seats: 12, equip: [{ pcs: 0, price: 240 }, { pcs: 6, price: 290 }, { pcs: 12, price: 330 }] },
    s25: { name: "Salle 25 places", seats: 25, equip: [{ pcs: 0, price: 420 }, { pcs: 25, price: 600 }] }
  };
  var LUNCH = 20; // formule déjeuner, HT par personne
  var EMAIL = "contact@alliaform.fr";

  var $ = function (sel, ctx) { return (ctx || document).querySelector(sel); };
  var $$ = function (sel, ctx) { return Array.prototype.slice.call((ctx || document).querySelectorAll(sel)); };
  var nf = new Intl.NumberFormat("fr-FR");
  // Espaces insécables classiques (certaines polices n'ont pas l'espace fine)
  var eur = function (n) { return nf.format(n).replace(/[\u202f\u2009]/g, "\u00a0") + "\u00a0€"; };
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function equipLabel(pcs) { return pcs ? pcs + " ordinateurs" : "Sans ordinateur"; }
  function findEquip(room, pcs) {
    var list = ROOMS[room].equip;
    for (var i = 0; i < list.length; i++) if (list[i].pcs === pcs) return list[i];
    return list[0];
  }

  // ---------- En-tête ----------
  var header = $(".site-header");
  function onScroll() { header.classList.toggle("scrolled", window.scrollY > 8); }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // ---------- Menu mobile ----------
  var toggle = $(".menu-toggle");
  function setMenu(open) {
    document.body.classList.toggle("menu-open", open);
    toggle.setAttribute("aria-expanded", String(open));
    toggle.setAttribute("aria-label", open ? "Fermer le menu" : "Ouvrir le menu");
  }
  toggle.addEventListener("click", function () { setMenu(toggle.getAttribute("aria-expanded") !== "true"); });
  $$("#menu a").forEach(function (a) { a.addEventListener("click", function () { setMenu(false); }); });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && document.body.classList.contains("menu-open")) { setMenu(false); toggle.focus(); }
  });
  window.addEventListener("resize", function () { if (window.innerWidth > 960) setMenu(false); });

  // ---------- Lien actif dans le menu ----------
  // La section active est la dernière dont le haut a dépassé le milieu de l'écran ;
  // les sections sans lien (accueil, « Tout compris », histoire…) n'allument rien.
  var navLinks = $$('.nav > a[href^="#"]');
  var spySections = $$("main > section[id]");
  var spyTicking = false;
  function updateCurrent() {
    spyTicking = false;
    var mid = window.innerHeight / 2, currentId = "";
    spySections.forEach(function (s) { if (s.getBoundingClientRect().top <= mid) currentId = s.id; });
    navLinks.forEach(function (a) {
      if (a.getAttribute("href") === "#" + currentId) a.setAttribute("aria-current", "true");
      else a.removeAttribute("aria-current");
    });
  }
  window.addEventListener("scroll", function () {
    if (!spyTicking) { spyTicking = true; window.requestAnimationFrame(updateCurrent); }
  }, { passive: true });
  updateCurrent();

  // ---------- Apparitions au défilement ----------
  var reveals = $$(".reveal");
  if ("IntersectionObserver" in window && !reduceMotion) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) { entry.target.classList.add("in"); io.unobserve(entry.target); }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add("in"); });
  }

  // ============================================================
  // Configurateur de salle : plan, équipement et tarif
  // ============================================================
  var cfg = { room: "s12", pcs: 0, layout: "classe" };
  var furniture = $("#plan-furniture");
  var SVGNS = "http://www.w3.org/2000/svg";

  // Dimensions du plan (unités du viewBox 600 × 420)
  var GEO = {
    s12: {
      classe: { groups: [2, 2], rows: 3, pitch: 62, aisle: 56, top: 146, step: 76, tableH: 26, chairW: 28, chairH: 14 },
      u: { arm: 4, bottom: 4, pitchArm: 52, pitchBottom: 62, top: 118, tableT: 26, chairW: 28, chairH: 14 }
    },
    s25: {
      classe: { groups: [3, 2], rows: 5, pitch: 48, aisle: 44, top: 124, step: 50, tableH: 20, chairW: 24, chairH: 11 },
      u: { arm: 8, bottom: 9, pitchArm: 27, pitchBottom: 36, top: 112, tableT: 20, chairW: 22, chairH: 11 }
    }
  };

  function rect(x, y, w, h, cls, rx) {
    return '<rect class="' + cls + '" x="' + x.toFixed(1) + '" y="' + y.toFixed(1) + '" width="' + w.toFixed(1) + '" height="' + h.toFixed(1) + '" rx="' + (rx || 3) + '"/>';
  }

  // Ordinateur vu de dessus ; « dir » = côté de l'écran (face au participant)
  function laptop(x, y, dir, s) {
    var a = 18 * s, b = 12 * s, t = 3.6 * s;
    if (dir === "up") return rect(x - a / 2, y - b / 2, a, b, "plan-pc-base", 2) + rect(x - a / 2, y - b / 2 - t + 1, a, t, "plan-pc-screen", 1.5);
    if (dir === "right") return rect(x - b / 2, y - a / 2, b, a, "plan-pc-base", 2) + rect(x + b / 2 - 1, y - a / 2, t, a, "plan-pc-screen", 1.5);
    return rect(x - b / 2, y - a / 2, b, a, "plan-pc-base", 2) + rect(x - b / 2 - t + 1, y - a / 2, t, a, "plan-pc-screen", 1.5);
  }

  function buildPlan() {
    var room = ROOMS[cfg.room], g = GEO[cfg.room][cfg.layout];
    var tables = [], seats = [];
    var s = cfg.room === "s25" ? 0.85 : 1;

    if (cfg.layout === "classe") {
      var rowW = g.groups.reduce(function (sum, n) { return sum + n * g.pitch; }, 0) + g.aisle * (g.groups.length - 1);
      for (var r = 0; r < g.rows; r++) {
        var y = g.top + r * g.step, x = 300 - rowW / 2;
        g.groups.forEach(function (n) {
          tables.push(rect(x + 2, y, n * g.pitch - 4, g.tableH, "plan-table"));
          for (var k = 0; k < n; k++) {
            var cx = x + g.pitch * (k + 0.5);
            seats.push({ cx: cx, cy: y + g.tableH + 4 + g.chairH / 2, w: g.chairW, h: g.chairH, px: cx, py: y + g.tableH / 2 + 1, dir: "up" });
          }
          x += n * g.pitch + g.aisle;
        });
      }
    } else {
      var inner = g.bottom * g.pitchBottom, armLen = g.arm * g.pitchArm, T = g.tableT;
      var lx = 300 - inner / 2 - T, rx = 300 + inner / 2, by = g.top + armLen;
      tables.push(rect(lx, g.top, T, armLen + T, "plan-table"));
      tables.push(rect(rx, g.top, T, armLen + T, "plan-table"));
      tables.push(rect(lx + T - 1, by, inner + 2, T, "plan-table"));
      var i;
      for (i = 0; i < g.arm; i++) {
        var yy = g.top + g.pitchArm * (i + 0.5);
        seats.push({ cx: lx - 4 - g.chairH / 2, cy: yy, w: g.chairH, h: g.chairW, px: lx + T / 2, py: yy, dir: "right" });
      }
      for (i = 0; i < g.bottom; i++) {
        var xx = 300 - inner / 2 + g.pitchBottom * (i + 0.5);
        seats.push({ cx: xx, cy: by + T + 4 + g.chairH / 2, w: g.chairW, h: g.chairH, px: xx, py: by + T / 2 + 1, dir: "up" });
      }
      for (i = 0; i < g.arm; i++) {
        var y2 = g.top + g.pitchArm * (g.arm - i - 0.5);
        seats.push({ cx: rx + T + 4 + g.chairH / 2, cy: y2, w: g.chairH, h: g.chairW, px: rx + T / 2, py: y2, dir: "left" });
      }
    }

    // Ordinateurs : un par place, ou un pour deux
    var every = cfg.pcs >= room.seats ? 1 : (cfg.pcs ? Math.round(room.seats / cfg.pcs) : 0);
    var html = "";
    // Bureau du formateur (à droite, devant)
    html += '<g class="plan-item" style="--i:0">' + rect(424, 74, 86, 24, "plan-desk") + rect(454, 56, 26, 13, "plan-chair", 5) + "</g>";
    tables.forEach(function (t, i) { html += '<g class="plan-item" style="--i:' + (i + 1) + '">' + t + "</g>"; });
    seats.forEach(function (st, i) {
      var g2 = rect(st.cx - st.w / 2, st.cy - st.h / 2, st.w, st.h, "plan-chair", 5);
      if (every && i % every === 0) g2 += laptop(st.px, st.py, st.dir, s);
      html += '<g class="plan-item" style="--i:' + (i + tables.length + 1) + '">' + g2 + "</g>";
    });
    furniture.innerHTML = html;
    if (reduceMotion) $$(".plan-item", furniture).forEach(function (el) { el.style.animation = "none"; });
  }

  var priceEl = $("#cfg-price");
  function renderConfigurator(animatePrice) {
    var room = ROOMS[cfg.room], eq = findEquip(cfg.room, cfg.pcs);
    cfg.pcs = eq.pcs;
    priceEl.textContent = eur(eq.price);
    if (animatePrice && !reduceMotion) { priceEl.classList.remove("bump"); void priceEl.offsetWidth; priceEl.classList.add("bump"); }
    $("#plan-name").textContent = room.name;
    var pcsTxt = eq.pcs === 0 ? "sans ordinateur" : eq.pcs + " ordinateurs" + (eq.pcs < room.seats ? " (1 pour 2)" : "");
    $("#plan-count").textContent = room.seats + " places · " + pcsTxt;
    buildPlan();
  }

  function renderEquipChoices() {
    var box = $("#cfg-equip");
    box.innerHTML = ROOMS[cfg.room].equip.map(function (e) {
      return '<label class="pill"><input type="radio" name="cfg-equip" value="' + e.pcs + '"' + (e.pcs === cfg.pcs ? " checked" : "") + "><span>" + equipLabel(e.pcs) + "</span></label>";
    }).join("");
  }

  if (furniture) {
    $$('input[name="cfg-room"]').forEach(function (input) {
      input.addEventListener("change", function () {
        cfg.room = input.value;
        // Avec ordinateurs : on garde l'équipement complet de la nouvelle salle
        cfg.pcs = cfg.pcs ? ROOMS[cfg.room].seats : 0;
        renderEquipChoices();
        renderConfigurator(true);
      });
    });
    $("#cfg-equip").addEventListener("change", function (e) {
      if (e.target.name !== "cfg-equip") return;
      cfg.pcs = parseInt(e.target.value, 10);
      renderConfigurator(true);
    });
    $$('input[name="cfg-layout"]').forEach(function (input) {
      input.addEventListener("change", function () { cfg.layout = input.value; buildPlan(); });
    });
    // Le navigateur peut restaurer les choix après un retour arrière
    var checkedRoom = $('input[name="cfg-room"]:checked'), checkedLayout = $('input[name="cfg-layout"]:checked');
    if (checkedRoom) cfg.room = checkedRoom.value;
    if (checkedLayout) cfg.layout = checkedLayout.value;
    var checkedEquip = $('input[name="cfg-equip"]:checked');
    if (checkedEquip) cfg.pcs = findEquip(cfg.room, parseInt(checkedEquip.value, 10)).pcs;
    renderEquipChoices();
    renderConfigurator(false);
  }

  // ============================================================
  // Formulaire de demande de devis
  // ============================================================
  var form = $("#quote");
  if (!form) return finish();

  var f = {
    objet: $("#q-objet"), salle: $("#q-salle"), pc: $("#q-pc"), formule: $("#q-formule"), date: $("#q-date"),
    jours: $("#q-jours"), participants: $("#q-participants"), dejeuner: $("#q-dejeuner"), nom: $("#q-nom"),
    organisme: $("#q-organisme"), email: $("#q-email"), tel: $("#q-tel"), message: $("#q-message")
  };
  var roomBlock = $("#q-room-block"), capHint = $("#q-capacity"), errorBox = $("#q-error");
  var totalEl = $("#q-total"), detailEl = $("#q-detail"), sent = $("#q-sent");
  var lastText = "";

  // Pas de date passée
  var today = new Date();
  today.setMinutes(today.getMinutes() - today.getTimezoneOffset());
  f.date.min = today.toISOString().slice(0, 10);

  function fillPcOptions(keep) {
    var room = ROOMS[f.salle.value], current = parseInt(keep, 10) || 0;
    f.pc.innerHTML = room.equip.map(function (e) { return '<option value="' + e.pcs + '">' + equipLabel(e.pcs) + "</option>"; }).join("");
    var eq = findEquip(f.salle.value, current);
    if (current && eq.pcs !== current) eq = findEquip(f.salle.value, room.seats);
    f.pc.value = String(eq.pcs);
  }

  function numberValue(input, min, max) {
    var n = parseInt(input.value, 10);
    if (isNaN(n)) return 0;
    return Math.max(min, Math.min(max, n));
  }

  function computeEstimate() {
    var room = ROOMS[f.salle.value], eq = findEquip(f.salle.value, parseInt(f.pc.value, 10));
    var days = numberValue(f.jours, 1, 60) || 1;
    var people = numberValue(f.participants, 0, 200);
    var fullDay = f.formule.value === "journee";
    var lunch = f.dejeuner.checked;
    var label = room.name + (eq.pcs ? " + " + eq.pcs + " ordinateurs" : "");
    var lines = [], total = 0;
    var meals = lunch && people ? people * days : 0;
    if (fullDay) {
      total = days * eq.price + meals * LUNCH;
      lines.push(days + (days > 1 ? " jours" : " jour") + " × " + label + " (" + eur(eq.price) + ")");
      if (meals) lines.push("+ " + meals + (meals > 1 ? " déjeuners" : " déjeuner") + " × " + eur(LUNCH));
    } else {
      lines.push("Tarif demi-journée réduit, précisé dans notre devis");
      if (meals) lines.push("· déjeuners : " + meals + " × " + eur(LUNCH) + " = " + eur(meals * LUNCH) + " HT");
    }
    if (lunch && !people) lines.push("· indiquez le nombre de participants pour estimer les déjeuners");
    return { fullDay: fullDay, total: total, meals: meals, lines: lines, label: label, days: days, people: people, room: room };
  }

  function renderEstimate() {
    var est = computeEstimate();
    totalEl.textContent = est.fullDay ? eur(est.total) + " HT" : "Sur devis";
    detailEl.textContent = est.lines.join(" ");
    // Capacité
    var msg = "";
    if (est.people > 25) msg = "Au-delà de 25 participants, précisez-le dans votre message : nous étudierons les possibilités avec vous.";
    else if (est.people > est.room.seats) msg = "Pour " + est.people + " participants, la salle 25 places est plus adaptée.";
    capHint.textContent = msg;
    capHint.hidden = !msg;
  }

  function syncObjet() { roomBlock.hidden = f.objet.value !== "location"; }

  f.salle.addEventListener("change", function () { fillPcOptions(f.pc.value); renderEstimate(); });
  [f.pc, f.formule, f.jours, f.participants, f.dejeuner].forEach(function (el) {
    el.addEventListener("input", renderEstimate);
    el.addEventListener("change", renderEstimate);
  });
  f.objet.addEventListener("change", syncObjet);
  [f.nom, f.email].forEach(function (el) { el.addEventListener("input", function () { el.removeAttribute("aria-invalid"); errorBox.hidden = true; }); });

  // « Demander cette salle » : reprend la configuration choisie
  var cfgCta = $("#cfg-cta");
  if (cfgCta) cfgCta.addEventListener("click", function () {
    f.objet.value = "location"; syncObjet();
    f.salle.value = cfg.room; fillPcOptions(cfg.pcs); renderEstimate();
    setTimeout(function () { try { f.date.focus({ preventScroll: true }); } catch (e) { f.date.focus(); } }, reduceMotion ? 0 : 700);
  });

  function formatDate(v) {
    if (!v) return "";
    var d = new Date(v + "T12:00:00");
    if (isNaN(d)) return v;
    return d.toLocaleDateString("fr-FR", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
  }

  function buildMessage() {
    var objets = {
      location: "louer une salle de formation",
      accompagnement: "en savoir plus sur votre accompagnement (logistique, administratif, commercial)",
      examens: "organiser des examens ou des concours chez AlliaForm",
      autre: "vous poser une question"
    };
    var L = [];
    L.push("Bonjour,", "", "Je souhaite " + objets[f.objet.value] + ".");
    var subject;
    if (f.objet.value === "location") {
      var est = computeEstimate(), formules = { journee: "Journée", matin: "Demi-journée, le matin (8 h 30 – 12 h 30)", "apres-midi": "Demi-journée, l'après-midi (13 h 30 – 17 h 30)" };
      L.push("");
      L.push("– Salle : " + est.label);
      L.push("– Formule : " + formules[f.formule.value]);
      if (f.date.value) L.push("– À partir du : " + formatDate(f.date.value));
      L.push("– Nombre de jours : " + est.days);
      if (est.people) L.push("– Participants : " + est.people);
      L.push("– Formule déjeuner : " + (f.dejeuner.checked ? "oui" : "non"));
      if (est.fullDay) L.push("– Estimation indicative (site) : " + eur(est.total) + " HT");
      else if (est.meals) L.push("– Déjeuners (estimation) : " + eur(est.meals * LUNCH) + " HT");
      subject = "Demande de devis – " + est.label + (f.date.value ? " – " + formatDate(f.date.value) : "");
    } else {
      subject = { accompagnement: "Demande d'information – Accompagnement", examens: "Demande d'information – Organisation d'examens", autre: "Question" }[f.objet.value] + " – AlliaForm";
    }
    if (f.message.value.trim()) L.push("", "Message :", f.message.value.trim());
    L.push("", "Cordialement,", f.nom.value.trim());
    if (f.organisme.value.trim()) L.push(f.organisme.value.trim());
    if (f.tel.value.trim()) L.push(f.tel.value.trim());
    L.push(f.email.value.trim());
    return { subject: subject, body: L.join("\r\n") };
  }

  function showError(msg, field) {
    errorBox.textContent = msg;
    errorBox.hidden = false;
    if (field) { field.setAttribute("aria-invalid", "true"); field.focus(); }
  }

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    errorBox.hidden = true;
    if (!f.nom.value.trim()) return showError("Merci d'indiquer votre nom.", f.nom);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(f.email.value.trim())) return showError("Merci d'indiquer une adresse e-mail valide, pour que nous puissions vous répondre.", f.email);
    var msg = buildMessage();
    lastText = "À : " + EMAIL + "\r\nObjet : " + msg.subject + "\r\n\r\n" + msg.body;
    window.location.href = "mailto:" + EMAIL + "?subject=" + encodeURIComponent(msg.subject) + "&body=" + encodeURIComponent(msg.body);
    form.hidden = true;
    sent.hidden = false;
    sent.focus();
  });

  $("#q-edit").addEventListener("click", function () {
    sent.hidden = true;
    form.hidden = false;
    f.nom.focus();
  });

  $("#q-copy").addEventListener("click", function () {
    var btn = this, label = $("span", btn);
    function done(ok) {
      label.textContent = ok ? "Demande copiée" : "Copie impossible : sélectionnez le texte";
      setTimeout(function () { label.textContent = "Copier ma demande"; }, 2600);
    }
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(lastText).then(function () { done(true); }, function () { done(fallbackCopy(lastText)); });
    } else {
      done(fallbackCopy(lastText));
    }
  });

  function fallbackCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }

  fillPcOptions(0);
  syncObjet();
  renderEstimate();
  finish();

  // ---------- Barre d'action mobile et année ----------
  function finish() {
    var year = $("#year");
    if (year) year.textContent = String(new Date().getFullYear());

    var bar = $("#mobile-bar"), hero = $(".hero"), contact = $("#contact");
    if (!bar || !hero || !("IntersectionObserver" in window)) return;
    var heroVisible = true, contactVisible = false;
    function update() { bar.classList.toggle("show", !heroVisible && !contactVisible); }
    new IntersectionObserver(function (en) { heroVisible = en[en.length - 1].isIntersecting; update(); }, { threshold: 0.05 }).observe(hero);
    if (contact) new IntersectionObserver(function (en) { contactVisible = en[en.length - 1].isIntersecting; update(); }, { threshold: 0.05 }).observe(contact);
  }
})();
