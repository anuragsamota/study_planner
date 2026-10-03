import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/planner_data.dart';
import '../models/settings.dart';

/// Local persistence (works on every platform, including web).
class Storage {
  Storage(this._prefs);

  static const _dataKey = 'planner_data_v1';
  static const _settingsKey = 'app_settings_v1';

  final SharedPreferencesWithCache _prefs;

  static Future<Storage> open() async => Storage(await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {_dataKey, _settingsKey}),
      ));

  PlannerData loadData() {
    final raw = _prefs.getString(_dataKey);
    if (raw == null) return PlannerData();
    try {
      return PlannerData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return PlannerData();
    }
  }

  Future<void> saveData(PlannerData data) => _prefs.setString(_dataKey, jsonEncode(data.toJson()));

  AppSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) => _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));

  Future<void> clear() async {
    await _prefs.remove(_dataKey);
    await _prefs.remove(_settingsKey);
  }
}
