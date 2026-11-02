import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/models/schedule_entry.dart';
import 'package:ymtimetable/theme.dart';
import 'package:ymtimetable/widgets/schedule_day_view.dart';

const boundaryKey = ValueKey('timeline-boundary');
const lineKey = ValueKey('current-time-line');

ScheduleEntry lesson(int id, String start, String end) => ScheduleEntry(
    id: id,
    groupId: 1,
    dayOfWeek: 7,
    period: 1,
    startTime: start,
    endTime: end,
    subject: 'Lesson $id');

Future<void> showTimeline(
    WidgetTester tester, List<ScheduleEntry> entries, DateTime Function() clock,
    {bool isToday = true, double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: RepaintBoundary(
                  key: boundaryKey,
                  child: ScheduleDayView(
                      entries: entries, isToday: isToday, clock: clock))))));
  await tester.pumpAndSettle();
}

Future<List<Color>> pixelsAt(WidgetTester tester, List<Offset> points) async {
  final element = find.byKey(boundaryKey);
  final boundary = tester.renderObject<RenderRepaintBoundary>(element);
  final origin = tester.getTopLeft(element);
  const scale = 4.0;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: scale);
    try {
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      return points.map((point) {
        final local = point - origin;
        final x = (local.dx * scale).floor();
        final y = (local.dy * scale).floor();
        final offset = (y * image.width + x) * 4;
        return Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2));
      }).toList();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  testWidgets(
      'hour rule, time badge and lesson start share the exact time coordinate',
      (tester) async {
    final entry = lesson(1, '09:00', '10:20');
    final now = DateTime(2026, 11, 1, 9);
    for (final scale in [1.0, 2.5]) {
      await showTimeline(tester, [entry], () => now, textScale: scale);
      final card = tester.getRect(find.byKey(ObjectKey(entry)));
      final line = tester.getRect(find.byKey(lineKey));
      final badge =
          tester.getRect(find.byKey(const ValueKey('current-time-label')));
      final hour = tester.getRect(find.byKey(const ValueKey('hour-line-540')));
      expect(line.center.dy, closeTo(card.top, 0.001));
      expect(hour.center.dy, closeTo(card.top, 0.001));
      expect(badge.center.dy, closeTo(line.center.dy, 0.001));
      expect(badge.right, lessThan(card.left));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'short lessons occupy only their actual duration on the hour scale',
      (tester) async {
    final entry = lesson(1, '09:00', '09:10');
    await showTimeline(tester, [entry], () => DateTime(2026, 11, 1, 9, 5));
    final card = tester.getRect(find.byKey(ObjectKey(entry)));
    final nine =
        tester.getCenter(find.byKey(const ValueKey('hour-line-540'))).dy;
    final ten =
        tester.getCenter(find.byKey(const ValueKey('hour-line-600'))).dy;
    expect(card.top, closeTo(nine, 0.001));
    expect(card.height, closeTo((ten - nine) / 6, 0.001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'the painted time stroke never enters an upcoming or finished card',
      (tester) async {
    final entry = lesson(1, '09:00', '09:10');
    var now = DateTime(2026, 11, 1, 8, 59, 59);
    DateTime clock() => now;
    for (final time in [
      DateTime(2026, 11, 1, 8, 59, 59),
      DateTime(2026, 11, 1, 9, 9, 59),
      DateTime(2026, 11, 1, 9, 10),
      DateTime(2026, 11, 1, 9, 10, 1),
    ]) {
      now = time;
      await showTimeline(tester, [entry], clock);
      final card = tester.getRect(find.byKey(ObjectKey(entry)));
      final active = time.hour == 9 && time.minute < 10;
      final point = Offset(
          card.center.dx, time.hour < 9 ? card.top + 0.25 : card.bottom - 0.25);
      final color = (await pixelsAt(tester, [point])).single;
      expect(color, active ? AppColors.nowLine : isNot(AppColors.nowLine),
          reason: 'Paint at $time must respect [09:00, 09:10)');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'at a shared boundary the marker crosses only the still-active parallel lesson',
      (tester) async {
    final ended = lesson(1, '09:00', '10:00');
    final active = lesson(2, '09:30', '10:30');
    await showTimeline(
        tester, [ended, active], () => DateTime(2026, 11, 1, 10));
    final first = tester.getRect(find.byKey(ObjectKey(ended)));
    final second = tester.getRect(find.byKey(ObjectKey(active)));
    final y = tester.getCenter(find.byKey(lineKey)).dy - 0.25;
    final colors = await pixelsAt(
        tester, [Offset(first.center.dx, y), Offset(second.center.dx, y)]);
    expect(colors[0], isNot(AppColors.nowLine));
    expect(colors[1], AppColors.nowLine);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'wall-aligned updates refresh at lesson start and end, then stop on other days',
      (tester) async {
    final entry = lesson(1, '09:00', '09:01');
    var now = DateTime(2026, 11, 1, 8, 59, 45);
    DateTime clock() => now;
    await showTimeline(tester, [entry], clock);
    expect(find.text('08:59'), findsOneWidget);
    now = DateTime(2026, 11, 1, 9);
    await tester.pump(const Duration(seconds: 15));
    expect(tester.getCenter(find.byKey(lineKey)).dy,
        closeTo(tester.getRect(find.byKey(ObjectKey(entry))).top, 0.001));
    now = DateTime(2026, 11, 1, 9, 1);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('09:01'), findsOneWidget);
    final card = tester.getRect(find.byKey(ObjectKey(entry)));
    final color =
        (await pixelsAt(tester, [Offset(card.center.dx, card.bottom - 0.25)]))
            .single;
    expect(color, isNot(AppColors.nowLine));
    await showTimeline(tester, [entry], clock, isToday: false);
    expect(find.byKey(lineKey), findsNothing);
    await tester.pump(const Duration(minutes: 1));
    expect(find.byKey(lineKey), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
