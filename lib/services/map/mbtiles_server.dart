import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

import '../../domain/models.dart';
import 'map_style.dart';

class _OpenMap {
  final String path;
  final GeoBounds? bounds;
  final Database db;
  _OpenMap(this.path, this.bounds, this.db);
}

/// Локальный HTTP-сервер на 127.0.0.1: отдаёт MapLibre векторные тайлы из
/// MBTiles, глифы шрифтов из assets и style.json. Наружу не слушает и
/// ни к каким внешним серверам не обращается.
///
/// Зачем: flutter maplibre_gl не умеет надёжно читать MBTiles напрямую.
class LocalTileServer {
  HttpServer? _server;
  final List<_OpenMap> _maps = [];
  int _revision = 0;
  int _maxZoom = 14;

  int get port => _server?.port ?? 0;
  bool get running => _server != null;
  bool get hasTiles => _maps.isNotEmpty;

  String get styleUrl => 'http://127.0.0.1:$port/style.json?v=$_revision';

  Future<void> start() async {
    if (_server != null) return;
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen(_handle, onError: (_) {});
  }

  /// Подключает набор установленных карт (путь + границы покрытия).
  Future<void> setMaps(List<(String path, GeoBounds? bounds)> maps) async {
    for (final m in _maps) {
      try {
        await m.db.close();
      } catch (_) {}
    }
    _maps.clear();
    var maxZ = 0;
    for (final (path, bounds) in maps) {
      try {
        if (!File(path).existsSync()) continue;
        final db = await openDatabase(path, readOnly: true, singleInstance: false);
        _maps.add(_OpenMap(path, bounds, db));
        final rows = await db
            .rawQuery("SELECT value FROM metadata WHERE name = 'maxzoom'");
        if (rows.isNotEmpty) {
          final z = int.tryParse('${rows.first['value']}');
          if (z != null) maxZ = max(maxZ, z);
        }
      } catch (_) {
        // Повреждённая карта не должна ронять приложение.
      }
    }
    _maxZoom = maxZ > 0 ? maxZ : 14;
    _revision++;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    for (final m in _maps) {
      try {
        await m.db.close();
      } catch (_) {}
    }
    _maps.clear();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final segs = req.uri.pathSegments;
      if (segs.isNotEmpty && segs.first == 'style.json') {
        final body = jsonEncode(buildMonoStyle(
          port: port,
          hasTiles: hasTiles,
          maxZoom: _maxZoom,
        ));
        req.response
          ..headers.contentType = ContentType.json
          ..write(body);
      } else if (segs.length == 4 && segs.first == 'tiles') {
        await _serveTile(req, segs);
      } else if (segs.length == 3 && segs.first == 'fonts') {
        await _serveGlyph(req, segs);
      } else {
        req.response.statusCode = HttpStatus.notFound;
      }
    } catch (_) {
      req.response.statusCode = HttpStatus.internalServerError;
    } finally {
      await req.response.close();
    }
  }

  Future<void> _serveGlyph(HttpRequest req, List<String> segs) async {
    final stack = Uri.decodeComponent(segs[1]).split(',').first.trim();
    final range = segs[2].replaceAll('.pbf', '');
    if (!RegExp(r'^[A-Za-z0-9\- ]+$').hasMatch(stack) ||
        !RegExp(r'^\d+-\d+$').hasMatch(range)) {
      req.response.statusCode = HttpStatus.badRequest;
      return;
    }
    try {
      final data = await rootBundle.load('assets/map/fonts/$stack/$range.pbf');
      req.response
        ..headers.contentType = ContentType('application', 'x-protobuf')
        ..add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } catch (_) {
      // Нет такого диапазона глифов: пустой ответ, подписи не рисуются.
      req.response.statusCode = HttpStatus.noContent;
    }
  }

  Future<void> _serveTile(HttpRequest req, List<String> segs) async {
    final z = int.tryParse(segs[1]);
    final x = int.tryParse(segs[2]);
    final y = int.tryParse(segs[3].split('.').first);
    if (z == null || x == null || y == null || z < 0 || z > 22) {
      req.response.statusCode = HttpStatus.badRequest;
      return;
    }
    final data = await _findTile(z, x, y);
    if (data == null) {
      req.response.statusCode = HttpStatus.noContent; // пустой тайл
      return;
    }
    req.response
      ..headers.contentType = ContentType('application', 'x-protobuf')
      ..add(data);
  }

  Future<List<int>?> _findTile(int z, int x, int y) async {
    if (_maps.isEmpty) return null;
    final n = pow(2, z).toDouble();
    final lon = (x + 0.5) / n * 360.0 - 180.0;
    final latRad = atan(_sinh(pi * (1 - 2 * (y + 0.5) / n)));
    final lat = latRad * 180.0 / pi;
    // Сначала карты, чьи границы содержат центр тайла, затем остальные.
    final ordered = [
      ..._maps.where((m) => m.bounds?.contains(lat, lon) ?? false),
      ..._maps.where((m) => !(m.bounds?.contains(lat, lon) ?? false)),
    ];
    final tmsY = (1 << z) - 1 - y; // MBTiles хранит TMS
    for (final m in ordered) {
      final rows = await m.db.rawQuery(
          'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
          [z, x, tmsY]);
      if (rows.isNotEmpty) {
        final raw = rows.first['tile_data'] as List<int>;
        if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
          return gzip.decode(raw); // Planetiler сжимает тайлы gzip
        }
        return raw;
      }
    }
    return null;
  }

  double _sinh(double v) => (exp(v) - exp(-v)) / 2;
}
