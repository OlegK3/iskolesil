import 'package:xml/xml.dart';

import '../core/ids.dart';
import 'models.dart';
import 'track_accumulator.dart';

const _gpxNs = 'http://www.topografix.com/GPX/1/1';
const _iskNs = 'urn:iskolesil:gpx:1';

class ParsedTrack {
  final String name;
  final String description;
  final List<TrackPoint> points; // rideId заполнен
  final Ride ride;
  ParsedTrack(this.name, this.description, this.points, this.ride);
}

class GpxParseResult {
  final List<ParsedTrack> tracks;
  final int skippedPoints;
  final List<String> warnings;
  GpxParseResult(this.tracks, this.skippedPoints, this.warnings);
}

class GpxCodec {
  /// Экспорт одной или нескольких поездок в GPX 1.1.
  /// Каждая поездка — отдельный <trk>, каждый сегмент — <trkseg>.
  static String export(List<(Ride, List<TrackPoint>)> rides) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element('gpx', nest: () {
      b.attribute('version', '1.1');
      b.attribute('creator', 'ИСКОЛЕСИЛ');
      b.namespace(_gpxNs);
      b.namespace(_iskNs, 'isk');
      for (final (ride, pts) in rides) {
        b.element('trk', nest: () {
          b.element('name', nest: ride.title);
          if (ride.description.isNotEmpty) {
            b.element('desc', nest: ride.description);
          }
          // Группировка по сегментам: каждый сегмент — отдельный <trkseg>.
          final segs = <int, List<TrackPoint>>{};
          for (final p in pts) {
            segs.putIfAbsent(p.segmentIndex, () => []).add(p);
          }
          for (final entry in segs.entries) {
            b.element('trkseg', nest: () {
              for (final p in entry.value) {
                b.element('trkpt', attributes: {
                  'lat': p.latitude.toStringAsFixed(7),
                  'lon': p.longitude.toStringAsFixed(7),
                }, nest: () {
                  if (p.altitude != null) {
                    b.element('ele', nest: p.altitude!.toStringAsFixed(1));
                  }
                  b.element('time',
                      nest: p.timestamp.toUtc().toIso8601String());
                  if (p.speed != null || p.accuracy != null) {
                    b.element('extensions', nest: () {
                      if (p.speed != null) {
                        b.element('isk:speed',
                            nest: p.speed!.toStringAsFixed(2));
                      }
                      if (p.accuracy != null) {
                        b.element('isk:acc',
                            nest: p.accuracy!.toStringAsFixed(1));
                      }
                    });
                  }
                });
              }
            });
          }
        });
      }
    });
    return b.buildDocument().toXmlString(pretty: false);
  }

  static XmlElement? _child(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static double? _d(String? s) => s == null ? null : double.tryParse(s.trim());

  /// Импорт GPX. Точки без времени пропускаются (время обязательно для
  /// расчёта длительности; мы не придумываем его). Бросает FormatException,
  /// если пригодных треков нет.
  static GpxParseResult parse(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } on XmlException catch (e) {
      throw FormatException('Файл не является корректным XML: ${e.message}');
    }
    final root = doc.rootElement;
    if (root.name.local != 'gpx') {
      throw const FormatException('Это не GPX-файл (нет корневого <gpx>).');
    }
    var skipped = 0;
    final warnings = <String>[];
    final tracks = <ParsedTrack>[];
    final trks =
        root.descendantElements.where((e) => e.name.local == 'trk').toList();
    for (final trk in trks) {
      final name = _child(trk, 'name')?.innerText.trim() ?? '';
      final desc = _child(trk, 'desc')?.innerText.trim() ?? '';
      final rideId = newId();
      final pts = <TrackPoint>[];
      var segIdx = 0;
      var firstSeg = true;
      for (final seg in trk.childElements.where((e) => e.name.local == 'trkseg')) {
        if (!firstSeg) segIdx++;
        firstSeg = false;
        var added = 0;
        for (final pt in seg.childElements.where((e) => e.name.local == 'trkpt')) {
          final lat = _d(pt.getAttribute('lat'));
          final lon = _d(pt.getAttribute('lon'));
          final t = DateTime.tryParse(_child(pt, 'time')?.innerText.trim() ?? '');
          if (lat == null ||
              lon == null ||
              lat < -90 ||
              lat > 90 ||
              lon < -180 ||
              lon > 180 ||
              t == null) {
            skipped++;
            continue;
          }
          double? speed, acc;
          final ext = _child(pt, 'extensions');
          if (ext != null) {
            speed = _d(_child(ext, 'speed')?.innerText);
            acc = _d(_child(ext, 'acc')?.innerText);
          }
          pts.add(TrackPoint(
            id: newId(),
            rideId: rideId,
            latitude: lat,
            longitude: lon,
            altitude: _d(_child(pt, 'ele')?.innerText),
            speed: speed,
            accuracy: acc,
            timestamp: t.toUtc(),
            segmentIndex: segIdx,
          ));
          added++;
        }
        if (added == 0 && segIdx > 0) segIdx--; // пустой сегмент не считаем
      }
      if (pts.length < 2) {
        warnings.add(
            'Трек «${name.isEmpty ? 'без названия' : name}» пропущен: меньше двух точек с координатами и временем.');
        continue;
      }
      pts.sort((a, b) {
        final c = a.segmentIndex.compareTo(b.segmentIndex);
        return c != 0 ? c : a.timestamp.compareTo(b.timestamp);
      });
      final m = TrackAccumulator.fromPoints(pts);
      final started = pts.first.timestamp;
      final finished = pts.last.timestamp;
      final now = DateTime.now().toUtc();
      final ride = Ride(
        id: rideId,
        title: name.isEmpty ? 'Импорт GPX' : name,
        description: desc,
        startedAt: started,
        finishedAt: finished,
        durationSeconds: finished.difference(started).inSeconds,
        movingDurationSeconds: m.movingSeconds,
        distanceMeters: m.distanceMeters,
        averageSpeed: m.averageSpeed,
        maxSpeed: m.maxSpeed,
        elevationGain: m.elevationGain,
        status: RideStatus.finished,
        createdAt: now,
        updatedAt: now,
      );
      tracks.add(ParsedTrack(ride.title, desc, pts, ride));
    }
    if (tracks.isEmpty) {
      throw FormatException(warnings.isEmpty
          ? 'В файле нет треков (<trk>) с точками.'
          : warnings.join('\n'));
    }
    return GpxParseResult(tracks, skipped, warnings);
  }
}
