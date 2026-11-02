import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/localization.dart';
import 'package:ymtimetable/models/faculty.dart';
import 'package:ymtimetable/models/group.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/screens/group_select_screen.dart';
import 'package:ymtimetable/screens/schedule_screen.dart';
import 'package:ymtimetable/services/sync_service.dart';
import 'package:ymtimetable/theme.dart';
import 'package:ymtimetable/widgets/schedule_date_strip.dart';
import 'package:ymtimetable/widgets/schedule_day_view.dart';

ScheduleController _controller() => ScheduleController()
  ..selectedGroupId = 1
  ..data = ScheduleData(
    version: 1,
    semesterStartDate: '2026-09-01',
    faculties: [Faculty(id: 10, name: 'Факультет радиофизики')],
    groups: [
      Group(id: 1, facultyId: 10, courseNumber: 2, name: 'Радиофизика РФ-21'),
    ],
    entries: const [],
    cancelledLessons: const [],
    messages: const [],
    fetchedAt: DateTime(2026, 11, 1),
  );

Widget _app(Widget home) => MaterialApp(
      theme: AppTheme.themeDataFor(AppThemeVariant.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.4),
          padding: const EdgeInsets.only(bottom: 24),
          viewPadding: const EdgeInsets.only(bottom: 24),
        ),
        child: child!,
      ),
      home: home,
    );

void main() {
  tearDown(() => Strings.current = AppLocale.ru);

  testWidgets('section menu retains the chosen day and respects system insets',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller();
    await tester.pumpWidget(_app(ScheduleScreen(controller: controller)));
    await tester.pumpAndSettle();
    final target = DateTime.now().add(const Duration(days: 2));
    tester
        .widget<ScheduleDateStrip>(find.byType(ScheduleDateStrip))
        .onSelect(target);
    await tester.pumpAndSettle();
    final selected = tester
        .widget<ScheduleDateStrip>(find.byType(ScheduleDateStrip))
        .selectedDate;
    expect(
        find.text('${Strings.dayFull(selected.weekday)}, ${selected.day} '
            '${Strings.monthShort(selected.month)}'),
        findsNothing);
    expect(tester.getBottomLeft(find.byType(ScheduleDayView)).dy, 616);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip(Strings.scheduleSections));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(CheckedPopupMenuItem<int>, Strings.exams));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(Strings.scheduleSections));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(CheckedPopupMenuItem<int>, Strings.schedule));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ScheduleDateStrip>(find.byType(ScheduleDateStrip))
            .selectedDate,
        selected);
    await tester.tap(find.byTooltip(Strings.today));
    await tester.pumpAndSettle();
    final today = DateTime.now();
    expect(
        tester
            .widget<ScheduleDateStrip>(find.byType(ScheduleDateStrip))
            .selectedDate,
        DateTime(today.year, today.month, today.day));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('group steps remain usable on a narrow screen with larger text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _controller();
    await tester.pumpWidget(
        _app(GroupSelectScreen(controller: controller, isChangingGroup: true)));
    await tester.pumpAndSettle();
    expect(find.text('Радиофизика РФ-21'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('course-step')));
    await tester.pumpAndSettle();
    expect(find.text('ВЫБЕРИТЕ КУРС'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('faculty-step')));
    await tester.pumpAndSettle();
    expect(find.text('ВЫБЕРИТЕ ФАКУЛЬТЕТ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
