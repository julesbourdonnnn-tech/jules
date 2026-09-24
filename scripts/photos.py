#!/usr/bin/env python3
"""
Récupération des photos des hôtels (exécuté par la GitHub Action « Photos »).

1. REPÉRAGE : pour chaque hôtel de data/photo-sources.json absent du rapport,
   visite ses pages (et quelques pages « galerie » / « chambres » du même site),
   repère les grandes photos et produit une planche-contact numérotée
   dans _review/<id>.jpg. Les URLs candidates sont notées dans data/photo-report.json.

2. TÉLÉCHARGEMENT : pour chaque hôtel de data/photo-selection.json, télécharge
   les photos choisies (numéros de la planche-contact), les recadre/optimise et
   les enregistre dans assets/hotels/<id>/<n>.jpg (+ version légère -sm.jpg).

Le script est idempotent : il ne refait que ce qui manque ou a changé.
"""
import hashlib
import html
import io
import json
import os
import re
import sys
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
import urllib.request

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "data", "photo-sources.json")
REPORT = os.path.join(ROOT, "data", "photo-report.json")
SELECTION = os.path.join(ROOT, "data", "photo-selection.json")
REVIEW_DIR = os.path.join(ROOT, "_review")
ASSETS_DIR = os.path.join(ROOT, "assets", "hotels")

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
SKIP = re.compile(r"logo|icon|favicon|picto|sprite|avatar|flag|drapeau|placeholder|loader|"
                  r"badge|label|tripadvisor|trustpilot|google|facebook|instagram|payment|"
                  r"map[-_.]|carte[-_.]|signature|qr|\.svg|\.gif", re.I)
GALLERY_LINK = re.compile(r"galer|gallery|photo|chambre|room|suite|cabane|cabin|lodge|"
                          r"hebergement|accommodation|bulle|igloo|decouvr|discover", re.I)
MAX_CANDIDATES = 24
TIME_BUDGET = 25 * 60  # secondes : au-delà, on enregistre ce qu'on a
START = time.time()
LOCK = threading.Lock()


def load(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)


def get(url, timeout=15):
    req = urllib.request.Request(url, headers={
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,image/avif,image/webp,image/*,*/*;q=0.8",
        "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.8",
    })
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.geturl(), r.headers.get("Content-Type", ""), r.read()


def page_text(doc):
    doc = re.sub(r"(?is)<(script|style|noscript|svg)[^>]*>.*?</\1>", " ", doc)
    doc = re.sub(r"(?s)<[^>]+>", " ", doc)
    return re.sub(r"\s+", " ", html.unescape(doc)).strip()


def meta(doc, name):
    m = re.search(r'<meta[^>]+(?:property|name)=["\']%s["\'][^>]*content=["\']([^"\']+)' % re.escape(name), doc, re.I) \
        or re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]*(?:property|name)=["\']%s["\']' % re.escape(name), doc, re.I)
    return html.unescape(m.group(1)).strip() if m else ""


def best_from_srcset(srcset):
    best, best_w = None, -1
    for part in srcset.split(","):
        bits = part.strip().split()
        if not bits:
            continue
        w = 0
        if len(bits) > 1 and bits[1].endswith("w"):
            try:
                w = int(bits[1][:-1])
            except ValueError:
                pass
        if w >= best_w:
            best, best_w = bits[0], w
    return best


def upscale_cdn(url):
    """Demande la version grande des images servies par des CDN connus."""
    url = re.sub(r"(static\.wixstatic\.com/media/[^/]+)/v1/.*$", r"\1", url)
    url = re.sub(r"([?&])(w|width)=\d+", r"\1\2=2000", url)
    url = re.sub(r"-\d{2,4}x\d{2,4}(\.(jpe?g|png|webp))", r"\1", url)  # WordPress
    return url


