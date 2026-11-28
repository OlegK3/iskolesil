import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/format.dart';
import '../core/ids.dart';
import '../domain/models.dart';
import '../domain/track_accumulator.dart';
import '../providers.dart';
import 'location_service.dart';

enum RecStatus { idle, recording, paused }

enum GpsState { unknown, searching, good, weak, lost, disabled, denied }

class RecordingState {
  final RecStatus status;
  final String? rideId;
  final DateTime? startedAt;
  final int elapsedSeconds;
  final int movingSeconds;
  final double distanceMeters;
  final double currentSpeed; // м/с
  final double maxSpeed;
  final double? elevationGain;
  final GpsState gps;
  final double? accuracy;
  final LatLon? position;
  final double? heading; // градусы, только при достоверных данных
  final List<List<LatLon>> segments; // текущий трек для карты
  final int pointCount;

  const RecordingState({
    this.status = RecStatus.idle,
    this.rideId,
    this.startedAt,
    this.elapsedSeconds = 0,
    this.movingSeconds = 0,
    this.distanceMeters = 0,
    this.currentSpeed = 0,
    this.maxSpeed = 0,
    this.elevationGain,
    this.gps = GpsState.unknown,
    this.accuracy,
    this.position,
    this.heading,
    this.segments = const [],
    this.pointCount = 0,
  });

  bool get active => status != RecStatus.idle;
  double get averageSpeed =>
      movingSeconds > 0 ? distanceMeters / movingSeconds : 0;

  RecordingState copyWith({
    RecStatus? status,
    int? elapsedSeconds,
    int? movingSeconds,
    double? distanceMeters,
    double? currentSpeed,
    double? maxSpeed,
    double? elevationGain,
    bool clearElevation = false,
    GpsState? gps,
    double? accuracy,
    LatLon? position,
    double? heading,
    bool clearHeading = false,
    List<List<LatLon>>? segments,
    int? pointCount,
  }) =>
      RecordingState(
        status: status ?? this.status,
        rideId: rideId,
        startedAt: startedAt,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        movingSeconds: movingSeconds ?? this.movingSeconds,
        distanceMeters: distanceMeters ?? this.distanceMeters,
        currentSpeed: currentSpeed ?? this.currentSpeed,
        maxSpeed: maxSpeed ?? this.maxSpeed,
        elevationGain:
            clearElevation ? null : (elevationGain ?? this.elevationGain),
        gps: gps ?? this.gps,
        accuracy: accuracy ?? this.accuracy,
        position: position ?? this.position,
        heading: clearHeading ? null : (heading ?? this.heading),
        segments: segments ?? this.segments,
        pointCount: pointCount ?? this.pointCount,
      );

  RecordingState withRide(String id, DateTime started) => RecordingState(
        status: status,
        rideId: id,
        startedAt: started,
        elapsedSeconds: elapsedSeconds,
        movingSeconds: movingSeconds,
        distanceMeters: distanceMeters,
        currentSpeed: currentSpeed,
        maxSpeed: maxSpeed,
        elevationGain: elevationGain,
        gps: gps,
        accuracy: accuracy,
        position: position,
        heading: heading,
        segments: segments,
        pointCount: pointCount,
      );
}

class StartResult {
  final bool ok;
  final LocPermission? permission;
  const StartResult(this.ok, [this.permission]);
}

const _activeKey = 'active_ride';

/// Конечный автомат записи поездки. Каждая принятая точка сразу пишется в БД,
/// поэтому при аварийном закрытии теряется не более одной точки.
class RecordingController extends Notifier<RecordingState> {
  TrackAccumulator _acc = TrackAccumulator();
  StreamSubscription<Position>? _posSub;
  StreamSubscription<bool>? _svcSub;
  Timer? _ticker;
  Timer? _retry;
  int _pausedTotalMs = 0;
  DateTime? _pausedAt;
  DateTime? _lastFixAt;
  int _tick = 0;
  int _seg = 0;
  List<List<LatLon>> _segments = [];

  @override
  RecordingState build() {
    ref.onDispose(_cleanup);
    return const RecordingState();
  }

  LocationService get _loc => ref.read(locationServiceProvider);

  // ---------- Жизненный цикл ----------

