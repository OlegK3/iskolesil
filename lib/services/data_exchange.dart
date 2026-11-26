import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/ids.dart';
import '../data/database.dart';
import '../domain/gpx.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';

class ImportResult {
  final int imported;
  final int duplicates;
  final int skippedPoints;
  final List<String> warnings;
  ImportResult(this.imported, this.duplicates, this.skippedPoints, this.warnings);
}

class RestoreResult {
  final int added;
  final int alreadyPresent;
  final int failed;
  RestoreResult(this.added, this.alreadyPresent, this.failed);
}

String safeFileName(String s) {
  final cleaned = s
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_')
      .trim();
  final r = cleaned.isEmpty ? 'ride' : cleaned;
  return r.length > 60 ? r.substring(0, 60) : r;
}

String _stamp(DateTime d) {
  String t(int v) => v.toString().padLeft(2, '0');
  final l = d.toLocal();
  return '${l.year}${t(l.month)}${t(l.day)}-${t(l.hour)}${t(l.minute)}';
}

/// GPX и резервные копии. Не зависит от UI и Flutter.
class DataExchangeService {
  DataExchangeService(this._rides);
  final RideRepository _rides;

  // ---------- GPX ----------

  Future<File> exportRideGpx(String rideId, Directory dir) async {
    final ride = await _rides.getRide(rideId);
    if (ride == null) throw StateError('Поездка не найдена');
    final pts = await _rides.getPoints(rideId);
    final xml = GpxCodec.export([(ride, pts)]);
    final f = File(p.join(dir.path, '${safeFileName(ride.title)}.gpx'));
    await f.writeAsString(xml, flush: true);
    return f;
  }

  Future<File> exportAllGpx(Directory dir) async {
    final rides = await _rides.listFinished();
    if (rides.isEmpty) throw StateError('Нет поездок для экспорта');
    final list = <(Ride, List<TrackPoint>)>[];
    for (final r in rides.reversed) {
      list.add((r, await _rides.getPoints(r.id)));
    }
    final f = File(p.join(dir.path, 'iskolesil-all-${_stamp(DateTime.now())}.gpx'));
    await f.writeAsString(GpxCodec.export(list), flush: true);
    return f;
  }

  Future<ImportResult> importGpx(File file) async {
    final text = await file.readAsString();
    final parsed = GpxCodec.parse(text); // FormatException при ошибке
    final existing = await _rides.listFinished();
    var imported = 0, dup = 0;
    for (final t in parsed.tracks) {
      final isDup = existing.any((e) =>
          e.startedAt.millisecondsSinceEpoch ==
              t.ride.startedAt.millisecondsSinceEpoch &&
          (e.distanceMeters - t.ride.distanceMeters).abs() < 1.0);
      if (isDup) {
        dup++;
        continue;
      }
      await _rides.insertRideWithPoints(t.ride, t.points);
      imported++;
    }
    return ImportResult(imported, dup, parsed.skippedPoints, parsed.warnings);
  }

  // ---------- Резервная копия ----------
  // Формат: gzip(JSON). Восстановление добавляет только отсутствующие поездки
  // (по UUID) и никогда не изменяет и не удаляет существующие данные.

  Future<File> createBackup(Directory dir) async {
    final rides = await _rides.listFinished();
    final out = <Map<String, dynamic>>[];
    for (final r in rides) {
      final pts = await _rides.getPoints(r.id);
      out.add({
        'id': r.id,
        'title': r.title,
        'description': r.description,
        'startedAt': r.startedAt.millisecondsSinceEpoch,
        'finishedAt': r.finishedAt?.millisecondsSinceEpoch,
        'durationSeconds': r.durationSeconds,
        'movingDurationSeconds': r.movingDurationSeconds,
        'distanceMeters': r.distanceMeters,
        'averageSpeed': r.averageSpeed,
        'maxSpeed': r.maxSpeed,
        'elevationGain': r.elevationGain,
        'createdAt': r.createdAt.millisecondsSinceEpoch,
        'updatedAt': r.updatedAt.millisecondsSinceEpoch,
        // [id, lat, lon, alt, speed, accuracy, tsMs, segment]
        'points': [
          for (final q in pts)
            [
              q.id,
              q.latitude,
              q.longitude,
              q.altitude,
              q.speed,
              q.accuracy,
              q.timestamp.millisecondsSinceEpoch,
              q.segmentIndex
            ]
        ],
      });
    }
    final doc = {
      'format': 'iskolesil-backup',
      'version': 1,
      'schemaVersion': AppDatabase.schemaVersion,
      'createdAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      'rides': out,
    };
    final bytes = gzip.encode(utf8.encode(jsonEncode(doc)));
    final f = File(p.join(dir.path, 'iskolesil-backup-${_stamp(DateTime.now())}.iskolesil'));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<RestoreResult> restoreBackup(File file) async {
    final Map<String, dynamic> doc;
    try {
      final raw = await file.readAsBytes();
      final text = utf8.decode(gzip.decode(raw));
      doc = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException(
          'Файл повреждён или не является резервной копией ИСКОЛЕСИЛ.');
    }
    if (doc['format'] != 'iskolesil-backup') {
      throw const FormatException('Это не резервная копия ИСКОЛЕСИЛ.');
    }
    final version = (doc['version'] as num?)?.toInt() ?? 0;
    if (version != 1) {
      throw FormatException('Неподдерживаемая версия копии: $version.');
    }
    final list = (doc['rides'] as List?) ?? const [];
    var added = 0, present = 0, failed = 0;
    for (final item in list) {
      try {
        final m = item as Map<String, dynamic>;
        final id = m['id'] as String;
        if (await _rides.rideExists(id)) {
          present++;
          continue;
        }
        DateTime d(Object? v) =>
            DateTime.fromMillisecondsSinceEpoch((v as num).toInt(), isUtc: true);
        final ride = Ride(
          id: id,
          title: m['title'] as String,
          description: (m['description'] ?? '') as String,
          startedAt: d(m['startedAt']),
          finishedAt: m['finishedAt'] == null ? null : d(m['finishedAt']),
          durationSeconds: (m['durationSeconds'] as num).toInt(),
          movingDurationSeconds: (m['movingDurationSeconds'] as num).toInt(),
          distanceMeters: (m['distanceMeters'] as num).toDouble(),
          averageSpeed: (m['averageSpeed'] as num).toDouble(),
          maxSpeed: (m['maxSpeed'] as num).toDouble(),
          elevationGain: (m['elevationGain'] as num?)?.toDouble(),
          status: RideStatus.finished,
          createdAt: d(m['createdAt']),
          updatedAt: d(m['updatedAt']),
        );
        double? nd(Object? v) => v == null ? null : (v as num).toDouble();
        final pts = <TrackPoint>[];
        for (final row in (m['points'] as List)) {
          final r = row as List;
          pts.add(TrackPoint(
            id: (r[0] as String?) ?? newId(),
            rideId: id,
            latitude: (r[1] as num).toDouble(),
            longitude: (r[2] as num).toDouble(),
            altitude: nd(r[3]),
            speed: nd(r[4]),
            accuracy: nd(r[5]),
            timestamp: d(r[6]),
            segmentIndex: (r[7] as num).toInt(),
          ));
        }
        await _rides.insertRideWithPoints(ride, pts); // транзакция
        added++;
      } catch (_) {
        failed++;
      }
    }
    return RestoreResult(added, present, failed);
  }
}
