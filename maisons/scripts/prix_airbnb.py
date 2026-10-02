"""Relève les prix Airbnb des deux maisons pour les 12 prochains mois.

Pour chaque quinzaine, on demande à Airbnb le prix de deux séjours qui
commencent le même jour (par exemple 3 et 5 nuits). La différence donne le
prix d'une nuit à cette période ; le reste, les frais fixes du séjour (ménage
et frais répartis par Airbnb). La ligne « Taxes » donne le taux de taxes.

Écrit js/tarifs-airbnb.js, lu par le site et par le serveur : le prix d'une
réservation directe = prix Airbnb de ces dates, moins la remise (js/tarifs.js).
Lancé par la GitHub Action « Maisons — données » (une fois par semaine).
"""
import base64
import json
import os
import re
import statistics
import sys
import time
import urllib.parse
import urllib.request
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from airbnb import API_KEY, HEADERS, LISTINGS, ROOT, get  # noqa: E402

OUT = os.path.join(ROOT, "js", "tarifs-airbnb.js")


def walk(o):
    if isinstance(o, dict):
        yield o
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)


# Valeurs connues (octobre 2026), utilisées si le script d'Airbnb n'est pas retrouvé
HASH = "0e1458eca5a69bd2871793b52650ee4a8d70cd02c2690b869947973b41eac13f"
ROUTE = "https://a0.muscache.com/airbnb/static/packages/web/fr/frontend/gp-stays-pdp-route/routes/PdpPlatformRoute.2be632ebc1.js"
STATIC = "https://a0.muscache.com/airbnb/static/packages/web/"


def find_ops():
    """Identifiant de la requête « StaysPdpSections » et liste des options du site Airbnb."""
    route = None
    try:
        page = get(f"https://www.airbnb.fr/rooms/{LISTINGS['bordeaux']}")
        direct = re.findall(r'(https://a0\.muscache\.com/[^"\'\s]+?PdpPlatformRoute\.[0-9a-f]+\.js)', page)
        if direct:
            route = direct[0]
        else:
            # Le script de la page est référencé par le chargeur « asyncRequire »
            for u in dict.fromkeys(re.findall(r'(https://a0\.muscache\.com/[^"\'\s]+?asyncRequire[^"\'\s]*?\.js)', page)):
                m = re.search(r'fr/frontend/gp-stays-pdp-route/routes/PdpPlatformRoute\.[0-9a-f]+\.js', get(u))
                if m:
                    route = STATIC + m.group(0)
                    break
    except Exception as e:  # noqa: BLE001
        print("page Airbnb :", e)
    try:
        js = get(route or ROUTE)
        ops = dict(re.findall(r"name:'(\w+)',type:'query',operationId:'([0-9a-f]{64})'", js))
        flags = sorted(set(re.findall(r"include[A-Z]\w+", js)) - {"includeGp", "includePdpMigration"})
        if ops.get("StaysPdpSections") and flags:
            return ops["StaysPdpSections"], flags
    except Exception as e:  # noqa: BLE001
        print("script Airbnb :", e)
    print("Script Airbnb introuvable : valeurs connues utilisées.")
    return HASH, FLAGS


FLAGS = ["includeGpAmenitiesFragment", "includeGpBookItFragment", "includeGpBookItNonExperiencedGuestFragment", "includeGpHeroFragment",
         "includeGpMessageBannerFragment", "includeGpPropertyAvailableRoomsFragment", "includeHistoryUpdate",
         "includeOverviewMerchandisingTipsFragment", "includePdpLayoutPipelineInputs", "includePdpMigrationAmenitiesFragment",
         "includePdpMigrationBookItCalendarSheetFragment", "includePdpMigrationBookItFloatingFooterFragment",
         "includePdpMigrationBookItNavFragment", "includePdpMigrationBookItNonExperiencedGuestFragment",
         "includePdpMigrationBookItSidebarFragment", "includePdpMigrationHeroFragment", "includePdpMigrationMessageBannerFragment",
         "includePdpMigrationPropertyAvailableRoomsFragment", "includePdpOffers", "includeRecentAskPdpQuestions",
         "includeStaysPdpPriceHeatmapFragment"]


