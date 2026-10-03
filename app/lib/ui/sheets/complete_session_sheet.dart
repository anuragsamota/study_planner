import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../widgets/common.dart';

const focusLabels = ['Very distracted', 'Distracted', 'Okay', 'Focused', 'In the zone'];
const focusIcons = [
  Icons.sentiment_very_dissatisfied,
  Icons.sentiment_dissatisfied,
  Icons.sentiment_neutral,
  Icons.sentiment_satisfied,
  Icons.sentiment_very_satisfied,
];

class FocusRating extends StatelessWidget {
  const FocusRating({super.key, required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('How focused were you?', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 1; i <= 5; i++)
          Tooltip(
            message: focusLabels[i - 1],
            child: ChoiceChip(
              label: Icon(focusIcons[i - 1], size: 26),
              selected: value == i,
              onSelected: (_) => onChanged(i),
            ),
          ),
      ]),
      if (value != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Center(child: Text(focusLabels[value! - 1], style: Theme.of(context).textTheme.bodySmall)),
        ),
    ]);
  }
}

class CompleteSessionSheet extends StatefulWidget {
  const CompleteSessionSheet({super.key, required this.session, required this.minutes});
  final StudySession session;
  final int minutes;

  @override
  State<CompleteSessionSheet> createState() => _CompleteSessionSheetState();
}

class _CompleteSessionSheetState extends State<CompleteSessionSheet> {
  late double _minutes = widget.minutes.clamp(1, 300).toDouble();
  int? _focus;
  bool _taskDone = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final task = state.data.taskById(widget.session.taskId);
    return SheetScaffold(
      title: 'Nice work!',
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await state.completeSession(widget.session, minutes: _minutes.round(), focus: _focus, taskDone: _taskDone);
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Save'),
        ),
      ],
      children: [
        Text(widget.session.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        LabeledSlider(
          label: 'Time studied',
          value: _minutes,
          min: 1,
          max: 300,
          divisions: 299,
          display: (v) => fmtMinutes(v.round()),
          onChanged: (v) => setState(() => _minutes = v),
        ),
        FocusRating(value: _focus, onChanged: (v) => setState(() => _focus = v)),
        if (task != null && !task.isDone) ...[
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _taskDone,
            onChanged: (v) => setState(() => _taskDone = v ?? false),
            title: Text('"${task.title}" is finished'),
            subtitle: Text('${fmtMinutes(task.completedMinutes + _minutes.round())} of ${fmtMinutes(task.estimatedMinutes)} done'),
          ),
        ],
      ],
    );
  }
}
