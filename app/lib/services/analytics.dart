// Study analytics – works fully offline.
// Mirrors server/study_planner_mcp/analytics.py; keep both in sync.

import '../models/planner_data.dart';

const strongThreshold = 0.70;
const weakThreshold = 0.50;

enum SubjectLevel { strong, average, weak }

String timePeriod(int hour) {
  if (hour >= 5 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 21) return 'evening';
  return 'night';
}

/// Weighted 0..1 mastery estimate; missing signals are re-normalised away.
double strengthScore({
  required double proficiency,
  double? scorePct,
  double? completionRate,
  double? avgFocus,
}) {
  final parts = <(double, double)>[(0.25, (proficiency - 1) / 4)];
  if (scorePct != null) parts.add((0.40, scorePct));
  if (completionRate != null) parts.add((0.20, completionRate));
  if (avgFocus != null) parts.add((0.15, (avgFocus - 1) / 4));
  final totalW = parts.fold<double>(0, (a, p) => a + p.$1);
  final v = parts.fold<double>(0, (a, p) => a + p.$1 * p.$2) / totalW;
  return v.clamp(0.0, 1.0);
}

SubjectLevel levelFor(double strength) => strength >= strongThreshold
    ? SubjectLevel.strong
    : strength < weakThreshold
        ? SubjectLevel.weak
        : SubjectLevel.average;

class SubjectStats {
  SubjectStats({
    required this.subject,
    required this.totalMinutes,
    required this.recentMinutes,
    required this.sessionsCompleted,
    required this.sessionsMissed,
    required this.completionRate,
    required this.avgFocus,
    required this.avgScorePct,
    required this.strength,
  });

  final Subject subject;
  final int totalMinutes;
  final int recentMinutes;
  final int sessionsCompleted;
  final int sessionsMissed;
  final double? completionRate;
  final double? avgFocus;
  final double? avgScorePct;
  final double strength;
  SubjectLevel get level => levelFor(strength);

  Map<String, dynamic> toJson() => {
        'name': subject.name,
        'level': level.name,
        'strength': double.parse(strength.toStringAsFixed(2)),
        'minutes_total': totalMinutes,
        'minutes_recent': recentMinutes,
        'completion_rate': completionRate?.toStringAsFixed(2),
        'avg_focus': avgFocus?.toStringAsFixed(1),
        'avg_score_pct': avgScorePct == null ? null : (avgScorePct! * 100).round(),
        'self_rated_proficiency': subject.proficiency,
        'difficulty': subject.difficulty,
      };
}

class DayMinutes {
  DayMinutes(this.date, this.minutes);
  final DateTime date;
  final int minutes;
}

class AnalyticsSummary {
  AnalyticsSummary({
    required this.subjects,
    required this.totalMinutes,
    required this.windowMinutes,
    required this.todayMinutes,
    required this.weekMinutes,
    required this.dailyGoalMinutes,
    required this.goalDaysLast7,
    required this.streakDays,
    required this.dailySeries,
    required this.minutesByPeriod,
    required this.bestPeriod,
    required this.openTasks,
    required this.doneTasks,
    required this.overdueTasks,
    required this.dueThisWeek,
  });

  final List<SubjectStats> subjects;
  final int totalMinutes;
  final int windowMinutes;
  final int todayMinutes;
  final int weekMinutes;
  final int dailyGoalMinutes;
  final int goalDaysLast7;
  final int streakDays;
  final List<DayMinutes> dailySeries; // last 14 days, oldest first
  final Map<String, int> minutesByPeriod;
  final String? bestPeriod;
  final int openTasks;
  final int doneTasks;
  final int overdueTasks;
  final int dueThisWeek;
  late final List<String> recommendations;

  List<SubjectStats> get weak =>
      (subjects.where((s) => s.level == SubjectLevel.weak).toList()..sort((a, b) => a.strength.compareTo(b.strength)));
  List<SubjectStats> get strong =>
      (subjects.where((s) => s.level == SubjectLevel.strong).toList()..sort((a, b) => b.strength.compareTo(a.strength)));