def quote(h, flags, lid, ci, co, adults=2):
    """Prix Airbnb d'un séjour : (sous-total des nuits, taxes, total) en euros, ou None."""
    gid = base64.b64encode(f"StayListing:{lid}".encode()).decode()
    dgid = base64.b64encode(f"DemandStayListing:{lid}".encode()).decode()
    imp = "p3_1700000000_P3sableetpierre"
    psr = {"adults": str(adults), "amenityFilters": None, "bypassTargetings": False, "categoryTag": None, "causeId": None, "children": None,
           "disasterId": None, "discountedGuestFeeVersion": None, "federatedSearchId": None, "forceBoostPriorityMessageType": None,
           "guestAges": None, "hostPreview": False, "infants": None, "interactionType": None, "layouts": ["SIDEBAR", "SINGLE_COLUMN"],
           "omniPageId": None, "omniVersionId": None, "pets": 0, "pdpTypeOverride": None, "photoId": None, "preview": False,
           "previousStateCheckIn": None, "previousStateCheckOut": None, "priceDropSource": None, "partner": None, "partnerProgram": None,
           "directBookingParams": None, "privateBooking": False, "promotionUuid": None, "relaxedAmenityIds": None, "searchId": None,
           "selectedCancellationPolicyId": None, "selectedRatePlanId": None, "splitStays": None, "staysBookingMigrationEnabled": False,
           "translateUgc": None, "useNewSectionWrapperApi": False, "sectionIds": ["BOOK_IT_SIDEBAR", "BOOK_IT_FLOATING_FOOTER"],
           "checkIn": ci, "checkOut": co, "p3ImpressionId": imp}
    v = {"id": gid, "demandStayListingId": dgid, "pdpSectionsRequest": psr, "categoryTag": None, "federatedSearchId": None,
         "federatedSearchSessionId": None, "p3ImpressionId": imp, "photoId": None, "amenityIds": None, "causeId": None,
         "dateRange": {"startDate": ci, "endDate": co}, "guestCounts": {"numberOfAdults": adults}, "numberOfChildren": None,
         "numberOfInfants": None, "numberOfPets": None}
    for f in flags:
        v[f] = f.startswith("includeGp")
    q = urllib.parse.urlencode({"operationName": "StaysPdpSections", "locale": "fr", "currency": "EUR",
                                "variables": json.dumps(v, separators=(",", ":")),
                                "extensions": json.dumps({"persistedQuery": {"version": 1, "sha256Hash": h}}, separators=(",", ":"))})
    req = urllib.request.Request(f"https://www.airbnb.fr/api/v3/StaysPdpSections/{h}?{q}", headers={
        **HEADERS, "Accept": "application/json", "X-Airbnb-API-Key": API_KEY, "Referer": "https://www.airbnb.fr/",
        "X-Airbnb-GraphQL-Platform": "web", "X-Airbnb-GraphQL-Platform-Client": "minimalist-niobe"})
    with urllib.request.urlopen(req, timeout=40) as r:
        data = json.loads(r.read().decode())
    money = lambda s: float(re.sub(r"[^\d,]", "", s).replace(",", "."))  # noqa: E731
    for d in walk(data):
        sdp = d.get("structuredDisplayPrice") if isinstance(d, dict) else None
        if not sdp or not sdp.get("explanationData"):
            continue
        sub = tax = total = None
        for g in sdp["explanationData"].get("priceDetails") or []:
            for it in g.get("items") or []:
                desc = (it.get("description") or "").lower()
                p = it.get("priceString") or ""
                if not p:
                    continue
                if "nuit" in desc and " x " in desc:
                    sub = (sub or 0) + money(p)
                elif desc.startswith("taxe"):
                    tax = (tax or 0) + money(p)
                elif desc == "total":
                    total = money(p)
                elif "réduction" in desc or "remise" in desc:
                    sub = (sub or 0) - abs(money(p))
                else:
                    # autres frais éventuels (ménage affiché à part, etc.)
                    sub = (sub or 0) + money(p)
        if sub:
            return sub, tax or 0.0, total or sub + (tax or 0)
    return None