def extract_images(doc, base):
    found = []
    for key in ("og:image", "og:image:secure_url", "twitter:image"):
        v = meta(doc, key)
        if v:
            found.append(v)
    for m in re.finditer(r'"image"\s*:\s*(\[[^\]]*\]|"[^"]+")', doc):
        found += re.findall(r'"(https?://[^"]+)"', m.group(1))
    for tag in re.finditer(r"<(?:img|source)\b[^>]*>", doc, re.I):
        t = tag.group(0)
        for attr in ("data-srcset", "srcset", "data-lazy-srcset"):
            m = re.search(r'\s%s=["\']([^"\']+)' % attr, t, re.I)
            if m:
                b = best_from_srcset(html.unescape(m.group(1)))
                if b:
                    found.append(b)
        for attr in ("data-src", "data-lazy-src", "data-original", "data-bg", "data-image", "src"):
            m = re.search(r'\s%s=["\']([^"\']+)' % attr, t, re.I)
            if m:
                found.append(html.unescape(m.group(1)))
    found += re.findall(r"url\(\s*['\"]?([^'\")]+\.(?:jpe?g|png|webp)[^'\")]*)", doc, re.I)
    found += re.findall(r"https?:\\?/\\?/[^\s\"'<>()]+?\.(?:jpe?g|png|webp)(?:\?[^\s\"'<>()]*)?", doc, re.I)

    out, seen = [], set()
    for u in found:
        u = u.replace("\\/", "/").strip()
        if u.startswith("data:") or not u:
            continue
        u = upscale_cdn(urllib.parse.urljoin(base, u))
        if not u.startswith("http") or SKIP.search(u):
            continue
        key = re.sub(r"\?.*$", "", u)
        if key in seen:
            continue
        seen.add(key)
        out.append(u)
    return out


def gallery_links(doc, base, limit=3):
    host = urllib.parse.urlparse(base).netloc
    links = []
    for m in re.finditer(r'<a\b[^>]*href=["\']([^"\'#]+)', doc, re.I):
        u = urllib.parse.urljoin(base, html.unescape(m.group(1)))
        if urllib.parse.urlparse(u).netloc == host and GALLERY_LINK.search(u) and u not in links and u != base:
            links.append(u)
    return links[:limit]


def open_image(data):
    im = Image.open(io.BytesIO(data))
    im = ImageOps.exif_transpose(im)
    return im.convert("RGB")


