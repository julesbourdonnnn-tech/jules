"""Récupère les informations et les photos des annonces Airbnb des maisons.

Lancé par la GitHub Action « Maisons — photos Airbnb »
(.github/workflows/maisons-airbnb.yml). Pour chaque maison de LISTINGS :
  - télécharge la page de l'annonce,
  - enregistre le détail de l'annonce dans data/airbnb/<maison>.json
    (description, équipements, couchages, règlement, notes, liste des photos),
  - enregistre les avis des voyageurs dans data/airbnb/raw/<maison>-reviews.json,
  - télécharge chaque photo en trois tailles (assets/photos/<maison>/NN-xl.webp,
    NN-md.webp et NN-sm.webp), en retirant les bandes noires des captures d'écran.

Les textes du site sont dans js/data.js : ils reprennent ces fichiers, sans
rien inventer. Si l'annonce change, relance l'Action puis mets js/data.js à jour.
"""
import html as htmlmod
import io
import json
import os
import re
import sys
import time
import urllib.request

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LISTINGS = {
    "lacanau": "662061426615418606",
    "bordeaux": "50226249",
}
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36")
HEADERS = {
    "User-Agent": UA,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.6",
}
IMG_RE = re.compile(r"https://a0\.muscache\.com/im/pictures/[^\"'\s\\?]+\.(?:jpe?g|png|webp)", re.I)


def get(url, binary=False, tries=4):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=40) as r:
                data = r.read()
                return data if binary else data.decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2 ** (i + 1))
    raise RuntimeError(f"{url}: {last}")


def walk(o):
    """Parcourt récursivement un objet JSON."""
    if isinstance(o, dict):
        yield o
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)


def deferred_states(page):
    out = []
    for m in re.finditer(r'<script[^>]*id="data-deferred-state-\d+"[^>]*>(.*?)</script>', page, re.S):
        try:
            out.append(json.loads(htmlmod.unescape(m.group(1))))
        except Exception:  # noqa: BLE001
            pass
    for m in re.finditer(r'<script[^>]*id="data-injector-instances"[^>]*>(.*?)</script>', page, re.S):
        try:
            out.append(json.loads(htmlmod.unescape(m.group(1))))
        except Exception:  # noqa: BLE001
            pass
    return out


DROP = {"__typename", "loggingEventData", "loggingData", "impressionLoggingEventData", "icon", "iconUrl",
        "localizedStringWithTranslationPreference", "source", "categoryConfigs", "experiments",
        "translationButton", "seeAllAmenitiesButton", "seeAllButton", "button", "ctaButton"}


def simplify(o):
    """Allège le JSON d'Airbnb pour qu'il reste lisible (sans perdre de texte)."""
    if isinstance(o, dict):
        if isinstance(o.get("localizedString"), str):
            return o["localizedString"]
        r = {k: simplify(v) for k, v in o.items() if k not in DROP}
        return {k: v for k, v in r.items() if v not in (None, [], {}, "")}
    if isinstance(o, list):
        return [v for v in (simplify(x) for x in o) if v not in (None, [], {}, "")]
    return o


def clean_url(u):
    return u.split("?")[0]


def extract(page, listing_id):
    states = deferred_states(page)
    info = {"id": listing_id, "url": f"https://www.airbnb.fr/rooms/{listing_id}"}

    # Métadonnées de la page (toujours présentes, même si le JSON change)
    for prop in ("og:title", "og:description", "og:image"):
        m = re.search(r'<meta[^>]+property="%s"[^>]+content="([^"]*)"' % re.escape(prop), page)
        if m:
            info[prop.replace("og:", "og_")] = htmlmod.unescape(m.group(1))
    m = re.search(r"<title>(.*?)</title>", page, re.S)
    if m:
        info["page_title"] = htmlmod.unescape(m.group(1)).strip()
    m = re.search(r'<meta[^>]+name="description"[^>]+content="([^"]*)"', page)
    if m:
        info["meta_description"] = htmlmod.unescape(m.group(1))

    # Photos, dans l'ordre de l'annonce, avec leur légende éventuelle
    photos, seen = [], set()
    for d in (x for s in states for x in walk(s)):
        if isinstance(d.get("mediaItems"), list):
            for it in d["mediaItems"]:
                if not isinstance(it, dict):
                    continue
                u = it.get("baseUrl") or it.get("url")
                if not u or "muscache" not in u:
                    continue
                u = clean_url(u)
                if u in seen:
                    continue
                seen.add(u)
                photos.append({
                    "src": u,
                    "caption": it.get("imageMetadata", {}).get("caption") if isinstance(it.get("imageMetadata"), dict) else None,
                    "accessibility": it.get("accessibilityLabel"),
                    "orientation": it.get("orientation"),
                })
    if not photos:  # Plan B : toutes les images de l'annonce dans la page
        for u in IMG_RE.findall(page):
            u = clean_url(u)
            if u in seen or "/user/" in u or "/User" in u or "AirbnbPlatformAssets" in u:
                continue
            seen.add(u)
            photos.append({"src": u, "caption": None, "accessibility": None, "orientation": None})
    info["photos"] = photos

    # Détail de l'annonce (description, équipements, couchages, règlement,
    # emplacement, notes) : c'est la source des textes de js/data.js.
    keep = ("title", "descriptions", "highlights", "overview", "sleepingArrangements", "amenities",
            "rules", "safetyAndProperty", "location", "quality", "hostInfo", "accessibilityFeatures")
    for d in (x for s in states for x in walk(s)):
        if isinstance(d.get("pdpPresentation"), dict):
            pp = d["pdpPresentation"]
            info["listing"] = {k: simplify(pp.get(k)) for k in keep if pp.get(k)}
            break
    return info


