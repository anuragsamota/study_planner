import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'home_shell.dart';
import 'settings_screen.dart';

const _suggestions = [
  'What should I study today?',
  'How am I doing this week?',
  'Which subject should I focus on?',
  'I have a maths test next Friday',
  'Give me tips to stay focused',
];

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});
  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final state = context.read<AppState>();
    if (text.trim().isEmpty || state.coachBusy) return;
    _input.clear();
    final future = state.askCoach(text.trim());
    _scrollToEnd();
    await future;
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _openAiSettings() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen(initialSection: 'ai')));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final status = state.aiStatus;
    final history = state.coachHistory;
    final ready = state.aiAvailable;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Coach'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: 'New conversation',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(history.clear),
            ),
          const SettingsButton(),
        ],
      ),
      body: Column(children: [
        _StatusBar(status: status, enabled: state.settings.ai.enabled, onSetup: _openAiSettings, onRetry: state.refreshAiStatus),
        Expanded(
          child: !ready
              ? Center(
                  child: SingleChildScrollView(
                    child: EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'The AI coach needs Ollama',
                      message: 'Connect to Ollama on this device, your local network or Ollama Cloud.\n'
                          'Your planner, reminders and analytics keep working without it.',
                      action: Wrap(spacing: 8, children: [
                        FilledButton.icon(onPressed: _openAiSettings, icon: const Icon(Icons.settings), label: const Text('Set up AI')),
                        OutlinedButton(onPressed: () => HomeNav.of(context)?.goTo(0), child: const Text('Back to today')),
                      ]),
                    ),
                  ),
                )
              : history.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Column(children: [
                            const EmptyState(
                              icon: Icons.auto_awesome,
                              title: 'Hi! I\'m your study coach',
                              message: 'Ask me what to study, how you\'re doing, or tell me about new deadlines.',
                            ),
                            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                              for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _send(s)),
                            ]),
                          ]),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: history.length + (state.coachBusy ? 1 : 0),
                      itemBuilder: (context, i) => i == history.length
                          ? const _Bubble(message: null)
                          : _Bubble(message: history[i]),
                    ),
        ),
        if (ready)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: _send,
                        decoration: InputDecoration(
                          hintText: status.agentMode ? 'Ask or tell me to change your plan…' : 'Ask your coach…',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: state.coachBusy ? null : () => _send(_input.text),
                      icon: const Icon(Icons.send),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.status, required this.enabled, required this.onSetup, required this.onRetry});
  final AiStatus status;
  final bool enabled;
  final VoidCallback onSetup;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String text, Color bg) = !status.checked
        ? (Icons.hourglass_empty, 'Checking AI connection…', scheme.surfaceContainerHigh)
        : !enabled
            ? (Icons.power_settings_new, 'AI features are off', scheme.surfaceContainerHigh)
            : status.agentMode
                ? (Icons.hub_outlined, 'Connected · Ollama + planner tools (MCP): the coach can update your plan', scheme.primaryContainer)
                : status.ollamaOk
                    ? (Icons.chat_outlined, 'Connected to Ollama · chat only (connect the MCP server to let the coach edit your plan)', scheme.secondaryContainer)
                    : (Icons.cloud_off, 'Ollama not reachable – offline mode', scheme.errorContainer);
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
          TextButton(onPressed: onSetup, child: const Text('Settings')),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final CoachMessage? message; // null = typing indicator

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message?.role == 'user';
    final maxW = (MediaQuery.sizeOf(context).width * 0.8).clamp(240.0, 640.0);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: message == null
              ? const SizedBox(width: 40, height: 18, child: LinearProgressIndicator())
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText(message!.text, style: TextStyle(color: mine ? scheme.onPrimary : scheme.onSurface)),
                  if (message!.toolsUsed.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      for (final t in message!.toolsUsed.toSet())
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(Icons.build_outlined, size: 14),
                          label: Text(t.replaceAll('_', ' '), style: const TextStyle(fontSize: 11)),
                        ),
                    ]),
                  ],
                ]),
        ),
      ),
    );
  }
}
