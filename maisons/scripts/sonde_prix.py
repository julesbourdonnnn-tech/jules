"""Sonde temporaire : retrouve comment la page Airbnb obtient le prix d'un séjour.
Enregistre dans data/airbnb/sonde/ le contexte des requêtes trouvées dans les scripts."""
import json, os, re, sys, base64, urllib.parse, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
from airbnb import get, HEADERS, API_KEY, ROOT, LISTINGS

OUT = os.path.join(ROOT, "data", "airbnb", "sonde")
os.makedirs(OUT, exist_ok=True)
log = []
page = get(f"https://www.airbnb.fr/rooms/{LISTINGS['bordeaux']}?check_in=2027-03-12&check_out=2027-03-14&adults=2")
open(f"{OUT}/page.html", "w").write(page)
scripts = list(dict.fromkeys(re.findall(r'(https://a0\.muscache\.com/[^"\'\s]+?\.js)', page)))
log.append(f"{len(scripts)} scripts dans la page")
names = ["StaysPdpSections", "stayCheckout", "StaysPdpBookIt", "BookItQuery", "PdpPlatformRoute", "priceDetails", "StayCheckout"]
ctx = {}
seen = set()
queue = scripts[:]
while queue and len(seen) < 500:
    u = queue.pop(0)
    if u in seen: continue
    seen.add(u)
    try: js = get(u, tries=1)
    except Exception: continue
    for n in names:
        for m in re.finditer(n, js):
            ctx.setdefault(n, [])
            if len(ctx[n]) < 6:
                ctx[n].append({"url": u, "ctx": js[max(0, m.start() - 300): m.end() + 300]})
    for rel in re.findall(r'["\'(]((?:https://a0\.muscache\.com/)?(?:airbnb/static/)?packages/web/[\w./\-]+?\.js)', js):
        full = rel if rel.startswith("http") else "https://a0.muscache.com/airbnb/static/" + rel.split("airbnb/static/")[-1]
        if full not in seen: queue.append(full)
log.append(f"{len(seen)} scripts parcourus ; trouvés : " + ", ".join(f"{k}×{len(v)}" for k, v in ctx.items()))
json.dump(ctx, open(f"{OUT}/contexte.json", "w"), ensure_ascii=False, indent=1)
# Toutes les opérations GraphQL repérées dans la page elle-même
ops = sorted(set(re.findall(r'"operationName"\s*:\s*"(\w+)"', page)) | set(re.findall(r'api/v3/(\w+)/', page)))
log.append("opérations dans la page : " + ", ".join(ops))
hashes = re.findall(r'(\w+)[^a-zA-Z0-9]{1,40}([0-9a-f]{64})', page)
log.append("hash dans la page : " + json.dumps(hashes[:20]))
open(f"{OUT}/log.txt", "w").write("\n".join(log))
print("\n".join(log))
