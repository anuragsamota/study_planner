import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class McpException implements Exception {
  McpException(this.message);
  final String message;
  @override
  String toString() => message;
}

class McpTool {
  McpTool(this.name, this.description, this.inputSchema);
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
}

class McpToolResult {
  McpToolResult(this.text, this.structured, this.isError);
  final String text;
  final Object? structured;
  final bool isError;
}

/// Minimal MCP client over the Streamable HTTP transport (JSON-RPC 2.0).
///
/// Handles both plain JSON and SSE-framed responses and keeps the
/// `Mcp-Session-Id` header for stateful servers.
class McpClient {
  McpClient({required this.url, this.token = '', http.Client? client}) : _http = client ?? http.Client();

  static const protocolVersion = '2025-06-18';

  final String url;
  final String token;
  final http.Client _http;
  String? _sessionId;
  bool _initialized = false;
  int _nextId = 1;
  Map<String, dynamic>? serverInfo;

  Future<void> initialize() async {
    if (_initialized) return;
    final result = await _request('initialize', {
      'protocolVersion': protocolVersion,
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'study-planner-app', 'version': '1.0.0'},
    });
    serverInfo = Map<String, dynamic>.from(result['serverInfo'] as Map? ?? const {});
    await _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    _initialized = true;
  }

  Future<List<McpTool>> listTools() async {
    await initialize();
    final tools = <McpTool>[];
    String? cursor;
    do {
      final result = await _request('tools/list', {'cursor': ?cursor});
      for (final t in (result['tools'] as List? ?? const []).whereType<Map>()) {
        tools.add(McpTool(
          t['name'].toString(),
          (t['description'] ?? '').toString(),
          Map<String, dynamic>.from(t['inputSchema'] as Map? ?? {'type': 'object'}),
        ));
      }
      cursor = result['nextCursor'] as String?;
    } while (cursor != null);
    return tools;
  }

  Future<McpToolResult> callTool(String name, Map<String, dynamic> arguments) async {
    await initialize();
    final result = await _request('tools/call', {'name': name, 'arguments': arguments});
    final text = (result['content'] as List? ?? const [])
        .whereType<Map>()
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'].toString())
        .join('\n');
    return McpToolResult(text, result['structuredContent'], result['isError'] == true);
  }

  Future<Map<String, dynamic>> _request(String method, Map<String, dynamic> params) async {
    final id = _nextId++;
    final msg = await _post({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    if (msg == null) throw McpException('Empty response from MCP server for $method');
    if (msg['error'] != null) {
      final err = msg['error'] as Map;
      throw McpException('MCP error ${err['code']}: ${err['message']}');
    }
    return Map<String, dynamic>.from(msg['result'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>?> _post(Map<String, dynamic> body) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) throw McpException('Invalid MCP server URL "$url"');
    final http.Response res;
    try {
      res = await _http
          .post(uri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json, text/event-stream',
                'MCP-Protocol-Version': protocolVersion,
                if (token.isNotEmpty) 'Authorization': 'Bearer $token',
                'Mcp-Session-Id': ?_sessionId,
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw McpException('MCP server at $url did not respond in time.');
    } catch (e) {
      throw McpException('Cannot reach MCP server at $url ($e)');
    }
    _sessionId = res.headers['mcp-session-id'] ?? _sessionId;
    if (res.statusCode == 401) throw McpException('MCP server rejected the access token.');
    if (res.statusCode == 202 || res.body.trim().isEmpty) return null;
    if (res.statusCode >= 400) throw McpException('MCP server error ${res.statusCode}: ${res.body}');

    final text = utf8.decode(res.bodyBytes);
    final contentType = res.headers['content-type'] ?? '';
    if (contentType.contains('text/event-stream')) {
      // Take the last JSON-RPC response carried in the SSE stream.
      Map<String, dynamic>? last;
      for (final line in const LineSplitter().convert(text)) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty) continue;
        final decoded = jsonDecode(data);
        if (decoded is Map && (decoded.containsKey('result') || decoded.containsKey('error'))) {
          last = Map<String, dynamic>.from(decoded);
        }
      }
      return last;
    }
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }

  void close() => _http.close();
}
