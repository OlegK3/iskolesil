import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

typedef Migration = Future<void> Function(Database db);

/// Локальная база SQLite (sqflite). Версия схемы = [schemaVersion].
/// Новые миграции добавляются в [_migrations] ключом «версия, к которой
/// приводит миграция». Не редактируйте уже выпущенные миграции.
class AppDatabase {
  AppDatabase._(this.db);
  final Database db;

  static const int schemaVersion = 1;

  static final Map<int, Migration> _migrations = {
    // 2: (db) async { await db.execute('ALTER TABLE ...'); },
  };

  static Future<AppDatabase> open({String? pathOverride}) async {
    final path = pathOverride ?? p.join(await getDatabasesPath(), 'iskolesil.db');
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _create(db);
      },
      onUpgrade: (db, oldV, newV) async {
        for (var v = oldV + 1; v <= newV; v++) {
          final m = _migrations[v];
          if (m == null) {
            throw StateError('Нет миграции базы до версии $v');
          }
          await m(db);
        }
      },
    );
    return AppDatabase._(db);
  }

  static Future<void> _create(Database db) async {
    // Поездки отдельно от карт. Время — Unix epoch, миллисекунды, UTC.
    await db.execute('''
      CREATE TABLE rides (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        started_at INTEGER NOT NULL,
        finished_at INTEGER,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        moving_duration_seconds INTEGER NOT NULL DEFAULT 0,
        distance_meters REAL NOT NULL DEFAULT 0,
        average_speed REAL NOT NULL DEFAULT 0,
        max_speed REAL NOT NULL DEFAULT 0,
        elevation_gain REAL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE track_points (
        id TEXT PRIMARY KEY,
        ride_id TEXT NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        speed REAL,
        accuracy REAL,
        timestamp INTEGER NOT NULL,
        segment_index INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute(
        'CREATE INDEX idx_points_ride_time ON track_points(ride_id, timestamp)');
    await db.execute('CREATE INDEX idx_rides_started ON rides(started_at)');
    await db.execute('''
      CREATE TABLE city_maps (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        region TEXT NOT NULL DEFAULT '',
        version INTEGER NOT NULL,
        local_path TEXT NOT NULL,
        min_lat REAL, min_lon REAL, max_lat REAL, max_lon REAL,
        size_bytes INTEGER NOT NULL,
        checksum TEXT NOT NULL,
        installation_status TEXT NOT NULL,
        installed_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }
}
