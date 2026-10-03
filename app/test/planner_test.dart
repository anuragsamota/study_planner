import 'package:flutter_test/flutter_test.dart';
import 'package:study_planner/models/planner_data.dart';
import 'package:study_planner/services/analytics.dart';
import 'package:study_planner/services/planner.dart';
import 'package:study_planner/services/reminders.dart';
import 'package:study_planner/models/settings.dart';

final now = DateTime(2026, 10, 5, 8); // Monday

void main() {
  test('JSON round trip keeps the server field names', () {
    final d = PlannerData(subjects: [Subject(id: 'm', name: 'Maths')], tasks: [
      StudyTask(id: 't', subjectId: 'm', title: 'Sheet', status: TaskStatus.inProgress, due: '2026-10-09'),
    ]);
    final j = d.toJson();
    expect((j['tasks'] as List).first['status'], 'in_progress');
    final back = PlannerData.fromJson(j);
    expect(back.tasks.single.status, TaskStatus.inProgress);
    expect(back.tasks.single.dueAt, DateTime(2026, 10, 9, 23, 59));
    expect(back.profile.availability[1]!.single.start, '17:00');
  });

  test('plan respects availability and the daily cap', () {
    final d = PlannerData(subjects: [Subject(id: 'm', name: 'Maths')]);
    final plan = generatePlan(d, now);
    expect(plan.sessions, isNotEmpty);
    final perDay = <String, int>{};
    for (final s in plan.sessions) {
      perDay.update(isoDate(s.startAt), (c) => c + 1, ifAbsent: () => 1);
      final windows = d.profile.availability[s.startAt.weekday]!;
      final startMin = s.startAt.hour * 60 + s.startAt.minute;
      expect(windows.any((w) => w.startMinutes <= startMin && startMin + s.durationMinutes <= w.endMinutes), isTrue);
    }
    expect(perDay.values.every((c) => c <= d.profile.maxSessionsPerDay), isTrue);
  });

  test('completing a session and skipping feed analytics', () {
    final d = PlannerData(subjects: [Subject(id: 'm', name: 'Maths', proficiency: 3)], sessions: [
      StudySession(subjectId: 'm', title: 'a', start: '2026-10-04T18:00:00', durationMinutes: 60, status: SessionStatus.completed, focusRating: 5),
      StudySession(subjectId: 'm', title: 'b', start: '2026-10-04T20:00:00', durationMinutes: 45, status: SessionStatus.skipped),
    ]);
    final s = summarize(d, now);
    expect(s.totalMinutes, 60);
    expect(s.streakDays, 1);
    expect(s.subjects.single.completionRate, 0.5);
  });

  test('reminders for sessions, deadlines and digest', () {
    final d = PlannerData(subjects: [Subject(id: 'm', name: 'Maths')], tasks: [
      StudyTask(subjectId: 'm', title: 'Essay', due: '2026-10-07'),
    ]);
    applyPlan(d, now);
    final r = buildReminders(d, ReminderSettings(minutesBefore: 10), now);
    expect(r.any((x) => x.key.startsWith('session:') && x.at == DateTime(2026, 10, 5, 16, 50)), isTrue);
    expect(r.any((x) => x.key.startsWith('due:') && x.title.contains('Essay')), isTrue);
    expect(r.any((x) => x.key.startsWith('digest:')), isTrue);
    expect(r.map((x) => x.at).toList(), orderedEquals([...r.map((x) => x.at)]..sort()));
    expect(buildReminders(d, ReminderSettings(enabled: false), now), isEmpty);
  });

  test('strength levels', () {
    expect(levelFor(0.8), SubjectLevel.strong);
    expect(levelFor(0.6), SubjectLevel.average);
    expect(levelFor(0.2), SubjectLevel.weak);
  });
}
