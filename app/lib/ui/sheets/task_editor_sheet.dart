import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/task_tile.dart';
import 'subject_editor_sheet.dart';

/// Create or edit a task. Pass [task] to edit (or to pre-fill from AI parsing
/// with [isNew] = true).
class TaskEditorSheet extends StatefulWidget {
  const TaskEditorSheet({super.key, this.task, this.isNew = false});
  final StudyTask? task;
  final bool isNew;

  @override
  State<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  String? _subjectId;
  TaskType _type = TaskType.assignment;
  DateTime? _due;
  bool _hasTime = false;
  int _priority = 2;
  double _estimate = 60;
  final _formKey = GlobalKey<FormState>();

  bool get _editing => widget.task != null && !widget.isNew;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final state = context.read<AppState>();
    _title = TextEditingController(text: t?.title ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _subjectId = t?.subjectId ?? state.data.subjects.firstOrNull?.id;
    if (state.data.subjectById(_subjectId) == null) _subjectId = state.data.subjects.firstOrNull?.id;
    if (t != null) {
      _type = t.type;
      _due = t.dueAt;
      _hasTime = t.due != null && t.due!.length > 10;
      _priority = t.priority;
      _estimate = t.estimatedMinutes.toDouble().clamp(15, 1200);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    setState(() => _due = DateTime(date.year, date.month, date.day, _hasTime ? (_due?.hour ?? 23) : 23, _hasTime ? (_due?.minute ?? 59) : 59));
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_due ?? DateTime.now()));
    if (time == null || !mounted) return;
    final d = _due ?? DateTime.now();
    setState(() {
      _hasTime = true;
      _due = DateTime(d.year, d.month, d.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final t = (_editing ? widget.task! : (widget.task ?? StudyTask(subjectId: _subjectId, title: '')))
      ..title = _title.text.trim()
      ..subjectId = _subjectId
      ..type = _type
      ..due = _due == null ? null : (_hasTime ? isoLocal(_due!) : isoDate(_due!))
      ..priority = _priority
      ..estimatedMinutes = _estimate.round()
      ..notes = _notes.text.trim();
    await state.upsertTask(t);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final subjects = state.data.subjects;
    return Form(
      key: _formKey,
      child: SheetScaffold(
        title: _editing ? 'Edit task' : 'New task',
        actions: [
          if (_editing)
            TextButton.icon(
              onPressed: () async {
                await state.deleteTask(widget.task!);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: subjects.isEmpty ? null : _save, child: const Text('Save')),
        ],
        children: [
          if (subjects.isEmpty)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                title: const Text('Add a subject first'),
                trailing: const Icon(Icons.add),
                onTap: () => showAdaptiveSheet<void>(context, const SubjectEditorSheet()),
              ),
            ),
          TextFormField(
            controller: _title,
            autofocus: !_editing && widget.task == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What do you need to do?', hintText: 'e.g. Chemistry lab report'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a title' : null,
          ),
          const SizedBox(height: 12),
          if (subjects.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _subjectId,
              decoration: const InputDecoration(labelText: 'Subject'),
              items: [
                for (final s in subjects)
                  DropdownMenuItem(
                    value: s.id,
                    child: Row(children: [SubjectDot(color: s.color), const SizedBox(width: 8), Text(s.name)]),
                  ),
              ],
              onChanged: (v) => setState(() => _subjectId = v),
            ),
          const SizedBox(height: 16),
          Text('Type', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in TaskType.values)
              ChoiceChip(
                avatar: Icon(taskTypeIcon(t), size: 18),
                label: Text(capitalize(t.name)),
                selected: _type == t,
                onSelected: (_) => setState(() => _type = t),
              ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDue,
                icon: const Icon(Icons.event),
                label: Text(_due == null ? 'Add due date' : DateFormat.yMMMEd().format(_due!)),
              ),
            ),
            const SizedBox(width: 8),
            if (_due != null) ...[
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text(_hasTime ? fmtTime(_due!) : 'Time'),
              ),
              IconButton(
                tooltip: 'Remove due date',
                onPressed: () => setState(() {
                  _due = null;
                  _hasTime = false;
                }),
                icon: const Icon(Icons.close),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          Text('Priority', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: [for (final e in priorityLabels.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 12),
          LabeledSlider(
            label: 'How long will it take?',
            value: _estimate,
            min: 15,
            max: 1200,
            divisions: 79,
            display: (v) => fmtMinutes(v.round()),
            onChanged: (v) => setState(() => _estimate = v),
          ),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 8),
          Text('Your study plan will automatically make time for this before it\'s due.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
