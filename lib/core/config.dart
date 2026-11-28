/// Константы приложения.
/// Карта — онлайн, Яндекс MapKit. Ключ MapKit в код не вшит: он передаётся
/// при сборке (см. docs/MAPKIT.md).
class AppConfig {
  static const String appName = 'ИСКОЛЕСИЛ';
  static const String slogan = 'У каждой улицы — твоя история';
  static const String tagline = 'Велотрекер города';
  static const String version = '0.3.0';

  /// Вид карты, пока положение пользователя неизвестно: вся страна,
  /// без привязки к конкретному городу.
  static const double fallbackLat = 61.5;
  static const double fallbackLon = 99.5;
  static const double fallbackZoom = 3;
}
