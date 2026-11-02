import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/localization.dart';
import 'package:ymtimetable/models/app_user.dart';
import 'package:ymtimetable/models/cancelled_lesson.dart';
import 'package:ymtimetable/models/group.dart';
import 'package:ymtimetable/models/lesson_update.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/models/schedule_entry.dart';
import 'package:ymtimetable/screens/schedule_screen.dart';
import 'package:ymtimetable/services/sync_service.dart';
import 'package:ymtimetable/services/update_channel.dart';

ScheduleEntry entry(
        {int id = 1,
        int group = 1,
        int day = 1,
        WeekParity parity = WeekParity.all}) =>
    ScheduleEntry(
        id: id,
        groupId: group,
        dayOfWeek: day,
        period: 1,
        startTime: '09:00',
        endTime: '10:20',
        subject: 'Physics $id',
        groupNameRu: 'Group $group',
        teacherId: 7,
        room: '115',
        weekParity: parity);
ScheduleData snapshot(
        {List<ScheduleEntry>? entries,
        List<LessonUpdate> updates = const [],
        List<CancelledLesson> cancelled = const []}) =>
    ScheduleData(
        version: 3,
        serverId: 'coordinator-test',
        semesterStartDate: '2026-09-01',
        groups: [
          Group(id: 1, name: 'Group 1', facultyId: 1, courseNumber: 1),
          Group(id: 2, name: 'Other course', facultyId: 1, courseNumber: 2),
          Group(id: 3, name: 'Other faculty', facultyId: 2, courseNumber: 1)
        ],
        entries: entries ?? [entry()],
        lessonUpdates: updates,
        cancelledLessons: cancelled,
        messages: [],
        fetchedAt: DateTime.now());
AppUser coordinator() => AppUser(
    id: 9,
    username: 'coordinator',
    role: AppRole.coordinator,
    displayName: 'Coordinator',
    facultyId: 1,
    courseNumber: 1);

class TestCoordinatorController extends ScheduleController {
  Map<String, dynamic>? saved;
  TestCoordinatorController() : super(channel: UpdateChannel.unsupported);
  @override
  Future<void> saveLessonUpdate(
      ScheduleEntry entry, DateTime date, Map<String, dynamic> value) async {
    saved = {
      ...value,
      'entryId': entry.id,
      'date': entry.originalDate ?? ScheduleData.isoDate(date)
    };
  }
}

