#!/usr/bin/env bash
# Vérification complète avant commit : formatage, lint, tests, build, intégrité de la place.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:$PATH"

echo "▶ StyLua (formatage)";   stylua --check src tests
echo "▶ Selene (lint)";        selene src
echo "▶ Tests Lune";           lune run tests/run
echo "▶ Build Rojo";           rojo build -o build/Game.rbxl
echo "▶ Intégrité de la place"; lune run scripts/verify-place build/Game.rbxl
echo "✅ Tout est vert."
