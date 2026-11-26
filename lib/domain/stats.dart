import 'models.dart';

enum StatsPeriod { week, month, year, all }

class PeriodStats {
  final int rideCount;
  final double distanceMeters;
  final int durationSeconds;
  final int movingSeconds;
  final double maxSpeed;
  final Ride? longestByDistance;
  final Ride? longestByDuration;
  final double? elevationGain;

  const PeriodStats({
    required this.rideCount,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.movingSeconds,
    required this.maxSpeed,
    this.longestByDistance,
    this.longestByDuration,
    this.elevationGain,
  });

  /// Средняя скорость = суммарное расстояние / суммарное время движения.
  /// (Не среднее арифметическое скоростей отдельных поездок.)
  double get averageSpeed =>
      movingSeconds > 0 ? distanceMeters / movingSeconds : 0;
}

class StatsCalculator {
  static PeriodStats compute(Iterable<Ride> rides) {
    var count = 0;
    var dist = 0.0;
    var dur = 0, mov = 0;
    var maxS = 0.0;
    Ride? longD, longT;
    double? gain;
    for (final r in rides) {
      if (r.status != RideStatus.finished) continue;
      count++;
      dist += r.distanceMeters;
      dur += r.durationSeconds;
      mov += r.movingDurationSeconds;
      if (r.maxSpeed > maxS) maxS = r.maxSpeed;
      if (longD == null || r.distanceMeters > longD.distanceMeters) longD = r;
      if (longT == null || r.durationSeconds > longT.durationSeconds) longT = r;
      if (r.elevationGain != null) gain = (gain ?? 0) + r.elevationGain!;
    }
    return PeriodStats(
      rideCount: count,
      distanceMeters: dist,
      durationSeconds: dur,
      movingSeconds: mov,
      maxSpeed: maxS,
      longestByDistance: longD,
      longestByDuration: longT,
      elevationGain: gain,
    );
  }

  /// Начало периода в локальном времени. Неделя — с понедельника.
  static DateTime? periodStart(StatsPeriod p, DateTime now) {
    final n = now.toLocal();
    switch (p) {
      case StatsPeriod.week:
        final d = DateTime(n.year, n.month, n.day);
        return d.subtract(Duration(days: n.weekday - 1));
      case StatsPeriod.month:
        return DateTime(n.year, n.month, 1);
      case StatsPeriod.year:
        return DateTime(n.year, 1, 1);
      case StatsPeriod.all:
        return null;
    }
  }

  static List<Ride> filter(List<Ride> rides, StatsPeriod p, DateTime now) {
    final start = periodStart(p, now);
    if (start == null) return rides.where((r) => r.status == RideStatus.finished).toList();
    return rides
        .where((r) =>
            r.status == RideStatus.finished &&
            !r.startedAt.toLocal().isBefore(start))
        .toList();
  }

  /// Расстояние по дням: [days] последних дней, заканчивая [end] (локальная дата).
  static List<(DateTime, double)> distanceByDay(
      List<Ride> rides, DateTime start, int days) {
    final out = <(DateTime, double)>[];
    for (var i = 0; i < days; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      var sum = 0.0;
      for (final r in rides) {
        final l = r.startedAt.toLocal();
        if (l.year == day.year && l.month == day.month && l.day == day.day) {
          sum += r.distanceMeters;
        }
      }
      out.add((day, sum));
    }
    return out;
  }

  /// Расстояние по месяцам: [months] месяцев, начиная с [start].
  static List<(DateTime, double)> distanceByMonth(
      List<Ride> rides, DateTime start, int months) {
    final out = <(DateTime, double)>[];
    for (var i = 0; i < months; i++) {
      final m = DateTime(start.year, start.month + i, 1);
      var sum = 0.0;
      for (final r in rides) {
        final l = r.startedAt.toLocal();
        if (l.year == m.year && l.month == m.month) sum += r.distanceMeters;
      }
      out.add((m, sum));
    }
    return out;
  }
}
