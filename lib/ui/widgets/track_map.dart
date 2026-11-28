import 'dart:async';
import 'dart:io' show InternetAddress;

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart' as ym;

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../providers.dart';

/// Светлая, почти чёрно-белая схема (штатная стилизация Яндекс MapKit).
/// Логотип и атрибуцию Яндекса не скрываем и не перекрашиваем.
const _monoStyle = '''
[
  {"stylers": {"saturation": -1}},
  {"tags": {"any": ["landscape"]}, "elements": "geometry", "stylers": {"color": "#ECECEC"}},
  {"tags": {"any": ["landcover", "park", "national_park", "vegetation"]}, "elements": "geometry", "stylers": {"color": "#E0E0E0"}},
  {"tags": {"any": ["water"]}, "elements": "geometry", "stylers": {"color": "#CFCFCF"}},
  {"tags": {"any": ["building"]}, "elements": "geometry.fill", "stylers": {"color": "#D2D2D2"}},
  {"tags": {"any": ["building"]}, "elements": "geometry.outline", "stylers": {"color": "#BEBEBE"}},
  {"tags": {"any": ["road"]}, "elements": "geometry.fill", "stylers": {"color": "#FFFFFF"}},
  {"tags": {"any": ["road"]}, "elements": "geometry.outline", "stylers": {"color": "#D8D8D8"}},
  {"elements": "label.text.fill", "stylers": {"color": "#4A4A4A"}},
  {"elements": "label.text.outline", "stylers": {"color": "#FFFFFF"}},
  {"tags": {"any": ["shopping", "commercial_services", "food_and_drink"]}, "stylers": {"visibility": "off"}}
]
''';

