import 'geo.dart';
import 'models.dart';

/// Сырое измерение GPS (уже приведённое к null для неизвестных значений).
class Fix {
  final double lat;
  final double lon;
  final double? altitude;
  final double? speed; // м/с
  final double? accuracy; // м
  final DateTime time;
  const Fix({
    required this.lat,
    required this.lon,
    this.altitude,
    this.speed,
    this.accuracy,
    required this.time,
  });
}

enum FixDecision {
  accepted,
  acceptedNewSegment,
  rejectedAccuracy,
  rejectedJump,
  rejectedDrift,
  rejectedDuplicate,
}

class AcceptResult {
  final FixDecision decision;
  final int segmentIndex;
  const AcceptResult(this.decision, this.segmentIndex);
  bool get accepted =>
      decision == FixDecision.accepted ||
      decision == FixDecision.acceptedNewSegment;
}

class RideMetrics {
  final double distanceMeters;
  final int movingSeconds;
  final double maxSpeed;
  final double? elevationGain;
  const RideMetrics(
      this.distanceMeters, this.movingSeconds, this.maxSpeed, this.elevationGain);

  double get averageSpeed =>
      movingSeconds > 0 ? distanceMeters / movingSeconds : 0;
}

class _ElevationGain {
  final int window;
  final double threshold;
  _ElevationGain(this.window, this.threshold);
  final List<double> _buf = [];
  double? _ref;
  double gain = 0;

  void add(double alt) {
    _buf.add(alt);
    if (_buf.length > window) _buf.removeAt(0);
    final avg = _buf.reduce((a, b) => a + b) / _buf.length;
    final ref = _ref;
    if (ref == null) {
      _ref = avg;
      return;
    }
    final diff = avg - ref;
    if (diff >= threshold) {
      gain += diff;
      _ref = avg;
    } else if (diff <= -threshold) {
      _ref = avg;
    }
  }
}

/// Фильтрация GPS-точек и накопление метрик поездки.
///
/// Правила (пороги — в [TrackingConfig], описаны в docs/ARCHITECTURE.md):
///  1. accuracy > maxAccuracyM — точка отбрасывается.
///  2. Пауза между любыми полученными измерениями > gapSeconds или ручная
///     пауза — новый сегмент; расстояние через разрыв не начисляется.
///  3. Скачок: implied speed > maxJumpSpeedMs — точка отбрасывается;
///     maxConsecutiveJumps подряд — принимаем как начало нового сегмента.
///  4. Дрейф: смещение < minMoveM, либо (скорость < driftSpeedMs и смещение
///     меньше accuracy) — точка отбрасывается.
///  5. Время движения: сумма интервалов между принятыми точками одного
///     сегмента, где расстояние/время >= movingSpeedMs.
class TrackAccumulator {
  TrackAccumulator([this.config = const TrackingConfig()])
      : _elev = _ElevationGain(config.elevationWindow, config.elevationThresholdM);

  final TrackingConfig config;
  final _ElevationGain _elev;

  double distanceMeters = 0;
  int movingMs = 0;
  double maxSpeed = 0;
  int acceptedCount = 0;
  int _altCount = 0;
  int segmentIndex = 0;

  _Last? _last;
  DateTime? _lastFixTime;
  bool _breakSegment = false;
  int _jumpStreak = 0;
  final List<double> _speedWin = [];

  /// Следующая принятая точка начнёт новый сегмент (пауза/возобновление).
  void breakSegment() => _breakSegment = true;

  int get movingSeconds => movingMs ~/ 1000;

  double? get elevationGain {
    if (acceptedCount < 10) return null;
    if (_altCount / acceptedCount < 0.8) return null;
    return _elev.gain;
  }

  RideMetrics get metrics =>
      RideMetrics(distanceMeters, movingSeconds, maxSpeed, elevationGain);

