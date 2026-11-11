#!/usr/bin/env bash
# Matrice de captures de nuit (lot I, étape 4 ; docs/05 §1) : l'outil d'écrans (tools/screens) sur le
# jeu ouvert (groupe « launch » : HUD, menu, chaque panneau du rail et chaque onglet, 13 interrupteurs
# du client, profil v2) à 3 résolutions de télé (tv1080, tv720, tv2160) × 2 langues (fr, en) × 2 tailles
# de texte (Medium, Largest = × 1,5) × 2 qualités graphiques (normale, réduite). Les images vont dans un
# dossier temporaire HORS de git (jamais validées) ; synthèse dans <dossier>/report.json.
#
#   ./scripts/screens-nightly.sh                    dossier temporaire neuf (mktemp)
#   ./scripts/screens-nightly.sh /chemin/sortie     dossier choisi (vidé d'abord)
#   SCREEN_GROUPS=launch,meta ./scripts/screens-nightly.sh autres groupes
#
# Code de sortie 1 au moindre problème de l'outil (écran impossible à jouer, rendu en erreur, démarrage
# du client en échec). Les défauts d'affichage relevés (texte coupé, débord…) sont comptés dans le
# rapport et ne font pas échouer la nuit : TextFit_all, Screens_display et Upgrades_Reference (check.sh)
# sont les gardes bloquantes ; la nuit sert à regarder les images.
# Durée : ≈ 6 min pour le groupe « launch » (24 combinaisons). Mémoire : un seul processus Lune à la fois.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:/opt/node22/bin:$PATH"

OUT="${1:-$(mktemp -d -t screens-nightly-XXXXXX)}"
GROUPS_ARG="${SCREEN_GROUPS:-launch}"
case "$OUT" in
"$PWD"/* | ./* | src/* | tests/*)
	echo "sortie dans le dépôt refusée : $OUT (dossier temporaire hors de git)" >&2
	exit 2
	;;
esac
rm -rf "$OUT"
mkdir -p "$OUT"
start=$(date +%s)
status=0
runs=()
for size in medium largest; do
	for quality in normal low; do
		dir="$OUT/$size-$quality"
		log="$OUT/$size-$quality.log"
		echo "▶ $size × $quality → $dir"
		if ! RS_CAPTURES="$dir" ./tools/screens/run.sh --profiles tv1080,tv720,tv2160 --langs fr,en \
			--groups "$GROUPS_ARG" --text-size "$size" --quality "$quality" >"$log" 2>&1; then
			echo "  ✗ l'outil a échoué (voir $log)"
			status=1
		fi
		if grep -q "^✗" "$log"; then
			echo "  ✗ écrans impossibles à jouer :"
			grep "^✗" "$log" | head -20
			status=1
		fi
		runs+=("$size-$quality")
	done
done
python3 - "$OUT" "$status" "$start" "${runs[@]}" <<'PY'
import json, os, sys, time
out, status, start, runs = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
report = {"generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "runs": [], "images": 0,
          "errors": 0, "totals": {}, "seconds": int(time.time()) - start}
for run in runs:
    path = os.path.join(out, run, "summary.json")
    entry = {"run": run, "rendered": 0, "errors": [], "totals": {}}
    if os.path.exists(path):
        s = json.load(open(path))
        entry["rendered"] = s.get("rendered", 0)
        entry["totals"] = s.get("totals", {})
        entry["errors"] = [p["folder"] + "/" + p["id"] + " : " + str(p["error"])
                           for p in s.get("perScreen", []) if p.get("error")]
    else:
        entry["errors"].append("summary.json absent")
    report["runs"].append(entry)
    report["images"] += entry["rendered"]
    report["errors"] += len(entry["errors"])
    for k, v in entry["totals"].items():
        report["totals"][k] = report["totals"].get(k, 0) + v
report["status"] = "ok" if status == 0 and report["errors"] == 0 else "échec"
json.dump(report, open(os.path.join(out, "report.json"), "w"), indent=1, ensure_ascii=False)
print(f"{report['images']} images, {report['errors']} erreurs de l'outil, défauts relevés : {report['totals']}, "
      f"{report['seconds']} s → {out}/report.json")
sys.exit(0 if report["status"] == "ok" else 1)
PY
summary=$?
if [ "$status" -ne 0 ] || [ "$summary" -ne 0 ]; then
	echo "✗ matrice de nuit : problème de l'outil (voir $OUT/report.json)"
	exit 1
fi
echo "✅ matrice de nuit : $OUT"
