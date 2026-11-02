import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/localization.dart';
import 'package:ymtimetable/models/faculty.dart';
import 'package:ymtimetable/models/group.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/screens/group_select_screen.dart';
import 'package:ymtimetable/services/sync_service.dart';

void main() {
  tearDown(() => Strings.current = AppLocale.ru);

  testWidgets(
      'student selects faculty, one of four courses, then sees its groups',
      (tester) async {
    Strings.current = AppLocale.ru;
    final controller = ScheduleController()
      ..data = ScheduleData(
        version: 1,
        semesterStartDate: null,
        faculties: [
          Faculty(id: 10, name: 'ФРиКТ', nameEn: 'FRCT'),
          Faculty(id: 20, name: 'Мехмат', nameEn: 'Mechanics'),
        ],
        groups: [
          Group(id: 1, facultyId: 10, courseNumber: 1, name: 'РФ-11'),
          Group(id: 2, facultyId: 10, courseNumber: 2, name: 'РФ-21'),
          Group(id: 3, facultyId: 20, courseNumber: 1, name: 'ММ-11'),
        ],
        entries: const [],
        cancelledLessons: const [],
        messages: const [],
        fetchedAt: DateTime(2026, 9, 19),
      );

    await tester.pumpWidget(MaterialApp(
      home: GroupSelectScreen(controller: controller),
    ));

    expect(find.text('ВЫБЕРИТЕ ФАКУЛЬТЕТ'), findsOneWidget);
    expect(find.text('ФРиКТ'), findsOneWidget);
    await tester.tap(find.text('ФРиКТ'));
    await tester.pump();

    expect(find.text('ВЫБЕРИТЕ КУРС'), findsOneWidget);
    expect(find.text('1 курс'), findsOneWidget);
    expect(find.text('2 курс'), findsOneWidget);
    expect(find.text('3 курс'), findsOneWidget);
    expect(find.text('4 курс'), findsOneWidget);
    await tester.tap(find.text('2 курс'));
    await tester.pump();

    expect(find.text('ВЫБЕРИТЕ ГРУППУ'), findsOneWidget);
    expect(find.text('РФ-21'), findsOneWidget);
    expect(find.text('РФ-11'), findsNothing);

    // The labeled back button retains the faculty and allows another year.
    await tester.tap(find.byKey(const ValueKey('group-selection-back')));
    await tester.pump();
    expect(find.text('ВЫБЕРИТЕ КУРС'), findsOneWidget);
    expect(find.text('ФРиКТ'), findsOneWidget);
    await tester.tap(find.text('1 курс'));
    await tester.pump();
    expect(find.text('РФ-11'), findsOneWidget);
    expect(find.text('РФ-21'), findsNothing);

    // Completed steps can be opened directly, including from an empty year.
    await tester.tap(find.byKey(const ValueKey('course-step')));
    await tester.pump();
    await tester.tap(find.text('4 курс'));
    await tester.pump();
    expect(find.text(Strings.noGroupsForCourse), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('faculty-step')));
    await tester.pump();
    expect(find.text('ВЫБЕРИТЕ ФАКУЛЬТЕТ'), findsOneWidget);
    await tester.tap(find.text('Мехмат'));
    await tester.pump();
    expect(find.text('ВЫБЕРИТЕ КУРС'), findsOneWidget);
    await tester.tap(find.text('1 курс'));
    await tester.pump();
    expect(find.text('ММ-11'), findsOneWidget);
    expect(find.text('РФ-11'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('group-selection-back')));
    await tester.pump();
    expect(find.text(Strings.backToFaculties), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-selection-back')));
    await tester.pump();
    expect(find.text('ВЫБЕРИТЕ ФАКУЛЬТЕТ'), findsOneWidget);
    expect(controller.selectedGroupId, isNull);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('changing a saved group supports system back through every step',
      (tester) async {
    final controller = ScheduleController()
      ..selectedGroupId = 2
      ..data = ScheduleData(
        version: 1,
        semesterStartDate: null,
        faculties: [Faculty(id: 10, name: 'ФРиКТ')],
        groups: [Group(id: 2, facultyId: 10, courseNumber: 2, name: 'РФ-21')],
        entries: const [],
        cancelledLessons: const [],
        messages: const [],
        fetchedAt: DateTime(2026, 11, 1),
      );

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => GroupSelectScreen(
                  controller: controller, isChangingGroup: true),
            )),
            child: const Text('Сменить группу'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Сменить группу'));
    await tester.pumpAndSettle();
    expect(find.text('ВЫБЕРИТЕ ГРУППУ'), findsOneWidget);
    expect(find.text('РФ-21'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ВЫБЕРИТЕ КУРС'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ВЫБЕРИТЕ ФАКУЛЬТЕТ'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Сменить группу'), findsOneWidget);
    expect(find.byType(GroupSelectScreen), findsNothing);
    expect(controller.selectedGroupId, 2);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
