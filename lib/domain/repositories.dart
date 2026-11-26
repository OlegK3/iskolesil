import 'models.dart';

/// Интерфейсы репозиториев. Реализации — в lib/data. Бизнес-логика
/// зависит только от этих интерфейсов (задел под синхронизацию/веб).
abstract class RideRepository {
  Future<void> insertRide(Ride ride);
  Future<void> updateRide(Ride ride);
  Future<Ride?> getRide(String id);

  /// Завершённые поездки, новые первыми.
  Future<List<Ride>> listFinished();

  /// Поездка со статусом recording/paused (после аварийного закрытия).
  Future<Ride?> findUnfinished();

  Future<void> deleteRide(String id); // точки удаляются каскадом
  Future<void> deleteAllRides();

  Future<void> addPoint(TrackPoint point);
  Future<List<TrackPoint>> getPoints(String rideId);

  /// Лёгкая загрузка геометрии всех завершённых поездок для общей карты.
  Future<Map<String, List<List<LatLon>>>> loadSegments(Set<String> rideIds);

  /// Атомарная вставка поездки с точками (импорт/восстановление).
  Future<void> insertRideWithPoints(Ride ride, List<TrackPoint> points);
  Future<bool> rideExists(String id);
}

abstract class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
  Future<String?> getRaw(String key);
  Future<void> setRaw(String key, String? value);
}

abstract class CityMapRepository {
  Future<List<CityMap>> list();
  Future<CityMap?> get(String id);
  Future<void> upsert(CityMap map);
  Future<void> delete(String id);
}
