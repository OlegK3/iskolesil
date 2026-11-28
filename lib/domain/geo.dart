import 'dart:math';

import 'models.dart';

const double _earthRadius = 6371008.8; // м, средний радиус (IUGG)

double _rad(double d) => d * pi / 180.0;

/// Геодезическое расстояние по формуле гаверсинусов, метры.
double haversine(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = pow(sin(dLat / 2), 2) +
      cos(_rad(lat1)) * cos(_rad(lat2)) * pow(sin(dLon / 2), 2);
  return 2 * _earthRadius * asin(min(1.0, sqrt(a)));
}

double distanceBetween(LatLon a, LatLon b) =>
    haversine(a.lat, a.lon, b.lat, b.lon);

/// Длина полилинии в метрах.
double polylineLength(List<LatLon> pts) {
  var d = 0.0;
  for (var i = 1; i < pts.length; i++) {
    d += distanceBetween(pts[i - 1], pts[i]);
  }
  return d;
}

/// Упрощение полилинии (Дуглас–Пекер, итеративно) в локальной
/// эквиректангулярной проекции. [toleranceM] — допуск в метрах.
List<LatLon> simplify(List<LatLon> pts, double toleranceM) {
  if (pts.length < 3 || toleranceM <= 0) return List.of(pts);
  final lat0 = pts.first.lat;
  final kx = 111320.0 * cos(_rad(lat0));
  const ky = 110540.0;
  final xs = List<double>.generate(pts.length, (i) => pts[i].lon * kx);
  final ys = List<double>.generate(pts.length, (i) => pts[i].lat * ky);
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <List<int>>[
    [0, pts.length - 1]
  ];
  final tol2 = toleranceM * toleranceM;
  while (stack.isNotEmpty) {
    final seg = stack.removeLast();
    final s = seg[0], e = seg[1];
    if (e <= s + 1) continue;
    var maxD = -1.0;
    var idx = -1;
    final dx = xs[e] - xs[s];
    final dy = ys[e] - ys[s];
    final len2 = dx * dx + dy * dy;
    for (var i = s + 1; i < e; i++) {
      double d2;
      if (len2 == 0) {
        final px = xs[i] - xs[s], py = ys[i] - ys[s];
        d2 = px * px + py * py;
      } else {
        var t = ((xs[i] - xs[s]) * dx + (ys[i] - ys[s]) * dy) / len2;
        t = t.clamp(0.0, 1.0).toDouble();
        final px = xs[s] + t * dx - xs[i];
        final py = ys[s] + t * dy - ys[i];
        d2 = px * px + py * py;
      }
      if (d2 > maxD) {
        maxD = d2;
        idx = i;
      }
    }
    if (maxD > tol2 && idx != -1) {
      keep[idx] = true;
      stack.add([s, idx]);
      stack.add([idx, e]);
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i]
  ];
}

/// Группирует точки по сегментам (в порядке времени).
List<List<LatLon>> groupSegments(List<TrackPoint> points) {
  final out = <List<LatLon>>[];
  int? seg;
  for (final p in points) {
    if (seg == null || p.segmentIndex != seg) {
      out.add(<LatLon>[]);
      seg = p.segmentIndex;
    }
    out.last.add(p.latLon);
  }
  return out;
}

GeoBounds? boundsOfSegments(Iterable<List<LatLon>> segments) =>
    GeoBounds.fromPoints(segments.expand((s) => s));

/// Убирает из начала и конца маршрута [meters] метров (приватность).
/// Если маршрут короче 2*meters, возвращает пустой список.
List<List<LatLon>> trimEnds(List<List<LatLon>> segments, double meters) {
  if (meters <= 0) return segments;
  final flat = <(int, LatLon)>[];
  for (var s = 0; s < segments.length; s++) {
    for (final p in segments[s]) {
      flat.add((s, p));
    }
  }
  if (flat.length < 2) return [];
  final cum = List<double>.filled(flat.length, 0);
  for (var i = 1; i < flat.length; i++) {
    cum[i] = cum[i - 1] +
        (flat[i].$1 == flat[i - 1].$1
            ? distanceBetween(flat[i - 1].$2, flat[i].$2)
            : 0);
  }
  final total = cum.last;
  if (total <= meters * 2) return [];
  final out = <List<LatLon>>[];
  int? cur;
  for (var i = 0; i < flat.length; i++) {
    if (cum[i] < meters || cum[i] > total - meters) continue;
    if (cur != flat[i].$1 || out.isEmpty) {
      out.add(<LatLon>[]);
      cur = flat[i].$1;
    }
    out.last.add(flat[i].$2);
  }
  return out;
}

/// Расстояние (м) от точки до полилинии (приближённо, через ближайшие
/// отрезки в локальной проекции).
double distanceToPolyline(LatLon p, List<LatLon> line) {
  if (line.isEmpty) return double.infinity;
  final kx = 111320.0 * cos(_rad(p.lat));
  const ky = 110540.0;
  double best = double.infinity;
  for (var i = 0; i < line.length; i++) {
    final ax = (line[i].lon - p.lon) * kx;
    final ay = (line[i].lat - p.lat) * ky;
    if (i == 0 || line.length == 1) {
      best = min(best, sqrt(ax * ax + ay * ay));
    }
    if (i + 1 < line.length) {
      final bx = (line[i + 1].lon - p.lon) * kx;
      final by = (line[i + 1].lat - p.lat) * ky;
      final dx = bx - ax, dy = by - ay;
      final l2 = dx * dx + dy * dy;
      var t = l2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / l2);
      t = t.clamp(0.0, 1.0).toDouble();
      final cx = ax + t * dx, cy = ay + t * dy;
      best = min(best, sqrt(cx * cx + cy * cy));
    }
  }
  return best;
}