  Future<StartResult> start() async {
    if (state.active) return const StartResult(true);
    final perm = await _loc.ensurePermission();
    if (perm != LocPermission.granted) return StartResult(false, perm);
    await _loc.requestNotificationPermission();

    final settings = ref.read(settingsProvider);
    _acc = TrackAccumulator(settings.trackingSettings);
    _pausedTotalMs = 0;
    _pausedAt = null;
    _seg = 0;
    _segments = [];
    final now = DateTime.now().toUtc();
    final ride = Ride(
      id: newId(),
      title: defaultRideTitle(now),
      startedAt: now,
      status: RideStatus.recording,
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(rideRepoProvider).insertRide(ride);
    state = const RecordingState(status: RecStatus.recording, gps: GpsState.searching)
        .withRide(ride.id, now);
    await _persistActive();
    _startStreams();
    return const StartResult(true);
  }

  Future<void> pause() async {
    if (state.status != RecStatus.recording) return;
    _pausedAt = DateTime.now().toUtc();
    _acc.breakSegment();
    state = state.copyWith(status: RecStatus.paused);
    await _persistActive();
  }

  Future<void> resume() async {
    if (state.status != RecStatus.paused) return;
    final pa = _pausedAt;
    if (pa != null) {
      _pausedTotalMs += DateTime.now().toUtc().difference(pa).inMilliseconds;
    }
    _pausedAt = null;
    _acc.breakSegment();
    state = state.copyWith(status: RecStatus.recording);
    if (_posSub == null) _startStreams();
    await _persistActive();
  }

  /// Завершает поездку и возвращает её id.
  Future<String?> finish() async {
    final id = state.rideId;
    if (id == null) return null;
    final end = (state.status == RecStatus.paused ? _pausedAt : null) ??
        DateTime.now().toUtc();
    final pausedMs = _pausedTotalMs;
    final started = state.startedAt!;
    final m = _acc.metrics;
    await _stopStreams();
    final repo = ref.read(rideRepoProvider);
    final ride = await repo.getRide(id);
    if (ride != null) {
      final elapsed =
          ((end.difference(started).inMilliseconds - pausedMs) / 1000).round();
      await repo.updateRide(ride.copyWith(
        finishedAt: end,
        durationSeconds: elapsed < 0 ? 0 : elapsed,
        movingDurationSeconds: m.movingSeconds,
        distanceMeters: m.distanceMeters,
        averageSpeed: m.averageSpeed,
        maxSpeed: m.maxSpeed,
        elevationGain: m.elevationGain,
        clearElevation: m.elevationGain == null,
        status: RideStatus.finished,
      ));
    }
    await ref.read(settingsRepoProvider).setRaw(_activeKey, null);
    state = const RecordingState();
    return id;
  }

  Future<void> discard() async {
    final id = state.rideId;
    await _stopStreams();
    if (id != null) await ref.read(rideRepoProvider).deleteRide(id);
    await ref.read(settingsRepoProvider).setRaw(_activeKey, null);
    state = const RecordingState();
  }

  // ---------- Восстановление после сбоя ----------

  /// Возвращает незавершённую поездку (если приложение было закрыто аварийно).
  Future<Ride?> findRecoverable() async {
    if (state.active) return null;
    return ref.read(rideRepoProvider).findUnfinished();
  }

  /// Продолжить: восстанавливаем метрики по сохранённым точкам. Время, когда
  /// приложение не работало, считается паузой. Запись идёт в «паузе» —
  /// пользователь сам нажимает «Продолжить».
  Future<void> resumeRecovered(Ride ride) async {
    final repo = ref.read(rideRepoProvider);
    final pts = await repo.getPoints(ride.id);
    final settings = ref.read(settingsProvider);
    _acc = TrackAccumulator(settings.trackingSettings);
    int? seg;
    final segs = <List<LatLon>>[];
    for (final p in pts) {
      if (seg != null && p.segmentIndex != seg) _acc.breakSegment();
      if (seg == null || p.segmentIndex != seg) segs.add(<LatLon>[]);
      seg = p.segmentIndex;
      _acc.addTrusted(p);
      segs.last.add(p.latLon);
    }
    _acc.breakSegment();
    _segments = segs;
    _seg = _acc.segmentIndex + 1;
    var pausedTotal = 0;
    DateTime lastKnown = pts.isNotEmpty ? pts.last.timestamp : ride.startedAt;
    try {
      final raw = await ref.read(settingsRepoProvider).getRaw(_activeKey);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (j['rideId'] == ride.id) {
          pausedTotal = (j['pausedTotalMs'] as num?)?.toInt() ?? 0;
          final upd = (j['updatedAtMs'] as num?)?.toInt();
          if (upd != null) {
            final u = DateTime.fromMillisecondsSinceEpoch(upd, isUtc: true);
            if (u.isAfter(lastKnown)) lastKnown = u;
          }
        }
      }
    } catch (_) {}
    _pausedTotalMs = pausedTotal;
    _pausedAt = lastKnown;
    final m = _acc.metrics;
    state = RecordingState(
      status: RecStatus.paused,
      gps: GpsState.searching,
      distanceMeters: m.distanceMeters,
      movingSeconds: m.movingSeconds,
      maxSpeed: m.maxSpeed,
      elevationGain: m.elevationGain,
      segments: List.of(_segments),
      pointCount: pts.length,
      position: pts.isNotEmpty ? pts.last.latLon : null,
    ).withRide(ride.id, ride.startedAt);
    await repo.updateRide(ride.copyWith(status: RideStatus.paused));
    await _persistActive();
    _startStreams();
  }

