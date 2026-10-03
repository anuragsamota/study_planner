import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../sheets/subject_editor_sheet.dart';
import '../sheets/task_editor_sheet.dart';
import '../widgets/common.dart';
import '../widgets/task_tile.dart';
import 'home_shell.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _showDone = false;
  String? _subjectFilter;

  Future<void> _quickAddWithAi() async {
    final state = context.read<AppState>();
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Describe your task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'e.g. Physics lab report due next Friday, about 3 hours, important'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Continue')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    showSnack(context, 'Reading your task…');
    try {
      final task = await state.ai.parseTask(text, state.data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await showAdaptiveSheet<void>(context, TaskEditorSheet(task: task, isNew: true));
    } catch (e) {
      if (mounted) showSnack(context, 'AI could not read that: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = state.now;
    final tasks = state.data.tasks
        .where((t) => t.isDone == _showDone && (_subjectFilter == null || t.subjectId == _subjectFilter))
        .toList()
      ..sort((a, b) {
        final c = (a.dueAt ?? DateTime(9999)).compareTo(b.dueAt ?? DateTime(9999));
        return c != 0 ? c : b.priority.compareTo(a.priority);
      });

    final groups = <String, List<StudyTask>>{};
    for (final t in tasks) {
      final due = t.dueAt;
      final String g;
      if (_showDone) {
        g = 'Completed';
      } else if (due == null) {
        g = 'No deadline';
      } else if (due.isBefore(now)) {
        g = 'Overdue';
      } else if (due.difference(dayOf(now)).inDays < 7) {
        g = 'This week';
      } else {
        g = 'Later';
      }
      groups.putIfAbsent(g, () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & deadlines'),
        actions: [
          if (state.aiAvailable)
            IconButton(tooltip: 'Add with AI', icon: const Icon(Icons.auto_awesome), onPressed: _quickAddWithAi),
          const SettingsButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAdaptiveSheet<void>(
            context, state.data.subjects.isEmpty ? const SubjectEditorSheet() : const TaskEditorSheet()),
        icon: const Icon(Icons.add),
        label: Text(state.data.subjects.isEmpty ? 'Subject' : 'Task'),
      ),
      body: PageBody(children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('To do'), icon: Icon(Icons.radio_button_unchecked)),
            ButtonSegment(value: true, label: Text('Done'), icon: Icon(Icons.check_circle_outline)),
          ],
          selected: {_showDone},
          onSelectionChanged: (s) => setState(() => _showDone = s.first),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: const Text('All subjects'),
                selected: _subjectFilter == null,
                onSelected: (_) => setState(() => _subjectFilter = null),
              ),
            ),
            for (final s in state.data.subjects)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: SubjectDot(color: s.color),
                  label: Text(s.name),
                  selected: _subjectFilter == s.id,
                  onSelected: (v) => setState(() => _subjectFilter = v ? s.id : null),
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Subjects'),
              onPressed: () => showAdaptiveSheet<void>(context, const SubjectsSheet()),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          EmptyState(
            icon: _showDone ? Icons.inventory_2_outlined : Icons.task_alt,
            title: _showDone ? 'No completed tasks yet' : 'All caught up!',
            message: _showDone ? null : 'Add assignments, projects and exams – the planner schedules time for them.',
            action: _showDone
                ? null
                : TextButton(onPressed: () => HomeNav.of(context)?.goTo(1), child: const Text('See your plan')),
          ),
        for (final e in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text('${e.key} · ${e.value.length}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: e.key == 'Overdue' ? Theme.of(context).colorScheme.error : null, fontWeight: FontWeight.w600)),
          ),
          for (final t in e.value) Padding(padding: const EdgeInsets.only(bottom: 8), child: TaskTile(task: t)),
        ],
      ]),
    );
  }
}

/// Manage subjects (list + add/edit).
class SubjectsSheet extends StatelessWidget {
  const SubjectsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SheetScaffold(
      title: 'Subjects',
      actions: [
        FilledButton.icon(
          onPressed: () => showAdaptiveSheet<void>(context, const SubjectEditorSheet()),
          icon: const Icon(Icons.add),
          label: const Text('Add subject'),
        ),
      ],
      children: [
        if (state.data.subjects.isEmpty) const EmptyState(icon: Icons.school_outlined, title: 'No subjects yet'),
        for (final s in state.data.subjects)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(backgroundColor: Color(s.color), child: Text(s.name.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white))),
            title: Text(s.name),
            subtitle: Text('${confidenceLabels[s.proficiency.clamp(1, 5) - 1]} · ${difficultyLabels[s.difficulty.clamp(1, 5) - 1]} · '
                '${fmtMinutes(s.targetMinutesPerWeek)}/week${s.examDate != null ? ' · exam ${s.examDate}' : ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAdaptiveSheet<void>(context, SubjectEditorSheet(subject: s)),
          ),
      ],
    );
  }
}
