"""Climat mois par mois à Lacanau et à Bordeaux, pour la rubrique « Quand venir ? ».

Moyennes calculées sur dix années complètes de relevés (2015 à 2024), à partir
des archives météo Open-Meteo (réanalyse ERA5, données libres) :
  - température maximale et minimale moyennes,
  - heures de soleil par jour,
  - nombre de jours de pluie (au moins 1 mm),
  - température de l'océan au large de Lacanau.

Écrit js/climat.js (lu par le site) et data/climat.json (copie lisible).
Lancé par la GitHub Action « Maisons — données » ; il suffit de le relancer une
fois par an, les moyennes bougent très peu.
"""
import json
import os
import statistics
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
START, END = "2015-01-01", "2024-12-31"
PLACES = {
    "lacanau": {"lat": 45.0042, "lng": -1.1284, "sea": (45.0, -1.30)},
    "bordeaux": {"lat": 44.8378, "lng": -0.5792, "sea": None},
}


def get_json(url, tries=4):
    last = None
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "sable-et-pierre/1.0"}), timeout=120) as r:
                return json.loads(r.read().decode())
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(5 * (i + 1))
    raise RuntimeError(f"{url[:120]}… : {last}")


def monthly(dates, values, agg=statistics.mean):
    by = {m: [] for m in range(1, 13)}
    for d, v in zip(dates, values):
        if v is not None:
            by[int(d[5:7])].append(v)
    return [round(agg(by[m]), 1) if by[m] else None for m in range(1, 13)]


def main():
    out = {"period": f"{START[:4]}–{END[:4]}", "source": "Open-Meteo (ERA5)", "updated": time.strftime("%Y-%m-%d")}
    for key, p in PLACES.items():
        q = urllib.parse.urlencode({
            "latitude": p["lat"], "longitude": p["lng"], "start_date": START, "end_date": END,
            "daily": "temperature_2m_max,temperature_2m_min,sunshine_duration,precipitation_sum",
            "timezone": "Europe/Paris",
        })
        d = get_json(f"https://archive-api.open-meteo.com/v1/archive?{q}")["daily"]
        days = d["time"]
        years = (int(END[:4]) - int(START[:4]) + 1)
        rain = [1 if (v or 0) >= 1 else 0 for v in d["precipitation_sum"]]
        res = {
            "tmax": monthly(days, d["temperature_2m_max"]),
            "tmin": monthly(days, d["temperature_2m_min"]),
            "sun": monthly(days, [None if v is None else v / 3600 for v in d["sunshine_duration"]]),
            "rainDays": [round(x * 1, 0) for x in monthly(days, rain, agg=lambda xs: sum(xs) / years)],
        }
        if p["sea"]:
            # Température de surface de l'océan : API marine (historique depuis 2022)
            # puis, à défaut, la réanalyse ERA5.
            lat, lng = p["sea"]
            sst = None
            for url in (
                "https://marine-api.open-meteo.com/v1/marine?" + urllib.parse.urlencode({
                    "latitude": lat, "longitude": lng, "start_date": "2022-01-01", "end_date": END,
                    "hourly": "sea_surface_temperature", "timezone": "Europe/Paris"}),
                "https://archive-api.open-meteo.com/v1/archive?" + urllib.parse.urlencode({
                    "latitude": lat, "longitude": lng, "start_date": START, "end_date": END,
                    "hourly": "sea_surface_temperature", "timezone": "Europe/Paris"}),
            ):
                try:
                    h = get_json(url)["hourly"]
                    vals = monthly([t[:10] for t in h["time"]], h["sea_surface_temperature"])
                    if all(v is not None for v in vals):
                        sst = vals
                        res["seaSource"] = "marine" if "marine-api" in url else "era5"
                        break
                except Exception as e:  # noqa: BLE001
                    print(f"{key} océan : {e}")
            res["sea"] = sst
        out[key] = res
        print(key, json.dumps(res))
    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    with open(os.path.join(ROOT, "data", "climat.json"), "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    with open(os.path.join(ROOT, "js", "climat.js"), "w") as f:
        f.write("/* Climat moyen mois par mois — fichier généré par scripts/climat.py, ne pas modifier à la main. */\n")
        f.write("window.CLIMATE = " + json.dumps(out, ensure_ascii=False) + ";\n")


if __name__ == "__main__":
    main()
