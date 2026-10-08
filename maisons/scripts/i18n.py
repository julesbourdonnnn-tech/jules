"""Versions anglaise (/en/) et espagnole (/es/) du site, générées à partir du site français.

    python3 scripts/i18n.py extract   # liste les textes à traduire -> i18n/catalogue.json + textes manquants
    python3 scripts/i18n.py build     # génère en/ et es/ (et met à jour les liens de langue des pages françaises)

Le site français reste la source : on le modifie, puis on relance « build ».
Les traductions sont dans i18n/traductions/*.json : { "texte français": ["english", "español"] }.
Un texte absent du dictionnaire reste en français (la commande « extract » les liste).
Nécessite : pip install beautifulsoup4 ; Node.js (pour lire js/data.js).
"""
import json
import os
import re
import subprocess
import sys

from bs4 import BeautifulSoup, Comment, NavigableString

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = "https://sable-et-pierre.com"
LANGS = {
    "en": {"intl": "en-GB", "og": "en_GB", "airbnb": "https://www.airbnb.com", "name": "English"},
    "es": {"intl": "es-ES", "og": "es_ES", "airbnb": "https://www.airbnb.es", "name": "Español"},
}
# Pages traduites (les autres — mentions légales, admin, 404 — restent en français)
PAGES = ["index.html", "lacanau.html", "bordeaux.html", "conditions.html", "reservation.html",
         "vacances-famille-lacanau.html", "vacances-famille-bordeaux.html",
         "guide-plages-lacanau.html", "guide-semaine-gironde-famille.html"]
NOINDEX = {"reservation.html", "conditions.html"}
# Scripts traduits (copiés dans en/js/, es/js/)
JS = ["main.js", "home.js", "house.js", "reservation.js", "prix.js", "tarifs.js"]
SKIP_TAGS = {"script", "style", "svg", "noscript", "template", "code"}
ATTRS = ["alt", "title", "aria-label", "placeholder", "data-label"]
META = {("name", "description"), ("property", "og:title"), ("property", "og:description"), ("property", "og:image:alt")}

norm = lambda s: " ".join(str(s).split())


def letters(s):
    return re.search(r"[A-Za-zÀ-ÿ]{2}", s) is not None


def is_text(s):
    """Un fragment de texte à traduire (et pas du code)."""
    t = s.strip()
    if not t or not letters(t):
        return False
    if re.fullmatch(r"[a-z0-9_\-.:/#?=&%]+", t):  # identifiants, chemins, sélecteurs simples
        return False
    if re.fullmatch(r"https?://\S+", t):
        return False
    return bool(re.search(r"[À-ÿ]", t) or " " in t or re.match(r"[A-ZÀ-Ý]", t))


def is_french(s):
    """Contient du texte français visible (hors balises, hors code)."""
    t = re.sub(r"<[^>]*>|<[^>]*$|^[^<]*>", " ", s)
    t = re.sub(r'[\w-]+="[^"]*"', " ", t)
    return bool(re.search(r"[À-ÿ]", t)) or bool(set(w.lower() for w in re.findall(r"[A-Za-z']{3,}", t)) & FR_WORDS)


# ---------------------------------------------------------------- JavaScript
def js_fragments(src):
    """Découpe un fichier JS : renvoie la liste des (début, fin) des morceaux de texte
    dans les chaînes '…', "…" et `…` (hors ${…}), en ignorant commentaires et regex."""
    out = []
    i, n = 0, len(src)
    stack = []  # pour les ${ } imbriqués dans les gabarits
    last = ""  # dernier caractère significatif (pour distinguer / division et regex)

    def read_string(i, q):
        start = i + 1
        j = start
        while j < n:
            c = src[j]
            if c == "\\":
                j += 2
                continue
            if c == q:
                out.append((start, j, q))
                return j + 1
            j += 1
        return j

    def read_template(i):
        # i pointe juste après ` ; renvoie l'index après le ` fermant, ou l'index après ${
        start = i
        j = i
        while j < n:
            c = src[j]
            if c == "\\":
                j += 2
                continue
            if c == "`":
                out.append((start, j, "`"))
                return j + 1, False
            if c == "$" and j + 1 < n and src[j + 1] == "{":
                out.append((start, j, "`"))
                return j + 2, True
            j += 1
        return j, False

    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
            continue
        if src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
            continue
        if src.startswith("/*", i):
            i = src.find("*/", i)
            i = n if i < 0 else i + 2
            continue
        if c in "'\"":
            i = read_string(i, c)
            last = "a"
            continue
        if c == "`":
            i, opened = read_template(i + 1)
            if opened:
                stack.append(0)
            last = "a"
            continue
        if c == "{" and stack:
            stack[-1] += 1
        if c == "}" and stack:
            if stack[-1] == 0:
                stack.pop()
                i, opened = read_template(i + 1)
                if opened:
                    stack.append(0)
                last = "a"
                continue
            stack[-1] -= 1
        if c == "/" and (last == "" or last in "(,=:[!&|?{};+-*%<>~^" or src[max(0, i - 7):i].rstrip().endswith("return")):
            # expression régulière
            j = i + 1
            cls = False
            while j < n:
                ch = src[j]
                if ch == "\\":
                    j += 2
                    continue
                if ch == "[":
                    cls = True
                elif ch == "]":
                    cls = False
                elif ch == "/" and not cls:
                    break
                elif ch == "\n":
                    break
                j += 1
            i = j + 1
            while i < n and src[i].isalpha():
                i += 1
            last = "a"
            continue
        last = c if not (c.isalnum() or c in "_$") else "a"
        i += 1
    return out


