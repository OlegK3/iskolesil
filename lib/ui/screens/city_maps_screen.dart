import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../services/map/city_map_service.dart';
import '../widgets/common.dart';

class _Progress {
  final int received;
  final int? total;
  final String? error;
  final CancelToken token;
  _Progress(this.received, this.total, this.token, {this.error});
}

class CityMapsScreen extends ConsumerStatefulWidget {
  const CityMapsScreen({super.key});
  @override
  ConsumerState<CityMapsScreen> createState() => _CityMapsScreenState();
}

class _CityMapsScreenState extends ConsumerState<CityMapsScreen> {
  List<CatalogEntry> _catalog = [];
  String? _catalogError;
  bool _loadingCatalog = true;
  String _query = '';
  final Map<String, _Progress> _busy = {};
  int? _free;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final svc = ref.read(cityMapServiceProvider);
    setState(() => _loadingCatalog = true);
    final (list, err) = await svc.loadCatalog();
    final free = await svc.freeBytes();
    if (!mounted) return;
    setState(() {
      _catalog = list;
      _catalogError = err;
      _loadingCatalog = false;
      _free = free;
    });
  }

  Future<void> _afterInstall(CityMap m) async {
    bumpMaps(ref);
    final s = ref.read(settingsProvider);
    if (s.currentCityId.isEmpty) {
      await ref.read(settingsProvider.notifier).update((x) => x.copyWith(currentCityId: m.id));
    }
    if (mounted) toast(context, 'Карта «${m.name}» установлена');
  }

  Future<void> _installFile({CatalogEntry? entry}) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null) return;
    if (!path.toLowerCase().endsWith('.mbtiles')) {
      if (mounted) toast(context, 'Нужен файл с расширением .mbtiles');
      return;
    }
    final key = entry?.id ?? '_file';
    final token = CancelToken();
    setState(() => _busy[key] = _Progress(0, null, token));
    try {
      final m = await ref.read(cityMapServiceProvider).installFromFile(
            File(path),
            entry: entry,
            cancel: token,
            onProgress: (r, t) {
              if (mounted) setState(() => _busy[key] = _Progress(r, t, token));
            },
          );
      await _afterInstall(m);
      if (mounted) setState(() => _busy.remove(key));
    } catch (e) {
      if (mounted) {
        setState(() => _busy.remove(key));
        toast(context, e.toString());
      }
    }
  }

  Future<void> _download(CatalogEntry e) async {
    final token = CancelToken();
    setState(() => _busy[e.id] = _Progress(0, e.sizeBytes, token));
    try {
      final m = await ref.read(cityMapServiceProvider).download(
            e,
            wifiOnly: ref.read(settingsProvider).wifiOnlyDownloads,
            cancel: token,
            onProgress: (r, t) {
              if (mounted) setState(() => _busy[e.id] = _Progress(r, t, token));
            },
          );
      await _afterInstall(m);
      if (mounted) setState(() => _busy.remove(e.id));
    } catch (err) {
      if (mounted) {
        setState(() => _busy[e.id] =
            _Progress(_busy[e.id]?.received ?? 0, _busy[e.id]?.total, token, error: err.toString()));
      }
    }
  }

  Future<void> _delete(CityMap m) async {
    final ok = await confirm(context,
        title: 'Удалить карту «${m.name}»?',
        text: 'Будет удалён файл карты (${fmtBytes(m.sizeBytes)}). Ваши поездки останутся.',
        yes: 'Удалить');
    if (!ok) return;
    await ref.read(cityMapServiceProvider).delete(m.id);
    bumpMaps(ref);
    if (ref.read(settingsProvider).currentCityId == m.id) {
      await ref.read(settingsProvider.notifier).update((s) => s.copyWith(currentCityId: ''));
    }
    final f = await ref.read(cityMapServiceProvider).freeBytes();
    if (mounted) setState(() => _free = f);
  }

  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(installedCitiesProvider).valueOrNull ?? const <CityMap>[];
    final settings = ref.watch(settingsProvider);
    final byId = {for (final c in installed) c.id: c};
    final q = _query.trim().toLowerCase();
    final catalog = _catalog
        .where((e) => q.isEmpty || '${e.name} ${e.region}'.toLowerCase().contains(q))
        .toList();
    final total = installed.fold<int>(0, (a, m) => a + m.sizeBytes);

    return Scaffold(
      appBar: AppBar(title: const Text('Карты городов')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'Поиск города'),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: BigStat(value: fmtBytes(total), label: 'Занято картами', size: 20)),
                Expanded(
                    child: BigStat(
                        value: _free == null ? '—' : fmtBytes(_free!),
                        label: 'Свободно',
                        size: 20)),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Загружать только по Wi-Fi'),
                value: settings.wifiOnlyDownloads,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(wifiOnlyDownloads: v)),
              ),
            ]),
          ),
          if (_catalogError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_catalogError!, style: const TextStyle(color: AppColors.accent)),
            ),
          const SectionTitle('Каталог'),
          if (_loadingCatalog) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          for (final e in catalog) ...[
            _entryCard(e, byId[e.id], settings),
            const SizedBox(height: 10),
          ],
          if (AppConfig.catalogUrl.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Сервер каталога не настроен (CATALOG_URL), поэтому карты устанавливаются из файла .mbtiles. '
                'Как получить файл — в docs/MAPS.md.',
                style: TextStyle(color: AppColors.secondary, fontSize: 12),
              ),
            ),
          const SectionTitle('Установить из файла'),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Выбрать файл .mbtiles'),
            onPressed: _busy.containsKey('_file') ? null : () => _installFile(),
          ),
          if (_busy['_file'] != null) _progressBar(_busy['_file']!),
          const SectionTitle('Установленные'),
          if (installed.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Пока нет установленных карт.',
                  style: TextStyle(color: AppColors.secondary)),
            ),
          for (final m in installed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Row(children: [
                  const Icon(Icons.map_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        Text('${fmtBytes(m.sizeBytes)} · версия ${m.version} · ${fmtDate(m.installedAt)}',
                            style: const TextStyle(color: AppColors.secondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Удалить карту',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(m),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _progressBar(_Progress p) {
    final frac = p.total == null || p.total == 0 ? null : p.received / p.total!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LinearProgressIndicator(
            value: frac, color: AppColors.accent, backgroundColor: AppColors.divider),
        const SizedBox(height: 4),
        Row(children: [
          Text(
              '${fmtBytes(p.received)}${p.total != null ? ' из ${fmtBytes(p.total!)}' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.secondary)),
          const Spacer(),
          TextButton(onPressed: p.token.cancel, child: const Text('Отмена')),
        ]),
      ]),
    );
  }

  Widget _entryCard(CatalogEntry e, CityMap? inst, AppSettings settings) {
    final progress = _busy[e.id];
    final needsUpdate = inst != null && e.version > inst.version;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(
                  '${e.region}${e.sizeBytes != null ? ' · ${fmtBytes(e.sizeBytes!)}' : ''}'
                  '${inst != null ? ' · установлена' : ''}',
                  style: const TextStyle(color: AppColors.secondary, fontSize: 12)),
            ]),
          ),
          if (inst != null &&
              settings.currentCityId != e.id)
            TextButton(
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .update((s) => s.copyWith(currentCityId: e.id)),
              child: const Text('Сделать текущим'),
            ),
        ]),
        const SizedBox(height: 8),
        if (progress != null && progress.error == null) _progressBar(progress),
        if (progress?.error != null) ...[
          Text(progress!.error!, style: const TextStyle(color: AppColors.accent, fontSize: 12)),
          const SizedBox(height: 4),
        ],
        if (progress == null || progress.error != null)
          Wrap(spacing: 8, children: [
            if (e.downloadable && (inst == null || needsUpdate))
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => _download(e),
                child: Text(progress?.error != null
                    ? 'Повторить'
                    : needsUpdate
                        ? 'Обновить'
                        : 'Скачать'),
              ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _installFile(entry: e),
              child: Text(inst == null ? 'Установить из файла' : 'Заменить из файла'),
            ),
          ]),
        if (!e.downloadable && progress == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Адрес загрузки не задан: файл на сервере РФ ещё не размещён.',
                style: TextStyle(fontSize: 12, color: AppColors.secondary)),
          ),
      ]),
    );
  }
}
