import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../services/location_service.dart';
import '../widgets/common.dart';
import 'city_maps_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  LocPermission? _perm;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshPerm();
  }

  Future<void> _refreshPerm() async {
    final p = await ref.read(locationServiceProvider).check();
    if (mounted) setState(() => _perm = p);
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File?> _pick(List<String> exts) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null) return null;
    if (!exts.any((e) => path.toLowerCase().endsWith(e))) {
      if (mounted) toast(context, 'Ожидается файл: ${exts.join(', ')}');
      return null;
    }
    return File(path);
  }

  String _permText(LocPermission? p) => switch (p) {
        LocPermission.granted => 'Разрешён',
        LocPermission.denied => 'Не разрешён',
        LocPermission.deniedForever => 'Запрещён в настройках',
        LocPermission.serviceDisabled => 'Геолокация выключена',
        null => '…',
      };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final exchange = ref.read(exchangeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            const SectionTitle('GPS'),
            AppCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.gps_fixed),
                title: const Text('Доступ к геолокации'),
                subtitle: Text(_permText(_perm)),
                trailing: TextButton(
                  onPressed: () async {
                    final r = await ref.read(locationServiceProvider).ensurePermission();
                    if (r == LocPermission.deniedForever ||
                        r == LocPermission.serviceDisabled) {
                      await ref.read(locationServiceProvider).openSettings();
                    }
                    _refreshPerm();
                  },
                  child: const Text('Настроить'),
                ),
              ),
            ),
            const SectionTitle('Карта'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SwitchListTile(
                  title: const Text('Показывать прежние маршруты'),
                  subtitle: const Text('Во время поездки, бледно-красным'),
                  value: s.showPreviousRoutes,
                  onChanged: (v) => notifier.update((x) => x.copyWith(showPreviousRoutes: v)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('Карты городов'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CityMapsScreen())),
                ),
              ]),
            ),
            const SectionTitle('Единицы измерения'),
            AppCard(
              child: SegmentedButton<MeasurementUnits>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.accent,
                  selectedForegroundColor: Colors.white,
                ),
                segments: const [
                  ButtonSegment(value: MeasurementUnits.metric, label: Text('км, км/ч')),
                  ButtonSegment(value: MeasurementUnits.imperial, label: Text('мили, миль/ч')),
                ],
                selected: {s.measurementUnits},
                onSelectionChanged: (v) =>
                    notifier.update((x) => x.copyWith(measurementUnits: v.first)),
              ),
            ),
            const SectionTitle('Данные'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Импорт GPX'),
                  onTap: () => _run(() async {
                    final f = await _pick(['.gpx']);
                    if (f == null) return;
                    final r = await exchange.importGpx(f);
                    bumpRides(ref);
                    if (!mounted) return;
                    toast(context,
                        'Импортировано: ${r.imported}, уже были: ${r.duplicates}'
                        '${r.skippedPoints > 0 ? ', пропущено точек: ${r.skippedPoints}' : ''}');
                  }),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Экспорт всех поездок в GPX'),
                  onTap: () => _run(() async {
                    final dir = await getTemporaryDirectory();
                    final f = await exchange.exportAllGpx(dir);
                    await Share.shareXFiles([XFile(f.path, mimeType: 'application/gpx+xml')]);
                  }),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: const Text('Создать резервную копию'),
                  subtitle: const Text('Файл .iskolesil — сохраните его вне телефона'),
                  onTap: () => _run(() async {
                    final dir = await getTemporaryDirectory();
                    final f = await exchange.createBackup(dir);
                    await Share.shareXFiles([XFile(f.path)]);
                  }),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Восстановить из копии'),
                  subtitle: const Text('Добавляет недостающие поездки, ничего не удаляя'),
                  onTap: () => _run(() async {
                    final f = await _pick(['.iskolesil']);
                    if (f == null) return;
                    final r = await exchange.restoreBackup(f);
                    bumpRides(ref);
                    if (!mounted) return;
                    toast(context,
                        'Добавлено: ${r.added}, уже были: ${r.alreadyPresent}'
                        '${r.failed > 0 ? ', ошибок: ${r.failed}' : ''}');
                  }),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined, color: AppColors.accent),
                  title: const Text('Удалить все данные',
                      style: TextStyle(color: AppColors.accent)),
                  subtitle: const Text('Поездки и треки. Карты городов останутся.'),
                  onTap: () => _run(() async {
                    final ok = await confirm(context,
                        title: 'Удалить все данные?',
                        text: 'Все поездки и треки будут удалены без возможности восстановления. '
                            'Сначала можно создать резервную копию.',
                        yes: 'Удалить всё');
                    if (!ok) return;
                    await ref.read(rideRepoProvider).deleteAllRides();
                    await notifier.update((x) => x.copyWith(hiddenRideIds: {}));
                    bumpRides(ref);
                    if (mounted) toast(context, 'Все поездки удалены');
                  }),
                ),
              ]),
            ),
            const SectionTitle('О приложении'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Карты и атрибуция'),
                  onTap: () => showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      backgroundColor: Colors.white,
                      title: const Text('Атрибуция'),
                      content: const Text(
                          '© участники OpenStreetMap (лицензия ODbL, openstreetmap.org/copyright).\n'
                          'Схема векторных тайлов OpenMapTiles; тайлы генерируются Planetiler.\n'
                          'Шрифты подписей: Noto Sans (SIL OFL).\n\n'
                          'Приложение не отправляет координаты и историю поездок '
                          'никуда: данные хранятся только на этом устройстве.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c), child: const Text('Закрыть'))
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.tag),
                  title: Text('${AppConfig.appName} ${AppConfig.version}'),
                  subtitle: Text(AppConfig.slogan),
                ),
              ]),
            ),
          ],
        ),
        if (_busy)
          const Positioned.fill(
              child: ColoredBox(
                  color: Color(0x33FFFFFF),
                  child: Center(child: CircularProgressIndicator()))),
      ]),
    );
  }
}
