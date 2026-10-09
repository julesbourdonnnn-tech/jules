/* Le Pendolino : petites interactions de la page (sans bibliothèque). */
(function () {
  'use strict';

  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* --- En-tête : fond plein après un léger défilement --- */
  var header = document.querySelector('.site-header');
  function onScroll() { header.classList.toggle('is-scrolled', window.scrollY > 40); }
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  /* --- Menu mobile --- */
  var burger = document.querySelector('.burger');
  var nav = document.getElementById('mobile-nav');
  function setNav(open) {
    burger.setAttribute('aria-expanded', String(open));
    document.body.style.overflow = open ? 'hidden' : '';
    if (open) {
      nav.hidden = false;
      requestAnimationFrame(function () { nav.classList.remove('opacity-0', 'pointer-events-none'); });
      nav.querySelector('a').focus();
    } else {
      nav.classList.add('opacity-0', 'pointer-events-none');
      setTimeout(function () { nav.hidden = true; }, reduceMotion ? 0 : 300);
    }
  }
  burger.addEventListener('click', function () { setNav(true); });
  nav.querySelector('.close-nav').addEventListener('click', function () { setNav(false); burger.focus(); });
  nav.addEventListener('click', function (e) { if (e.target.closest('a')) setNav(false); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !nav.hidden) { setNav(false); burger.focus(); } });

  /* --- Onglets de la carte (clavier : flèches gauche/droite) --- */
  var tabs = Array.prototype.slice.call(document.querySelectorAll('[role="tab"]'));
  function selectTab(tab, focus) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
      var panel = document.getElementById(t.getAttribute('aria-controls'));
      panel.hidden = !on;
      if (on && !reduceMotion) {
        Array.prototype.forEach.call(panel.children, function (card, i) {
          card.style.animation = 'none';
          card.offsetHeight; // relance l'animation
          card.style.animation = 'fade-up .6s cubic-bezier(.2,.7,.2,1) ' + (i * 0.05) + 's both';
          // on retire l'animation une fois jouée, sinon elle bloquerait l'effet de survol
          card.addEventListener('animationend', function () { card.style.animation = ''; }, { once: true });
        });
      }
    });
    if (focus) { tab.focus(); tab.scrollIntoView({ block: 'nearest', inline: 'center', behavior: reduceMotion ? 'auto' : 'smooth' }); }
  }
  tabs.forEach(function (tab, i) {
    tab.addEventListener('click', function () { selectTab(tab, false); });
    tab.addEventListener('keydown', function (e) {
      var next = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : null;
      if (next === null) return;
      e.preventDefault();
      selectTab(tabs[(next + tabs.length) % tabs.length], true);
    });
  });

  /* --- Carrousel d'avis --- */
  var track = document.querySelector('.reviews');
  var slides = track.querySelectorAll('.review');
  var dotsBox = document.querySelector('.review-dots');
  var dots = Array.prototype.map.call(slides, function () {
    var d = document.createElement('span');
    d.className = 'h-1.5 w-1.5 rounded-full bg-basil/20 transition-all duration-300';
    dotsBox.appendChild(d);
    return d;
  });
  function step() { return slides[0].getBoundingClientRect().width + 20; }
  function current() { return Math.round(track.scrollLeft / step()); }
  function paintDots() {
    var c = Math.min(current(), dots.length - 1);
    dots.forEach(function (d, i) { d.className = 'h-1.5 rounded-full transition-all duration-300 ' + (i === c ? 'w-6 bg-tomato' : 'w-1.5 bg-basil/20'); });
  }
  function go(dir) {
    var atEnd = track.scrollLeft + track.clientWidth >= track.scrollWidth - 8;
    if (dir > 0 && atEnd) track.scrollTo({ left: 0 });
    else if (dir < 0 && track.scrollLeft <= 8) track.scrollTo({ left: track.scrollWidth });
    else track.scrollBy({ left: dir * step() });
  }
  document.querySelector('.review-prev').addEventListener('click', function () { go(-1); });
  document.querySelector('.review-next').addEventListener('click', function () { go(1); });
  track.addEventListener('scroll', function () { requestAnimationFrame(paintDots); }, { passive: true });
  paintDots();

  // Défilement automatique doux, en pause au survol, au toucher ou au clavier
  if (!reduceMotion) {
    var paused = false, timer = null;
    ['mouseenter', 'focusin', 'touchstart'].forEach(function (ev) { track.addEventListener(ev, function () { paused = true; }, { passive: true }); });
    ['mouseleave', 'focusout'].forEach(function (ev) { track.addEventListener(ev, function () { paused = false; }); });
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        clearInterval(timer);
        if (entries[0].isIntersecting) timer = setInterval(function () { if (!paused && !document.hidden) go(1); }, 5500);
      }, { threshold: 0.4 }).observe(track);
    }
  }

  /* --- Apparition des blocs au défilement --- */
  var reveals = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window && !reduceMotion) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('is-visible'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.08 });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add('is-visible'); });
  }

  /* --- Photos manquantes : on garde l'emplacement décoratif --- */
  document.querySelectorAll('.photo img').forEach(function (img) {
    function miss() { img.closest('.photo').classList.add('is-missing'); }
    if (img.complete && img.naturalWidth === 0) miss(); else img.addEventListener('error', miss);
  });

  /* --- Horaires : jour en cours mis en avant + « Ouvert / Fermé » (heure de Paris) --- */
  var parts = {};
  try {
    new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Paris', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
      .formatToParts(new Date()).forEach(function (p) { parts[p.type] = p.value; });
  } catch (e) { /* navigateur ancien : on saute ce bonus */ }
  var dayIndex = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }[parts.weekday];
  if (dayIndex !== undefined) {
    var row = document.querySelector('.hours tr[data-day="' + dayIndex + '"]');
    row.classList.add('text-copper');
    row.querySelector('th').insertAdjacentHTML('beforeend', ' <span class="ml-1 rounded-full bg-copper/20 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider">Aujourd’hui</span>');
    var now = parseInt(parts.hour, 10) * 60 + parseInt(parts.minute, 10);
    var open = false, slot = row.getAttribute('data-open');
    function mins(t) { var h = t.split(':'); return h[0] * 60 + +h[1]; }
    if (slot) { var r = slot.split('-'); open = now >= mins(r[0]) && now < mins(r[1]); }
    var status = document.querySelector('.open-status');
    status.innerHTML = open
      ? '<span class="h-2 w-2 animate-pulse rounded-full bg-green-400"></span> Ouvert en ce moment'
      : '<span class="h-2 w-2 rounded-full bg-tomato"></span> Fermé actuellement';
    status.hidden = false;
  }

  var year = document.querySelector('.year');
  if (year) year.textContent = new Date().getFullYear();
})();
