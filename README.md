# ИСКОЛЕСИЛ — «У каждой улицы — твоя история»

GPS-трекер для велосипедистов: накопительная карта всех поездок, история, статистика, GPX.
Версия 0.3.0 (versionCode 3), Android. Flutter/Dart, Riverpod, SQLite, **карта — Яндекс MapKit (онлайн)**.

> **Статус честно.** Код этой версии написан без возможности скомпилировать и запустить его
> (в среде разработки нет Flutter/Android SDK и нет доступа к pub.dev). **Сборка, `flutter analyze`,
> тесты и работа на устройстве для v0.3 не проверялись.** Первая сборка в GitHub Actions может потребовать
> правок по логу. См. [docs/TESTING.md](docs/TESTING.md).

## Сборка APK на GitHub

1. В репозитории должен быть секрет **`YANDEX_MAPKIT_API_KEY`** (Settings → Secrets and variables → Actions).
   Для подписи release-APK используются секреты `ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`
   (см. [docs/SIGNING.md](docs/SIGNING.md)).
2. **Actions → Build APK** (запускается на push в `main` или вручную). Шаги: проверка секрета → `tool/bootstrap.sh`
   (Android-проект, MainApplication с ключом, иконка, подпись) → `flutter pub get` → аудит зависимостей → `analyze` → `test` → `build apk`.
3. Артефакт `iskolesil-apk` → `app-release.apk`.

Передача ключа MapKit и ограничения лицензии: [docs/MAPKIT.md](docs/MAPKIT.md).

### Локальная сборка (Android Studio)

Нужны Flutter stable, Java 21, Android SDK. В корне проекта создайте файл `mapkit.properties` (он в `.gitignore`):

    YANDEX_MAPKIT_API_KEY=ваш_ключ

Затем: `bash tool/bootstrap.sh && flutter pub get && flutter run`.

## Что реализовано

Главная · «Куда поедем?» · активная поездка (пауза/продолжение/завершение, фоновая запись) · «Где я» · «Моя карта» ·
история (карта поездки: масштаб, «весь маршрут», полный экран) · статистика · настройки · GPX импорт/экспорт · резервная копия ·
«О приложении». Данные хранятся только на устройстве.

## Известные ограничения

- Не собиралось и не тестировалось (см. выше).
- Фон карты загружается из интернета; без связи он может не отображаться, но запись трека идёт.
- Бесплатная лицензия MapKit имеет суточный лимит уникальных пользователей — см. docs/MAPKIT.md.
- Ключ мобильного SDK можно извлечь из готового APK.
- Построение маршрута до точки назначения отложено ([docs/ROUTING.md](docs/ROUTING.md)).
- Изображение маршрута для «поделиться» рисуется без фона карты.
- Минимальная версия Android — 8.0 (API 26), требование MapKit.

## Документы

[ARCHITECTURE](docs/ARCHITECTURE.md) · [DESIGN](docs/DESIGN.md) · [INFRASTRUCTURE](docs/INFRASTRUCTURE.md) · [MAPKIT](docs/MAPKIT.md) · [ROUTING](docs/ROUTING.md) · [SIGNING](docs/SIGNING.md) · [TESTING](docs/TESTING.md) · [LICENSES](docs/LICENSES.md) · [CHANGELOG](CHANGELOG.md)
