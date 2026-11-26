import 'package:flutter_test/flutter_test.dart';
import 'package:iskolesil/domain/models.dart';
import 'package:iskolesil/domain/track_accumulator.dart';

final _t0 = DateTime.utc(2026, 5, 1, 10);

Fix fix(int sec, double lat, double lon,
        {double? acc = 5, double? speed, double? alt}) =>
    Fix(
        lat: lat,
        lon: lon,
        accuracy: acc,
        speed: speed,
        altitude: alt,
        time: _t0.add(Duration(seconds: sec)));

void main() {
  test('равномерное движение: расстояние и время движения', () {
    final a = TrackAccumulator();
    // ~5.5 м/с на север (0.00005° ≈ 5.55 м за секунду)
    for (var i = 0; i <= 60; i++) {
      a.add(fix(i, 53.0 + i * 0.00005, 83.0, speed: 5.5));
    }
    expect(a.distanceMeters, closeTo(333, 5));
    expect(a.movingSeconds, closeTo(60, 1));
    expect(a.maxSpeed, closeTo(5.5, 0.2));
    expect(a.segmentIndex, 0);
  });

  test('плохая точность отбрасывается', () {
    final a = TrackAccumulator();
    a.add(fix(0, 53.0, 83.0));
    final r = a.add(fix(1, 53.0001, 83.0, acc: 80));
    expect(r.decision, FixDecision.rejectedAccuracy);
    expect(a.distanceMeters, 0);
  });

  test('скачок отбрасывается, расстояние не растёт', () {
    final a = TrackAccumulator();
    a.add(fix(0, 53.0, 83.0));
    final r = a.add(fix(1, 53.01, 83.0)); // ~1.1 км за 1 с
    expect(r.decision, FixDecision.rejectedJump);
    expect(a.distanceMeters, 0);
  });

  test('дрейф при неподвижности не накапливает километраж', () {
    final a = TrackAccumulator();
    a.add(fix(0, 53.0, 83.0, speed: 0));
    for (var i = 1; i <= 120; i++) {
      // шум ±1 м
      a.add(fix(i, 53.0 + (i.isEven ? 0.00001 : -0.00001), 83.0, speed: 0.1));
    }
    expect(a.distanceMeters, lessThan(1));
    expect(a.movingSeconds, 0);
  });

  test('разрыв сигнала > 20 с создаёт новый сегмент без прямой линии', () {
    final a = TrackAccumulator();
    for (var i = 0; i < 10; i++) {
      a.add(fix(i, 53.0 + i * 0.00005, 83.0, speed: 5.5));
    }
    final before = a.distanceMeters;
    final r = a.add(fix(60, 53.02, 83.0, speed: 5.5)); // 50 с тишины, +2 км
    expect(r.decision, FixDecision.acceptedNewSegment);
    expect(r.segmentIndex, 1);
    expect(a.distanceMeters, before);
  });

  test('breakSegment (пауза) начинает новый сегмент', () {
    final a = TrackAccumulator();
    a.add(fix(0, 53.0, 83.0));
    a.add(fix(1, 53.00005, 83.0, speed: 5));
    a.breakSegment();
    final r = a.add(fix(2, 53.001, 83.0));
    expect(r.segmentIndex, 1);
    expect(a.distanceMeters, closeTo(5.5, 1));
  });

  test('набор высоты: шум меньше порога игнорируется', () {
    final a = TrackAccumulator();
    for (var i = 0; i < 40; i++) {
      a.add(fix(i, 53.0 + i * 0.00005, 83.0,
          speed: 5.5, alt: 100 + (i.isEven ? 0.5 : -0.5)));
    }
    expect(a.elevationGain, lessThan(2));
  });

  test('набор высоты: подъём 20 м учитывается', () {
    final a = TrackAccumulator();
    for (var i = 0; i < 40; i++) {
      a.add(fix(i, 53.0 + i * 0.00005, 83.0, speed: 5.5, alt: 100 + i * 0.5));
    }
    expect(a.elevationGain, closeTo(18, 4));
  });

  test('набор высоты null без высот', () {
    final a = TrackAccumulator();
    for (var i = 0; i < 40; i++) {
      a.add(fix(i, 53.0 + i * 0.00005, 83.0, speed: 5.5));
    }
    expect(a.elevationGain, isNull);
  });

  test('fromPoints совпадает с онлайн-накоплением', () {
    final pts = <TrackPoint>[
      for (var i = 0; i < 30; i++)
        TrackPoint(
          id: '$i',
          rideId: 'r',
          latitude: 53.0 + i * 0.00005,
          longitude: 83.0,
          speed: 5.5,
          timestamp: _t0.add(Duration(seconds: i)),
          segmentIndex: i < 15 ? 0 : 1,
        )
    ];
    final m = TrackAccumulator.fromPoints(pts);
    // 29 интервалов, один из них через границу сегментов не считается
    expect(m.distanceMeters, closeTo(28 * 5.55, 3));
  });
}
