import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../widgets/common.dart';
import 'complete_session_sheet.dart';

Widget _subjectDropdown(List<Subject> subjects, String? value, ValueChanged<String?> onChanged) =>
    DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Subject'),
      items: [
        for (final s in subjects)
          DropdownMenuItem(value: s.id, child: Row(children: [SubjectDot(color: s.color), const SizedBox(width: 8), Text(s.name)])),
      ],
      onChanged: onChanged,
    );

Widget _taskDropdown(List<StudyTask> tasks, String? value, ValueChanged<String?> onChanged) =>
    DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Task (optional)'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('General study')),
        for (final t in tasks) DropdownMenuItem<String?>(value: t.id, child: Text(t.title, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );

/// Schedule a session by hand (the auto-planner works around it).
class AddSessionSheet extends StatefulWidget {
  const AddSessionSheet({super.key, required this.day});
  final DateTime day;

  @override
  State<AddSessionSheet> createState() => _AddSessionSheetState();
}

class _AddSessionSheetState extends State<AddSessionSheet> {
  String? _subjectId;
  String? _taskId;
  late DateTime _date = widget.day;
  TimeOfDay _time = const TimeOfDay(hour: 17, minute: 0);
  double _minutes = 45;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _subjectId = state.data.subjects.firstOrNull?.id;
    _minutes = state.data.profile.sessionMinutes.toDouble().clamp(15, 240);
    final now = state.now;
    if (isoDate(_date) == isoDate(now)) _time = TimeOfDay(hour: (now.hour + 1).clamp(0, 23), minute: 0);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = state.data.tasks.where((t) => !t.isDone && t.subjectId == _subjectId).toList();
    return SheetScaffold(
      title: 'Schedule a session',
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _subjectId == null
              ? null
              : () async {
                  final start = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
                  final subject = state.data.subjectById(_subjectId)!;
                  await state.addManualSession(StudySession(
                    subjectId: _subjectId,
                    taskId: _taskId,
                    title: state.data.taskById(_taskId)?.title ?? '${subject.name} study',
                    start: isoLocal(start),
                    durationMinutes: _minutes.round(),
                    source: SessionSource.manual,
                  ));
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Add'),
        ),
      ],
      children: [
        _subjectDropdown(state.data.subjects, _subjectId, (v) => setState(() {
              _subjectId = v;
              _taskId = null;
            })),
        const SizedBox(height: 12),
        _taskDropdown(tasks, _taskId, (v) => setState(() => _taskId = v)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(DateFormat.MMMEd().format(_date)),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(_time.format(context)),
              onPressed: () async {
                final t = await showTimePicker(context: context, initialTime: _time);
                if (t != null) setState(() => _time = t);
              },
            ),
          ),
        ]),
        const SizedBox(height: 12),
        LabeledSlider(
          label: 'Duration',
          value: _minutes,
          min: 15,
          max: 240,
          divisions: 15,
          display: (v) => fmtMinutes(v.round()),
          onChanged: (v) => setState(() => _minutes = v),
        ),
      ],
    );
  }
}

/// Record study done outside the plan.
class LogStudySheet extends StatefulWidget {
  const LogStudySheet({super.key});
  @override
  State<LogStudySheet> createState() => _LogStudySheetState();
}

class _LogStudySheetState extends State<LogStudySheet> {
  String? _subjectId;
  String? _taskId;
  double _minutes = 30;
  int? _focus;

  @override
  void initState() {
    super.initState();
    _subjectId = context.read<AppState>().data.subjects.firstOrNull?.id;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = state.data.tasks.where((t) => !t.isDone && t.subjectId == _subjectId).toList();
    return SheetScaffold(
      title: 'Log study time',
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _subjectId == null
              ? null
              : () async {
                  await state.logStudy(subjectId: _subjectId!, minutes: _minutes.round(), focus: _focus, taskId: _taskId);
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('Save'),
        ),
      ],
      children: [
        _subjectDropdown(state.data.subjects, _subjectId, (v) => setState(() {
              _subjectId = v;
              _taskId = null;
            })),
        const SizedBox(height: 12),
        _taskDropdown(tasks, _taskId, (v) => setState(() => _taskId = v)),
        const SizedBox(height: 12),
        LabeledSlider(
          label: 'Time studied',
          value: _minutes,
          min: 5,
          max: 300,
          divisions: 59,
          display: (v) => fmtMinutes(v.round()),
          onChanged: (v) => setState(() => _minutes = v),
        ),
        FocusRating(value: _focus, onChanged: (v) => setState(() => _focus = v)),
      ],
    );
  }
}

/// Record a test / quiz / assignment grade.
class ScoreSheet extends StatefulWidget {
  const ScoreSheet({super.key, this.subjectId});
  final String? subjectId;
  @override
  State<ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends State<ScoreSheet> {
  String? _subjectId;
  final _title = TextEditingController(text: 'Quiz');
  final _score = TextEditingController();
  final _max = TextEditingController(text: '100');
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _subjectId = widget.subjectId ?? context.read<AppState>().data.subjects.firstOrNull?.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _score.dispose();
    _max.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    String? number(String? v) => double.tryParse((v ?? '').replaceAll(',', '.')) == null ? 'Enter a number' : null;
    return Form(
      key: _formKey,
      child: SheetScaffold(
        title: 'Add a result',
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (_subjectId == null || !_formKey.currentState!.validate()) return;
              final max = double.parse(_max.text.replaceAll(',', '.'));
              final score = double.parse(_score.text.replaceAll(',', '.')).clamp(0, max).toDouble();
              await state.addScore(Score(subjectId: _subjectId!, title: _title.text.trim(), score: score, maxScore: max));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
        children: [
          _subjectDropdown(state.data.subjects, _subjectId, (v) => setState(() => _subjectId = v)),
          const SizedBox(height: 12),
          TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Test / assignment name')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _score,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Score'),
                validator: number,
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('out of')),
            Expanded(
              child: TextFormField(
                controller: _max,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Max'),
                validator: (v) => number(v) ?? ((double.tryParse(v!) ?? 0) <= 0 ? 'Must be > 0' : null),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Results help the app find your strong and weak areas.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
