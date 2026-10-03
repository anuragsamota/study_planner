import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../models/settings.dart';
import '../../services/ai_service.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../widgets/common.dart';
import 'tasks_screen.dart';

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initialSection});
  final String? initialSection; // 'ai'

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _aiKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.initialSection == 'ai') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _aiKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _ProfileSection(),
              const SizedBox(height: 16),
              const _AvailabilitySection(),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Subjects',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.school_outlined),
                  title: Text('${state.data.subjects.length} subjects'),
                  subtitle: const Text('Confidence, difficulty, weekly targets and exam dates'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showAdaptiveSheet<void>(context, const SubjectsSheet()),
                ),
              ),
              const SizedBox(height: 16),
              _AiSection(key: _aiKey),
              const SizedBox(height: 16),
              const _RemindersSection(),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Appearance',
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                  ],
                  selected: {state.settings.themeMode},
                  onSelectionChanged: (s) {
                    state.settings.themeMode = s.first;
                    state.saveSettings();
                  },
                ),
              ),
              const SizedBox(height: 16),
              const _DataSection(),
            ]),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- profile

class _ProfileSection extends StatefulWidget {
  const _ProfileSection();
  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<_ProfileSection> {
  late final TextEditingController _name;
  late double _goal, _session, _break, _max;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().data.profile;
    _name = TextEditingController(text: p.name);
    _goal = p.dailyGoalMinutes.toDouble().clamp(15, 600);
    _session = p.sessionMinutes.toDouble().clamp(15, 120);
    _break = p.breakMinutes.toDouble().clamp(0, 30);
    _max = p.maxSessionsPerDay.toDouble().clamp(1, 10);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.data.profile;
    void save(void Function(Profile p) f) => state.updateProfile(f);
    return SectionCard(
      title: 'Study profile',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Your name'),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => save((p) => p.name = v.trim().isEmpty ? 'Student' : v.trim()),
          onTapOutside: (_) {
            if (_name.text.trim() != p.name) save((p) => p.name = _name.text.trim().isEmpty ? 'Student' : _name.text.trim());
            FocusManager.instance.primaryFocus?.unfocus();
          },
        ),
        const SizedBox(height: 12),
        LabeledSlider(
          label: 'Daily study goal',
          value: _goal,
          min: 15,
          max: 600,
          divisions: 39,
          display: (v) => fmtMinutes(v.round()),
          onChanged: (v) => setState(() => _goal = v),
          onChangeEnd: (v) => save((p) => p.dailyGoalMinutes = v.round()),
        ),
        LabeledSlider(
          label: 'Session length',
          value: _session,
          min: 15,
          max: 120,
          divisions: 21,
          display: (v) => fmtMinutes(v.round()),
          onChanged: (v) => setState(() => _session = v),
          onChangeEnd: (v) => save((p) => p.sessionMinutes = v.round()),
        ),
        LabeledSlider(
          label: 'Break between sessions',
          value: _break,
          min: 0,
          max: 30,
          divisions: 6,
          display: (v) => fmtMinutes(v.round()),
          onChanged: (v) => setState(() => _break = v),
          onChangeEnd: (v) => save((p) => p.breakMinutes = v.round()),
        ),
        LabeledSlider(
          label: 'Max sessions per day',
          value: _max,
          min: 1,
          max: 10,
          divisions: 9,
          onChanged: (v) => setState(() => _max = v),
          onChangeEnd: (v) => save((p) => p.maxSessionsPerDay = v.round()),
        ),
        Text('I study best in the…', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (v, label, icon) in studyPeriods)
            ChoiceChip(avatar: Icon(icon, size: 18), label: Text(label), selected: p.preferredTime == v, onSelected: (_) => save((p) => p.preferredTime = v)),
        ]),
      ]),
    );
  }
}

// --------------------------------------------------------------------------- availability

class _AvailabilitySection extends StatelessWidget {
  const _AvailabilitySection();

