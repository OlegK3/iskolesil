# Библиотеки и лицензии

Версии указаны ограничениями в `pubspec.yaml`; точные — в `pubspec.lock` (артефакт CI). Лицензии приведены по моим сведениям и требуют проверки по `pubspec.lock`.

| Пакет | Назначение | Лицензия (проверить) |
|---|---|---|
| flutter, flutter_localizations | UI | BSD-3 |
| flutter_riverpod | состояние | MIT |
| sqflite, path, path_provider | SQLite, файлы | BSD-2/3, MIT |
| geolocator | GPS + foreground service | MIT |
| permission_handler | разрешения/уведомления | MIT |
| maplibre_gl | карта MapLibre | BSD-3 |
| xml | GPX | MIT |
| crypto | SHA-256 | BSD-3 |
| file_picker | выбор файлов | MIT |
| share_plus | «Поделиться» | BSD-3 |

Инструменты сборки карты (не входят в APK): Planetiler (Apache-2.0), openmaptiles/fonts, Noto Sans (SIL OFL 1.1). Данные: OpenStreetMap (ODbL), схема OpenMapTiles.