def js_keys(src, data_keys):
    keys = []
    for a, b, _ in js_fragments(src):
        frag = src[a:b]
        if is_text(frag) or norm(frag) in data_keys:
            keys.append(frag)
    return keys


def translate_js(src, T, lang):
    frags = js_fragments(src)
    res, pos = [], 0
    for a, b, q in frags:
        frag = src[a:b]
        k = norm(frag)
        if k in T and T[k] != k:
            lead = frag[: len(frag) - len(frag.lstrip())]
            trail = frag[len(frag.rstrip()):]
            t = T[k].replace("\\'", "'").replace('\\"', '"')
            if q == "'":
                t = t.replace("'", "\\'")
            elif q == '"':
                t = t.replace('"', '\\"')
            else:
                t = t.replace("`", "\\`").replace("${", "\\${")
            res.append(src[pos:a])
            res.append(lead + t + trail)
            pos = b
    res.append(src[pos:])
    out = "".join(res)
    intl = LANGS[lang]["intl"]
    out = out.replace('"fr-FR"', f'"{intl}"').replace("'fr-FR'", f"'{intl}'")
    if lang == "en":  # séparateur décimal : 4.88 en anglais, 4,88 en français et en espagnol
        out = out.replace('.replace(".", ",")', "")
    # Adresses : le site traduit est dans un sous-dossier
    out = re.sub(r'(["\'`])(api|assets)/', r"\1../\2/", out)
    return out


# ---------------------------------------------------------------- Données (js/data.js)
def load_data():
    code = ("globalThis.window=globalThis;require(%s);process.stdout.write(JSON.stringify({HOUSES:window.HOUSES,DESTINATIONS:window.DESTINATIONS,REVIEWS:window.REVIEWS}))"
            % json.dumps(os.path.join(ROOT, "js", "data.js")))
    return json.loads(subprocess.check_output(["node", "-e", code]))


SKIP_DATA_KEYS = {"id", "page", "airbnbId", "airbnbUrl", "registration", "weather"}


def data_strings(o, out, key=None):
    if key in SKIP_DATA_KEYS:
        return
    if isinstance(o, str):
        if letters(o) and not re.fullmatch(r"[a-z0-9_\-]+", o) and not o.startswith("http"):
            out.append(o)
    elif isinstance(o, list):
        for v in o:
            data_strings(v, out, key)
    elif isinstance(o, dict):
        for k, v in o.items():
            data_strings(v, out, k)
            if key == "rules":
                out.append(k)  # titres des règles (clés)


CATS = [("ext", r"piscine|jardin|patio|terrasse|maison et|maison,|ponton|coucher|salon d'extérieur"), ("bed", r"chambre"), ("bath", r"salle de bain|salle d'eau"), ("live", r".")]


def translate_data(o, T, lang, key=None):
    if key in SKIP_DATA_KEYS:
        if key == "airbnbUrl":
            return re.sub(r"^https://www\.airbnb\.fr", LANGS[lang]["airbnb"], o)
        return o
    if isinstance(o, str):
        return T.get(norm(o), o)
    if isinstance(o, list):
        return [translate_data(v, T, lang, key) for v in o]
    if isinstance(o, dict):
        return {(T.get(norm(k), k) if key == "rules" else k): translate_data(v, T, lang, k) for k, v in o.items()}
    return o


