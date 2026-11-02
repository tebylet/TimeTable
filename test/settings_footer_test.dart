import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/localization.dart';
import 'package:ymtimetable/screens/settings_screen.dart';
import 'package:ymtimetable/services/sync_service.dart';

class _SettingsController extends ScheduleController {
  int retrustCalls = 0;

  @override
  Future<void> retrustServerCertificate() async {
    retrustCalls++;
  }
}

void main() {
  testWidgets('certificate recovery remains available without address editing',
      (tester) async {
    final controller = _SettingsController()
      ..lastErrorIsCertificateMismatch = true;
    await tester
        .pumpWidget(MaterialApp(home: SettingsScreen(controller: controller)));
    expect(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.keyboardType == TextInputType.url),
        findsNothing);
    final recovery = find.widgetWithText(
        OutlinedButton, Strings.trustServerCertificateAgain);
    await tester.ensureVisible(recovery);
    await tester.pumpAndSettle();
    await tester.tap(recovery);
    await tester.pumpAndSettle();
    expect(controller.retrustCalls, 1);
    expect(find.text(Strings.syncNow), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('footer stays above Android navigation buttons', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);
    final controller = ScheduleController();
    await tester
        .pumpWidget(MaterialApp(home: SettingsScreen(controller: controller)));
    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await tester.pumpAndSettle();
    final footer = find.text('Разработчик: YM');
    expect(footer, findsOneWidget);
    expect(tester.getBottomLeft(footer).dy, lessThanOrEqualTo(800 - 48 - 20));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