  Future<TimeWindow?> _editWindow(BuildContext context, TimeWindow? w) async {
    TimeOfDay parse(String s) => TimeOfDay(hour: int.parse(s.split(':')[0]) % 24, minute: int.parse(s.split(':')[1]));
    final start = await showTimePicker(
        context: context, helpText: 'Start time', initialTime: parse(w?.start ?? '17:00'));
    if (start == null || !context.mounted) return null;
    final end = await showTimePicker(
        context: context,
        helpText: 'End time',
        initialTime: parse(w?.end ?? '${(start.hour + 2).clamp(0, 23).toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}'));
    if (end == null) return null;
    String f(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) {
      if (context.mounted) showSnack(context, 'End time must be after start time');
      return null;
    }
    return TimeWindow(f(start), f(end));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final avail = state.data.profile.availability;
    final totalPerWeek = avail.values.expand((l) => l).fold<int>(0, (a, w) => a + (w.endMinutes - w.startMinutes));
    return SectionCard(
      title: 'When can you study?',
      trailing: Text('${fmtMinutes(totalPerWeek)}/week', style: Theme.of(context).textTheme.bodySmall),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('The planner only schedules sessions inside these times.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (var d = 1; d <= 7; d++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(width: 92, child: Text(weekdayNames[d - 1])),
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final w in avail[d] ?? const <TimeWindow>[])
                    InputChip(
                      label: Text('${w.start}–${w.end}'),
                      onPressed: () async {
                        final edited = await _editWindow(context, w);
                        if (edited != null) {
                          state.updateProfile((p) => p.availability[d] = [
                                for (final x in p.availability[d]!) identical(x, w) ? edited : x,
                              ]);
                        }
                      },
                      onDeleted: () => state.updateProfile((p) => p.availability[d]!.remove(w)),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    onPressed: () async {
                      final w = await _editWindow(context, null);
                      if (w != null) state.updateProfile((p) => (p.availability[d] ??= []).add(w));
                    },
                  ),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Copy Monday to all weekdays'),
            onPressed: () => state.updateProfile((p) {
              for (var d = 2; d <= 5; d++) {
                p.availability[d] = [for (final w in p.availability[1] ?? const <TimeWindow>[]) TimeWindow(w.start, w.end)];
              }
            }),
          ),
        ),
      ]),
    );
  }
}

// --------------------------------------------------------------------------- AI

class _AiSection extends StatefulWidget {
  const _AiSection({super.key});
  @override
  State<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends State<_AiSection> {
  late final TextEditingController _url, _key, _model, _mcpUrl, _mcpToken;
  bool _testing = false;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    final ai = context.read<AppState>().settings.ai;
    _url = TextEditingController(text: ai.baseUrl);
    _key = TextEditingController(text: ai.apiKey);
    _model = TextEditingController(text: ai.model);
    _mcpUrl = TextEditingController(text: ai.mcpUrl);
    _mcpToken = TextEditingController(text: ai.mcpToken);
  }

