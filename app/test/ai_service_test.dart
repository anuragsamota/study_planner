import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_planner/models/planner_data.dart';
import 'package:study_planner/models/settings.dart';
import 'package:study_planner/services/ai_service.dart';

/// Fake Ollama + MCP server.
class FakeBackend {
  final ollamaRequests = <Map<String, dynamic>>[];
  final mcpCalls = <Map<String, dynamic>>[];
  var serverDoc = PlannerData(subjects: [Subject(id: 'm', name: 'Maths')]).toJson();
  int chatTurn = 0;

  http.Client client() => MockClient((req) async {
        if (req.url.host == 'ollama.test') return _ollama(req);
        if (req.url.host == 'mcp.test') return _mcp(req);
        return http.Response('nope', 404);
      });

  http.Response _json(Object body, {Map<String, String> headers = const {}}) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json', ...headers});

  Future<http.Response> _ollama(http.Request req) async {
    if (req.url.path == '/api/tags') {
      return _json({'models': [{'name': 'llama3.2:latest'}]});
    }
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    ollamaRequests.add(body);
    chatTurn++;
    if (body['tools'] != null && chatTurn == 1) {
      return _json({
        'message': {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {'function': {'name': 'add_task', 'arguments': {'title': 'Test prep', 'subject': 'Maths', 'due': '2026-10-09'}}}
          ],
        }
      });
    }
    return _json({'message': {'role': 'assistant', 'content': 'Added it and re-planned your week.'}});
  }

  Future<http.Response> _mcp(http.Request req) async {
    final msg = jsonDecode(req.body) as Map<String, dynamic>;
    if (msg['id'] == null) return http.Response('', 202);
    Object result;
    switch (msg['method']) {
      case 'initialize':
        result = {'protocolVersion': '2025-06-18', 'serverInfo': {'name': 'study-planner'}, 'capabilities': {}};
      case 'tools/list':
        result = {
          'tools': [
            {
              'name': 'add_task',
              'description': 'Add a task',
              'inputSchema': {
                'type': 'object',
                'properties': {'title': {'type': 'string'}, 'student_id': {'type': 'string'}},
                'required': ['title'],
              },
            },
            {'name': 'sync_push', 'description': '', 'inputSchema': {'type': 'object'}},
            {'name': 'sync_pull', 'description': '', 'inputSchema': {'type': 'object'}},
          ]
        };
      case 'tools/call':
        final p = msg['params'] as Map<String, dynamic>;
        mcpCalls.add(p);
        final args = p['arguments'] as Map<String, dynamic>;
        switch (p['name']) {
          case 'sync_push':
            serverDoc = args['snapshot'] as Map<String, dynamic>;
            result = {'content': [{'type': 'text', 'text': '{}'}], 'structuredContent': {'merged': false, 'document': serverDoc}};
          case 'sync_pull':
            result = {'content': [{'type': 'text', 'text': jsonEncode(serverDoc)}], 'structuredContent': serverDoc};
          default:
            (serverDoc['tasks'] as List).add(StudyTask(id: 'new', subjectId: 'm', title: args['title'] as String).toJson());
            serverDoc['updated_at'] = '2026-10-05T09:00:00';
            result = {'content': [{'type': 'text', 'text': '{"id": "new"}'}], 'isError': false};
        }
      default:
        return _json({'jsonrpc': '2.0', 'id': msg['id'], 'error': {'code': -32601, 'message': 'no'}});
    }
    // Answer as SSE to exercise that code path too.
    return http.Response('event: message\ndata: ${jsonEncode({'jsonrpc': '2.0', 'id': msg['id'], 'result': result})}\n\n', 200,
        headers: {'content-type': 'text/event-stream', 'mcp-session-id': 'abc'});
  }
}

void main() {
  late FakeBackend backend;
  late AiService ai;

  setUp(() {
    backend = FakeBackend();
    ai = AiService(
      AiSettings(baseUrl: 'http://ollama.test', mcpEnabled: true, mcpUrl: 'http://mcp.test/mcp', studentId: 'stu1'),
      httpClient: backend.client,
    );
  });

  test('status reports Ollama models and MCP tools', () async {
    final s = await ai.checkStatus();
    expect(s.ollamaOk, isTrue);
    expect(s.models, ['llama3.2:latest']);
    expect(s.mcpOk, isTrue);
    expect(s.agentMode, isTrue);
  });

  test('agent mode: model calls MCP tools, student_id is injected, data comes back', () async {
    final local = PlannerData(subjects: [Subject(id: 'm', name: 'Maths')]);
    final reply = await ai.chat([], 'I have a maths test on Friday', local, agentMode: true);

    expect(reply.text, 'Added it and re-planned your week.');
    expect(reply.toolsUsed, ['add_task']);
    expect(reply.updatedData!.tasks.single.title, 'Test prep');

    final tools = backend.ollamaRequests.first['tools'] as List;
    expect(tools.map((t) => t['function']['name']), ['add_task']); // sync_* hidden
    expect((tools.single['function']['parameters']['properties'] as Map).containsKey('student_id'), isFalse);

    final call = backend.mcpCalls.firstWhere((c) => c['name'] == 'add_task');
    expect(call['arguments']['student_id'], 'stu1');
    // The tool result was fed back to the model.
    final second = backend.ollamaRequests[1]['messages'] as List;
    expect(second.last['role'], 'tool');
  });

  test('chat-only mode embeds the student data and sends no tools', () async {
    final local = PlannerData(subjects: [Subject(id: 'm', name: 'Maths')]);
    final reply = await ai.chat([], 'How am I doing?', local, agentMode: false);
    expect(reply.updatedData, isNull);
    final req = backend.ollamaRequests.single;
    expect(req['tools'], isNull);
    expect((req['messages'] as List).first['content'], contains('"name":"Maths"'));
  });

  test('unreachable Ollama gives a friendly error', () async {
    final offline = AiService(AiSettings(baseUrl: 'http://ollama.test'),
        httpClient: () => MockClient((_) async => throw const SocketLikeException()));
    final s = await offline.checkStatus();
    expect(s.ollamaOk, isFalse);
    expect(s.ollamaError, contains('Cannot reach Ollama'));
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}
