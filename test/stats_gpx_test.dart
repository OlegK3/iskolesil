import 'package:flutter_test/flutter_test.dart';
import 'package:iskolesil/domain/gpx.dart';
import 'package:iskolesil/domain/models.dart';
import 'package:iskolesil/domain/stats.dart';

Ride ride(String id, double dist, int moving, double maxS,
    {DateTime? at, double? gain}) {
  final t = at ?? DateTime.utc(2026, 5, 1, 10);
  return Ride(
    id: id,
    title: id,
    startedAt: t,
    finishedAt: t.add(Duration(seconds: moving)),
    durationSeconds: moving,
    movingDurationSeconds: moving,
    distanceMeters: dist,
    averageSpeed: moving > 0 ? dist / moving : 0,
    maxSpeed: maxS,
    elevationGain: gain,
    status: RideStatus.finished,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  test('средняя скорость = сумма расстояний / сумма времени движения', () {
    // A: 10 км за 3600 с (2,78 м/с); B: 5 км за 600 с (8,33 м/с).
    // Среднее арифметическое скоростей дало бы 5,56 м/с — это неверно.
    final a = ride('a', 10000, 3600, 5);
    final b = ride('b', 5000, 600, 9);
    final s = StatsCalculator.compute([a, b]);
    expect(s.averageSpeed, closeTo(15000 / 4200, 1e-9));
    expect(s.maxSpeed, 9);
    expect(s.rideCount, 2);
    expect(s.longestByDistance!.id, 'a');
    expect(s.longestByDuration!.id, 'a');
  });

  test('набор высоты суммируется только по поездкам, где он известен', () {
    final s = StatsCalculator.compute([
      ride('a', 1000, 100, 5, gain: 20),
      ride('b', 1000, 100, 5),
    ]);
    expect(s.elevationGain, 20);
    expect(StatsCalculator.compute([ride('c', 1, 1, 1)]).elevationGain, isNull);
  });

  test('distanceByDay', () {
    final day = DateTime(2026, 5, 4);
    final r = ride('a', 5000, 100, 5, at: DateTime(2026, 5, 5, 12).toUtc());
    final list = StatsCalculator.distanceByDay([r], day, 7);
    expect(list.length, 7);
    expect(list[1].$2, 5000);
    expect(list[0].$2, 0);
  });

  group('GPX', () {
    final rideA = ride('a', 0, 0, 0);
    final pts = [
      for (var i = 0; i < 6; i++)
        TrackPoint(
          id: 'p$i',
          rideId: 'a',
          latitude: 53.0 + i * 0.0001,
          longitude: 83.0,
          altitude: i == 3 ? null : 150.0 + i,
          speed: 5.0,
          accuracy: 4.0,
          timestamp: DateTime.utc(2026, 5, 1, 10, 0, i * 2),
          segmentIndex: i < 3 ? 0 : 1,
        )
    ];

    test('экспорт → импорт сохраняет точки и сегменты', () {
      final xml = GpxCodec.export([(rideA, pts)]);
      expect(xml.contains('<gpx'), isTrue);
      final res = GpxCodec.parse(xml);
      expect(res.tracks.length, 1);
      final t = res.tracks.single;
      expect(t.points.length, 6);
      expect(t.points.first.segmentIndex, 0);
      expect(t.points.last.segmentIndex, 1);
      expect(t.points[3].altitude, isNull); // null не превращается в 0
      expect(t.points[0].speed, 5.0);
    });

    test('точки без времени пропускаются, без точек — ошибка', () {
      const bad = '<gpx version="1.1"><trk><trkseg>'
          '<trkpt lat="53" lon="83"></trkpt>'
          '<trkpt lat="53.1" lon="83"></trkpt>'
          '</trkseg></trk></gpx>';
      expect(() => GpxCodec.parse(bad), throwsFormatException);
    });

    test('не GPX — ошибка', () {
      expect(() => GpxCodec.parse('<foo/>'), throwsFormatException);
      expect(() => GpxCodec.parse('не xml'), throwsFormatException);
    });

    test('некорректные координаты пропускаются', () {
      const x = '<gpx version="1.1"><trk><trkseg>'
          '<trkpt lat="53" lon="83"><time>2026-05-01T10:00:00Z</time></trkpt>'
          '<trkpt lat="95" lon="83"><time>2026-05-01T10:00:01Z</time></trkpt>'
          '<trkpt lat="53.0003" lon="83"><time>2026-05-01T10:00:05Z</time></trkpt>'
          '</trkseg></trk></gpx>';
      final r = GpxCodec.parse(x);
      expect(r.skippedPoints, 1);
      expect(r.tracks.single.points.length, 2);
    });
  });
}