API_KEY = "d306zoyjsyarp7ifhu67rjxn52tv0t20"  # clé publique du site web Airbnb


def api_get(url):
    req = urllib.request.Request(url, headers={**HEADERS, "Accept": "application/json",
                                               "X-Airbnb-API-Key": API_KEY,
                                               "Referer": "https://www.airbnb.fr/"})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


KNOWN_HASHES = {  # identifiants connus, utilisés si la recherche échoue
    "StaysPdpReviewsQuery": ["dec1c8061483e78373602047450322fd474e79ba9afa8d3dbbc27f504030f91d"],
}


def find_hash(js, name):
    for pat in (r'name:"%s",type:"query",operationId:"([0-9a-f]{64})"',
                r'"%s"[^{}]{0,400}?operationId["\']?\s*:\s*["\']([0-9a-f]{64})',
                r'operationId["\']?\s*:\s*["\']([0-9a-f]{64})["\'][^{}]{0,400}?"%s"'):
        m = re.search(pat % name, js)
        if m:
            return m.group(1)
    return None


def operation_hashes(page):
    """Trouve dans les scripts du site les identifiants des requêtes GraphQL.

    Parcourt les scripts de la page, puis les morceaux de scripts qu'ils
    chargent à la demande (où se trouve souvent la requête des avis)."""
    wanted = ("StaysPdpReviewsQuery",)
    found = {}
    base = "https://a0.muscache.com/airbnb/static/"
    queue = list(dict.fromkeys(re.findall(r'(https://a0\.muscache\.com/airbnb/static/packages/web/[^"\'\s]+?\.js)', page)))
    seen = set()
    while queue and len(seen) < 600 and len(found) < len(wanted):
        u = queue.pop(0)
        if u in seen:
            continue
        seen.add(u)
        try:
            js = get(u, tries=2)
        except Exception:  # noqa: BLE001
            continue
        for name in wanted:
            if name not in found and name in js:
                h = find_hash(js, name)
                if h:
                    found[name] = h
        for rel in re.findall(r'["\'/]((?:packages/web/)[\w./\-]+?\.js)["\']', js):
            full = base + rel
            if full not in seen:
                queue.append(full)
    print(f"   {len(seen)} scripts parcourus")
    for name, hs in KNOWN_HASHES.items():
        found.setdefault(name, hs[0])
    return found


def fetch_reviews(page, lid, key):
    """Avis des voyageurs, via l'API du site (la page ne contient que la note)."""
    import base64
    import urllib.parse
    out = {}
    hashes = operation_hashes(page)
    print(f"   requêtes trouvées : {sorted(hashes)}")
    gid = base64.b64encode(f"StayListing:{lid}".encode()).decode()
    raw_dir = os.path.join(ROOT, "data", "airbnb", "raw")
    if "StaysPdpReviewsQuery" in hashes:
        reviews = []
        for offset in range(0, 120, 24):
            variables = {"id": gid, "pdpReviewsRequest": {
                "fieldSelector": "for_p3_translation_only", "forPreview": False, "limit": 24,
                "offset": str(offset), "showingTranslationButton": False, "first": 24,
                "sortingPreference": "MOST_RECENT"}}
            q = urllib.parse.urlencode({
                "operationName": "StaysPdpReviewsQuery", "locale": "fr", "currency": "EUR",
                "variables": json.dumps(variables, separators=(",", ":")),
                "extensions": json.dumps({"persistedQuery": {"version": 1, "sha256Hash": hashes["StaysPdpReviewsQuery"]}}, separators=(",", ":"))})
            try:
                data = api_get(f"https://www.airbnb.fr/api/v3/StaysPdpReviewsQuery/{hashes['StaysPdpReviewsQuery']}?{q}")
            except Exception as e:  # noqa: BLE001
                print(f"   StaysPdpReviewsQuery : {e}")
                break
            batch = [d for d in walk(data) if isinstance(d, dict) and "comments" in d and "reviewer" in d]
            if not batch and offset == 0:
                with open(os.path.join(raw_dir, f"{key}-reviews-debug.json"), "w") as f:
                    json.dump(data, f, ensure_ascii=False)
            reviews.extend(batch)
            if len(batch) < 24:
                break
        with open(os.path.join(raw_dir, f"{key}-reviews.json"), "w") as f:
            json.dump(reviews, f, ensure_ascii=False)
        out["reviews"] = len(reviews)
        print(f"   {len(reviews)} avis")
    return out


