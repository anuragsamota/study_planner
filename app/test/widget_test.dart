import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:study_planner/models/planner_data.dart';
import 'package:study_planner/models/settings.dart';
import 'package:study_planner/services/reminders.dart';
import 'package:study_planner/services/storage.dart';
import 'package:study_planner/state/app_state.dart';
import 'package:study_planner/ui/app.dart';

class FakeReminders extends ReminderService {
  int rescheduled = 0;
  @override
  Future<void> init() async {}
  @override
  Future<void> requestPermission() async {}
  @override
  Future<void> reschedule(PlannerData data, ReminderSettings settings) async => rescheduled++;
}

Future<AppState> makeState({bool onboarded = false}) async {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  final storage = await Storage.open();
  final state = AppState(storage, FakeReminders(), clock: () => DateTime(2026, 10, 5, 8));
  state.settings.ai.enabled = false; // no network in tests
  state.settings.onboarded = onboarded;
  return state;
}

Future<void> pumpApp(WidgetTester tester, AppState state, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: state, child: const StudyPlannerApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('onboarding creates subjects and a plan', (tester) async {
    final state = await makeState();
    await tester.runAsync(state.start);
    await pumpApp(tester, state, const Size(400, 860));

    expect(find.text('Study smarter, not harder'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ada Lovelace');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathematics'));
    await tester.tap(find.text('Physics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning'));
    await tester.tap(find.text('Create my plan'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(state.settings.onboarded, isTrue);
    expect(state.data.subjects.map((s) => s.name), ['Mathematics', 'Physics']);
    expect(state.data.profile.availability[1]!.single.start, '07:00');
    expect(state.data.sessions, isNotEmpty);
    expect(find.textContaining('Good morning, Ada'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    state.dispose();
  });

  for (final (name, size, nav) in [
    ('phone', const Size(390, 844), NavigationBar),
    ('tablet', const Size(900, 1100), NavigationRail),
    ('desktop', const Size(1440, 900), NavigationRail),
  ]) {
    testWidgets('all tabs render without overflow on $name', (tester) async {
      final state = await makeState(onboarded: true);
      state.data.subjects.addAll([Subject(name: 'Maths', proficiency: 2), Subject(name: 'History', proficiency: 5)]);
      state.data.tasks.add(StudyTask(subjectId: state.data.subjects.first.id, title: 'Problem set', due: '2026-10-07', priority: 3));
      await tester.runAsync(state.start);
      await pumpApp(tester, state, size);
      expect(find.byType(nav), findsOneWidget);

      for (final tab in ['Plan', 'Tasks', 'Insights', 'Coach', 'Today']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab on $name');
      }
      expect(find.text('Problem set'), findsWidgets);
      await tester.tap(find.byTooltip('Settings').first);
      await tester.pumpAndSettle();
      expect(find.text('When can you study?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      state.dispose();
    });
  }

  testWidgets('finishing a session from the plan updates analytics', (tester) async {
    final state = await makeState(onboarded: true);
    state.data.subjects.add(Subject(id: 'm', name: 'Maths'));
    await tester.runAsync(state.start);
    await pumpApp(tester, state, const Size(430, 900));

    final first = state.data.sessions.first;
    await tester.runAsync(() => state.completeSession(first, minutes: 40, focus: 4));
    await tester.pumpAndSettle();
    expect(state.summary.todayMinutes, 40);
    expect(find.textContaining('40m of 2h today'), findsOneWidget);
    state.dispose();
  });
}
