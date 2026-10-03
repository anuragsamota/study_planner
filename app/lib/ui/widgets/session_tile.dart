import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../screens/focus_screen.dart';
import '../sheets/complete_session_sheet.dart';
import 'common.dart';

class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session, this.highlight = false});
  final StudySession session;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final subject = state.data.subjectById(session.subjectId);
    final status = session.effectiveStatus(state.now);
    final color = Color(subject?.color ?? theme.colorScheme.primary.toARGB32());
    final faded = status == SessionStatus.skipped || status == SessionStatus.missed;

    return Card(
      color: highlight ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showActions(context, state),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            SizedBox(
              width: 64,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fmtTime(session.startAt), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text(fmtMinutes(session.durationMinutes), style: theme.textTheme.bodySmall),
              ]),
            ),
            Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: faded ? 0.55 : 1,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                          decoration: status == SessionStatus.completed ? TextDecoration.lineThrough : null)),
                  Text(
                    [subject?.name, if (session.notes.isNotEmpty) session.notes].whereType<String>().join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            _StatusBadge(status: status, onStart: () => startFocus(context, session)),
          ]),
        ),
      ),
    );
  }

  void _showActions(BuildContext context, AppState state) {
    final status = session.effectiveStatus(state.now);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(session.title, style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: Text('${fmtDay(session.startAt)} · ${fmtTime(session.startAt)} · ${fmtMinutes(session.durationMinutes)}'
                '${session.notes.isNotEmpty ? '\n${session.notes}' : ''}'),
          ),
          const Divider(),
          if (status != SessionStatus.completed) ...[
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Start focus timer'),
              onTap: () {
                Navigator.pop(ctx);
                startFocus(context, session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Mark as done'),
              onTap: () {
                Navigator.pop(ctx);
                showAdaptiveSheet<void>(context, CompleteSessionSheet(session: session, minutes: session.durationMinutes));
              },
            ),
          ],
          if (status == SessionStatus.planned)
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('Skip this session'),
              subtitle: const Text('Your plan will adapt automatically'),
              onTap: () {
                Navigator.pop(ctx);
                state.skipSession(session);
              },
            ),
          if (session.source != SessionSource.auto || status != SessionStatus.planned)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                state.deleteSession(session);
              },
            ),
        ]),
      ),
    );
  }
}

void startFocus(BuildContext context, StudySession session) {
  Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => FocusScreen(session: session)));
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.onStart});
  final SessionStatus status;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      SessionStatus.planned => IconButton.filledTonal(tooltip: 'Start', onPressed: onStart, icon: const Icon(Icons.play_arrow)),
      SessionStatus.completed => Icon(Icons.check_circle, color: scheme.primary),
      SessionStatus.skipped => Tooltip(message: 'Skipped', child: Icon(Icons.skip_next, color: scheme.outline)),
      SessionStatus.missed => Tooltip(message: 'Missed', child: Icon(Icons.history_toggle_off, color: scheme.error)),
    };
  }
}
