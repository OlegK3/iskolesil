#!/usr/bin/env bash
# Генерирует локальные глифы (PBF) Noto Sans для подписей карты из openmaptiles/fonts.
# Результат: assets/map/fonts/NotoSans-Regular и NotoSans-Bold (латиница + кириллица).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
git clone --depth 1 https://github.com/openmaptiles/fonts.git "$TMP/fonts"
cd "$TMP/fonts"
npm install --no-audit --no-fund
node ./generate.js
for pair in "Noto Sans Regular:NotoSans-Regular" "Noto Sans Bold:NotoSans-Bold"; do
  src="${pair%%:*}"; dst="${pair##*:}"
  mkdir -p "$ROOT/assets/map/fonts/$dst"
  for r in 0-255 256-511 512-767 768-1023 1024-1279 1280-1535 8192-8447 8448-8703; do
    cp "_output/$src/$r.pbf" "$ROOT/assets/map/fonts/$dst/$r.pbf"
  done
done
echo "Глифы готовы"
