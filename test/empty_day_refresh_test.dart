import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/localization.dart';
import 'package:ymtimetable/widgets/schedule_day_view.dart';

void main() {
  testWidgets('pulling down on a day without lessons refreshes the timetable',
      (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async {
            refreshes++;
          },
          child: const ScheduleDayView(entries: [], isToday: false),
        ),
      ),
    ));
    expect(find.text(Strings.noClassesToday), findsOneWidget);
    await tester.drag(find.byType(ScheduleDayView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });
}
