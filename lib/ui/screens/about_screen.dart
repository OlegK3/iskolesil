import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, 6)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('assets/images/iskolesil_icon.png',
                    width: 112, height: 112),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(AppConfig.appName,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text('Велотрекер города',
                style: TextStyle(fontSize: 15, color: AppColors.secondary)),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('У каждой улицы — твоя история.',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.accent)),
          ),
          const SizedBox(height: 20),
          const AppCard(
            child: Text(
              'ИСКОЛЕСИЛ — приложение для записи велосипедных поездок и создания '
              'персональной карты пройденных маршрутов.\n\n'
              'Открывайте новые улицы, исследуйте город, сохраняйте свои поездки и '
              'наблюдайте, как постепенно формируется ваша собственная карта.\n\n'
              'Скачайте карту своего города и отправляйтесь в поездку даже без '
              'подключения к интернету.',
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
          ),
          const SectionTitle('Версия'),
          const AppCard(
            child: Row(children: [
              Icon(Icons.tag, color: AppColors.accent),
              SizedBox(width: 12),
              Text(AppConfig.version,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
          const SectionTitle('Работа без интернета'),
          const AppCard(
            child: Text(
              'Карта, GPS, запись поездок, история, статистика и экспорт работают без '
              'интернета. Он нужен только для скачивания и обновления карт городов.',
              style: TextStyle(height: 1.4),
            ),
          ),
          const SectionTitle('Ваши данные'),
          const AppCard(
            child: Text(
              'Поездки и GPS-треки хранятся только на этом устройстве. Приложение не '
              'отправляет координаты и историю никуда, не содержит аналитики и '
              'телеметрии. Резервную копию и экспорт GPX вы создаёте сами.',
              style: TextStyle(height: 1.4),
            ),
          ),
          const SectionTitle('Карты'),
          const AppCard(
            child: Text(
              '© участники OpenStreetMap (лицензия ODbL, openstreetmap.org/copyright).\n'
              'Схема векторных тайлов OpenMapTiles. Шрифты подписей: Noto Sans (SIL OFL).',
              style: TextStyle(height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: const Text('Лицензии библиотек'),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: AppConfig.version,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset('assets/images/iskolesil_icon.png', width: 56, height: 56),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
