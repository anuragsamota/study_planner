// Planner data model. The JSON shape is shared with the MCP server
// (server/study_planner_mcp/model.py) so documents sync losslessly.
//
// All date-times are naive local ISO strings ("2026-10-03T17:00:00").

import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4().replaceAll('-', '');

String isoLocal(DateTime dt) =>
    DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second)
        .toIso8601String()
        .split('.')
        .first;

String isoDate(DateTime dt) => isoLocal(dt).substring(0, 10);

DateTime? parseLocal(String? value) {
  if (value == null || value.isEmpty) return null;
  final dt = DateTime.tryParse(value);
  if (dt == null) return null;
  return dt.isUtc ? dt.toLocal() : dt;
}

/// A bare date as a due date means "end of that day".
DateTime? parseDue(String? value) {
  final dt = parseLocal(value);
  if (dt == null) return null;
  if (value!.length == 10) return DateTime(dt.year, dt.month, dt.day, 23, 59);
  return dt;
}

int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

enum TaskType { assignment, project, exam, reading, revision, other }

enum TaskStatus { todo, inProgress, done }

enum SessionStatus { planned, completed, skipped, missed }

enum SessionSource { auto, manual, ai }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  final n = (name ?? '').toString().replaceAll('_', '').toLowerCase();
  return values.firstWhere((e) => e.name.toLowerCase() == n, orElse: () => fallback);
}

String _snake(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

class TimeWindow {
  TimeWindow(this.start, this.end);
  final String start; // "HH:MM"
  final String end;

  factory TimeWindow.fromJson(Map<String, dynamic> j) =>
      TimeWindow(j['start'] as String? ?? '17:00', j['end'] as String? ?? '19:00');
  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  int get startMinutes => _toMinutes(start);
  int get endMinutes => _toMinutes(end);
  static int _toMinutes(String hm) {
    final p = hm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p.length > 1 ? p[1] : '0');
  }
}

class Profile {
  Profile({
    this.name = 'Student',
    this.dailyGoalMinutes = 120,
    this.sessionMinutes = 45,
    this.breakMinutes = 10,
    this.maxSessionsPerDay = 4,
    this.preferredTime = 'evening',
    this.utcOffsetMinutes = 0,
    this.aiSummary,
    this.aiSummaryAt,
    Map<int, List<TimeWindow>>? availability,
  }) : availability = availability ?? defaultAvailability();

  String name;
  int dailyGoalMinutes;
  int sessionMinutes;
  int breakMinutes;
  int maxSessionsPerDay;
  String preferredTime; // morning | afternoon | evening | night
  int utcOffsetMinutes;
  String? aiSummary; // personalised learner profile written by the AI coach
  String? aiSummaryAt;

  /// ISO weekday (1 = Monday) -> windows.
  Map<int, List<TimeWindow>> availability;

  static Map<int, List<TimeWindow>> defaultAvailability() => {
        for (var d = 1; d <= 5; d++) d: [TimeWindow('17:00', '21:00')],
        6: [TimeWindow('10:00', '13:00')],
        7: [TimeWindow('15:00', '18:00')],
      };

  factory Profile.fromJson(Map<String, dynamic> j) {
    final avail = <int, List<TimeWindow>>{};
    final raw = j['availability'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final day = int.tryParse(k.toString());
        if (day != null && v is List) {
          avail[day] = v.map((w) => TimeWindow.fromJson(Map<String, dynamic>.from(w as Map))).toList();
        }
      });
    }
    return Profile(
      name: j['name'] as String? ?? 'Student',
      dailyGoalMinutes: _int(j['daily_goal_minutes'], 120),
      sessionMinutes: _int(j['session_minutes'], 45),
      breakMinutes: _int(j['break_minutes'], 10),
      maxSessionsPerDay: _int(j['max_sessions_per_day'], 4),
      preferredTime: j['preferred_time'] as String? ?? 'evening',
      utcOffsetMinutes: _int(j['utc_offset_minutes'], 0),
      aiSummary: j['ai_summary'] as String?,
      aiSummaryAt: j['ai_summary_at'] as String?,
      availability: raw is Map ? avail : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'daily_goal_minutes': dailyGoalMinutes,
        'session_minutes': sessionMinutes,
        'break_minutes': breakMinutes,
        'max_sessions_per_day': maxSessionsPerDay,
        'preferred_time': preferredTime,
        'utc_offset_minutes': utcOffsetMinutes,
        'ai_summary': aiSummary,
        'ai_summary_at': aiSummaryAt,
        'availability': {
          for (final e in availability.entries) '${e.key}': e.value.map((w) => w.toJson()).toList(),
        },
      };
}

