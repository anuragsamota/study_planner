import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/planner_data.dart';
import '../../state/app_state.dart';
import '../format.dart';
import '../widgets/common.dart';

const _suggestedSubjects = ['Mathematics', 'Physics', 'Chemistry', 'Biology', 'English', 'History', 'Computer Science', 'Economics'];

/// Availability presets for the preferred time of day.
Map<int, List<TimeWindow>> presetAvailability(String preferred) {
  final weekday = switch (preferred) {
    'morning' => TimeWindow('07:00', '10:00'),
    'afternoon' => TimeWindow('14:00', '18:00'),
    'night' => TimeWindow('20:00', '23:30'),
    _ => TimeWindow('17:00', '21:00'),
  };
  return {
    for (var d = 1; d <= 5; d++) d: [TimeWindow(weekday.start, weekday.end)],
    6: [TimeWindow('10:00', '13:00')],
    7: [TimeWindow('15:00', '18:00')],
  };
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  final _subjectInput = TextEditingController();
  final _subjects = <String, int>{}; // name -> proficiency
  String _preferred = 'evening';
  double _goal = 120;
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    _subjectInput.dispose();
    super.dispose();
  }

  void _go(int page) {
    FocusScope.of(context).unfocus();
    _pages.animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _addSubject(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    setState(() => _subjects.putIfAbsent(n, () => 3));
    _subjectInput.clear();
  }

  Future<void> _finish() async {
    final state = context.read<AppState>();
    await state.mutate((d) {
      d.profile
        ..name = _name.text.trim().isEmpty ? 'Student' : _name.text.trim()
        ..preferredTime = _preferred
        ..dailyGoalMinutes = _goal.round()
        ..availability = presetAvailability(_preferred);
      var i = d.subjects.length;
      for (final e in _subjects.entries) {
        if (d.subjects.any((s) => s.name.toLowerCase() == e.key.toLowerCase())) continue;
        d.subjects.add(Subject(name: e.key, proficiency: e.value, color: subjectPalette[i++ % subjectPalette.length]));
      }
    });
    await state.completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [_welcome(theme), _subjectsStep(theme), _scheduleStep(theme)];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(children: [
                  for (var i = 0; i < steps.length; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i <= _page ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ]),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (p) => setState(() => _page = p),
                  children: [for (final s in steps) SingleChildScrollView(padding: const EdgeInsets.all(24), child: s)],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(children: [
                  if (_page > 0) TextButton(onPressed: () => _go(_page - 1), child: const Text('Back')),
                  const Spacer(),
                  if (_page < steps.length - 1)
                    FilledButton(
                      onPressed: _page == 1 && _subjects.isEmpty ? null : () => _go(_page + 1),
                      child: const Text('Continue'),
                    )
                  else
                    FilledButton.icon(onPressed: _finish, icon: const Icon(Icons.auto_awesome), label: const Text('Create my plan')),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _welcome(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 24),
        Icon(Icons.school, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text('Study smarter, not harder', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(
          'Tell us your subjects and when you can study. We\'ll plan every session around your deadlines and weak '
          'spots, remind you when it\'s time, and show how you\'re improving.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'What should we call you?', prefixIcon: Icon(Icons.person_outline)),
          onSubmitted: (_) => _go(1),
        ),
      ]);

  Widget _subjectsStep(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('What are you studying?', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Add your subjects and how confident you feel. Weaker subjects get more practice.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _subjectInput,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Add a subject',
            suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: () => _addSubject(_subjectInput.text)),
          ),
          onSubmitted: _addSubject,
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in _suggestedSubjects.where((s) => !_subjects.containsKey(s)))
            ActionChip(avatar: const Icon(Icons.add, size: 16), label: Text(s), onPressed: () => _addSubject(s)),
        ]),
        const SizedBox(height: 16),
        for (final e in _subjects.entries)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(children: [
                Expanded(child: Text(e.key, style: theme.textTheme.titleSmall)),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 2, icon: Icon(Icons.sentiment_dissatisfied), tooltip: 'Weak'),
                    ButtonSegment(value: 3, icon: Icon(Icons.sentiment_neutral), tooltip: 'Okay'),
                    ButtonSegment(value: 4, icon: Icon(Icons.sentiment_very_satisfied), tooltip: 'Strong'),
                  ],
                  selected: {e.value},
                  onSelectionChanged: (v) => setState(() => _subjects[e.key] = v.first),
                ),
                IconButton(tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: () => setState(() => _subjects.remove(e.key))),
              ]),
            ),
          ),
      ]);

  Widget _scheduleStep(ThemeData theme) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('When do you like to study?', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('You can fine-tune exact times for each day later in Settings.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        for (final (v, label, icon) in studyPeriods)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: _preferred == v ? theme.colorScheme.primaryContainer : null,
            child: ListTile(
              leading: Icon(icon),
              title: Text(label),
              subtitle: Text('Weekdays ${presetAvailability(v)[1]!.single.start}–${presetAvailability(v)[1]!.single.end}'
                  ' · weekends 10–13 & 15–18'),
              trailing: _preferred == v ? const Icon(Icons.check_circle) : null,
              onTap: () => setState(() => _preferred = v),
            ),
          ),
        const SizedBox(height: 16),
        LabeledSlider(
          label: 'Daily study goal',
          value: _goal,
          min: 30,
          max: 360,
          divisions: 22,
          display: (v) => fmtMinutes(v.round()),
          onChanged: (v) => setState(() => _goal = v),
        ),
      ]);
}