  @override
  void dispose() {
    for (final c in [_url, _key, _model, _mcpUrl, _mcpToken]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final state = context.read<AppState>();
    final ai = state.settings.ai
      ..baseUrl = _url.text.trim()
      ..apiKey = _key.text.trim()
      ..model = _model.text.trim()
      ..mcpUrl = _mcpUrl.text.trim()
      ..mcpToken = _mcpToken.text.trim();
    if (ai.model.isEmpty) ai.model = ai.mode.defaultModel;
    await state.saveSettings();
    setState(() => _testing = true);
    await state.refreshAiStatus();
    if (!mounted) return;
    setState(() => _testing = false);
    final s = state.aiStatus;
    if (s.ollamaOk && s.models.isNotEmpty && !s.models.contains(ai.model) && !s.models.contains('${ai.model}:latest')) {
      showSnack(context, 'Connected, but model "${ai.model}" was not found. Pick one from the list.');
    } else {
      showSnack(context, s.ollamaOk ? 'Connected to Ollama' : 'Could not connect: ${s.ollamaError}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ai = state.settings.ai;
    final status = state.aiStatus;
    final theme = Theme.of(context);
    return SectionCard(
      title: 'AI (Ollama)',
      trailing: Switch(
        value: ai.enabled,
        onChanged: (v) async {
          ai.enabled = v;
          await state.saveSettings();
          await state.refreshAiStatus();
        },
      ),
      child: !ai.enabled
          ? Text('AI features are off. Planning, reminders and analytics work without AI.', style: theme.textTheme.bodyMedium)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Where does Ollama run?', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in OllamaMode.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: ai.mode == m,
                    onSelected: (_) {
                      setState(() {
                        // Only replace the URL/model if they are still the previous mode's defaults.
                        if (_url.text.trim().isEmpty || _url.text.trim() == ai.mode.defaultUrl) _url.text = m.defaultUrl;
                        if (_model.text.trim().isEmpty || _model.text.trim() == ai.mode.defaultModel) _model.text = m.defaultModel;
                        ai.mode = m;
                      });
                      state.saveSettings();
                    },
                  ),
              ]),
              const SizedBox(height: 8),
              Text(ai.mode.help, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Ollama URL', prefixIcon: Icon(Icons.link)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                obscureText: !_showKey,
                decoration: InputDecoration(
                  labelText: ai.mode.needsKey ? 'API key (required)' : 'API key (optional)',
                  prefixIcon: const Icon(Icons.key),
                  suffixIcon: IconButton(
                    icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _model,
                decoration: InputDecoration(
                  labelText: 'Model',
                  helperText: 'Use a model that supports tool calling, e.g. llama3.2, qwen3, gpt-oss',
                  prefixIcon: const Icon(Icons.memory),
                  suffixIcon: status.models.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: 'Choose an available model',
                          icon: const Icon(Icons.arrow_drop_down),
                          onSelected: (m) {
                            setState(() => _model.text = m);
                            ai.model = m;
                            state.saveSettings();
                          },
                          itemBuilder: (_) => [for (final m in status.models) PopupMenuItem(value: m, child: Text(m))],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledSlider(
                label: 'Creativity',
                value: ai.temperature,
                min: 0,
                max: 1,
                divisions: 10,
                display: (v) => v.toStringAsFixed(1),
                onChanged: (v) => setState(() => ai.temperature = v),
                onChangeEnd: (_) => state.saveSettings(),
              ),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: ai.mcpEnabled,
                title: const Text('Connect the planner MCP server'),
                subtitle: const Text('Lets the coach update your plan using tools, syncs your data to the server '
                    'and exposes it to other MCP apps (e.g. Claude Desktop).'),
                onChanged: (v) {
                  setState(() => ai.mcpEnabled = v);
                  state.saveSettings();
                },
              ),
              if (ai.mcpEnabled) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _mcpUrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'MCP server URL', hintText: 'http://localhost:8765/mcp', prefixIcon: Icon(Icons.hub_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _mcpToken,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Access token (PLANNER_API_TOKEN)', prefixIcon: Icon(Icons.lock_outline)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text('Student ID: ${ai.studentId.substring(0, 8)}…'
                        '${ai.lastSyncedAt != null ? ' · last sync ${ai.lastSyncedAt!.replaceFirst('T', ' ')}' : ''}',
                        style: theme.textTheme.bodySmall),
                  ),
                  if (status.mcpOk) TextButton(onPressed: state.syncNow, child: const Text('Sync now')),
                ]),
                if (state.syncError != null) Text(state.syncError!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              _StatusLines(status: status, mcpEnabled: ai.mcpEnabled),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _testing ? null : _saveAndTest,
                icon: _testing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Save & test connection'),
              ),
              if (kIsWeb) ...[
                const SizedBox(height: 8),
                Text('Web app: start Ollama with OLLAMA_ORIGINS="*" (or this site\'s address) so the browser may connect.',
                    style: theme.textTheme.bodySmall),
              ],
            ]),
    );
  }
}

