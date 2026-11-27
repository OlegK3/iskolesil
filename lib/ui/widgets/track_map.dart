import 'dart:math' show Point;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../providers.dart';

/// Карта: монохромная подложка из локального сервера + три раздельных слоя
/// (сохранённые треки, выделенный/текущий трек, положение).
class TrackMap extends ConsumerStatefulWidget {
  const TrackMap({
    super.key,
    this.previous = const [],
    this.highlighted = const [],
    this.position,
    this.follow = false,
    this.fitBounds,
    this.fitNonce = 0,
    this.centerNonce = 0,
    this.centerOn,
    this.centerZoom = 16,
    this.onUserGesture,
    this.onTap,
    this.interactive = true,
  });

  /// Бледно-красные линии (каждый элемент — набор сегментов одной поездки).
  final List<List<List<LatLon>>> previous;

  /// Насыщенный красный (текущая/выбранная поездка).
  final List<List<LatLon>> highlighted;
  final LatLon? position;
  final bool follow;
  final GeoBounds? fitBounds;
  final int fitNonce; // изменение запускает подгонку границ
  final int centerNonce; // изменение запускает центрирование (кнопка «Где я»)
  final LatLon? centerOn; // куда центрировать по centerNonce (по умолчанию position)
  final double centerZoom;

  /// Пользователь двигает карту рукой (для отключения автоследования).
  final VoidCallback? onUserGesture;
  final void Function(LatLon, double zoom)? onTap;
  final bool interactive;

  @override
  ConsumerState<TrackMap> createState() => _TrackMapState();
}

class _TrackMapState extends ConsumerState<TrackMap> {
  MapLibreMapController? _c;
  bool _styleReady = false;

  static const _prevSrc = 'prev-src';
  static const _selSrc = 'sel-src';
  static const _posSrc = 'pos-src';

