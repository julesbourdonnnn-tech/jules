"""Disponibilités réelles des deux maisons, lues dans le calendrier Airbnb.

Pour les 12 prochains mois, Airbnb indique jour par jour : si la nuit est libre,
si l'on peut arriver ou partir ce jour-là, et la durée minimale et maximale du
séjour. Ce script écrit tout cela dans js/disponibilites.js, que le calendrier
du site utilise pour griser les dates prises et faire respecter la durée minimale.

Lancé automatiquement plusieurs fois par jour par la GitHub Action
« Maisons — données ». Rien à faire à la main.
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from airbnb import API_KEY, HEADERS, LISTINGS, ROOT, find_hash, get  # noqa: E402

# Identifiant de la requête « calendrier » du site Airbnb. S'il change, le
# script le retrouve tout seul dans les scripts de la page.
KNOWN = "8f08e03c7bd16fcad3c92a3592c19a8b559a0d0855a84028d1163d4733ed9ade"


def walk(o):
    if isinstance(o, dict):
        yield o
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)


def calendar(lid, h):
    today = time.gmtime()
    variables = {"request": {"count": 12, "listingId": lid, "month": today.tm_mon, "year": today.tm_year}}
    q = urllib.parse.urlencode({
        "operationName": "PdpAvailabilityCalendar", "locale": "fr", "currency": "EUR",
        "variables": json.dumps(variables, separators=(",", ":")),
        "extensions": json.dumps({"persistedQuery": {"version": 1, "sha256Hash": h}}, separators=(",", ":")),
    })
    req = urllib.request.Request(f"https://www.airbnb.fr/api/v3/PdpAvailabilityCalendar/{h}?{q}", headers={
        **HEADERS, "Accept": "application/json", "X-Airbnb-API-Key": API_KEY, "Referer": "https://www.airbnb.fr/"})
    with urllib.request.urlopen(req, timeout=40) as r:
        data = json.loads(r.read().decode())
    days = sorted((d for d in walk(data) if isinstance(d, dict) and "calendarDate" in d), key=lambda d: d["calendarDate"])
    if not days:
        raise RuntimeError(f"réponse sans calendrier : {json.dumps(data)[:300]}")
    return days


def discover_hash(lid):
    import re
    page = get(f"https://www.airbnb.fr/rooms/{lid}")
    for u in dict.fromkeys(re.findall(r'(https://a0\.muscache\.com/airbnb/static/packages/web/[^"\'\s]+?\.js)', page)):
        try:
            js = get(u, tries=2)
        except Exception:  # noqa: BLE001
            continue
        if "PdpAvailabilityCalendar" in js:
            h = find_hash(js, "PdpAvailabilityCalendar")
            if h:
                return h
    return None


def encode(days):
    """Une chaîne de chiffres (un par jour) : 1 = nuit libre, 2 = arrivée possible,
    4 = départ possible (additionnés), plus les durées min/max par jour."""
    flags = "".join(str((1 if d.get("available") else 0) + (2 if d.get("availableForCheckin") else 0)
                        + (4 if d.get("availableForCheckout") else 0)) for d in days)
    return {
        "from": days[0]["calendarDate"],
        "flags": flags,
        "min": [d.get("minNights") or 1 for d in days],
        "max": [d.get("maxNights") or 0 for d in days],
    }


def main():
    out = {}
    h = KNOWN
    for key, lid in LISTINGS.items():
        try:
            days = calendar(lid, h)
        except Exception as e:  # noqa: BLE001
            print(f"{key} : {e} — recherche d'un nouvel identifiant")
            h = discover_hash(lid) or h
            days = calendar(lid, h)
        enc = encode(days)
        # Durées min/max : on compresse (souvent identiques sur toute l'année)
        out[key] = enc
        print(key, enc["from"], len(enc["flags"]), "jours,", enc["flags"].count("7"), "jours libres (arrivée et départ)")
    out["updated"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    path = os.path.join(ROOT, "js", "disponibilites.js")
    old = open(path).read() if os.path.exists(path) else ""
    body = json.dumps({k: v for k, v in out.items() if k != "updated"}, separators=(",", ":"))
    if body in old:
        print("Aucun changement de disponibilité.")
        return
    with open(path, "w") as f:
        f.write("/* Disponibilités Airbnb des deux maisons — fichier généré par scripts/disponibilites.py, ne pas modifier à la main. */\n")
        f.write(f"window.AVAILABILITY = Object.assign({body}, {{ updated: \"{out['updated']}\" }});\n")


if __name__ == "__main__":
    main()
