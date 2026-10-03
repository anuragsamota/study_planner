import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../sheets/task_editor_sheet.dart';
import 'common.dart';

IconData taskTypeIcon(TaskType t) => switch (t) {
      TaskType.assignment => Icons.assignment_outlined,
      TaskType.project => Icons.construction_outlined,
      TaskType.exam => Icons.quiz_outlined,
      TaskType.reading => Icons.menu_book_outlined,
      TaskType.revision => Icons.replay_outlined,
      TaskType.other => Icons.task_alt_outlined,
    };

const priorityLabels = {1: 'Low', 2: 'Medium', 3: 'High'};

class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, this.dense = false});
  final StudyTask task;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final subject = state.data.subjectById(task.subjectId);
    final due = task.dueAt;
    final overdue = due != null && due.isBefore(state.now) && !task.isDone;
    final progress = task.estimatedMinutes == 0 ? 0.0 : (task.completedMinutes / task.estimatedMinutes).clamp(0.0, 1.0);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showAdaptiveSheet<void>(context, TaskEditorSheet(task: task)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(4, dense ? 4 : 8, 12, dense ? 4 : 8),
          child: Row(children: [
            Checkbox(
              value: task.isDone,
              shape: const CircleBorder(),
              onChanged: (v) => state.setTaskDone(task, v ?? false),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (subject != null) ...[SubjectDot(color: subject.color, size: 10), const SizedBox(width: 6)],
                  Expanded(
                    child: Text(task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(decoration: task.isDone ? TextDecoration.lineThrough : null)),
                  ),
                  if (task.priority == 3 && !task.isDone)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.priority_high, size: 16, color: theme.colorScheme.error),
                    ),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 10, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _Meta(icon: taskTypeIcon(task.type), text: subject?.name ?? capitalize(task.type.name)),
                  if (due != null)
                    _Meta(
                      icon: Icons.event_outlined,
                      text: fmtDue(due, now: state.now),
                      color: overdue ? theme.colorScheme.error : null,
                    ),
                  _Meta(icon: Icons.timelapse, text: '${fmtMinutes(task.completedMinutes)} / ${fmtMinutes(task.estimatedMinutes)}'),
                ]),
                if (!dense && !task.isDone && progress > 0) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: progress, minHeight: 4),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: c),
      const SizedBox(width: 3),
      Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c)),
    ]);
  }
}
