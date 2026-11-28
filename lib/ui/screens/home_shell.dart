import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../providers.dart';
import '../../services/recording_controller.dart';
import '../widgets/common.dart';
import 'active_ride_screen.dart';
import 'history_screen.dart';
import 'my_map_screen.dart';
import 'ride_detail_screen.dart';
import 'start_screen.dart';
import 'stats_screen.dart';

final tabIndexProvider = StateProvider<int>((ref) => 0);

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecovery());
  }

  Future<void> _checkRecovery() async {
    final ctrl = ref.read(recordingProvider.notifier);
    final ride = await ctrl.findRecoverable();
    if (ride == null || !mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Найдена незавершённая поездка'),
        content: Text(
            '«${ride.title}» от ${fmtDateTime(ride.startedAt)}. Приложение было закрыто '
            'во время записи. Сохранённые точки на месте; пропущенный участок '
            'не дорисовывается.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Удалить')),
          TextButton(onPressed: () => Navigator.pop(c, 'finish'), child: const Text('Завершить')),
          TextButton(onPressed: () => Navigator.pop(c, 'resume'), child: const Text('Продолжить')),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'resume':
        await ctrl.resumeRecovered(ride);
        if (!mounted) return;
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ActiveRideScreen()));
        break;
      case 'finish':
        final id = await ctrl.finalizeRecovered(ride);
        bumpRides(ref);
        if (!mounted) return;
        if (id != null) {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RideDetailScreen(rideId: id, isNew: true)));
        } else {
          toast(context, 'В поездке слишком мало точек — она удалена.');
        }
        break;
      case 'delete':
        await ctrl.deleteRecovered(ride);
        bumpRides(ref);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tabIndexProvider);
    const pages = [
      StartScreen(),
      MyMapScreen(),
      HistoryScreen(),
      StatsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(tabIndexProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.play_circle_outline), label: 'Старт'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Моя карта'),
          NavigationDestination(icon: Icon(Icons.history), label: 'История'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Статистика'),
        ],
      ),
    );
  }
}
