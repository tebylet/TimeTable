import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/localization.dart';
import 'package:ymtimetable/models/exam_entry.dart';
import 'package:ymtimetable/models/group.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/screens/exams_screen.dart';
import 'package:ymtimetable/screens/schedule_screen.dart';
import 'package:ymtimetable/services/sync_service.dart';
import 'package:ymtimetable/widgets/schedule_day_view.dart';

class ExamTestController extends ScheduleController {
  int syncCalls = 0;
  @override
  Future<void> sync({bool force = false}) async {
    syncCalls++;
  }

  void replaceData(ScheduleData value) {
    data = value;
    notifyListeners();
  }
}

ExamEntry exam(
        {int id = 1,
        int subject = 10,
        String name = 'Mathematics',
        String date = '2026-11-02',
        int group = 1}) =>
    ExamEntry(
        id: id,
        groupId: group,
        subjectId: subject,
        subject: name,
        groupNameRu: 'Group $group',
        date: date,
        startTime: '09:00',
        endTime: '11:00',
        teacherId: 7,
        teacher: 'Smith',
        room: '315',
        notes: 'Bring a calculator');

ScheduleData snapshot(List<ExamEntry> exams) => ScheduleData(
    version: 1,
    semesterStartDate: '2026-09-01',
    groups: [Group(id: 1, name: 'Group 1'), Group(id: 2, name: 'Group 2')],
    entries: [],
    cancelledLessons: [],
    messages: [],
    exams: exams,
    fetchedAt: DateTime(2026, 10, 30));

Future<void> selectSubject(WidgetTester tester, int id) async {
  await tester.tap(find.byKey(const ValueKey('exam-subject-filter')));
  await tester.pumpAndSettle();
  await tester.tap(find
      .descendant(
          of: find.byKey(ValueKey('exam-subject-$id')).last,
          matching: find.byType(Text))
      .last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Strings.current = AppLocale.en);
  tearDown(() => Strings.current = AppLocale.ru);

  testWidgets(
      'students can open Exams and switch between dates and subject results',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ExamTestController()..selectedGroupId = 1;
    controller.data = snapshot([
      exam(),
      exam(id: 2, subject: 20, name: 'Physics', date: '2026-12-15'),
      exam(id: 3, group: 2, name: 'Other group exam'),
    ]);
    await tester
        .pumpWidget(MaterialApp(home: ScheduleScreen(controller: controller)));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Exams'), findsNothing);
    await tester.tap(find.byTooltip('Schedule sections'));
    await tester.pumpAndSettle();
    expect(find.text('Statistics'), findsNothing);
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Exams'));
    await tester.pumpAndSettle();
    expect(find.text('By date'), findsOneWidget);
    expect(find.text('By subject'), findsOneWidget);
    expect(find.text('Statistics'), findsNothing);
    await tester.tap(find.text('By subject'));
    await tester.pumpAndSettle();
    await selectSubject(tester, 20);
    expect(find.byType(ListTile), findsOneWidget);
    final result = tester.widget<ListTile>(find.byType(ListTile));
    expect((result.title as Text).data, 'Physics');
    expect((result.subtitle as Text).data, contains('09:00–11:00'));
    expect(find.text('Mathematics'), findsNothing);
    expect(find.text('Other group exam'), findsNothing);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.text('Bring a calculator'), findsOneWidget);
    expect(find.text('room 315'), findsOneWidget);
    await tester.tap(find.text('Show this day'));
    await tester.pumpAndSettle();
    final day = tester.widget<ScheduleDayView>(find.byType(ScheduleDayView));
    expect(day.entries.single.subject, 'Physics');
    expect(day.entries.single.startTime, '09:00');
    expect(find.textContaining('15 Dec 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    expect(find.text('No exams on this date'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ScheduleDayView>(find.byType(ScheduleDayView))
            .entries
            .single
            .subject,
        'Physics');
    await tester.tap(find.byTooltip('Schedule sections'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Schedule'));
    await tester.pumpAndSettle();
    expect(find.byType(ExamsScreen), findsNothing);
    expect(find.byType(ScheduleDayView), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
      'same-name subjects keep distinct identities and contextual labels',
      (tester) async {
    final controller = ExamTestController()..selectedGroupId = 1;
    controller.data = snapshot([
      exam(subject: 10, name: 'Physics'),
      exam(id: 2, subject: 20, name: 'Physics', date: '2026-12-15'),
    ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExamsScreen(
                controller: controller, initialDate: DateTime(2026, 11, 2)))));
    expect(
        tester
            .widget<ScheduleDayView>(find.byType(ScheduleDayView))
            .entries
            .single
            .id,
        1);
    await tester.tap(find.text('By subject'));
    await tester.pumpAndSettle();
    final dropdown =
        tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>));
    final labels = dropdown.items!
        .skip(1)
        .map((item) => (item.child as Text).data)
        .toSet();
    expect(labels.length, 2);
    await selectSubject(tester, 20);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Tuesday, 15 Dec 2026'), findsOneWidget);
    expect(find.text('Monday, 2 Nov 2026'), findsNothing);
    controller.replaceData(snapshot([exam()]));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .value,
        0);
    expect(find.byType(ListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('empty cached exam timetable remains refreshable while offline',
      (tester) async {
    final controller = ExamTestController()
      ..selectedGroupId = 1
      ..lastSyncAt = DateTime(2026, 10, 30)
      ..lastSyncOk = false
      ..data = ScheduleData.decode(snapshot([]).encode());
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ExamsScreen(controller: controller))));
    await tester.pumpAndSettle();
    expect(find.text('No exams scheduled yet'), findsOneWidget);
    expect(find.text(Strings.noServerConnection), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(controller.syncCalls, 1);
    await tester.tap(find.text('By subject'));
    await tester.pumpAndSettle();
    expect(find.text('No exams scheduled yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