def scan(hotel):
    entry = {"id": hotel["id"], "sources": list(hotel["pages"]), "pages": [], "candidates": []}
    urls, visited = list(hotel["pages"]), set()
    first_domain_pages = 0
    while urls and len(visited) < 7:
        url = urls.pop(0)
        if url in visited:
            continue
        visited.add(url)
        try:
            final, ctype, body = get(url)
            doc = body.decode("utf-8", "replace")
        except Exception as e:  # noqa: BLE001
            entry["pages"].append({"url": url, "error": str(e)[:200]})
            continue
        entry["pages"].append({
            "url": url, "final": final,
            "title": re.sub(r"\s+", " ", html.unescape((re.search(r"(?is)<title[^>]*>(.*?)</title>", doc) or [None, ""])[1])).strip()[:200],
            "description": meta(doc, "description") or meta(doc, "og:description"),
            "text": page_text(doc)[:3000],
        })
        entry["candidates"] += [u for u in extract_images(doc, final) if u not in entry["candidates"]]
        if first_domain_pages < 2:
            urls += gallery_links(doc, final)
            first_domain_pages += 1

    # Téléchargement des candidates pour la planche-contact
    def download(u):
        try:
            _, _, data = get(u)
            if len(data) < 25_000:
                return None
            return u, hashlib.md5(data).hexdigest(), open_image(data)
        except Exception:  # noqa: BLE001
            return None

    with ThreadPoolExecutor(6) as pool:
        results = list(pool.map(download, entry["candidates"][:60]))

    thumbs, kept, hashes = [], [], set()
    for res in results:
        if not res or len(kept) >= MAX_CANDIDATES:
            continue
        u, h, im = res
        if h in hashes:
            continue
        w, hgt = im.size
        if w < 800 or hgt < 450 or not (0.5 <= w / hgt <= 2.6):
            continue
        hashes.add(h)
        kept.append({"n": len(kept) + 1, "url": u, "w": w, "h": hgt})
        thumbs.append(ImageOps.fit(im, (360, 240)))
    entry["candidates"] = kept

    if thumbs:
        cols = 4
        rows = (len(thumbs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * 370 + 10, rows * 270 + 10), "white")
        draw = ImageDraw.Draw(sheet)
        try:
            font = ImageFont.load_default(size=28)
        except TypeError:
            font = ImageFont.load_default()
        for i, (t, c) in enumerate(zip(thumbs, kept)):
            x, y = 10 + (i % cols) * 370, 10 + (i // cols) * 270
            sheet.paste(t, (x, y))
            draw.rectangle([x, y, x + 150, y + 36], fill="black")
            draw.text((x + 8, y + 3), f"#{c['n']} {c['w']}px", fill="yellow", font=font)
        os.makedirs(REVIEW_DIR, exist_ok=True)
        sheet.save(os.path.join(REVIEW_DIR, f"{hotel['id']}.jpg"), quality=72)
    return entry


def fetch_selected(hid, picks, report):
    cands = {c["n"]: c for c in report.get(hid, {}).get("candidates", [])}
    extra = {}
    out_dir = os.path.join(ASSETS_DIR, hid)
    os.makedirs(out_dir, exist_ok=True)
    for f in os.listdir(out_dir):
        os.remove(os.path.join(out_dir, f))
    saved = []
    for i, pick in enumerate(picks, 1):
        url = pick if isinstance(pick, str) else cands.get(pick, {}).get("url")
        if not url:
            print(f"  ! {hid}: photo {pick} introuvable")
            continue
        try:
            _, _, data = get(url)
            im = open_image(data)
        except Exception as e:  # noqa: BLE001
            print(f"  ! {hid}: {url} -> {e}")
            continue
        big = im.copy()
        big.thumbnail((1800, 1800))
        big.save(os.path.join(out_dir, f"{i}.jpg"), quality=80, optimize=True, progressive=True)
        small = ImageOps.fit(im, (900, 675)) if im.width / im.height > 1.1 else ImageOps.fit(im, (720, 900))
        small.save(os.path.join(out_dir, f"{i}-sm.jpg"), quality=76, optimize=True, progressive=True)
        saved.append(f"assets/hotels/{hid}/{i}.jpg")
        extra[str(i)] = url
    save(os.path.join(out_dir, "source.json"), extra)
    return saved


def visited_sources(entry, hotel):
    """Pages sources utilisées lors du dernier repérage (les premières pages visitées)."""
    if "sources" in entry:
        return entry["sources"]
    return [p["url"] for p in entry.get("pages", [])][:len(hotel["pages"])]


def main():
    sources = load(SOURCES, [])
    report = load(REPORT, {})
    only = set(filter(None, os.environ.get("ONLY", "").split(",")))

    # À (re)faire : hôtels nouveaux, demandés explicitement, ou dont les pages sources ont changé
    todo = [h for h in sources
            if h["id"] not in report or h["id"] in only
            or visited_sources(report[h["id"]], h) != h["pages"]]

    def work(hotel):
        if time.time() - START > TIME_BUDGET:
            print(f"Temps écoulé, {hotel['id']} sera traité au prochain passage")
            return
        entry = scan(hotel)
        with LOCK:
            report[hotel["id"]] = entry
            save(REPORT, report)
        print(f"Repérage : {hotel['id']} -> {len(entry['candidates'])} photos candidates", flush=True)

    with ThreadPoolExecutor(8) as pool:
        list(pool.map(work, todo))

    selection = load(SELECTION, {})
    done = load(os.path.join(ASSETS_DIR, "_done.json"), {})
    for hid, picks in selection.items():
        if done.get(hid) == picks and os.path.isdir(os.path.join(ASSETS_DIR, hid)):
            continue
        print(f"Téléchargement : {hid} {picks}")
        saved = fetch_selected(hid, picks, report)
        print(f"  {len(saved)} photos enregistrées")
        done[hid] = picks
        save(os.path.join(ASSETS_DIR, "_done.json"), done)


if __name__ == "__main__":
    sys.exit(main())
