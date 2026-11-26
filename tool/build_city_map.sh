#!/usr/bin/env bash
# Генерация офлайн-карты города (MBTiles, векторные тайлы OpenMapTiles) из данных OSM.
# Требуется: Java 21+, ~8 ГБ ОЗУ, интернет (только на этапе сборки, не в приложении).
# Использование: tool/build_city_map.sh <id> "<Название>" <minLon,minLat,maxLon,maxLat> <osm.pbf URL> [maxzoom]
# Пример (Барнаул):
#   tool/build_city_map.sh barnaul "Барнаул" 83.2,52.95,84.4,53.75 \
#     https://download.geofabrik.de/russia/siberian-fed-district-latest.osm.pbf 14
set -euo pipefail
ID=${1:?id}; NAME=${2:?name}; BOUNDS=${3:?bounds}; PBF_URL=${4:?pbf url}; MAXZ=${5:-14}
WORK=${WORK:-work}; mkdir -p "$WORK"
JAR="$WORK/planetiler.jar"
if [ ! -f "$JAR" ]; then
  curl -fL -o "$JAR" https://github.com/onthegomap/planetiler/releases/latest/download/planetiler.jar
fi
OUT="$WORK/$ID.mbtiles"
java -Xmx${PLANETILER_HEAP:-6g} -jar "$JAR" \
  --download --osm-url="$PBF_URL" --bounds="$BOUNDS" \
  --output="$OUT" --force --maxzoom="$MAXZ" \
  --exclude-layers=poi,housenumber,aeroway,aerodrome_label,mountain_peak \
  --tmpdir="$WORK/tmp" --storage=mmap
VERSION=$(date -u +%Y%m%d)
python3 - "$OUT" "$ID" "$NAME" "$VERSION" <<'PY'
import sqlite3, sys
path, id_, name, version = sys.argv[1:5]
db = sqlite3.connect(path)
for k, v in [("iskolesil_id", id_), ("name", name), ("iskolesil_version", version)]:
    db.execute("INSERT OR REPLACE INTO metadata(name, value) VALUES (?, ?)", (k, v))
db.commit(); db.close()
PY
python3 "$(dirname "$0")/build_catalog_entry.py" "$OUT" "$ID" "$NAME" "$BOUNDS" "$VERSION" > "$WORK/$ID.catalog.json"
echo "Готово: $OUT"; cat "$WORK/$ID.catalog.json"