  /// Завершить восстановленную поездку без продолжения.
  Future<String?> finalizeRecovered(Ride ride) async {
    final repo = ref.read(rideRepoProvider);
    final pts = await repo.getPoints(ride.id);
    if (pts.length < 2) {
      await repo.deleteRide(ride.id);
      await ref.read(settingsRepoProvider).setRaw(_activeKey, null);
      return null;
    }
    final m = TrackAccumulator.fromPoints(
        pts, ref.read(settingsProvider).trackingSettings);
    var pausedMs = 0;
    try {
      final raw = await ref.read(settingsRepoProvider).getRaw(_activeKey);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (j['rideId'] == ride.id) {
          pausedMs = (j['pausedTotalMs'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (_) {}
    final end = pts.last.timestamp;
    final elapsed =
        ((end.difference(ride.startedAt).inMilliseconds - pausedMs) / 1000)
            .round();
    await repo.updateRide(ride.copyWith(
      finishedAt: end,
      durationSeconds: elapsed < 0 ? 0 : elapsed,
      movingDurationSeconds: m.movingSeconds,
      distanceMeters: m.distanceMeters,
      averageSpeed: m.averageSpeed,
      maxSpeed: m.maxSpeed,
      elevationGain: m.elevationGain,
      clearElevation: m.elevationGain == null,
      status: RideStatus.finished,
    ));
    await ref.read(settingsRepoProvider).setRaw(_activeKey, null);
    return ride.id;
  }

  Future<void> deleteRecovered(Ride ride) async {
    await ref.read(rideRepoProvider).deleteRide(ride.id);
    await ref.read(settingsRepoProvider).setRaw(_activeKey, null);
  }

  // ---------- Потоки ----------

  void _startStreams() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _listenPositions();
    _svcSub?.cancel();
    _svcSub = _loc.serviceEnabledStream().listen((enabled) {
      if (!state.active) return;
      if (!enabled) {
        state = state.copyWith(gps: GpsState.disabled);
      } else if (_posSub == null) {
        _listenPositions();
      }
    }, onError: (_) {});
  }

  void _listenPositions() {
    _posSub?.cancel();
    _retry?.cancel();
    try {
      _posSub = _loc.positionStream().listen(
        _onPosition,
        onError: (Object e) {
          // Отзыв разрешения / выключенная геолокация: запись не падает,
          // просто ждём и пробуем подписаться снова.
          _posSub?.cancel();
          _posSub = null;
          final gps = e is PermissionDeniedException
              ? GpsState.denied
              : GpsState.disabled;
          if (state.active) state = state.copyWith(gps: gps);
          _retry = Timer(const Duration(seconds: 5), () async {
            if (!state.active) return;
            final p = await _loc.check();
            if (p == LocPermission.granted) {
              _listenPositions();
            } else {
              state = state.copyWith(
                  gps: p == LocPermission.serviceDisabled
                      ? GpsState.disabled
                      : GpsState.denied);
              _retry = Timer(const Duration(seconds: 5), _listenPositions);
            }
          });
        },
        cancelOnError: false,
      );
    } catch (_) {
      state = state.copyWith(gps: GpsState.denied);
    }
  }

  Future<void> _stopStreams() async {
    _ticker?.cancel();
    _retry?.cancel();
    await _posSub?.cancel();
    await _svcSub?.cancel();
    _ticker = _retry = null;
    _posSub = null;
    _svcSub = null;
  }

  void _cleanup() {
    _ticker?.cancel();
    _retry?.cancel();
    _posSub?.cancel();
    _svcSub?.cancel();
  }

  void _onTick() {
    if (!state.active) return;
    _tick++;
    final started = state.startedAt!;
    final now = DateTime.now().toUtc();
    final until = state.status == RecStatus.paused ? (_pausedAt ?? now) : now;
    final elapsed =
        ((until.difference(started).inMilliseconds - _pausedTotalMs) / 1000)
            .floor();
    var gps = state.gps;
    if (gps != GpsState.disabled && gps != GpsState.denied) {
      final last = _lastFixAt;
      if (last == null) {
        gps = GpsState.searching;
      } else if (now.difference(last).inSeconds > 10) {
        gps = GpsState.lost;
      }
    }
    state = state.copyWith(
      elapsedSeconds: elapsed < 0 ? 0 : elapsed,
      gps: gps,
      currentSpeed: gps == GpsState.lost ? 0 : state.currentSpeed,
    );
    if (_tick % 15 == 0) _persistActive();
  }

  Future<void> _onPosition(Position p) async {
    if (!state.active) return;
    final fix = LocationService.toFix(p);
    _lastFixAt = DateTime.now().toUtc();
    final acc = fix.accuracy;
    final gps = acc == null || acc <= 20 ? GpsState.good : GpsState.weak;
    final pos = LatLon(fix.lat, fix.lon);
    double? heading;
    if (p.heading >= 0 && (fix.speed ?? 0) >= 1.5) heading = p.heading;

    if (state.status != RecStatus.recording) {
      state = state.copyWith(
          gps: gps,
          accuracy: acc,
          position: pos,
          heading: heading,
          clearHeading: heading == null);
      return;
    }
    final res = _acc.add(fix);
    if (res.accepted) {
      final point = TrackPoint(
        id: newId(),
        rideId: state.rideId!,
        latitude: fix.lat,
        longitude: fix.lon,
        altitude: fix.altitude,
        speed: fix.speed,
        accuracy: fix.accuracy,
        timestamp: fix.time,
        segmentIndex: res.segmentIndex,
      );
      try {
        await ref.read(rideRepoProvider).addPoint(point);
      } catch (_) {
        // Ошибка записи не должна останавливать запись остальных точек.
      }
      if (res.decision == FixDecision.acceptedNewSegment || _segments.isEmpty) {
        _segments = [..._segments, <LatLon>[]];
      }
      _segments.last.add(pos);
    }
    final m = _acc.metrics;
    state = state.copyWith(
      gps: gps,
      accuracy: acc,
      position: pos,
      heading: heading,
      clearHeading: heading == null,
      currentSpeed: fix.speed ?? state.currentSpeed,
      distanceMeters: m.distanceMeters,
      movingSeconds: m.movingSeconds,
      maxSpeed: m.maxSpeed,
      elevationGain: m.elevationGain,
      clearElevation: m.elevationGain == null,
      segments: res.accepted ? List.of(_segments) : null,
      pointCount: res.accepted ? state.pointCount + 1 : null,
    );
  }

  Future<void> _persistActive() async {
    final id = state.rideId;
    if (id == null) return;
    await ref.read(settingsRepoProvider).setRaw(
        _activeKey,
        jsonEncode({
          'rideId': id,
          'pausedTotalMs': _pausedTotalMs,
          'pausedAtMs': _pausedAt?.millisecondsSinceEpoch,
          'updatedAtMs': DateTime.now().toUtc().millisecondsSinceEpoch,
        }));
    final repo = ref.read(rideRepoProvider);
    final ride = await repo.getRide(id);
    if (ride != null) {
      await repo.updateRide(ride.copyWith(
          status: state.status == RecStatus.paused
              ? RideStatus.paused
              : RideStatus.recording));
    }
  }
}

final recordingProvider =
    NotifierProvider<RecordingController, RecordingState>(RecordingController.new);