  Map<String, dynamic> _multiLine(List<List<LatLon>> segs) => {
        'type': 'FeatureCollection',
        'features': [
          for (final s in segs)
            if (s.length >= 2)
              {
                'type': 'Feature',
                'properties': <String, dynamic>{},
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    for (final p in s) [p.lon, p.lat]
                  ],
                },
              }
        ],
      };

  Map<String, dynamic> _point(LatLon? p) => {
        'type': 'FeatureCollection',
        'features': [
          if (p != null)
            {
              'type': 'Feature',
              'properties': <String, dynamic>{},
              'geometry': {
                'type': 'Point',
                'coordinates': [p.lon, p.lat],
              },
            }
        ],
      };

  Future<void> _onStyleLoaded() async {
    final c = _c;
    if (c == null) return;
    final empty = {'type': 'FeatureCollection', 'features': []};
    await c.addGeoJsonSource(_prevSrc, empty);
    await c.addGeoJsonSource(_selSrc, empty);
    await c.addGeoJsonSource(_posSrc, empty);
    await c.addLineLayer(
      _prevSrc,
      'prev-line',
      const LineLayerProperties(
        lineColor: AppColors.prevRouteHex,
        lineWidth: 3.0,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await c.addLineLayer(
      _selSrc,
      'sel-line',
      const LineLayerProperties(
        lineColor: AppColors.accentHex,
        lineWidth: 5.5,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await c.addCircleLayer(
      _posSrc,
      'pos-circle',
      const CircleLayerProperties(
        circleRadius: 8.0,
        circleColor: AppColors.accentHex,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3.0,
      ),
    );
    _styleReady = true;
    await _push();
    _fit();
    if (widget.fitBounds == null && widget.centerOn != null) {
      _center(explicit: true);
    }
  }

  /// Поэлементное сравнение по идентичности: родитель может пересоздавать
  /// внешний список при каждой перерисовке, а геометрию кэширует провайдер.
  bool _differs(List<Object?> a, List<Object?> b) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return true;
    }
    return false;
  }

  Future<void> _push() async {
    await _pushPrev();
    await _pushSel();
    await _pushPos();
  }

  Future<void> _pushPrev() async {
    final c = _c;
    if (c == null || !_styleReady) return;
    await c.setGeoJsonSource(
        _prevSrc, _multiLine([for (final r in widget.previous) ...r]));
  }

  Future<void> _pushSel() async {
    final c = _c;
    if (c == null || !_styleReady) return;
    await c.setGeoJsonSource(_selSrc, _multiLine(widget.highlighted));
  }

  Future<void> _pushPos() async {
    final c = _c;
    if (c == null || !_styleReady) return;
    await c.setGeoJsonSource(_posSrc, _point(widget.position));
  }

  void _fit() {
    final c = _c;
    final b = widget.fitBounds;
    if (c == null || !_styleReady || b == null) return;
    // Вырожденные границы (одна точка) — просто приближаем.
    if ((b.maxLat - b.minLat).abs() < 1e-5 && (b.maxLon - b.minLon).abs() < 1e-5) {
      c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(b.minLat, b.minLon), 15));
      return;
    }
    c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(b.minLat, b.minLon),
          northeast: LatLng(b.maxLat, b.maxLon),
        ),
        left: 40,
        right: 40,
        top: 60,
        bottom: 60,
      ),
    );
  }

  /// [explicit] — нажатие «Где я»: ставим удобный масштаб. Иначе (следование)
  /// масштаб пользователя не меняем.
  void _center({bool explicit = false}) {
    final c = _c;
    final p = explicit ? (widget.centerOn ?? widget.position) : widget.position;
    if (c == null || !_styleReady || p == null) return;
    final target = LatLng(p.lat, p.lon);
    if (explicit) {
      final z = c.cameraPosition?.zoom ?? 0;
      c.animateCamera(CameraUpdate.newLatLngZoom(
          target, z < widget.centerZoom - 1 ? widget.centerZoom : z.clamp(widget.centerZoom - 1, 19).toDouble()));
    } else {
      c.animateCamera(CameraUpdate.newLatLng(target));
    }
  }

  @override
  void didUpdateWidget(covariant TrackMap old) {
    super.didUpdateWidget(old);
    if (!_styleReady) return;
    if (_differs(old.previous, widget.previous)) _pushPrev();
    if (!identical(old.highlighted, widget.highlighted)) _pushSel();
    if (old.position != widget.position) _pushPos();
    if (old.fitNonce != widget.fitNonce) _fit();
    if (old.centerNonce != widget.centerNonce) _center(explicit: true);
    if (widget.follow && old.position != widget.position) _center();
  }

  @override
  Widget build(BuildContext context) {
    final style = ref.watch(styleUrlProvider);
    return style.when(
      loading: () => const ColoredBox(color: AppColors.bg),
      error: (e, _) => Center(child: Text('Карта недоступна: $e')),
      data: (url) => Stack(
        children: [
          Listener(
            onPointerMove: (_) => widget.onUserGesture?.call(),
            child: MapLibreMap(
            key: ValueKey(url),
            styleString: url,
            initialCameraPosition: CameraPosition(
              target: widget.position != null
                  ? LatLng(widget.position!.lat, widget.position!.lon)
                  : const LatLng(AppConfig.defaultCenterLat, AppConfig.defaultCenterLon),
              zoom: widget.position != null ? 15 : AppConfig.defaultZoom,
            ),
            onMapCreated: (c) {
              _c = c;
              _styleReady = false;
            },
            onStyleLoadedCallback: _onStyleLoaded,
            trackCameraPosition: true,
            onMapClick: (Point<double> p, LatLng l) => widget.onTap?.call(
                LatLon(l.latitude, l.longitude), _c?.cameraPosition?.zoom ?? 12),
            compassEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            scrollGesturesEnabled: widget.interactive,
            zoomGesturesEnabled: widget.interactive,
            // Карта забирает жесты первой: работает масштабирование двумя
            // пальцами и перемещение даже внутри прокручиваемых экранов.
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
            },
          ),
          ),
          const Positioned(
            left: 8,
            bottom: 6,
            child: IgnorePointer(
              child: Text(
                AppConfig.mapAttribution,
                style: TextStyle(fontSize: 10, color: AppColors.secondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
