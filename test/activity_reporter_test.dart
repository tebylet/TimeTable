import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/services/activity_reporter.dart';

void main() {
  testWidgets(
      'signals foreground/background and sends nothing while backgrounded',
      (tester) async {
    final signals = <bool>[];
    final reporter = ActivityReporter(send: (active) async {
      signals.add(active);
    });
    reporter.setForeground(true);
    await tester.pump();
    expect(signals, [true]);
    await tester.pump(const Duration(seconds: 30));
    expect(signals, [true, true]);
    reporter.setForeground(false);
    await tester.pump();
    expect(signals, [true, true, false]);
    await tester.pump(const Duration(minutes: 10));
    expect(signals.length, 3);
    reporter.setForeground(true);
    await tester.pump();
    expect(signals.last, isTrue);
    reporter.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(signals.length, 4);
  });
  testWidgets('a delayed foreground request cannot overtake background signal',
      (tester) async {
    final gate = Completer<void>();
    final signals = <bool>[];
    final reporter = ActivityReporter(send: (active) async {
      signals.add(active);
      if (active) await gate.future;
    });
    reporter.setForeground(true);
    reporter.setForeground(false);
    await tester.pump();
    expect(signals, [true]);
    gate.complete();
    await tester.pump();
    expect(signals, [true, false]);
    reporter.dispose();
  });
  testWidgets('failures are swallowed without a retry storm', (tester) async {
    var count = 0;
    final reporter = ActivityReporter(send: (_) async {
      count++;
      throw StateError('offline');
    });
    reporter.setForeground(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 29));
    expect(count, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(count, 2);
    reporter.dispose();
  });
}
