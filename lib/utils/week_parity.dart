import '../models/schedule_entry.dart';

DateTime _startOfWeek(DateTime date) {
  // Calendar weeks must stay seven days long across local DST changes.
  final d = DateTime.utc(date.year, date.month, date.day);
  final daysFromMonday = (d.weekday - DateTime.monday) % 7;
  return d.subtract(Duration(days: daysFromMonday));
}

/// Зеркало алгоритма расчёта чётности недели с сервера
/// (server/src/utils/week.js) — неделя с датой начала семестра считается 1-й
/// (нечётной).
WeekParity weekParityOn(String? semesterStartDate, DateTime onDate) {
  if (semesterStartDate == null) return WeekParity.all;
  final start = DateTime.tryParse(semesterStartDate);
  if (start == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(semesterStartDate) ||
      start.toIso8601String().substring(0, 10) != semesterStartDate) {
    return WeekParity.all;
  }

  final startWeek = _startOfWeek(start);
  final targetWeek = _startOfWeek(onDate);
  final diffWeeks = targetWeek.difference(startWeek).inDays ~/ 7;
  final weekNumber = diffWeeks + 1; // 1-based
  return weekNumber % 2 == 1 ? WeekParity.odd : WeekParity.even;
}

/// Понедельник = 1 ... суббота = 6, воскресенье не используется в расписании.
int dartWeekdayToScheduleDay(int dartWeekday) =>
    dartWeekday; // DateTime.monday == 1

// Названия дней недели/месяцев теперь локализуются через Strings
// (см. lib/localization.dart) — Strings.dayShort/dayFull/monthShort.
