import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ymtimetable/services/api_client.dart';
import 'package:ymtimetable/services/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'large snapshots survive isolate parsing, persistence and indexed reload',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store =
        await (await LocalStore.open()).forServer('https://large.test');
    final fixture = {
      'version': 42,
      'serverId': 'large-server',
      'semesterStartDate': '2026-09-01',
      'groups': [
        {'id': 1, 'name': 'Group 1'}
      ],
      'entries': [
        for (var id = 1; id <= 1000; id++)
          {
            'id': id,
            'groupId': 1,
            'teacherId': 7,
            'dayOfWeek': 1,
            'period': 1,
            'startTime': '09:00',
            'endTime': '10:20',
            'subject': 'Subject $id',
            'weekParity': 'all',
          }
      ],
      'messages': [],
      'cancelledLessons': [],
    };
    final encoded = jsonEncode(fixture);
    expect(encoded.length, greaterThan(65536));
    final api = ApiClient(
        baseUrl: 'https://large.test',
        store: store,
        clientFactory: (_) => MockClient((request) async => http.Response(
            request.url.path == '/api/version'
                ? jsonEncode({
                    'version': 42,
                    'serverId': 'large-server',
                    'connectionAddresses': []
                  })
                : encoded,
            200)));
    addTearDown(api.close);
    final snapshot = await api.fetchSchedule();
    expect(snapshot.entriesForTeacherOnDay(7, 1).length, 1000);
    await store.saveSchedule(snapshot);
    final restored = await store.loadCachedScheduleAsync();
    expect(restored.version, 42);
    expect(restored.serverId, 'large-server');
    expect(restored.entriesForGroup(1).length, 1000);
    expect(restored.groupIdsForTeacher(7), {1});
  });
}