  AcceptResult add(Fix f) {
    final prevFix = _lastFixTime;
    _lastFixTime = f.time;
    if (prevFix != null &&
        f.time.difference(prevFix).inMilliseconds > config.gapSeconds * 1000) {
      _breakSegment = true;
    }
    final acc = f.accuracy;
    if (acc != null && acc > config.maxAccuracyM) {
      return AcceptResult(FixDecision.rejectedAccuracy, segmentIndex);
    }
    final last = _last;
    if (last == null || _breakSegment) {
      if (last != null) segmentIndex++;
      _breakSegment = false;
      _jumpStreak = 0;
      _speedWin.clear();
      _commit(f, 0, 0, newSegment: true);
      return AcceptResult(FixDecision.acceptedNewSegment, segmentIndex);
    }
    final dtMs = f.time.difference(last.time).inMilliseconds;
    if (dtMs <= 0) {
      return AcceptResult(FixDecision.rejectedDuplicate, segmentIndex);
    }
    final d = haversine(last.lat, last.lon, f.lat, f.lon);
    final dt = dtMs / 1000.0;
    if (d / dt > config.maxJumpSpeedMs) {
      _jumpStreak++;
      if (_jumpStreak >= config.maxConsecutiveJumps) {
        segmentIndex++;
        _jumpStreak = 0;
        _speedWin.clear();
        _commit(f, 0, 0, newSegment: true);
        return AcceptResult(FixDecision.acceptedNewSegment, segmentIndex);
      }
      return AcceptResult(FixDecision.rejectedJump, segmentIndex);
    }
    _jumpStreak = 0;
    final s = f.speed;
    final drift = d < config.minMoveM ||
        (s != null &&
            s < config.driftSpeedMs &&
            d < (acc != null && acc > config.minMoveM ? acc : config.minMoveM));
    if (drift) {
      return AcceptResult(FixDecision.rejectedDrift, segmentIndex);
    }
    _commit(f, d, dtMs);
    return AcceptResult(FixDecision.accepted, segmentIndex);
  }

  void _commit(Fix f, double d, int dtMs, {bool newSegment = false}) {
    if (!newSegment) {
      distanceMeters += d;
      final dt = dtMs / 1000.0;
      final implied = dt > 0 ? d / dt : 0.0;
      if (implied >= config.movingSpeedMs) movingMs += dtMs;
      var sample = f.speed ?? implied;
      if (sample < 0) sample = 0;
      if (sample > config.maxJumpSpeedMs) sample = config.maxJumpSpeedMs;
      _speedWin.add(sample);
      if (_speedWin.length > 3) _speedWin.removeAt(0);
      if (_speedWin.length == 3) {
        final avg = (_speedWin[0] + _speedWin[1] + _speedWin[2]) / 3;
        if (avg > maxSpeed) maxSpeed = avg;
      }
    }
    acceptedCount++;
    if (f.altitude != null) {
      _altCount++;
      _elev.add(f.altitude!);
    }
    _last = _Last(f.lat, f.lon, f.time);
  }

  /// Пересчёт метрик по уже сохранённым (отфильтрованным) точкам:
  /// восстановление после сбоя, импорт GPX, демо.
  static RideMetrics fromPoints(List<TrackPoint> points,
      [TrackingConfig config = const TrackingConfig()]) {
    final acc = TrackAccumulator(config);
    int? seg;
    for (final p in points) {
      if (seg != null && p.segmentIndex != seg) acc.breakSegment();
      seg = p.segmentIndex;
      acc.addTrusted(p);
    }
    return acc.metrics;
  }

  /// Добавление уже отфильтрованной точки без повторной фильтрации.
  void addTrusted(TrackPoint p) {
    final f = Fix(
      lat: p.latitude,
      lon: p.longitude,
      altitude: p.altitude,
      speed: p.speed,
      accuracy: p.accuracy,
      time: p.timestamp,
    );
    final last = _last;
    if (last == null || _breakSegment) {
      if (last != null) segmentIndex++;
      _breakSegment = false;
      _speedWin.clear();
      _commit(f, 0, 0, newSegment: true);
      return;
    }
    final dtMs = f.time.difference(last.time).inMilliseconds;
    if (dtMs <= 0) return;
    final d = haversine(last.lat, last.lon, f.lat, f.lon);
    _commit(f, d, dtMs);
  }
}

class _Last {
  final double lat;
  final double lon;
  final DateTime time;
  _Last(this.lat, this.lon, this.time);
}