/// Карта Яндекса: фон + три слоя (сохранённые треки, текущий/выбранный трек,
/// положение). GPS-запись от карты не зависит.
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
  ym.YandexMapController? _c;
  double _zoom = AppConfig.fallbackZoom;
  List<ym.MapObject> _prevObjs = const [];
  List<ym.MapObject> _selObjs = const [];
  Timer? _netTimer;
  bool _online = true;

  @override
  void initState() {
    super.initState();
    _prevObjs = _lines('prev', [for (final r in widget.previous) ...r],
        AppColors.prevRoute, 3.5, 1);
    _selObjs = _lines('sel', widget.highlighted, AppColors.accent, 5.5, 2);
    _netTimer = Timer.periodic(const Duration(seconds: 20), (_) => _checkNet());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNet());
  }

  @override
  void dispose() {
    _netTimer?.cancel();
    _c = null;
    super.dispose();
  }

  /// Простая проверка связи, чтобы честно сообщить, что фон карты может не
  /// загружаться. На запись трека это не влияет.
  Future<void> _checkNet() async {
    bool ok;
    try {
      final r = await InternetAddress.lookup('yandex.ru')
          .timeout(const Duration(seconds: 4));
      ok = r.isNotEmpty;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (_online && !ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        duration: Duration(seconds: 4),
        content: Text('Нет интернета: фон карты может не загружаться. '
            'Запись маршрута продолжается.'),
      ));
    }
    _online = ok;
  }

  static ym.Point _pt(double lat, double lon) =>
      ym.Point(latitude: lat, longitude: lon);

  List<ym.MapObject> _lines(String prefix, List<List<LatLon>> segs, Color color,
      double width, double z) {
    final out = <ym.MapObject>[];
    var i = 0;
    for (final s in segs) {
      if (s.length < 2) continue;
      out.add(ym.PolylineMapObject(
        mapId: ym.MapObjectId('$prefix${i++}'),
        polyline: ym.Polyline(points: [for (final p in s) _pt(p.lat, p.lon)]),
        strokeColor: color,
        strokeWidth: width,
        zIndex: z,
      ));
    }
    return out;
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

  Future<void> _onCreated(ym.YandexMapController c) async {
    _c = c;
    try {
      await c.setMapStyle(_monoStyle);
    } catch (_) {
      // Стиль не применился — остаётся стандартная карта, работа не страдает.
    }
    if (!mounted) return;
    if (widget.fitBounds != null) {
      _fit(animate: false);
      return;
    }
    final p = widget.centerOn ?? widget.position;
    if (p != null) {
      _moveTo(p.lat, p.lon, 15, animate: false);
      return;
    }
    // Положение ещё неизвестно: берём последнее известное (без запросов
    // разрешений). Если и его нет — вид всей страны, без привязки к городу.
    _moveTo(AppConfig.fallbackLat, AppConfig.fallbackLon, AppConfig.fallbackZoom,
        animate: false);
    final fix = await ref.read(locationServiceProvider).lastKnown();
    if (!mounted || fix == null) return;
    if (widget.fitBounds == null && widget.position == null) {
      _moveTo(fix.lat, fix.lon, 14, animate: false);
    }
  }

  void _moveTo(double lat, double lon, double zoom, {bool animate = true}) {
    final c = _c;
    if (c == null) return;
    _zoom = zoom;
    c.moveCamera(
      ym.CameraUpdate.newCameraPosition(
          ym.CameraPosition(target: _pt(lat, lon), zoom: zoom)),
      animation: animate
          ? ym.MapAnimation(type: ym.MapAnimationType.smooth, duration: 0.5)
          : null,
    );
  }

  void _fit({bool animate = true}) {
    final c = _c;
    final b = widget.fitBounds;
    if (c == null || b == null) return;
    final dLat = b.maxLat - b.minLat;
    final dLon = b.maxLon - b.minLon;
    // Вырожденные границы (одна точка) — просто приближаем.
    if (dLat.abs() < 1e-5 && dLon.abs() < 1e-5) {
      _moveTo(b.minLat, b.minLon, 15, animate: animate);
      return;
    }
    final mLat = (dLat * 0.18).clamp(0.0004, 5.0).toDouble();
    final mLon = (dLon * 0.18).clamp(0.0004, 5.0).toDouble();
    c.moveCamera(
      ym.CameraUpdate.newBounds(ym.BoundingBox(
        southWest: _pt(b.minLat - mLat, b.minLon - mLon),
        northEast: _pt(b.maxLat + mLat, b.maxLon + mLon),
      )),
      animation: animate
          ? ym.MapAnimation(type: ym.MapAnimationType.smooth, duration: 0.5)
          : null,
    );
  }

  /// [explicit] — нажатие «Где я»: ставим удобный масштаб. Иначе (следование)
  /// масштаб пользователя не меняем.
  void _center({bool explicit = false}) {
    final p = explicit ? (widget.centerOn ?? widget.position) : widget.position;
    if (_c == null || p == null) return;
    final z = explicit
        ? (_zoom < widget.centerZoom - 1
            ? widget.centerZoom
            : _zoom.clamp(widget.centerZoom - 1, 19).toDouble())
        : _zoom;
    _moveTo(p.lat, p.lon, z);
  }

  @override
  void didUpdateWidget(covariant TrackMap old) {
    super.didUpdateWidget(old);
    var changed = false;
    if (_differs(old.previous, widget.previous)) {
      _prevObjs = _lines('prev', [for (final r in widget.previous) ...r],
          AppColors.prevRoute, 3.5, 1);
      changed = true;
    }
    if (!identical(old.highlighted, widget.highlighted)) {
      _selObjs = _lines('sel', widget.highlighted, AppColors.accent, 5.5, 2);
      changed = true;
    }
    if (changed) setState(() {});
    if (old.fitNonce != widget.fitNonce) _fit();
    if (old.centerNonce != widget.centerNonce) _center(explicit: true);
    if (widget.follow && old.position != widget.position) _center();
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.position;
    return ym.YandexMap(
      onMapCreated: _onCreated,
      mapObjects: [
        ..._prevObjs,
        ..._selObjs,
        if (pos != null)
          ym.PlacemarkMapObject(
            mapId: ym.MapObjectId('pos'),
            point: _pt(pos.lat, pos.lon),
            icon: ym.PlacemarkIcon.single(ym.PlacemarkIconStyle(
              image: ym.BitmapDescriptor.fromAssetImage('assets/images/pos_dot.png'),
            )),
          ),
      ],
      onCameraPositionChanged: (position, reason, finished) {
        _zoom = position.zoom;
        // Только жесты пользователя отключают автоследование.
        if (reason == ym.CameraUpdateReason.gestures) {
          widget.onUserGesture?.call();
        }
      },
      onMapTap: (p) =>
          widget.onTap?.call(LatLon(p.latitude, p.longitude), _zoom),
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      // Карта забирает жесты первой: масштабирование двумя пальцами и
      // перемещение работают даже внутри прокручиваемых экранов.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }
}
