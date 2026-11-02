import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ymtimetable/models/app_message.dart';
import 'package:ymtimetable/models/app_user.dart';
import 'package:ymtimetable/models/group.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/models/schedule_entry.dart';
import 'package:ymtimetable/services/api_client.dart';
import 'package:ymtimetable/services/local_store.dart';
import 'package:ymtimetable/services/notification_service.dart';
import 'package:ymtimetable/services/sync_service.dart';
import 'package:ymtimetable/services/update_channel.dart';

const _urlA = 'http://school-a.test:3000';
const _urlB = 'http://school-b.test:3000';

ScheduleData _snapshot(String id,
        {int version = 1,
        List<int> groupIds = const [1, 2, 3],
        Set<int> teacherGroups = const {1},
        List<AppMessage> messages = const []}) =>
    ScheduleData(
      version: version,
      serverId: id,
      semesterStartDate: '2026-09-01',
      groups: [
        for (final group in groupIds) Group(id: group, name: '$id-$group')
      ],
      entries: [
        for (final group in groupIds)
          ScheduleEntry(
            id: group,
            groupId: group,
            teacherId: teacherGroups.contains(group) ? 7 : 8,
            dayOfWeek: 1,
            period: 1,
            startTime: '09:00',
            endTime: '10:20',
            subject: '$id-subject-$group',
          ),
      ],
      cancelledLessons: [],
      messages: messages,
      fetchedAt: DateTime.utc(2026, 10, 24),
    );

AppMessage _message(int id, int? group, {int? sender}) => AppMessage(
      id: id,
      senderName: 'Teacher',
      senderUserId: sender,
      targetGroupId: group,
      body: 'Message $id',
      createdAt: DateTime.utc(2026, 10, 24, 10),
    );

AppUser _staff(int id) => AppUser(
      id: id,
      username: 'staff-$id',
      role: AppRole.teacher,
      displayName: 'Teacher $id',
      teacherId: 7,
    );

class _Notifications extends NotificationService {
  final shownIds = <int>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> showMessage(
      {required int id, required String title, required String body}) async {
    shownIds.add(id);
  }
}

class _Endpoint {
  final String id;
  ScheduleData snapshot;
  AppUser? user;
  int versionCalls = 0;
  int scheduleCalls = 0;
  int loginCalls = 0;
  int updateCalls = 0;
  int clientsClosed = 0;
  final validatedTokens = <String>[];
  Future<int> Function()? onVersion;
  Future<ScheduleData> Function()? onSchedule;
  Future<AppLoginResult> Function()? onLogin;
  Future<Map<String, dynamic>> Function()? onUpdate;
  Future<void> Function(int)? onDelete;
  final deletedMessages = <int>[];

  _Endpoint(this.id, this.snapshot, {this.user});
}

class _FakeApi extends ApiClient {
  final _Endpoint endpoint;

  _FakeApi(this.endpoint, String url, LocalStore store)
      : super(baseUrl: url, store: store);

  @override
  String? get serverId => endpoint.id;

  @override
  Future<int> fetchVersion() {
    endpoint.versionCalls++;
    return endpoint.onVersion?.call() ??
        Future.value(endpoint.snapshot.version);
  }

  @override
  Future<ScheduleData> fetchSchedule() {
    endpoint.scheduleCalls++;
    return endpoint.onSchedule?.call() ?? Future.value(endpoint.snapshot);
  }

  @override
  Future<AppLoginResult> appLogin(String username, String password) {
    endpoint.loginCalls++;
    return endpoint.onLogin?.call() ??
        Future.value(AppLoginResult(
          ok: true,
          token: 'token-${endpoint.id}',
          user: endpoint.user ?? _staff(20),
        ));
  }

  @override
  Future<AppUser?> appMe(String token) async {
    endpoint.validatedTokens.add(token);
    return endpoint.user;
  }

  @override
  Future<Map<String, dynamic>> getJson(String path) {
    endpoint.updateCalls++;
    return endpoint.onUpdate?.call() ?? Future.value({'versionCode': 0});
  }

  @override
  Future<void> appLogout(String token) async {}

  @override
  Future<void> deleteMessage(String token, int messageId) async {
    endpoint.deletedMessages.add(messageId);
    if (endpoint.onDelete != null) {
      await endpoint.onDelete!(messageId);
    } else {
      endpoint.snapshot = endpoint.snapshot.withoutMessage(messageId);
    }
  }

