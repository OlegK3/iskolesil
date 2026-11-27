/// Все настраиваемые адреса и константы приложения.
/// Сетевые адреса задаются при сборке: --dart-define=CATALOG_URL=https://...
/// По умолчанию приложение не обращается ни к каким внешним серверам.
class AppConfig {
  static const String appName = 'ИСКОЛЕСИЛ';
  static const String slogan = 'У каждой улицы — твоя история';
  static const String tagline = 'Велотрекер города';
  static const String version = '0.2.0';

  /// URL JSON-каталога карт городов (сервер в РФ). Пусто = только локальный каталог.
  static const String catalogUrl =
      String.fromEnvironment('CATALOG_URL', defaultValue: '');

  static const String defaultCityId = 'barnaul';
  static const String defaultCityName = 'Барнаул';
  static const double defaultCenterLat = 53.3548;
  static const double defaultCenterLon = 83.7698;
  static const double defaultZoom = 11.5;

  static const String mapAttribution =
      '© участники OpenStreetMap · схема OpenMapTiles';

  static const String storageChannel = 'ru.iskolesil/storage';
}