class Subject {
  Subject({
    String? id,
    required this.name,
    this.color = 0xFF5C6BC0,
    this.difficulty = 3,
    this.proficiency = 3,
    this.targetMinutesPerWeek = 120,
    this.examDate,
    this.aiWeight = 1.0,
  }) : id = id ?? newId();

  final String id;
  String name;
  int color;
  int difficulty; // 1..5
  int proficiency; // 1..5 self-rating
  int targetMinutesPerWeek;
  String? examDate; // YYYY-MM-DD
  double aiWeight; // AI-suggested emphasis multiplier (0.5..2)

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'] as String?,
        name: j['name'] as String? ?? 'Subject',
        color: _int(j['color'], 0xFF5C6BC0),
        difficulty: _int(j['difficulty'], 3),
        proficiency: _int(j['proficiency'], 3),
        targetMinutesPerWeek: _int(j['target_minutes_per_week'], 120),
        examDate: j['exam_date'] as String?,
        aiWeight: (j['ai_weight'] as num?)?.toDouble() ?? 1.0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'difficulty': difficulty,
        'proficiency': proficiency,
        'target_minutes_per_week': targetMinutesPerWeek,
        'exam_date': examDate,
        'ai_weight': aiWeight,
      };
}

class StudyTask {
  StudyTask({
    String? id,
    required this.subjectId,
    required this.title,
    this.type = TaskType.assignment,
    this.due,
    this.priority = 2,
    this.estimatedMinutes = 60,
    this.completedMinutes = 0,
    this.status = TaskStatus.todo,
    this.notes = '',
    String? createdAt,
  })  : id = id ?? newId(),
        createdAt = createdAt ?? isoLocal(DateTime.now());

  final String id;
  String? subjectId;
  String title;
  TaskType type;
  String? due;
  int priority; // 1 low, 2 medium, 3 high
  int estimatedMinutes;
  int completedMinutes;
  TaskStatus status;
  String notes;
  final String createdAt;

  DateTime? get dueAt => parseDue(due);
  int get remainingMinutes => (estimatedMinutes - completedMinutes).clamp(0, 1 << 30);
  bool get isDone => status == TaskStatus.done;

  factory StudyTask.fromJson(Map<String, dynamic> j) => StudyTask(
        id: j['id'] as String?,
        subjectId: j['subject_id'] as String?,
        title: j['title'] as String? ?? 'Task',
        type: _enumByName(TaskType.values, j['type'], TaskType.other),
        due: j['due'] as String?,
        priority: _int(j['priority'], 2),
        estimatedMinutes: _int(j['estimated_minutes'], 60),
        completedMinutes: _int(j['completed_minutes'], 0),
        status: _enumByName(TaskStatus.values, j['status'], TaskStatus.todo),
        notes: j['notes'] as String? ?? '',
        createdAt: j['created_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject_id': subjectId,
        'title': title,
        'type': type.name,
        'due': due,
        'priority': priority,
        'estimated_minutes': estimatedMinutes,
        'completed_minutes': completedMinutes,
        'status': _snake(status.name),
        'notes': notes,
        'created_at': createdAt,
      };
}

class StudySession {
  StudySession({
    String? id,
    required this.subjectId,
    this.taskId,
    required this.title,
    required this.start,
    required this.durationMinutes,
    this.status = SessionStatus.planned,
    this.source = SessionSource.manual,
    this.focusRating,
    this.notes = '',
  }) : id = id ?? newId();

  final String id;
  String? subjectId;
  String? taskId;
  String title;
  String start;
  int durationMinutes;
  SessionStatus status;
  SessionSource source;
  int? focusRating; // 1..5
  String notes; // for auto sessions: why the planner chose it

