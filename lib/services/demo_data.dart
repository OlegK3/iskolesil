import 'dart:math';

import '../domain/models.dart';
import '../domain/track_accumulator.dart';

/// Демонстрационные данные. Синтетические, держатся только в памяти,
/// НИКОГДА не записываются в БД и не участвуют в реальной статистике.
/// Маршруты не следуют дорожной сети.
class DemoRide {
  final Ride ride;
  final List<TrackPoint> points;
  final bool isDinosaur;
  const DemoRide(this.ride, this.points, {this.isDinosaur = false});
}

class DemoData {
  static const _centerLat = 53.3548;
  static const _centerLon = 83.7698;

  // Контур динозавра в условных единицах (1 ед. ≈ 100 м), x вправо, y вверх.
  static const _dino = <List<double>>[
    [0, 9], [6, 10], [12, 12], [15, 16], [20, 18], [25, 19], [28, 22], [30, 25],
    [35, 26], [38, 24], [38, 22], [34, 21], [31, 20], [30, 17], [29, 14],
    [31, 12], [29, 11], [27, 10], [26, 6], [28, 3], [24, 3], [22, 7], [19, 7],
    [17, 3], [13, 3], [15, 8], [13, 10], [9, 9], [4, 8], [0, 9],
  ];

  static List<DemoRide> build({DateTime? now}) {
    final base = (now ?? DateTime.now()).toUtc();
    final rides = <DemoRide>[];
    final loops = [
      ('Демо: набережная Оби', -0.012, 0.0, 0.020, 0.010, 3),
      ('Демо: Центральный район', 0.002, 0.004, 0.012, 0.008, 5),
      ('Демо: Пригородный круг', -0.03, -0.035, 0.045, 0.030, 8),
    ];
    for (var i = 0; i < loops.length; i++) {
      final l = loops[i];
      final pts = _ellipse(
          'demo-$i', _centerLat + l.$2, _centerLon + l.$3, l.$4, l.$5, l.$6.toDouble(),
          base.subtract(Duration(days: (i + 1) * 3)), speed: 5.0 + i);
      rides.add(DemoRide(_makeRide('demo-$i', l.$1, pts), pts));
    }
    final dino = _dinoPoints('demo-dino', base.subtract(const Duration(days: 1)));
    rides.add(DemoRide(_makeRide('demo-dino', 'Демо: динозавр (GPS Art)', dino), dino,
        isDinosaur: true));
    return rides;
  }

  static Ride _makeRide(String id, String title, List<TrackPoint> pts) {
    final m = TrackAccumulator.fromPoints(pts);
    final s = pts.first.timestamp, e = pts.last.timestamp;
    return Ride(
      id: id,
      title: title,
      description: 'Демонстрационные данные. Не отражают реальные поездки.',
      startedAt: s,
      finishedAt: e,
      durationSeconds: e.difference(s).inSeconds,
      movingDurationSeconds: m.movingSeconds,
      distanceMeters: m.distanceMeters,
      averageSpeed: m.averageSpeed,
      maxSpeed: m.maxSpeed,
      elevationGain: null,
      status: RideStatus.finished,
      createdAt: s,
      updatedAt: s,
    );
  }

  static List<TrackPoint> _ellipse(String id, double lat0, double lon0,
      double rLat, double rLon, double wobble, DateTime start,
      {required double speed}) {
    final pts = <TrackPoint>[];
    const n = 400;
    var t = start;
    LatLon? prev;
    for (var i = 0; i <= n; i++) {
      final a = i / n * 2 * pi;
      final k = 1 + 0.12 * sin(a * wobble);
      final p = LatLon(lat0 + rLat * k * sin(a), lon0 + rLon * k * cos(a));
      if (prev != null) {
        final d = _dist(prev, p);
        t = t.add(Duration(milliseconds: (d / speed * 1000).round()));
      }
      pts.add(TrackPoint(
          id: '$id-$i',
          rideId: id,
          latitude: p.lat,
          longitude: p.lon,
          speed: speed,
          accuracy: 5,
          timestamp: t,
          segmentIndex: 0));
      prev = p;
    }
    return pts;
  }

  static List<TrackPoint> _dinoPoints(String id, DateTime start) {
    // 1 ед. = 100 м; центрируем контур около центра города.
    const mLat = 110540.0;
    final mLon = 111320.0 * cos(_centerLat * pi / 180);
    final path = <LatLon>[
      for (final p in _dino)
        LatLon(_centerLat + (p[1] - 14) * 100 / mLat, _centerLon + (p[0] - 19) * 100 / mLon)
    ];
    final pts = <TrackPoint>[];
    var t = start;
    var n = 0;
    const speed = 5.5;
    for (var i = 1; i < path.length; i++) {
      final a = path[i - 1], b = path[i];
      final d = _dist(a, b);
      final steps = max(1, (d / 20).ceil());
      for (var k = (i == 1 ? 0 : 1); k <= steps; k++) {
        final f = k / steps;
        t = t.add(Duration(milliseconds: (d / steps / speed * 1000).round()));
        pts.add(TrackPoint(
            id: '$id-${n++}',
            rideId: id,
            latitude: a.lat + (b.lat - a.lat) * f,
            longitude: a.lon + (b.lon - a.lon) * f,
            speed: speed,
            accuracy: 5,
            timestamp: t,
            segmentIndex: 0));
      }
    }
    return pts;
  }

  static double _dist(LatLon a, LatLon b) {
    final kx = 111320.0 * cos(a.lat * pi / 180);
    final dx = (b.lon - a.lon) * kx, dy = (b.lat - a.lat) * 110540.0;
    return sqrt(dx * dx + dy * dy);
  }
}
