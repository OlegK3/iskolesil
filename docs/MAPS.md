# Офлайн-карты

Формат: **MBTiles**, векторные тайлы (pbf) схемы **OpenMapTiles**, z0–14. Выбор: Planetiler (один JAR, без БД) → MBTiles → локальный loopback-сервер в приложении. Не использовались: TileServer GL/Martin (нужен сервер), PMTiles (нет проверенной поддержки в плагине), публичные серверы OSM.

## Сделать карту города

```bash
tool/build_city_map.sh barnaul "Барнаул" 83.2,52.95,84.4,53.75 \
  https://download.geofabrik.de/russia/siberian-fed-district-latest.osm.pbf 14
```
Нужны Java 21, ~8 ГБ ОЗУ. Результат: `work/<id>.mbtiles` (+ метаданные `iskolesil_id`, `iskolesil_version`) и `work/<id>.catalog.json` (размер и SHA-256 — реальные). Либо запустите workflow **Build city map** в GitHub Actions.

Границы Барнаула: центр 53,3548 N 83,7698 E; bbox с запасом на пригороды — `83.2,52.95,84.4,53.75` (оценка, при необходимости расширьте).

## Шрифты/спрайты

Глифы Noto Sans (латиница+кириллица) генерируются `tool/make_glyphs.sh` из openmaptiles/fonts в `assets/map/fonts/` (SIL OFL). Спрайтов нет — значки POI не рисуются. Если глифы не сгенерированы, карта работает без подписей.

## Установка

Приложение → Настройки → Карты городов → «Установить из файла». Порядок: копирование во временный файл → проверка SHA-256 (если известна) → проверка MBTiles (таблицы, формат pbf, тайлы) → атомарная замена старой карты. При сбое старая карта сохраняется. Удаление карты не затрагивает поездки.

## Каталог (JSON)

Поля: `id, name, region, country, center{lat,lon}, bounds{minLat,minLon,maxLat,maxLon}, version, updatedAt, sizeBytes, url, sha256`. Встроенный — `assets/catalog.json` (для Барнаула url/sha256/size = null, потому что файл ещё нигде не размещён). Удалённый — `--dart-define=CATALOG_URL=https://…` (только HTTPS).

## Лицензии

Данные © участники OpenStreetMap, ODbL. Схема OpenMapTiles (BSD для кода схемы; атрибуция «© OpenMapTiles»). Атрибуция показана на карте и в Настройках.
