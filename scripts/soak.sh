#!/usr/bin/env bash
# Robot de longue durée « de nuit » (docs/04 §17.1 couche c) : 16 robots, 6 h de temps simulé.
# check.sh lance la même spec avec la durée par défaut (SOAK_HOURS absent : 0,5 h).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:$PATH"
export SOAK_HOURS="${SOAK_HOURS:-6}"
echo "▶ Soak : ${SOAK_HOURS} h de temps simulé"
lune run tests/run -- Soak
