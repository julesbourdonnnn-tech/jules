#!/usr/bin/env python3
"""
Temps de trajet en voiture (exécuté par la GitHub Action « Trajets », qui a accès à internet).
Entrée : data/trajets-entree.json  { id: { "lat": …, "lng": …, "gare": { "lat": …, "lng": … } | null } }
Sortie : data/trajets-voiture.json { id: { "paris": min, "lyon": min, "bordeaux": min, "gare": min } }
Calcul avec le serveur public OSRM (itinéraire routier le plus rapide, sans trafic).
"""
import json, os, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IN = os.path.join(ROOT, "data", "trajets-entree.json")
OUT = os.path.join(ROOT, "data", "trajets-voiture.json")
OSRM = "https://router.project-osrm.org"
CITIES = {"paris": (48.8566, 2.3522), "lyon": (45.7640, 4.8357), "bordeaux": (44.8378, -0.5792)}
UA = {"User-Agent": "nuits-singulieres-trajets/1.0"}

def get(url):
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            print("  nouvel essai", attempt + 1, e, flush=True)
            time.sleep(3 * (attempt + 1))
    raise RuntimeError("OSRM injoignable")

def mins(seconds):
    return None if seconds is None else int(round(seconds / 60.0))

def main():
    data = json.load(open(IN, encoding="utf-8"))
    ids = list(data)
    out = {i: {} for i in ids}
    # 1. Paris, Lyon, Bordeaux → chaque établissement (une seule requête « table » par paquet de 60)
    for start in range(0, len(ids), 60):
        chunk = ids[start:start + 60]
        coords = [f"{lng},{lat}" for lat, lng in CITIES.values()] + [f"{data[i]['lng']},{data[i]['lat']}" for i in chunk]
        url = f"{OSRM}/table/v1/driving/{';'.join(coords)}?sources=0;1;2&destinations={';'.join(str(k) for k in range(3, len(coords)))}&annotations=duration"
        res = get(url)
        for ci, city in enumerate(CITIES):
            for hi, hid in enumerate(chunk):
                out[hid][city] = mins(res["durations"][ci][hi])
        time.sleep(1.5)
    # 2. Gare la plus pratique → établissement (dernier trajet)
    for hid in ids:
        g = data[hid].get("gare")
        if not g:
            continue
        res = get(f"{OSRM}/route/v1/driving/{g['lng']},{g['lat']};{data[hid]['lng']},{data[hid]['lat']}?overview=false")
        if res.get("routes"):
            out[hid]["gare"] = mins(res["routes"][0]["duration"])
        time.sleep(1.1)
    out = {"_calcul": time.strftime("%Y-%m-%d"), **out}
    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"{len(ids)} établissements calculés")

if __name__ == "__main__":
    sys.exit(main())
