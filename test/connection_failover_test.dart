import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ymtimetable/services/api_client.dart';
import 'package:ymtimetable/services/local_store.dart';
import 'package:ymtimetable/services/server_connection.dart';

const primary = 'http://primary.example:3000';
const backup = 'http://backup.example:3000';
const identity = 'logical-server-a';
const user = {
  'id': 9,
  'username': 'teacher',
  'displayName': 'Teacher',
  'role': 'teacher',
  'teacherId': 3,
};

http.Response jsonResponse(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

http.Response metadata(
        {String? id = identity, List<Object?> addresses = const [backup]}) =>
    jsonResponse({
      'version': 7,
      if (id != null) 'serverId': id,
      'connectionAddresses': addresses,
    });

String? bearer(http.Request request) => request.headers['authorization'];

class TrackedClient extends http.BaseClient {
  final MockClient _delegate;
  int closes = 0;
  TrackedClient(Future<http.Response> Function(http.Request) handler)
      : _delegate = MockClient(handler);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _delegate.send(request);
  @override
  void close() {
    closes++;
    _delegate.close();
  }
}

class Network {
  final Future<http.Response> Function(http.Request) handler;
  final requests = <http.Request>[];
  final clients = <String, List<TrackedClient>>{};
  Network(this.handler);
  http.Client create(String origin) {
    final client = TrackedClient((request) async {
      requests.add(request);
      return handler(request);
    });
    (clients[origin] ??= []).add(client);
    return client;
  }
}

Future<LocalStore> profile([String origin = primary]) async =>
    (await LocalStore.open()).forServer(origin);

ApiClient clientFor(LocalStore store, Network network,
    {String origin = primary, Duration timeout = const Duration(seconds: 1)}) {
  final api = ApiClient(
      baseUrl: origin,
      store: store,
      timeout: timeout,
      clientFactory: network.create);
  addTearDown(api.close);
  return api;
}

void expectOnlyProbes(Iterable<http.Request> requests) {
  expect(requests, isNotEmpty);
  for (final request in requests) {
    expect(request.method, 'GET');
    expect(request.url.path, '/api/version');
    expect(bearer(request), isNull);
    expect(request.body, isEmpty);
    expect(request.followRedirects, isFalse);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('metadata advertisements persist and can change without a schedule bump',
      () async {
    final store = await profile();
    List<Object?> addresses = [backup, '$backup/', 'https://second.example'];
    final network = Network((request) async => metadata(addresses: addresses));
    final api = clientFor(store, network);
    expect(await api.fetchVersion(), 7);
    expect(store.serverId, identity);
    expect(store.connectionAddresses, [backup, 'https://second.example']);
    expect((await profile()).connectionAddresses, store.connectionAddresses);
    addresses = ['https://replacement.example'];
    expect(await api.fetchVersion(), 7);
    expect(api.connectionAddresses, ['https://replacement.example']);
    expect(store.connectionAddresses, ['https://replacement.example']);
    addresses = [];
    expect(await api.fetchVersion(), 7);
    expect(store.connectionAddresses, isEmpty);
    expectOnlyProbes(network.requests);
  });

  test('a restarted profile verifies backup identity before sending its bearer',
      () async {
    final store = await profile();
    var primaryDead = false;
    final network = Network((request) async {
      if (request.url.origin == primary && primaryDead) {
        throw const SocketException('primary unavailable');
      }
      if (request.url.path == '/api/version') return metadata();
      expect(request.url.origin, backup);
      expect(bearer(request), 'Bearer private-token');
      return jsonResponse({'user': user});
    });
    final original = clientFor(store, network);
    await original.fetchVersion();
    original.close();
    primaryDead = true;
    final restarted = clientFor(await profile(), network);
    expect((await restarted.appMe('private-token'))?.id, 9);
    expect(restarted.activeBaseUrl, backup);
    expect(store.activeServerUrl, backup);
    expectOnlyProbes(network.requests
        .where((request) => request.url.path == '/api/version'));
    expect(
        network.requests
            .where((request) => request.url.path == '/api/app-me')
            .single
            .url
            .origin,
        backup);
    expect(network.clients[primary]!.first.closes, greaterThanOrEqualTo(1));
  });

  test('an unrelated server receives neither stored bearer nor login password',
      () async {
    final store = await profile();
    await store.saveConnection(
        serverId: identity,
        addresses: [backup],
        activeUrl: primary,
        requiresHttps: false);
    final network = Network((request) async {
      if (request.url.origin == primary) {
        throw const SocketException('primary unavailable');
      }
      return metadata(id: 'unrelated-server');
    });
    final api = clientFor(store, network);
    final mismatch = isA<ApiException>().having(
        (error) => error.serverIdentityMismatch, 'identity mismatch', true);
    await expectLater(api.appMe('private-token'), throwsA(mismatch));
    await expectLater(
        api.appLogin('teacher', 'private-password'), throwsA(mismatch));
    expectOnlyProbes(network.requests);
    expect(store.serverId, identity);
  });

  test('an unbound advertised address cannot establish a profile identity',
      () async {
    final store = await profile();
    await store.saveConnection(
        serverId: null,
        addresses: [backup],
        activeUrl: primary,
        requiresHttps: false);
    final network = Network((request) async {
      if (request.url.origin == primary) {
        throw const SocketException('primary unavailable');
      }
      return metadata();
    });
    await expectLater(clientFor(store, network).appLogin('teacher', 'password'),
        throwsA(isA<ApiException>()));
    expectOnlyProbes(network.requests);
    expect(store.serverId, isNull);
  });

  test('legacy servers cannot advertise automatic failover without identity',
      () async {
    final store = await profile();
    final network = Network((request) async => metadata(id: null));
    final api = clientFor(store, network);
    expect(await api.fetchVersion(), 7);
    expect(api.serverId, isNull);
    expect(api.connectionAddresses, isEmpty);
    expect(store.connectionAddresses, isEmpty);
  });

  test('HTTPS profiles never fall back to advertised HTTP origins', () async {
    const securePrimary = 'https://primary.example:3443';
    final store = await profile(securePrimary);
    await store.saveConnection(
        serverId: identity,
        addresses: [backup],
        activeUrl: securePrimary,
        requiresHttps: true);
    final network = Network((request) async {
      throw const HandshakeException('certificate changed');
    });
    await expectLater(
        clientFor(store, network, origin: securePrimary).appMe('private-token'),
        throwsA(isA<ApiException>().having((error) => error.certificateMismatch,
            'certificate mismatch', true)));
    expect(network.requests.every((request) => request.url.scheme == 'https'),
        isTrue);
    expectOnlyProbes(network.requests);
  });

  test('an HTTPS upgrade remains enforced after reconnecting an HTTP primary',
      () async {
    const secureBackup = 'https://backup.example:3443';
    final store = await profile();
    await store.saveConnection(
        serverId: identity,
        addresses: [secureBackup],
        activeUrl: primary,
        requiresHttps: false);
    final network = Network((request) async {
      if (request.url.origin == primary) {
        throw const SocketException('primary unavailable');
      }
      if (request.url.path == '/api/version') {
        return metadata(addresses: [secureBackup]);
      }
      return jsonResponse({'user': user});
    });
    final api = clientFor(store, network);
    await api.appMe('private-token');
    expect(store.requiresHttps, isTrue);
    final beforeRestart = network.requests.length;
    final restarted = clientFor(await profile(), network);
    await restarted.appMe('private-token');
    expect(
        network.requests
            .skip(beforeRestart)
            .every((request) => request.url.origin == secureBackup),
        isTrue);
  });

  test('authentication refusals remain on the current server', () async {
    final store = await profile();
    final network = Network((request) async {
      if (request.url.path == '/api/version') return metadata();
      return jsonResponse(
          {'error': 'refused'}, request.url.path == '/api/app-me' ? 401 : 403);
    });
    final api = clientFor(store, network);
    await api.fetchVersion();
    expect(await api.appMe('expired-token'), isNull);
    await expectLater(
        api.adminStatistics('restricted-token'), throwsA(isA<ApiException>()));
    expect((await api.appLogin('teacher', 'wrong')).ok, isFalse);
    expect(network.requests.every((request) => request.url.origin == primary),
        isTrue);
    expect(
        network.requests
            .where((request) => request.url.path == '/api/version')
            .length,
        1);
  });

  test('ambiguous POST transport failure is never replayed to a backup',
      () async {
    final store = await profile();
    final network = Network((request) async {
      if (request.url.path == '/api/version') return metadata();
      throw const SocketException('connection dropped after accepting body');
    });
    final api = clientFor(store, network);
    await api.fetchVersion();
    await expectLater(api.sendMessage('private-token', body: 'Send once'),
        throwsA(isA<ApiException>()));
    final writes =
        network.requests.where((request) => request.method == 'POST');
    expect(writes.length, 1);
    expect(writes.single.url.origin, primary);
    expect(jsonDecode(writes.single.body)['body'], 'Send once');
    expect(network.requests.any((request) => request.url.origin == backup),
        isFalse);
  });

  test('a timed out POST is not retried when its eventual result is unknown',
      () async {
    final store = await profile();
    final completion = Completer<http.Response>();
    final network = Network((request) async {
      if (request.url.path == '/api/version') return metadata();
      return completion.future;
    });
    final api =
        clientFor(store, network, timeout: const Duration(milliseconds: 30));
    await api.fetchVersion();
    await expectLater(api.sendMessage('private-token', body: 'Send once'),
        throwsA(isA<ApiException>()));
    completion.complete(jsonResponse({'id': 12}, 201));
    expect(network.requests.where((request) => request.method == 'POST').length,
        1);
    expect(network.requests.any((request) => request.url.origin == backup),
        isFalse);
  });

  test('an unavailable snapshot GET retries a verified backup', () async {
    final store = await profile();
    final network = Network((request) async {
      if (request.url.path == '/api/version') return metadata();
      if (request.url.origin == primary) {
        return jsonResponse({'error': 'temporarily unavailable'}, 503);
      }
      return jsonResponse({'version': 7, 'serverId': identity});
    });
    final api = clientFor(store, network);
    await api.fetchVersion();
    final schedule = await api.fetchSchedule();
    expect(schedule.serverId, identity);
    expect(api.activeBaseUrl, backup);
    expect(
        network.requests
            .where((request) => request.url.path == '/api/schedule')
            .map((request) => request.url.origin),
        [primary, backup]);
    expectOnlyProbes(network.requests.where((request) =>
        request.url.origin == backup && request.url.path == '/api/version'));
  });

  test('concurrent first requests share one credential-free identity probe',
      () async {
    final store = await profile();
    final verification = Completer<http.Response>();
    final network = Network((request) async {
      if (request.url.path == '/api/version') return verification.future;
      if (request.url.path == '/api/app-me') {
        return jsonResponse({'user': user});
      }
      return jsonResponse({'token': 'new-token', 'user': user});
    });
    final api = clientFor(store, network);
    final me = api.appMe('private-token');
    final login = api.appLogin('teacher', 'private-password');
    await Future<void>.delayed(Duration.zero);
    expectOnlyProbes(network.requests);
    expect(network.requests.length, 1);
    verification.complete(metadata());
    expect((await me)?.id, 9);
    expect((await login).token, 'new-token');
    expect(
        network.requests
            .where((request) => request.url.path == '/api/version')
            .length,
        1);
    expect(network.clients[primary]!.length, 1);
  });

  test('pooled origin clients are reused and closed with their connection',
      () async {
    final store = await profile();
    final network = Network((request) async =>
        request.url.path == '/api/version' ? metadata() : jsonResponse({}));
    final api = clientFor(store, network);
    await api.fetchVersion();
    await api.fetchVersion();
    await api.getJson('/api/example');
    final pooled = network.clients[primary]!;
    expect(pooled.length, 1);
    expect(pooled.single.closes, 0);
    expect(
        network.requests.every((request) => !request.followRedirects), isTrue);
    api.close();
    expect(pooled.single.closes, 1);
    await expectLater(api.fetchVersion(), throwsA(isA<ApiException>()));
    expect(pooled.length, 1);
  });

  test('a removed backup is not recovered from the persisted active address',
      () async {
    final store = await profile();
    var primaryDead = true;
    var advertiseBackup = true;
    await store.saveConnection(
        serverId: identity,
        addresses: [backup],
        activeUrl: backup,
        requiresHttps: false);
    final network = Network((request) async {
      if (request.url.origin == primary && primaryDead) {
        throw const SocketException('primary unavailable');
      }
      return metadata(addresses: advertiseBackup ? [backup] : []);
    });
    final original = clientFor(store, network);
    await original.fetchVersion();
    expect(original.activeBaseUrl, backup);
    advertiseBackup = false;
    await original.fetchVersion();
    expect(store.connectionAddresses, isEmpty);
    expect(store.activeServerUrl, backup);
    final restartIndex = network.requests.length;
    await expectLater(clientFor(await profile(), network).fetchVersion(),
        throwsA(isA<ApiException>()));
    expect(
        network.requests
            .skip(restartIndex)
            .every((request) => request.url.origin == primary),
        isTrue);
    primaryDead = false;
  });

  test(
      'a recovered primary is retried when its active backup becomes unavailable',
      () async {
    final store = await profile();
    var primaryDead = true;
    var backupDead = false;
    await store.saveConnection(
        serverId: identity,
        addresses: [backup],
        activeUrl: primary,
        requiresHttps: false);
    final network = Network((request) async {
      if ((request.url.origin == primary && primaryDead) ||
          (request.url.origin == backup && backupDead)) {
        throw const SocketException('unavailable');
      }
      return metadata();
    });
    final api = clientFor(store, network);
    await api.fetchVersion();
    expect(api.activeBaseUrl, backup);
    primaryDead = false;
    backupDead = true;
    final recoveryIndex = network.requests.length;
    await api.fetchVersion();
    expect(api.activeBaseUrl, primary);
    expect(
        network.requests
            .skip(recoveryIndex)
            .map((request) => request.url.origin),
        [backup, primary]);
  });

  test('connection URL validation refuses credentials, paths and query strings',
      () {
    for (final address in [
      'https://user:password@example.com',
      'https://example.com/api',
      'https://example.com?token=secret',
      'https://example.com#fragment',
      'ftp://example.com',
      'https://example.com:0',
      'https://example.com:65536',
      'https://exa mple.com',
    ]) {
      expect(() => normalizeServerUrl(address), throwsFormatException,
          reason: address);
    }
    expect(normalizeServerUrl(' HTTPS://EXAMPLE.COM:443/ '),
        'https://example.com');
    expect(normalizeServerUrl('http://[::1]:3000/'), 'http://[::1]:3000');
  });
}
