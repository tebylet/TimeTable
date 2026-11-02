import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/models/app_message.dart';
import 'package:ymtimetable/models/cancelled_lesson.dart';
import 'package:ymtimetable/models/group.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/models/schedule_entry.dart';
import 'package:ymtimetable/utils/week_parity.dart';

ScheduleEntry entry(int id, int groupId, int day, int period,
        {int? teacherId, WeekParity parity = WeekParity.all}) =>
    ScheduleEntry(
      id: id,
      groupId: groupId,
      dayOfWeek: day,
      period: period,
      startTime: '09:00',
      endTime: '10:20',
      subject: 'Subject $id',
      teacherId: teacherId,
      weekParity: parity,
    );

AppMessage message(int id, int? groupId,
        {String timestamp = '2026-10-24 10:00:00'}) =>
    AppMessage.fromJson({
      'id': id,
      'senderName': 'Teacher',
      'senderUserId': null,
      'targetGroupId': groupId,
      'body': 'Message $id',
      'createdAt': timestamp,
    });

void main() {
  test('snapshot indexes are sorted and isolated from mutable source lists',
      () {
    final source = [
      entry(1, 10, 2, 2, teacherId: 7),
      entry(2, 20, 1, 1, teacherId: 7),
      entry(3, 10, 1, 2, teacherId: 8, parity: WeekParity.odd),
      entry(4, 10, 1, 2, teacherId: 7, parity: WeekParity.even),
      entry(5, 20, 1, 2),
    ];
    final cancellation = CancelledLesson(entryId: 1, date: '2026-10-24');
    final snapshot = ScheduleData(
      version: 1,
      serverId: 'school-a',
      semesterStartDate: '2026-09-01',
      groups: [Group(id: 10, name: 'A'), Group(id: 20, name: 'B')],
      entries: source,
      cancelledLessons: [cancellation],
      messages: [message(1, null), message(2, 10), message(3, 20)],
      fetchedAt: DateTime.utc(2026, 10, 24),
    );
    source.clear();

    expect(snapshot.entriesForGroup(10).map((e) => e.id), [3, 4, 1]);
    expect(snapshot.entriesForTeacher(7).map((e) => e.id), [2, 4, 1]);
    expect(snapshot.entriesForGroupOnDay(10, 1).map((e) => e.id), [3, 4]);
    expect(snapshot.entriesForTeacherOnDay(7, 1).map((e) => e.id), [2, 4]);
    expect(snapshot.entriesForGroup(99), isEmpty);
    expect(snapshot.entriesForTeacherOnDay(99, 1), isEmpty);
    expect(snapshot.groupIdsForTeacher(7), {10, 20});
    expect(snapshot.groupById(10)?.name, 'A');
    expect(snapshot.groupById(null), isNull);
    expect(
        snapshot.hasSubgroupSplit(snapshot.entriesForGroup(10).first), isTrue);
    expect(
        snapshot.hasSubgroupSplit(snapshot.entriesForGroup(20).first), isFalse);
    expect(snapshot.cancelledLessonsOn(DateTime(2026, 10, 24))[1],
        same(cancellation));
    expect(snapshot.cancelledLessonsOn(DateTime(2026, 10, 25)), isEmpty);
    expect(snapshot.messagesForGroup(10).map((m) => m.id), [1, 2]);
    expect(snapshot.messagesForGroup(null).map((m) => m.id), [1]);

    expect(snapshot.entriesForGroup(10), same(snapshot.entriesForGroup(10)));
    expect(snapshot.messagesForGroup(10), same(snapshot.messagesForGroup(10)));
    expect(() => snapshot.entries.clear(), throwsUnsupportedError);
    expect(() => snapshot.entriesForGroup(10).clear(), throwsUnsupportedError);
    expect(
        () => snapshot.groupIdsForTeacher(7).clear(), throwsUnsupportedError);
    expect(() => snapshot.cancelledLessonsOn(DateTime(2026, 10, 24)).clear(),
        throwsUnsupportedError);
    expect(() => snapshot.messagesForGroup(10).clear(), throwsUnsupportedError);

    final restored = ScheduleData.decode(snapshot.encode());
    expect(restored.serverId, 'school-a');
    expect(restored.entriesForTeacher(7).map((e) => e.id), [2, 4, 1]);
    expect(restored.messages.first.createdAt, DateTime.utc(2026, 10, 24, 10));
    expect(ScheduleData.fromJson({'version': 1}).serverId, isNull);
  });

  test('legacy UTC timestamps and explicit offsets refer to the same instant',
      () {
    final expected = DateTime.utc(2026, 10, 24, 10);
    for (final timestamp in [
      '2026-10-24 10:00:00',
      '2026-10-24T10:00:00',
      '2026-10-24T10:00:00Z',
      '2026-10-24T13:00:00+03:00',
      '2026-10-24T07:00:00-0300',
    ]) {
      final parsed = message(1, null, timestamp: timestamp);
      expect(parsed.createdAt, expected);
      expect(parsed.createdAt.isUtc, isTrue);
      expect(parsed.toJson()['createdAt'], '2026-10-24T10:00:00.000Z');
      expect(AppMessage.fromJson(parsed.toJson()).createdAt, expected);
    }
    for (final invalid in [
      '',
      'not-a-time',
      '2026-02-31 10:00:00',
      '2026-10-24T24:00:00Z'
    ]) {
      expect(() => message(1, null, timestamp: invalid), throwsFormatException);
    }
  });

  test('malformed lesson data rejects the snapshot rather than hiding a row',
      () {
    final valid = entry(1, 10, 7, 8).toJson();
    expect(ScheduleEntry.fromJson({...valid, 'dayOfWeek': 7.0}).dayOfWeek, 7);
    final invalidValues = <String, dynamic>{
      'id': 0,
      'groupId': '10',
      'teacherId': 1.5,
      'dayOfWeek': 1.5,
      'period': 'abc',
      'startTime': 'not-a-time',
      'endTime': '99:99',
      'startDate': '2026-02-31',
      'endDate': '2026-99-99',
      'weekParity': 'sometimes',
    };
    for (final field in invalidValues.entries) {
      expect(
          () => ScheduleData.fromJson({
                'entries': [
                  {...valid, field.key: field.value}
                ],
              }),
          throwsFormatException,
          reason: field.key);
    }
    for (final invalid in [
      {...valid, 'dayOfWeek': 8},
      {...valid, 'period': 9},
      {...valid, 'endTime': '08:00'},
      {...valid, 'startDate': '2026-10-24', 'endDate': '2026-10-24'},
    ]) {
      expect(() => ScheduleEntry.fromJson(invalid), throwsFormatException);
    }
  });

  test('calendar parity advances once per week and rejects invalid start dates',
      () {
    expect(weekParityOn('2026-03-23', DateTime(2026, 3, 29, 23, 59)),
        WeekParity.odd);
    expect(weekParityOn('2026-03-23', DateTime(2026, 3, 30)), WeekParity.even);
    expect(weekParityOn('2026-10-26', DateTime(2026, 10, 19)), WeekParity.even);
    expect(weekParityOn('2026-02-31', DateTime(2026, 3, 2)), WeekParity.all);
  });
}
