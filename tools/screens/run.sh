#!/usr/bin/env bash
# Captures d'écran hors moteur, en une commande (tools/screens/README.md) :
#   1. capture.luau (Lune) : démarre le vrai client dans le harnais pour chaque appareil × langue ×
#      écran et écrit un instantané JSON par écran ;
#   2. render.mjs (Node + Playwright) : dessine chaque instantané en PNG avec les vraies polices,
#      écrit un rapport par écran, la synthèse et la planche contact index.html.
#
#   ./tools/screens/run.sh                         tout (6 appareils × 2 langues × tous les écrans)
#   ./tools/screens/run.sh --out /tmp/captures     autre dossier de sortie
#   ./tools/screens/run.sh --profiles tv1080 --langs fr --screens upgrades
#   ./tools/screens/run.sh --pending               régénère aussi tests/fixtures/TextFitPending.luau
# Options transmises à capture.luau : --profiles, --langs, --groups, --screens, --pending.
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:$PATH"

OUT="${CC_CAPTURES:-/tmp/claude-0/-home-user-jules/29348b7e-66e1-5b7a-87be-31d48100e74e/scratchpad/cc-captures}"
JOBS="${CC_JOBS:-6}"
CAPTURE_ARGS=()
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
	--profiles | --langs | --groups | --screens)
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
node tools/screens/render.mjs --in "$JSON" --out "$OUT" --jobs "$JOBS"
echo "✅ Planche contact : $OUT/index.html"
