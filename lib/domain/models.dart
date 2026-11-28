import 'dart:convert';

enum RideStatus { recording, paused, finished }

enum MeasurementUnits { metric, imperial }

class LatLon {
  final double lat;
  final double lon;
  const LatLon(this.lat, this.lon);

  @override
  bool operator ==(Object other) =>
      other is LatLon && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'LatLon($lat, $lon)';
}

class GeoBounds {
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;
  const GeoBounds(this.minLat, this.minLon, this.maxLat, this.maxLon);

  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  LatLon get center => LatLon((minLat + maxLat) / 2, (minLon + maxLon) / 2);

  static GeoBounds? fromPoints(Iterable<LatLon> pts) {
    double? minLat, minLon, maxLat, maxLon;
    for (final p in pts) {
      minLat = minLat == null || p.lat < minLat ? p.lat : minLat;
      maxLat = maxLat == null || p.lat > maxLat ? p.lat : maxLat;
      minLon = minLon == null || p.lon < minLon ? p.lon : minLon;
      maxLon = maxLon == null || p.lon > maxLon ? p.lon : maxLon;
    }
    if (minLat == null) return null;
    return GeoBounds(minLat, minLon!, maxLat!, maxLon!);
  }

  GeoBounds union(GeoBounds o) => GeoBounds(
        minLat < o.minLat ? minLat : o.minLat,
        minLon < o.minLon ? minLon : o.minLon,
        maxLat > o.maxLat ? maxLat : o.maxLat,
        maxLon > o.maxLon ? maxLon : o.maxLon,
      );
}

/// Точка трека. Необязательные значения — null (ничего не выдумываем).
class TrackPoint {
  final String id;
  final String rideId;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double? speed; // м/с
  final double? accuracy; // м
  final DateTime timestamp; // UTC
  final int segmentIndex;

  const TrackPoint({
    required this.id,
    required this.rideId,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.speed,
    this.accuracy,
    required this.timestamp,
    required this.segmentIndex,
  });

  LatLon get latLon => LatLon(latitude, longitude);
}

