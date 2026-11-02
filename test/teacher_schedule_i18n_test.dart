import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/localization.dart';
import 'package:ymtimetable/models/app_user.dart';
import 'package:ymtimetable/models/group.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/models/schedule_entry.dart';
import 'package:ymtimetable/screens/schedule_screen.dart';
import 'package:ymtimetable/services/sync_service.dart';

void main() {
  tearDown(() => Strings.current = AppLocale.ru);

  test('group and subject use English values with Russian fallback', () {
    final group = Group(
      id: 1,
      name: 'Группа 1',
      nameEn: 'Group 1',
      specialization: 'Физика',
    );
    final translated = ScheduleEntry(
      id: 1,
      groupId: 1,
      dayOfWeek: 1,
      period: 1,
      startTime: '09:00',
      endTime: '10:20',
      subject: 'Математика',
      subjectEn: 'Mathematics',
    );
    final fallback = ScheduleEntry(
      id: 2,
      groupId: 1,
      dayOfWeek: 1,
      period: 2,
      startTime: '10:30',
      endTime: '11:50',
      subject: 'Физика',
    );
    Strings.current = AppLocale.en;
    expect(group.name, 'Group 1');
    expect(group.specialization, 'Физика');
    expect(translated.subject, 'Mathematics');
    expect(fallback.subject, 'Физика');
  });

  testWidgets(
      'teacher sees personal schedule without selecting a group and can open calendar',
      (tester) async {
    final now = DateTime.now();
    final controller = ScheduleController()
      ..appUser = AppUser(
        id: 5,
        username: 'teacher',
        role: AppRole.teacher,
        displayName: 'Иванов И.И.',
        teacherId: 7,
      )
      ..data = ScheduleData(
        version: 1,
        semesterStartDate: null,
        groups: [Group(id: 3, name: 'РФ-11', nameEn: 'RP-11')],
        entries: [
          ScheduleEntry(
            id: 9,
            groupId: 3,
            groupNameRu: 'РФ-11',
            groupNameEn: 'RP-11',
            dayOfWeek: now.weekday,
            period: 1,
            startTime: '09:00',
            endTime: '10:20',
            subject: 'Физика',
            teacherId: 7,
          ),
        ],
        cancelledLessons: const [],
        messages: const [],
        fetchedAt: now,
      );

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ScheduleScreen(controller: controller),
    ));
    await tester.pump();
    expect(find.text('Моё расписание'), findsOneWidget);
    expect(find.text('Физика'), findsOneWidget);
    expect(find.text('Группа: РФ-11'), findsOneWidget);
    expect(find.text('Выберите группу'), findsNothing);

    await tester.tap(find.byTooltip('Выбрать дату'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
