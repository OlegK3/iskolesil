import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/sqlite_repositories.dart';
import 'domain/geo.dart';
import 'domain/models.dart';
import 'domain/repositories.dart';
import 'services/data_exchange.dart';
import 'services/location_service.dart';

// ---- Инфраструктура (переопределяется в main) ----
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());
final initialSettingsProvider =
    Provider<AppSettings>((ref) => throw UnimplementedError());

final rideRepoProvider =
    Provider<RideRepository>((ref) => SqliteRideRepository(ref.watch(databaseProvider)));
final settingsRepoProvider = Provider<SettingsRepository>(
    (ref) => SqliteSettingsRepository(ref.watch(databaseProvider)));

final exchangeProvider = Provider<DataExchangeService>(
    (ref) => DataExchangeService(ref.watch(rideRepoProvider)));
final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

// ---- Ревизии данных: инкремент = перечитать зависимые провайдеры ----
final rideRevisionProvider = StateProvider<int>((ref) => 0);

void bumpRides(WidgetRef ref) => ref.read(rideRevisionProvider.notifier).state++;

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
