import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../services/location_service.dart';
import '../../services/recording_controller.dart';
import '../widgets/common.dart';
import '../widgets/locate_button.dart';
import '../widgets/track_map.dart';
import 'active_ride_screen.dart';

/// Промежуточный экран «Куда поедем?». Свободная поездка: карта, положение
/// пользователя, «Где я» и красная кнопка «Поехали».
///
/// Выбор конечной точки и построение маршрута отложены (нужен маршрутизатор,
/// см. docs/ROUTING.md), поэтому неработающих элементов здесь нет.
class TripPrepScreen extends ConsumerStatefulWidget {
  const TripPrepScreen({super.key});
  @override
  ConsumerState<TripPrepScreen> createState() => _TripPrepScreenState();
}

class _TripPrepScreenState extends ConsumerState<TripPrepScreen> {
  LatLon? _pos;
  int _centerNonce = 0;
  StreamSubscription<Position>? _sub;
  LocPermission? _perm;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final loc = ref.read(locationServiceProvider);
    final perm = await loc.check();
    if (!mounted) return;
    setState(() => _perm = perm);
    if (perm != LocPermission.granted) return;
    _listen();
    final fix = await loc.currentFix();
    if (!mounted || fix == null) return;
    setState(() {
      _pos = LatLon(fix.lat, fix.lon);
      _centerNonce++;
    });
  }

  void _listen() {
    _sub?.cancel();
    _sub = ref.read(locationServiceProvider).previewStream().listen((p) {
      if (!mounted) return;
      setState(() => _pos = LatLon(p.latitude, p.longitude));
    }, onError: (_) {});
  }

  Future<void> _locate() async {
    final p = await locateUser(context, ref);
    if (p == null || !mounted) return;
    setState(() {
      _pos = p;
      _perm = LocPermission.granted;
      _centerNonce++;
    });
    if (_sub == null) _listen();
  }

  Future<void> _go() async {
    if (_starting) return;
    setState(() => _starting = true);
    final r = await ref.read(recordingProvider.notifier).start();
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _starting = false);
      await showLocationPermissionDialog(context, ref, r.permission);
      return;
    }
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ActiveRideScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allSegmentsProvider).valueOrNull ?? const {};
    final settings = ref.watch(settingsProvider);
    final noGps = _perm != null && _perm != LocPermission.granted;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Куда поедем?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      // Карта — над нижней панелью: логотип Яндекса остаётся видимым.
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
          Positioned.fill(
            child: TrackMap(
              previous: settings.showPreviousRoutes
                  ? [for (final e in all.entries) e.value]
                  : const [],
              position: _pos,
              centerOn: _pos,
              centerNonce: _centerNonce,
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: LocateButton(onPressed: _locate),
          ),
          if (noGps)
            Positioned(
              left: 12,
              right: 76,
              top: 12,
              child: AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.location_off_outlined, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _perm == LocPermission.serviceDisabled
                          ? 'Геолокация выключена'
                          : 'Нет доступа к геолокации',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Свободная поездка: запишем ваш маршрут по GPS',
                        style: TextStyle(fontSize: 13, color: AppColors.secondary)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 68,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 6,
                          shadowColor: const Color(0x66000000),
                        ),
                        onPressed: _starting ? null : _go,
                        child: _starting
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                    strokeWidth: 3, color: Colors.white))
                            : const Text('Поехали',
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
