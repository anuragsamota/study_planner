// Reminders for study sessions, deadlines and a daily digest.
//
// * Android, iOS, macOS, Windows: OS-scheduled notifications (fire even when
//   the app is closed).
// * Web and Linux can't schedule notifications, so an in-app ticker fires them
//   while the app is open (system notification + in-app banner).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/planner_data.dart';
import '../models/settings.dart';

class Reminder {
  Reminder(this.key, this.at, this.title, this.body);
  final String key;
  final DateTime at;
  final String title;
  final String body;
  int get id => key.hashCode & 0x7fffffff;
}

/// Pure function: which reminders should exist for [data] (soonest first).
List<Reminder> buildReminders(PlannerData data, ReminderSettings settings, DateTime now,
    {int horizonDays = 7, int limit = 60}) {
  if (!settings.enabled) return [];
  final horizon = now.add(Duration(days: horizonDays));
  final out = <Reminder>[];

  for (final s in data.sessions) {
    if (s.status != SessionStatus.planned) continue;
    final at = s.startAt.subtract(Duration(minutes: settings.minutesBefore));
    if (at.isBefore(now) || at.isAfter(horizon)) continue;
    final subject = data.subjectById(s.subjectId)?.name;
    final when = settings.minutesBefore == 0 ? 'now' : 'in ${settings.minutesBefore} min';
    out.add(Reminder('session:${s.id}', at, 'Study $when: ${s.title}',
        '${subject ?? 'Study'} · ${s.durationMinutes} min${s.notes.isNotEmpty ? ' · ${s.notes}' : ''}'));
  }

  if (settings.deadlineReminders) {
    for (final t in data.tasks) {
      final due = t.dueAt;
      if (t.isDone || due == null) continue;
      final subject = data.subjectById(t.subjectId)?.name ?? '';
      for (final (offset, label) in [(const Duration(days: 1), 'tomorrow'), (const Duration(hours: 3), 'in 3 hours')]) {
        final at = due.subtract(offset);
        if (at.isBefore(now) || at.isAfter(horizon)) continue;
        out.add(Reminder('due:${t.id}:${offset.inHours}', at, 'Due $label: ${t.title}',
            '$subject · ${t.remainingMinutes} min of work left'));
      }
    }
  }

  if (settings.dailyDigest) {
    final parts = settings.digestTime.split(':');
    for (var d = 0; d < horizonDays; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      final at = DateTime(day.year, day.month, day.day, int.parse(parts[0]), int.parse(parts.length > 1 ? parts[1] : '0'));
      if (at.isBefore(now)) continue;
      final sessions = data.sessions
          .where((s) => s.status == SessionStatus.planned && isoDate(s.startAt) == isoDate(day))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      if (sessions.isEmpty) continue;
      final minutes = sessions.fold<int>(0, (a, s) => a + s.durationMinutes);
      out.add(Reminder('digest:${isoDate(day)}', at, "Today's plan: ${sessions.length} sessions, $minutes min",
          sessions.take(4).map((s) => '${_hhmm(s.startAt)} ${s.title}').join(' · ')));
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(limit).toList(); // iOS allows at most 64 pending notifications
}

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _inApp = StreamController<Reminder>.broadcast();
  final _fired = <String>{};
  List<Reminder> _pending = [];
  Timer? _ticker;
  bool _ready = false;

  /// Reminders fired while the app is open (shown as an in-app banner).
  Stream<Reminder> get inAppReminders => _inApp.stream;

  bool get canSchedule =>
      !kIsWeb &&
      const {TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.windows}
          .contains(defaultTargetPlatform);

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        // Unknown zone name: keep UTC; we schedule with absolute instants anyway.
      }
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Open Study Planner'),
          windows: WindowsInitializationSettings(
            appName: 'Study Planner',
            appUserModelId: 'dev.studyplanner.app',
            guid: '6f1d3c3e-7c0e-4b8f-9a8e-2f6b7d1c9a41',
          ),
          web: WebInitializationSettings(),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      if (kIsWeb) return; // the browser asks when the first notification is shown
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission();
        case TargetPlatform.iOS:
          await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true);
        case TargetPlatform.macOS:
          await _plugin
              .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true);
        default:
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails('study_reminders', 'Study reminders',
        channelDescription: 'Upcoming study sessions, deadlines and daily plan',
        importance: Importance.high,
        priority: Priority.high),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  /// Replace all scheduled reminders with the ones derived from [data].
  Future<void> reschedule(PlannerData data, ReminderSettings settings) async {
    final now = DateTime.now();
    _pending = buildReminders(data, settings, now);
    if (!_ready || !canSchedule) return;
    try {
      await _plugin.cancelAll();
      for (final r in _pending) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Scheduling reminders failed: $e');
    }
  }

  Future<void> _tick() async {
    final now = DateTime.now();
    for (final r in _pending) {
      if (r.at.isAfter(now) || _fired.contains(r.key)) continue;
      _fired.add(r.key);
      if (now.difference(r.at) > const Duration(minutes: 10)) continue; // stale
      if (!canSchedule) {
        _inApp.add(r);
        if (_ready) {
          try {
            await _plugin.show(id: r.id, title: r.title, body: r.body, notificationDetails: _details);
          } catch (_) {}
        }
      }
    }
  }

  /// Fire a test notification right away.
  Future<void> showTest() async {
    final r = Reminder('test', DateTime.now(), 'Reminders are working', 'You will be reminded before each session.');
    _inApp.add(r);
    if (_ready) {
      try {
        await _plugin.show(id: r.id, title: r.title, body: r.body, notificationDetails: _details);
      } catch (_) {}
    }
  }

  void dispose() {
    _ticker?.cancel();
    _inApp.close();
  }
}
