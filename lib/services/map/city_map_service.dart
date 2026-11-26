import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/config.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';

class CancelToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class MapInstallException implements Exception {
  final String message;
  MapInstallException(this.message);
  @override
  String toString() => message;
}

class MbtilesInfo {
  final String? name;
  final String? iskId;
  final int? version;
  final GeoBounds? bounds;
  final int? maxZoom;
  MbtilesInfo(this.name, this.iskId, this.version, this.bounds, this.maxZoom);
}

typedef ProgressCallback = void Function(int received, int? total);

/// Управление офлайн-картами городов: каталог, установка из файла,
/// загрузка, проверка контрольной суммы, атомарная замена, удаление.
/// Удаление карты никогда не затрагивает поездки (другая таблица/файлы).
class CityMapService {
  CityMapService(this._repo);
  final CityMapRepository _repo;
  static const _channel = MethodChannel(AppConfig.storageChannel);

  Future<Directory> mapsDir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'maps'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  // ---------- Каталог ----------

  /// Встроенный каталог + (если задан CATALOG_URL) удалённый.
  /// Возвращает также ошибку загрузки удалённого каталога, если была.
  Future<(List<CatalogEntry>, String?)> loadCatalog() async {
    final entries = <String, CatalogEntry>{};
    final bundled = await rootBundle.loadString('assets/catalog.json');
    for (final e in _parseCatalog(bundled)) {
      entries[e.id] = e;
    }
    String? error;
    if (AppConfig.catalogUrl.isNotEmpty) {
      try {
        final text = await _httpGetString(Uri.parse(AppConfig.catalogUrl));
        for (final e in _parseCatalog(text)) {
          entries[e.id] = e; // удалённый каталог приоритетнее
        }
      } catch (e) {
        error = 'Не удалось загрузить каталог: $e';
      }
    }
    return (entries.values.toList(), error);
  }

  List<CatalogEntry> _parseCatalog(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return [
      for (final c in (m['cities'] as List))
        CatalogEntry.fromJson(c as Map<String, dynamic>)
    ];
  }

