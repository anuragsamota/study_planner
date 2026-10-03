import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart' show isoDate;
import '../../state/app_state.dart';
import '../format.dart';
import '../sheets/session_sheets.dart';
import '../sheets/subject_editor_sheet.dart';
import '../sheets/task_editor_sheet.dart';
import '../widgets/common.dart';
import '../widgets/session_tile.dart';
import '../widgets/task_tile.dart';
import 'home_shell.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = state.now;
    final summary = state.summary;
    final today = state.sessionsOn(now);
    final next = state.nextSession;
    final dueSoon = state.data.tasks.where((t) => !t.isDone && t.dueAt != null).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${greeting(now)}, ${state.data.profile.name.split(' ').first}'),
          Text(DateFormat.MMMMEEEEd().format(now), style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: const [SettingsButton()],
      ),
      floatingActionButton: state.data.subjects.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAdaptiveSheet<void>(context, const LogStudySheet()),
              icon: const Icon(Icons.add_task),
              label: const Text('Log study'),
            ),
      body: state.data.subjects.isEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.school_outlined,
                title: 'Add your subjects to get a plan',
                message: 'Your study plan is created automatically from your subjects, deadlines and free time.',
                action: FilledButton.icon(
                  onPressed: () => showAdaptiveSheet<void>(context, const SubjectEditorSheet()),
                  icon: const Icon(Icons.add),
                  label: const Text('Add subject'),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => state.replan(),
              child: PageBody(children: [
                _ProgressCard(minutes: summary.todayMinutes, goal: summary.dailyGoalMinutes, streak: summary.streakDays),
                const SizedBox(height: 16),
                if (state.atRisk.isNotEmpty) ...[
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: Text('${state.atRisk.length} task(s) may not fit before their deadline'),
                      subtitle: Text(state.atRisk
                          .map((r) => '${r.task.title} (${fmtMinutes(r.unscheduledMinutes)} short)')
                          .join(', ')),
                      trailing: TextButton(onPressed: () => HomeNav.of(context)?.goTo(2), child: const Text('Review')),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                ResponsiveColumns(children: [
                  SectionCard(
                    title: "Today's plan",
                    trailing: TextButton(onPressed: () => HomeNav.of(context)?.goTo(1), child: const Text('Week')),
                    child: today.isEmpty
                        ? EmptyState(
                            icon: Icons.free_breakfast_outlined,
                            title: 'Nothing planned for today',
                            message: 'Enjoy the break, or add study time in your availability settings.',
                            action: OutlinedButton.icon(
                              onPressed: () => showAdaptiveSheet<void>(context, AddSessionSheet(day: now)),
                              icon: const Icon(Icons.add),
                              label: const Text('Add a session'),
                            ),
                          )
                        : Column(children: [
                            for (final s in today)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SessionTile(session: s, highlight: s.id == next?.id),
                              ),
                          ]),
                  ),
                  if (next != null && isoDate(next.startAt) != isoDate(now))
                    SectionCard(title: 'Up next · ${fmtDay(next.startAt, now: now)}', child: SessionTile(session: next, highlight: true)),
                  SectionCard(
                    title: 'Coming up',
                    trailing: TextButton(onPressed: () => HomeNav.of(context)?.goTo(2), child: const Text('All tasks')),
                    child: dueSoon.isEmpty
                        ? EmptyState(
                            icon: Icons.celebration_outlined,
                            title: 'No deadlines',
                            action: OutlinedButton.icon(
                              onPressed: () => showAdaptiveSheet<void>(context, const TaskEditorSheet()),
                              icon: const Icon(Icons.add),
                              label: const Text('Add assignment or exam'),
                            ),
                          )
                        : Column(children: [
                            for (final t in dueSoon.take(4))
                              Padding(padding: const EdgeInsets.only(bottom: 8), child: TaskTile(task: t, dense: true)),
                          ]),
                  ),
                  SectionCard(
                    title: 'Tips for you',
                    child: Column(children: [
                      for (final tip in summary.recommendations.take(3))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.lightbulb_outline),
                          title: Text(tip),
                        ),
                    ]),
                  ),
                ]),
              ]),
            ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.minutes, required this.goal, required this.streak});
  final int minutes;
  final int goal;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = goal == 0 ? 0.0 : (minutes / goal).clamp(0.0, 1.0);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(fit: StackFit.expand, children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.1),
              ),
              Center(child: Text('${(progress * 100).round()}%', style: theme.textTheme.titleMedium)),
            ]),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${fmtMinutes(minutes)} of ${fmtMinutes(goal)} today',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                progress >= 1 ? 'Daily goal reached – great job!' : 'Follow your plan to reach your daily goal.',
                style: theme.textTheme.bodyMedium,
              ),
            ]),
          ),
          if (streak > 0)
            Column(children: [
              Icon(Icons.local_fire_department, size: 30, color: theme.colorScheme.tertiary),
              Text('$streak day${streak == 1 ? '' : 's'}', style: theme.textTheme.labelLarge),
            ]),
        ]),
      ),
    );
  }
}
