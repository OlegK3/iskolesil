import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/geo.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../providers.dart';
import '../../services/demo_data.dart';
import '../widgets/common.dart';
import '../widgets/track_map.dart';

/// Демонстрационный режим. Данные живут только в памяти этого экрана.
class DemoScreen extends ConsumerStatefulWidget {
  const DemoScreen({super.key});
  @override
  ConsumerState<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends ConsumerState<DemoScreen>
    with SingleTickerProviderStateMixin {
  late final List<DemoRide> _rides = DemoData.build();
  late final AnimationController _anim;
  int _selected = 0;
  int _fitNonce = 1;
  bool _playing = false;
  late List<List<LatLon>> _segments;
  late final List<List<List<LatLon>>> _allSegs = [
    for (final r in _rides) groupSegments(r.points)
  ];
  late List<List<List<LatLon>>> _prev;

  DemoRide get _cur => _rides[_selected];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 30))
      ..addListener(() => setState(() {}))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) setState(() => _playing = false);
      });
    _segments = _allSegs[_selected];
    _prev = _others();
  }

  List<List<List<LatLon>>> _others() => [
        for (var i = 0; i < _allSegs.length; i++)
          if (i != _selected) _allSegs[i]
      ];

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _select(int i) {
    _anim.stop();
    _anim.value = 0;
    setState(() {
      _selected = i;
      _playing = false;
      _segments = _allSegs[_selected];
      _prev = _others();
      _fitNonce++;
    });
  }

  void _togglePlay() {
    if (_playing) {
      _anim.stop();
      setState(() => _playing = false);
    } else {
      if (_anim.value >= 1) _anim.value = 0;
      _anim.forward();
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(settingsProvider).measurementUnits;
    final pts = _cur.points;
    final idx = (_anim.value * (pts.length - 1)).round().clamp(0, pts.length - 1).toInt();
    final simulating = _playing || _anim.value > 0;
    final pos = simulating ? pts[idx].latLon : null;
    // Показатели симуляции — по пройденной части трека.
    final done = simulating ? TrackAccumulatorSlice.metrics(pts, idx) : null;
    final all = StatsCalculator.compute([for (final r in _rides) r.ride]);

    return Scaffold(
      appBar: AppBar(title: const Text('Демонстрационный режим')),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: AppColors.accent,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: const Text(
            'ДЕМО · синтетические данные, не вошли в вашу статистику',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        Expanded(
          flex: 5,
          child: TrackMap(
            previous: _prev,
            highlighted: _segments,
            position: pos,
            fitBounds: boundsOfSegments(_segments),
            fitNonce: _fitNonce,
          ),
        ),
        Expanded(
          flex: 5,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Row(children: [
                  Expanded(
                      child: BigStat(
                          value: distanceParts(done?.distanceMeters ?? _cur.ride.distanceMeters, units).$1,
                          unit: distanceParts(done?.distanceMeters ?? _cur.ride.distanceMeters, units).$2,
                          label: simulating ? 'Симуляция' : 'Расстояние',
                          size: 28)),
                  Expanded(
                      child: BigStat(
                          value: fmtDuration(simulating
                              ? pts[idx].timestamp.difference(pts.first.timestamp).inSeconds
                              : _cur.ride.durationSeconds),
                          label: 'Время',
                          size: 28)),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: AppColors.accent),
                    iconSize: 30,
                    onPressed: _togglePlay,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  ),
                ]),
              ),
              const SectionTitle('Тестовые маршруты'),
              for (var i = 0; i < _rides.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () => _select(i),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      Icon(i == _selected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: i == _selected ? AppColors.accent : AppColors.unvisited),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(_rides[i].ride.title,
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(fmtDistance(_rides[i].ride.distanceMeters, units),
                          style: const TextStyle(color: AppColors.secondary)),
                    ]),
                  ),
                ),
              const SectionTitle('Тестовая статистика'),
              AppCard(
                child: Row(children: [
                  Expanded(
                      child: BigStat(
                          value: distanceParts(all.distanceMeters, units).$1,
                          unit: distanceParts(all.distanceMeters, units).$2,
                          label: 'Всего',
                          size: 24)),
                  Expanded(
                      child: BigStat(
                          value: speedParts(all.averageSpeed, units).$1,
                          unit: speedParts(all.averageSpeed, units).$2,
                          label: 'Средняя',
                          size: 24)),
                  Expanded(
                      child: BigStat(value: '${all.rideCount}', label: 'Маршрутов', size: 24)),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Динозавр нарисован по условным координатам и не следует дорогам.',
                  style: TextStyle(fontSize: 12, color: AppColors.secondary),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Метрики по первым [upTo]+1 точкам демо-трека.
class TrackAccumulatorSlice {
  static ({double distanceMeters}) metrics(List<TrackPoint> pts, int upTo) {
    var d = 0.0;
    for (var i = 1; i <= upTo && i < pts.length; i++) {
      d += haversine(pts[i - 1].latitude, pts[i - 1].longitude, pts[i].latitude,
          pts[i].longitude);
    }
    return (distanceMeters: d);
  }
}
