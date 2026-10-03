import 'dart:async';

import 'package:flutter/material.dart';

import '../models/planner_data.dart';
import '../models/settings.dart';
import '../services/ai_service.dart';
import '../services/analytics.dart';
import '../services/planner.dart';
import '../services/reminders.dart';
import '../services/storage.dart';

/// Single source of truth for the UI. Every change is saved locally, the plan
/// is regenerated automatically and reminders are rescheduled, so the student
/// never has to plan by hand. AI and MCP sync are optional extras.
class AppState extends ChangeNotifier {
  AppState(this._storage, this.reminders, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        data = _storage.loadData(),
        settings = _storage.loadSettings() {
    ai = AiService(settings.ai);
  }

  final Storage _storage;
  final ReminderService reminders;
  final DateTime Function() _clock;
  late final AiService ai;

  PlannerData data;
  AppSettings settings;
  AiStatus aiStatus = const AiStatus();
  List<AtRiskTask> atRisk = [];
  final List<CoachMessage> coachHistory = [];
  bool coachBusy = false;
  String? syncError;

  AnalyticsSummary? _summary;
  Timer? _syncDebounce;
  Timer? _dayWatcher;
  String _plannedFor = '';

  DateTime get now => _clock();
  AnalyticsSummary get summary => _summary ??= summarize(data, now);

  Future<void> start() async {
    replan(save: false);
    await _persist();
    unawaited(refreshAiStatus());
    // Re-plan when the day changes while the app stays open (missed sessions
    // become "missed", the horizon moves forward).
    _dayWatcher = Timer.periodic(const Duration(minutes: 15), (_) {
      if (isoDate(now) != _plannedFor) {
        replan();
      }
    });
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _dayWatcher?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ persistence

  Future<void> _persist({bool sync = true}) async {
    data.updatedAt = isoLocal(DateTime.now());
    data.profile.utcOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    _summary = null;
    notifyListeners();
    await _storage.saveData(data);
    await reminders.reschedule(data, settings.reminders);
    if (sync) _scheduleSync();
  }

  Future<void> saveSettings() async {
    ai.settings = settings.ai;
    notifyListeners();
    await _storage.saveSettings(settings);
  }

  /// Apply a change, re-plan and save.
  Future<void> mutate(void Function(PlannerData d) change, {bool replanAfter = true}) async {
    change(data);
    if (replanAfter) replan(save: false);
    await _persist();
  }

  // ------------------------------------------------------------------ planning

  void replan({bool save = true, int days = 7}) {
    final plan = applyPlan(data, now, days: days);
    atRisk = plan.atRisk;
    _plannedFor = isoDate(now);
    if (save) unawaited(_persist());
  }

  List<StudySession> sessionsOn(DateTime day) {
    final key = isoDate(day);
    return data.sessions.where((s) => isoDate(s.startAt) == key).toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  StudySession? get nextSession {
    final t = now;
    final upcoming = data.sessions
        .where((s) => s.status == SessionStatus.planned && s.endAt.isAfter(t))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return upcoming.firstOrNull;
  }

  // ------------------------------------------------------------------ subjects

  Future<void> upsertSubject(Subject s) => mutate((d) {
        final i = d.subjects.indexWhere((x) => x.id == s.id);
        i >= 0 ? d.subjects[i] = s : d.subjects.add(s);
      });

  Future<void> deleteSubject(Subject s) => mutate((d) {
        d.subjects.removeWhere((x) => x.id == s.id);
        final removed = <String>{s.id};
        d.tasks.removeWhere((t) => t.subjectId == s.id && removed.add(t.id));
        d.sessions.removeWhere((x) => x.subjectId == s.id && x.status == SessionStatus.planned && removed.add(x.id));
        d.tombstones.addAll(removed);
      });

  // ------------------------------------------------------------------ tasks

  Future<void> upsertTask(StudyTask t) => mutate((d) {
        final i = d.tasks.indexWhere((x) => x.id == t.id);
        i >= 0 ? d.tasks[i] = t : d.tasks.add(t);
      });

  Future<void> deleteTask(StudyTask t) => mutate((d) {
        d.tasks.removeWhere((x) => x.id == t.id);
        d.sessions.removeWhere((s) => s.taskId == t.id && s.status == SessionStatus.planned);
        d.tombstones.add(t.id);
      });

  Future<void> setTaskDone(StudyTask t, bool done) => mutate((_) {
        t.status = done ? TaskStatus.done : (t.completedMinutes > 0 ? TaskStatus.inProgress : TaskStatus.todo);
      });

  // ------------------------------------------------------------------ sessions

  Future<void> addManualSession(StudySession s) => mutate((d) => d.sessions.add(s));

  Future<void> deleteSession(StudySession s) => mutate((d) {
        d.sessions.removeWhere((x) => x.id == s.id);
        d.tombstones.add(s.id);
      });

  /// Finish a session (from the focus timer or the "done" button).
  Future<void> completeSession(StudySession s,
      {required int minutes, int? focus, bool taskDone = false, String notes = ''}) {
    return mutate((d) {
      final startedEarlier = s.startAt.isAfter(now);
      s
        ..status = SessionStatus.completed
        ..durationMinutes = minutes
        ..focusRating = focus
        ..notes = notes.isNotEmpty ? notes : s.notes;
      // If the session was done ahead of time, record when it really happened.
      if (startedEarlier) s.start = isoLocal(now.subtract(Duration(minutes: minutes)));
      // Keep it out of the auto planner's way.
      if (s.source == SessionSource.auto) s.source = SessionSource.manual;
      final task = d.taskById(s.taskId);
      if (task != null) {
        task.completedMinutes += minutes;
        task.status = taskDone ? TaskStatus.done : TaskStatus.inProgress;
      }
    });
  }

  Future<void> skipSession(StudySession s) => mutate((_) {
        s.status = SessionStatus.skipped;
        s.source = SessionSource.manual;
      });

  /// Log study that wasn't planned.
  Future<void> logStudy({required String subjectId, required int minutes, int? focus, String? taskId, DateTime? at}) {
    return mutate((d) {
      final end = at ?? now;
      d.sessions.add(StudySession(
        subjectId: subjectId,
        taskId: taskId,
        title: taskId != null ? (d.taskById(taskId)?.title ?? 'Study') : '${d.subjectById(subjectId)?.name ?? ''} study',
        start: isoLocal(end.subtract(Duration(minutes: minutes))),
        durationMinutes: minutes,
        status: SessionStatus.completed,
        source: SessionSource.manual,
        focusRating: focus,
      ));
      final task = d.taskById(taskId);
      if (task != null) {
        task.completedMinutes += minutes;
        if (task.status == TaskStatus.todo) task.status = TaskStatus.inProgress;
      }
    });
  }

  // ------------------------------------------------------------------ scores & profile

  Future<void> addScore(Score s) => mutate((d) => d.scores.add(s));

  Future<void> deleteScore(Score s) => mutate((d) {
        d.scores.removeWhere((x) => x.id == s.id);
        d.tombstones.add(s.id);
      });

  Future<void> updateProfile(void Function(Profile p) change) => mutate((d) => change(d.profile));

  Future<void> completeOnboarding() async {
    settings.onboarded = true;
    await saveSettings();
    await reminders.requestPermission();
    replan();
  }

  Future<void> resetAll() async {
    await _storage.clear();
    data = PlannerData();
    settings = AppSettings();
    ai.settings = settings.ai;
    coachHistory.clear();
    await _persist(sync: false);
  }

  // ------------------------------------------------------------------ AI

  bool get aiAvailable => settings.ai.enabled && aiStatus.ollamaOk;

  Future<void> refreshAiStatus() async {
    aiStatus = await ai.checkStatus();
    notifyListeners();
    if (aiStatus.mcpOk) await syncNow();
  }

  /// Send a message to the AI coach.
  Future<void> askCoach(String text) async {
    coachHistory.add(CoachMessage('user', text));
    coachBusy = true;
    notifyListeners();
    try {
      final reply = await ai.chat(coachHistory.sublist(0, coachHistory.length - 1), text, data,
          agentMode: aiStatus.agentMode);
      coachHistory.add(CoachMessage('assistant', reply.text, toolsUsed: reply.toolsUsed));
      if (reply.updatedData != null) {
        await _adoptServerData(reply.updatedData!);
      }
    } catch (e) {
      coachHistory.add(CoachMessage('assistant', 'Something went wrong: $e'));
      unawaited(refreshAiStatus());
    } finally {
      coachBusy = false;
      notifyListeners();
    }
  }

  /// Ask the AI for a personalised learner profile and let it tune the planner.
  Future<void> buildAiProfile() async {
    final profile = await ai.buildProfile(data);
    await mutate((d) {
      d.profile.aiSummary = profile.summary;
      d.profile.aiSummaryAt = isoLocal(now);
      for (final s in d.subjects) {
        s.aiWeight = profile.weights[s.id] ?? 1.0;
      }
    });
  }

  Future<void> clearAiTuning() => mutate((d) {
        d.profile.aiSummary = null;
        d.profile.aiSummaryAt = null;
        for (final s in d.subjects) {
          s.aiWeight = 1.0;
        }
      });

  // ------------------------------------------------------------------ MCP sync

  void _scheduleSync() {
    if (!settings.ai.mcpEnabled || !aiStatus.mcpOk) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 3), () => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    if (!settings.ai.mcpEnabled) return;
    try {
      final merged = await ai.syncPush(data);
      syncError = null;
      await _adoptServerData(merged, push: false);
    } catch (e) {
      syncError = e.toString();
      notifyListeners();
    }
  }

  Future<void> _adoptServerData(PlannerData server, {bool push = true}) async {
    data = server;
    replan(save: false);
    await saveSettings(); // persists lastSyncedAt
    await _persist(sync: push);
  }
}
