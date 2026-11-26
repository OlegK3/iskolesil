import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/sqlite_repositories.dart';
import 'domain/geo.dart';
import 'domain/models.dart';
import 'domain/repositories.dart';
import 'services/data_exchange.dart';
import 'services/location_service.dart';
import 'services/map/city_map_service.dart';
import 'services/map/mbtiles_server.dart';

// ---- Инфраструктура (переопределяется в main) ----
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());
final initialSettingsProvider =
    Provider<AppSettings>((ref) => throw UnimplementedError());

final rideRepoProvider =
    Provider<RideRepository>((ref) => SqliteRideRepository(ref.watch(databaseProvider)));
final settingsRepoProvider = Provider<SettingsRepository>(
    (ref) => SqliteSettingsRepository(ref.watch(databaseProvider)));
final cityRepoProvider = Provider<CityMapRepository>(
    (ref) => SqliteCityMapRepository(ref.watch(databaseProvider)));

final exchangeProvider = Provider<DataExchangeService>(
    (ref) => DataExchangeService(ref.watch(rideRepoProvider)));
final locationServiceProvider = Provider<LocationService>((ref) => LocationService());
final cityMapServiceProvider = Provider<CityMapService>(
    (ref) => CityMapService(ref.watch(cityRepoProvider)));

// ---- Ревизии данных: инкремент = перечитать зависимые провайдеры ----
final rideRevisionProvider = StateProvider<int>((ref) => 0);
final mapRevisionProvider = StateProvider<int>((ref) => 0);

void bumpRides(WidgetRef ref) => ref.read(rideRevisionProvider.notifier).state++;
void bumpMaps(WidgetRef ref) => ref.read(mapRevisionProvider.notifier).state++;

// ---- Настройки ----
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  Future<void> update(AppSettings Function(AppSettings) f) async {
    state = f(state);
    await ref.read(settingsRepoProvider).save(state);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---- Поездки ----
final ridesProvider = FutureProvider<List<Ride>>((ref) {
  ref.watch(rideRevisionProvider);
  return ref.watch(rideRepoProvider).listFinished();
});

final rideProvider = FutureProvider.family<Ride?, String>((ref, id) {
  ref.watch(rideRevisionProvider);
  return ref.watch(rideRepoProvider).getRide(id);
});

final ridePointsProvider =
    FutureProvider.family<List<TrackPoint>, String>((ref, id) {
  return ref.watch(rideRepoProvider).getPoints(id);
});

List<List<LatLon>> _simplifyAll(List<List<LatLon>> segs) =>
    [for (final s in segs) simplify(s, 4)];

/// Упрощённая геометрия одной поездки (для карты и миниатюр).
final rideSegmentsProvider =
    FutureProvider.family<List<List<LatLon>>, String>((ref, id) async {
  final pts = await ref.watch(ridePointsProvider(id).future);
  return compute(_simplifyAll, groupSegments(pts));
});

Map<String, List<List<LatLon>>> _simplifyMap(Map<String, List<List<LatLon>>> m) =>
    {for (final e in m.entries) e.key: [for (final s in e.value) simplify(s, 6)]};

/// Геометрия всех завершённых поездок для общей карты.
final allSegmentsProvider =
    FutureProvider<Map<String, List<List<LatLon>>>>((ref) async {
  final rides = await ref.watch(ridesProvider.future);
  final raw = await ref
      .watch(rideRepoProvider)
      .loadSegments(rides.map((r) => r.id).toSet());
  return compute(_simplifyMap, raw);
});

// ---- Карты ----
final installedCitiesProvider = FutureProvider<List<CityMap>>((ref) {
  ref.watch(mapRevisionProvider);
  return ref.watch(cityRepoProvider).list();
});

final tileServerProvider = Provider<LocalTileServer>((ref) {
  final s = LocalTileServer();
  ref.onDispose(s.stop);
  return s;
});

/// URL стиля локального сервера; меняется при смене набора карт.
final styleUrlProvider = FutureProvider<String>((ref) async {
  final cities = await ref.watch(installedCitiesProvider.future);
  final server = ref.watch(tileServerProvider);
  await server.start();
  await server.setMaps([
    for (final c in cities)
      if (c.installationStatus == InstallStatus.installed) (c.localPath, c.bounds)
  ]);
  return server.styleUrl;
});
