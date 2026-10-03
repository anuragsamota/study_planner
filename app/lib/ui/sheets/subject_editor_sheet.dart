import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../widgets/common.dart';

const difficultyLabels = ['Very easy', 'Easy', 'Medium', 'Hard', 'Very hard'];
const confidenceLabels = ['Struggling', 'Unsure', 'Okay', 'Good', 'Confident'];

class SubjectEditorSheet extends StatefulWidget {
  const SubjectEditorSheet({super.key, this.subject});
  final Subject? subject;

  @override
  State<SubjectEditorSheet> createState() => _SubjectEditorSheetState();
}

class _SubjectEditorSheetState extends State<SubjectEditorSheet> {
  late final TextEditingController _name;
  late int _color;
  late double _difficulty;
  late double _proficiency;
  late double _weekly;
  DateTime? _exam;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final s = widget.subject;
    final count = context.read<AppState>().data.subjects.length;
    _name = TextEditingController(text: s?.name ?? '');
    _color = s?.color ?? subjectPalette[count % subjectPalette.length];
    _difficulty = (s?.difficulty ?? 3).toDouble();
    _proficiency = (s?.proficiency ?? 3).toDouble();
    _weekly = (s?.targetMinutesPerWeek ?? 120).toDouble().clamp(0, 900);
    _exam = parseLocal(s?.examDate);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final s = (widget.subject ?? Subject(name: ''))
      ..name = _name.text.trim()
      ..color = _color
      ..difficulty = _difficulty.round()
      ..proficiency = _proficiency.round()
      ..targetMinutesPerWeek = _weekly.round()
      ..examDate = _exam == null ? null : isoDate(_exam!);
    await state.upsertSubject(s);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.subject!.name}?'),
        content: const Text('Its tasks and planned sessions will be removed. Completed study history is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await state.deleteSubject(widget.subject!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SheetScaffold(
        title: widget.subject == null ? 'New subject' : 'Edit subject',
        actions: [
          if (widget.subject != null)
            TextButton.icon(onPressed: _delete, icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
          const Spacer(),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
        children: [
          TextFormField(
            controller: _name,
            autofocus: widget.subject == null,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Subject name', hintText: 'e.g. Mathematics'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in subjectPalette)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _color = c),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(c),
                  child: _color == c ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                ),
              ),
          ]),
          const SizedBox(height: 16),
          LabeledSlider(
            label: 'How confident do you feel?',
            value: _proficiency,
            min: 1,
            max: 5,
            divisions: 4,
            display: (v) => confidenceLabels[v.round() - 1],
            onChanged: (v) => setState(() => _proficiency = v),
          ),
          LabeledSlider(
            label: 'How hard is it?',
            value: _difficulty,
            min: 1,
            max: 5,
            divisions: 4,
            display: (v) => difficultyLabels[v.round() - 1],
            onChanged: (v) => setState(() => _difficulty = v),
          ),
          LabeledSlider(
            label: 'Weekly study target',
            value: _weekly,
            min: 0,
            max: 900,
            divisions: 30,
            display: (v) => '${fmtMinutes(v.round())} / week',
            onChanged: (v) => setState(() => _weekly = v),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _exam ?? now.add(const Duration(days: 30)),
                firstDate: now.subtract(const Duration(days: 30)),
                lastDate: now.add(const Duration(days: 730)),
              );
              if (d != null) setState(() => _exam = d);
            },
            icon: const Icon(Icons.school_outlined),
            label: Text(_exam == null ? 'Add exam date (optional)' : 'Exam: ${DateFormat.yMMMEd().format(_exam!)}'),
          ),
          if (_exam != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => setState(() => _exam = null), child: const Text('Remove exam date')),
            ),
          const SizedBox(height: 4),
          Text('Weaker and harder subjects automatically get more study time, and revision ramps up as an exam approaches.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
