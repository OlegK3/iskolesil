import 'package:flutter_test/flutter_test.dart';
import 'package:iskolesil/domain/geo.dart';
import 'package:iskolesil/domain/models.dart';

void main() {
  test('haversine: 1 градус широты ≈ 111.2 км', () {
    final d = haversine(53.0, 83.0, 54.0, 83.0);
    expect(d, closeTo(111195, 300));
  });

  test('haversine: нулевое расстояние', () {
    expect(haversine(53.3, 83.7, 53.3, 83.7), 0);
  });

  test('simplify сохраняет концы и убирает коллинеарные точки', () {
    final pts = [
      for (var i = 0; i <= 10; i++) LatLon(53.0 + i * 0.0001, 83.0),
    ];
    final s = simplify(pts, 2);
    expect(s.length, 2);
    expect(s.first, pts.first);
    expect(s.last, pts.last);
  });

  test('simplify сохраняет излом', () {
    final pts = [
      const LatLon(53.0, 83.0),
      const LatLon(53.0, 83.001),
      const LatLon(53.001, 83.001),
    ];
    expect(simplify(pts, 2).length, 3);
  });

  test('trimEnds: короткий маршрут скрывается целиком', () {
    final seg = [
      [const LatLon(53.0, 83.0), const LatLon(53.0005, 83.0)]
    ];
    expect(trimEnds(seg, 300), isEmpty);
  });

  test('trimEnds обрезает начало и конец', () {
    final seg = [
      [for (var i = 0; i <= 100; i++) LatLon(53.0 + i * 0.0001, 83.0)]
    ];
    final t = trimEnds(seg, 200); // ~1.1 км маршрут
    expect(t.single.length, lessThan(101));
    expect(t.single.first.lat, greaterThan(53.0));
    expect(t.single.last.lat, lessThan(53.01));
  });

  test('distanceToPolyline', () {
    final line = [const LatLon(53.0, 83.0), const LatLon(53.0, 83.01)];
    final d = distanceToPolyline(const LatLon(53.0009, 83.005), line);
    expect(d, closeTo(100, 5));
  });
}