def available(av, d, n):
    """Séjour possible d'après js/disponibilites.js (arrivée, nuits libres, départ)."""
    if not av:
        return True
    i0 = (d - date.fromisoformat(av["from"])).days
    f = lambda i: int(av["flags"][i]) if 0 <= i < len(av["flags"]) else 7  # noqa: E731
    if not (f(i0) & 2) or not (f(i0 + n) & 4):
        return False
    return all(f(i) & 1 for i in range(i0, i0 + n)) and n >= (av["min"][i0] if 0 <= i0 < len(av["min"]) else 1)


def main():
    avail = {}
    try:
        t = open(os.path.join(ROOT, "js", "disponibilites.js")).read()
        avail = json.loads(re.search(r"Object\.assign\((\{.*?\}),\s*\{\s*updated", t, re.S).group(1))
    except Exception:  # noqa: BLE001
        pass
    h, flags = find_ops()
    today = date.today()
    out = {"updated": time.strftime("%Y-%m-%d"), "source": "Airbnb, prix voyageur affichés (frais compris)"}
    for key, lid in LISTINGS.items():
        av = avail.get(key)
        periods, fixed, taxes = [], [], []
        for k in range(24):  # quinzaines sur 12 mois
            start = date(today.year, today.month, 1) + timedelta(days=15 * k + 1)
            if start <= today:
                start = today + timedelta(days=1)
            got = None
            for shift in range(0, 14):
                d = start + timedelta(days=shift)
                i0 = (d - date.fromisoformat(av["from"])).days if av else -1
                n1 = max(2, av["min"][i0] if av and 0 <= i0 < len(av["min"]) else 2)
                n2 = n1 + 2
                if available(av, d, n1) and available(av, d, n2):
                    try:
                        a = quote(h, flags, lid, d.isoformat(), (d + timedelta(days=n1)).isoformat())
                        time.sleep(1.2)
                        b = quote(h, flags, lid, d.isoformat(), (d + timedelta(days=n2)).isoformat())
                        time.sleep(1.2)
                    except Exception as e:  # noqa: BLE001
                        print(key, d, "erreur", e)
                        continue
                    if a and b:
                        got = (d, n1, n2, a, b)
                        break
            if not got:
                continue
            d, n1, n2, (s1, t1, _), (s2, t2, _) = got
            night = (s2 - s1) / (n2 - n1)
            fix = s1 - night * n1
            periods.append({"du": d.isoformat(), "nuit": round(night)})
            fixed.append(fix)
            if s1:
                taxes.append(t1 / s1 * 100)
            print(key, d, f"{n1} nuits = {s1:.0f} €, {n2} nuits = {s2:.0f} € → nuit {night:.0f} €, fixe {fix:.0f} €, taxes {t1:.2f} €")
        if not periods:
            print(key, "aucun prix relevé")
            continue
        out[key] = {
            "periodes": periods,
            "fixe": round(max(0, statistics.median(fixed))),
            "taxesPct": round(statistics.median(taxes), 2) if taxes else 0,
        }
    # Une maison mal relevée garde ses prix précédents
    try:
        old = json.loads(re.search(r"TARIFS_AIRBNB = (\{.*\});", open(OUT).read(), re.S).group(1))
    except Exception:  # noqa: BLE001
        old = {}
    for key in LISTINGS:
        if len(out.get(key, {}).get("periodes", [])) < 6 and old.get(key):
            print(key, "relevé incomplet : prix précédents conservés")
            out[key] = old[key]
    if not any(k in out for k in LISTINGS):
        raise SystemExit("Aucun prix relevé : rien n'est modifié.")
    with open(OUT, "w") as f:
        f.write("/* Prix Airbnb relevés automatiquement — fichier généré par scripts/prix_airbnb.py, ne pas modifier à la main. */\n")
        f.write("globalThis.TARIFS_AIRBNB = " + json.dumps(out, ensure_ascii=False) + ";\n")
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
