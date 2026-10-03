import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../sheets/complete_session_sheet.dart';
import '../widgets/common.dart';

/// Distraction-free countdown for one study session.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.session});
  final StudySession session;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  late final int _total = widget.session.durationMinutes * 60;
  int _elapsed = 0;
  bool _running = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_running) return;
      setState(() => _elapsed++);
      if (_elapsed >= _total) {
        _running = false;
        _finish();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _running = false);
    final saved = await showAdaptiveSheet<bool>(
      context,
      CompleteSessionSheet(session: widget.session, minutes: (_elapsed / 60).ceil().clamp(1, 600)),
    );
    if (saved == true && mounted) Navigator.of(context).pop();
  }

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject = context.watch<AppState>().data.subjectById(widget.session.subjectId);
    final color = Color(subject?.color ?? theme.colorScheme.primary.toARGB32());
    final remaining = (_total - _elapsed).clamp(0, _total);
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final dial = (shortest * 0.65).clamp(200.0, 380.0);

    return Scaffold(
      appBar: AppBar(title: const Text('Focus')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.session.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              if (subject != null) Text(subject.name, style: theme.textTheme.titleMedium?.copyWith(color: color)),
              const SizedBox(height: 32),
              SizedBox(
                width: dial,
                height: dial,
                child: Stack(fit: StackFit.expand, children: [
                  CircularProgressIndicator(
                    value: _total == 0 ? 1 : _elapsed / _total,
                    strokeWidth: 12,
                    strokeCap: StrokeCap.round,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                  ),
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_fmt(remaining),
                          style: theme.textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                      Text(_running ? 'Stay focused' : 'Paused', style: theme.textTheme.titleMedium),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 32),
              Wrap(spacing: 16, runSpacing: 12, alignment: WrapAlignment.center, children: [
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _running = !_running),
                  icon: Icon(_running ? Icons.pause : Icons.play_arrow),
                  label: Text(_running ? 'Pause' : 'Resume'),
                ),
                FilledButton.icon(onPressed: _finish, icon: const Icon(Icons.check), label: const Text('Finish')),
              ]),
              const SizedBox(height: 16),
              Text('Tip: put your phone face down and close other tabs.', style: theme.textTheme.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }
}