  Map<String, dynamic> toJson() => {
        'total_minutes': totalMinutes,
        'today_minutes': todayMinutes,
        'week_minutes': weekMinutes,
        'daily_goal_minutes': dailyGoalMinutes,
        'goal_days_last_7': goalDaysLast7,
        'streak_days': streakDays,
        'best_period': bestPeriod,
        'minutes_by_period': minutesByPeriod,
        'tasks': {'open': openTasks, 'done': doneTasks, 'overdue': overdueTasks, 'due_this_week': dueThisWeek},
        'subjects': subjects.map((s) => s.toJson()).toList(),
      };
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

List<SubjectStats> subjectStats(PlannerData data, DateTime now, {int windowDays = 30}) {
  final windowStart = now.subtract(Duration(days: windowDays));
  return [
    for (final subject in data.subjects)
      () {
        var total = 0, recent = 0, completed = 0, missed = 0;
        final focus = <int>[];
        for (final s in data.sessions) {
          if (s.subjectId != subject.id) continue;
          final status = s.effectiveStatus(now);
          if (status == SessionStatus.completed) {
            completed++;
            total += s.durationMinutes;
            if (!s.startAt.isBefore(windowStart)) recent += s.durationMinutes;
            if (s.focusRating != null) focus.add(s.focusRating!);
          } else if (status == SessionStatus.missed || status == SessionStatus.skipped) {
            missed++;
          }
        }
        final scores = data.scores.where((x) => x.subjectId == subject.id && x.maxScore > 0).map((x) => x.percent).toList();
        final scorePct = scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;
        final completion = completed + missed == 0 ? null : completed / (completed + missed);
        final avgFocus = focus.isEmpty ? null : focus.reduce((a, b) => a + b) / focus.length;
        return SubjectStats(
          subject: subject,
          totalMinutes: total,
          recentMinutes: recent,
          sessionsCompleted: completed,
          sessionsMissed: missed,
          completionRate: completion,
          avgFocus: avgFocus,
          avgScorePct: scorePct,
          strength: strengthScore(
            proficiency: subject.proficiency.toDouble(),
            scorePct: scorePct,
            completionRate: completion,
            avgFocus: avgFocus,
          ),
        );
      }(),
  ];
}

AnalyticsSummary summarize(PlannerData data, DateTime now, {int windowDays = 30}) {
  final subjects = subjectStats(data, now, windowDays: windowDays);
  final today = _day(now);
  final daily = <DateTime, int>{};
  final periodFocus = <String, List<int>>{};
  final periodMinutes = <String, int>{};
  var total = 0;
  for (final s in data.sessions) {
    if (s.effectiveStatus(now) != SessionStatus.completed) continue;
    final start = s.startAt;
    total += s.durationMinutes;
    daily.update(_day(start), (m) => m + s.durationMinutes, ifAbsent: () => s.durationMinutes);
    final period = timePeriod(start.hour);
    periodMinutes.update(period, (m) => m + s.durationMinutes, ifAbsent: () => s.durationMinutes);
    if (s.focusRating != null) periodFocus.putIfAbsent(period, () => []).add(s.focusRating!);
  }

  DateTime back(int days) => DateTime(today.year, today.month, today.day - days);
  final series = [for (var i = 13; i >= 0; i--) DayMinutes(back(i), daily[back(i)] ?? 0)];
  final windowFrom = back(windowDays - 1);
  final windowMinutes = daily.entries.where((e) => !e.key.isBefore(windowFrom)).fold<int>(0, (a, e) => a + e.value);

  var streak = 0;
  var cursor = (daily[today] ?? 0) > 0 ? today : back(1);
  while ((daily[cursor] ?? 0) > 0) {
    streak++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }

  final goal = data.profile.dailyGoalMinutes;
  final last7 = [for (var i = 0; i < 7; i++) daily[back(i)] ?? 0];
  final goalDays = last7.where((m) => goal > 0 && m >= goal).length;

  final open = data.tasks.where((t) => !t.isDone).toList();
  final overdue = open.where((t) => t.dueAt != null && t.dueAt!.isBefore(now)).length;
  final dueWeek = open
      .where((t) => t.dueAt != null && !t.dueAt!.isBefore(now) && !t.dueAt!.isAfter(now.add(const Duration(days: 7))))
      .length;

  String? best;
  if (periodFocus.isNotEmpty) {
    double avg(String p) => periodFocus[p]!.reduce((a, b) => a + b) / periodFocus[p]!.length;
    best = periodFocus.keys.reduce((a, b) => avg(b) > avg(a) ? b : a);
  } else if (periodMinutes.isNotEmpty) {
    best = periodMinutes.keys.reduce((a, b) => periodMinutes[b]! > periodMinutes[a]! ? b : a);
  }

  final summary = AnalyticsSummary(
    subjects: subjects,
    totalMinutes: total,
    windowMinutes: windowMinutes,
    todayMinutes: daily[today] ?? 0,
    weekMinutes: last7.fold(0, (a, b) => a + b),
    dailyGoalMinutes: goal,
    goalDaysLast7: goalDays,
    streakDays: streak,
    dailySeries: series,
    minutesByPeriod: periodMinutes,
    bestPeriod: best,
    openTasks: open.length,
    doneTasks: data.tasks.length - open.length,
    overdueTasks: overdue,
    dueThisWeek: dueWeek,
  );
  summary.recommendations = recommendations(summary, data);
  return summary;
}

/// Plain rule-based tips – always available, no AI required.
List<String> recommendations(AnalyticsSummary s, PlannerData data) {
  final tips = <String>[];
  if (s.overdueTasks > 0) {
    tips.add('You have ${s.overdueTasks} overdue task(s). Tackle them first or move their deadlines.');
  }
  for (final w in s.weak.take(2)) {
    tips.add('${w.subject.name} looks like a weak area – your plan gives it extra practice sessions.');
  }
  final hasHistory = s.totalMinutes > 0;
  if (hasHistory && s.dailyGoalMinutes > 0 && s.goalDaysLast7 < 4) {
    tips.add('You met your ${s.dailyGoalMinutes}-minute daily goal on ${s.goalDaysLast7} of the last 7 days. '
        'Shorter, more frequent sessions can help build the habit.');
  }
  if (s.bestPeriod != null && s.bestPeriod != data.profile.preferredTime) {
    tips.add('You focus best in the ${s.bestPeriod}. Consider making it your preferred study time.');
  }
  final neglected = s.subjects.where((x) => x.recentMinutes == 0).map((x) => x.subject.name).take(3).toList();
  if (hasHistory && neglected.isNotEmpty) tips.add('Not studied recently: ${neglected.join(', ')}.');
  if (s.streakDays >= 3) tips.add('${s.streakDays}-day streak – keep it going!');
  if (tips.isEmpty) {
    tips.add(hasHistory
        ? "You're on track. Keep following your plan."
        : 'Start your first session from the plan – your progress and insights will appear here.');
  }
  return tips;
}
