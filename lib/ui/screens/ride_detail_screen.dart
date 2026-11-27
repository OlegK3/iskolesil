import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/geo.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../services/data_exchange.dart';
import '../../services/export_image.dart';
import '../widgets/common.dart';
import '../widgets/track_map.dart';

/// Экран «Завершение поездки» (isNew) и детали поездки из истории.
class RideDetailScreen extends ConsumerStatefulWidget {
  const RideDetailScreen({super.key, required this.rideId, this.isNew = false});
  final String rideId;
  final bool isNew;
  @override
  ConsumerState<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends ConsumerState<RideDetailScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  bool _loaded = false;
  bool _busy = false;
  int _fitTick = 0;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save({bool pop = false}) async {
    final ride = await ref.read(rideRepoProvider).getRide(widget.rideId);
    if (ride == null) return;
    final title = _title.text.trim().isEmpty ? ride.title : _title.text.trim();
    await ref
        .read(rideRepoProvider)
        .updateRide(ride.copyWith(title: title, description: _desc.text.trim()));
    bumpRides(ref);
    if (!mounted) return;
    if (pop) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      toast(context, 'Сохранено');
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'Удалить поездку?',
        text: 'Поездка и её трек будут удалены без возможности восстановления. '
            'Статистика и общая карта пересчитаются.',
        yes: 'Удалить');
    if (!ok) return;
    await ref.read(rideRepoProvider).deleteRide(widget.rideId);
    bumpRides(ref);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _exportGpx() async {
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final f = await ref.read(exchangeProvider).exportRideGpx(widget.rideId, dir);
      await Share.shareXFiles([XFile(f.path, mimeType: 'application/gpx+xml')]);
    } catch (e) {
      if (mounted) toast(context, 'Не удалось экспортировать: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareImage(Ride ride) async {
    var hide = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Изображение маршрута'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: hide,
            activeColor: AppColors.accent,
            onChanged: (v) => setS(() => hide = v ?? true),
            title: const Text('Скрыть начало и конец'),
            subtitle: const Text('Уберёт по 300 м с обоих концов — например, ваш дом.'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Создать')),
          ],
        ),
      ),
    );
    if (go != true) return;
    setState(() => _busy = true);
    try {
      final segs = await ref.read(rideSegmentsProvider(widget.rideId).future);
      final bytes = await RouteImageExporter.render(
        ride: ride,
        segments: segs,
        units: ref.read(settingsProvider).measurementUnits,
        hideEnds: hide,
      );
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, '${safeFileName(ride.title)}.png'));
      await f.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(f.path, mimeType: 'image/png')]);
    } catch (e) {
      if (mounted) toast(context, 'Не удалось создать изображение: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideAsync = ref.watch(rideProvider(widget.rideId));
    final segs = ref.watch(rideSegmentsProvider(widget.rideId)).valueOrNull ?? const [];
    final units = ref.watch(settingsProvider).measurementUnits;
    final all = ref.watch(allSegmentsProvider).valueOrNull ?? const {};

    return rideAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Ошибка: $e'))),
      data: (ride) {
        if (ride == null) {
          return Scaffold(
              appBar: AppBar(),
              body: const EmptyState(icon: Icons.search_off, title: 'Поездка не найдена'));
        }
        if (!_loaded) {
          _title.text = ride.title;
          _desc.text = ride.description;
          _loaded = true;
        }
        final bounds = boundsOfSegments(segs);
        final dist = distanceParts(ride.distanceMeters, units);
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.isNew ? 'Поездка завершена' : 'Поездка'),
            actions: [
              IconButton(
                  tooltip: 'Удалить',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _delete),
            ],
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 280,
                      child: Stack(children: [
                        Positioned.fill(
                          child: TrackMap(
                            previous: [
                              for (final e in all.entries)
                                if (e.key != ride.id) e.value
                            ],
                            highlighted: segs,
                            fitBounds: bounds,
                            fitNonce: segs.length + 1 + _fitTick * 1000,
                          ),
                        ),
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Column(children: [
                            _MapAction(
                              icon: Icons.fit_screen_outlined,
                              tooltip: 'Весь маршрут',
                              onTap: () => setState(() => _fitTick++),
                            ),
                            const SizedBox(height: 8),
                            _MapAction(
                              icon: Icons.open_in_full,
                              tooltip: 'На весь экран',
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          RouteMapScreen(rideId: ride.id))),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      '${fmtDate(ride.startedAt)}, ${fmtTime(ride.startedAt)}'
                      '${ride.finishedAt != null ? ' – ${fmtTime(ride.finishedAt!)}' : ''}',
                      style: const TextStyle(color: AppColors.secondary)),
                  const SizedBox(height: 12),
                  AppCard(
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: BigStat(
                                value: dist.$1, unit: dist.$2, label: 'Расстояние', size: 36)),
                        Expanded(
                            child: BigStat(
                                value: fmtDuration(ride.durationSeconds),
                                label: 'Длительность',
                                size: 36)),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: BigStat(
                                value: fmtDuration(ride.movingDurationSeconds),
                                label: 'В движении',
                                size: 22)),
                        Expanded(
                            child: BigStat(
                                value: speedParts(ride.averageSpeed, units).$1,
                                unit: speedParts(ride.averageSpeed, units).$2,
                                label: 'Средняя',
                                size: 22)),
                        Expanded(
                            child: BigStat(
                                value: speedParts(ride.maxSpeed, units).$1,
                                unit: speedParts(ride.maxSpeed, units).$2,
                                label: 'Макс.',
                                size: 22)),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: BigStat(
                                value: fmtElevation(ride.elevationGain, units),
                                label: 'Набор высоты',
                                size: 22)),
                        const Spacer(flex: 2),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Название'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _desc,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Описание'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _save(pop: widget.isNew),
                    child: Text(widget.isNew ? 'Сохранить' : 'Сохранить изменения'),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('GPX'),
                        onPressed: _busy ? null : _exportGpx,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Картинка'),
                        onPressed: _busy ? null : () => _shareImage(ride),
                      ),
                    ),
                  ]),
                  if (widget.isNew) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _delete,
                      child: const Text('Удалить поездку'),
                    ),
                  ],
                ],
              ),
              if (_busy) const Positioned.fill(child: ColoredBox(color: Color(0x33FFFFFF), child: Center(child: CircularProgressIndicator()))),
            ],
          ),
        );
      },
    );
  }
}

