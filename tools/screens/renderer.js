// Moteur de rendu hors jeu, exécuté DANS Chromium (Playwright, tools/screens/render.mjs).
// Dessine un instantané JSON (tests/harness/ScreenDump) sur un canevas à la résolution de
// l'appareil, avec les vraies polices de Google Fonts, en suivant les règles de texte de Roblox,
// puis contrôle ce qui a été dessiné (report : textes qui ne tiennent pas, coupés, tronqués, trop
// petits, hors écran, hors zone sûre, chevauchements, contraste, chaînes brutes).
//
// Règles reproduites (documentation Roblox) :
//   * TextSize = hauteur d'UNE ligne : la taille CSS vaut TextSize / lineRatio (fonts.mjs) ;
//   * TextScaled : plus grande taille ENTIÈRE ≤ 100, bornée par UITextSizeConstraint, où le texte
//     tient en largeur et en hauteur ; TextScaled active implicitement TextWrapped ;
//   * TextWrapped : retour aux espaces (jamais à l'espace insécable), « \n » force une ligne, un mot
//     plus large que la boîte est coupé entre deux caractères ;
//   * TextTruncate AtEnd : lignes qui ne tiennent pas retirées, « … » en fin de dernière ligne ;
//   * alignements, LineHeight, UIPadding du libellé ; RichText de base (b, i, font color/weight,
//     stroke, br, uppercase) ;
//   * UIStroke : contour du texte (Contextual sur un texte) ou du cadre (Border, ou Contextual sur
//     un cadre), coins arrondis suivis ; UICorner (Scale × min(l, h) + Offset, au plus la moitié) ;
//     UIGradient (couleurs et transparences multipliées, dans l'espace normalisé de l'objet,
//     Rotation, Offset ; sur un CanvasGroup : tout le groupe) ; bordure héritée (BorderSizePixel,
//     sans UICorner) ; transparences, GroupTransparency ;
//   * ordre : écrans par DisplayOrder ; ZIndexBehavior Sibling (enfants après leur parent, frères
//     par ZIndex puis ordre) ou Global ; découpe ClipsDescendants / ScrollingFrame / CanvasGroup ;
//   * images : remplaçants neutres teintés (ImageColor3) avec leur id ; icônes de manette
//     PlayStation dessinées (symbole).

