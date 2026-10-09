/* Le Pendolino : interactions de la page et pizzas dessinées (sans bibliothèque). */
(function () {
  'use strict';

  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };

  /* =================================================================
     Pizzas dessinées
     Chaque <canvas data-pizza="…" data-seed="…"> reçoit une pizza peinte
     au hasard (mais toujours la même pour une graine donnée) : croûte
     tachetée par le four, sauce, fior di latte, garnitures.
     ================================================================= */
  function rng(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // Forme irrégulière (pâte, fromage, tranche…) autour de (x, y)
  function blob(ctx, x, y, r, irreg, rand, n) {
    n = n || 14;
    var ph1 = rand() * 6.28, ph2 = rand() * 6.28, pts = [];
    for (var i = 0; i < n; i++) {
      var a = (i / n) * Math.PI * 2;
      var k = 1 + irreg * (Math.sin(a * 3 + ph1) * 0.5 + Math.sin(a * 5 + ph2) * 0.3 + (rand() - 0.5) * 0.6);
      pts.push([x + Math.cos(a) * r * k, y + Math.sin(a) * r * k]);
    }
    ctx.beginPath();
    var last = pts[n - 1], first = pts[0];
    ctx.moveTo((last[0] + first[0]) / 2, (last[1] + first[1]) / 2);
    for (var j = 0; j < n; j++) {
      var p = pts[j], q = pts[(j + 1) % n];
      ctx.quadraticCurveTo(p[0], p[1], (p[0] + q[0]) / 2, (p[1] + q[1]) / 2);
    }
    ctx.closePath();
  }

  function radial(ctx, x, y, r, stops) {
    var g = ctx.createRadialGradient(x - r * 0.25, y - r * 0.3, r * 0.05, x, y, r);
    stops.forEach(function (s) { g.addColorStop(s[0], s[1]); });
    return g;
  }

  // Point au hasard dans un disque de rayon r
  function spot(rand, cx, cy, r) {
    var a = rand() * Math.PI * 2, d = Math.sqrt(rand()) * r;
    return [cx + Math.cos(a) * d, cy + Math.sin(a) * d];
  }

  function shadowed(ctx, R, fn) {
    ctx.save();
    ctx.shadowColor = 'rgba(60,25,10,.35)';
    ctx.shadowBlur = R * 0.025;
    ctx.shadowOffsetY = R * 0.01;
    fn();
    ctx.restore();
  }

  var paint = {
    mozza: function (ctx, rand, cx, cy, R, n, big) {
      for (var i = 0; i < n; i++) {
        var p = spot(rand, cx, cy, R * 0.6), r = R * (big ? 0.2 : 0.11 + rand() * 0.06);
        shadowed(ctx, R, function () {
          blob(ctx, p[0], p[1], r, 0.28, rand, 12);
          ctx.fillStyle = radial(ctx, p[0], p[1], r, [[0, '#FFFDF6'], [0.7, '#FBF1DC'], [1, '#EBD3A4']]);
          ctx.fill();
        });
        if (rand() > 0.45) { // petite dorure
          ctx.fillStyle = 'rgba(190,120,50,.35)';
          blob(ctx, p[0] + r * 0.25, p[1] - r * 0.2, r * 0.28, 0.4, rand, 8); ctx.fill();
        }
      }
    },
    basil: function (ctx, rand, cx, cy, R, n) {
      for (var i = 0; i < n; i++) {
        var p = spot(rand, cx, cy, R * 0.55), L = R * (0.13 + rand() * 0.05), a = rand() * 6.28;
        ctx.save(); ctx.translate(p[0], p[1]); ctx.rotate(a);
        shadowed(ctx, R, function () {
          ctx.beginPath();
          ctx.moveTo(-L, 0);
          ctx.quadraticCurveTo(-L * 0.1, -L * 0.62, L, 0);
          ctx.quadraticCurveTo(-L * 0.1, L * 0.62, -L, 0);
          var g = ctx.createLinearGradient(0, -L * 0.5, 0, L * 0.5);
          g.addColorStop(0, '#4F8F38'); g.addColorStop(1, '#2B5E22');
          ctx.fillStyle = g; ctx.fill();
        });
        ctx.strokeStyle = 'rgba(190,230,150,.55)'; ctx.lineWidth = Math.max(1, R * 0.006);
        ctx.beginPath(); ctx.moveTo(-L * 0.9, 0); ctx.quadraticCurveTo(0, -L * 0.04, L * 0.85, 0); ctx.stroke();
        if (rand() > 0.5) { ctx.fillStyle = 'rgba(30,25,10,.45)'; ctx.beginPath(); ctx.ellipse(L * 0.7, 0, L * 0.18, L * 0.08, 0, 0, 6.28); ctx.fill(); }
        ctx.restore();
      }
    },
    discs: function (ctx, rand, cx, cy, R, n, size, fill, rim, dots) {
      for (var i = 0; i < n; i++) {
        var p = spot(rand, cx, cy, R * 0.62), r = R * size * (0.85 + rand() * 0.3);
        shadowed(ctx, R, function () {
          blob(ctx, p[0], p[1], r, 0.08, rand, 12);
          ctx.fillStyle = radial(ctx, p[0], p[1], r, [[0, fill[0]], [1, fill[1]]]); ctx.fill();
        });
        if (rim) { ctx.strokeStyle = rim; ctx.lineWidth = r * 0.14; ctx.stroke(); }
        if (dots) {
          ctx.fillStyle = dots;
          for (var d = 0; d < 6; d++) { var q = spot(rand, p[0], p[1], r * 0.7); ctx.beginPath(); ctx.arc(q[0], q[1], r * 0.09, 0, 6.28); ctx.fill(); }
        }
      }
    },
    rings: function (ctx, rand, cx, cy, R, n, size, color, inner) {
      for (var i = 0; i < n; i++) {
        var p = spot(rand, cx, cy, R * 0.66), r = R * size;
        ctx.beginPath(); ctx.arc(p[0], p[1], r, 0, 6.28);
        ctx.fillStyle = color; ctx.fill();
        ctx.beginPath(); ctx.arc(p[0], p[1], r * 0.45, 0, 6.28);
        ctx.fillStyle = inner; ctx.fill();
      }
    },
    bits: function (ctx, rand, cx, cy, R, n, size, colors) {
      for (var i = 0; i < n; i++) {
        var p = spot(rand, cx, cy, R * 0.66);
        ctx.fillStyle = colors[i % colors.length];
        blob(ctx, p[0], p[1], R * size * (0.7 + rand() * 0.6), 0.3, rand, 8);
        ctx.fill();
      }
    },
    strips: function (ctx, rand, cx, cy, R, n, len, wid, colors) {
      for (var i = 0; i < n; i++) {
        var p = spot(rand, cx, cy, R * 0.6);
        ctx.save(); ctx.translate(p[0], p[1]); ctx.rotate(rand() * 6.28);
        shadowed(ctx, R, function () {
          ctx.beginPath();
          ctx.moveTo(-R * len, 0);
          ctx.bezierCurveTo(-R * len * 0.3, -R * wid * 2, R * len * 0.3, R * wid * 2, R * len, 0);
          ctx.lineWidth = R * wid; ctx.lineCap = 'round';
          ctx.strokeStyle = colors[i % colors.length]; ctx.stroke();
        });
        ctx.restore();
      }
    },
    mushrooms: function (ctx, rand, cx, cy, R, n) {
      for (var i = 0; i < n; i++) {
        var p = spot(rand, cx, cy, R * 0.62), s = R * (0.07 + rand() * 0.02);
        ctx.save(); ctx.translate(p[0], p[1]); ctx.rotate(rand() * 6.28);
        shadowed(ctx, R, function () {
          ctx.beginPath();
          ctx.arc(0, 0, s, Math.PI, 0);
          ctx.lineTo(s * 0.35, 0); ctx.lineTo(s * 0.3, s * 0.9); ctx.lineTo(-s * 0.3, s * 0.9); ctx.lineTo(-s * 0.35, 0);
          ctx.closePath();
          ctx.fillStyle = '#E3CFAE'; ctx.fill();
        });
        ctx.strokeStyle = '#8A6343'; ctx.lineWidth = s * 0.16;
        ctx.beginPath(); ctx.arc(0, 0, s, Math.PI, 0); ctx.stroke();
        ctx.restore();
      }
    },
    specks: function (ctx, rand, cx, cy, R, n, color, size) {
      ctx.fillStyle = color;
      for (var i = 0; i < n; i++) { var p = spot(rand, cx, cy, R * 0.72); ctx.beginPath(); ctx.arc(p[0], p[1], R * size * (0.5 + rand()), 0, 6.28); ctx.fill(); }
    },
    drizzle: function (ctx, rand, cx, cy, R, color, width) {
      ctx.strokeStyle = color; ctx.lineWidth = R * width; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      ctx.beginPath();
      var x = cx - R * 0.6, y = cy - R * 0.45;
      ctx.moveTo(x, y);
      for (var i = 0; i < 7; i++) {
        x += R * 0.17; y = cy - R * 0.45 + (i % 2 ? R * 0.9 : 0) + (rand() - 0.5) * R * 0.15;
        ctx.quadraticCurveTo(x - R * 0.12, (y + cy) / 2, x, y);
      }
      ctx.stroke();
    }
  };

  var RED = [[0, '#DA4B36'], [0.7, '#C8322B'], [1, '#A9271F']];

  // Raccourcis pour les garnitures de la carte
  var g = {
    olives: function (c, r, x, y, R, n) { paint.rings(c, r, x, y, R, n || 7, 0.045, '#2A2420', '#B9302A'); },
    origan: function (c, r, x, y, R) { paint.specks(c, r, x, y, R, 45, '#5B6B2E', 0.006); },
    jambon: function (c, r, x, y, R, n) { paint.bits(c, r, x, y, R, n || 7, 0.08, ['#EDAAA4', '#E59C97']); },
    merguez: function (c, r, x, y, R) { paint.strips(c, r, x, y, R, 7, 0.07, 0.045, ['#8E3B24', '#7A3220']); },
    chorizo: function (c, r, x, y, R) { paint.discs(c, r, x, y, R, 8, 0.07, ['#D2522F', '#A83A22'], '#8E2E1A', 'rgba(255,215,190,.55)'); },
    viande: function (c, r, x, y, R) { paint.bits(c, r, x, y, R, 24, 0.035, ['#6B3F2A', '#5A3322', '#7B4A33']); },
    oignons: function (c, r, x, y, R) { paint.strips(c, r, x, y, R, 6, 0.06, 0.012, ['#EBDCE6', '#B582A8']); },
    poivrons: function (c, r, x, y, R) { paint.strips(c, r, x, y, R, 6, 0.08, 0.03, ['#D9452E', '#3F7A34', '#E8B23A']); },
    emmental: function (c, r, x, y, R) { paint.bits(c, r, x, y, R, 6, 0.1, ['rgba(245,215,120,.75)']); },
    bleu: function (c, r, x, y, R) { paint.discs(c, r, x, y, R, 4, 0.07, ['#F4F0E6', '#D7DCD6'], null, 'rgba(70,95,120,.7)'); },
    chevre: function (c, r, x, y, R) { paint.rings(c, r, x, y, R, 5, 0.065, '#E2DCCD', '#FFFDF6'); },
    cru: function (c, r, x, y, R) { paint.strips(c, r, x, y, R, 5, 0.11, 0.045, ['#C9605B', '#B9524E']); },
    parmesan: function (c, r, x, y, R) { paint.bits(c, r, x, y, R, 8, 0.035, ['#F4E6BE', '#EEDCA8']); },
    champignons: function (c, r, x, y, R) { paint.mushrooms(c, r, x, y, R, 7); },
    artichauts: function (c, r, x, y, R) { paint.bits(c, r, x, y, R, 5, 0.065, ['#A7A86A', '#8E9257']); },
    aubergines: function (c, r, x, y, R) { paint.rings(c, r, x, y, R, 4, 0.075, '#4A2742', '#E6D6B0'); },
    anchois: function (c, r, x, y, R) { paint.strips(c, r, x, y, R, 6, 0.1, 0.03, ['#7D6352', '#6B5243']); },
    capres: function (c, r, x, y, R) { paint.specks(c, r, x, y, R, 12, '#6E7F35', 0.012); },
    roquette: function (c, r, x, y, R) { paint.strips(c, r, x, y, R, 10, 0.06, 0.022, ['#4E8A33', '#3A7027']); },
    confites: function (c, r, x, y, R) { paint.discs(c, r, x, y, R, 5, 0.045, ['#D9532E', '#B23A1F'], null, null); },
    balsamique: function (c, r, x, y, R) { paint.drizzle(c, r, x, y, R, 'rgba(59,31,20,.85)', 0.014); },
    ravioles: function (c, r, x, y, R) {
      for (var i = 0; i < 12; i++) {
        var p = spot(r, x, y, R * 0.6), s = R * 0.075;
        c.save(); c.translate(p[0], p[1]); c.rotate(r() * 6.28);
        shadowed(c, R, function () { c.fillStyle = '#F1DFA6'; c.fillRect(-s / 2, -s / 2, s, s); });
        c.strokeStyle = 'rgba(190,150,80,.8)'; c.lineWidth = s * 0.12; c.setLineDash([s * 0.12, s * 0.1]);
        c.strokeRect(-s / 2 + s * 0.08, -s / 2 + s * 0.08, s * 0.84, s * 0.84);
        c.setLineDash([]); c.restore();
      }
    },
    oeuf: function (c, r, x, y, R) {
      shadowed(c, R, function () { blob(c, x, y, R * 0.2, 0.2, r, 12); c.fillStyle = '#FFFDF6'; c.fill(); });
      c.beginPath(); c.arc(x + R * 0.02, y - R * 0.01, R * 0.075, 0, 6.28);
      c.fillStyle = radial(c, x, y, R * 0.075, [[0, '#FFC64A'], [1, '#E9940F']]); c.fill();
    }
  };

  function recipe(list) {
    return { base: RED, top: function (c, r, x, y, R) { paint.mozza(c, r, x, y, R, 5); list.forEach(function (k) { g[k](c, r, x, y, R); }); } };
  }

  var recipes = {
    margarita: { base: RED, top: function (c, r, x, y, R) { paint.mozza(c, r, x, y, R, 9); g.olives(c, r, x, y, R, 9); g.origan(c, r, x, y, R); } },
    jambon: recipe(['jambon', 'olives', 'origan']),
    royale: recipe(['jambon', 'champignons', 'olives', 'origan']),
    orientale: recipe(['merguez', 'oignons', 'olives', 'origan']),
    chorizo: recipe(['chorizo', 'poivrons', 'olives']),
    viande: recipe(['viande', 'oignons', 'olives', 'origan']),
    napolitaine: recipe(['anchois', 'capres', 'olives']),
    piemontaise: recipe(['jambon', 'chevre', 'olives', 'origan']),
    parme: recipe(['cru', 'parmesan', 'olives', 'origan']),
    saisons: recipe(['aubergines', 'poivrons', 'artichauts', 'champignons', 'olives']),
    fromages: recipe(['bleu', 'chevre', 'emmental', 'olives']),
    bolognaise: recipe(['viande', 'champignons', 'emmental', 'olives', 'origan']),
    fromagere: { base: RED, top: function (c, r, x, y, R) { paint.mozza(c, r, x, y, R, 4); ['bleu', 'emmental', 'parmesan', 'olives'].forEach(function (k) { g[k](c, r, x, y, R); }); g.oeuf(c, r, x, y, R); } },
    mexicaine: recipe(['chorizo', 'merguez', 'poivrons', 'oignons', 'olives']),
    locale: recipe(['ravioles', 'cru', 'olives', 'origan']),
    troisbecs: recipe(['ravioles', 'jambon', 'emmental', 'bleu', 'olives']),
    roquette: recipe(['cru', 'confites', 'parmesan', 'roquette', 'olives', 'balsamique'])
  };

  function drawPizza(ctx, type, seed, cx, cy, R) {
    var rand = rng(seed * 9973 + 17);
    var recipe = recipes[type] || recipes.margarita;

    if (type === 'calzone' || type === 'calzone3') return drawCalzone(ctx, rand, cx, cy, R);

    // Ombre portée
    ctx.save();
    ctx.shadowColor = 'rgba(40,20,5,.45)'; ctx.shadowBlur = R * 0.08; ctx.shadowOffsetY = R * 0.04;
    blob(ctx, cx, cy, R, 0.035, rand, 22);
    ctx.fillStyle = radial(ctx, cx, cy, R, [[0, '#F6DCA6'], [0.78, '#E9B66F'], [0.92, '#D79A55'], [1, '#B8773A']]);
    ctx.fill();
    ctx.restore();

    // Leopardatura : taches brunes et noires laissées par le four sur le cornicione
    for (var i = 0; i < 70; i++) {
      var a = rand() * Math.PI * 2, d = R * (0.8 + rand() * 0.17), s = R * (0.008 + rand() * 0.03);
      var dark = rand() > 0.55;
      ctx.fillStyle = dark ? 'rgba(45,25,12,' + (0.45 + rand() * 0.4) + ')' : 'rgba(150,85,35,' + (0.2 + rand() * 0.25) + ')';
      ctx.beginPath();
      ctx.ellipse(cx + Math.cos(a) * d, cy + Math.sin(a) * d, s * (1 + rand()), s, a, 0, 6.28);
      ctx.fill();
    }
    // Bulles de la croûte
    for (var b = 0; b < 10; b++) {
      var ab = rand() * 6.28, db = R * 0.88;
      ctx.fillStyle = 'rgba(255,240,205,.35)';
      ctx.beginPath(); ctx.ellipse(cx + Math.cos(ab) * db, cy + Math.sin(ab) * db, R * 0.05, R * 0.03, ab + 1.57, 0, 6.28); ctx.fill();
    }

    // Garniture de base (sauce tomate ou crème)
    blob(ctx, cx, cy, R * 0.79, 0.05, rand, 18);
    ctx.fillStyle = radial(ctx, cx, cy, R * 0.79, recipe.base);
    ctx.fill();
    ctx.save(); ctx.clip();
    for (var k = 0; k < 18; k++) {
      var p = spot(rand, cx, cy, R * 0.8);
      ctx.fillStyle = recipe.base === RED ? 'rgba(140,25,15,.1)' : 'rgba(210,170,100,.22)';
      blob(ctx, p[0], p[1], R * (0.04 + rand() * 0.08), 0.4, rand, 8); ctx.fill();
    }
    ctx.restore();

    recipe.top(ctx, rand, cx, cy, R);

    // Filet d'huile d'olive
    for (var o = 0; o < 6; o++) {
      var q = spot(rand, cx, cy, R * 0.6);
      ctx.fillStyle = 'rgba(255,255,255,.22)';
      ctx.beginPath(); ctx.ellipse(q[0], q[1], R * 0.035, R * 0.012, rand() * 3, 0, 6.28); ctx.fill();
    }
  }

  function drawCalzone(ctx, rand, cx, cy, R) {
    ctx.save();
    ctx.translate(cx, cy); ctx.rotate(-0.35);
    ctx.shadowColor = 'rgba(40,20,5,.45)'; ctx.shadowBlur = R * 0.08; ctx.shadowOffsetY = R * 0.04;
    ctx.beginPath();
    ctx.moveTo(-R * 0.95, R * 0.15);
    ctx.bezierCurveTo(-R * 0.9, -R * 0.95, R * 0.9, -R * 0.95, R * 0.95, R * 0.15);
    ctx.quadraticCurveTo(0, R * 0.42, -R * 0.95, R * 0.15);
    ctx.closePath();
    var g = ctx.createLinearGradient(0, -R * 0.8, 0, R * 0.3);
    g.addColorStop(0, '#F3D296'); g.addColorStop(0.7, '#E4AA62'); g.addColorStop(1, '#C0803F');
    ctx.fillStyle = g; ctx.fill();
    ctx.restore();
    ctx.save(); ctx.translate(cx, cy); ctx.rotate(-0.35);
    // Bord pincé
    ctx.strokeStyle = 'rgba(150,90,40,.6)'; ctx.lineWidth = R * 0.02; ctx.setLineDash([R * 0.05, R * 0.05]);
    ctx.beginPath(); ctx.moveTo(-R * 0.86, R * 0.16); ctx.quadraticCurveTo(0, R * 0.36, R * 0.86, R * 0.16); ctx.stroke();
    ctx.setLineDash([]);
    for (var i = 0; i < 40; i++) {
      var x = (rand() - 0.5) * R * 1.6, y = -R * 0.6 + rand() * R * 0.8;
      if (y > R * 0.15) continue;
      ctx.fillStyle = rand() > 0.5 ? 'rgba(45,25,12,.55)' : 'rgba(150,85,35,.3)';
      ctx.beginPath(); ctx.ellipse(x, y, R * 0.02 * (1 + rand()), R * 0.015, rand() * 3, 0, 6.28); ctx.fill();
    }
    ctx.fillStyle = '#C8322B';
    blob(ctx, -R * 0.1, -R * 0.35, R * 0.12, 0.3, rand, 10); ctx.fill();
    ctx.restore();
    paint.specks(ctx, rand, cx, cy - R * 0.3, R * 0.5, 30, '#5B6B2E', 0.01);
  }

  // Décor « photo » quand une image manque : nappe, bois ou ardoise
  function drawScene(ctx, W, H, type, seed) {
    var rand = rng(seed * 31 + 3), kind = seed % 3;
    if (kind === 0) {
      ctx.fillStyle = '#FAF7F2'; ctx.fillRect(0, 0, W, H);
      var s = Math.max(W, H) / 9;
      ctx.fillStyle = 'rgba(200,50,43,.45)';
      for (var x = 0; x < W; x += s * 2) ctx.fillRect(x, 0, s, H);
      for (var y = 0; y < H; y += s * 2) ctx.fillRect(0, y, W, s);
    } else if (kind === 1) {
      var g = ctx.createLinearGradient(0, 0, W, H);
      g.addColorStop(0, '#6B4226'); g.addColorStop(1, '#4A2C18');
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
      ctx.strokeStyle = 'rgba(0,0,0,.18)'; ctx.lineWidth = 1.5;
      for (var l = 0; l < 26; l++) { var yy = rand() * H; ctx.beginPath(); ctx.moveTo(0, yy); ctx.bezierCurveTo(W * 0.3, yy + 8, W * 0.6, yy - 8, W, yy + 4); ctx.stroke(); }
    } else {
      ctx.fillStyle = '#2B2B29'; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = 'rgba(255,250,240,.12)';
      for (var f = 0; f < 260; f++) { ctx.beginPath(); ctx.arc(rand() * W, rand() * H, rand() * 2.2, 0, 6.28); ctx.fill(); }
    }
    var R = Math.min(W, H) * (0.42 + rand() * 0.12);
    drawPizza(ctx, type, seed, W * (0.45 + rand() * 0.15), H * (0.48 + rand() * 0.1), R);
  }

  function render(canvas) {
    var w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var key = w + 'x' + h + '@' + dpr;
    if (canvas._drawn === key) return;
    canvas._drawn = key;
    canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
    var ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    var type = canvas.getAttribute('data-pizza'), seed = +canvas.getAttribute('data-seed') || 1;
    if (canvas.hasAttribute('data-scene')) return drawScene(ctx, w, h, type, seed);
    var S = Math.min(w, h), cx = w / 2, cy = h / 2;
    if (canvas.hasAttribute('data-board')) {
      // Pelle en bois sous la pizza
      ctx.save();
      ctx.shadowColor = 'rgba(80,45,20,.35)'; ctx.shadowBlur = S * 0.04; ctx.shadowOffsetY = S * 0.02;
      ctx.beginPath(); ctx.arc(cx, cy, S * 0.45, 0, 6.28);
      ctx.fillStyle = radial(ctx, cx, cy, S * 0.45, [[0, '#D9A672'], [0.85, '#C18A55'], [1, '#9C6A3B']]);
      ctx.fill(); ctx.restore();
      var rr = rng(seed);
      ctx.strokeStyle = 'rgba(110,65,30,.22)'; ctx.lineWidth = 1.2;
      for (var i = 0; i < 16; i++) { ctx.beginPath(); ctx.arc(cx, cy, S * (0.1 + rr() * 0.34), rr() * 6, rr() * 6 + 1.5); ctx.stroke(); }
      drawPizza(ctx, type, seed, cx, cy, S * 0.385);
    } else {
      drawPizza(ctx, type, seed, cx, cy, S * 0.43);
    }
  }

  function renderAll() { $$('canvas[data-pizza]').forEach(render); }

  // Photo manquante (ou bloquée) : une pizza dessinée prend sa place
  $$('.shot > img[data-pizza]').forEach(function (img) {
    function swap() {
      if (img._swapped) return;
      img._swapped = true;
      var c = document.createElement('canvas');
      c.setAttribute('data-pizza', img.getAttribute('data-pizza'));
      c.setAttribute('data-seed', img.getAttribute('data-seed'));
      c.setAttribute('data-scene', '');
      c.setAttribute('role', 'img');
      c.setAttribute('aria-label', img.alt || 'Pizza');
      img.replaceWith(c);
      render(c);
    }
    if (img.complete && img.naturalWidth === 0 && img.getAttribute('src')) swap();
    else img.addEventListener('error', swap);
  });

  renderAll();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(renderAll);
  var rt;
  window.addEventListener('resize', function () { clearTimeout(rt); rt = setTimeout(renderAll, 150); });

  /* =================================================================
     En-tête et menu mobile
     ================================================================= */
  var header = $('.site-header');
  function onScroll() { header.classList.toggle('is-scrolled', window.scrollY > 60); }
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  var burger = $('.burger'), nav = $('#mobile-nav');
  function setNav(open) {
    burger.setAttribute('aria-expanded', String(open));
    document.body.style.overflow = open ? 'hidden' : '';
    if (open) {
      nav.hidden = false;
      requestAnimationFrame(function () { nav.classList.remove('opacity-0'); });
      $('a', nav).focus();
    } else {
      nav.classList.add('opacity-0');
      setTimeout(function () { nav.hidden = true; }, reduceMotion ? 0 : 300);
    }
  }
  burger.addEventListener('click', function () { setNav(true); });
  $('.close-nav').addEventListener('click', function () { setNav(false); burger.focus(); });
  nav.addEventListener('click', function (e) { if (e.target.closest('a')) setNav(false); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !nav.hidden) { setNav(false); burger.focus(); } });

  /* =================================================================
     Onglets de la carte (flèches gauche/droite au clavier)
     ================================================================= */
  var tabs = $$('[role="tab"]');
  function selectTab(tab, focus) {
    tabs.forEach(function (t) {
      var on = t === tab, panel = document.getElementById(t.getAttribute('aria-controls'));
      t.setAttribute('aria-selected', String(on));
      t.tabIndex = on ? 0 : -1;
      panel.hidden = !on;
      if (on) {
        $$('canvas[data-pizza]', panel).forEach(render);
        if (!reduceMotion) $$('.dish', panel).forEach(function (d, i) {
          d.style.animation = 'none'; d.offsetHeight;
          d.style.animation = 'rise .6s cubic-bezier(.2,.7,.2,1) ' + (i * 0.06) + 's both';
          d.addEventListener('animationend', function () { d.style.animation = ''; }, { once: true });
        });
      }
    });
    if (focus) { tab.focus(); tab.scrollIntoView({ block: 'nearest', inline: 'center' }); }
  }
  tabs.forEach(function (tab, i) {
    tab.addEventListener('click', function () { selectTab(tab, false); });
    tab.addEventListener('keydown', function (e) {
      var n = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: tabs.length - 1 }[e.key];
      if (n === undefined) return;
      e.preventDefault();
      selectTab(tabs[(n + tabs.length) % tabs.length], true);
    });
  });

  /* =================================================================
     Carrousel d'avis
     ================================================================= */
  var track = $('.reviews'), notes = $$('.review-note', track);
  function step() { return notes[0].getBoundingClientRect().width + 24; }
  function go(dir) {
    var max = track.scrollWidth - track.clientWidth - 8;
    if (dir > 0 && track.scrollLeft >= max) track.scrollTo({ left: 0 });
    else if (dir < 0 && track.scrollLeft <= 8) track.scrollTo({ left: track.scrollWidth });
    else track.scrollBy({ left: dir * step() });
  }
  $('.review-prev').addEventListener('click', function () { go(-1); });
  $('.review-next').addEventListener('click', function () { go(1); });
  if (!reduceMotion && 'IntersectionObserver' in window) {
    var paused = false, timer;
    ['mouseenter', 'focusin', 'touchstart'].forEach(function (ev) { track.addEventListener(ev, function () { paused = true; }, { passive: true }); });
    ['mouseleave', 'focusout'].forEach(function (ev) { track.addEventListener(ev, function () { paused = false; }); });
    new IntersectionObserver(function (en) {
      clearInterval(timer);
      if (en[0].isIntersecting) timer = setInterval(function () { if (!paused && !document.hidden) go(1); }, 6000);
    }, { threshold: 0.4 }).observe(track);
  }

  /* =================================================================
     Horaires : tableau des départs à palettes + « ouvert maintenant »
     ================================================================= */
  var GLYPHS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  $$('.flap').forEach(function (el) {
    var text = el.textContent.trim().toUpperCase();
    el.setAttribute('aria-label', el.textContent.trim());
    el.textContent = '';
    text.split('').forEach(function (ch) {
      var s = document.createElement('span');
      s.setAttribute('aria-hidden', 'true');
      if (ch === ' ') s.className = 'is-space';
      s.textContent = ch;
      s._final = ch;
      el.appendChild(s);
    });
  });

  function flipBoard() {
    if (reduceMotion) return;
    $$('.flap span').forEach(function (s, idx) {
      if (s._final === ' ' || s._final === '-') return;
      var n = 6 + (idx % 7), k = 0;
      var t = setInterval(function () {
        s.textContent = ++k >= n ? s._final : GLYPHS[Math.floor(Math.random() * GLYPHS.length)];
        if (k >= n) clearInterval(t);
      }, 55);
    });
  }

  function parisNow() {
    var parts = {};
    try {
      new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/Paris', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
        .formatToParts(new Date()).forEach(function (p) { parts[p.type] = p.value; });
    } catch (e) { return null; }
    var day = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }[parts.weekday];
    if (day === undefined) return null;
    return { day: day, h: parts.hour, m: parts.minute, min: +parts.hour * 60 + +parts.minute };
  }
  function toMin(t) { var p = t.split(':'); return +p[0] * 60 + +p[1]; }
  function fmt(t) { return t.replace(':', 'h'); }

  var now = parisNow();
  if (now) {
    var row = $('.hours tr[data-day="' + now.day + '"]');
    row.classList.add('is-today');
    var slot = row.getAttribute('data-open'), status = $('.board-status', row), live = $('.board-live');
    var state, line, pill;
    if (!slot) { state = 'Repos'; line = 'Aujourd’hui, le four se repose'; pill = 'Fermé aujourd’hui'; }
    else {
      var r = slot.split('-'), o = toMin(r[0]), c = toMin(r[1]);
      if (now.min < o) { state = 'Ce soir'; line = 'Ouverture ce soir à ' + fmt(r[0]); pill = 'Ouvert ce soir dès ' + fmt(r[0]); }
      else if (now.min < c) { state = 'En cuisson'; line = 'Ouvert : le four tourne jusqu’à ' + fmt(r[1]); pill = 'Ouvert jusqu’à ' + fmt(r[1]); }
      else { state = 'Terminé'; line = 'Fermé pour ce soir, à demain !'; pill = 'Fermé pour ce soir'; }
    }
    var openNow = state === 'En cuisson';
    status.innerHTML = '<span class="' + (openNow ? 'text-[#9BE39B]' : 'text-copper') + '">' + state + '</span>';
    live.innerHTML = '<span class="flicker h-2.5 w-2.5 rounded-full ' + (openNow ? 'bg-[#6BD66B]' : 'bg-tomato') + '"></span>' + line;
    live.hidden = false;
    $('.today-text').textContent = pill;
    $('.today-dot').className = 'today-dot h-2 w-2 rounded-full ' + (openNow ? 'bg-[#3FA34D] flicker' : 'bg-tomato');

    var clock = $('.board-clock');
    var tick = function () { var n = parisNow(); if (n) clock.innerHTML = n.h + '<span class="flicker">:</span>' + n.m; };
    tick(); setInterval(tick, 20000);
  }

  /* =================================================================
     Apparitions au défilement
     ================================================================= */
  var reveals = $$('.reveal'), board = $('.board');
  if ('IntersectionObserver' in window && !reduceMotion) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add('is-visible');
        io.unobserve(e.target);
        if (e.target.contains(board)) flipBoard();
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.05 });
    reveals.forEach(function (el) { io.observe(el); });
  } else {
    reveals.forEach(function (el) { el.classList.add('is-visible'); });
  }

  var year = $('.year');
  if (year) year.textContent = new Date().getFullYear();
})();
