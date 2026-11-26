import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../providers.dart';
import '../widgets/common.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});
  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsPeriod _period = StatsPeriod.week;

  static const _labels = {
    StatsPeriod.week: 'Неделя',
    StatsPeriod.month: 'Месяц',
    StatsPeriod.year: 'Год',
    StatsPeriod.all: 'Всё время',
  };

  @override
  Widget build(BuildContext context) {
    final rides = ref.watch(ridesProvider).valueOrNull ?? const <Ride>[];
    final units = ref.watch(settingsProvider).measurementUnits;
    final now = DateTime.now();
    final filtered = StatsCalculator.filter(rides, _period, now);
    final s = StatsCalculator.compute(filtered);
    final chart = _chartData(filtered, now);
    final dist = distanceParts(s.distanceMeters, units);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text('Статистика',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          ),
          SegmentedButton<StatsPeriod>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              backgroundColor: AppColors.card,
              selectedBackgroundColor: AppColors.accent,
              selectedForegroundColor: Colors.white,
              foregroundColor: AppColors.text,
            ),
            segments: [
              for (final e in _labels.entries)
                ButtonSegment(value: e.key, label: Text(e.value, style: const TextStyle(fontSize: 12))),
            ],
            selected: {_period},
            onSelectionChanged: (v) => setState(() => _period = v.first),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: BigStat(
                        value: dist.$1, unit: dist.$2, label: 'Расстояние', size: 38)),
                Expanded(
                    child: BigStat(
                        value: '${s.rideCount}', label: 'Поездок', size: 38)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: BigStat(
                        value: fmtDurationLong(s.durationSeconds),
                        label: 'Общее время',
                        size: 22)),
                Expanded(
                    child: BigStat(
                        value: fmtDurationLong(s.movingSeconds),
                        label: 'В движении',
                        size: 22)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: BigStat(
                        value: speedParts(s.averageSpeed, units).$1,
                        unit: speedParts(s.averageSpeed, units).$2,
                        label: 'Средняя',
                        size: 22)),
                Expanded(
                    child: BigStat(
                        value: speedParts(s.maxSpeed, units).$1,
                        unit: speedParts(s.maxSpeed, units).$2,
                        label: 'Максимальная',
                        size: 22)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: BigStat(
                        value: s.longestByDistance == null
                            ? '—'
                            : fmtDistance(s.longestByDistance!.distanceMeters, units),
                        label: 'Самая длинная',
                        size: 20)),
                Expanded(
                    child: BigStat(
                        value: s.longestByDuration == null
                            ? '—'
                            : fmtDurationLong(s.longestByDuration!.durationSeconds),
                        label: 'Самая долгая',
                        size: 20)),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: BigStat(
                        value: fmtElevation(s.elevationGain, units),
                        label: 'Набор высоты',
                        size: 20)),
                const Spacer(),
              ]),
            ]),
          ),
          SectionTitle(
              _period == StatsPeriod.week || _period == StatsPeriod.month
                  ? 'Расстояние по дням'
                  : 'Расстояние по месяцам'),
          AppCard(
            child: SizedBox(
              height: 180,
              child: s.rideCount == 0
                  ? const Center(
                      child: Text('Нет данных за период',
                          style: TextStyle(color: AppColors.secondary)))
                  : _BarChart(data: chart, units: units),
            ),
          ),
        ],
      ),
    );
  }

  List<(String, double)> _chartData(List<Ride> rides, DateTime now) {
    final n = now.toLocal();
    switch (_period) {
      case StatsPeriod.week:
        final start = StatsCalculator.periodStart(_period, n)!;
        return [
          for (final (d, v) in StatsCalculator.distanceByDay(rides, start, 7))
            (weekdayShort(d), v)
        ];
      case StatsPeriod.month:
        final start = StatsCalculator.periodStart(_period, n)!;
        final days = DateTime(n.year, n.month + 1, 0).day;
        return [
          for (final (d, v) in StatsCalculator.distanceByDay(rides, start, days))
            ('${d.day}', v)
        ];
      case StatsPeriod.year:
        return [
          for (final (d, v) in StatsCalculator.distanceByMonth(rides, DateTime(n.year, 1, 1), 12))
            (monthName(d.month).substring(0, 3), v)
        ];
      case StatsPeriod.all:
        if (rides.isEmpty) return const [];
        final first = rides
            .map((r) => r.startedAt.toLocal())
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final start = DateTime(first.year, first.month, 1);
        final months = (n.year - start.year) * 12 + n.month - start.month + 1;
        final cap = months > 24 ? 24 : months;
        final from = DateTime(n.year, n.month - cap + 1, 1);
        return [
          for (final (d, v) in StatsCalculator.distanceByMonth(rides, from, cap))
            ('${monthName(d.month).substring(0, 3)}', v)
        ];
    }
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.data, required this.units});
  final List<(String, double)> data;
  final MeasurementUnits units;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.infinite, painter: _BarPainter(data, units));
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.data, this.units);
  final List<(String, double)> data;
  final MeasurementUnits units;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    const bottom = 22.0, top = 16.0;
    final maxV = data.map((e) => e.$2).fold<double>(0, (a, b) => b > a ? b : a);
    final plotH = size.height - bottom - top;
    final slot = size.width / data.length;
    final barW = slot * 0.62;
    final base = Paint()..color = AppColors.divider;
    canvas.drawRect(Rect.fromLTWH(0, size.height - bottom, size.width, 1), base);
    final step = data.length > 14 ? (data.length / 7).ceil() : 1;
    for (var i = 0; i < data.length; i++) {
      final v = data[i].$2;
      final h = maxV == 0 ? 0.0 : v / maxV * plotH;
      final x = i * slot + (slot - barW) / 2;
      if (v > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x, top + plotH - h, barW, h), const Radius.circular(3)),
          Paint()..color = AppColors.accent,
        );
      } else {
        canvas.drawRect(
            Rect.fromLTWH(x, size.height - bottom - 2, barW, 2),
            Paint()..color = AppColors.unvisited);
      }
      if (i % step == 0) {
        final tp = TextPainter(
          text: TextSpan(
              text: data[i].$1,
              style: const TextStyle(fontSize: 10, color: AppColors.secondary)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: slot * step);
        tp.paint(canvas, Offset(i * slot + (slot - tp.width) / 2, size.height - bottom + 5));
      }
      if (v > 0 && v == maxV) {
        final (val, unit) = distanceParts(v, units);
        final tp = TextPainter(
          text: TextSpan(
              text: '$val $unit',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text)),
          textDirection: TextDirection.ltr,
        )..layout();
        final dx = (x + barW / 2 - tp.width / 2).clamp(0.0, size.width - tp.width).toDouble();
        tp.paint(canvas, Offset(dx, top + plotH - h - 15));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.data != data;
}
