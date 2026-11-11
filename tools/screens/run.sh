#!/usr/bin/env bash
# Captures d'écran hors moteur de Raise a Squishy, en une commande (tools/screens/README.md) :
#   1. capture.luau (Lune) : démarre le vrai client dans le harnais pour chaque appareil × langue ×
#      écran et écrit un instantané JSON par écran (et keys.json : chaque clé de texte vérifiée) ;
#   2. render.mjs (Node + Playwright) : dessine chaque instantané en PNG avec les vraies polices,
#      écrit un rapport par écran, la synthèse et la planche contact index.html.
#
#   ./tools/screens/run.sh                         tout (4 appareils × 2 langues × tous les écrans)
#   ./tools/screens/run.sh --out /tmp/captures     autre dossier de sortie
#   ./tools/screens/run.sh --profiles tv1080 --langs fr --screens panel.Ranch
#   ./tools/screens/run.sh --pending               régénère aussi tests/fixtures/TextFitPending.luau
#   ./tools/screens/run.sh --keys-pending          régénère aussi tests/fixtures/TextFitKeysPending.luau
#   ./tools/screens/run.sh --text-size largest --quality low   taille de texte × 1,5, graphismes réduits
# Options transmises à capture.luau : --profiles, --langs, --groups, --screens, --pending,
# --keys-pending. Option du rendu : --cap screen (autre hypothèse sur les bornes de TextScaled).
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:/opt/node22/bin:$PATH"

OUT="${RS_CAPTURES:-/tmp/claude-0/-home-user-jules/29348b7e-66e1-5b7a-87be-31d48100e74e/scratchpad/rs-captures}"
JOBS="${RS_JOBS:-6}"
CAPTURE_ARGS=()
RENDER_ARGS=()
while [[ $# -gt 0 ]]; do
	case "$1" in
	--out)
		OUT="$2"
		shift 2
		;;
	--jobs)
		JOBS="$2"
		shift 2
		;;
	--pending)
		CAPTURE_ARGS+=("--pending" "tests/fixtures/TextFitPending.luau")
		shift
		;;
	--keys-pending)
		CAPTURE_ARGS+=("--keys-pending" "tests/fixtures/TextFitKeysPending.luau")
		shift
		;;
	--cap)
		RENDER_ARGS+=("--cap" "$2")
		shift 2
		;;
	--profiles | --langs | --groups | --screens | --text-size | --quality)
		CAPTURE_ARGS+=("$1" "$2")
		shift 2
		;;
	*)
		echo "option inconnue : $1" >&2
		exit 2
		;;
	esac
done

JSON="$OUT/json"
rm -rf "$JSON"
mkdir -p "$OUT"
echo "▶ Captures (Lune) → $JSON"
lune run tools/screens/capture -- --out "$JSON" "${CAPTURE_ARGS[@]}"
echo "▶ Rendu (Chromium, polices Google Fonts) → $OUT"
node tools/screens/render.mjs --in "$JSON" --out "$OUT" --jobs "$JOBS" "${RENDER_ARGS[@]}"
cp "$JSON/keys.json" "$OUT/keys.json" 2>/dev/null || true
echo "✅ Planche contact : $OUT/index.html"
