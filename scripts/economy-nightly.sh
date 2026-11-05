#!/usr/bin/env bash
# Jeu de nuit de la porte d'économie v2.0 (docs/04 §27.9, GDD §4.24.1) : BLOQUANT, comme la porte de
# check.sh. Chaque cas est un processus Lune (EconomyPacing.spec avec ECON_NIGHT=<cas>) :
#   tailsRef4 tailsRef8 tailsRef16 tailsAssidu4 tailsAssidu8
#                      les configurations de check.sh (référence 84 jours, assidu 28 jours, serveurs de
#                      4, 8 et 16) sur 400 joueurs : chaque clé à sa VRAIE limite, dont les clés de queue
#                      que check.sh ne garde qu'en alarme rapide (docs/04 §27.9) ; bruit imprimé (SPREAD)
#   ref140 assidu140   référence et assidu (2 h par jour), 400 joueurs, 140 jours, serveur de 16 (+ sans
#                      Ascension, 80 joueurs, 28 jours : recordRDay28) ; assidu140 tient lieu de
#                      tailsAssidu16 (mêmes graines, mêmes 28 premiers jours)
#   min10 min20        10 et 20 min par jour, 84 jours
#   weekend            90 min le samedi et le dimanche, 140 jours
#   allday             6 h par jour, serveur de 4, 28 jours (≤ 30 % « sans but » par bande)
#   noatelier          jamais l'Atelier (référence 84 jours, assidu 84 jours) et atelierEffect
#   refuse3            refuse la 1re Ascension pendant 3 jours (référence, assidu)
#   advisor            politique « Conseillé » (UpgradeAdvisor.next), référence et assidu
#   spender            gros acheteur, 200 joueurs, 84 jours : spenderLeadTimeShare ≤ 25 % (A1 à A7)
#   forcedA10 … 60     profils de départ à A = 10, 20, 30, 60 (Prestige.apply répété)
#   fullAtelier        Atelier et « Pour le plaisir » complets dès le début
# Usage : ./scripts/economy-nightly.sh [cas …]   (sans argument : tous)
#   ECON_JOBS=4            cas joués en même temps (4 par défaut : un par cœur)
#   ECON_NIGHT_PLAYERS=80  joueurs par configuration (80 au moins) ; ECON_TAIL_PLAYERS=400 joueurs des
#                          cas tails* ; ECON_SPENDERS=200 gros acheteurs
#   ECON_NIGHT_OUT=<dossier> journaux (par défaut un dossier temporaire, gardé et affiché)
# Code de sortie : 0 si tous les cas sont verts, 1 sinon. Résumé à la fin : durée, tests réussis et
# échoués de chaque cas, clés hors limites.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:$PATH"

# les plus longs d'abord (le jeu finit plus tôt quand ils commencent en premier)
ALL_CASES=(assidu140 ref140 noatelier advisor tailsAssidu4 tailsAssidu8 tailsRef16 tailsRef4 tailsRef8 refuse3 spender allday fullAtelier weekend min20 min10 forcedA10 forcedA20 forcedA30 forcedA60)
if [ "$#" -gt 0 ]; then
	CASES=("$@")
else
	CASES=("${ALL_CASES[@]}")
fi
JOBS="${ECON_JOBS:-4}"
OUT="${ECON_NIGHT_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/economy-nightly.XXXXXX")}"
mkdir -p "$OUT"
START=$(date +%s)
echo "▶ Porte d'économie v2.0, jeu de nuit : ${#CASES[@]} cas, ${JOBS} à la fois, journaux dans ${OUT}"

run_case() {
	local name="$1"
	local t0
	t0=$(date +%s)
	ECON_NIGHT="$name" lune run tests/run -- EconomyPacing >"$OUT/$name.log" 2>&1
	local rc=$?
	echo "$rc $(($(date +%s) - t0))" >"$OUT/$name.status"
}

running=0
for name in "${CASES[@]}"; do
	run_case "$name" &
	running=$((running + 1))
	if [ "$running" -ge "$JOBS" ]; then
		wait -n
		running=$((running - 1))
	fi
done
wait

# Résumé
failed=0
echo
echo "════════ Résumé du jeu de nuit ($(($(date +%s) - START)) s) ════════"
printf "%-12s %-6s %8s %10s\n" "cas" "état" "durée" "tests"
for name in "${CASES[@]}"; do
	status="$OUT/$name.status"
	log="$OUT/$name.log"
	if [ ! -f "$status" ]; then
		printf "%-12s %-6s %8s %10s\n" "$name" "ABSENT" "—" "—"
		failed=1
		continue
	fi
	read -r rc secs <"$status"
	counts=$(grep -aoE "[0-9]+ réussis, [0-9]+ échoués, [0-9]+ specs non chargées" "$log" | tail -1)
	pass=$(echo "$counts" | grep -oE "^[0-9]+" || echo "?")
	fail=$(echo "$counts" | grep -oE "[0-9]+ échoués" | grep -oE "^[0-9]+" || echo "?")
	state="vert"
	if [ "$rc" -ne 0 ] || [ -z "$counts" ] || [ "$fail" != "0" ]; then
		state="ROUGE"
		failed=1
	fi
	printf "%-12s %-6s %7ss %4s / %-4s\n" "$name" "$state" "$secs" "$pass" "$fail"
	if [ "$state" = "ROUGE" ]; then
		grep -a " HORS$" "$log" | sed 's/^/      /' | head -40
		grep -a "cas inconnu\|échec de chargement" "$log" | sed 's/^/      /' | head -5
	fi
done
echo
if [ "$failed" -eq 0 ]; then
	echo "✅ Jeu de nuit vert."
	exit 0
fi
echo "❌ Jeu de nuit rouge (détail : ${OUT}/<cas>.log)."
exit 1