void main() {
  tearDown(() => Strings.current = AppLocale.ru);
  test(
      'coordinator scope survives login/cache serialization and restricts management',
      () {
    final user = AppUser.fromJson(coordinator().toJson());
    expect(user.role, AppRole.coordinator);
    expect(user.facultyId, 1);
    expect(user.courseNumber, 1);
    final controller = TestCoordinatorController()
      ..appUser = user
      ..data = snapshot(
          entries: [entry(), entry(id: 2, group: 2), entry(id: 3, group: 3)]);
    expect(controller.hasStaffSchedule, isTrue);
    expect(controller.messageTargetGroups.map((g) => g.id), [1]);
    expect(controller.canCancelLesson(entry()), isTrue);
    expect(controller.canCancelLesson(entry(group: 2)), isFalse);
    expect(controller.canCancelLesson(entry(group: 3)), isFalse);
    expect(
        controller.entriesOnDate(DateTime(2026, 10, 26)).map((e) => e.id), [1]);
    controller.dispose();
  });
  test(
      'a room override affects one occurrence and survives offline cache roundtrip',
      () {
    final data = ScheduleData.decode(snapshot(updates: [
      LessonUpdate(
          entryId: 1,
          date: '2026-10-26',
          kind: 'room_changed',
          room: '555',
          notes: 'Entrance B')
    ]).encode());
    final changed =
        data.entriesOnDate(DateTime(2026, 10, 26), groupId: 1).single;
    expect(changed.room, '555');
    expect(changed.originalDate, '2026-10-26');
    expect(changed.notes, contains('Entrance B'));
    expect(data.entriesOnDate(DateTime(2026, 11, 2), groupId: 1).single.room,
        '115');
    expect(data.entries.single.room, '115');
  });
  test(
      'rescheduling removes only the source occurrence and inserts the destination with original identity',
      () {
    final data = snapshot(updates: [
      LessonUpdate(
          entryId: 1,
          date: '2026-10-26',
          kind: 'rescheduled',
          newDate: '2026-10-27',
          startTime: '11:00',
          endTime: '12:20',
          room: '777')
    ], cancelled: [
      CancelledLesson(entryId: 1, date: '2026-10-26', isRescheduled: true)
    ]);
    expect(data.entriesOnDate(DateTime(2026, 10, 26), groupId: 1), isEmpty);
    final moved = data.entriesOnDate(DateTime(2026, 10, 27), groupId: 1).single;
    expect(moved.id, 1);
    expect(moved.originalDate, '2026-10-26');
    expect(moved.startTime, '11:00');
    expect(moved.room, '777');
    expect(data.cancelledLessonsOn(DateTime(2026, 10, 26)), isEmpty);
    expect(
        data.entriesOnDate(DateTime(2026, 11, 2), groupId: 1).single.startTime,
        '09:00');
    expect(data.entriesOnDate(DateTime(2026, 10, 27), groupId: 2), isEmpty);
  });
  test(
      'same-day time changes do not duplicate a lesson; notes preserve base data',
      () {
    final data = snapshot(updates: [
      LessonUpdate(
          entryId: 1,
          date: '2026-10-26',
          kind: 'rescheduled',
          newDate: '2026-10-26',
          startTime: '13:00',
          endTime: '14:20')
    ]);
    expect(
        data.entriesOnDate(DateTime(2026, 10, 26), groupId: 1).single.startTime,
        '13:00');
    final note = snapshot(updates: [
      LessonUpdate(
          entryId: 1,
          date: '2026-10-26',
          kind: 'note',
          notes: 'Bring calculators')
    ]);
    expect(note.entriesOnDate(DateTime(2026, 10, 26), groupId: 1).single.notes,
        contains('Bring calculators'));
    expect(note.entries.single.notes, isNull);
  });
  test(
      'a rescheduled occurrence keeps its subgroup on a destination with different week parity',
      () {
    final data = snapshot(entries: [
      entry(parity: WeekParity.odd)
    ], updates: [
      LessonUpdate(
          entryId: 1,
          date: '2026-10-26',
          kind: 'rescheduled',
          newDate: '2026-11-02',
          startTime: '11:00',
          endTime: '12:20')
    ]);
    expect(
        data
            .entriesOnDate(DateTime(2026, 11, 2),
                groupId: 1, subgroupFor: (_) => WeekParity.odd)
            .length,
        1);
    expect(
        data.entriesOnDate(DateTime(2026, 11, 2),
            groupId: 1, subgroupFor: (_) => WeekParity.even),
        isEmpty);
    expect(data.entriesOnDate(DateTime(2026, 11, 2), teacherId: 7).length, 1);
  });
  test('malformed session overrides reject invalid dates and time ranges', () {
    for (final value in [
      {'entryId': 1, 'date': '2026-02-30', 'kind': 'note', 'notes': 'bad'},
      {
        'entryId': 1,
        'date': '2026-10-26',
        'kind': 'rescheduled',
        'newDate': '2026-10-27',
        'startTime': '12:00',
        'endTime': '11:00'
      },
      {'entryId': 1, 'date': '2026-10-26', 'kind': 'unsupported'},
    ]) {
      expect(() => LessonUpdate.fromJson(value), throwsFormatException);
    }
  });
  testWidgets(
      'coordinator sees course schedule without group selection and can submit a session update',
      (tester) async {
    final today = DateTime.now();
    final controller = TestCoordinatorController()
      ..appUser = coordinator()
      ..data = snapshot(entries: [
        entry(day: today.weekday),
        entry(id: 2, group: 2, day: today.weekday)
      ]);
    await tester
        .pumpWidget(MaterialApp(home: ScheduleScreen(controller: controller)));
    expect(find.text(Strings.courseSchedule), findsOneWidget);
    expect(find.text('Physics 2'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Статистика'), findsNothing);
    await tester.ensureVisible(find.text('Physics 1').first);
    await tester.tap(find.text('Physics 1').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(Strings.changeLessonAction));
    await tester.tap(find.text(Strings.changeLessonAction));
    await tester.pumpAndSettle();
    expect(find.text(Strings.saveAndNotify), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), '11:00');
    await tester.enterText(fields.at(2), '12:20');
    await tester.enterText(fields.at(3), '555');
    await tester.enterText(fields.at(4), 'One-off move');
    await tester.ensureVisible(find.text(Strings.saveAndNotify));
    await tester.tap(find.text(Strings.saveAndNotify));
    await tester.pumpAndSettle();
    expect(controller.saved?['kind'], 'rescheduled');
    expect(controller.saved?['date'], ScheduleData.isoDate(today));
    expect(controller.saved?['room'], '555');
    expect(controller.saved?['entryId'], 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