def data_js(T, lang):
    d = load_data()
    for h in d["HOUSES"].values():  # catégorie des photos calculée sur la légende française
        h["photos"] = [[n, cap, next(c for c, r in CATS if re.search(r, cap, re.I))] for n, cap, *_ in h["photos"]]
    d = translate_data(d, T, lang)
    return ("/* Généré par scripts/i18n.py à partir de js/data.js — ne pas modifier à la main. */\n"
            + "".join(f"window.{k} = {json.dumps(v, ensure_ascii=False)};\n" for k, v in d.items()))


# ---------------------------------------------------------------- HTML
def units(el, out):
    """Éléments « feuilles » : ceux qui contiennent directement du texte."""
    for child in el.children:
        if isinstance(child, NavigableString) or child.name in SKIP_TAGS:
            continue
        if child.get("translate") == "no":
            continue
        direct = any(isinstance(c, NavigableString) and not isinstance(c, Comment) and c.strip() for c in child.children)
        if direct:
            out.append(child)
        else:
            units(child, out)


def inner(el):
    return el.decode_contents()


def html_keys(soup):
    keys = []
    if soup.title and soup.title.string:
        keys.append(soup.title.string)
    for m in soup.find_all("meta"):
        for a, v in META:
            if m.get(a) == v and m.get("content"):
                keys.append(m["content"])
    body = soup.body or soup
    lst = []
    units(body, lst)
    keys += [inner(u) for u in lst]
    for el in body.find_all(True):
        for a in ATTRS:
            if el.get(a) and is_text(el[a]):
                keys.append(el[a])
    for s in soup.find_all("script", type="application/ld+json"):
        def walk(o, k=None):
            if isinstance(o, str):
                if k in ("name", "description", "text") and letters(o):
                    keys.append(o)
            elif isinstance(o, list):
                for v in o:
                    walk(v, k)
            elif isinstance(o, dict):
                for kk, v in o.items():
                    walk(v, kk)
        walk(json.loads(s.string))
    for s in soup.find_all("script"):
        if not s.get("src") and s.get("type") != "application/ld+json" and s.string:
            keys += [s.string[a:b] for a, b, _ in js_fragments(s.string) if is_text(s.string[a:b])]
    return keys


def page_url(lang, page):
    p = "" if page == "index.html" else page[:-5]
    return f"{SITE}/{'' if lang == 'fr' else lang + '/'}{p}"


def lang_switch(soup, lang, page):
    """Liens FR · EN · ES dans l'en-tête (et le menu mobile)."""
    def href(target):
        if target == lang:
            return "./" if page == "index.html" else page
        up = "" if lang == "fr" else "../"
        sub = "" if target == "fr" else target + "/"
        return f"{up}{sub}{'' if page == 'index.html' else page}" or "./"
    cur = ' aria-current="true"'
    html = '<span class="langs" translate="no">' + "".join(
        f'<a href="{href(l)}" hreflang="{l}" lang="{l}"{cur if l == lang else ""}>{l.upper()}</a>' for l in ["fr", "en", "es"]) + "</span>"
    for old in soup.select(".langs"):
        old.decompose()
    nav = soup.select_one("header .nav")
    if nav:
        frag = BeautifulSoup(html, "html.parser")
        burger = nav.select_one(".burger")
        btn = nav.select_one(".btn")
        anchor = btn or burger
        if anchor:
            anchor.insert_before(frag)
        else:
            nav.append(frag)
    menu = soup.select_one(".menu__links .menu__foot")
    if menu:
        menu.insert_before(BeautifulSoup(html, "html.parser"))


def alternates(soup, page):
    for l in soup.find_all("link", rel="alternate"):
        if l.get("hreflang"):
            l.decompose()
    head = soup.head
    canon = head.find("link", rel="canonical")
    anchor = canon or head.find("title")
    for l in ["fr", "en", "es"]:
        tag = soup.new_tag("link", rel="alternate", hreflang=l, href=page_url(l, page))
        anchor.insert_after(tag)
        anchor = tag
    tag = soup.new_tag("link", rel="alternate", hreflang="x-default", href=page_url("fr", page))
    anchor.insert_after(tag)


