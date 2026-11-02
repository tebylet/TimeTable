import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/localization.dart';
import 'package:ymtimetable/models/app_message.dart';
import 'package:ymtimetable/models/app_user.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/screens/chat_screen.dart';
import 'package:ymtimetable/services/api_client.dart';
import 'package:ymtimetable/services/sync_service.dart';
import 'package:ymtimetable/services/update_channel.dart';

class _Controller extends ScheduleController {
  int calls = 0;
  bool fail = false;
  Completer<void>? pending;
  _Controller() : super(channel: UpdateChannel.unsupported) {
    appUser = AppUser(
        id: 9,
        username: 'staff',
        role: AppRole.teacher,
        displayName: 'Staff',
        teacherId: 7);
    data = ScheduleData(
        version: 1,
        semesterStartDate: null,
        groups: [],
        entries: [],
        cancelledLessons: [],
        fetchedAt: DateTime(2026, 11, 2),
        messages: [
          for (final id in [1, 2, 3])
            AppMessage(
                id: id,
                senderName: 'Same name',
                senderUserId: id == 1
                    ? 9
                    : id == 2
                        ? 8
                        : null,
                targetGroupId: null,
                body: 'Message $id',
                createdAt: DateTime.utc(2026, 11, 2)),
        ]);
  }
  @override
  Future<void> markMessagesSeen() async {}
  @override
  Future<void> deleteMessage(AppMessage message) async {
    calls++;
    if (pending != null) await pending!.future;
    if (fail) throw ApiException('Test offline');
    data = data.withoutMessage(message.id);
    notifyListeners();
  }
}

void main() {
  tearDown(() => Strings.current = AppLocale.ru);
  testWidgets(
      'only own messages have deletion, with confirmation and one pending request',
      (tester) async {
    final controller = _Controller();
    await tester
        .pumpWidget(MaterialApp(home: ChatScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('delete-message-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-message-2')), findsNothing);
    expect(find.byKey(const ValueKey('delete-message-3')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('delete-message-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, Strings.dialogCancel));
    await tester.pumpAndSettle();
    expect(controller.calls, 0);
    expect(find.text('Message 1'), findsOneWidget);
    controller.pending = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('delete-message-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, Strings.deleteMessage));
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.calls, 1);
    expect(find.byKey(const ValueKey('delete-message-1')), findsNothing);
    controller.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Message 1'), findsNothing);
    expect(find.text('Message 2'), findsOneWidget);
    await tester.tap(find.text(Strings.messagesFilterMine));
    await tester.pumpAndSettle();
    expect(find.text(Strings.chatEmptyMine), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('failed deletion keeps the message and allows retry',
      (tester) async {
    final controller = _Controller()..fail = true;
    await tester
        .pumpWidget(MaterialApp(home: ChatScreen(controller: controller)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-message-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, Strings.deleteMessage));
    await tester.pumpAndSettle();
    expect(find.text('Test offline'), findsOneWidget);
    expect(find.text('Message 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-message-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
