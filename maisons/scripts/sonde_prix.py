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
flags = sorted(set(re.findall(r"include[A-Z]\w+", js)))
ci, co = "2027-03-12", "2027-03-14"
psr = {"adults": "2", "amenityFilters": None, "bypassTargetings": False, "categoryTag": None, "causeId": None, "children": None,
       "disasterId": None, "discountedGuestFeeVersion": None, "federatedSearchId": None, "forceBoostPriorityMessageType": None,
       "guestAges": None, "hostPreview": False, "infants": None, "interactionType": None, "layouts": ["SIDEBAR", "SINGLE_COLUMN"],
       "omniPageId": None, "omniVersionId": None, "pets": 0, "pdpTypeOverride": None, "photoId": None, "preview": False,
       "previousStateCheckIn": None, "previousStateCheckOut": None, "priceDropSource": None, "partner": None, "partnerProgram": None,
       "directBookingParams": None, "privateBooking": False, "promotionUuid": None, "relaxedAmenityIds": None, "searchId": None,
       "selectedCancellationPolicyId": None, "selectedRatePlanId": None, "splitStays": None, "staysBookingMigrationEnabled": False,
       "translateUgc": None, "useNewSectionWrapperApi": False, "sectionIds": None, "checkIn": ci, "checkOut": co, "p3ImpressionId": "p3_1700000000_P3abcdef"}
base = {"id": gid, "demandStayListingId": dgid, "pdpSectionsRequest": psr, "categoryTag": None, "federatedSearchId": None,
        "federatedSearchSessionId": None, "p3ImpressionId": "p3_1700000000_P3abcdef", "photoId": None, "amenityIds": None, "causeId": None,
        "dateRange": {"startDate": ci, "endDate": co}, "guestCounts": {"numberOfAdults": 2}, "numberOfChildren": None,
        "numberOfInfants": None, "numberOfPets": None}
for f in flags:
    if f in ("includeGp", "includePdpMigration"): continue
    base[f] = f.startswith("includeGp")
log.append("drapeaux : " + ", ".join(f"{f}={base.get(f)}" for f in flags))
for op in ("StaysPdpBookItQuery", "StaysPdpSections"):
    for name, v in (("A", base), ("B", dict(base, pdpSectionsRequest=dict(psr, sectionIds=["BOOK_IT_SIDEBAR", "BOOK_IT_FLOATING_FOOTER"])))):
        d = call(op, v)
        txt = json.dumps(d, ensure_ascii=False)
        prices = re.findall(r'"(?:price|qualifier|discountedPrice|originalPrice|accessibilityLabel|description|title)"\s*:\s*"([^"]*€[^"]*)"', txt)[:14]
        log.append(f"{op} {name}: erreurs={json.dumps(d.get('errors') if isinstance(d, dict) else None, ensure_ascii=False)[:400]} http={d.get('http') if isinstance(d, dict) else ''} taille={len(txt)} prix={prices}")
        json.dump(d, open(f"{OUT}/rep-{op}-{name}.json", "w"), ensure_ascii=False)
open(f"{OUT}/log.txt", "w").write("\n".join(log))
print("\n".join(log))