(() => {
  const SCALED_WRAPS = true;
  const ELLIPSIS = '…';
  const REF = 100; // taille de référence des mesures (largeurs linéaires en taille)
  let FONTS = {};
  let FALLBACK = 'sans-serif';
  const METRICS = {}; // clé → { lineRatio, ascent }
  const measureCtx = document.createElement('canvas').getContext('2d');
  const widthCache = new Map();

  // ------------------------------------------------------------------ polices et mesures

  function init(fonts, fallback) {
    FONTS = fonts;
    FALLBACK = fallback;
    for (const key of Object.keys(FONTS)) {
      measureCtx.font = fontSpec(key, 100, false, false);
      const m = measureCtx.measureText('Hg');
      const asc = m.fontBoundingBoxAscent;
      const desc = m.fontBoundingBoxDescent;
      METRICS[key] = { lineRatio: (asc + desc) / 100, ascent: asc / (asc + desc) };
    }
    return METRICS;
  }

  function fontInfo(key) {
    return FONTS[key] || FONTS['GothamSSm@400'];
  }

  function metrics(key) {
    return METRICS[key] || METRICS['GothamSSm@400'] || { lineRatio: 1.2, ascent: 0.8 };
  }

  // taille Roblox (hauteur de ligne en px) → déclaration de police CSS
  function fontSpec(key, robloxPx, bold, italic) {
    const f = fontInfo(key);
    const m = METRICS[key];
    const css = m ? robloxPx / m.lineRatio : robloxPx;
    const weight = bold ? Math.max(700, f.weight) : f.weight;
    return `${italic ? 'italic ' : ''}${weight} ${css}px "${f.css}", ${FALLBACK}`;
  }

  // largeur d'une chaîne d'un même style, en px à la taille Roblox `size`
  function width(str, key, style, size) {
    if (str === '') return 0;
    const ck = `${key}|${style.bold ? 1 : 0}${style.italic ? 1 : 0}|${str}`;
    let w = widthCache.get(ck);
    if (w === undefined) {
      measureCtx.font = fontSpec(key, REF, style.bold, style.italic);
      w = measureCtx.measureText(str).width;
      widthCache.set(ck, w);
    }
    return (w * size) / REF;
  }

  // ------------------------------------------------------------------ texte riche

  function hex(c) {
    if (!c) return null;
    let m = /^#?([0-9a-f]{6})$/i.exec(c.trim());
    if (m) {
      const n = parseInt(m[1], 16);
      return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
    }
    m = /rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/i.exec(c);
    if (m) return [Number(m[1]), Number(m[2]), Number(m[3])];
    return null;
  }

  function attr(tag, name) {
    const m = new RegExp(`${name}\\s*=\\s*["']([^"']*)["']`, 'i').exec(tag);
    return m ? m[1] : null;
  }

  function decode(s) {
    return s
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&amp;/g, '&');
  }

  // → { chars: [{ c, s }], styles: [style] } ; style = { bold, italic, color, stroke, upper }
  function parse(text, rich) {
    const styles = [{ bold: false, italic: false, color: null, stroke: null, upper: false }];
    const chars = [];
    const push = (str, si) => {
      for (const ch of str) chars.push({ c: styles[si].upper ? ch.toUpperCase() : ch, s: si });
    };
    if (!rich) {
      push(text, 0);
      return { chars, styles };
    }
    const stack = [0];
    const re = /<[^<>]*>/g;
    let last = 0;
    let m;
    while ((m = re.exec(text))) {
      push(decode(text.slice(last, m.index)), stack[stack.length - 1]);
      last = m.index + m[0].length;
      const tag = m[0];
      const close = /^<\//.test(tag);
      const name = (/^<\/?\s*([a-z]+)/i.exec(tag) || [])[1];
      if (!name) continue;
      const lname = name.toLowerCase();
      if (lname === 'br') {
        push('\n', stack[stack.length - 1]);
        continue;
      }
      if (close) {
        if (stack.length > 1) stack.pop();
        continue;
      }
      const base = styles[stack[stack.length - 1]];
      const st = { ...base };
      if (lname === 'b') st.bold = true;
      else if (lname === 'i') st.italic = true;
      else if (lname === 'uppercase' || lname === 'uc') st.upper = true;
      else if (lname === 'font') {
        const col = hex(attr(tag, 'color'));
        if (col) st.color = col;
        const w = attr(tag, 'weight');
        if (w && (/bold|heavy|black/i.test(w) || Number(w) >= 600)) st.bold = true;
      } else if (lname === 'stroke') {
        st.stroke = {
          color: hex(attr(tag, 'color')) || [0, 0, 0],
          thick: Number(attr(tag, 'thickness') || 1),
          t: Number(attr(tag, 'transparency') || 0),
        };
      }
      styles.push(st);
      stack.push(styles.length - 1);
    }
    push(decode(text.slice(last)), stack[stack.length - 1]);
    return { chars, styles };
  }

  // ------------------------------------------------------------------ mise en page du texte

  const isBreak = (c) => c === ' ' || c === '\t';

  function runWidth(chars, i0, i1, key, styles, size) {
    let w = 0;
    let i = i0;
    while (i <= i1) {
      const s = chars[i].s;
      let j = i;
      let str = '';
      while (j <= i1 && chars[j].s === s) {
        str += chars[j].c;
        j++;
      }
      w += width(str, key, styles[s], size);
      i = j;
    }
    return w;
  }

  // lignes : [{ a, b, w }] (indices inclus dans chars) ; boxW = Infinity : pas de retour automatique
  function wrap(parsed, key, size, boxW) {
    const { chars, styles } = parsed;
    const lines = [];
    let split = false;
    let p0 = 0;
    const n = chars.length;
    const eps = 1e-6;
    while (p0 <= n) {
      let p1 = p0;
      while (p1 < n && chars[p1].c !== '\n') p1++;
      // paragraphe [p0, p1)
      let lineA = -1;
      let lineB = -1;
      let lineW = 0;
      let i = p0;
      const startCount = lines.length;
      while (i < p1) {
        const s0 = i;
        while (i < p1 && isBreak(chars[i].c)) i++;
        const spaceW = i > s0 ? runWidth(chars, s0, i - 1, key, styles, size) : 0;
        if (i >= p1) break;
        const w0 = i;
        while (i < p1 && !isBreak(chars[i].c)) i++;
        const w1 = i - 1;
        const wordW = runWidth(chars, w0, w1, key, styles, size);
        if (lineA >= 0 && lineW + spaceW + wordW <= boxW + eps) {
          lineB = w1;
          lineW += spaceW + wordW;
          continue;
        }
        if (lineA >= 0) lines.push({ a: lineA, b: lineB, w: lineW });
        lineA = -1;
        lineW = 0;
        if (wordW <= boxW + eps) {
          lineA = w0;
          lineB = w1;
          lineW = wordW;
        } else {
          split = true;
          let c0 = w0;
          let acc = 0;
          for (let k = w0; k <= w1; k++) {
            const a = runWidth(chars, k, k, key, styles, size);
            if (acc + a > boxW + eps && k > c0) {
              lines.push({ a: c0, b: k - 1, w: acc });
              c0 = k;
              acc = 0;
            }
            acc += a;
          }
          lineA = c0;
          lineB = w1;
          lineW = acc;
        }
      }
      if (lineA >= 0) lines.push({ a: lineA, b: lineB, w: lineW });
      if (lines.length === startCount) lines.push({ a: p0, b: p0 - 1, w: 0 });
      p0 = p1 + 1;
      if (p1 >= n) break;
    }
    return { lines, split };
  }

  function block(parsed, key, size, boxW, wrapped, lh) {
    const r = wrap(parsed, key, size, wrapped ? boxW : Infinity);
    let w = 0;
    for (const l of r.lines) w = Math.max(w, l.w);
    return { lines: r.lines, split: r.split, w, h: r.lines.length * size * lh };
  }

  // Texte d'un nœud dans une boîte de bw × bh px DE MISE EN PAGE ; k = px d'écran par px de mise
  // en page (UIScale cumulés). capMode : 'layout' (défaut : tailles TextScaled entières, 100 et
  // UITextSizeConstraint comptés AVANT UIScale) ou 'screen' (comptés en px d'écran, APRÈS UIScale :
  // hypothèse à vérifier sur une vraie console, voir README)
  function layoutText(t, bw, bh, k, capMode) {
    const unit = capMode === 'screen' ? 1 / Math.max(k || 1, 1e-6) : 1;
    const key = t.key;
    const parsed = parse(t.shown || '', t.rich);
    const scaled = !!t.scaled;
    const wrapped = !!t.wrapped || (scaled && SCALED_WRAPS);
    const lh = t.lh || 1;
    const minS = t.minS != null ? t.minS : 1;
    const maxS = t.maxS != null ? t.maxS : 100;
    let size;
    let fitsMin = true;
    const fits = (b) => b.w <= bw + 0.01 && b.h <= bh + 0.01;
    if (scaled) {
      const top = Math.floor(Math.min(maxS, 100));
      const bottom = Math.max(1, Math.ceil(minS));
      const hi0 = Math.max(top, bottom);
      if ((t.shown || '') === '') size = hi0 * unit;
      else if (!fits(block(parsed, key, bottom * unit, bw, wrapped, lh))) {
        size = bottom * unit;
        fitsMin = false;
      } else {
        let lo = bottom;
        let hi = hi0;
        while (lo < hi) {
          const mid = Math.ceil((lo + hi) / 2);
          if (fits(block(parsed, key, mid * unit, bw, wrapped, lh))) lo = mid;
          else hi = mid - 1;
        }
        size = lo * unit;
      }
    } else {
      size = t.fit && t.fit.size ? t.fit.size : t.size || 8;
    }
    const b = block(parsed, key, size, bw, wrapped, lh);
    let lines = b.lines.map((l) => ({ ...l, ell: false }));
    let truncated = false;
    let hidden = '';
    let overflowX = Math.max(0, b.w - bw);
    let overflowY = Math.max(0, b.h - bh);
    if (t.trunc && t.trunc !== 'None' && (overflowX > 0.01 || overflowY > 0.01)) {
      truncated = true;
      const fitLines = Math.max(1, Math.floor((bh + 0.01) / (size * lh)));
      const keep = lines.slice(0, fitLines);
      const hiddenParts = lines.slice(fitLines).map((l) => text(parsed, l.a, l.b));
      const lastLine = keep[keep.length - 1];
      const ell = width(ELLIPSIS, key, parsed.styles[0], size);
      let cut = lastLine.b;
      while (cut >= lastLine.a && runWidth(parsed.chars, lastLine.a, cut, key, parsed.styles, size) + ell > bw + 0.01)
        cut--;
      if (cut < lastLine.b) hiddenParts.unshift(text(parsed, cut + 1, lastLine.b));
      keep[keep.length - 1] = {
        a: lastLine.a,
        b: cut,
        w: runWidth(parsed.chars, lastLine.a, cut, key, parsed.styles, size) + ell,
        ell: true,
      };
      lines = keep;
      hidden = hiddenParts.join(' ');
      overflowX = 0;
      overflowY = 0;
    }
    let bwOut = 0;
    for (const l of lines) bwOut = Math.max(bwOut, l.w);
    return {
      parsed,
      key,
      size,
      lh,
      scaled,
      wrapped,
      fitsMin,
      lines,
      blockW: bwOut,
      blockH: lines.length * size * lh,
      overflowX,
      overflowY,
      truncated,
      hidden,
      split: b.split,
    };
  }

  function text(parsed, a, b) {
    let s = '';
    for (let i = a; i <= b; i++) s += parsed.chars[i].c;
    return s;
  }

  // ------------------------------------------------------------------ outils de dessin

  const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${Math.max(0, Math.min(1, a))})`;

  function radiusOf(node, w, h) {
    if (!node.corner) return 0;
    const r = node.corner.s * Math.min(w, h) + node.corner.o;
    return Math.max(0, Math.min(r, Math.min(w, h) / 2));
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    if (r <= 0.01) ctx.rect(x, y, w, h);
    else ctx.roundRect(x, y, w, h, r);
  }

  function sampleSeq(seq, t, fallback) {
    if (!seq || !seq.length) return fallback;
    if (t <= seq[0][0]) return seq[0].slice(1);
    for (let i = 1; i < seq.length; i++) {
      const a = seq[i - 1];
      const b = seq[i];
      if (t <= b[0]) {
        const u = (t - a[0]) / Math.max(1e-9, b[0] - a[0]);
        return a.slice(1).map((v, k) => v + (b[k + 1] - v) * u);
      }
    }
    return seq[seq.length - 1].slice(1);
  }

  // UIGradient appliqué aux pixels d'un canevas (rectangle x, y, w, h de l'objet dans ce canevas)
  function applyGradient(canvas, grad, x, y, w, h) {
    const ctx = canvas.getContext('2d');
    const x0 = Math.max(0, Math.floor(x));
    const y0 = Math.max(0, Math.floor(y));
    const x1 = Math.min(canvas.width, Math.ceil(x + w));
    const y1 = Math.min(canvas.height, Math.ceil(y + h));
    if (x1 <= x0 || y1 <= y0) return;
    const img = ctx.getImageData(x0, y0, x1 - x0, y1 - y0);
    const d = img.data;
    const rad = ((grad.rot || 0) * Math.PI) / 180;
    const cs = Math.cos(rad);
    const sn = Math.sin(rad);
    const ox = grad.off ? grad.off[0] : 0;
    const oy = grad.off ? grad.off[1] : 0;
    const colors = grad.colors && grad.colors.length ? grad.colors : null;
    const trans = grad.trans && grad.trans.length ? grad.trans : null;
    // table de 256 pas (couleur, transparence)
    const lut = new Float32Array(256 * 4);
    for (let i = 0; i < 256; i++) {
      const t = i / 255;
      const c = colors ? sampleSeq(colors, t, [255, 255, 255]) : [255, 255, 255];
      const a = trans ? sampleSeq(trans, t, [0])[0] : 0;
      lut[i * 4] = c[0] / 255;
      lut[i * 4 + 1] = c[1] / 255;
      lut[i * 4 + 2] = c[2] / 255;
      lut[i * 4 + 3] = 1 - a;
    }
    const W = x1 - x0;
    for (let py = y0; py < y1; py++) {
      const v = (py + 0.5 - y) / h - 0.5 - oy;
      for (let px = x0; px < x1; px++) {
        const idx = ((py - y0) * W + (px - x0)) * 4;
        if (d[idx + 3] === 0) continue;
        const u = (px + 0.5 - x) / w - 0.5 - ox;
        let t = u * cs + v * sn + 0.5;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        const l = Math.round(t * 255) * 4;
        d[idx] *= lut[l];
        d[idx + 1] *= lut[l + 1];
        d[idx + 2] *= lut[l + 2];
        d[idx + 3] *= lut[l + 3];
      }
    }
    ctx.putImageData(img, x0, y0);
  }

  // ------------------------------------------------------------------ contraste (WCAG)

  function lum(c) {
    const f = (v) => {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]);
  }
  function contrast(a, b) {
    const la = lum(a);
    const lb = lum(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  }
  const mix = (a, b, t) => [a[0] * t + b[0] * (1 - t), a[1] * t + b[1] * (1 - t), a[2] * t + b[2] * (1 - t)];

  // ------------------------------------------------------------------ rendu d'un écran

  const PS = {
    ButtonCross: { sym: '✕', color: [124, 178, 232] },
    ButtonCircle: { sym: '○', color: [255, 102, 102] },
    ButtonSquare: { sym: '□', color: [255, 105, 248] },
    ButtonTriangle: { sym: '△', color: [64, 226, 160] },
    ButtonL1: { label: 'L1' },
    ButtonR1: { label: 'R1' },
    ButtonL2: { label: 'L2' },
    ButtonR2: { label: 'R2' },
    ButtonL3: { label: 'L3' },
    ButtonR3: { label: 'R3' },
    DPadUp: { sym: '▲', dpad: true },
    DPadDown: { sym: '▼', dpad: true },
    DPadLeft: { sym: '◀', dpad: true },
    DPadRight: { sym: '▶', dpad: true },
  };

  function render(dump, options) {
    const opts = options || {};
    const [VW, VH] = dump.viewport;
    const canvas = document.createElement('canvas');
    canvas.width = VW;
    canvas.height = VH;
    const main = canvas.getContext('2d');
    if (!opts.noSky) {
      // monde 3D absent : ciel clair et sol (pire cas pour les textes blancs sans fond)
      const sky = main.createLinearGradient(0, 0, 0, VH);
      sky.addColorStop(0, '#7fb6f0');
      sky.addColorStop(0.55, '#cfe6ff');
      sky.addColorStop(0.551, '#6fb36a');
      sky.addColorStop(1, '#3f7f3f');
      main.fillStyle = sky;
      main.fillRect(0, 0, VW, VH);
    }

    const nodes = dump.nodes || [];
    const byIndex = new Map();
    const kids = new Map();
    for (const n of nodes) {
      byIndex.set(n.i, n);
      const key = `${n.g}:${n.p}`;
      if (!kids.has(key)) kids.set(key, []);
      kids.get(key).push(n);
    }
    const childrenOf = (g, p) => (kids.get(`${g}:${p}`) || []).slice().sort((a, b) => a.z - b.z || a.o - b.o);

    const items = []; // problèmes
    const texts = []; // textes dessinés (contrôles)
    const opaque = []; // fonds opaques dessinés (occultations)
    let drawIndex = 0;
    const layers = [{ canvas, ctx: main, ox: 0, oy: 0 }];
    const rootScale = dump.rootScale || 1;
    const minPx = (dump.minReadable || 28) * rootScale;

    function ancestors(n) {
      const out = new Set();
      let cur = n;
      while (cur && cur.p) {
        out.add(cur.p);
        cur = byIndex.get(cur.p);
      }
      return out;
    }

    function clipRect(n) {
      return n.clip ? { x: n.clip[0], y: n.clip[1], w: n.clip[2], h: n.clip[3] } : null;
    }
    function inter(a, b) {
      if (!a) return b;
      if (!b) return a;
      const x0 = Math.max(a.x, b.x);
      const y0 = Math.max(a.y, b.y);
      const x1 = Math.min(a.x + a.w, b.x + b.w);
      const y1 = Math.min(a.y + a.h, b.y + b.h);
      return { x: x0, y: y0, w: Math.max(0, x1 - x0), h: Math.max(0, y1 - y0) };
    }
    const area = (r) => (r ? r.w * r.h : 0);

    // couleur moyenne déjà dessinée sous un rectangle (pile des calques)
    function backdrop(r) {
      let color = null;
      for (let li = layers.length - 1; li >= 0; li--) {
        const L = layers[li];
        const x0 = Math.max(0, Math.floor(r.x - L.ox));
        const y0 = Math.max(0, Math.floor(r.y - L.oy));
        const x1 = Math.min(L.canvas.width, Math.ceil(r.x + r.w - L.ox));
        const y1 = Math.min(L.canvas.height, Math.ceil(r.y + r.h - L.oy));
        if (x1 <= x0 || y1 <= y0) continue;
        const d = L.ctx.getImageData(x0, y0, x1 - x0, y1 - y0).data;
        let R = 0;
        let G = 0;
        let B = 0;
        let A = 0;
        let cnt = 0;
        const step = Math.max(1, Math.floor(d.length / 4 / 4000)) * 4;
        for (let i = 0; i < d.length; i += step) {
          const a = d[i + 3] / 255;
          R += d[i] * a;
          G += d[i + 1] * a;
          B += d[i + 2] * a;
          A += a;
          cnt++;
        }
        if (cnt === 0) continue;
        const alpha = A / cnt;
        const c = A > 0 ? [R / A, G / A, B / A] : [0, 0, 0];
        if (color === null) color = { c, a: alpha };
        else {
          // calque du dessous sous le calque du dessus
          const top = color;
          const outA = top.a + alpha * (1 - top.a);
          const oc = mix(top.c, c, top.a / Math.max(outA, 1e-6));
          color = { c: oc, a: outA };
        }
        if (color.a > 0.99) break;
      }
      // fond transparent (panneaux du monde) : ciel moyen derrière
      const world = [93, 143, 191];
      if (!color) return world;
      return color.a >= 0.99 ? color.c : mix(color.c, world, color.a);
    }

    // multiplicateur de couleur des UIGradient des CanvasGroup qui contiennent n, au point (px, py)
    function groupTint(n, px, py) {
      const out = [1, 1, 1];
      let cur = byIndex.get(n.p);
      while (cur) {
        if (cur.c === 'CanvasGroup' && cur.grad) {
          const g = cur.grad;
          const rad = ((g.rot || 0) * Math.PI) / 180;
          const u = (px - cur.x) / cur.w - 0.5 - (g.off ? g.off[0] : 0);
          const v = (py - cur.y) / cur.h - 0.5 - (g.off ? g.off[1] : 0);
          const tt = Math.max(0, Math.min(1, u * Math.cos(rad) + v * Math.sin(rad) + 0.5));
          const c = g.colors && g.colors.length ? sampleSeq(g.colors, tt, [255, 255, 255]) : [255, 255, 255];
          out[0] *= c[0] / 255;
          out[1] *= c[1] / 255;
          out[2] *= c[2] / 255;
        }
        cur = byIndex.get(cur.p);
      }
      return out;
    }

    function drawBackground(ctx, n, alpha) {
      const bgA = (1 - n.bgt) * alpha;
      const r = radiusOf(n, n.w, n.h);
      if (bgA > 0.001 && n.bg) {
        ctx.fillStyle = rgba(n.bg, bgA);
        roundRect(ctx, n.x, n.y, n.w, n.h, r);
        ctx.fill();
      }
      // bordure héritée (pas avec UICorner) ; transparence = celle du fond
      if (!n.corner && n.bs > 0 && bgA > 0.001 && n.bc) {
        const b = n.bs * (n.k || 1);
        ctx.fillStyle = rgba(n.bc, bgA);
        const o = n.bm === 'Inset' ? 0 : n.bm === 'Middle' ? b / 2 : b;
        const x = n.x - o;
        const y = n.y - o;
        const w = n.w + 2 * o;
        const h = n.h + 2 * o;
        ctx.beginPath();
        ctx.rect(x, y, w, h);
        ctx.rect(x + b, y + b, Math.max(0, w - 2 * b), Math.max(0, h - 2 * b));
        ctx.fill('evenodd');
      }
    }

    function drawBorderStroke(ctx, n, alpha) {
      const s = n.stroke;
      if (!s) return;
      const contextual = s.mode !== 'Border';
      // Contextual sur un texte : contour des lettres (rien si le texte est vide), jamais du cadre
      if (contextual && n.text) return;
      const a = (1 - s.t) * alpha;
      if (a <= 0.001 || s.thick <= 0) return;
      const r = radiusOf(n, n.w, n.h);
      const pos = s.pos || 'Outer';
      const off = pos === 'Inner' ? -s.thick / 2 : pos === 'Center' ? 0 : s.thick / 2;
      ctx.strokeStyle = rgba(s.color, a);
      ctx.lineWidth = s.thick;
      ctx.lineJoin = (s.join || 'Round').toLowerCase();
      roundRect(ctx, n.x - off, n.y - off, n.w + 2 * off, n.h + 2 * off, r > 0 ? r + off : 0);
      ctx.stroke();
    }

    function drawImage(ctx, n, alpha) {
      const im = n.img;
      const a = (1 - im.t) * alpha;
      if (a <= 0.001 || !im.id) return;
      let { x, y, w, h } = n;
      if (im.scale === 'Fit') {
        const s = Math.min(w, h);
        x += (w - s) / 2;
        y += (h - s) / 2;
        w = s;
        h = s;
      }
      const m = /PlayStationController\/([A-Za-z0-9]+)@/.exec(im.id);
      const ps = m && PS[m[1]];
      if (ps) {
        const cx = x + w / 2;
        const cy = y + h / 2;
        const rr = Math.min(w, h) / 2;
        ctx.fillStyle = rgba([30, 30, 36], a);
        if (ps.label) {
          roundRect(ctx, x + w * 0.04, y + h * 0.18, w * 0.92, h * 0.64, h * 0.18);
          ctx.fill();
          ctx.fillStyle = rgba([235, 235, 240], a);
          ctx.font = `700 ${h * 0.42}px "Montserrat", sans-serif`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillText(ps.label, cx, cy + h * 0.02);
        } else {
          ctx.beginPath();
          ctx.arc(cx, cy, rr * 0.96, 0, Math.PI * 2);
          ctx.fill();
          ctx.fillStyle = rgba(ps.color || [235, 235, 240], a);
          ctx.font = `700 ${rr * (ps.dpad ? 0.95 : 1.15)}px "Noto Sans Symbols 2", "Noto Sans Symbols", sans-serif`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillText(ps.sym, cx, cy + rr * 0.05);
        }
        ctx.textAlign = 'left';
        ctx.textBaseline = 'alphabetic';
        return;
      }
      const c = im.color || [255, 255, 255];
      ctx.fillStyle = rgba(c, 0.3 * a);
      ctx.fillRect(x, y, w, h);
      ctx.strokeStyle = rgba(c, 0.7 * a);
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 3]);
      ctx.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
      ctx.setLineDash([]);
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + w, y + h);
      ctx.moveTo(x + w, y);
      ctx.lineTo(x, y + h);
      ctx.stroke();
      if (w > 40 && h > 14) {
        const id = im.id.replace(/^rbxasset(id)?:\/\/(textures\/)?/, '');
        ctx.fillStyle = rgba([20, 20, 20], 0.8 * a);
        ctx.font = `600 ${Math.min(12, h / 3)}px "Montserrat", sans-serif`;
        ctx.fillText(id.slice(0, Math.floor(w / 6)), x + 3, y + Math.min(12, h / 3) + 2);
      }
    }

    // texte : dessin + mesures pour les contrôles
    function drawText(ctx, n, alpha) {
      const t = n.text;
      const shown = t.shown || '';
      const pad = (t.fit && t.fit.pad) || [0, 0, 0, 0];
      const k = n.k || 1;
      const bx = n.x + pad[0];
      const by = n.y + pad[1];
      const bw = Math.max(0, n.w - pad[0] - pad[2]);
      const bh = Math.max(0, n.h - pad[1] - pad[3]);
      const L = layoutText(t, bw / k, bh / k, k, opts.capMode);
      // même texte si Roblox bornait TextScaled en px d'écran (après UIScale) : écart à signaler
      const Lalt = t.scaled && opts.capMode !== 'screen' ? layoutText(t, bw / k, bh / k, k, 'screen') : null;
      const sizeReal = L.size * k;
      const lineH = sizeReal * L.lh;
      const blockW = L.blockW * k;
      const blockH = L.blockH * k;
      const xa = t.xa || 'Center';
      const ya = t.ya || 'Center';
      const top = ya === 'Top' ? by : ya === 'Bottom' ? by + bh - blockH : by + (bh - blockH) / 2;
      const left = xa === 'Left' ? bx : xa === 'Right' ? bx + bw - blockW : bx + (bw - blockW) / 2;
      const ink = { x: left, y: top, w: blockW, h: blockH };
      const textA = (1 - (t.t || 0)) * alpha;
      const entry = { n, L, ink, sizeReal, box: { x: bx, y: by, w: bw, h: bh }, draw: drawIndex, textA };
      if (Lalt) {
        entry.altReal = Lalt.size * k;
        entry.altL = Lalt;
      }
      // calibrage : taille retenue par tests/harness/TextFit (largeurs sans crénage) vs navigateur
      if (t.scaled && t.fit && t.fit.size && shown.trim() !== '') entry.luauSize = t.fit.size;
      if (shown.trim() !== '' && textA > 0.01) {
        const clipped = inter(ink, clipRect(n));
        if (area(clipped) > 1) {
          // UIGradient d'un CanvasGroup englobant : multiplie TOUT le groupe (texte, contour et fond)
          const tint = groupTint(n, clipped.x + clipped.w / 2, clipped.y + clipped.h / 2);
          const mul = (c) => [c[0] * tint[0], c[1] * tint[1], c[2] * tint[2]];
          const bgc = mul(backdrop(clipped));
          const tc = mul(t.color || [0, 0, 0]);
          const color = mix(tc, bgc, Math.min(1, textA));
          let ratio = contrast(color, bgc);
          const s = n.stroke;
          if (s && s.mode !== 'Border' && s.t < 0.5 && s.thick >= 0.75) {
            ratio = Math.max(ratio, contrast(tc, mul(s.color)));
          } else if (t.strokeT < 0.5) {
            ratio = Math.max(ratio, contrast(tc, mul(t.strokeColor || [0, 0, 0])));
          }
          if (tint[0] < 0.999 || tint[1] < 0.999 || tint[2] < 0.999) entry.tint = tint.map((v) => +v.toFixed(3));
          entry.contrast = ratio;
          entry.backdrop = bgc.map(Math.round);
        }
      }
      texts.push(entry);
      if (shown === '' || textA <= 0.001) return;
      const m = metrics(L.key);
      const st = n.stroke && n.stroke.mode !== 'Border' ? n.stroke : null;
      ctx.textBaseline = 'alphabetic';
      ctx.textAlign = 'left';
      L.lines.forEach((line, li) => {
        const lw = line.w * k;
        let x = xa === 'Left' ? bx : xa === 'Right' ? bx + bw - lw : bx + (bw - lw) / 2;
        const baseline = top + li * lineH + (lineH - sizeReal) / 2 + m.ascent * sizeReal;
        const segs = [];
        let i = line.a;
        while (i <= line.b) {
          const s = L.parsed.chars[i].s;
          let str = '';
          while (i <= line.b && L.parsed.chars[i].s === s) {
            str += L.parsed.chars[i].c;
            i++;
          }
          segs.push({ str, style: L.parsed.styles[s] });
        }
        if (line.ell) segs.push({ str: ELLIPSIS, style: L.parsed.styles[0] });
        for (const seg of segs) {
          ctx.font = fontSpec(L.key, sizeReal, seg.style.bold, seg.style.italic);
          const fill = seg.style.color || t.color || [0, 0, 0];
          const stroke = seg.style.stroke
            ? { color: seg.style.stroke.color, thick: seg.style.stroke.thick * k, t: seg.style.stroke.t }
            : st;
          if (stroke && stroke.thick > 0) {
            const sa = (1 - stroke.t) * textA;
            if (sa > 0.001) {
              ctx.strokeStyle = rgba(stroke.color, sa);
              ctx.lineWidth = 2 * stroke.thick;
              ctx.lineJoin = ((st && st.join) || 'Round').toLowerCase();
              ctx.strokeText(seg.str, x, baseline);
            }
          } else if (t.strokeT < 1) {
            ctx.strokeStyle = rgba(t.strokeColor || [0, 0, 0], (1 - t.strokeT) * textA);
            ctx.lineWidth = 2 * Math.max(1, k);
            ctx.lineJoin = 'round';
            ctx.strokeText(seg.str, x, baseline);
          }
          ctx.fillStyle = rgba(fill, textA);
          ctx.fillText(seg.str, x, baseline);
          x += width(seg.str, L.key, seg.style, sizeReal);
        }
      });
    }

    function drawScrollbar(ctx, n, alpha) {
      const s = n.scroll;
      if (!s || s.contentH <= n.h + 1 || s.thick <= 0) return;
      const a = (1 - s.t) * alpha;
      if (a <= 0.001) return;
      const len = Math.max(s.thick * 2, (n.h * n.h) / s.contentH);
      const pos = (s.offY / Math.max(1, s.contentH - n.h)) * (n.h - len);
      ctx.fillStyle = rgba(s.color || [0, 0, 0], a);
      ctx.fillRect(n.x + n.w - s.thick, n.y + pos, s.thick, len);
    }

    function drawOwn(ctx, n, alpha) {
      drawBackground(ctx, n, alpha);
      if (n.img) drawImage(ctx, n, alpha);
      if (n.text) drawText(ctx, n, alpha);
    }

    function withClip(ctx, n, fn) {
      const c = clipRect(n);
      ctx.save();
      if (c) {
        ctx.beginPath();
        ctx.rect(c.x, c.y, c.w, c.h);
        ctx.clip();
      }
      fn();
      ctx.restore();
    }

    function newLayer(x, y, w, h) {
      const c = document.createElement('canvas');
      c.width = Math.max(1, Math.ceil(w) + 2);
      c.height = Math.max(1, Math.ceil(h) + 2);
      const ctx = c.getContext('2d');
      const ox = Math.floor(x) - 1;
      const oy = Math.floor(y) - 1;
      ctx.translate(-ox, -oy);
      return { canvas: c, ctx, ox, oy };
    }

    function drawNode(ctx, n, alpha, guiZb) {
      drawIndex++;
      const myIndex = drawIndex;
      ctx.save();
      if (n.rot) {
        const cx = n.x + n.w / 2;
        const cy = n.y + n.h / 2;
        ctx.translate(cx, cy);
        ctx.rotate((n.rot * Math.PI) / 180);
        ctx.translate(-cx, -cy);
      }
      const visibleRect = inter({ x: n.x, y: n.y, w: n.w, h: n.h }, clipRect(n));
      if (n.bgt < 0.4 && alpha > 0.6 && area(visibleRect) > 0) opaque.push({ draw: myIndex, r: visibleRect, n });
      if (n.c === 'CanvasGroup') {
        const L = newLayer(n.x, n.y, n.w, n.h);
        layers.push(L);
        L.ctx.save();
        roundRect(L.ctx, n.x, n.y, n.w, n.h, radiusOf(n, n.w, n.h));
        L.ctx.clip();
        drawOwn(L.ctx, n, 1);
        if (guiZb !== 'Global') for (const ch of childrenOf(n.g, n.i)) drawNode(L.ctx, ch, 1, guiZb);
        L.ctx.restore();
        layers.pop();
        if (n.grad) applyGradient(L.canvas, n.grad, n.x - L.ox, n.y - L.oy, n.w, n.h);
        withClip(ctx, n, () => {
          ctx.globalAlpha = alpha * (1 - (n.gt || 0));
          ctx.drawImage(L.canvas, L.ox, L.oy);
          ctx.globalAlpha = 1;
          drawBorderStroke(ctx, n, alpha * (1 - (n.gt || 0)));
        });
      } else {
        withClip(ctx, n, () => {
          if (n.grad) {
            const L = newLayer(n.x - 2, n.y - 2, n.w + 4, n.h + 4);
            layers.push(L);
            drawOwn(L.ctx, n, 1);
            layers.pop();
            applyGradient(L.canvas, n.grad, n.x - L.ox, n.y - L.oy, n.w, n.h);
            ctx.globalAlpha = alpha;
            ctx.drawImage(L.canvas, L.ox, L.oy);
            ctx.globalAlpha = 1;
            drawBorderStroke(ctx, n, alpha);
          } else {
            drawBackground(ctx, n, alpha);
            drawBorderStroke(ctx, n, alpha);
            if (n.img) drawImage(ctx, n, alpha);
            if (n.text) drawText(ctx, n, alpha);
          }
          if (n.scroll) drawScrollbar(ctx, n, alpha);
        });
        if (guiZb !== 'Global') for (const ch of childrenOf(n.g, n.i)) drawNode(ctx, ch, alpha, guiZb);
      }
      ctx.restore();
    }

    // écrans : DisplayOrder puis ordre dans PlayerGui
    const guis = (dump.guis || []).map((g, gi) => ({ ...g, gi: gi + 1 }));
    guis.sort((a, b) => a.displayOrder - b.displayOrder || a.order - b.order);
    for (const g of guis) {
      if (g.zb === 'Global') {
        const all = nodes.filter((n) => n.g === g.gi).sort((a, b) => a.z - b.z || a.i - b.i);
        for (const n of all) drawNode(main, n, 1, 'Global');
      } else {
        for (const n of childrenOf(g.gi, 0)) drawNode(main, n, 1, 'Sibling');
      }
    }

    // cadre de sélection (GuiService.SelectedObject) par-dessus tout
    const sel = dump.selected;
    if (sel && sel.rect && !sel.hidden) {
      const [x, y, w, h] = sel.rect;
      const o = sel.outset || [4, 4];
      const r = sel.radius || 8;
      if (sel.edge && sel.edgeColor) {
        main.strokeStyle = rgba(sel.edgeColor, 1);
        main.lineWidth = (sel.thick || 3) + 2 * sel.edge;
        main.beginPath();
        main.roundRect(x - o[0], y - o[1], w + 2 * o[0], h + 2 * o[1], r);
        main.stroke();
      }
      main.strokeStyle = rgba(sel.color || [255, 255, 255], 1);
      main.lineWidth = sel.thick || 3;
      main.beginPath();
      main.roundRect(x - o[0], y - o[1], w + 2 * o[0], h + 2 * o[1], r);
      main.stroke();
    }

    // zone sûre TV (pointillés fins)
    if (dump.safe) {
      const [x, y, w, h] = dump.safe;
      main.save();
      main.setLineDash([10, 8]);
      main.lineWidth = Math.max(1, VH / 720);
      main.strokeStyle = 'rgba(255,0,200,0.85)';
      main.strokeRect(x + 0.5, y + 0.5, w - 1, h - 1);
      main.restore();
    }

    // ---------------------------------------------------------------- contrôles
    const add = (kind, n, message, extra) =>
      items.push({ kind, path: n ? n.path : '', text: n && n.text ? n.text.shown : undefined, message, ...extra });
    const screenRect = { x: 0, y: 0, w: VW, h: VH };
    const safe = dump.safe ? { x: dump.safe[0], y: dump.safe[1], w: dump.safe[2], h: dump.safe[3] } : null;
    const nearestClipper = (n) => {
      let cur = byIndex.get(n.p);
      while (cur) {
        if (cur.c === 'ScrollingFrame' || cur.cd || cur.c === 'CanvasGroup') return cur;
        cur = byIndex.get(cur.p);
      }
      return null;
    };
    const R = (r) => [Math.round(r.x), Math.round(r.y), Math.round(r.w), Math.round(r.h)];
    const outside = (r, bound) =>
      Math.max(bound.x - r.x, bound.y - r.y, r.x + r.w - (bound.x + bound.w), r.y + r.h - (bound.y + bound.h));

    for (const e of texts) {
      const { n, L, ink } = e;
      const t = n.text;
      const shown = (t.shown || '').trim();
      if (shown === '') {
        // texte prévu (TextScaled ou UITextSizeConstraint) laissé vide
        // seulement si une boîte VISIBLE est dessinée (pastille, bouton) : sinon rien ne se voit
        const boxVisible = (n.bgt < 0.99 && (n.bg || n.grad)) || (n.stroke && n.stroke.mode === 'Border' && n.stroke.t < 0.99);
        if ((t.scaled || t.maxS != null) && boxVisible && !n.deco && n.c !== 'TextBox' && !t.placeholder)
          add('empty', n, 'boîte de texte visible mais vide', { rect: R(n) });
        continue;
      }
      if (e.textA <= 0.01) continue;
      const k = n.k || 1;
      const clip = clipRect(n);
      const visible = inter(ink, clip);
      if (clip && area(visible) < 1) continue; // défilé hors de vue
      if (t.scaled && !L.fitsMin)
        add('overflow', n, `ne tient pas même à MinTextSize ${L.size} (TextScaled)`, {
          rect: R(ink),
          size: +e.sizeReal.toFixed(1),
        });
      else if (!L.truncated && (L.overflowX * k > 1 || L.overflowY * k > Math.max(1, 0.15 * e.sizeReal)))
        add(
          'overflow',
          n,
          `déborde de ${Math.round(L.overflowX * k)} × ${Math.round(L.overflowY * k)} px (boîte ${Math.round(e.box.w)} × ${Math.round(e.box.h)})`,
          { rect: R(ink), size: +e.sizeReal.toFixed(1) },
        );
      if (L.split) add('splitWord', n, 'mot coupé par le retour à la ligne', { rect: R(ink) });
      if (L.lines.length > 1 && /[\p{L}\p{N}]/u.test(shown)) {
        // signe seul sur sa ligne (« ACCLAMER » / « ! », « … · » / « ★ ») : espace normale avant
        const orphan = L.lines.find((l) => l.b >= l.a && /\S/.test(text(L.parsed, l.a, l.b)) && !/[\p{L}\p{N}]/u.test(text(L.parsed, l.a, l.b)));
        if (orphan) add('orphan', n, `« ${text(L.parsed, orphan.a, orphan.b).trim()} » seul sur une ligne`, { rect: R(ink) });
        // mêmes règles que tests/harness/TextFit (unitSplit, noms en capitales), mais sur les lignes
        // du NAVIGATEUR : avec le crénage, une ligne peut se couper ailleurs que dans la mesure Luau
        // (« Autocollant Jour » / « 1 » ici, « Autocollant » / « Jour 1 » en Luau : revue de l'outil)
        const UNITS = ['s', 'min', 'h', 'j', '%', 'K', 'M', 'B', 'T', 'Qa', 'Qi', 'Sx', 'Sp', 'Oc', 'No', 'Dc', 'px', 'sur'];
        const BRANDS = [['BOOP', 'RUSH'], ['MEGA', 'SQUISH']];
        for (let li = 1; li < L.lines.length; li++) {
          const prev = text(L.parsed, L.lines[li - 1].a, L.lines[li - 1].b).replace(/\s+$/u, '');
          const cur = text(L.parsed, L.lines[li].a, L.lines[li].b).replace(/^\s+/u, '').replace(/\s+$/u, '');
          const unit = UNITS.find((u) => cur.startsWith(u) && (cur.length === u.length || /[\s.,;:!?)/]/u.test(cur[u.length])));
          const brand = BRANDS.find(([a, b]) => new RegExp(`(^|[\\s\\p{P}])${a}$`, 'u').test(prev) && cur.startsWith(b));
          if (/\d$/u.test(prev) && unit) {
            add('unitSplit', n, `« ${prev.slice(-8)} » / « ${cur.slice(0, 8)} » : unité séparée de son nombre`, { rect: R(ink) });
            break;
          } else if (/\p{L}$/u.test(prev) && /\d/u.test(cur) && /^[\d\s  ,.!?]+$/u.test(cur)) {
            add('unitSplit', n, `« ${prev.slice(-12)} » / « ${cur} » : nombre séparé de son mot`, { rect: R(ink) });
            break;
          } else if (brand) {
            add('splitWord', n, `nom « ${brand.join(' ')} » coupé par le retour à la ligne`, { rect: R(ink) });
            break;
          }
        }
      }
      if (L.truncated) {
        const num = /\d/.test(L.hidden);
        const rest = /^\S*\s+(.*)$/.exec(L.hidden);
        const word = rest && rest[1].split(/\s+/).find((w) => (w.match(/\p{L}/gu) || []).length >= 2);
        add('truncated', n, `« … » cache « ${L.hidden} »`, {
          hidden: L.hidden,
          severe: num || !!word,
          rect: R(ink),
        });
      }
      if (clip && area(visible) + 2 < area(ink)) {
        const clipper = nearestClipper(n);
        const boxCut = area(inter(e.box, clip)) + 2 < area(e.box);
        // rangée entrouverte d'une liste virtuelle (attribut PeekRows, Widgets.rows) : voulue, classée
        // à part (information)
        if (clipper && clipper.peek)
          add('peek', n, `rangée entrouverte de ${clipper.path} (voulue : annonce la suite de la liste)`, { rect: R(ink) });
        else if (!(clipper && clipper.c === 'ScrollingFrame' && boxCut))
          add('clipped', n, `coupé par ${clipper ? clipper.path : 'un parent'} (${Math.round(area(ink) - area(visible))} px² cachés)`, {
            rect: R(ink),
          });
      }
      if (!n.deco && e.sizeReal < minPx - 0.05)
        add(
          t.scaled ? 'small' : 'smallFixed',
          n,
          `${e.sizeReal.toFixed(1)} px réels < ${minPx.toFixed(1)} px (${dump.minReadable || 28} px de référence × ${rootScale})`,
          { size: +e.sizeReal.toFixed(1) },
        );
      // information (pas un défaut) : taille qui dépend de l'ordre plafond / UIScale de Roblox. Les
      // DEUX ordres sont calculés : bornes (MinTextSize, MaxTextSize, plafond de 100) comptées avant
      // UIScale (rendu dessiné) ou après (px d'écran). Signalé si l'autre ordre change la taille ET
      // la rend illisible (sous le minimum) ou la fait déborder (MinTextSize en px d'écran > boîte,
      // typiquement en 720p où UIScale < 1).
      if (e.altReal !== undefined && !n.deco && Math.abs(e.sizeReal - e.altReal) > 0.5) {
        const A = e.altL;
        const altBelow = e.altReal < minPx - 0.05;
        const altOverflow =
          !!A && (!A.fitsMin || A.overflowX * k > 1 || A.overflowY * k > Math.max(1, 0.15 * e.altReal));
        if (altBelow || altOverflow || e.sizeReal > e.altReal * 1.1 + 0.5)
          add(
            'capRisk',
            n,
            `TextScaled ${e.sizeReal.toFixed(1)} px réels ; ${e.altReal.toFixed(1)} px si les bornes s'appliquent après UIScale${
              altBelow ? ' (alors sous le minimum lisible)' : ''
            }${altOverflow ? ' (alors le texte déborde)' : ''}`,
            {
              size: +e.sizeReal.toFixed(1),
              alt: +e.altReal.toFixed(1),
              belowMin: altBelow,
              overflowAlt: altOverflow,
              atRisk: altBelow || altOverflow,
            },
          );
      }
      // icônes en texte (emoji en couleur, symboles) : pas de contrôle de contraste
      const iconOnly = !/[\p{L}\p{N}]/u.test(shown);
      if (!n.deco && !iconOnly && e.contrast !== undefined && e.contrast < 3)
        add(
          'contrast',
          n,
          `contraste ${e.contrast.toFixed(2)} < 3 (texte ${JSON.stringify(t.color)} sur ${JSON.stringify(e.backdrop)}${
            e.tint ? `, teinté ×${JSON.stringify(e.tint)} par l'UIGradient d'un CanvasGroup parent` : ''
          })`,
          {
          ratio: +e.contrast.toFixed(2),
          rect: R(visible),
        });
      if (!n.deco && e.tint && Math.min(...e.tint) < 0.6)
        add('tinted', n, `couleur du texte multipliée par ×${JSON.stringify(e.tint)} (UIGradient d'un CanvasGroup parent : il teinte tout le groupe)`, {
          rect: R(ink),
        });
      if (/^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9_]+)+$/.test(shown)) add('rawKey', n, 'clé de localisation affichée');
      if (/\{[A-Za-z0-9_]+\}/.test(shown)) add('placeholder', n, 'variable non remplacée');
      {
        // « 60 → 60 places » : flèche de progression sans changement (niveau maximum)
        const parts = shown.split('→');
        const a = parts.length === 2 ? parts[0].trim() : '';
        const b = parts.length === 2 ? parts[1].trim() : '';
        if (a !== '' && (b === a || b.startsWith(a + ' ') || b.startsWith(a + '\u00a0')))
          add('noChange', n, `« ${shown} » : la flèche annonce un changement qui n'existe pas`);
      }
      const vr = visible || ink;
      if (!n.deco && outside(vr, screenRect) > 2) add('offscreen', n, `texte hors de l'écran de ${Math.round(outside(vr, screenRect))} px`, { rect: R(vr) });
      else if (safe && !n.deco && outside(vr, safe) > 2)
        add('unsafe', n, `texte hors de la zone sûre TV de ${Math.round(outside(vr, safe))} px`, { rect: R(vr) });
    }
    // objets sélectionnables ou visibles hors écran / hors zone sûre
    for (const n of nodes) {
      if (n.deco || n.text) continue;
      const hasContent = n.sel || n.img || n.bgt < 0.9 || n.stroke;
      if (!hasContent) continue;
      if (n.w >= VW - 1 && n.h >= VH - 60) continue; // fonds plein écran
      const vr = inter({ x: n.x, y: n.y, w: n.w, h: n.h }, clipRect(n));
      if (area(vr) < 1) continue;
      if (outside(vr, screenRect) > 2)
        add('offscreen', n, `${n.c} hors de l'écran de ${Math.round(outside(vr, screenRect))} px`, { rect: R(vr) });
      else if (safe && n.sel && outside(vr, safe) > 2)
        add('unsafe', n, `bouton hors de la zone sûre TV de ${Math.round(outside(vr, safe))} px`, { rect: R(vr) });
    }
    // chevauchements : textes entre eux, boutons entre eux (ni parent ni enfant, aucun fond opaque
    // dessiné entre les deux qui couvre la zone commune)
    const anc = new Map();
    const ancOf = (n) => {
      if (!anc.has(n.i)) anc.set(n.i, ancestors(n));
      return anc.get(n.i);
    };
    const covered = (r, d0, d1) => opaque.some((o) => o.draw > d0 && o.draw < d1 && inter(o.r, r).w >= r.w - 0.5 && inter(o.r, r).h >= r.h - 0.5);
    const related = (a, b) => ancOf(a).has(b.i) || ancOf(b).has(a.i);
    const shownTexts = texts.filter((e) => (e.n.text.shown || '').trim() !== '' && e.textA > 0.01 && !e.n.deco);
    // icône en texte (symbole sans lettre ni chiffre : ✓, !, ★…) : superposition voulue (pastille,
    // coche) ; exclue des chevauchements
    const isIcon = (e) => !/[\p{L}\p{N}]/u.test(e.n.text.shown || '');
    const inkVis = (e) => inter(e.ink, clipRect(e.n));
    for (let i = 0; i < shownTexts.length; i++) {
      const A = shownTexts[i];
      const ra = inkVis(A);
      if (area(ra) < 4) continue;
      for (let j = i + 1; j < shownTexts.length; j++) {
        const B = shownTexts[j];
        const rb = inkVis(B);
        if (area(rb) < 4) continue;
        const r = inter(ra, rb);
        if (r.w < 3 || r.h < 3) continue;
        if (area(r) < 0.15 * Math.min(area(ra), area(rb))) continue;
        if (related(A.n, B.n) || isIcon(A) || isIcon(B)) continue;
        const [d0, d1] = A.draw < B.draw ? [A.draw, B.draw] : [B.draw, A.draw];
        if (covered(r, d0, d1)) continue;
        add('overlap', B.n, `texte sur « ${(A.n.text.shown || '').slice(0, 40)} » (${A.n.path})`, {
          other: A.n.path,
          rect: R(r),
        });
      }
    }
    const buttons = [];
    for (const n of nodes) if (n.sel && !n.deco) buttons.push(n);
    const order = new Map();
    {
      // index de dessin des nœuds (ordre de parcours)
      let d = 0;
      const walk = (g, p) => {
        for (const ch of childrenOf(g, p)) {
          order.set(ch.i, ++d);
          walk(g, ch.i);
        }
      };
      for (const g of guis) walk(g.gi, 0);
    }
    for (let i = 0; i < buttons.length; i++) {
      for (let j = i + 1; j < buttons.length; j++) {
        const a = buttons[i];
        const b = buttons[j];
        const ra = inter({ x: a.x, y: a.y, w: a.w, h: a.h }, clipRect(a));
        const rb = inter({ x: b.x, y: b.y, w: b.w, h: b.h }, clipRect(b));
        const r = inter(ra, rb);
        if (r.w < 3 || r.h < 3 || area(r) < 0.15 * Math.min(area(ra), area(rb))) continue;
        if (related(a, b)) continue;
        const da = order.get(a.i) || 0;
        const db = order.get(b.i) || 0;
        if (covered(r, Math.min(da, db), Math.max(da, db))) continue;
        add('overlap', b, `bouton sur le bouton ${a.path}`, { other: a.path, rect: R(r) });
      }
    }
    // message (pile des toasts) par-dessus un panneau ouvert : il cache le haut du panneau (onglets)
    {
      const windows = nodes.filter((n) => /^Panels\.Safe\.Panel_[A-Za-z]+$/.test(n.path) && n.bgt < 0.5);
      const toasts = nodes.filter((n) => /^Toasts\.Safe\.Stack\.Toast$/.test(n.path) && n.bgt < 0.5);
      // la barre de titre (96 px TV) peut recevoir le message (UI/Toast.anchor) : seul le corps compte
      const header = 96 * rootScale;
      for (const t of toasts) {
        for (const w of windows) {
          const r = inter({ x: t.x, y: t.y, w: t.w, h: t.h }, { x: w.x, y: w.y + header, w: w.w, h: w.h - header });
          if (r.w > 2 && r.h > 2) {
            add('covered', t, `message par-dessus le panneau ouvert ${w.path} (${Math.round(r.w)} × ${Math.round(r.h)} px cachés)`, {
              rect: R(r),
            });
            break;
          }
        }
      }
    }
    // fond plein (≤ 50 % transparent) qui porte du texte mais que la Transparency de son UIGradient
    // rend transparent par endroits : le HUD et le rail dessous transparaissent (« GRAND SPLORCH ! »
    // fantôme derrière les cases d'un panneau ; revue de l'outil)
    {
      const textOwners = new Set();
      for (const e of texts) for (const a of ancestors(e.n)) textOwners.add(a);
      for (const n of nodes) {
        if (n.deco || n.c === 'CanvasGroup' || !(n.bgt < 0.5) || !n.grad || !textOwners.has(n.i)) continue;
        // reflet qui passe (Offset animé, hors du cadre au repos) : effet voulu, pas un fond troué
        if (n.grad.off && (Math.abs(n.grad.off[0]) > 0.01 || Math.abs(n.grad.off[1]) > 0.01)) continue;
        const maxT = Math.max(0, ...(n.grad.trans || []).map((kp) => kp[1]));
        if (maxT > 0.001)
          add('seeThrough', n, `fond transparent à ${Math.round(maxT * 100)} % par son dégradé : ce qui est dessous transparaît`, {
            rect: R(n),
          });
      }
    }
    // fond carré d'un enfant dans le coin arrondi de son parent (ClipsDescendants coupe au rectangle,
    // jamais à l'arrondi ; seul un CanvasGroup arrondi coupe à sa forme) : jauge pleine ou balayage
    // de recharge dessinés en carré dans un cercle (revue de l'outil)
    for (const n of nodes) {
      const p = byIndex.get(n.p);
      if (!p || n.deco || p.c === 'CanvasGroup' || !(n.bgt < 0.9) || n.w <= 1 || n.h <= 1) continue;
      const rp = radiusOf(p, p.w, p.h);
      if (rp < 6) continue;
      // même couleur que le fond sous le parent (croissant de lune : rond « Bite » de la couleur de
      // l'icône) : le débord ne se voit pas
      const gp = byIndex.get(p.p);
      const same = (a, b) => a && b && Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]) + Math.abs(a[2] - b[2]) < 24;
      if (gp && gp.bgt < 0.5 && same(n.bg, gp.bg)) continue;
      const rc = radiusOf(n, n.w, n.h);
      const d = 0.29 * rp;
      const pts = [
        [p.x + d, p.y + d],
        [p.x + p.w - d, p.y + d],
        [p.x + d, p.y + p.h - d],
        [p.x + p.w - d, p.y + p.h - d],
      ];
      const painted = ([x, y]) => {
        if (!(x > n.x + 0.5 && x < n.x + n.w - 0.5 && y > n.y + 0.5 && y < n.y + n.h - 0.5)) return false;
        const cx = Math.min(Math.max(x, n.x + rc), n.x + n.w - rc);
        const cy = Math.min(Math.max(y, n.y + rc), n.y + n.h - rc);
        return (x - cx) ** 2 + (y - cy) ** 2 <= rc * rc;
      };
      if (pts.some(painted)) add('squareCorner', n, `fond carré dans le coin arrondi de ${p.path}`, { rect: R(n) });
    }
    // curseur de sélection (GuiService.SelectedObject) : visible, entier à l'écran, pas coupé par
    // un parent qui découpe (le moteur dessine SelectionImageObject DANS la découpe des ancêtres)
    if (sel) {
      if (sel.hidden) add('selection', null, `objet sélectionné invisible : ${sel.path}`, { path: sel.path });
      else if (sel.rect) {
        const o = sel.outset || [4, 4];
        const halo = { x: sel.rect[0] - o[0], y: sel.rect[1] - o[1], w: sel.rect[2] + 2 * o[0], h: sel.rect[3] + 2 * o[1] };
        const node = sel.node ? byIndex.get(sel.node) : null;
        const clip = node ? clipRect(node) : null;
        const shownHalo = inter(halo, clip);
        if (outside(halo, screenRect) > 2)
          items.push({ kind: 'selection', path: sel.path, message: `curseur hors de l'écran de ${Math.round(outside(halo, screenRect))} px`, rect: R(halo) });
        else if (clip && area(shownHalo) < 0.5 * area(halo))
          items.push({ kind: 'selection', path: sel.path, message: 'curseur presque entièrement caché par un parent qui découpe', rect: R(halo) });
      }
    }
    // problèmes vus côté Luau (clés brutes exactes, « ? », texte jamais posé)
    for (const li of dump.luauIssues || []) {
      if (li.kind === 'rawKey' || li.kind === 'question' || li.kind === 'defaultText' || li.kind === 'placeholder') {
        if (!items.some((x) => x.kind === li.kind && x.path === li.path))
          items.push({ kind: li.kind, path: li.path, text: li.text, message: li.message });
      }
    }

    // ---------------------------------------------------------------- sorties
    // écart de taille TextScaled entre la mesure Luau (TextFit) et le navigateur (vraies polices)
    const calib = { n: 0, same: 0, off1: 0, off2: 0, max: 0 };
    for (const e of texts) {
      if (e.luauSize === undefined) continue;
      const d = Math.abs(e.luauSize - e.L.size);
      calib.n++;
      if (d < 0.5) calib.same++;
      else if (d <= 1.01) calib.off1++;
      else calib.off2++;
      calib.max = Math.max(calib.max, d);
    }
    const out = { items, textCount: shownTexts.length, calib };
    if (opts.keepCanvas) out.canvas = canvas;
    if (opts.png !== false) out.png = canvas.toDataURL('image/png');
    if (opts.thumb) {
      const tw = opts.thumb;
      const th = Math.round((tw * VH) / VW);
      const tc = document.createElement('canvas');
      tc.width = tw;
      tc.height = th;
      const tctx = tc.getContext('2d');
      tctx.imageSmoothingQuality = 'high';
      tctx.drawImage(canvas, 0, 0, tw, th);
      out.thumb = tc.toDataURL('image/jpeg', 0.82);
    }
    return out;
  }

  // Panneaux du monde (BillboardGui) côte à côte, chacun à sa taille en pixels, sur un fond bleu
  // moyen (ciel) ; contrôles de texte (sans minimum lisible : la taille dépend de la distance)
  function renderBillboards(dump) {
    const list = dump.billboards || [];
    if (!list.length) return null;
    const gap = 24;
    const caption = 18;
    let W = gap;
    let H = 0;
    for (const b of list) {
      W += Math.ceil(b.w) + gap;
      H = Math.max(H, Math.ceil(b.h));
    }
    H += gap * 2 + caption;
    const canvas = document.createElement('canvas');
    canvas.width = W;
    canvas.height = H;
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#5d8fbf';
    ctx.fillRect(0, 0, W, H);
    let x = gap;
    const items = [];
    const KEEP = new Set(['overflow', 'clipped', 'truncated', 'splitWord', 'overlap', 'rawKey', 'placeholder', 'contrast', 'empty']);
    for (const b of list) {
      const sub = render(
        {
          viewport: [Math.max(1, Math.ceil(b.w)), Math.max(1, Math.ceil(b.h))],
          nodes: b.nodes || [],
          guis: [{ name: b.name, displayOrder: 0, zb: 'Sibling', order: 1 }],
          rootScale: 1,
          minReadable: 0,
        },
        { png: false, noSky: true, keepCanvas: true },
      );
      ctx.drawImage(sub.canvas, x, gap);
      ctx.strokeStyle = 'rgba(255,255,255,0.35)';
      ctx.setLineDash([4, 4]);
      ctx.strokeRect(x + 0.5, gap + 0.5, Math.ceil(b.w) - 1, Math.ceil(b.h) - 1);
      ctx.setLineDash([]);
      ctx.fillStyle = '#fff';
      ctx.font = '600 12px "Montserrat", sans-serif';
      ctx.fillText(`${b.name} ${Math.round(b.w)}×${Math.round(b.h)} px (${b.pxPerStud} px/stud)`, x, H - gap / 2 - 4);
      for (const it of sub.items) if (KEEP.has(it.kind)) items.push({ ...it, billboard: b.path });
      x += Math.ceil(b.w) + gap;
    }
    return { png: canvas.toDataURL('image/png'), items };
  }

  window.CC = { init, render, renderBillboards, layoutText, metrics: () => METRICS };
})();
