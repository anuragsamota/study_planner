// End-to-end over real HTTP: the Python MCP server + an Ollama endpoint.
// Skipped unless E2E_MCP_URL and E2E_OLLAMA_URL are set, e.g.:
//
//   (cd server && python -m study_planner_mcp --port 8765 --data-dir /tmp/e2e &)
//   (cd server && python tests/fake_ollama.py --port 11500 &)
//   E2E_MCP_URL=http://127.0.0.1:8765/mcp E2E_OLLAMA_URL=http://127.0.0.1:11500 flutter test test/e2e_mcp_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_planner/models/planner_data.dart';
import 'package:study_planner/models/settings.dart';
import 'package:study_planner/services/ai_service.dart';

void main() {
  final mcpUrl = Platform.environment['E2E_MCP_URL'];
  final ollamaUrl = Platform.environment['E2E_OLLAMA_URL'];
  final skip = mcpUrl == null || ollamaUrl == null ? 'set E2E_MCP_URL and E2E_OLLAMA_URL' : null;

  test('coach adds a task through MCP and the plan comes back', () async {
    final ai = AiService(AiSettings(
      baseUrl: ollamaUrl!,
      model: Platform.environment['E2E_MODEL'] ?? 'fake-model',
      mcpEnabled: true,
      mcpUrl: mcpUrl!,
      mcpToken: Platform.environment['E2E_MCP_TOKEN'] ?? '',
    ));
    final status = await ai.checkStatus();
    expect(status.agentMode, isTrue, reason: '${status.ollamaError} ${status.mcpError}');
    expect(status.mcpToolCount, greaterThan(10));

    final local = PlannerData(subjects: [Subject(name: 'Maths', proficiency: 2)]);
    final reply = await ai.chat([], 'I have a maths test, please plan for it', local, agentMode: true);
    expect(reply.toolsUsed, containsAll(['add_task', 'auto_plan']));

    final data = reply.updatedData!;
    final task = data.tasks.singleWhere((t) => t.title == 'Maths test prep');
    expect(task.type, TaskType.exam);
    expect(data.sessions.where((s) => s.taskId == task.id && s.source == SessionSource.auto), isNotEmpty);
    // student_id isolation: the subject we pushed came back under our id.
    expect(data.subjects.single.name, 'Maths');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
