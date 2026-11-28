import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../services/recording_controller.dart';
import '../widgets/common.dart';
import '../widgets/locate_button.dart';
import '../widgets/track_map.dart';
import 'ride_detail_screen.dart';

class ActiveRideScreen extends ConsumerStatefulWidget {
  const ActiveRideScreen({super.key});
  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen> {
  bool _finishing = false;
  bool _follow = true;
  bool _showPrev = true;
  int _centerNonce = 0;
  LatLon? _locatePos;

  (Color, String) _gpsInfo(GpsState g) => switch (g) {
        GpsState.good => (AppColors.gps, 'GPS: хороший сигнал'),
        GpsState.weak => (const Color(0xFFE6A100), 'GPS: слабый сигнал'),
        GpsState.searching => (const Color(0xFFE6A100), 'GPS: поиск спутников'),
        GpsState.lost => (AppColors.accent, 'GPS: сигнал потерян'),
        GpsState.disabled => (AppColors.accent, 'Геолокация выключена'),
        GpsState.denied => (AppColors.accent, 'Нет разрешения на GPS'),
        GpsState.unknown => (AppColors.secondary, 'GPS'),
      };

  Future<void> _locate() async {
    final p = await locateUser(context, ref);
    if (p == null || !mounted) return;
    setState(() {
      _locatePos = p;
      _follow = true; // во время поездки камера следует за пользователем
      _centerNonce++;
    });
  }

  Future<void> _finish() async {
    final ctrl = ref.read(recordingProvider.notifier);
    final st = ref.read(recordingProvider);
    final short = st.distanceMeters < 50;
    final ok = await confirm(context,
        title: 'Завершить поездку?',
        text: short
            ? 'Пройдено меньше 50 м. Её можно сохранить или удалить на следующем экране.'
            : 'Запись будет остановлена и поездка сохранена.',
        yes: 'Завершить');
    if (!ok || !mounted) return;
    _finishing = true;
    final id = await ctrl.finish();
    bumpRides(ref);
    if (!mounted) return;
    if (id == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => RideDetailScreen(rideId: id, isNew: true)));
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(recordingProvider);
    final settings = ref.watch(settingsProvider);
    final units = settings.measurementUnits;
    final all = ref.watch(allSegmentsProvider).valueOrNull ?? const {};

    if (!st.active && !_finishing) {
      // Поездка завершена/удалена — возвращаемся.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }

    final (gpsColor, gpsText) = _gpsInfo(st.gps);
    final paused = st.status == RecStatus.paused;
    final dist = distanceParts(st.distanceMeters, units);
    final cur = speedParts(st.currentSpeed, units);

    return Scaffold(
      // Карта — над панелью, а не под ней: логотип Яндекса остаётся видимым.
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
          Positioned.fill(
            child: TrackMap(
              previous: _showPrev && settings.showPreviousRoutes
                  ? [for (final e in all.entries) e.value]
                  : const [],
              highlighted: st.segments,
              position: st.position,
              follow: _follow,
              centerNonce: _centerNonce,
              centerOn: _locatePos ?? st.position,
              onUserGesture: () {
                if (_follow) setState(() => _follow = false);
              },
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.card,
                    child: IconButton(
                      tooltip: 'Назад',
                      icon: const Icon(Icons.arrow_back, color: AppColors.text),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GpsDot(color: gpsColor, label: gpsText),
                      if (paused) ...[
                        const SizedBox(height: 6),
                        const GpsDot(color: AppColors.accent, label: 'Пауза'),
                      ],
                    ],
                  ),
                  const Spacer(),
                  Column(
                    children: [
                      LocateButton(onPressed: _locate),
                      const SizedBox(height: 8),
                      _MapButton(
                        icon: Icons.layers_outlined,
                        active: _showPrev,
                        onTap: () => setState(() => _showPrev = !_showPrev),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
              ],
            ),
          ),
          Container(
              decoration: const BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 16)],
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: BigStat(
                              value: dist.$1, unit: dist.$2, label: 'Расстояние', size: 44)),
                      Expanded(
                          child: BigStat(
                              value: fmtDuration(st.elapsedSeconds),
                              label: 'Время',
                              size: 44)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: BigStat(
                              value: cur.$1, unit: cur.$2, label: 'Скорость', size: 22)),
                      Expanded(
                          child: BigStat(
                              value: speedParts(st.averageSpeed, units).$1,
                              label: 'Средняя',
                              size: 22)),
                      Expanded(
                          child: BigStat(
                              value: speedParts(st.maxSpeed, units).$1,
                              label: 'Макс.',
                              size: 22)),
                      Expanded(
                          child: BigStat(
                              value: fmtElevation(st.elevationGain, units),
                              label: 'Набор',
                              size: 22)),
                      if (st.heading != null)
                        Transform.rotate(
                          angle: st.heading! * math.pi / 180,
                          child: const Icon(Icons.navigation_outlined,
                              color: AppColors.accent),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 60)),
                          icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                          label: Text(paused ? 'Продолжить' : 'Пауза'),
                          onPressed: () {
                            final c = ref.read(recordingProvider.notifier);
                            paused ? c.resume() : c.pause();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 60)),
                          onPressed: _finish,
                          child: const Text('Завершить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap, this.active = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => CircleAvatar(
        backgroundColor: AppColors.card,
        child: IconButton(
          icon: Icon(icon, color: active ? AppColors.accent : AppColors.text),
          onPressed: onTap,
        ),
      );
}
