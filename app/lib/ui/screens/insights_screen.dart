import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../services/analytics.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../sheets/session_sheets.dart';
import '../sheets/subject_editor_sheet.dart';
import '../widgets/common.dart';
import 'home_shell.dart';
import 'settings_screen.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Insights'), actions: const [SettingsButton()]),
      floatingActionButton: state.data.subjects.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showAdaptiveSheet<void>(context, const ScoreSheet()),
              icon: const Icon(Icons.grade_outlined),
              label: const Text('Add result'),
            ),
      body: PageBody(children: [
        StatGrid(tiles: [
          StatTile(icon: Icons.today, label: 'Today', value: fmtMinutes(s.todayMinutes)),
          StatTile(icon: Icons.date_range, label: 'Last 7 days', value: fmtMinutes(s.weekMinutes)),
          StatTile(icon: Icons.local_fire_department_outlined, label: 'Day streak', value: '${s.streakDays}'),
          StatTile(icon: Icons.flag_outlined, label: 'Goal met (7 days)', value: '${s.goalDaysLast7}/7'),
        ]),
        const SizedBox(height: 16),
        const _AiProfileCard(),
        const SizedBox(height: 16),
        ResponsiveColumns(minColumnWidth: 420, children: [
          SectionCard(title: 'Study time – last 14 days', child: _DailyChart(summary: s)),
          SectionCard(
            title: 'Strengths & weak areas',
            child: s.subjects.isEmpty
                ? const EmptyState(icon: Icons.school_outlined, title: 'Add subjects to see your strengths')
                : Column(children: [
                    for (final st in [...s.subjects]..sort((a, b) => b.strength.compareTo(a.strength)))
                      _StrengthRow(stats: st),
                    const SizedBox(height: 8),
                    Text('Based on your results, self-rating, completed sessions and focus. Tap a subject for details.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
          ),
          SectionCard(title: 'Time per subject – last 30 days', child: _SubjectTime(summary: s)),
          SectionCard(title: 'When you study', child: _PeriodBreakdown(summary: s)),
          SectionCard(
            title: 'Recommendations',
            child: Column(children: [
              for (final tip in s.recommendations)
                ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.lightbulb_outline), title: Text(tip)),
            ]),
          ),
          SectionCard(
            title: 'Tasks',
            child: Wrap(spacing: 24, runSpacing: 8, children: [
              _Num(label: 'Open', value: s.openTasks),
              _Num(label: 'Due this week', value: s.dueThisWeek),
              _Num(label: 'Overdue', value: s.overdueTasks, alert: s.overdueTasks > 0),
              _Num(label: 'Completed', value: s.doneTasks),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _Num extends StatelessWidget {
  const _Num({required this.label, required this.value, this.alert = false});
  final String label;
  final int value;
  final bool alert;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (alert) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.error_outline, size: 18, color: t.colorScheme.error)),
      ]),
      Text(label, style: t.textTheme.bodySmall),
    ]);
  }
}

class _AiProfileCard extends StatefulWidget {
  const _AiProfileCard();
  @override
  State<_AiProfileCard> createState() => _AiProfileCardState();
}

class _AiProfileCardState extends State<_AiProfileCard> {
  bool _busy = false;

  Future<void> _generate() async {
    setState(() => _busy = true);
    try {
      await context.read<AppState>().buildAiProfile();
      if (mounted) showSnack(context, 'Profile updated – your plan now uses it');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not build profile: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.data.profile;
    final theme = Theme.of(context);
    final tuned = state.data.subjects.where((s) => (s.aiWeight - 1).abs() > 0.05).toList();
    return SectionCard(
      title: 'Your learner profile',
      trailing: const Icon(Icons.auto_awesome),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p.aiSummary != null) ...[
          Text(p.aiSummary!, style: theme.textTheme.bodyLarge),
          if (tuned.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in tuned)
                Chip(
                  avatar: Icon(s.aiWeight > 1 ? Icons.trending_up : Icons.trending_down, size: 18),
                  label: Text('${s.name} ${s.aiWeight > 1 ? 'more' : 'less'} time'),
                ),
            ]),
          ],
          const SizedBox(height: 4),
          Text('Updated ${p.aiSummaryAt?.replaceFirst('T', ' ').substring(0, 16) ?? ''}', style: theme.textTheme.bodySmall),
        ] else
          Text(
            state.aiAvailable
                ? 'Let the AI coach analyse your study data and build a personal profile. It also tunes how much time '
                    'the planner gives each subject.'
                : 'Connect Ollama in Settings to get an AI-written learner profile. Everything else on this page works offline.',
            style: theme.textTheme.bodyMedium,
          ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (state.aiAvailable)
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(p.aiSummary == null ? 'Build my profile' : 'Refresh'),
            )
          else
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SettingsScreen(initialSection: 'ai'))),
              icon: const Icon(Icons.link),
              label: const Text('Set up AI'),
            ),
          if (p.aiSummary != null)
            TextButton(onPressed: state.clearAiTuning, child: const Text('Reset AI tuning')),
        ]),
      ]),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.summary});
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = summary.dailySeries;
    final goal = summary.dailyGoalMinutes.toDouble();
    final peak = [goal, ...series.map((d) => d.minutes.toDouble())].reduce((a, b) => a > b ? a : b);
    final interval = peak > 240 ? 60.0 : 30.0;
    final maxY = ((peak * 1.1) / interval).ceil() * interval + (peak == 0 ? interval : 0);
    String axis(double v) => v == 0 ? '0' : v % 60 == 0 ? '${v ~/ 60}h' : v < 60 ? '${v.round()}m' : '${(v / 60).toStringAsFixed(1)}h';
    final muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: 'Bar chart of minutes studied per day for the last 14 days. '
          '${series.map((d) => '${DateFormat.MMMd().format(d.date)}: ${d.minutes} minutes').join(', ')}',
      child: SizedBox(
        height: 220,
        child: BarChart(BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
          ),
          extraLinesData: ExtraLinesData(horizontalLines: [
            if (goal > 0)
              HorizontalLine(
                y: goal,
                color: muted,
                strokeWidth: 1,
                dashArray: [4, 4],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  labelResolver: (_) => 'Goal ${fmtMinutes(goal.round())}',
                ),
              ),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: interval,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(axis(v), style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= series.length || (i.isOdd && i != series.length - 1)) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(DateFormat.E().format(series[i].date).substring(0, 2),
                        style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${DateFormat.MMMEd().format(series[group.x].date)}\n${fmtMinutes(rod.toY.round())}',
                TextStyle(color: theme.colorScheme.onInverseSurface, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < series.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: series[i].minutes.toDouble(),
                  width: 14,
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        )),
      ),
    );
  }
}

