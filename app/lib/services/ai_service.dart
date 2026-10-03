// AI features with graceful degradation:
//
//  * Ollama + MCP server  -> full agent: the model calls the planner's MCP
//                            tools (add tasks, re-plan, log study, ...).
//  * Ollama only          -> the coach answers using a snapshot of the
//                            student's data in the prompt (read-only).
//  * neither              -> the app keeps working with its built-in planner,
//                            analytics and reminders; AI screens explain how
//                            to connect.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/planner_data.dart';
import '../models/settings.dart';
import 'analytics.dart';
import 'mcp_client.dart';
import 'ollama_client.dart';

class AiStatus {
  const AiStatus({
    this.ollamaOk = false,
    this.mcpOk = false,
    this.models = const [],
    this.ollamaError,
    this.mcpError,
    this.mcpToolCount = 0,
    this.checked = false,
  });

  final bool ollamaOk;
  final bool mcpOk;
  final List<String> models;
  final String? ollamaError;
  final String? mcpError;
  final int mcpToolCount;
  final bool checked;

  bool get agentMode => ollamaOk && mcpOk;
}

class CoachMessage {
  CoachMessage(this.role, this.text, {this.toolsUsed = const []});
  final String role; // user | assistant
  final String text;
  final List<String> toolsUsed;
}

class CoachReply {
  CoachReply(this.text, this.toolsUsed, this.updatedData);
  final String text;
  final List<String> toolsUsed;
  final PlannerData? updatedData; // agent mode: the server's document after the turn
}

class AiProfile {
  AiProfile(this.summary, this.weights);
  final String summary;
  final Map<String, double> weights; // subject id -> emphasis (0.5..2)
}

class AiService {
  AiService(this.settings, {this._httpClient});

  AiSettings settings;
  final http.Client Function()? _httpClient;

  static const _maxToolRounds = 6;

  OllamaClient _ollama() =>
      OllamaClient(baseUrl: settings.baseUrl, apiKey: settings.apiKey, client: _httpClient?.call());
  McpClient _mcp() => McpClient(url: settings.mcpUrl, token: settings.mcpToken, client: _httpClient?.call());

  Future<AiStatus> checkStatus() async {
    if (!settings.enabled) return const AiStatus(checked: true, ollamaError: 'AI features are turned off');
    var status = const AiStatus(checked: true);
    final ollama = _ollama();
    try {
      final models = await ollama.listModels();
      status = AiStatus(checked: true, ollamaOk: true, models: models);
    } catch (e) {
      status = AiStatus(checked: true, ollamaError: e.toString());
    } finally {
      ollama.close();
    }
    if (!settings.mcpEnabled) return status;
    final mcp = _mcp();
    try {
      final tools = await mcp.listTools();
      return AiStatus(
          checked: true,
          ollamaOk: status.ollamaOk,
          ollamaError: status.ollamaError,
          models: status.models,
          mcpOk: true,
          mcpToolCount: tools.length);
    } catch (e) {
      return AiStatus(
          checked: true,
          ollamaOk: status.ollamaOk,
          ollamaError: status.ollamaError,
          models: status.models,
          mcpError: e.toString());
    } finally {
      mcp.close();
    }
  }

  // ------------------------------------------------------------------ sync

  /// Push local data to the MCP server; returns the (possibly merged) document.
  Future<PlannerData> syncPush(PlannerData data) async {
    final mcp = _mcp();
    try {
      final res = await mcp.callTool('sync_push', {
        'snapshot': data.toJson(),
        'last_synced_at': settings.lastSyncedAt,
        'student_id': settings.studentId,
      });
      if (res.isError) throw McpException(res.text);
      final doc = _structured(res)['document'];
      final merged = PlannerData.fromJson(Map<String, dynamic>.from(doc as Map));
      settings.lastSyncedAt = merged.updatedAt;
      return merged;
    } finally {
      mcp.close();
    }
  }

  Future<PlannerData> syncPull() async {
    final mcp = _mcp();
    try {
      final res = await mcp.callTool('sync_pull', {'student_id': settings.studentId});
      if (res.isError) throw McpException(res.text);
      final pulled = PlannerData.fromJson(_structured(res));
      settings.lastSyncedAt = pulled.updatedAt;
      return pulled;
    } finally {
      mcp.close();
    }
  }

  Map<String, dynamic> _structured(McpToolResult res) {
    final s = res.structured;
    if (s is Map) {
      // FastMCP wraps non-object return values in {"result": ...}.
      final m = Map<String, dynamic>.from(s);
      return m.length == 1 && m['result'] is Map ? Map<String, dynamic>.from(m['result'] as Map) : m;
    }
    return Map<String, dynamic>.from(jsonDecode(res.text) as Map);
  }

  // ------------------------------------------------------------------ coach chat