  @override
  void close() {
    endpoint.clientsClosed++;
    super.close();
  }
}

class _Rig {
  final ScheduleController controller;
  final LocalStore store;
  final _Endpoint a;
  final _Endpoint b;
  final _Notifications notifications;
  bool disposed = false;

  _Rig(this.controller, this.store, this.a, this.b, this.notifications);

  void dispose() {
    if (disposed) return;
    disposed = true;
    controller.dispose();
  }
}

Future<void> _until(bool Function() complete) async {
  for (var attempt = 0; attempt < 100 && !complete(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(complete(), isTrue,
      reason: 'Expected asynchronous operation to start');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rigs = <_Rig>[];

  Future<_Rig> start(
      {ScheduleData? cachedA,
      ScheduleData? cachedB,
      int? selectedGroup,
      AppUser? user,
      String? token,
      int? lastSeen,
      UpdateChannel channel = UpdateChannel.unsupported}) async {
    final store = await LocalStore.open();
    await store.setServerUrl(_urlA);
    final profileA = await store.forServer(_urlA);
    if (cachedA != null) await profileA.saveSchedule(cachedA);
    if (selectedGroup != null) await profileA.setSelectedGroupId(selectedGroup);
    if (user != null) await profileA.setAppAuthUser(user);
    if (token != null) await profileA.setAppAuthToken(token);
    if (lastSeen != null) await profileA.setLastSeenMessageId(lastSeen);
    if (cachedB != null) {
      await (await store.forServer(_urlB)).saveSchedule(cachedB);
    }
    final a = _Endpoint('A', cachedA ?? _snapshot('A'), user: user);
    final b = _Endpoint('B', cachedB ?? _snapshot('B'), user: _staff(20));
    final endpoints = {_urlA: a, _urlB: b};
    final notifications = _Notifications();
    final controller = ScheduleController(
      channel: channel,
      apiFactory: (url, store) => _FakeApi(endpoints[url]!, url, store),
      notifications: notifications,
    );
    final rig = _Rig(controller, store, a, b, notifications);
    rigs.add(rig);
    await controller.init(startBackgroundTasks: false);
    return rig;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Para',
      packageName: 'test.para',
      version: '1.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
  });

  tearDown(() {
    for (final rig in rigs) {
      rig.dispose();
    }
    rigs.clear();
  });

  for (final savedUrl in [null, 'http://10.0.2.2:3000', _urlA]) {
    test('startup selects the correct primary for saved address $savedUrl',
        () async {
      const publicUrl = 'http://80.242.59.206:3000';
      expect(defaultServerUrl, publicUrl);
      final expected = savedUrl == _urlA ? _urlA : publicUrl;
      final store = await LocalStore.open();
      if (savedUrl != null) await store.setServerUrl(savedUrl);
      final profile = await store.forServer(expected);
      await profile.saveSchedule(_snapshot('primary'));
      await profile.setSelectedGroupId(2);
      final endpoint = _Endpoint('primary', _snapshot('primary'));
      final requestedOrigins = <String>[];
      final controller = ScheduleController(
        channel: UpdateChannel.unsupported,
        apiFactory: (url, store) {
          requestedOrigins.add(url);
          return _FakeApi(endpoint, url, store);
        },
      );
      addTearDown(controller.dispose);

      await controller.init(startBackgroundTasks: false);
      expect(controller.serverUrl, expected);
      expect(requestedOrigins, [expected]);
      expect(controller.selectedGroupId, 2);
      expect(controller.data.groups.first.name, 'primary-1');
      await controller.sync();
      expect(endpoint.versionCalls, 1);
      expect(controller.lastSyncOk, isTrue);
    });
  }

  test('confirmed deletion persists even when the following sync is offline',
      () async {
    final mine = _message(1, null, sender: 10);
    final other = _message(2, null, sender: 20);
    final rig = await start(
        cachedA: _snapshot('A', messages: [mine, other]),
        user: _staff(10),
        token: 'token-A');
    rig.a.onDelete = (_) async {};
    rig.a.onVersion = () => Future.error(ApiException('Offline'));
    await rig.controller.deleteMessage(mine);
    expect(rig.a.deletedMessages, [1]);
    expect(rig.controller.data.messages.map((message) => message.id), [2]);
    expect(
        (await rig.store.forServer(_urlA))
            .loadCachedSchedule()
            .messages
            .map((message) => message.id),
        [2]);
    expect(rig.controller.myMessages, isEmpty);
    expect(rig.controller.lastSyncOk, isFalse);
  });

  test('an older in-flight snapshot cannot restore a confirmed deletion',
      () async {
    final mine = _message(1, null, sender: 10);
    final rig = await start(
        cachedA: _snapshot('A', messages: [mine]),
        user: _staff(10),
        token: 'token-A');
    final stale = Completer<ScheduleData>();
    rig.a.onSchedule = () => stale.future;
    final syncing = rig.controller.sync(force: true);
    await _until(() => rig.a.scheduleCalls == 1);
    rig.a.onVersion = () => Future.error(ApiException('Offline'));
    final deleting = rig.controller.deleteMessage(mine);
    stale.complete(_snapshot('A', messages: [mine]));
    await syncing;
    await deleting;
    expect(rig.controller.data.messages, isEmpty);
    expect((await rig.store.forServer(_urlA)).loadCachedSchedule().messages,
        isEmpty);
  });

  test('failed and unauthorized deletions leave messages intact', () async {
    final mine = _message(1, null, sender: 10);
    final other = _message(2, null, sender: 20);
    final rig = await start(
        cachedA: _snapshot('A', messages: [mine, other]),
        user: _staff(10),
        token: 'token-A');
    await expectLater(
        rig.controller.deleteMessage(other), throwsA(isA<ApiException>()));
    expect(rig.a.deletedMessages, isEmpty);
    rig.a.onDelete = (_) => Future.error(ApiException('Offline'));
    await expectLater(
        rig.controller.deleteMessage(mine), throwsA(isA<ApiException>()));
    expect(rig.controller.data.messages.map((message) => message.id), [1, 2]);
  });

  test('late delete response cannot alter a different server profile',
      () async {
    final mine = _message(1, null, sender: 10);
    final rig = await start(
        cachedA: _snapshot('A', messages: [mine]),
        cachedB: _snapshot('B', messages: [_message(1, null, sender: 20)]),
        user: _staff(10),
        token: 'token-A');
    final pending = Completer<void>();
    rig.a.onDelete = (_) => pending.future;
    final deletion = rig.controller.deleteMessage(mine);
    await rig.controller.setServerUrl(_urlB);
    pending.complete();
    await deletion;
    expect(rig.controller.data.messages.single.senderUserId, 20);
    expect(
        (await rig.store.forServer(_urlB)).loadCachedSchedule().messages.length,
        1);
  });

  test('overlapping syncs share work and coalesce forced refresh intent',
      () async {
    final rig = await start(cachedA: _snapshot('A'));
    final heldVersion = Completer<int>();
    rig.a.onVersion = () => heldVersion.future;
    final first = rig.controller.sync();
    final forced = rig.controller.sync(force: true);
    final forcedAgain = rig.controller.sync(force: true);
    expect(identical(first, forced), isTrue);
    expect(identical(first, forcedAgain), isTrue);
    expect(rig.a.versionCalls, 1);
    expect(rig.a.scheduleCalls, 0);

    heldVersion.complete(1);
    await Future.wait([first, forced, forcedAgain]);
    expect(rig.a.versionCalls, 2);
    expect(rig.a.scheduleCalls, 1);
    expect(rig.controller.isSyncing, isFalse);
    expect(rig.controller.lastSyncOk, isTrue);
  });

  test(
      'a previous server update failure cannot overwrite the new server result',
      () async {
    final rig = await start(channel: UpdateChannel.website);
    final oldResponse = Completer<Map<String, dynamic>>();
    rig.a.onUpdate = () => oldResponse.future;
    final oldCheck = rig.controller.checkForUpdate();
    await _until(() => rig.a.updateCalls == 1);
    await rig.controller.setServerUrl(_urlB);
    rig.b.onUpdate = () async => {
          'versionCode': 2,
          'versionName': '2.0',
          'published': true,
          'distribution': 'website',
          'apkAvailable': true,
          'apkUrl': '/api/app-download',
          'sha256': List.filled(64, 'a').join(),
        };
    await rig.controller.checkForUpdate();
    expect(rig.controller.updateAvailable, isTrue);
    oldResponse.completeError(StateError('old server offline'));
    await oldCheck;
    expect(rig.controller.latestUpdate?.versionCode, 2);
    expect(rig.controller.updateAvailable, isTrue);
    expect(rig.controller.updateCheckFailed, isFalse);
  });

  test('late A snapshot cannot overwrite B with the same numeric version',
      () async {
    final cachedA = _snapshot('A', groupIds: [101]);
    final cachedB = _snapshot('B', groupIds: [202]);
    final rig = await start(cachedA: cachedA, cachedB: cachedB);
    final lateSnapshot = Completer<ScheduleData>();
    rig.a.onSchedule = () => lateSnapshot.future;
    final oldSync = rig.controller.sync(force: true);
    await _until(() => rig.a.scheduleCalls == 1);

    await rig.controller.setServerUrl(_urlB);
    expect(rig.controller.data.serverId, 'B');
    expect(rig.controller.data.entries.single.subjectRu, 'B-subject-202');
    expect(rig.b.scheduleCalls, 1,
        reason: 'Switch must force a fetch even for equal versions');
    lateSnapshot.complete(_snapshot('A', version: 99, groupIds: [999]));
    await oldSync;

    expect(rig.controller.serverUrl, _urlB);
    expect(rig.controller.data.serverId, 'B');
    expect(rig.controller.data.version, 1);
    expect(
        (await rig.store.forServer(_urlB)).loadCachedSchedule().serverId, 'B');
    expect((await rig.store.forServer(_urlA)).loadCachedSchedule().version, 1);
  });

  test(
      'server profiles isolate credentials, selections, read state and offline cache',
      () async {
    final rig = await start(
      cachedA: _snapshot('A',
          groupIds: [101], teacherGroups: {101}, messages: [_message(10, 101)]),
      selectedGroup: 101,
      user: _staff(10),
      token: 'token-A',
      lastSeen: 10,
    );
    await rig.controller.setSubgroupPreference(
        rig.controller.data.entries.single, WeekParity.odd);
    rig.b.snapshot = _snapshot('B',
        groupIds: [202], teacherGroups: {202}, messages: [_message(20, 202)]);
    await rig.controller.setServerUrl(_urlB);
    expect(rig.controller.appUser, isNull);
    expect(rig.controller.selectedGroupId, isNull);
    expect(rig.b.validatedTokens, isEmpty);
    expect(rig.controller.data.serverId, 'B');

    await rig.controller.selectGroup(202);
    expect(await rig.controller.loginStaff('b-staff', 'secret'), isTrue);
    await rig.controller.sync();
    await rig.controller.markMessagesSeen();
    await rig.controller.setSubgroupPreference(
        rig.controller.data.entries.single, WeekParity.even);
    rig.a.onVersion = () => Future.error(ApiException('A offline'));
    await rig.controller.setServerUrl(_urlA);
    expect(rig.controller.lastSyncOk, isFalse);
    expect(rig.controller.data.serverId, 'A');
    expect(rig.controller.data.entries.single.subjectRu, 'A-subject-101');
    expect(rig.controller.selectedGroupId, 101);
    expect(rig.controller.appUser?.id, 10);
    expect(
        rig.controller
            .subgroupPreferenceFor(rig.controller.data.entries.single),
        WeekParity.odd);
    expect(rig.a.validatedTokens, ['token-A']);

    await rig.controller.setServerUrl(_urlB);
    expect(rig.controller.selectedGroupId, 202);
    expect(rig.controller.appUser?.id, 20);
    expect(
        rig.controller
            .subgroupPreferenceFor(rig.controller.data.entries.single),
        WeekParity.even);
    expect(rig.b.validatedTokens, ['token-B']);
    final profileA = await rig.store.forServer(_urlA);
    final profileB = await rig.store.forServer(_urlB);
    expect(profileA.appAuthToken, 'token-A');
    expect(profileB.appAuthToken, 'token-B');
    expect(profileA.lastSeenMessageId, 10);
    expect(profileB.lastSeenMessageId, 20);
    expect(profileA.selectedGroupId, 101);
    expect(profileB.selectedGroupId, 202);
  });

  test(
      'login response from the previous server cannot install staff credentials',
      () async {
    final rig = await start(cachedA: _snapshot('A'));
    final lateLogin = Completer<AppLoginResult>();
    rig.a.onLogin = () => lateLogin.future;
    final login = rig.controller.loginStaff('a-staff', 'secret');
    expect(rig.controller.isLoggingIn, isTrue);
    await rig.controller.setServerUrl(_urlB);
    lateLogin.complete(
        AppLoginResult(ok: true, token: 'old-A-token', user: _staff(10)));
    expect(await login, isFalse);
    expect(rig.controller.appUser, isNull);
    expect(rig.controller.isLoggingIn, isFalse);
    expect((await rig.store.forServer(_urlA)).appAuthToken, isNull);
    expect((await rig.store.forServer(_urlB)).appAuthToken, isNull);
  });

  test(
      'student notifications use the same group recipients as the visible feed',
      () async {
    final rig = await start(
        cachedA: _snapshot('A', messages: [_message(1, null)]),
        selectedGroup: 1);
    rig.a.snapshot = _snapshot('A', version: 2, messages: [
      _message(1, null),
      _message(2, null),
      _message(3, 1),
      _message(4, 2),
    ]);
    await rig.controller.sync();
    expect(rig.controller.visibleMessages.map((m) => m.id), [1, 2, 3]);
    expect(rig.notifications.shownIds, [2, 3]);
  });

  test(
      'teacher notifications use fresh group membership and exclude own messages',
      () async {
    final rig = await start(
        cachedA: _snapshot('A', messages: [_message(1, null)]),
        selectedGroup: 1,
        user: _staff(10),
        token: 'token-A',
        lastSeen: 1);
    rig.a.snapshot = _snapshot('A', version: 2, teacherGroups: {
      1,
      2
    }, messages: [
      _message(1, null),
      _message(2, null),
      _message(3, 1),
      _message(4, 2),
      _message(5, 3),
      _message(6, null, sender: 10),
    ]);
    await rig.controller.sync();
    expect(rig.controller.visibleMessages.map((m) => m.id), [1, 2, 3, 4, 6]);
    expect(rig.notifications.shownIds, [2, 3, 4]);
    expect(rig.controller.unreadMessagesCount, 4);
    await rig.controller.markMessagesSeen();
    expect(rig.controller.unreadMessagesCount, 0);
  });

  test(
      'failed first sync does not turn initial message history into notifications',
      () async {
    final rig = await start(selectedGroup: 1);
    rig.a.snapshot =
        _snapshot('A', messages: [_message(1, null), _message(2, 1)]);
    rig.a.onVersion = () => Future.error(ApiException('offline'));
    await rig.controller.sync();
    expect(rig.controller.lastSyncOk, isFalse);
    expect(rig.controller.lastSyncAt, isNotNull);
    rig.a.onVersion = null;
    await rig.controller.sync();
    expect(rig.controller.lastSyncOk, isTrue);
    expect(rig.notifications.shownIds, isEmpty);
    rig.a.snapshot = _snapshot('A', version: 2, messages: [
      _message(1, null),
      _message(2, 1),
      _message(3, 1),
    ]);
    await rig.controller.sync();
    expect(rig.notifications.shownIds, [3]);
  });

  test('resuming triggers a sync while paused and disposed states do not',
      () async {
    final rig = await start(cachedA: _snapshot('A'));
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(rig.a.versionCalls, 0);
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await rig.controller.sync();
    expect(rig.a.versionCalls, 1);
    rig.dispose();
    rig.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(rig.a.versionCalls, 1);
  });

  test(
      'disposing during an in-flight sync discards completion without notifications',
      () async {
    final cached = _snapshot('A');
    final rig = await start(cachedA: cached);
    final lateSnapshot = Completer<ScheduleData>();
    rig.a.onSchedule = () => lateSnapshot.future;
    var changes = 0;
    rig.controller.addListener(() {
      changes++;
    });
    final pending = rig.controller.sync(force: true);
    await _until(() => rig.a.scheduleCalls == 1);
    final changesBeforeDispose = changes;
    rig.dispose();
    lateSnapshot
        .complete(_snapshot('A', version: 2, messages: [_message(2, null)]));
    await pending;
    expect(changes, changesBeforeDispose);
    expect(rig.controller.data.version, 1);
    expect(rig.notifications.shownIds, isEmpty);
    expect((await rig.store.forServer(_urlA)).loadCachedSchedule().version, 1);
  });
}
