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

from airbnb import find_hash
import re as _re

def find_ops(page, names):
    found = {}
    base = "https://a0.muscache.com/airbnb/static/"
    queue = list(dict.fromkeys(_re.findall(r'(https://a0\.muscache\.com/airbnb/static/packages/web/[^"\'\s]+?\.js)', page)))
    seen = set()
    while queue and len(seen) < 700 and len(found) < len(names):
        u = queue.pop(0)
        if u in seen: continue
        seen.add(u)
        try: js = get(u, tries=2)
        except Exception: continue
        for n in names:
            if n not in found and n in js:
                h = find_hash(js, n)
                if h: found[n] = h
        for rel in _re.findall(r'["\'/]((?:packages/web/)[\w./\-]+?\.js)["\']', js):
            if base + rel not in seen: queue.append(base + rel)
    return found

key, lid = "bordeaux", LISTINGS["bordeaux"]
page = get(f"https://www.airbnb.fr/rooms/{lid}")
ops = find_ops(page, ["StaysPdpSections", "StaysPdpBookItQuery", "PdpBookItQuery", "StaysCheckoutQuery", "stayCheckout"])
log.append(f"opérations trouvées : {ops}")
gid = base64.b64encode(f"StayListing:{lid}".encode()).decode()
base_req = {"adults": "2", "bypassTargetings": False, "categoryTag": None, "causeId": None, "children": None,
    "disasterId": None, "discountedGuestFeeVersion": None, "displayExtensions": None, "federatedSearchId": None,
    "forceBoostPriorityMessageType": None, "infants": None, "interactionType": None, "layouts": ["SIDEBAR", "SINGLE_COLUMN"],
    "pets": 0, "pdpTypeOverride": None, "photoId": None, "preview": False, "previousStateCheckIn": None,
    "previousStateCheckOut": None, "priceDropSource": None, "privateBooking": False, "promotionUuid": None,
    "relaxedAmenityIds": None, "searchId": None, "selectedCancellationPolicyId": None, "selectedRatePlanId": None,
    "splitStays": None, "staysBookingMigrationEnabled": False, "translateUgc": None, "useNewSectionWrapperApi": False,
    "sectionIds": ["BOOK_IT_SIDEBAR", "BOOK_IT_FLOATING_FOOTER"], "checkIn": "2027-03-12", "checkOut": "2027-03-14"}
if "StaysPdpSections" in ops:
    h = ops["StaysPdpSections"]
    for name, variables in (
        ("v1", {"id": gid, "pdpSectionsRequest": base_req}),
        ("v2", {"id": gid, "pdpSectionsRequest": {**base_req, "sectionIds": None}}),
        ("v3", {"id": gid, "demandStayListingId": gid, "pdpSectionsRequest": base_req}),
    ):
        q = urllib.parse.urlencode({"operationName": "StaysPdpSections", "locale": "fr", "currency": "EUR",
            "variables": json.dumps(variables, separators=(",", ":")),
            "extensions": json.dumps({"persistedQuery": {"version": 1, "sha256Hash": h}}, separators=(",", ":"))})
        try:
            data = api(f"https://www.airbnb.fr/api/v3/StaysPdpSections/{h}?{q}")
            json.dump(data, open(f"{OUT}/prix-{name}.json", "w"), ensure_ascii=False)
            prices = [d for d in walk(data) if isinstance(d, dict) and d.get("__typename", "").endswith("DisplayPriceLine")][:5]
            log.append(f"{name}: erreurs={json.dumps(data.get('errors'))[:300]} prix={json.dumps(prices, ensure_ascii=False)[:600]}")
        except Exception as e:
            log.append(f"{name}: erreur {e}")

open(f"{OUT}/log2.txt", "w").write("\n".join(log))
print("\n".join(log))
