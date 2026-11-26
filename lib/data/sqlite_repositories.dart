import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'database.dart';

int _ms(DateTime d) => d.toUtc().millisecondsSinceEpoch;
DateTime _dt(Object? v) =>
    DateTime.fromMillisecondsSinceEpoch((v as num).toInt(), isUtc: true);
double? _dbl(Object? v) => v == null ? null : (v as num).toDouble();

Map<String, Object?> _rideMap(Ride r) => {
      'id': r.id,
      'title': r.title,
      'description': r.description,
      'started_at': _ms(r.startedAt),
      'finished_at': r.finishedAt == null ? null : _ms(r.finishedAt!),
      'duration_seconds': r.durationSeconds,
      'moving_duration_seconds': r.movingDurationSeconds,
      'distance_meters': r.distanceMeters,
      'average_speed': r.averageSpeed,
      'max_speed': r.maxSpeed,
      'elevation_gain': r.elevationGain,
      'status': r.status.name,
      'created_at': _ms(r.createdAt),
      'updated_at': _ms(r.updatedAt),
    };

Ride _rideFrom(Map<String, Object?> m) => Ride(
      id: m['id'] as String,
      title: m['title'] as String,
      description: (m['description'] ?? '') as String,
      startedAt: _dt(m['started_at']),
      finishedAt: m['finished_at'] == null ? null : _dt(m['finished_at']),
      durationSeconds: (m['duration_seconds'] as num).toInt(),
      movingDurationSeconds: (m['moving_duration_seconds'] as num).toInt(),
      distanceMeters: (m['distance_meters'] as num).toDouble(),
      averageSpeed: (m['average_speed'] as num).toDouble(),
      maxSpeed: (m['max_speed'] as num).toDouble(),
      elevationGain: _dbl(m['elevation_gain']),
      status: RideStatus.values.firstWhere((s) => s.name == m['status'],
          orElse: () => RideStatus.finished),
      createdAt: _dt(m['created_at']),
      updatedAt: _dt(m['updated_at']),
    );

Map<String, Object?> _pointMap(TrackPoint p) => {
      'id': p.id,
      'ride_id': p.rideId,
      'latitude': p.latitude,
      'longitude': p.longitude,
      'altitude': p.altitude,
      'speed': p.speed,
      'accuracy': p.accuracy,
      'timestamp': _ms(p.timestamp),
      'segment_index': p.segmentIndex,
    };

TrackPoint _pointFrom(Map<String, Object?> m) => TrackPoint(
      id: m['id'] as String,
      rideId: m['ride_id'] as String,
      latitude: (m['latitude'] as num).toDouble(),
      longitude: (m['longitude'] as num).toDouble(),
      altitude: _dbl(m['altitude']),
      speed: _dbl(m['speed']),
      accuracy: _dbl(m['accuracy']),
      timestamp: _dt(m['timestamp']),
      segmentIndex: (m['segment_index'] as num).toInt(),
    );

class SqliteRideRepository implements RideRepository {
  SqliteRideRepository(this._app);
  final AppDatabase _app;
  Database get _db => _app.db;

