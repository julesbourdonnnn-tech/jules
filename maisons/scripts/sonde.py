"""Sonde temporaire : vérifie quelles données de prix et de disponibilité
Airbnb renvoie pour les deux annonces. Résultats dans data/airbnb/sonde/."""
import json, os, re, sys, html as H, urllib.request, urllib.parse, base64
sys.path.insert(0, os.path.dirname(__file__))
from airbnb import get, HEADERS, API_KEY, walk, LISTINGS, ROOT

OUT = os.path.join(ROOT, "data", "airbnb", "sonde")
os.makedirs(OUT, exist_ok=True)
log = []

def api(url):
    req = urllib.request.Request(url, headers={**HEADERS, "Accept": "application/json", "X-Airbnb-API-Key": API_KEY, "Referer": "https://www.airbnb.fr/"})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read().decode())

for key, lid in LISTINGS.items():
    # 1. Page avec dates : le bloc de réservation contient-il un prix ?
    for ci, co in (("2027-06-12", "2027-06-19"), ("2026-11-14", "2026-11-16")):
        try:
            page = get(f"https://www.airbnb.fr/rooms/{lid}?check_in={ci}&check_out={co}&adults=2")
            m = re.search(r'id="data-deferred-state-0"[^>]*>(.*?)</script>', page, re.S)
            st = json.loads(H.unescape(m.group(1))) if m else {}
            found = []
            for d in walk(st):
                if isinstance(d, dict) and d.get("sectionId") in ("BOOK_IT_SIDEBAR", "BOOK_IT_FLOATING_FOOTER", "BOOK_IT_NAV") and d.get("section"):
                    found.append(d)
            prices = re.findall(r'[0-9][0-9\s  .,]*\s?€[^"<]{0,60}', page)[:40]
            json.dump({"sections": found, "price_strings": prices}, open(f"{OUT}/{key}-page-{ci}.json", "w"), ensure_ascii=False, indent=1)
            log.append(f"{key} page {ci}: {len(found)} sections, {len(prices)} prix trouvés : {prices[:6]}")
        except Exception as e:
            log.append(f"{key} page {ci}: erreur {e}")
    # 2. Calendrier de disponibilités
    for h in ("8f08e03c7bd16fcad3c92a3592c19a8b559a0d0855a84028d1163d4733ed9ade",):
        v = {"request": {"count": 12, "listingId": lid, "month": 10, "year": 2026}}
        q = urllib.parse.urlencode({"operationName": "PdpAvailabilityCalendar", "locale": "fr", "currency": "EUR",
                                    "variables": json.dumps(v, separators=(",", ":")),
                                    "extensions": json.dumps({"persistedQuery": {"version": 1, "sha256Hash": h}}, separators=(",", ":"))})
        try:
            data = api(f"https://www.airbnb.fr/api/v3/PdpAvailabilityCalendar/{h}?{q}")
            json.dump(data, open(f"{OUT}/{key}-calendar.json", "w"), ensure_ascii=False)
            days = [d for d in walk(data) if isinstance(d, dict) and "calendarDate" in d]
            log.append(f"{key} calendrier: {len(days)} jours, exemple {json.dumps(days[:2], ensure_ascii=False)[:400]}")
        except Exception as e:
            log.append(f"{key} calendrier: erreur {e}")

open(f"{OUT}/log.txt", "w").write("\n".join(log))
print("\n".join(log))
