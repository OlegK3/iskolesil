import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../widgets/common.dart';
import '../widgets/route_painter.dart';
import 'ride_detail_screen.dart';

enum _Sort { date, distance, duration }

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  _Sort _sort = _Sort.date;

  @override
  Widget build(BuildContext context) {
    final ridesAsync = ref.watch(ridesProvider);
    final units = ref.watch(settingsProvider).measurementUnits;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text('История',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (s, label) in const [
                  (_Sort.date, 'По дате'),
                  (_Sort.distance, 'По расстоянию'),
                  (_Sort.duration, 'По длительности'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _sort == s,
                    selectedColor: const Color(0xFFFDE6E8),
                    backgroundColor: AppColors.card,
                    side: const BorderSide(color: AppColors.divider),
                    onSelected: (_) => setState(() => _sort = s),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ridesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
              data: (rides) {
                if (rides.isEmpty) {
                  return const EmptyState(
                      icon: Icons.directions_bike_outlined,
                      title: 'Поездок пока нет',
                      text: 'Завершённые поездки появятся здесь.');
                }
                final list = [...rides];
                switch (_sort) {
                  case _Sort.date:
                    list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
                  case _Sort.distance:
                    list.sort((a, b) => b.distanceMeters.compareTo(a.distanceMeters));
                  case _Sort.duration:
                    list.sort((a, b) => b.durationSeconds.compareTo(a.durationSeconds));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (c, i) => _RideCard(ride: list[i], units: units),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RideCard extends ConsumerWidget {
  const _RideCard({required this.ride, required this.units});
  final Ride ride;
  final MeasurementUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segs = ref.watch(rideSegmentsProvider(ride.id)).valueOrNull;
    final dist = distanceParts(ride.distanceMeters, units);
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RideDetailScreen(rideId: ride.id))),
      child: Row(
        children: [
          TrackThumbnail(segments: segs),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ride.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(fmtDateTime(ride.startedAt),
                    style: const TextStyle(color: AppColors.secondary, fontSize: 12)),
                const SizedBox(height: 8),
                Row(children: [
                  Text('${dist.$1} ${dist.$2}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(width: 12),
                  Text(fmtDuration(ride.durationSeconds),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(fmtSpeed(ride.averageSpeed, units),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.secondary)),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
