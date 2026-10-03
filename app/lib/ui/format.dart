import 'package:intl/intl.dart';

String fmtMinutes(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String fmtTime(DateTime t) => DateFormat.jm().format(t);

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

String fmtDay(DateTime d, {DateTime? now}) {
  final today = dayOf(now ?? DateTime.now());
  final diff = dayOf(d).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat.EEEE().format(d);
  return DateFormat.MMMEd().format(d);
}

/// "in 3 days", "today 23:59", "2 days overdue".
String fmtDue(DateTime due, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (due.isBefore(n)) {
    final days = dayOf(n).difference(dayOf(due)).inDays;
    return days == 0 ? 'Overdue' : '$days ${days == 1 ? 'day' : 'days'} overdue';
  }
  final days = dayOf(due).difference(dayOf(n)).inDays;
  final time = due.hour == 23 && due.minute == 59 ? '' : ' ${fmtTime(due)}';
  if (days == 0) return 'Due today$time';
  if (days == 1) return 'Due tomorrow$time';
  if (days < 7) return 'Due ${DateFormat.EEEE().format(due)}';
  return 'Due ${DateFormat.MMMd().format(due)}';
}

String greeting(DateTime now) {
  final h = now.hour;
  if (h < 5) return 'Burning the midnight oil';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
