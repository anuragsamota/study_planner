import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';

class StudyPlannerApp extends StatelessWidget {
  const StudyPlannerApp({super.key});

  static const seed = Color(0xFF4F6BED);

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      chipTheme: const ChipThemeData(showCheckmark: false),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(extendedPadding: EdgeInsets.symmetric(horizontal: 20)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'Study Planner',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: state.settings.themeMode,
      home: state.settings.onboarded ? const HomeShell() : const OnboardingScreen(),
    );
  }
}
