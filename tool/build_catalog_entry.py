#!/usr/bin/env python3
"""Печатает запись каталога для готового .mbtiles. URL не выдумывается:
передайте --url после реального размещения файла (сервер в РФ, HTTPS)."""
import argparse, hashlib, json, os, datetime
ap = argparse.ArgumentParser()
ap.add_argument("mbtiles"); ap.add_argument("id"); ap.add_argument("name")
ap.add_argument("bounds"); ap.add_argument("version", type=int)
ap.add_argument("--region", default=""); ap.add_argument("--country", default="Россия")
ap.add_argument("--url", default=None)
a = ap.parse_args()
min_lon, min_lat, max_lon, max_lat = [float(x) for x in a.bounds.split(",")]
h = hashlib.sha256()
with open(a.mbtiles, "rb") as f:
    for c in iter(lambda: f.read(1 << 20), b""):
        h.update(c)
print(json.dumps({
    "id": a.id, "name": a.name, "region": a.region, "country": a.country,
    "center": {"lat": round((min_lat + max_lat) / 2, 5), "lon": round((min_lon + max_lon) / 2, 5)},
    "bounds": {"minLat": min_lat, "minLon": min_lon, "maxLat": max_lat, "maxLon": max_lon},
    "version": a.version, "updatedAt": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "sizeBytes": os.path.getsize(a.mbtiles), "url": a.url, "sha256": h.hexdigest(),
}, ensure_ascii=False, indent=2))