  Future<String> _httpGetString(Uri uri) async {
    if (uri.scheme != 'https') {
      throw MapInstallException('Допускается только HTTPS');
    }
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await c.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw MapInstallException('Сервер ответил ${res.statusCode}');
      }
      return await res.transform(utf8.decoder).join();
    } finally {
      c.close(force: true);
    }
  }

  // ---------- Устройство ----------

  Future<int?> freeBytes() async {
    try {
      final d = await mapsDir();
      final v = await _channel.invokeMethod<int>('freeBytes', {'path': d.path});
      return v;
    } catch (_) {
      return null; // не удалось определить — не блокируем
    }
  }

  Future<bool> isMetered() async {
    try {
      return await _channel.invokeMethod<bool>('isMetered') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------- Проверка ----------

  Future<String> sha256Of(File f) async {
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString();
  }

  /// Проверяет, что файл — читаемый MBTiles с векторными тайлами.
  Future<MbtilesInfo> verifyMbtiles(File f) async {
    Database? db;
    try {
      db = await openDatabase(f.path, readOnly: true, singleInstance: false);
      final tables = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type IN ('table','view')"))
          .map((r) => r['name'])
          .toSet();
      if (!tables.contains('tiles') || !tables.contains('metadata')) {
        throw MapInstallException('Это не MBTiles: нет таблиц tiles/metadata.');
      }
      final any = await db.rawQuery('SELECT 1 FROM tiles LIMIT 1');
      if (any.isEmpty) throw MapInstallException('В файле нет тайлов.');
      final meta = <String, String>{
        for (final r in await db.rawQuery('SELECT name, value FROM metadata'))
          '${r['name']}': '${r['value']}'
      };
      final format = meta['format'];
      if (format != null && format != 'pbf') {
        throw MapInstallException(
            'Нужны векторные тайлы (pbf), а в файле формат «$format».');
      }
      GeoBounds? b;
      final bs = meta['bounds']?.split(',');
      if (bs != null && bs.length == 4) {
        final v = bs.map((e) => double.tryParse(e.trim())).toList();
        if (!v.contains(null)) b = GeoBounds(v[1]!, v[0]!, v[3]!, v[2]!);
      }
      return MbtilesInfo(meta['name'], meta['iskolesil_id'],
          int.tryParse(meta['iskolesil_version'] ?? meta['version'] ?? ''), b,
          int.tryParse(meta['maxzoom'] ?? ''));
    } on MapInstallException {
      rethrow;
    } catch (e) {
      throw MapInstallException('Файл карты повреждён или не читается ($e).');
    } finally {
      await db?.close();
    }
  }

  // ---------- Установка ----------

  /// Установка из локального файла (.mbtiles). Копирует во временный файл,
  /// проверяет и только затем заменяет старую версию.
  Future<CityMap> installFromFile(
    File src, {
    CatalogEntry? entry,
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    final dir = await mapsDir();
    final size = await src.length();
    final free = await freeBytes();
    if (free != null && free < size + 50 * 1024 * 1024) {
      throw MapInstallException(
          'Недостаточно места: нужно ${(size / 1048576).ceil() + 50} МБ, свободно ${free ~/ 1048576} МБ.');
    }
    final tmpName = '${DateTime.now().millisecondsSinceEpoch}.part';
    final tmp = File(p.join(dir.path, tmpName));
    try {
      var copied = 0;
      final sink = tmp.openWrite();
      try {
        await for (final chunk in src.openRead()) {
          if (cancel?.cancelled ?? false) {
            throw MapInstallException('Отменено');
          }
          sink.add(chunk);
          copied += chunk.length;
          onProgress?.call(copied, size);
        }
      } finally {
        await sink.close();
      }
      return await _finalize(tmp, dir, entry: entry);
    } catch (_) {
      if (tmp.existsSync()) tmp.deleteSync();
      rethrow;
    }
  }

  /// Загрузка по URL из каталога с докачкой и проверкой SHA-256.
  Future<CityMap> download(
    CatalogEntry entry, {
    required bool wifiOnly,
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    if (!entry.downloadable) {
      throw MapInstallException(
          'Для этой карты не задан адрес загрузки. Установите её из файла.');
    }
    final uri = Uri.parse(entry.url!);
    if (uri.scheme != 'https') {
      throw MapInstallException('Допускается только HTTPS-адрес.');
    }
    if (wifiOnly && await isMetered()) {
      throw MapInstallException(
          'Включена загрузка только по Wi-Fi, а сейчас мобильная сеть.');
    }
    final dir = await mapsDir();
    final part = File(p.join(dir.path, '${entry.id}.download.part'));
    var have = part.existsSync() ? part.lengthSync() : 0;
    final expected = entry.sizeBytes;
    final free = await freeBytes();
    if (free != null && expected != null && free < (expected - have) + 100 * 1024 * 1024) {
      throw MapInstallException(
          'Недостаточно места: нужно ещё ${((expected - have) / 1048576).ceil() + 100} МБ, свободно ${free ~/ 1048576} МБ.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(uri);
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      final res = await req.close();
      if (res.statusCode == 200) {
        have = 0; // сервер игнорирует Range — качаем заново
      } else if (res.statusCode != 206) {
        throw MapInstallException('Сервер ответил ${res.statusCode}');
      }
      final total = res.statusCode == 206
          ? have + (res.contentLength > 0 ? res.contentLength : 0)
          : (res.contentLength > 0 ? res.contentLength : expected);
      final sink = part.openWrite(
          mode: have > 0 ? FileMode.append : FileMode.write);
      var received = have;
      try {
        await for (final chunk in res) {
          if (cancel?.cancelled ?? false) {
            await sink.flush();
            throw MapInstallException('Отменено (загруженное сохранено для докачки)');
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
    final tmp = File(p.join(dir.path, '${entry.id}.verify.part'));
    if (tmp.existsSync()) tmp.deleteSync();
    await part.rename(tmp.path);
    try {
      return await _finalize(tmp, dir, entry: entry, expectedSha: entry.sha256);
    } catch (_) {
      if (tmp.existsSync()) tmp.deleteSync();
      rethrow;
    }
  }

  Future<CityMap> _finalize(File tmp, Directory dir,
      {CatalogEntry? entry, String? expectedSha}) async {
    final sha = await sha256Of(tmp);
    if (expectedSha != null &&
        expectedSha.isNotEmpty &&
        sha.toLowerCase() != expectedSha.toLowerCase()) {
      throw MapInstallException(
          'Контрольная сумма не совпала — файл повреждён. Старая карта сохранена.');
    }
    final info = await verifyMbtiles(tmp);
    final id = entry?.id ?? info.iskId ?? _slug(info.name ?? 'map');
    final name = entry?.name ?? info.name ?? id;
    final target = File(p.join(dir.path, '$id.mbtiles'));
    final backup = File('${target.path}.old');
    final hadOld = target.existsSync();
    if (hadOld) {
      if (backup.existsSync()) backup.deleteSync();
      await target.rename(backup.path);
    }
    try {
      await tmp.rename(target.path);
    } catch (e) {
      if (hadOld) await backup.rename(target.path);
      throw MapInstallException('Не удалось установить карту: $e');
    }
    final ev = entry?.version ?? 0;
    final map = CityMap(
      id: id,
      name: name,
      region: entry?.region ?? '',
      version: ev > 0 ? ev : (info.version ?? 1),
      localPath: target.path,
      bounds: info.bounds ?? entry?.bounds,
      sizeBytes: await target.length(),
      checksum: sha,
      installationStatus: InstallStatus.installed,
      installedAt: DateTime.now().toUtc(),
    );
    try {
      await _repo.upsert(map);
    } catch (e) {
      // Откат файла, если запись в БД не удалась.
      if (target.existsSync()) target.deleteSync();
      if (hadOld) await backup.rename(target.path);
      throw MapInstallException('Не удалось записать карту в базу: $e');
    }
    if (backup.existsSync()) backup.deleteSync();
    return map;
  }

  String _slug(String s) {
    final r = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]+'), '-');
    return r.isEmpty ? 'map' : r;
  }

  // ---------- Удаление ----------

  Future<void> delete(String id) async {
    final m = await _repo.get(id);
    if (m != null) {
      final f = File(m.localPath);
      if (f.existsSync()) f.deleteSync();
    }
    await _repo.delete(id);
    final dir = await mapsDir();
    for (final suffix in ['.download.part', '.verify.part']) {
      final f = File(p.join(dir.path, '$id$suffix'));
      if (f.existsSync()) f.deleteSync();
    }
  }

  Future<int> partialBytes(String id) async {
    final dir = await mapsDir();
    final f = File(p.join(dir.path, '$id.download.part'));
    return f.existsSync() ? f.lengthSync() : 0;
  }

  Future<int> totalInstalledBytes() async {
    final list = await _repo.list();
    return list.fold<int>(0, (a, m) => a + m.sizeBytes);
  }
}