def fix_path(v, lang):
    """Chemin relatif d'une page française -> chemin depuis /en/ ou /es/."""
    if not v or re.match(r"^(https?:|mailto:|tel:|data:|#|/|javascript:)", v):
        return v
    base = re.split(r"[?#]", v)[0]
    if base in ("", "./") or base in PAGES or base + ".html" in PAGES:
        return v  # page traduite : même dossier
    if base.startswith("js/") and base[3:] in JS + ["data.js"]:
        return v  # script traduit : copie locale
    return "../" + v


_BLOCS = {}


def prerender_bloc(lang, house):
    """Contenu prérendu des fiches, reconstruit par scripts/seo.mjs à partir des données traduites."""
    if lang not in _BLOCS:
        _BLOCS[lang] = json.loads(subprocess.check_output(["node", os.path.join(ROOT, "scripts", "seo.mjs"), "--bloc", lang], cwd=ROOT))
    return _BLOCS[lang][house]


def switch_html(lang, page):
    def href(target):
        if target == lang:
            return "./" if page == "index.html" else page
        up = "" if lang == "fr" else "../"
        sub = "" if target == "fr" else target + "/"
        return f"{up}{sub}{'' if page == 'index.html' else page}" or "./"
    cur = ' aria-current="true"'
    return '<span class="langs" translate="no">' + "".join(
        f'<a href="{href(l)}" hreflang="{l}" lang="{l}"{cur if l == lang else ""}>{l.upper()}</a>' for l in ["fr", "en", "es"]) + "</span>"


def fr_links(src, page):
    """Page française : liens FR · EN · ES et <link hreflang>, par simple insertion de texte."""
    src = re.sub(r'<span class="langs"[^>]*>(?:<a [^>]*>[A-Z]{2}</a>)*</span>', "", src)
    src = re.sub(r'\n?\s*<!-- langues -->.*?<!-- /langues -->', "", src, flags=re.S)
    sw = switch_html("fr", page)
    head = re.search(r"<header class=\"header[\s\S]*?</header>", src)
    if head:
        h = head.group(0)
        if '<a class="btn"' in h:
            h2 = h.replace('<a class="btn"', sw + '<a class="btn"', 1)
        elif '<button class="burger"' in h:
            h2 = h.replace('<button class="burger"', sw + '<button class="burger"', 1)
        else:
            h2 = re.sub(r"</nav>", sw + "</nav>", h, count=1)
        src = src.replace(h, h2, 1)
    # (lignes vides laissées par la version précédente du sélecteur : supprimées, pour un résultat identique à chaque fois)
    src = re.sub(r'(?:\n[ \t]*)+(<p class="menu__foot">)', r'\n      \1', src, count=1)
    src = src.replace('\n      <p class="menu__foot">', '\n      ' + sw + '\n      <p class="menu__foot">', 1)
    alt = "\n  <!-- langues -->" + "".join(f'<link rel="alternate" hreflang="{l}" href="{page_url(l, page)}">' for l in ["fr", "en", "es"]) + f'<link rel="alternate" hreflang="x-default" href="{page_url("fr", page)}"><!-- /langues -->'
    m = re.search(r'<link rel="canonical"[^>]*>', src)
    if m:
        src = src[: m.end()] + alt + src[m.end():]
    else:
        src = src.replace("</title>", "</title>" + alt, 1)
    return src


