# Архитектура

## Слои

| Слой | Каталог | Содержимое |
|---|---|---|
| Presentation | `lib/ui` | Экраны и виджеты (Flutter, Riverpod `ConsumerWidget`). Бизнес-логики нет. |
| Domain | `lib/domain` | Чистый Dart: модели, геометрия, фильтрация трека (`TrackAccumulator`), статистика, GPX, интерфейсы репозиториев. Не зависит от Flutter/Android. |
| Data | `lib/data` | SQLite (sqflite), миграции, реализации репозиториев. |
| Location Service | `lib/services/location_service.dart`, `recording_controller.dart` | geolocator + Foreground Service; автомат записи поездки. |
| Map Service | `lib/services/map/` | Локальный HTTP-сервер тайлов (MBTiles), монохромный стиль, управление картами городов. |
| Storage Service | `lib/services/data_exchange.dart` | GPX, резервные копии. |

Провайдеры — `lib/providers.dart`. Совместно с Android-кодом только канал `ru.iskolesil/storage` (свободное место, метрическая сеть).

## Замены относительно предпочтительного стека (обоснование)

- **sqflite вместо Drift**: Drift требует кодогенерации (`build_runner`), а код писался без возможности запускать её. Репозитории скрыты за интерфейсами — переход на Drift не затронет domain/UI.
- **Локальный loopback-сервер тайлов вместо прямого `mbtiles://`**: поддержка локальных MBTiles в Flutter-плагине MapLibre не проверена; сервер на 127.0.0.1 — простой и контролируемый способ (cleartext разрешён только для loopback через `network_security_config`).
- **Foreground Service через geolocator** (`ForegroundNotificationConfig`) вместо собственного плагина — меньше нативного кода.
- **Без Riverpod codegen/uuid/intl/dio**: меньше зависимостей.

## База данных (SQLite, `schemaVersion = 1`)

Время — Unix epoch (мс, UTC). `PRAGMA foreign_keys = ON`.

- `rides(id UUID PK, title, description, started_at, finished_at, duration_seconds, moving_duration_seconds, distance_meters, average_speed, max_speed, elevation_gain NULL, status [recording|paused|finished], created_at, updated_at)`
- `track_points(id PK, ride_id FK → rides ON DELETE CASCADE, latitude, longitude, altitude NULL, speed NULL, accuracy NULL, timestamp, segment_index)`; индекс `(ride_id, timestamp)`.
- `city_maps(id, name, region, version, local_path, min/max lat/lon, size_bytes, checksum, installation_status, installed_at)` — отдельно от поездок.
- `app_settings(key, value)` — mapStyle, showPreviousRoutes, measurementUnits, trackingSettings (JSON), wifiOnlyDownloads, currentCityId, hiddenRideIds, schemaVersion; служебный ключ `active_ride` (состояние записи для восстановления).

Миграции: словарь `AppDatabase._migrations` (версия → функция), применяются подряд в `onUpgrade`. Идентификаторы — UUID v4 (задел под синхронизацию); `updated_at` есть у поездок.

## Фильтрация GPS и расчёты (`TrackingConfig`, пороги по умолчанию)

1. `accuracy > 30 м` — точка отбрасывается. Точность 0/неизвестна → `null`, не отбрасывается.
2. Разрыв между любыми полученными измерениями `> 20 с` либо ручная пауза → новый сегмент. **Расстояние через разрыв не начисляется** (линия не соединяется).
3. Скачок: вычисленная скорость `> 30 м/с` — точка отбрасывается; 5 скачков подряд — принимаются как начало нового сегмента.
4. Дрейф при неподвижности: смещение `< 3 м`, либо скорость `< 0,5 м/с` и смещение меньше accuracy — отбрасывается.
5. Расстояние — гаверсинус по принятым точкам одного сегмента (R = 6 371 008,8 м).
6. **Время движения** — сумма интервалов между соседними принятыми точками одного сегмента, где расстояние/время ≥ 0,8 м/с.
7. **Длительность** = (завершение − начало) − суммарное время ручных пауз. Простой при восстановлении после сбоя считается паузой.
8. **Средняя скорость** = расстояние / время движения; для периода — Σрасстояний / Σвремён движения (не среднее скоростей).
9. **Макс. скорость** — максимум скользящего среднего из 3 значений скорости (защита от выбросов), ограничено 30 м/с.
10. **Набор высоты** — скользящее среднее по 5 точкам + гистерезис 3 м; `null`, если высота есть менее чем у 80 % точек или точек < 10.

Тесты: `test/*.dart` (написаны, не запускались).

## Запись и устойчивость

`RecordingController`: `idle → recording ⇄ paused → finished`. Каждая принятая точка сразу вставляется в БД. `active_ride` обновляется при паузе/продолжении и каждые 15 с. После аварийного закрытия `HomeShell` предлагает продолжить (стартует в паузе), завершить или удалить; пропущенные точки не выдумываются. Отзыв разрешения / выключение геолокации не останавливают поездку: состояние GPS меняется, подписка восстанавливается каждые 5 с.

## Карта

`LocalTileServer` (127.0.0.1, случайный порт): `/style.json`, `/tiles/{z}/{x}/{y}.pbf` (MBTiles TMS → XYZ, gzip распаковывается), `/fonts/{stack}/{range}.pbf` (из assets). При нескольких картах приоритет у той, чьи границы содержат центр тайла. Слои поверх карты (GeoJSON): сохранённые треки (`#EFA7AB`, 3 px) → выбранный/текущий (`#F01428`, 5,5 px) → положение (точка с белой обводкой). Геометрия упрощается Дугласом–Пекером (4–6 м) в изоляте (`compute`).

## Задел на будущее (не реализовано)

Интерфейсы `RideRepository/SettingsRepository/CityMapRepository` позволяют добавить синхронизацию; домен без UI можно вынести в пакет для веба/iOS.
