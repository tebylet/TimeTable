import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/models/app_user.dart';
import 'package:ymtimetable/screens/schedule_screen.dart';
import 'package:ymtimetable/services/sync_service.dart';

class TestController extends ScheduleController {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> loadAdminStatistics() async {
    calls++;
    return {
      'activeNow': 7,
      'periods': [
        {'period': 'day', 'visits': 12},
        {'period': 'week', 'visits': 30},
        {'period': 'month', 'visits': 50},
        {'period': 'year', 'visits': 100}
      ],
      'timeZone': 'Europe/Minsk',
      'startedAt': '2026-09-17T00:00:00Z',
      'generatedAt': '2026-09-17T00:00:00Z'
    };
  }

  @override
  Future<Map<String, dynamic>> loadAdminAudit({int? before}) async =>
      {'items': [], 'nextCursor': null};
  void changeRole(AppRole role) {
    appUser = AppUser(id: 1, username: 'test', role: role, displayName: 'Test');
    notifyListeners();
  }
}

void main() {
  testWidgets(
      'admin gets lazy statistics through the menu; teachers cannot see it',
      (tester) async {
    final controller = TestController()..selectedGroupId = 1;
    controller.changeRole(AppRole.admin);
    await tester
        .pumpWidget(MaterialApp(home: ScheduleScreen(controller: controller)));
    await tester.pump();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Статистика'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('schedule-section-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Статистика'), findsOneWidget);
    expect(controller.calls, 0);
    await tester
        .tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Статистика'));
    await tester.pumpAndSettle();
    expect(find.text('Активные сейчас'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(controller.calls, 1);
    controller.changeRole(AppRole.teacher);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Статистика'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('schedule-section-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Статистика'), findsNothing);
    expect(find.text('Экзамены'), findsOneWidget);
    expect(find.text('Активные сейчас'), findsNothing);
    await tester
        .tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Экзамены'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 45));
    expect(controller.calls, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
