// App settings: AI backend (Ollama + MCP server), reminders, appearance.

import 'package:flutter/material.dart';

import 'planner_data.dart';

/// Where the Ollama instance lives. Each mode only pre-fills sensible defaults;
/// the URL is always editable.
enum OllamaMode { local, lan, cloud, custom }

extension OllamaModeInfo on OllamaMode {
  String get label => switch (this) {
        OllamaMode.local => 'This device',
        OllamaMode.lan => 'Local network (LAN)',
        OllamaMode.cloud => 'Ollama Cloud',
        OllamaMode.custom => 'Custom / self-hosted',
      };

  String get help => switch (this) {
        OllamaMode.local => 'Ollama running on this computer (http://localhost:11434).',
        OllamaMode.lan => 'Ollama on another computer in your network. Start it with OLLAMA_HOST=0.0.0.0 '
            'and enter that computer\'s IP address.',
        OllamaMode.cloud => 'Ollama\'s hosted models at ollama.com. Needs an API key from ollama.com/settings/keys.',
        OllamaMode.custom => 'Any Ollama-compatible endpoint, e.g. your own server behind HTTPS. '
            'API key is optional (sent as a Bearer token).',
      };

  String get defaultUrl => switch (this) {
        OllamaMode.local => 'http://localhost:11434',
        OllamaMode.lan => 'http://192.168.1.10:11434',
        OllamaMode.cloud => 'https://ollama.com',
        OllamaMode.custom => 'https://ollama.example.com',
      };

  String get defaultModel => this == OllamaMode.cloud ? 'gpt-oss:20b' : 'llama3.2';
  bool get needsKey => this == OllamaMode.cloud;
}

class AiSettings {
  AiSettings({
    this.enabled = true,
    this.mode = OllamaMode.local,
    String? baseUrl,
    String? model,
    this.apiKey = '',
    this.temperature = 0.4,
    this.mcpEnabled = false,
    this.mcpUrl = 'http://localhost:8765/mcp',
    this.mcpToken = '',
    String? studentId,
    this.lastSyncedAt,
  })  : baseUrl = baseUrl ?? mode.defaultUrl,
        model = model ?? mode.defaultModel,
        studentId = studentId ?? newId();

  bool enabled;
  OllamaMode mode;
  String baseUrl;
  String model;
  String apiKey;
  double temperature;

  bool mcpEnabled;
  String mcpUrl;
  String mcpToken;
  String studentId; // identifies this student's data on a shared MCP server
  String? lastSyncedAt;

  factory AiSettings.fromJson(Map<String, dynamic> j) {
    final mode = OllamaMode.values.asNameMap()[j['mode']] ?? OllamaMode.local;
    return AiSettings(
      enabled: j['enabled'] as bool? ?? true,
      mode: mode,
      baseUrl: j['base_url'] as String?,
      model: j['model'] as String?,
      apiKey: j['api_key'] as String? ?? '',
      temperature: (j['temperature'] as num?)?.toDouble() ?? 0.4,
      mcpEnabled: j['mcp_enabled'] as bool? ?? false,
      mcpUrl: j['mcp_url'] as String? ?? 'http://localhost:8765/mcp',
      mcpToken: j['mcp_token'] as String? ?? '',
      studentId: j['student_id'] as String?,
      lastSyncedAt: j['last_synced_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'mode': mode.name,
        'base_url': baseUrl,
        'model': model,
        'api_key': apiKey,
        'temperature': temperature,
        'mcp_enabled': mcpEnabled,
        'mcp_url': mcpUrl,
        'mcp_token': mcpToken,
        'student_id': studentId,
        'last_synced_at': lastSyncedAt,
      };
}

class ReminderSettings {
  ReminderSettings({
    this.enabled = true,
    this.minutesBefore = 10,
    this.deadlineReminders = true,
    this.dailyDigest = true,
    this.digestTime = '08:00',
  });

  bool enabled;
  int minutesBefore;
  bool deadlineReminders;
  bool dailyDigest;
  String digestTime; // HH:MM

  factory ReminderSettings.fromJson(Map<String, dynamic> j) => ReminderSettings(
        enabled: j['enabled'] as bool? ?? true,
        minutesBefore: (j['minutes_before'] as num?)?.toInt() ?? 10,
        deadlineReminders: j['deadline_reminders'] as bool? ?? true,
        dailyDigest: j['daily_digest'] as bool? ?? true,
        digestTime: j['digest_time'] as String? ?? '08:00',
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'minutes_before': minutesBefore,
        'deadline_reminders': deadlineReminders,
        'daily_digest': dailyDigest,
        'digest_time': digestTime,
      };
}

class AppSettings {
  AppSettings({AiSettings? ai, ReminderSettings? reminders, this.themeMode = ThemeMode.system, this.onboarded = false})
      : ai = ai ?? AiSettings(),
        reminders = reminders ?? ReminderSettings();

  AiSettings ai;
  ReminderSettings reminders;
  ThemeMode themeMode;
  bool onboarded;

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        ai: j['ai'] is Map ? AiSettings.fromJson(Map<String, dynamic>.from(j['ai'] as Map)) : null,
        reminders: j['reminders'] is Map
            ? ReminderSettings.fromJson(Map<String, dynamic>.from(j['reminders'] as Map))
            : null,
        themeMode: ThemeMode.values.asNameMap()[j['theme_mode']] ?? ThemeMode.system,
        onboarded: j['onboarded'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'ai': ai.toJson(),
        'reminders': reminders.toJson(),
        'theme_mode': themeMode.name,
        'onboarded': onboarded,
      };
}
