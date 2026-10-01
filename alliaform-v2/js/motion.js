/* ============================================================
   AlliaForm — version 2 : le mouvement
   Titres révélés mot à mot, filets tracés, plans dessinés, frise
   qui se remplit, texte qui s'écrit au défilement, dessin des quais
   vivant, en-tête qui s'efface. Si le visiteur préfère moins
   d'animations, tout s'affiche directement, sans mouvement.
   ============================================================ */
(function () {
  "use strict";

  var $ = function (s, c) { return (c || document).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || document).querySelectorAll(s)); };
  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var hasIO = "IntersectionObserver" in window;
  var animate = hasIO && !reduce;

  // ---------- Apparition quand l'élément arrive à l'écran ----------
  var callbacks = new Map();
  var io = animate ? new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (!e.isIntersecting) return;
      e.target.classList.add("in");
      var cb = callbacks.get(e.target);
      if (cb) cb(e.target);
      io.unobserve(e.target);
    });
  }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" }) : null;

  function watch(el, cb) {
    if (cb) callbacks.set(el, cb);
    if (io) io.observe(el);
    else { el.classList.add("in"); if (cb) cb(el); }
  }

  // Décale les éléments d'un même groupe pour qu'ils arrivent l'un après l'autre
  // (un élément masqué par clip-path n'est jamais « visible » pour le navigateur :
  // pour les volets, c'est donc le parent qui déclenche l'apparition)
  function stagger(selector, step, cls) {
    var groups = new Map();
    cls = cls || "rv";
    $$(selector).forEach(function (el) {
      if (el.hidden) return;
      var parent = el.parentNode;
      var list = groups.get(parent);
      if (!list) { list = []; groups.set(parent, list); }
      if (animate) {
        el.classList.add(cls);
        el.style.setProperty("--d", (list.length * step) / 1000 + "s");
      }
      list.push(el);
      if (cls !== "rv-wipe") watch(el);
    });
    if (cls === "rv-wipe") groups.forEach(function (list, parent) {
      watch(parent, function () { list.forEach(function (el) { el.classList.add("in"); }); });
    });
  }

  // ---------- Découpe d'un titre en mots (en gardant les espaces insécables) ----------
  function splitWords(el, wrapClass, innerClass) {
    var i = 0, words = [];
    (function walk(node) {
      Array.prototype.slice.call(node.childNodes).forEach(function (n) {
        if (n.nodeType === 3) {
          var frag = document.createDocumentFragment();
          n.textContent.split(/([ \t\n\r]+)/).forEach(function (part) {
            if (!part) return;
            if (/^[ \t\n\r]+$/.test(part)) { frag.appendChild(document.createTextNode(" ")); return; }
            var inner = document.createElement("span");
            inner.textContent = part;
            inner.style.setProperty("--i", i++);
            if (innerClass) inner.className = innerClass;
            if (wrapClass) {
              var w = document.createElement("span");
              w.className = wrapClass;
              w.appendChild(inner);
              frag.appendChild(w);
            } else frag.appendChild(inner);
            words.push(inner);
          });
          node.replaceChild(frag, n);
        } else if (n.nodeType === 1 && !n.classList.contains("sr")) walk(n);
      });
    })(el);
    return words;
  }

  // ---------- Titres des sections ----------
  $$(".sec h2:not(.sr)").forEach(function (h) {
    if (animate) { splitWords(h, "w"); h.classList.add("split"); }
    watch(h);
  });
  $$(".sec-head").forEach(function (el) { watch(el); });

  // ---------- Textes, listes et blocs ----------
  stagger(".sec-intro .lead", 0);
  stagger(".room-body > *", 70);
  stagger(".room-plan figcaption", 0);
  stagger(".spec-title", 0);
  stagger(".spec-list > div", 60, "rv-wipe");
  stagger(".table-detail figcaption", 0);
  stagger(".moments > li", 90);
  stagger(".day-now-text", 0);
  stagger(".price-col > h3", 0);
  stagger(".pricelist > li", 90);
  stagger(".price-side > div", 140);
  stagger(".exams > li", 90);
  stagger(".exam-note", 0);
  stagger(".cols > div", 120);
  stagger(".cols-cta", 0);
  stagger(".chrono > li", 90);
  stagger(".ways > li", 90);
  stagger(".map", 0, "rv-wipe");
  stagger(".faq > div", 70);
  stagger(".letter > p, .letter > .letter-foot", 60);
  stagger(".contact-direct > *", 100);

  // ---------- Les grands numéros des salles comptent jusqu'à 12 et 25 ----------
  $$(".room-num").forEach(function (el) {
    var to = parseInt(el.textContent, 10);
    if (!animate || isNaN(to)) return;
    el.textContent = "0";
    watch(el, function () {
      var t0 = null;
      (function step(ts) {
        if (t0 === null) t0 = ts;
        var p = Math.min(1, (ts - t0) / 1100);
        el.textContent = String(Math.round(to * (1 - Math.pow(1 - p, 4))));
        if (p < 1) requestAnimationFrame(step);
      })(performance.now());
    });
  });

  // ---------- Plans : les murs et les cotes se tracent, puis le mobilier ----------
  $$(".plan, .detail").forEach(function (svg) {
    if (!animate) return;
    var lines = $$(".p-wall, .p-dim, .p-tick", svg);
    lines.forEach(function (l) {
      var len = l.getTotalLength ? Math.ceil(l.getTotalLength()) : 0;
      if (!len) return;
      l.style.strokeDasharray = len + " " + len;
      l.style.strokeDashoffset = String(len);
    });
    $$(".p-table, .p-chair, .p-screen, .p-txt, .p-door, .p-num", svg).forEach(function (it, i) {
      it.style.transitionDelay = (450 + i * 22) + "ms";
    });
    svg.classList.add("pre");
    watch(svg, function () {
      svg.classList.remove("pre");
      lines.forEach(function (l) { l.style.strokeDashoffset = "0"; });
    });
  });

  // ---------- Frise de la journée ----------
  var track = $(".day-track");
  if (track) watch(track);

  // ---------- Histoire : le texte s'écrit au fil du défilement ----------
  var story = $(".story"), storyWords = [], storyShown = -1;
  if (story && animate) {
    storyWords = splitWords(story, null, "sw");
    story.classList.add("scrub");
  }

  // ---------- Dessin des quais et bandeau : animés seulement quand ils sont visibles ----------
  ["panorama", "ticker"].forEach(function (cls) {
    var el = $("." + cls);
    if (!el) return;
    if (!hasIO) { el.classList.add("live"); return; }
    new IntersectionObserver(function (en) {
      el.classList.toggle("live", en[en.length - 1].isIntersecting);
    }).observe(el);
  });

  // ---------- Au défilement : en-tête, barre de lecture, soleil, parallaxe ----------
  var mast = $(".mast");
  var bar = document.createElement("span");
  bar.className = "mast-progress";
  bar.setAttribute("aria-hidden", "true");
  if (mast) mast.appendChild(bar);
  var sun = $(".sun"), pano = $(".panorama");
  var nums = $$(".room-num");
  var lastY = window.scrollY, ticking = false;

  function onScroll() {
    ticking = false;
    var y = window.scrollY, vh = window.innerHeight;
    var max = document.documentElement.scrollHeight - vh;
    bar.style.setProperty("--p", max > 0 ? Math.min(1, y / max).toFixed(4) : "0");

    if (mast && !reduce) {
      var menuOpen = document.body.classList.contains("menu-open");
      if (!menuOpen && y > lastY + 6 && y > 260) mast.classList.add("hide");
      else if (y < lastY - 6 || y < 260 || menuOpen) mast.classList.remove("hide");
    }
    lastY = y;
    if (reduce) return;

    // Le soleil se couche derrière les toits à mesure qu'on descend
    if (sun && pano) {
      var r = pano.getBoundingClientRect();
      var p = (vh - r.top) / (vh + r.height);
      var off = Math.max(-20, Math.min(170, (p - 0.35) * 260));
      sun.style.transform = "translateY(" + off.toFixed(1) + "px)";
    }

    // Les grands numéros glissent un peu moins vite que la page
    nums.forEach(function (n) {
      var rr = n.parentNode.getBoundingClientRect();
      if (rr.bottom < -200 || rr.top > vh + 200) return;
      var c = rr.top + rr.height / 2 - vh / 2;
      n.style.translate = "0 " + (c * -0.09).toFixed(1) + "px";
    });

    // Le texte de l'histoire s'éclaire mot après mot
    if (storyWords.length) {
      var s = story.getBoundingClientRect();
      var prog = (vh * 0.88 - s.top) / (s.height + vh * 0.32);
      var n = Math.max(0, Math.min(storyWords.length, Math.round(prog * storyWords.length)));
      if (n !== storyShown) {
        storyShown = n;
        storyWords.forEach(function (w, i) { w.classList.toggle("on", i < n); });
      }
    }
  }
  window.addEventListener("scroll", function () { if (!ticking) { ticking = true; requestAnimationFrame(onScroll); } }, { passive: true });
  window.addEventListener("resize", onScroll);
  if (mast) mast.addEventListener("focusin", function () { mast.classList.remove("hide"); });
  onScroll();
})();
