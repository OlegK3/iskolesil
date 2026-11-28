import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../core/config.dart';
import '../domain/track_accumulator.dart';

enum LocPermission { granted, denied, deniedForever, serviceDisabled }

/// Обёртка над geolocator. Foreground Service (тип location) запускается
/// самим geolocator при подписке на поток с foregroundNotificationConfig.
class LocationService {
  Future<LocPermission> check() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocPermission.serviceDisabled;
    }
    final p = await Geolocator.checkPermission();
    return _map(p);
  }

  Future<LocPermission> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocPermission.serviceDisabled;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return _map(p);
  }

  LocPermission _map(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocPermission.granted;
      case LocationPermission.deniedForever:
        return LocPermission.deniedForever;
      default:
        return LocPermission.denied;
    }
  }

  /// Уведомления нужны для отображения уведомления службы (Android 13+).
  /// Отказ не мешает записи.
  Future<void> requestNotificationPermission() async {
    try {
      await ph.Permission.notification.request();
    } catch (_) {}
  }

  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  Stream<Position> positionStream() {
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: AppConfig.appName,
        notificationText: 'Идёт запись поездки',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  /// Поток положения для экранов вне поездки (без Foreground Service и
  /// уведомления): только пока экран открыт.
  Stream<Position> previewStream() => Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 3),
      ));

  Stream<bool> serviceEnabledStream() => Geolocator.getServiceStatusStream()
      .map((s) => s == ServiceStatus.enabled);

  Future<Fix?> currentFix() async {
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10)));
      return toFix(p);
    } catch (_) {
      return null;
    }
  }

  /// Последнее известное положение без запроса разрешений и без ожидания
  /// спутников. null — если разрешения нет или положения ещё не было.
  Future<Fix?> lastKnown() async {
    try {
      if (await check() != LocPermission.granted) return null;
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : toFix(p);
    } catch (_) {
      return null;
    }
  }

  static Fix toFix(Position p) {
    final DateTime? ts = p.timestamp;
    return Fix(
      lat: p.latitude,
      lon: p.longitude,
      altitude: p.altitude,
      speed: p.speed < 0 ? null : p.speed,
      accuracy: p.accuracy <= 0 ? null : p.accuracy,
      time: (ts ?? DateTime.now()).toUtc(),
    );
  }
}