def build_page(page, T, lang):
    src = open(os.path.join(ROOT, page), encoding="utf-8").read()
    if page in ("lacanau.html", "bordeaux.html"):
        bloc = prerender_bloc(lang, page[:-5])
        src = re.sub(r"(<!-- seo:debut[^>]*-->)[\s\S]*?(\s*<!-- seo:fin -->)", lambda m: m.group(1) + bloc + m.group(2), src)
    soup = BeautifulSoup(src, "html.parser")
    tr = lambda s: T.get(norm(s))
    if soup.html:
        soup.html["lang"] = lang
    if soup.title and soup.title.string and tr(soup.title.string):
        soup.title.string = tr(soup.title.string)
    for m in soup.find_all("meta"):
        for a, v in META:
            if m.get(a) == v and m.get("content") and tr(m["content"]):
                m["content"] = tr(m["content"])
        if m.get("property") == "og:locale":
            m["content"] = LANGS[lang]["og"]
        if m.get("property") == "og:url":
            m["content"] = page_url(lang, page)
    canon = soup.head.find("link", rel="canonical")
    if canon:
        canon["href"] = page_url(lang, page)
    lst = []
    units(soup.body, lst)
    for u in lst:
        t = tr(inner(u))
        if t:
            u.clear()
            u.append(BeautifulSoup(t, "html.parser"))
    for el in soup.body.find_all(True):
        for a in ATTRS:
            if el.get(a) and tr(el[a]):
                el[a] = tr(el[a])
    for s in soup.find_all("script", type="application/ld+json"):
        def walk(o, k=None):
            if isinstance(o, str):
                if k in ("name", "description", "text"):
                    return T.get(norm(o), o)
                if k in ("url", "item", "@id") and o.startswith(SITE):
                    rest = o[len(SITE):].strip("/")
                    pg = "index.html" if rest == "" else rest + ".html"
                    return page_url(lang, pg) if pg in PAGES else o
                return o
            if isinstance(o, list):
                return [walk(v, k) for v in o]
            if isinstance(o, dict):
                return {kk: walk(v, kk) for kk, v in o.items()}
            return o
        s.string = "\n  " + json.dumps(walk(json.loads(s.string)), ensure_ascii=False, indent=2) + "\n  "
    for s in soup.find_all("script"):
        if not s.get("src") and s.get("type") != "application/ld+json" and s.string:
            s.string = translate_js(s.string, T, lang)
    # Chemins
    for el in soup.find_all(True):
        for a in ("href", "src", "content" if el.name == "meta" and el.get("property") == "og:image" else None):
            if a and el.get(a):
                el[a] = fix_path(el[a], lang)
        for a in ("srcset", "imagesrcset"):
            if el.get(a):
                el[a] = ", ".join(" ".join([fix_path(p.split()[0], lang)] + p.split()[1:]) for p in el[a].split(","))
        if el.get("style") and "url(" in el["style"]:
            el["style"] = re.sub(r"url\((['\"]?)(?!https?:|/|data:)", r"url(\1../", el["style"])
    lang_switch(soup, lang, page)
    alternates(soup, page)
    if page in NOINDEX and not soup.find("meta", attrs={"name": "robots"}):
        soup.head.append(soup.new_tag("meta", attrs={"name": "robots", "content": "noindex"}))
    out = str(soup)
    if not out.lstrip().lower().startswith("<!doctype"):
        out = "<!doctype html>\n" + out
    return out


# ---------------------------------------------------------------- Commandes
def catalogue():
    data = load_data()
    dkeys = []
    data_strings(data, dkeys)
    dset = {norm(k) for k in dkeys}
    keys = [("data.js", k) for k in dkeys]
    for f in JS:
        keys += [(f, k) for k in js_keys(open(os.path.join(ROOT, "js", f), encoding="utf-8").read(), dset)]
    for p in PAGES:
        src = open(os.path.join(ROOT, p), encoding="utf-8").read()
        src = re.sub(r"<!-- seo:debut[\s\S]*?<!-- seo:fin -->", "", src)  # reconstruit à part (prerender_bloc)
        soup = BeautifulSoup(src, "html.parser")
        keys += [(p, k) for k in html_keys(soup)]
    seen, cat = set(), []
    for where, k in keys:
        nk = norm(k)
        if nk and nk not in seen and letters(nk):
            seen.add(nk)
            cat.append({"fr": nk, "ou": where})
    return cat


def load_T(lang):
    """Traductions : i18n/traductions/*.json, chaque entrée « français »: ["english", "español"]."""
    idx = list(LANGS).index(lang)
    T = {}
    d = os.path.join(ROOT, "i18n", "traductions")
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if f.endswith(".json"):
            for k, v in json.load(open(os.path.join(d, f), encoding="utf-8")).items():
                if isinstance(v, list) and len(v) > idx and v[idx]:
                    T[norm(k)] = v[idx]
    return T


SEG_ATTR = re.compile(r'((?:aria-label|placeholder|title|alt|data-label)=")([^"]*)("|$)')


def load_segments(lang):
    """i18n/segments/*.json : morceaux de texte (entre deux balises) -> traduction."""
    idx = list(LANGS).index(lang)
    S = {}
    d = os.path.join(ROOT, "i18n", "segments")
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if f.endswith(".json"):
            for k, v in json.load(open(os.path.join(d, f), encoding="utf-8")).items():
                if isinstance(v, list) and len(v) > idx and v[idx] is not None:
                    S[norm(k)] = v[idx]
    return S