class _StatusLines extends StatelessWidget {
  const _StatusLines({required this.status, required this.mcpEnabled});
  final AiStatus status;
  final bool mcpEnabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget line(bool ok, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ok ? Icons.check_circle : Icons.error_outline, size: 18, color: ok ? scheme.primary : scheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          ]),
        );
    if (!status.checked) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
 line(status.ollamaOk,
          status.ollamaOk ? 'Ollama reachable · ${status.models.length} models' : 'Ollama: ${status.ollamaError}'),
      if (mcpEnabled)
        line(status.mcpOk,
            status.mcpOk ? 'MCP server reachable · ${status.mcpToolCount} tools' : 'MCP server: ${status.mcpError}'),
    ]);
  }
}

// --------------------------------------------------------------------------- reminders

class _RemindersSection extends StatelessWidget {
  const _RemindersSection();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final r = state.settings.reminders;
    Future<void> save() async {
      await state.saveSettings();
      await state.reminders.reschedule(state.data, r);
    }

    return SectionCard(
      title: 'Reminders',
      trailing: Switch(value: r.enabled, onChanged: (v) {
        r.enabled = v;
        save();
      }),
      child: !r.enabled
          ? const Text('Reminders are off.')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('Remind me before each session')),
                DropdownButton<int>(
                  value: const [0, 5, 10, 15, 30, 60].contains(r.minutesBefore) ? r.minutesBefore : 10,
                  items: [
                    for (final m in const [0, 5, 10, 15, 30, 60])
                      DropdownMenuItem(value: m, child: Text(m == 0 ? 'At start' : '$m min')),
                  ],
                  onChanged: (v) {
                    r.minutesBefore = v ?? 10;
                    save();
                  },
                ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Deadline reminders'),
                subtitle: const Text('1 day and 3 hours before something is due'),
                value: r.deadlineReminders,
                onChanged: (v) {
                  r.deadlineReminders = v;
                  save();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Daily plan summary'),
                subtitle: Text('Every morning at ${r.digestTime}'),
                value: r.dailyDigest,
                onChanged: (v) {
                  r.dailyDigest = v;
                  save();
                },
                secondary: r.dailyDigest
                    ? IconButton(
                        tooltip: 'Change time',
                        icon: const Icon(Icons.schedule),
                        onPressed: () async {
                          final p = r.digestTime.split(':');
                          final t = await showTimePicker(
                              context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
                          if (t == null) return;
                          r.digestTime = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                          save();
                        },
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(
                    state.reminders.canSchedule
                        ? 'Notifications arrive even when the app is closed.'
                        : 'On this platform reminders appear while the app is open.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await state.reminders.requestPermission();
                    await state.reminders.showTest();
                  },
                  child: const Text('Test'),
                ),
              ]),
            ]),
    );
  }
}

// --------------------------------------------------------------------------- data

class _DataSection extends StatelessWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return SectionCard(
      title: 'Your data',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Everything is stored on this device. Nothing leaves it unless you connect an MCP server or a remote Ollama.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Export (copy)'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent(' ').convert(state.data.toJson())));
              if (context.mounted) showSnack(context, 'Backup copied to clipboard');
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined),
            label: const Text('Import'),
            onPressed: () => _import(context, state),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Reset app'),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset everything?'),
                  content: const Text('All subjects, tasks, sessions and settings on this device will be deleted.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                  ],
                ),
              );
              if (ok == true) {
                await state.resetAll();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
        ]),
      ]),
    );
  }

  Future<void> _import(BuildContext context, AppState state) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import backup'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'Paste the exported JSON here'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Import')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;
    try {
      final imported = PlannerData.fromJson(jsonDecode(text) as Map<String, dynamic>);
      await state.mutate((d) {
        d
          ..profile = imported.profile
          ..subjects = imported.subjects
          ..tasks = imported.tasks
          ..sessions = imported.sessions
          ..scores = imported.scores;
      });
      if (context.mounted) showSnack(context, 'Backup imported');
    } catch (e) {
      if (context.mounted) showSnack(context, 'That doesn\'t look like a valid backup');
    }
  }
}