  String _systemPrompt(PlannerData data, DateTime now, {required bool tools}) {
    final p = data.profile;
    final base = StringBuffer()
      ..writeln('You are a friendly, concise study coach inside a study planner app for ${p.name}.')
      ..writeln('Current local time: ${isoLocal(now)} (${_weekday(now)}).')
      ..writeln('Help the student decide what to study, stay motivated and manage deadlines. '
          'Keep answers short (under 150 words), practical and encouraging. Use bullet points for plans.');
    if (p.aiSummary != null) base.writeln('Learner profile: ${p.aiSummary}');
    if (tools) {
      base.writeln('You can read and change the student\'s planner with tools. Look data up with tools instead of '
          'guessing. After adding or changing tasks or subjects, call auto_plan so the schedule updates. '
          'Never invent task ids – get them from list_tasks.');
    } else {
      base
        ..writeln('You cannot change the planner yourself. If the student asks you to change something, tell them '
            'which button to use (Tasks tab to add tasks, Plan tab to re-plan).')
        ..writeln('Student data (JSON):')
        ..writeln(jsonEncode(contextSnapshot(data, now)));
    }
    return base.toString();
  }

  /// Compact view of the student's data for prompts.
  static Map<String, dynamic> contextSnapshot(PlannerData data, DateTime now) {
    final stats = summarize(data, now);
    final open = data.tasks.where((t) => !t.isDone).toList()
      ..sort((a, b) => (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999)));
    final soon = data.sessions
        .where((s) => s.status == SessionStatus.planned && !s.startAt.isBefore(now) && s.startAt.isBefore(now.add(const Duration(days: 3))))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return {
      'profile': {
        'daily_goal_minutes': data.profile.dailyGoalMinutes,
        'session_minutes': data.profile.sessionMinutes,
        'preferred_time': data.profile.preferredTime,
      },
      'analytics': stats.toJson(),
      'open_tasks': [
        for (final t in open.take(15))
          {
            'title': t.title,
            'subject': data.subjectById(t.subjectId)?.name,
            'type': t.type.name,
            'due': t.due,
            'priority': t.priority,
            'minutes_left': t.remainingMinutes,
          }
      ],
      'next_sessions': [
        for (final s in soon.take(12))
          {'start': s.start, 'minutes': s.durationMinutes, 'title': s.title, 'subject': data.subjectById(s.subjectId)?.name}
      ],
    };
  }

  /// One coach turn. In agent mode the local [data] is synced to the MCP server
  /// first and the server's document is returned afterwards.
  Future<CoachReply> chat(List<CoachMessage> history, String message, PlannerData data,
      {required bool agentMode}) async {
    final now = DateTime.now();
    final ollama = _ollama();
    final mcp = agentMode ? _mcp() : null;
    try {
      List<Map<String, dynamic>>? tools;
      if (mcp != null) {
        await syncPush(data);
        tools = [
          for (final t in await mcp.listTools())
            if (!t.name.startsWith('sync_')) _toOllamaTool(t),
        ];
      }
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': _systemPrompt(data, now, tools: mcp != null)},
        for (final m in history.length > 12 ? history.sublist(history.length - 12) : history)
          {'role': m.role, 'content': m.text},
        {'role': 'user', 'content': message},
      ];
      final used = <String>[];
      for (var round = 0; round <= _maxToolRounds; round++) {
        final reply = await ollama.chat(
          model: settings.model,
          messages: messages,
          tools: round < _maxToolRounds ? tools : null,
          temperature: settings.temperature,
        );
        if (reply.toolCalls.isEmpty || mcp == null) {
          // In agent mode the server copy is authoritative after the turn
          // (it includes the merge done by syncPush and any tool changes).
          final updated = mcp != null ? await syncPull() : null;
          final text = reply.content.isEmpty ? 'Done.' : _stripThinking(reply.content);
          return CoachReply(text, used, updated);
        }
        messages.add(reply.raw);
        for (final call in reply.toolCalls) {
          used.add(call.name);
          String content;
          try {
            final res = await mcp.callTool(call.name, {...call.arguments, 'student_id': settings.studentId});
            content = res.isError ? 'Error: ${res.text}' : res.text;
          } catch (e) {
            content = 'Error: $e';
          }
          messages.add({'role': 'tool', 'tool_name': call.name, 'content': _truncate(content, 6000)});
        }
      }
      return CoachReply('Sorry, I got stuck. Please try rephrasing.', used, await syncPull());
    } finally {
      ollama.close();
      mcp?.close();
    }
  }

  Map<String, dynamic> _toOllamaTool(McpTool t) {
    // student_id is filled in by the app, so hide it from the model.
    final schema = jsonDecode(jsonEncode(t.inputSchema)) as Map<String, dynamic>;
    (schema['properties'] as Map?)?.remove('student_id');
    (schema['required'] as List?)?.remove('student_id');
    schema.remove('title');
    return {
      'type': 'function',
      'function': {'name': t.name, 'description': t.description, 'parameters': schema},
    };
  }

  // ------------------------------------------------------------------ structured helpers

  /// Personalised learner profile + per-subject emphasis for the planner.
  Future<AiProfile> buildProfile(PlannerData data) async {
    final now = DateTime.now();
    final ollama = _ollama();
    try {
      final reply = await ollama.chat(
        model: settings.model,
        temperature: 0.3,
        format: {
          'type': 'object',
          'properties': {
            'summary': {'type': 'string'},
            'subject_emphasis': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'subject': {'type': 'string'},
                  'weight': {'type': 'number'},
                },
                'required': ['subject', 'weight'],
              },
            },
          },
          'required': ['summary', 'subject_emphasis'],
        },
        messages: [
          {
            'role': 'system',
            'content': 'You analyse a student\'s study data and write a personalised learner profile. '
                'Reply with JSON only. "summary": 3-5 short sentences in second person covering strengths, '
                'weak areas, study habits (time of day, consistency, focus) and 2 concrete tips. '
                '"subject_emphasis": for every subject a weight between 0.5 (needs less time) and 2.0 '
                '(needs much more time) for the automatic planner; 1.0 is neutral.',
          },
          {'role': 'user', 'content': jsonEncode(contextSnapshot(data, now))},
        ],
      );
      final json = _decodeJson(reply.content);
      final weights = <String, double>{};
      for (final e in (json['subject_emphasis'] as List? ?? const []).whereType<Map>()) {
        final name = e['subject'].toString().toLowerCase().trim();
        final subject = data.subjects.where((s) => s.name.toLowerCase().trim() == name).firstOrNull;
        final w = (e['weight'] as num?)?.toDouble();
        if (subject != null && w != null) weights[subject.id] = w.clamp(0.5, 2.0);
      }
      final summary = (json['summary'] ?? '').toString().trim();
      if (summary.isEmpty) throw OllamaException('The model returned an empty profile. Try another model.');
      return AiProfile(summary, weights);
    } finally {
      ollama.close();
    }
  }

  /// Turn "physics lab report due next friday, ~3h, important" into a task.
  Future<StudyTask> parseTask(String text, PlannerData data) async {
    final now = DateTime.now();
    final ollama = _ollama();
    try {
      final reply = await ollama.chat(
        model: settings.model,
        temperature: 0,
        format: {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'subject': {'type': 'string'},
            'type': {'type': 'string', 'enum': TaskType.values.map((e) => e.name).toList()},
            'due': {'type': 'string', 'description': 'YYYY-MM-DD or YYYY-MM-DDTHH:MM, empty if none'},
            'priority': {'type': 'integer', 'enum': [1, 2, 3]},
            'estimated_minutes': {'type': 'integer'},
          },
          'required': ['title', 'subject', 'type', 'due', 'priority', 'estimated_minutes'],
        },
        messages: [
          {
            'role': 'system',
            'content': 'Extract one study task from the user text. Today is ${isoDate(now)} (${_weekday(now)}). '
                'Known subjects: ${data.subjects.map((s) => s.name).join(', ')}. Pick the closest subject name. '
                'Resolve relative dates. priority: 1 low, 2 normal, 3 high/urgent. Estimate minutes if not given. '
                'Reply with JSON only.',
          },
          {'role': 'user', 'content': text},
        ],
      );
      final j = _decodeJson(reply.content);
      final subjectName = (j['subject'] ?? '').toString().toLowerCase();
      final subject = data.subjects.where((s) => s.name.toLowerCase() == subjectName).firstOrNull ??
          data.subjects.where((s) => subjectName.contains(s.name.toLowerCase()) || s.name.toLowerCase().contains(subjectName)).firstOrNull;
      final due = (j['due'] ?? '').toString();
      return StudyTask(
        subjectId: subject?.id ?? (data.subjects.isNotEmpty ? data.subjects.first.id : null),
        title: (j['title'] ?? text).toString(),
        type: TaskType.values.asNameMap()[j['type']] ?? TaskType.assignment,
        due: parseLocal(due) == null ? null : (due.length <= 10 ? due : isoLocal(parseLocal(due)!)),
        priority: ((j['priority'] as num?)?.toInt() ?? 2).clamp(1, 3),
        estimatedMinutes: ((j['estimated_minutes'] as num?)?.toInt() ?? 60).clamp(15, 6000),
      );
    } finally {
      ollama.close();
    }
  }

  static Map<String, dynamic> _decodeJson(String content) {
    final text = _stripThinking(content);
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) throw OllamaException('The model did not return JSON. Try another model.');
    return Map<String, dynamic>.from(jsonDecode(text.substring(start, end + 1)) as Map);
  }

  static String _stripThinking(String s) => s.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  static String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';
  static String _weekday(DateTime d) =>
      const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1];
}
