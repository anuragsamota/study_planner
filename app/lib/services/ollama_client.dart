import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class OllamaException implements Exception {
  OllamaException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ToolCall {
  ToolCall(this.name, this.arguments);
  final String name;
  final Map<String, dynamic> arguments;
}

class ChatReply {
  ChatReply(this.content, this.toolCalls, this.raw);
  final String content;
  final List<ToolCall> toolCalls;
  final Map<String, dynamic> raw; // the assistant message, to append to history
}

/// Minimal client for the Ollama REST API. Works with a local instance, one on
/// the LAN, Ollama Cloud (https://ollama.com + API key) or any compatible proxy.
class OllamaClient {
  OllamaClient({required String baseUrl, this.apiKey = '', http.Client? client})
      : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final http.Client _http;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      };

  Uri _uri(String path) {
    final uri = Uri.tryParse('$baseUrl$path');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw OllamaException('Invalid Ollama URL "$baseUrl". Example: http://localhost:11434');
    }
    return uri;
  }

  /// Installed / available model names.
  Future<List<String>> listModels({Duration timeout = const Duration(seconds: 6)}) async {
    final res = await _send(() => _http.get(_uri('/api/tags'), headers: _headers), timeout);
    final models = (res['models'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => (m['name'] ?? m['model']).toString())
        .toList()
      ..sort();
    return models;
  }

  /// One non-streaming chat turn. [format] may be a JSON schema for structured output.
  Future<ChatReply> chat({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Object? format,
    double temperature = 0.4,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final body = {
      'model': model,
      'messages': messages,
      'stream': false,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
      'format': ?format,
      'options': {'temperature': temperature},
    };
    final res = await _send(
      () => _http.post(_uri('/api/chat'), headers: _headers, body: jsonEncode(body)),
      timeout,
    );
    final message = Map<String, dynamic>.from(res['message'] as Map? ?? const {});
    final calls = <ToolCall>[];
    for (final c in (message['tool_calls'] as List? ?? const []).whereType<Map>()) {
      final fn = Map<String, dynamic>.from(c['function'] as Map? ?? const {});
      var args = fn['arguments'];
      if (args is String) {
        try {
          args = jsonDecode(args);
        } catch (_) {
          args = <String, dynamic>{};
        }
      }
      calls.add(ToolCall(fn['name'].toString(), Map<String, dynamic>.from(args as Map? ?? const {})));
    }
    return ChatReply((message['content'] as String? ?? '').trim(), calls, message);
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request, Duration timeout) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } on TimeoutException {
      throw OllamaException('Ollama at $baseUrl did not respond in time.');
    } catch (e) {
      throw OllamaException('Cannot reach Ollama at $baseUrl. Is it running and reachable? ($e)');
    }
    Map<String, dynamic> body = const {};
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw OllamaException('Ollama rejected the API key (HTTP ${res.statusCode}).');
    }
    if (res.statusCode >= 400) {
      throw OllamaException('Ollama error ${res.statusCode}: ${body['error'] ?? res.reasonPhrase}');
    }
    return body;
  }

  void close() => _http.close();
}