class Ride {
  final String id;
  final String title;
  final String description;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int durationSeconds;
  final int movingDurationSeconds;
  final double distanceMeters;
  final double averageSpeed; // м/с = distance / movingDuration
  final double maxSpeed; // м/с
  final double? elevationGain; // м, null если данные недостоверны
  final RideStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Ride({
    required this.id,
    required this.title,
    this.description = '',
    required this.startedAt,
    this.finishedAt,
    this.durationSeconds = 0,
    this.movingDurationSeconds = 0,
    this.distanceMeters = 0,
    this.averageSpeed = 0,
    this.maxSpeed = 0,
    this.elevationGain,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  Ride copyWith({
    String? title,
    String? description,
    DateTime? finishedAt,
    int? durationSeconds,
    int? movingDurationSeconds,
    double? distanceMeters,
    double? averageSpeed,
    double? maxSpeed,
    double? elevationGain,
    bool clearElevation = false,
    RideStatus? status,
    DateTime? updatedAt,
  }) =>
      Ride(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        movingDurationSeconds:
            movingDurationSeconds ?? this.movingDurationSeconds,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        averageSpeed: averageSpeed ?? this.averageSpeed,
        maxSpeed: maxSpeed ?? this.maxSpeed,
        elevationGain:
            clearElevation ? null : (elevationGain ?? this.elevationGain),
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );
}

class TrackingConfig {
  final double maxAccuracyM;
  final double maxJumpSpeedMs;
  final double minMoveM;
  final double driftSpeedMs;
  final double movingSpeedMs;
  final int gapSeconds;
  final int maxConsecutiveJumps;
  final double elevationThresholdM;
  final int elevationWindow;

  const TrackingConfig({
    this.maxAccuracyM = 30,
    this.maxJumpSpeedMs = 30,
    this.minMoveM = 3,
    this.driftSpeedMs = 0.5,
    this.movingSpeedMs = 0.8,
    this.gapSeconds = 20,
    this.maxConsecutiveJumps = 5,
    this.elevationThresholdM = 3,
    this.elevationWindow = 5,
  });

  Map<String, dynamic> toJson() => {
        'maxAccuracyM': maxAccuracyM,
        'maxJumpSpeedMs': maxJumpSpeedMs,
        'minMoveM': minMoveM,
        'driftSpeedMs': driftSpeedMs,
        'movingSpeedMs': movingSpeedMs,
        'gapSeconds': gapSeconds,
        'maxConsecutiveJumps': maxConsecutiveJumps,
        'elevationThresholdM': elevationThresholdM,
        'elevationWindow': elevationWindow,
      };

  factory TrackingConfig.fromJson(Map<String, dynamic> j) {
    const d = TrackingConfig();
    double n(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    int i(String k, int def) => (j[k] as num?)?.toInt() ?? def;
    return TrackingConfig(
      maxAccuracyM: n('maxAccuracyM', d.maxAccuracyM),
      maxJumpSpeedMs: n('maxJumpSpeedMs', d.maxJumpSpeedMs),
      minMoveM: n('minMoveM', d.minMoveM),
      driftSpeedMs: n('driftSpeedMs', d.driftSpeedMs),
      movingSpeedMs: n('movingSpeedMs', d.movingSpeedMs),
      gapSeconds: i('gapSeconds', d.gapSeconds),
      maxConsecutiveJumps: i('maxConsecutiveJumps', d.maxConsecutiveJumps),
      elevationThresholdM: n('elevationThresholdM', d.elevationThresholdM),
      elevationWindow: i('elevationWindow', d.elevationWindow),
    );
  }
}

class AppSettings {
  final String mapStyle;
  final bool showPreviousRoutes;
  final MeasurementUnits measurementUnits;
  final TrackingConfig trackingSettings;
  final bool wifiOnlyDownloads;
  final String currentCityId;
  final Set<String> hiddenRideIds;
  final int schemaVersion;

  const AppSettings({
    this.mapStyle = 'mono',
    this.showPreviousRoutes = true,
    this.measurementUnits = MeasurementUnits.metric,
    this.trackingSettings = const TrackingConfig(),
    this.wifiOnlyDownloads = true,
    this.currentCityId = '',
    this.hiddenRideIds = const {},
    this.schemaVersion = 1,
  });

  AppSettings copyWith({
    String? mapStyle,
    bool? showPreviousRoutes,
    MeasurementUnits? measurementUnits,
    TrackingConfig? trackingSettings,
    bool? wifiOnlyDownloads,
    String? currentCityId,
    Set<String>? hiddenRideIds,
    int? schemaVersion,
  }) =>
      AppSettings(
        mapStyle: mapStyle ?? this.mapStyle,
        showPreviousRoutes: showPreviousRoutes ?? this.showPreviousRoutes,
        measurementUnits: measurementUnits ?? this.measurementUnits,
        trackingSettings: trackingSettings ?? this.trackingSettings,
        wifiOnlyDownloads: wifiOnlyDownloads ?? this.wifiOnlyDownloads,
        currentCityId: currentCityId ?? this.currentCityId,
        hiddenRideIds: hiddenRideIds ?? this.hiddenRideIds,
        schemaVersion: schemaVersion ?? this.schemaVersion,
      );

  Map<String, String> toKeyValues() => {
        'mapStyle': mapStyle,
        'showPreviousRoutes': showPreviousRoutes ? '1' : '0',
        'measurementUnits': measurementUnits.name,
        'trackingSettings': jsonEncode(trackingSettings.toJson()),
        'wifiOnlyDownloads': wifiOnlyDownloads ? '1' : '0',
        'currentCityId': currentCityId,
        'hiddenRideIds': jsonEncode(hiddenRideIds.toList()),
        'schemaVersion': schemaVersion.toString(),
      };

  factory AppSettings.fromKeyValues(Map<String, String> kv) {
    const d = AppSettings();
    TrackingConfig tc = const TrackingConfig();
    try {
      final raw = kv['trackingSettings'];
      if (raw != null) {
        tc = TrackingConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    Set<String> hidden = {};
    try {
      final raw = kv['hiddenRideIds'];
      if (raw != null) {
        hidden = (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return AppSettings(
      mapStyle: kv['mapStyle'] ?? d.mapStyle,
      showPreviousRoutes: (kv['showPreviousRoutes'] ?? '1') == '1',
      measurementUnits: kv['measurementUnits'] == 'imperial'
          ? MeasurementUnits.imperial
          : MeasurementUnits.metric,
      trackingSettings: tc,
      wifiOnlyDownloads: (kv['wifiOnlyDownloads'] ?? '1') == '1',
      currentCityId: kv['currentCityId'] ?? '',
      hiddenRideIds: hidden,
      schemaVersion: int.tryParse(kv['schemaVersion'] ?? '') ?? 1,
    );
  }
}