  DateTime get startAt => parseLocal(start) ?? DateTime.now();
  DateTime get endAt => startAt.add(Duration(minutes: durationMinutes));

  /// Planned sessions whose end has passed count as missed.
  SessionStatus effectiveStatus(DateTime now) =>
      status == SessionStatus.planned && !endAt.isAfter(now) ? SessionStatus.missed : status;

  factory StudySession.fromJson(Map<String, dynamic> j) => StudySession(
        id: j['id'] as String?,
        subjectId: j['subject_id'] as String?,
        taskId: j['task_id'] as String?,
        title: j['title'] as String? ?? 'Study',
        start: j['start'] as String? ?? isoLocal(DateTime.now()),
        durationMinutes: _int(j['duration_minutes'], 45),
        status: _enumByName(SessionStatus.values, j['status'], SessionStatus.planned),
        source: _enumByName(SessionSource.values, j['source'], SessionSource.manual),
        focusRating: (j['focus_rating'] as num?)?.toInt(),
        notes: j['notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject_id': subjectId,
        'task_id': taskId,
        'title': title,
        'start': start,
        'duration_minutes': durationMinutes,
        'status': status.name,
        'source': source.name,
        'focus_rating': focusRating,
        'notes': notes,
      };
}

class Score {
  Score({String? id, required this.subjectId, required this.title, required this.score, this.maxScore = 100, String? date})
      : id = id ?? newId(),
        date = date ?? isoDate(DateTime.now());

  final String id;
  String subjectId;
  String title;
  double score;
  double maxScore;
  String date;

  double get percent => maxScore > 0 ? score / maxScore : 0;

  factory Score.fromJson(Map<String, dynamic> j) => Score(
        id: j['id'] as String?,
        subjectId: j['subject_id'] as String? ?? '',
        title: j['title'] as String? ?? 'Score',
        score: (j['score'] as num?)?.toDouble() ?? 0,
        maxScore: (j['max_score'] as num?)?.toDouble() ?? 100,
        date: j['date'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'subject_id': subjectId, 'title': title, 'score': score, 'max_score': maxScore, 'date': date};
}

class PlannerData {
  PlannerData({
    Profile? profile,
    List<Subject>? subjects,
    List<StudyTask>? tasks,
    List<StudySession>? sessions,
    List<Score>? scores,
    List<String>? tombstones,
    String? updatedAt,
  })  : profile = profile ?? Profile(),
        subjects = subjects ?? [],
        tasks = tasks ?? [],
        sessions = sessions ?? [],
        scores = scores ?? [],
        tombstones = tombstones ?? [],
        updatedAt = updatedAt ?? isoLocal(DateTime.now());

  Profile profile;
  List<Subject> subjects;
  List<StudyTask> tasks;
  List<StudySession> sessions;
  List<Score> scores;
  List<String> tombstones; // ids deleted locally, so sync merges don't resurrect them
  String updatedAt;

  Subject? subjectById(String? id) {
    if (id == null) return null;
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  StudyTask? taskById(String? id) {
    if (id == null) return null;
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  factory PlannerData.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) => ((j[key] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => f(Map<String, dynamic>.from(m)))
        .toList();
    return PlannerData(
      profile: j['profile'] is Map ? Profile.fromJson(Map<String, dynamic>.from(j['profile'] as Map)) : null,
      subjects: list('subjects', Subject.fromJson),
      tasks: list('tasks', StudyTask.fromJson),
      sessions: list('sessions', StudySession.fromJson),
      scores: list('scores', Score.fromJson),
      tombstones: ((j['tombstones'] as List?) ?? const []).map((e) => e.toString()).toList(),
      updatedAt: j['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'updated_at': updatedAt,
        'profile': profile.toJson(),
        'subjects': subjects.map((e) => e.toJson()).toList(),
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((e) => e.toJson()).toList(),
        'scores': scores.map((e) => e.toJson()).toList(),
        'tombstones': tombstones.length > 1000 ? tombstones.sublist(tombstones.length - 1000) : tombstones,
      };
}