class _MapAction extends StatelessWidget {
  const _MapAction({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: Colors.black, size: 22),
          onPressed: onTap,
        ),
      );
}

/// Полноэкранный просмотр маршрута: масштабирование двумя пальцами,
/// перемещение, возврат к исходному масштабу.
class RouteMapScreen extends ConsumerStatefulWidget {
  const RouteMapScreen({super.key, required this.rideId});
  final String rideId;
  @override
  ConsumerState<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends ConsumerState<RouteMapScreen> {
  int _fitTick = 0;

  @override
  Widget build(BuildContext context) {
    final segs = ref.watch(rideSegmentsProvider(widget.rideId)).valueOrNull ?? const [];
    final all = ref.watch(allSegmentsProvider).valueOrNull ?? const {};
    final ride = ref.watch(rideProvider(widget.rideId)).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(ride?.title ?? 'Маршрут', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Весь маршрут',
            icon: const Icon(Icons.fit_screen_outlined),
            onPressed: () => setState(() => _fitTick++),
          ),
        ],
      ),
      body: TrackMap(
        previous: [
          for (final e in all.entries)
            if (e.key != widget.rideId) e.value
        ],
        highlighted: segs,
        fitBounds: boundsOfSegments(segs),
        fitNonce: segs.length + 1 + _fitTick * 1000,
      ),
    );
  }
}
