/* ============================================================
   AlliaForm — version 2 : interactions
   Les tarifs sont dans la constante ROOMS (et dans la section
   « Tarifs » de index.html).
   ============================================================ */
(function () {
  "use strict";

  var ROOMS = {
    s12: { name: "Salle de 12 places", seats: 12, equip: [{ pcs: 0, price: 240 }, { pcs: 6, price: 290 }, { pcs: 12, price: 330 }] },
    s25: { name: "Salle de 25 places", seats: 25, equip: [{ pcs: 0, price: 420 }, { pcs: 25, price: 600 }] }
  };
  var LUNCH = 20;
  var EMAIL = "contact@alliaform.fr";

  var $ = function (s, c) { return (c || document).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || document).querySelectorAll(s)); };
  var nf = new Intl.NumberFormat("fr-FR");
  var NBSP = " ";
  var eur = function (n) { return nf.format(n).replace(/[  ]/g, NBSP) + NBSP + "€"; };

  // ---------- Menu ----------
  var btn = $(".menu-btn");
  function setMenu(open) {
    document.body.classList.toggle("menu-open", open);
    btn.setAttribute("aria-expanded", String(open));
  }
  btn.addEventListener("click", function () { setMenu(btn.getAttribute("aria-expanded") !== "true"); });
  $$("#menu a").forEach(function (a) { a.addEventListener("click", function () { setMenu(false); }); });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && document.body.classList.contains("menu-open")) { setMenu(false); btn.focus(); }
  });
  window.addEventListener("resize", function () { if (window.innerWidth > 900) setMenu(false); });

  // ---------- Section courante dans le menu ----------
  var links = $$('.nav > a[href^="#"]');
  var sections = $$("main section[id]");
  var ticking = false;
  function current() {
    ticking = false;
    var mid = window.innerHeight * 0.4, id = "";
    sections.forEach(function (s) { if (s.getBoundingClientRect().top <= mid) id = s.id; });
    links.forEach(function (a) {
      if (a.getAttribute("href") === "#" + id) a.setAttribute("aria-current", "true");
      else a.removeAttribute("aria-current");
    });
  }
  window.addEventListener("scroll", function () { if (!ticking) { ticking = true; requestAnimationFrame(current); } }, { passive: true });
  current();

  // ---------- « Une journée ici » : l'heure qu'il est à Bordeaux ----------
  (function dayNow() {
    var marker = $("#day-now"), text = $("#day-now-text");
    if (!marker || !text) return;
    var parts = {};
    try {
      new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Paris", weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
        .formatToParts(new Date()).forEach(function (p) { parts[p.type] = p.value; });
    } catch (e) { return; }
    var h = parseInt(parts.hour, 10), m = parseInt(parts.minute, 10);
    if (isNaN(h) || parts.weekday === "Sat" || parts.weekday === "Sun") return;
    var t = h + m / 60;
    if (t < 8 || t > 18) return;
    var moment = t < 8.5 ? "la salle se prépare" : t < 12.5 ? "c'est la matinée de formation" : t < 13.5 ? "c'est l'heure du déjeuner" : t < 17.5 ? "c'est l'après-midi de formation" : "la journée se termine";
    marker.style.setProperty("--t", ((t - 8) * 10).toFixed(2));
    marker.hidden = false;
    text.textContent = "Il est " + h + NBSP + "h" + NBSP + (m < 10 ? "0" : "") + m + " à Bordeaux : dans une journée type, " + moment + ".";
    text.hidden = false;
  })();

  // ---------- Les salles : équipement et ordinateurs sur le plan ----------
  $$(".room-config").forEach(function (group) {
    var plan = document.getElementById(group.getAttribute("data-plan"));
    var room = group.closest(".room");
    var out = $(".price-out", room), what = $(".price-what", room), fig = $(".room-plan", room);
    if (plan) $$(".p-pc", plan).forEach(function (pc, i) { pc.style.transitionDelay = (i * 22) + "ms"; });
    $$("button", group).forEach(function (b) {
      b.addEventListener("click", function () {
        var pcs = parseInt(b.getAttribute("data-pcs"), 10);
        $$("button", group).forEach(function (x) { x.setAttribute("aria-pressed", String(x === b)); });
        if (plan) plan.setAttribute("data-pcs", String(pcs));
        if (fig) fig.classList.toggle("has-pcs", pcs > 0);
        if (out) out.textContent = eur(parseInt(b.getAttribute("data-price"), 10));
        if (what) what.textContent = pcs ? ", avec " + pcs + " ordinateurs" : ", sans ordinateur";
      });
    });
  });

  // ---------- Le tram entre dans le dessin des quais ----------
  var pano = $(".panorama");
  if (pano) {
    if ("IntersectionObserver" in window) {
      var tramIo = new IntersectionObserver(function (en) {
        if (en[en.length - 1].isIntersecting) { pano.classList.add("go"); tramIo.disconnect(); }
      }, { threshold: 0.6 });
      tramIo.observe(pano);
    } else pano.classList.add("go");
  }

  // ---------- Formulaire « lettre » ----------
  var form = $("#quote");
  if (form) {
    var f = {
      nom: $("#f-nom"), org: $("#f-org"), salle: $("#f-salle"), pc: $("#f-pc"), duree: $("#f-duree"), date: $("#f-date"),
      nb: $("#f-nb"), dej: $("#f-dej"), email: $("#f-email"), tel: $("#f-tel"), msg: $("#f-msg")
    };
    var errorBox = $("#f-error"), total = $("#f-total"), detail = $("#f-detail"), sent = $("#f-sent");
    var lastText = "";

    var today = new Date();
    today.setMinutes(today.getMinutes() - today.getTimezoneOffset());
    f.date.min = today.toISOString().slice(0, 10);

    var findEquip = function (room, pcs) {
      var list = ROOMS[room].equip;
      for (var i = 0; i < list.length; i++) if (list[i].pcs === pcs) return list[i];
      return null;
    };
    var pcLabel = function (n) { return n ? "avec " + n + " ordinateurs" : "sans ordinateur"; };

    var fillPc = function () {
      var room = ROOMS[f.salle.value], current = parseInt(f.pc.value, 10) || 0;
      f.pc.innerHTML = room.equip.map(function (e) { return '<option value="' + e.pcs + '">' + pcLabel(e.pcs) + "</option>"; }).join("");
      var eq = findEquip(f.salle.value, current) || (current ? findEquip(f.salle.value, room.seats) : room.equip[0]);
      f.pc.value = String(eq.pcs);
    };

    // Champs à largeur automatique (selon le texte choisi)
    var sizer = document.createElement("span");
    sizer.setAttribute("aria-hidden", "true");
    sizer.style.cssText = "position:absolute;visibility:hidden;white-space:pre;left:-9999px;top:0";
    form.appendChild(sizer);
    var fit = function (sel) {
      var cs = getComputedStyle(sel);
      ["fontFamily", "fontSize", "fontWeight", "fontStyle", "letterSpacing"].forEach(function (k) { sizer.style[k] = cs[k]; });
      sizer.textContent = sel.options[sel.selectedIndex].text;
      var w = sizer.getBoundingClientRect().width + parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight) + 4;
      sel.style.width = Math.min(Math.ceil(w), sel.parentNode.getBoundingClientRect().width) + "px";
    };
    var fitAll = function () { [f.salle, f.pc, f.duree, f.dej].forEach(fit); };

    var compute = function () {
      var room = ROOMS[f.salle.value], eq = findEquip(f.salle.value, parseInt(f.pc.value, 10)) || room.equip[0];
      var d = f.duree.value, days = parseInt(d, 10);
      var people = Math.max(0, Math.min(200, parseInt(f.nb.value, 10) || 0));
      var lunch = f.dej.value === "oui";
      var label = room.name + (eq.pcs ? ", avec " + eq.pcs + " ordinateurs" : "");
      var res = { label: label, room: room, people: people, lunch: lunch, days: isNaN(days) ? 0 : days, total: null, info: "" };
      if (!isNaN(days)) {
        var meals = lunch && people ? people * days : 0;
        res.total = days * eq.price + meals * LUNCH;
        res.info = days + (days > 1 ? " jours" : " jour") + ", " + label.charAt(0).toLowerCase() + label.slice(1) + (meals ? ", " + meals + " déjeuners" : "");
        if (lunch && !people) res.info += " (indiquez le nombre de participants pour les déjeuners)";
      } else if (d === "matin" || d === "apres-midi") {
        res.info = "Demi-journée à tarif réduit, précisé dans notre devis";
      } else {
        res.info = "Plusieurs sessions : devis sur mesure";
      }
      return res;
    };

    // L'estimation défile jusqu'au nouveau montant
    var shown = null, raf = 0;
    var calm = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var showTotal = function (to) {
      cancelAnimationFrame(raf);
      if (to === null) { shown = null; total.textContent = "Sur devis"; return; }
      var from = shown === null ? to : shown;
      if (calm || from === to) { shown = to; total.textContent = eur(to) + " HT"; return; }
      var t0 = performance.now();
      (function step(now) {
        var p = Math.min(1, (now - t0) / 550), v = Math.round(from + (to - from) * (1 - Math.pow(1 - p, 3)));
        shown = v;
        total.textContent = eur(v) + " HT";
        if (p < 1) raf = requestAnimationFrame(step);
      })(t0);
    };

    var render = function () {
      var r = compute();
      showTotal(r.total);
      detail.textContent = r.info;
    };

    f.salle.addEventListener("change", function () { fillPc(); fitAll(); render(); });
    [f.pc, f.duree, f.dej].forEach(function (s) { s.addEventListener("change", function () { fit(s); render(); }); });
    f.nb.addEventListener("input", render);
    // La zone de texte s'agrandit avec le message (lignes de la lettre comprises)
    var grow = function () { f.msg.style.height = "auto"; f.msg.style.height = Math.max(f.msg.scrollHeight, f.msg.clientHeight) + "px"; };
    f.msg.addEventListener("input", grow);
    [f.nom, f.email].forEach(function (el) { el.addEventListener("input", function () { el.removeAttribute("aria-invalid"); errorBox.hidden = true; }); });

    var dateFr = function (v) {
      if (!v) return "";
      var dt = new Date(v + "T12:00:00");
      return isNaN(dt) ? v : dt.toLocaleDateString("fr-FR", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
    };

    // « de » devient « d' » devant une voyelle : « d'Organisme Exemple »
    var de = function (org) { return /^[aeiouyàâäéèêëîïôöùûü]/i.test(org) ? "d'" + org : "de " + org; };
    var deLabel = $("#f-de");
    f.org.addEventListener("input", function () { deLabel.textContent = /^[aeiouyàâäéèêëîïôöùûü]/i.test(f.org.value.trim()) ? "d'" : "de"; });

    var optText = function (sel) { return sel.options[sel.selectedIndex].text; };

    var buildMail = function () {
      var r = compute(), org = f.org.value.trim();
      var horaires = { matin: " (de 8 h 30 à 12 h 30)", "apres-midi": " (de 13 h 30 à 17 h 30)" };
      var L = ["Bonjour,", ""];
      L.push("Je m'appelle " + f.nom.value.trim() + (org ? ", " + de(org) : "") + ".");
      var phrase = "Je cherche " + optText(f.salle) + " " + optText(f.pc) + " pour " + optText(f.duree) + (horaires[f.duree.value] || "");
      if (f.date.value) phrase += ", à partir du " + dateFr(f.date.value);
      if (r.people) phrase += ", pour " + r.people + " participant" + (r.people > 1 ? "s" : "");
      phrase += ", " + optText(f.dej) + ".";
      L.push(phrase);
      if (r.total !== null) L.push("", "Estimation indicative (site) : " + eur(r.total) + " HT.");
      if (f.msg.value.trim()) L.push("", f.msg.value.trim());
      L.push("", "Vous pouvez me répondre à " + f.email.value.trim() + (f.tel.value.trim() ? " ou au " + f.tel.value.trim() : "") + ".", "", "Cordialement,", f.nom.value.trim());
      var subject = "Demande de disponibilité – " + r.label + (f.date.value ? " – " + dateFr(f.date.value) : "");
      return { subject: subject, body: L.join("\r\n") };
    };

    var fail = function (msg, el) {
      errorBox.textContent = msg;
      errorBox.hidden = false;
      el.setAttribute("aria-invalid", "true");
      el.focus();
    };

    form.addEventListener("submit", function (e) {
      e.preventDefault();
      errorBox.hidden = true;
      if (!f.nom.value.trim()) return fail("Indiquez votre nom, pour que nous sachions à qui répondre.", f.nom);
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(f.email.value.trim())) return fail("Indiquez une adresse e-mail valide, pour que nous puissions vous répondre.", f.email);
      var mail = buildMail();
      lastText = "À : " + EMAIL + "\r\nObjet : " + mail.subject + "\r\n\r\n" + mail.body;
      window.location.href = "mailto:" + EMAIL + "?subject=" + encodeURIComponent(mail.subject) + "&body=" + encodeURIComponent(mail.body);
      form.hidden = true;
      sent.hidden = false;
      sent.focus();
    });

    $("#f-edit").addEventListener("click", function () { sent.hidden = true; form.hidden = false; fitAll(); f.nom.focus(); });

    $("#f-copy").addEventListener("click", function () {
      var b = this;
      var done = function (ok) {
        b.textContent = ok ? "Demande copiée" : "Copie impossible";
        setTimeout(function () { b.textContent = "Copier la demande"; }, 2600);
      };
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(lastText).then(function () { done(true); }, function () { done(copyFallback(lastText)); });
      } else done(copyFallback(lastText));
    });

    var copyFallback = function (t) {
      var ta = document.createElement("textarea");
      ta.value = t; ta.setAttribute("readonly", ""); ta.style.position = "fixed"; ta.style.opacity = "0";
      document.body.appendChild(ta); ta.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
      document.body.removeChild(ta);
      return ok;
    };

    fillPc();
    render();
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitAll); else fitAll();
    window.addEventListener("resize", fitAll);
  }

  // ---------- Barre mobile et année ----------
  var year = $("#year");
  if (year) year.textContent = String(new Date().getFullYear());
  var quick = $("#quick"), hero = $(".hero, .page-hero"), contact = $("#contact, .cta");
  if (quick && hero && "IntersectionObserver" in window) {
    var heroIn = true, contactIn = false;
    var upd = function () { quick.classList.toggle("show", !heroIn && !contactIn); };
    new IntersectionObserver(function (en) { heroIn = en[en.length - 1].isIntersecting; upd(); }, { threshold: 0.02 }).observe(hero);
    if (contact) new IntersectionObserver(function (en) { contactIn = en[en.length - 1].isIntersecting; upd(); }, { threshold: 0.02 }).observe(contact);
  }
})();
