import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../sheets/session_sheets.dart';
import '../widgets/common.dart';
import '../widgets/session_tile.dart';
import 'home_shell.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  int _selected = 0; // day offset from today

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = state.now;
    final days = [for (var i = 0; i < 7; i++) DateTime(now.year, now.month, now.day + i)];
    final day = days[_selected];
    final sessions = state.sessionsOn(day);
    final planned = sessions.where((s) => s.status != SessionStatus.skipped).fold<int>(0, (a, s) => a + s.durationMinutes);
    final wide = windowSize(context) != WindowSize.compact;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study plan'),
        actions: [
          IconButton(
            tooltip: 'Re-plan now',
            icon: const Icon(Icons.auto_fix_high),
            onPressed: () {
              state.replan();
              showSnack(context, 'Plan updated for the next 7 days');
            },
          ),
          const SettingsButton(),
        ],
      ),
      floatingActionButton: state.data.subjects.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAdaptiveSheet<void>(context, AddSessionSheet(day: day)),
              icon: const Icon(Icons.add),
              label: const Text('Session'),
            ),
      body: PageBody(children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const ListTile(
            leading: Icon(Icons.auto_awesome),
            title: Text('Your plan updates itself'),
            subtitle: Text('Whenever you add tasks, finish or skip sessions, the schedule is rebuilt around '
                'deadlines, weak subjects and your free time. Sessions you add yourself are kept.'),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final d = days[i];
              final minutes = state
                  .sessionsOn(d)
                  .where((s) => s.status != SessionStatus.skipped)
                  .fold<int>(0, (a, s) => a + s.durationMinutes);
              final selected = i == _selected;
              final scheme = Theme.of(context).colorScheme;
              return SizedBox(
                width: wide ? 110 : 74,
                child: Material(
                  color: selected ? scheme.primary : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _selected = i),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: selected ? scheme.onPrimary : scheme.onSurface),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(i == 0 ? 'Today' : DateFormat.E().format(d), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${d.day}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        Text(minutes == 0 ? '–' : fmtMinutes(minutes), style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text(fmtDay(day, now: now), style: Theme.of(context).textTheme.titleLarge)),
          Text('${sessions.length} sessions · ${fmtMinutes(planned)}', style: Theme.of(context).textTheme.bodyMedium),
        ]),
        const SizedBox(height: 12),
        if (state.data.subjects.isEmpty)
          const EmptyState(icon: Icons.school_outlined, title: 'Add subjects in Settings to get a plan')
        else if (sessions.isEmpty)
          EmptyState(
            icon: Icons.event_available_outlined,
            title: 'Free day',
            message: (state.data.profile.availability[day.weekday] ?? const []).isEmpty
                ? 'You have no study time set for ${DateFormat.EEEE().format(day)}s.'
                : 'Nothing needs your attention on this day.',
            action: OutlinedButton(
              onPressed: () => HomeNav.of(context)?.goTo(0),
              child: const Text('Back to today'),
            ),
          )
        else
          for (final s in sessions) Padding(padding: const EdgeInsets.only(bottom: 8), child: SessionTile(session: s)),
      ]),
    );
  }
}
