import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/geo.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../widgets/common.dart';
import '../widgets/track_map.dart';
import 'ride_detail_screen.dart';

class MyMapScreen extends ConsumerStatefulWidget {
  const MyMapScreen({super.key});
  @override
  ConsumerState<MyMapScreen> createState() => _MyMapScreenState();
}

class _MyMapScreenState extends ConsumerState<MyMapScreen> {
  String? _selected;
  DateTimeRange? _range;
  int _fitNonce = 0;

  List<Ride> _visible(List<Ride> rides, Set<String> hidden) => rides.where((r) {
        if (hidden.contains(r.id)) return false;
        if (_range != null) {
          final d = r.startedAt.toLocal();
          final from = DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
          final to = DateTime(_range!.end.year, _range!.end.month, _range!.end.day + 1);
          if (d.isBefore(from) || !d.isBefore(to)) return false;
        }
        return true;
      }).toList();

  void _onTap(LatLon p, double zoom, Map<String, List<List<LatLon>>> segs, List<Ride> visible) {
    // Порог выбора ~28 px на текущем масштабе.
    final mPerPx = 156543.03 * math.cos(p.lat * math.pi / 180) / math.pow(2, zoom);
    final threshold = 28 * mPerPx;
    String? best;
    var bestD = double.infinity;
    for (final r in visible) {
      for (final s in segs[r.id] ?? const <List<LatLon>>[]) {
        final d = distanceToPolyline(p, s);
        if (d < bestD) {
          bestD = d;
          best = r.id;
        }
      }
    }
    setState(() => _selected = bestD <= threshold ? best : null);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (r != null) setState(() {
      _range = r;
      _fitNonce++;
    });
  }

  void _hideSheet(List<Ride> rides) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (c) => Consumer(builder: (c, ref, _) {
        final hidden = ref.watch(settingsProvider).hiddenRideIds;
        final units = ref.watch(settingsProvider).measurementUnits;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (c, sc) => ListView(
            controller: sc,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Показывать на карте',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              for (final r in rides)
                SwitchListTile(
                  value: !hidden.contains(r.id),
                  title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${fmtDate(r.startedAt)} · ${fmtDistance(r.distanceMeters, units)}'),
                  onChanged: (v) => ref.read(settingsProvider.notifier).update((s) {
                    final set = {...s.hiddenRideIds};
                    v ? set.remove(r.id) : set.add(r.id);
                    return s.copyWith(hiddenRideIds: set);
                  }),
                ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ridesAsync = ref.watch(ridesProvider);
    final segsAsync = ref.watch(allSegmentsProvider);
    final settings = ref.watch(settingsProvider);
    final units = settings.measurementUnits;
    final rides = ridesAsync.valueOrNull ?? const <Ride>[];
    final segs = segsAsync.valueOrNull ?? const <String, List<List<LatLon>>>{};
    final visible = _visible(rides, settings.hiddenRideIds);
    final selectedRide = visible.where((r) => r.id == _selected).firstOrNull;

    final prev = <List<List<LatLon>>>[
      for (final r in visible)
        if (r.id != _selected && segs[r.id] != null) segs[r.id]!
    ];
    final high = selectedRide == null ? const <List<LatLon>>[] : (segs[selectedRide.id] ?? const []);
    final fit = boundsOfSegments([
      for (final r in visible) ...(segs[r.id] ?? const <List<LatLon>>[])
    ]);
    final totalDist = visible.fold<double>(0, (a, r) => a + r.distanceMeters);
    final totalDur = visible.fold<int>(0, (a, r) => a + r.durationSeconds);
    final dist = distanceParts(totalDist, units);

    return Stack(
      children: [
        Positioned.fill(
          child: TrackMap(
            previous: prev,
            highlighted: high,
            fitBounds: selectedRide != null ? boundsOfSegments(high) : fit,
            fitNonce: _fitNonce + visible.length * 1000 + (segs.isEmpty ? 0 : 1),
            onTap: (p, z) => _onTap(p, z, segs, visible),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                        child: BigStat(
                            value: dist.$1, unit: dist.$2, label: 'Километраж', size: 24)),
                    Expanded(
                        child: BigStat(
                            value: fmtDurationLong(totalDur), label: 'Время', size: 20)),
                    Expanded(
                        child: BigStat(
                            value: '${visible.length}', label: 'Поездок', size: 24)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  _Chip(
                    icon: Icons.date_range_outlined,
                    label: _range == null
                        ? 'Все даты'
                        : '${fmtDate(_range!.start)} – ${fmtDate(_range!.end)}',
                    onTap: _pickRange,
                    onClear: _range == null
                        ? null
                        : () => setState(() {
                              _range = null;
                              _fitNonce++;
                            }),
                  ),
                  const SizedBox(width: 8),
                  _Chip(
                    icon: Icons.visibility_outlined,
                    label: settings.hiddenRideIds.isEmpty
                        ? 'Треки'
                        : 'Скрыто: ${settings.hiddenRideIds.length}',
                    onTap: () => _hideSheet(rides),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    backgroundColor: AppColors.card,
                    child: IconButton(
                      tooltip: 'Показать все маршруты',
                      icon: const Icon(Icons.fit_screen_outlined, color: AppColors.text),
                      onPressed: () => setState(() {
                        _selected = null;
                        _fitNonce++;
                      }),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
        if (rides.isEmpty)
          const Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Здесь появятся все ваши поездки. Пока их нет.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.secondary, fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
        if (selectedRide != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: AppCard(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RideDetailScreen(rideId: selectedRide.id))),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selectedRide.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                          '${fmtDate(selectedRide.startedAt)} · ${fmtDistance(selectedRide.distanceMeters, units)} · ${fmtDuration(selectedRide.durationSeconds)}',
                          style: const TextStyle(color: AppColors.secondary)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.secondary),
              ]),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap, this.onClear});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (onClear != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                    onTap: onClear,
                    child: const Icon(Icons.close, size: 16, color: AppColors.secondary)),
              ],
            ]),
          ),
        ),
      );
}
