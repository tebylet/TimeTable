import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/models/group.dart';
import 'package:ymtimetable/models/lesson_update.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/models/schedule_entry.dart';

ScheduleEntry entry(int id, String start, String end) => ScheduleEntry(
    id: id,
    groupId: 1,
    dayOfWeek: 1,
    period: 1,
    startTime: '09:00',
    endTime: '10:20',
    subject: 'Physics $id',
    startDate: DateTime.parse(start),
    endDate: DateTime.parse(end),
    sourceWeekStart: DateTime.parse(start));

ScheduleData snapshot(List<ScheduleEntry> entries,
        {List<LessonUpdate> updates = const []}) =>
    ScheduleData(
        version: 1,
        semesterStartDate: '2026-09-01',
        groups: [Group(id: 1, name: 'Group')],
        entries: entries,
        cancelledLessons: [],
        messages: [],
        lessonUpdates: updates,
        fetchedAt: DateTime(2026, 11, 2));

void main() {
  test(
      'repeated timeline survives offline serialization and stops at the semester boundary',
      () {
    final data = ScheduleData.decode(snapshot([
      entry(1, '2026-11-02', '2027-01-04'),
    ]).encode());
    expect(data.entries.single.sourceWeekStart, DateTime(2026, 11, 2));
    expect(data.entriesOnDate(DateTime(2026, 11, 9), groupId: 1).single.id, 1);
    expect(data.entriesOnDate(DateTime(2026, 11, 23), groupId: 1).single.id, 1);
    expect(data.entriesOnDate(DateTime(2027, 1, 4), groupId: 1), isEmpty);
    expect(data.entriesOnDate(DateTime(2027, 2, 15), groupId: 1), isEmpty);
    expect(data.entriesOnDate(DateTime(2026, 10, 26), groupId: 1), isEmpty);
  });
  test(
      'new published week replaces the repeated template without duplicate sessions',
      () {
    final data = snapshot([
      entry(1, '2026-11-02', '2026-11-16'),
      entry(2, '2026-11-16', '2027-01-04')
    ]);
    expect(
        data.entriesOnDate(DateTime(2026, 11, 9), groupId: 1).map((e) => e.id),
        [1]);
    expect(
        data.entriesOnDate(DateTime(2026, 11, 16), groupId: 1).map((e) => e.id),
        [2]);
    expect(
        data.entriesOnDate(DateTime(2026, 11, 23), groupId: 1).map((e) => e.id),
        [2]);
  });
  test(
      'a reschedule changes only one repeated occurrence and retains its source context',
      () {
    final data = snapshot([
      entry(1, '2026-11-02', '2027-01-04')
    ], updates: [
      LessonUpdate.fromJson({
        'entryId': 1,
        'date': '2026-11-09',
        'kind': 'rescheduled',
        'newDate': '2026-11-10',
        'startTime': '11:00',
        'endTime': '12:20'
      }),
    ]);
    expect(data.entriesOnDate(DateTime(2026, 11, 9), groupId: 1), isEmpty);
    final moved = data.entriesOnDate(DateTime(2026, 11, 10), groupId: 1).single;
    expect(moved.originalDate, '2026-11-09');
    expect(moved.sourceWeekStart, DateTime(2026, 11, 2));
    expect(
        data.entriesOnDate(DateTime(2026, 11, 16), groupId: 1).single.startTime,
        '09:00');
  });
}
