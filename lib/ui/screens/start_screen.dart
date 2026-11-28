import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../providers.dart';
import '../../services/recording_controller.dart';
import '../widgets/common.dart';
import 'about_screen.dart';
import 'active_ride_screen.dart';
import 'home_shell.dart';
import 'settings_screen.dart';
import 'trip_prep_screen.dart';

const _homeImage = 'assets/images/iskolesil_home.jpg';

/// Главная страница: шапка, городское фото с кнопкой «Начать поездку»,
/// карточки разделов, город и «О приложении».
class StartScreen extends ConsumerWidget {
  const StartScreen({super.key});

  void _start(BuildContext context, WidgetRef ref) {
    final rec = ref.read(recordingProvider);
    // Идущая поездка: сразу на экран записи. Иначе — «Куда поедем?».
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            rec.active ? const ActiveRideScreen() : const TripPrepScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(recordingProvider);

    void tab(int i) => ref.read(tabIndexProvider.notifier).state = i;

    return SafeArea(
      child: LayoutBuilder(builder: (context, box) {
        final compact = box.maxHeight < 620;
        final hero = _Hero(
          active: rec.active,
          onStart: () => _start(context, ref),
        );
        final body = <Widget>[
          _Header(
            onSettings: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(height: 12),
          if (compact) SizedBox(height: 260, child: hero) else Expanded(child: hero),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _NavCard(
                icon: Icons.map_outlined,
                title: 'Моя карта',
                subtitle: 'Пройденные улицы',
                onTap: () => tab(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NavCard(
                icon: Icons.bar_chart_outlined,
                title: 'Статистика',
                subtitle: 'Километры, время',
                onTap: () => tab(3),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _NavCard(
            icon: Icons.history,
            title: 'История',
            subtitle: 'Все поездки',
            onTap: () => tab(2),
          ),
          const SizedBox(height: 14),
          _Footer(
            onAbout: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
        ];
        final pad = const EdgeInsets.fromLTRB(16, 8, 16, 12);
        if (compact) {
          return ListView(padding: pad, children: body);
        }
        return Padding(
          padding: pad,
          child: Column(children: body),
        );
      }),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/images/iskolesil_icon.png',
                width: 46, height: 46),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppConfig.appName,
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
                Text(AppConfig.tagline,
                    style: TextStyle(fontSize: 13, color: AppColors.secondary)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Настройки',
            iconSize: 28,
            icon: const Icon(Icons.settings_outlined),
            onPressed: onSettings,
          ),
        ],
      );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.active, required this.onStart});
  final bool active;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(_homeImage,
              fit: BoxFit.cover, alignment: const Alignment(0, 0.3)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x00000000), Color(0x66000000)],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: _StartButton(active: active, onTap: onStart),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 10, 0),
            child: Row(children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    active ? 'Продолжить поездку' : 'Начать поездку',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text),
                  ),
                ),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 38),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFDE6E8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.secondary, fontSize: 12)),
              ],
            ),
          ),
        ]),
      );
}

/// Низ страницы: продолжение городского фото (приглушённое) и «О приложении».
class _Footer extends StatelessWidget {
  const _Footer({required this.onAbout});
  final VoidCallback onAbout;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.16,
              child: Image.asset(_homeImage,
                  fit: BoxFit.cover, alignment: const Alignment(0, 0.9)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: Colors.white),
                onPressed: onAbout,
                child: const Text('О приложении', style: TextStyle(fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