def by_segments(key, S):
    """Traduit un texte morceau par morceau (texte entre balises, attributs). None si rien n'a changé."""
    def seg(t):
        core = t.strip()
        if not core:
            return t
        tr = S.get(norm(core))
        if tr is None:
            return t
        return t[: len(t) - len(t.lstrip())] + tr + t[len(t.rstrip()):]
    parts = []
    for p in re.split(r"(<[^>]*>)", key):
        m = re.search(r"<[^>]*$", p) if not (p.startswith("<") and p.endswith(">")) else None
        if m and m.start() > 0:  # balise ouverte en fin de morceau : on la sépare du texte
            parts += [p[: m.start()], p[m.start():]]
        else:
            parts.append(p)
    out = []
    for p in parts:
        if p.startswith("<") and p.endswith(">"):
            out.append(SEG_ATTR.sub(lambda m: m.group(1) + seg(m.group(2)) + m.group(3), p))
        elif p.startswith("<"):  # balise ouverte en fin de morceau : ses attributs
            out.append(SEG_ATTR.sub(lambda m: m.group(1) + seg(m.group(2)) + m.group(3), p))
        else:
            # morceau qui commence au milieu d'une balise (ex. ' alt="…"> texte')
            if ">" in p and "<" not in p.split(">")[0]:
                head, _, tail = p.partition(">")
                head = SEG_ATTR.sub(lambda m: m.group(1) + seg(m.group(2)) + m.group(3), head)
                out.append(head + ">" + seg(tail))
            else:
                out.append(SEG_ATTR.sub(lambda m: m.group(1) + seg(m.group(2)) + m.group(3), p) if '="' in p else seg(p))
    res = "".join(out)
    return None if res == key else res


def full_T(lang, cat):
    T = load_T(lang)
    S = load_segments(lang)
    for c in cat:
        if c["fr"] not in T:
            t = by_segments(c["fr"], S)
            if t is not None:
                T[c["fr"]] = t
    return T


def french_left(fr, tr):
    """Reste-t-il du français ? (mots accentués ou mots courants français identiques à l'original)"""
    if tr is None:
        return True
    words = set(re.findall(r"[A-Za-zÀ-ÿ']{3,}", re.sub(r"<[^>]*>", " ", fr)))
    left = set(re.findall(r"[A-Za-zÀ-ÿ']{3,}", re.sub(r"<[^>]*>", " ", tr)))
    common = {w for w in words & left if not w[0].isupper()}  # les noms propres restent identiques
    return any(re.search(r"[À-ÿ]", w) for w in common) or len(common & FR_WORDS) > 0


FR_WORDS = {"les", "des", "est", "une", "pour", "avec", "dans", "sur", "vous", "nous", "votre", "vos", "pas", "aux", "par", "plus", "que", "qui", "sont", "jour", "jours", "nuit", "nuits", "maison", "voyageurs", "chambres", "réserver", "avis", "mois"}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "build"
    os.makedirs(os.path.join(ROOT, "i18n"), exist_ok=True)
    cat = catalogue()
    if cmd == "extract":
        json.dump(cat, open(os.path.join(ROOT, "i18n", "catalogue.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        for lang in LANGS:
            T = full_T(lang, cat)
            missing = [c for c in cat if is_french(c["fr"]) and french_left(c["fr"], T.get(c["fr"]))]
            json.dump(missing, open(os.path.join(ROOT, "i18n", f"manquant-{lang}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            print(f"{lang} : {len(missing)} textes encore en français -> i18n/manquant-{lang}.json")
        return
    for lang in LANGS:
        T = full_T(lang, cat)
        d = os.path.join(ROOT, lang)
        os.makedirs(os.path.join(d, "js"), exist_ok=True)
        open(os.path.join(d, "js", "data.js"), "w", encoding="utf-8").write(data_js(T, lang))
        for f in JS:
            open(os.path.join(d, "js", f), "w", encoding="utf-8").write(translate_js(open(os.path.join(ROOT, "js", f), encoding="utf-8").read(), T, lang))
        for p in PAGES:
            open(os.path.join(d, p), "w", encoding="utf-8").write(build_page(p, T, lang))
        missing = sum(1 for c in cat if is_french(c["fr"]) and french_left(c["fr"], T.get(c["fr"])))
        print(f"{lang}/ : {len(PAGES)} pages, {len(JS) + 1} scripts — {missing} textes non traduits")
    # Pages françaises : liens de langue et versions alternatives, insérés sans reformater le fichier
    for p in PAGES:
        path = os.path.join(ROOT, p)
        src = open(path, encoding="utf-8").read()
        open(path, "w", encoding="utf-8").write(fr_links(src, p))
    print("pages françaises : liens de langue à jour")


if __name__ == "__main__":
    main()
