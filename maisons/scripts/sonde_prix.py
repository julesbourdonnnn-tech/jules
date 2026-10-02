"""Sonde temporaire (2) : interroge la requête de prix d'Airbnb."""
import json, os, re, sys, base64, urllib.parse, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
from airbnb import get, HEADERS, API_KEY, ROOT, LISTINGS

OUT = os.path.join(ROOT, "data", "airbnb", "sonde")
os.makedirs(OUT, exist_ok=True)
log = []
route = "https://a0.muscache.com/airbnb/static/packages/web/fr/frontend/gp-stays-pdp-route/routes/PdpPlatformRoute.2be632ebc1.js"
page = get(f"https://www.airbnb.fr/rooms/{LISTINGS['bordeaux']}")
cands = [u for u in re.findall(r'(https://a0\.muscache\.com/[^"\'\s]+?PdpPlatformRoute[^"\'\s]*?\.js)', page)]
if cands: route = cands[0]
js = get(route)
open(f"{OUT}/route.js", "w").write(js)
ops = dict(re.findall(r"name:'(\w+)',type:'query',operationId:'([0-9a-f]{64})'", js))
log.append(f"opérations : {sorted(ops)}")
# Contexte d'utilisation de la requête de prix (variables)
for m in re.finditer(r"StaysPdpBookItQuery|BookItQuery", js):
    pass
idx = [m.start() for m in re.finditer(r"pdpSectionsRequest", js)][:6]
for i in idx: log.append("CTX: " + js[max(0, i - 250): i + 400].replace("\n", " "))

def call(op, variables):
    h = ops[op]
    q = urllib.parse.urlencode({"operationName": op, "locale": "fr", "currency": "EUR",
        "variables": json.dumps(variables, separators=(",", ":")),
        "extensions": json.dumps({"persistedQuery": {"version": 1, "sha256Hash": h}}, separators=(",", ":"))})
    req = urllib.request.Request(f"https://www.airbnb.fr/api/v3/{op}/{h}?{q}", headers={**HEADERS, "Accept": "application/json", "X-Airbnb-API-Key": API_KEY, "Referer": "https://www.airbnb.fr/", "X-Airbnb-GraphQL-Platform": "web", "X-Airbnb-GraphQL-Platform-Client": "minimalist-niobe"})
    try:
        with urllib.request.urlopen(req, timeout=40) as r: return json.loads(r.read().decode())
    except urllib.error.HTTPError as e: return {"http": e.code, "body": e.read().decode()[:500]}

lid = LISTINGS["bordeaux"]
gid = base64.b64encode(f"StayListing:{lid}".encode()).decode()
dgid = base64.b64encode(f"DemandStayListing:{lid}".encode()).decode()
req = {"adults": "2", "categoryTag": None, "causeId": None, "children": None, "disasterId": None, "discountedGuestFeeVersion": None,
       "displayExtensions": None, "federatedSearchId": None, "forceBoostPriorityMessageType": None, "infants": None, "interactionType": None,
       "layouts": ["SIDEBAR", "SINGLE_COLUMN"], "pets": 0, "pdpTypeOverride": None, "photoId": None, "preview": False,
       "previousStateCheckIn": None, "previousStateCheckOut": None, "priceDropSource": None, "privateBooking": False, "promotionUuid": None,
       "relaxedAmenityIds": None, "searchId": None, "selectedCancellationPolicyId": None, "selectedRatePlanId": None, "splitStays": None,
       "staysBookingMigrationEnabled": False, "translateUgc": None, "useNewSectionWrapperApi": False,
       "sectionIds": None, "checkIn": "2027-03-12", "checkOut": "2027-03-14", "p3ImpressionId": "p3_1_x"}
tries = []
for op in ("StaysPdpBookItQuery", "StaysPdpSections"):
    if op not in ops: continue
    for name, v in (("A", {"id": gid, "pdpSectionsRequest": req}), ("B", {"id": dgid, "pdpSectionsRequest": req}),
                    ("C", {"id": gid, "demandStayListingId": dgid, "pdpSectionsRequest": req, "includeGpReviewsFragment": False, "includePdpMigrationReviewsFragment": False, "includePdpMigrationHighlightsFragment": False}),
                    ("D", {"id": dgid, "pdpSectionsRequest": dict(req, sectionIds=["BOOK_IT_SIDEBAR"])})):
        d = call(op, v)
        txt = json.dumps(d, ensure_ascii=False)
        prices = re.findall(r'"(?:price|qualifier|discountedPrice|originalPrice|accessibilityLabel)"\s*:\s*"([^"]*€[^"]*)"', txt)[:10]
        log.append(f"{op} {name}: erreurs={json.dumps(d.get('errors') if isinstance(d, dict) else None, ensure_ascii=False)[:300]} http={d.get('http') if isinstance(d, dict) else ''} prix={prices}")
        if prices: json.dump(d, open(f"{OUT}/prix-{op}-{name}.json", "w"), ensure_ascii=False)
open(f"{OUT}/log.txt", "w").write("\n".join(log))
print("\n".join(log))
