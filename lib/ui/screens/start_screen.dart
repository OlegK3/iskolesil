import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/stats.dart';
import '../../providers.dart';
import '../../services/location_service.dart';
import '../../services/recording_controller.dart';
import '../widgets/common.dart';
import 'active_ride_screen.dart';
import 'city_maps_screen.dart';
import 'home_shell.dart';
import 'settings_screen.dart';

class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final rec = ref.read(recordingProvider);
    if (!rec.active) {
      final r = await ref.read(recordingProvider.notifier).start();
      if (!r.ok) {
        if (!context.mounted) return;
        await _permissionDialog(context, ref, r.permission);
        return;
      }
    }
    if (!context.mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ActiveRideScreen()));
  }

  Future<void> _permissionDialog(
      BuildContext context, WidgetRef ref, LocPermission? p) async {
    final text = switch (p) {
      LocPermission.serviceDisabled =>
        'Геолокация выключена. Включите её в шторке уведомлений или настройках телефона.',
      LocPermission.deniedForever =>
        'Доступ к геолокации запрещён. Разрешите его в настройках приложения.',
      _ => 'Для записи поездки нужен доступ к геолокации.',
    };
    final open = await confirm(context,
        title: 'Нет доступа к GPS',
        text: text,
        yes: 'Открыть настройки',
        no: 'Закрыть');
    if (open) await ref.read(locationServiceProvider).openSettings();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ridesAsync = ref.watch(ridesProvider);
    final cities = ref.watch(installedCitiesProvider).valueOrNull ?? const [];
    final settings = ref.watch(settingsProvider);
    final rec = ref.watch(recordingProvider);
    final units = settings.measurementUnits;
    final rides = ridesAsync.valueOrNull ?? const [];
    final all = StatsCalculator.compute(rides);
    final month = StatsCalculator.compute(
        StatsCalculator.filter(rides, StatsPeriod.month, DateTime.now()));
    final cityName = cities.isEmpty
        ? AppConfig.defaultCityName
        : cities
            .firstWhere((c) => c.id == settings.currentCityId,
                orElse: () => cities.first)
            .name;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              const AppLogo(),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppConfig.appName,
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    Text(AppConfig.slogan,
                        style: TextStyle(fontSize: 12, color: AppColors.secondary)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Настройки',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.location_on_outlined, size: 18, color: AppColors.secondary),
            const SizedBox(width: 4),
            Text(cityName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          if (cities.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CityMapsScreen())),
                child: const Row(children: [
                  Icon(Icons.map_outlined, color: AppColors.accent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        'Карта города не установлена. Установите её, чтобы видеть улицы без интернета. Запись поездок работает и без карты.',
                        style: TextStyle(fontSize: 13)),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.secondary),
                ]),
              ),
            ),
          SizedBox(
            height: 76,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              onPressed: () => _start(context, ref),
              child: Text(
                  rec.active ? 'Продолжить поездку' : 'Начать поездку',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Row(
              children: [
                Expanded(
                    child: BigStat(
                        value: distanceParts(all.distanceMeters, units).$1,
                        unit: distanceParts(all.distanceMeters, units).$2,
                        label: 'Всего')),
                Expanded(
                    child: BigStat(
                        value: fmtDurationLong(all.durationSeconds),
                        label: 'Время',
                        size: 22)),
                Expanded(
                    child: BigStat(
                        value: '${all.rideCount}', label: 'Поездок')),
              ],
            ),
          ),
          const SectionTitle('Этот месяц'),
          AppCard(
            child: Row(
              children: [
                Expanded(
                    child: BigStat(
                        value: distanceParts(month.distanceMeters, units).$1,
                        unit: distanceParts(month.distanceMeters, units).$2,
                        label: 'Расстояние',
                        size: 24)),
                Expanded(
                    child: BigStat(
                        value: speedParts(month.averageSpeed, units).$1,
                        unit: speedParts(month.averageSpeed, units).$2,
                        label: 'Средняя',
                        size: 24)),
                Expanded(
                    child: BigStat(
                        value: '${month.rideCount}', label: 'Поездок', size: 24)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: const Text('Моя карта'),
            onPressed: () => ref.read(tabIndexProvider.notifier).state = 1,
          ),
          if (rides.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Пока нет ни одной поездки. Нажмите «Начать поездку» — всё, что вы проедете, останется на вашей карте.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.secondary),
              ),
            ),
        ],
      ),
    );
  }
}
