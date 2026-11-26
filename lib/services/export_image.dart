import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../domain/geo.dart';
import '../domain/models.dart';
import '../ui/widgets/route_painter.dart';

/// Рисует PNG маршрута: красная линия, название, показатели, логотип и
/// атрибуция. В v0.1 подложка — светлая сетка без векторной карты
/// (отрисовка тайлов вне MapLibre не реализована; см. README, ограничения).
class RouteImageExporter {
  static Future<Uint8List> render({
    required Ride ride,
    required List<List<LatLon>> segments,
    required MeasurementUnits units,
    bool hideEnds = false,
    double hideMeters = 300,
  }) async {
    const w = 1080.0, h = 1350.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = AppColors.bg);

    // Монохромная «сетка» подложки
    final grid = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 2;
    for (var x = 0.0; x <= w; x += 90) {
      canvas.drawLine(Offset(x, 0), Offset(x, 900), grid);
    }
    for (var y = 0.0; y <= 900; y += 90) {
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }

    final shown = hideEnds ? trimEnds(segments, hideMeters) : segments;
    const mapRect = Rect.fromLTWH(0, 0, w, 900);
    canvas.save();
    canvas.clipRect(mapRect);
    RoutePainter(
      segments: shown,
      strokeWidth: 9,
      padding: 90,
      drawEnds: !hideEnds,
    ).paint(canvas, mapRect.size);
    canvas.restore();

    // Нижняя белая панель
    canvas.drawRect(const Rect.fromLTWH(0, 900, w, 450), Paint()..color = Colors.white);

    void text(String s, Offset o,
        {double size = 40,
        FontWeight weight = FontWeight.w500,
        Color color = AppColors.text,
        double maxWidth = 960}) {
      final tp = TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(fontSize: size, fontWeight: weight, color: color)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      tp.paint(canvas, o);
    }

    text(ride.title, const Offset(60, 935), size: 52, weight: FontWeight.w800);
    text(fmtDateTime(ride.startedAt), const Offset(60, 1000),
        size: 32, color: AppColors.secondary);

    final dist = distanceParts(ride.distanceMeters, units);
    final cols = [
      ('Расстояние', '${dist.$1} ${dist.$2}'),
      ('Время', fmtDuration(ride.durationSeconds)),
      ('Средняя', fmtSpeed(ride.averageSpeed, units)),
    ];
    for (var i = 0; i < cols.length; i++) {
      final x = 60.0 + i * 340;
      text(cols[i].$1, Offset(x, 1075), size: 28, color: AppColors.secondary, maxWidth: 320);
      text(cols[i].$2, Offset(x, 1112),
          size: 50, weight: FontWeight.w800, maxWidth: 320);
    }

    // Логотип и атрибуция
    final rr = RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 1240, 64, 64), const Radius.circular(18));
    canvas.drawRRect(rr, Paint()..color = AppColors.accent);
    text('И', const Offset(80, 1246), size: 48, weight: FontWeight.w900, color: Colors.white, maxWidth: 40);
    text(AppConfig.appName, const Offset(140, 1248), size: 36, weight: FontWeight.w900, maxWidth: 400);
    text(AppConfig.slogan, const Offset(140, 1292), size: 22, color: AppColors.secondary, maxWidth: 500);
    text(AppConfig.mapAttribution, const Offset(560, 1296),
        size: 20, color: AppColors.secondary, maxWidth: 460);

    final pic = recorder.endRecording();
    final img = await pic.toImage(w.toInt(), h.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}
