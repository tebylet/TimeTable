import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/services/sync_service.dart';
import 'package:ymtimetable/services/update_channel.dart';
import 'package:ymtimetable/services/update_installer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('de.ffuf.in_app_update/methods');
  final calls = <String>[];
  var denied = false;
  var downloaded = false;
  var unavailable = false;
  setUp(() {
    calls.clear();
    denied = false;
    downloaded = false;
    unavailable = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'checkForUpdate') {
        if (unavailable) throw PlatformException(code: 'API_NOT_AVAILABLE');
        return {
          'updateAvailability': 2,
          'immediateAllowed': true,
          'flexibleAllowed': true,
          'availableVersionCode': 9,
          'installStatus': downloaded ? 11 : 0,
          'packageName': 'com.example.ymtimetable',
          'clientVersionStalenessDays': 1,
          'updatePriority': 0
        };
      }
      if (call.method == 'startFlexibleUpdate' && denied) {
        throw PlatformException(code: 'USER_DENIED_UPDATE');
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
      'Play checks do not need the timetable server; restart requires a separate action',
      () async {
    final controller = ScheduleController(channel: UpdateChannel.googlePlay);
    await controller.checkForUpdate();
    expect(controller.updateAvailable, isTrue);
    await controller.installUpdate();
    expect(controller.installPhase, InstallPhase.ready);
    expect(calls.where((call) => call == 'completeFlexibleUpdate'), isEmpty);
    await controller.installUpdate();
    expect(calls.last, 'completeFlexibleUpdate');
    expect(controller.isInstallingUpdate, isFalse);
    controller.dispose();
  });
  test('cancellation allows retry and refreshes Play information', () async {
    final controller = ScheduleController(channel: UpdateChannel.googlePlay);
    await controller.checkForUpdate();
    denied = true;
    await controller.installUpdate();
    expect(controller.installPhase, InstallPhase.canceled);
    denied = false;
    await controller.installUpdate();
    expect(controller.installPhase, InstallPhase.ready);
    expect(calls.where((call) => call == 'checkForUpdate').length, 3);
    controller.dispose();
  });
  test('already downloaded updates can be completed after an app restart',
      () async {
    downloaded = true;
    final controller = ScheduleController(channel: UpdateChannel.googlePlay);
    await controller.checkForUpdate();
    expect(controller.installPhase, InstallPhase.ready);
    await controller.installUpdate();
    expect(calls, ['checkForUpdate', 'completeFlexibleUpdate']);
    controller.dispose();
  });
  test('Play failure is not reported as being up to date', () async {
    unavailable = true;
    final controller = ScheduleController(channel: UpdateChannel.googlePlay);
    await controller.checkForUpdate();
    expect(controller.updateCheckFailed, isTrue);
    expect(controller.updateAvailable, isFalse);
    controller.dispose();
  });
}