  @override
  Future<void> insertRide(Ride ride) async {
    await _db.insert('rides', _rideMap(ride),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<void> updateRide(Ride ride) async {
    await _db.update('rides', _rideMap(ride),
        where: 'id = ?', whereArgs: [ride.id]);
  }

  @override
  Future<Ride?> getRide(String id) async {
    final rows = await _db.query('rides', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _rideFrom(rows.first);
  }

  @override
  Future<List<Ride>> listFinished() async {
    final rows = await _db.query('rides',
        where: 'status = ?',
        whereArgs: [RideStatus.finished.name],
        orderBy: 'started_at DESC');
    return rows.map(_rideFrom).toList();
  }

  @override
  Future<Ride?> findUnfinished() async {
    final rows = await _db.query('rides',
        where: 'status IN (?, ?)',
        whereArgs: [RideStatus.recording.name, RideStatus.paused.name],
        orderBy: 'started_at DESC',
        limit: 1);
    return rows.isEmpty ? null : _rideFrom(rows.first);
  }

  @override
  Future<void> deleteRide(String id) async {
    // Точки удаляются каскадом (PRAGMA foreign_keys = ON).
    await _db.delete('rides', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteAllRides() async {
    await _db.transaction((txn) async {
      await txn.delete('track_points');
      await txn.delete('rides');
    });
  }

  @override
  Future<void> addPoint(TrackPoint point) async {
    await _db.insert('track_points', _pointMap(point));
  }

  @override
  Future<List<TrackPoint>> getPoints(String rideId) async {
    final rows = await _db.query('track_points',
        where: 'ride_id = ?',
        whereArgs: [rideId],
        orderBy: 'segment_index ASC, timestamp ASC');
    return rows.map(_pointFrom).toList();
  }

  @override
  Future<Map<String, List<List<LatLon>>>> loadSegments(
      Set<String> rideIds) async {
    final out = <String, List<List<LatLon>>>{};
    if (rideIds.isEmpty) return out;
    final rows = await _db.rawQuery(
        'SELECT p.ride_id AS rid, p.latitude AS lat, p.longitude AS lon, '
        'p.segment_index AS seg FROM track_points p '
        'JOIN rides r ON r.id = p.ride_id WHERE r.status = ? '
        'ORDER BY p.ride_id, p.segment_index, p.timestamp',
        [RideStatus.finished.name]);
    String? curRide;
    int? curSeg;
    for (final r in rows) {
      final rid = r['rid'] as String;
      if (!rideIds.contains(rid)) continue;
      final seg = (r['seg'] as num).toInt();
      if (rid != curRide) {
        curRide = rid;
        curSeg = null;
        out[rid] = <List<LatLon>>[];
      }
      if (seg != curSeg) {
        out[rid]!.add(<LatLon>[]);
        curSeg = seg;
      }
      out[rid]!.last.add(
          LatLon((r['lat'] as num).toDouble(), (r['lon'] as num).toDouble()));
    }
    return out;
  }

  @override
  Future<void> insertRideWithPoints(Ride ride, List<TrackPoint> points) async {
    await _db.transaction((txn) async {
      await txn.insert('rides', _rideMap(ride),
          conflictAlgorithm: ConflictAlgorithm.abort);
      final batch = txn.batch();
      for (final p in points) {
        batch.insert('track_points', _pointMap(p));
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<bool> rideExists(String id) async {
    final rows = await _db.query('rides',
        columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._app);
  final AppDatabase _app;

  @override
  Future<AppSettings> load() async {
    final rows = await _app.db.query('app_settings');
    final kv = {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
    return AppSettings.fromKeyValues(kv);
  }

  @override
  Future<void> save(AppSettings s) async {
    final batch = _app.db.batch();
    s.toKeyValues().forEach((k, v) {
      batch.insert('app_settings', {'key': k, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  @override
  Future<String?> getRaw(String key) async {
    final rows = await _app.db
        .query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> setRaw(String key, String? value) async {
    if (value == null) {
      await _app.db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await _app.db.insert('app_settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}

class SqliteCityMapRepository implements CityMapRepository {
  SqliteCityMapRepository(this._app);
  final AppDatabase _app;

  CityMap _from(Map<String, Object?> m) {
    final minLat = _dbl(m['min_lat']);
    return CityMap(
      id: m['id'] as String,
      name: m['name'] as String,
      region: (m['region'] ?? '') as String,
      version: (m['version'] as num).toInt(),
      localPath: m['local_path'] as String,
      bounds: minLat == null
          ? null
          : GeoBounds(minLat, _dbl(m['min_lon'])!, _dbl(m['max_lat'])!,
              _dbl(m['max_lon'])!),
      sizeBytes: (m['size_bytes'] as num).toInt(),
      checksum: m['checksum'] as String,
      installationStatus: InstallStatus.values.firstWhere(
          (s) => s.name == m['installation_status'],
          orElse: () => InstallStatus.installed),
      installedAt: _dt(m['installed_at']),
    );
  }

  @override
  Future<List<CityMap>> list() async {
    final rows = await _app.db.query('city_maps', orderBy: 'name ASC');
    return rows.map(_from).toList();
  }

  @override
  Future<CityMap?> get(String id) async {
    final rows =
        await _app.db.query('city_maps', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _from(rows.first);
  }

  @override
  Future<void> upsert(CityMap m) async {
    await _app.db.insert(
        'city_maps',
        {
          'id': m.id,
          'name': m.name,
          'region': m.region,
          'version': m.version,
          'local_path': m.localPath,
          'min_lat': m.bounds?.minLat,
          'min_lon': m.bounds?.minLon,
          'max_lat': m.bounds?.maxLat,
          'max_lon': m.bounds?.maxLon,
          'size_bytes': m.sizeBytes,
          'checksum': m.checksum,
          'installation_status': m.installationStatus.name,
          'installed_at': _ms(m.installedAt),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete(String id) async {
    await _app.db.delete('city_maps', where: 'id = ?', whereArgs: [id]);
  }
}
