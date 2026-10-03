import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/reminders.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'coach_screen.dart';
import 'insights_screen.dart';
import 'plan_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';
import 'today_screen.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _dests = [
  _Dest('Today', Icons.wb_sunny_outlined, Icons.wb_sunny),
  _Dest('Plan', Icons.calendar_month_outlined, Icons.calendar_month),
  _Dest('Tasks', Icons.checklist_outlined, Icons.checklist),
  _Dest('Insights', Icons.insights_outlined, Icons.insights),
  _Dest('Coach', Icons.auto_awesome_outlined, Icons.auto_awesome),
];

/// Lets any screen switch tabs (e.g. "See all tasks").
class HomeNav extends InheritedWidget {
  const HomeNav({super.key, required this.goTo, required super.child});
  final void Function(int index) goTo;
  static HomeNav? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HomeNav>();
  @override
  bool updateShouldNotify(HomeNav oldWidget) => false;
}

/// Settings button used in every screen's app bar.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Settings',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription<Reminder>? _sub;

  @override
  void initState() {
    super.initState();
    // In-app reminder banners (used on web/Linux, where the OS can't schedule).
    _sub = context.read<AppState>().reminders.inAppReminders.listen((r) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showMaterialBanner(MaterialBanner(
        leading: const Icon(Icons.notifications_active),
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(r.body),
        ]),
        actions: [TextButton(onPressed: messenger.hideCurrentMaterialBanner, child: const Text('Dismiss'))],
      ));
      Timer(const Duration(seconds: 20), () {
        if (mounted) messenger.hideCurrentMaterialBanner();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Widget _screen() => switch (_index) {
        0 => const TodayScreen(),
        1 => const PlanScreen(),
        2 => const TasksScreen(),
        3 => const InsightsScreen(),
        _ => const CoachScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final size = windowSize(context);
    final body = HomeNav(goTo: (i) => setState(() => _index = i), child: _screen());
    if (size == WindowSize.compact) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in _dests) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
          ],
        ),
      );
    }
    final extended = size == WindowSize.expanded;
    return Scaffold(
      body: Row(children: [
        SafeArea(
          child: NavigationRail(
            extended: extended,
            minExtendedWidth: 200,
            selectedIndex: _index,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: extended
                  ? Row(children: [
                      Icon(Icons.school, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Study Planner', style: Theme.of(context).textTheme.titleMedium),
                    ])
                  : Icon(Icons.school, color: Theme.of(context).colorScheme.primary),
            ),
            destinations: [
              for (final d in _dests)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]),
    );
  }
}
