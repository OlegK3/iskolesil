import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../providers.dart';
import '../../services/location_service.dart';
import 'common.dart';

/// Получает актуальные координаты для кнопки «Где я».
/// Ничего не выдумывает: при отсутствии разрешения/сигнала возвращает null
/// и показывает понятное сообщение.
Future<LatLon?> locateUser(BuildContext context, WidgetRef ref) async {
  final loc = ref.read(locationServiceProvider);
  final perm = await loc.ensurePermission();
  if (!context.mounted) return null;
  switch (perm) {
    case LocPermission.serviceDisabled:
      toast(context, 'Геолокация выключена. Включите её в настройках телефона.');
      return null;
    case LocPermission.denied:
      toast(context, 'Нет разрешения на геолокацию.');
      return null;
    case LocPermission.deniedForever:
      toast(context, 'Доступ к геолокации запрещён. Разрешите его в настройках приложения.');
      return null;
    case LocPermission.granted:
      break;
  }
  final fix = await loc.currentFix();
  if (!context.mounted) return null;
  if (fix == null) {
    toast(context, 'Не удаётся определить положение: нет сигнала GPS. Выйдите на открытое место.');
    return null;
  }
  return LatLon(fix.lat, fix.lon);
}

/// Круглая белая кнопка с чёрной иконкой прицела и мягкой тенью.
class LocateButton extends StatefulWidget {
  const LocateButton({super.key, required this.onPressed});

  /// Должна вернуться, когда определение положения завершено.
  final Future<void> Function() onPressed;

  @override
  State<LocateButton> createState() => _LocateButtonState();
}

class _LocateButtonState extends State<LocateButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _tap,
          child: Center(
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.black),
                  )
                : const Icon(Icons.my_location, color: Colors.black, size: 26),
          ),
        ),
      ),
    );
  }
}

/// Диалог «нет доступа к GPS» с переходом в настройки.
Future<void> showLocationPermissionDialog(
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
