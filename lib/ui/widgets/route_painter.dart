import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/geo.dart';
import '../../domain/models.dart';

/// Проекция набора сегментов в прямоугольник с сохранением пропорций.
class RouteProjection {
  RouteProjection(List<List<LatLon>> segments, Size size, {double padding = 12}) {
    final b = boundsOfSegments(segments);
    if (b == null) {
      valid = false;
      return;
    }
    valid = true;
    final midLat = (b.minLat + b.maxLat) / 2;
    final kx = cos(midLat * pi / 180);
    final w = max((b.maxLon - b.minLon) * kx, 1e-7);
    final h = max(b.maxLat - b.minLat, 1e-7);
    final availW = max(size.width - padding * 2, 1);
    final availH = max(size.height - padding * 2, 1);
    scale = min(availW / w, availH / h).toDouble();
    offX = (size.width - w * scale) / 2;
    offY = (size.height - h * scale) / 2;
    _b = b;
    _kx = kx;
    _h = h;
  }
  bool valid = false;
  double scale = 1, offX = 0, offY = 0, _kx = 1, _h = 1;
  late GeoBounds _b;

  Offset project(LatLon p) => Offset(
        offX + (p.lon - _b.minLon) * _kx * scale,
        offY + (_h - (p.lat - _b.minLat)) * scale,
      );
}

class RoutePainter extends CustomPainter {
  RoutePainter({
    required this.segments,
    this.color = AppColors.accent,
    this.strokeWidth = 3,
    this.background,
    this.drawEnds = false,
    this.padding = 12,
  });
  final List<List<LatLon>> segments;
  final Color color;
  final double strokeWidth;
  final Color? background;
  final bool drawEnds;
  final double padding;

  @override
  void paint(Canvas canvas, Size size) {
    if (background != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background!);
    }
    final proj = RouteProjection(segments, size, padding: padding);
    if (!proj.valid) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in segments) {
      if (s.length < 2) continue;
      final path = Path();
      final f = proj.project(s.first);
      path.moveTo(f.dx, f.dy);
      for (var i = 1; i < s.length; i++) {
        final o = proj.project(s[i]);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
    }
    if (drawEnds) {
      final first = segments.firstWhere((s) => s.isNotEmpty, orElse: () => []);
      final last = segments.lastWhere((s) => s.isNotEmpty, orElse: () => []);
      if (first.isNotEmpty && last.isNotEmpty) {
        final r = strokeWidth * 1.8;
        canvas.drawCircle(proj.project(first.first), r, Paint()..color = Colors.white);
        canvas.drawCircle(proj.project(first.first), r * 0.6, Paint()..color = color);
        canvas.drawCircle(proj.project(last.last), r, Paint()..color = color);
        canvas.drawCircle(proj.project(last.last), r * 0.45, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RoutePainter old) =>
      old.segments != segments || old.color != color;
}

/// Миниатюра маршрута для карточек истории.
class TrackThumbnail extends StatelessWidget {
  const TrackThumbnail({super.key, required this.segments, this.size = 72});
  final List<List<LatLon>>? segments;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: segments == null
          ? null
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: RoutePainter(
                    segments: segments!, strokeWidth: 2.2, padding: 10),
              ),
            ),
    );
  }
}