class _StrengthRow extends StatelessWidget {
  const _StrengthRow({required this.stats});
  final SubjectStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon) = switch (stats.level) {
      SubjectLevel.strong => ('Strong', Icons.verified_outlined),
      SubjectLevel.average => ('Average', Icons.remove_circle_outline),
      SubjectLevel.weak => ('Needs work', Icons.priority_high),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showAdaptiveSheet<void>(context, SubjectDetailSheet(subject: stats.subject)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SubjectDot(color: stats.subject.color),
            const SizedBox(width: 8),
            Expanded(child: Text(stats.subject.name, style: theme.textTheme.titleSmall)),
            Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('$label · ${(stats.strength * 100).round()}%', style: theme.textTheme.bodySmall),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stats.strength,
              minHeight: 8,
              color: Color(stats.subject.color),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ]),
      ),
    );
  }
}

class _SubjectTime extends StatelessWidget {
  const _SubjectTime({required this.summary});
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [...summary.subjects]..sort((a, b) => b.recentMinutes.compareTo(a.recentMinutes));
    final max = rows.isEmpty ? 0 : rows.first.recentMinutes;
    if (max == 0) {
      return const EmptyState(icon: Icons.timer_outlined, title: 'No study logged yet', message: 'Finish a session to see your time here.');
    }
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 110, child: Text(r.subject.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: r.recentMinutes / max,
                  minHeight: 14,
                  color: Color(r.subject.color),
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
            SizedBox(width: 64, child: Text(fmtMinutes(r.recentMinutes), textAlign: TextAlign.right, style: theme.textTheme.bodySmall)),
          ]),
        ),
    ]);
  }
}

class _PeriodBreakdown extends StatelessWidget {
  const _PeriodBreakdown({required this.summary});
  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = summary.minutesByPeriod.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const EmptyState(icon: Icons.schedule, title: 'No data yet');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (p, label, icon) in studyPeriods)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(
              width: 110,
              child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)]),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (summary.minutesByPeriod[p] ?? 0) / total,
                  minHeight: 14,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            SizedBox(width: 64, child: Text(fmtMinutes(summary.minutesByPeriod[p] ?? 0), textAlign: TextAlign.right, style: theme.textTheme.bodySmall)),
          ]),
        ),
      if (summary.bestPeriod != null) ...[
        const SizedBox(height: 8),
        Text('You focus best in the ${summary.bestPeriod}.', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    ]);
  }
}

/// Details for one subject: stats, results, quick actions.
class SubjectDetailSheet extends StatelessWidget {
  const SubjectDetailSheet({super.key, required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final stats = state.summary.subjects.where((s) => s.subject.id == subject.id).firstOrNull;
    final scores = state.data.scores.where((s) => s.subjectId == subject.id).toList()..sort((a, b) => b.date.compareTo(a.date));
    if (stats == null) return const SizedBox.shrink();
    String pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';
    return SheetScaffold(
      title: subject.name,
      actions: [
        TextButton.icon(
          onPressed: () => showAdaptiveSheet<void>(context, SubjectEditorSheet(subject: subject)),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
        ),
        FilledButton.icon(
          onPressed: () => showAdaptiveSheet<void>(context, ScoreSheet(subjectId: subject.id)),
          icon: const Icon(Icons.add),
          label: const Text('Add result'),
        ),
      ],
      children: [
        Wrap(spacing: 24, runSpacing: 12, children: [
          _Kv('Strength', pct(stats.strength)),
          _Kv('Avg. result', pct(stats.avgScorePct)),
          _Kv('Sessions done', '${stats.sessionsCompleted}'),
          _Kv('Missed/skipped', '${stats.sessionsMissed}'),
          _Kv('Avg. focus', stats.avgFocus == null ? '–' : '${stats.avgFocus!.toStringAsFixed(1)}/5'),
          _Kv('Total time', fmtMinutes(stats.totalMinutes)),
        ]),
        const SizedBox(height: 16),
        Text('Results', style: Theme.of(context).textTheme.titleSmall),
        if (scores.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No results yet. Adding grades makes the analysis more accurate.')),
        for (final sc in scores)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(sc.title),
            subtitle: Text(sc.date),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${sc.score.toStringAsFixed(sc.score % 1 == 0 ? 0 : 1)}/${sc.maxScore.toStringAsFixed(0)} (${pct(sc.percent)})'),
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => state.deleteScore(sc)),
            ]),
          ),
      ],
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);
  final String k;
  final String v;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text(k, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