def trim_bars(im):
    """Retire les bandes noires des captures d'écran de téléphone (haut et bas).

    Ne touche qu'aux images très allongées (format écran de téléphone), pour ne
    jamais rogner le ciel d'une photo de nuit."""
    if im.height / im.width < 1.6:
        return im
    g = im.convert("L").resize((200, im.height))
    px = g.load()

    def content(y):  # ligne d'image (et non bande noire ou barre du téléphone)
        return sum(1 for x in range(200) if px[x, y] > 18) >= 120

    top = 0
    while top < im.height // 3 and not content(top):
        top += 1
    bottom = im.height
    while bottom > im.height * 2 // 3 and not content(bottom - 1):
        bottom -= 1
    if top > 8 or im.height - bottom > 8:
        return im.crop((0, top + 4 if top > 8 else 0, im.width, bottom - 4 if im.height - bottom > 8 else im.height))
    return im


def save_photo(src, base):
    raw = get(src + "?im_w=2560", binary=True)
    im = trim_bars(Image.open(io.BytesIO(raw)).convert("RGB"))
    for suffix, width, q in (("xl", 2200, 80), ("md", 1100, 78), ("sm", 560, 72)):
        w = min(width, im.width)
        h = round(im.height * w / im.width)
        im.resize((w, h), Image.LANCZOS).save(f"{base}-{suffix}.webp", "WEBP", quality=q, method=6)
    return {"w": im.width, "h": im.height}


def main():
    only = [s for s in os.environ.get("ONLY", "").split(",") if s.strip()]
    ok = True
    for key, lid in LISTINGS.items():
        if only and key not in only:
            continue
        print(f"== {key} ({lid})")
        try:
            page = get(f"https://www.airbnb.fr/rooms/{lid}")
        except Exception as e:  # noqa: BLE001
            print(f"!! page inaccessible : {e}")
            ok = False
            continue
        os.makedirs(os.path.join(ROOT, "data", "airbnb", "raw"), exist_ok=True)
        with open(os.path.join(ROOT, "data", "airbnb", "raw", f"{key}.html"), "w") as f:
            f.write(page)
        info = extract(page, lid)
        try:
            info["api"] = fetch_reviews(page, lid, key)
        except Exception as e:  # noqa: BLE001
            print(f"   avis indisponibles : {e}")
        print(f"   {len(info['photos'])} photos, détail de l'annonce : {'oui' if info.get('listing') else 'non'}")
        if not info["photos"] and not info.get("listing"):
            # Page vide (protection anti-robots) : on garde un extrait pour diagnostic
            with open(os.path.join(ROOT, "data", "airbnb", f"{key}-debug.html"), "w") as f:
                f.write(page[:200000])
            ok = False
        outdir = os.path.join(ROOT, "assets", "photos", key)
        os.makedirs(outdir, exist_ok=True)
        for i, p in enumerate(info["photos"], 1):
            base = os.path.join(outdir, f"{i:02d}")
            if os.path.exists(base + "-xl.webp") and not os.environ.get("FORCE_PHOTOS"):
                with Image.open(base + "-xl.webp") as im:
                    p["file"] = f"assets/photos/{key}/{i:02d}"
                    p["w"], p["h"] = im.size
                continue
            try:
                p.update(save_photo(p["src"], base))
                p["file"] = f"assets/photos/{key}/{i:02d}"
            except Exception as e:  # noqa: BLE001
                print(f"   photo {i} : {e}")
        with open(os.path.join(ROOT, "data", "airbnb", f"{key}.json"), "w") as f:
            json.dump(info, f, ensure_ascii=False, indent=1)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
