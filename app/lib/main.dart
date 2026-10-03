import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/reminders.dart';
import 'services/storage.dart';
import 'state/app_state.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  final reminders = ReminderService();
  await reminders.init();
  final state = AppState(storage, reminders);
  await state.start();
  runApp(ChangeNotifierProvider.value(value: state, child: const StudyPlannerApp()));
}
