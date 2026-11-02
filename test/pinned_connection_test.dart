import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ymtimetable/services/api_client.dart';
import 'package:ymtimetable/services/local_store.dart';
import 'package:ymtimetable/services/pinned_http.dart';

// Flutter's widget binding installs an HTTP stub. This integration test needs
// real loopback sockets while retaining the production certificate checks.
class _RealHttpOverrides extends HttpOverrides {}

const _fixture = r'''
const https = require('node:https');
const crypto = require('node:crypto');
const readline = require('node:readline');
const selfsigned = require(process.argv[2]);
(async () => {
  const generate = () => selfsigned.generate([
    { name: 'commonName', value: 'localhost' },
  ], {
    algorithm: 'sha256', keySize: 2048,
    extensions: [
      { name: 'basicConstraints', cA: false },
      { name: 'keyUsage', digitalSignature: true, keyEncipherment: true },
      { name: 'extKeyUsage', serverAuth: true },
      { name: 'subjectAltName', altNames: [
        { type: 2, value: 'localhost' }, { type: 7, ip: '127.0.0.1' },
      ] },
    ],
  });
  const first = await generate();
  const second = await generate();
  const sockets = new Set();
  const server = https.createServer({ key: first.private, cert: first.cert }, (req, res) => {
    // Force every request to negotiate a new connection, proving that a reused
    // TOFU client trusts the pin it learned on its first handshake.
    res.writeHead(200, { 'Content-Type': 'application/json', Connection: 'close' });
    res.end(JSON.stringify({
      version: 9, serverId: 'tls-integration-server', connectionAddresses: [],
    }));
  });
  server.on('connection', socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  process.stdout.write(JSON.stringify({ port: server.address().port }) + '\n');
  readline.createInterface({ input: process.stdin }).on('line', command => {
    if (command === 'rotate') {
      server.setSecureContext({ key: second.private, cert: second.cert });
      server.setTicketKeys(crypto.randomBytes(48));
      for (const socket of sockets) socket.destroy();
      process.stdout.write('rotated\n');
    } else if (command === 'stop') {
      for (const socket of sockets) socket.destroy();
      server.close(() => process.exit(0));
    }
  });
})().catch(error => { console.error(error.message); process.exit(1); });
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'real TLS reuses TOFU trust, persists pins and requires explicit retrust',
      () async {
    SharedPreferences.setMockInitialValues({});
    final temporary = await Directory.systemTemp.createTemp('para-tls-mobile-');
    final script = File('${temporary.path}${Platform.pathSeparator}server.cjs');
    await script.writeAsString(_fixture);
    final selfsigned = Directory(
        '${Directory.current.parent.path}${Platform.pathSeparator}server${Platform.pathSeparator}node_modules${Platform.pathSeparator}selfsigned');
    final process = await Process.start('node', [script.path, selfsigned.path]);
    final errors = StringBuffer();
    final stderr = process.stderr.transform(utf8.decoder).listen(errors.write);
    final lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    final clients = <ApiClient>[];
    try {
      expect(
          await lines.moveNext().timeout(const Duration(seconds: 20)), isTrue,
          reason: errors.toString());
      final port = (jsonDecode(lines.current) as Map<String, dynamic>)['port'];
      final origin = 'https://127.0.0.1:$port';
      final key = hostPortKey(Uri.parse(origin));

      await HttpOverrides.runWithHttpOverrides(() async {
        final store = await LocalStore.open();
        var createdClients = 0;
        final first = ApiClient(
            baseUrl: origin,
            store: store,
            clientFactory: (url) {
              createdClients++;
              return buildClientFor(url, store);
            });
        clients.add(first);
        expect(await first.fetchVersion(), 9);
        final originalPin = store.pinnedCertificates[key];
        expect(originalPin, contains('BEGIN CERTIFICATE'));
        expect(await first.fetchVersion(), 9);
        expect(createdClients, 1);
        expect(store.pinnedCertificates[key], originalPin);
        first.close();

        final reopenedStore = await LocalStore.open();
        expect(reopenedStore.pinnedCertificates[key], originalPin);
        final reopened = ApiClient(baseUrl: origin, store: reopenedStore);
        clients.add(reopened);
        expect(await reopened.fetchVersion(), 9);

        process.stdin.writeln('rotate');
        await process.stdin.flush();
        expect(await lines.moveNext().timeout(const Duration(seconds: 10)),
            isTrue);
        expect(lines.current, 'rotated');
        await expectLater(
            reopened.fetchVersion(),
            throwsA(isA<ApiException>().having(
                (error) => error.certificateMismatch,
                'certificateMismatch',
                isTrue)));
        expect(reopenedStore.pinnedCertificates[key], originalPin);
        reopened.close();

        await reopenedStore.clearPinnedCertificate(key);
        final retrusted = ApiClient(baseUrl: origin, store: reopenedStore);
        clients.add(retrusted);
        expect(await retrusted.fetchVersion(), 9);
        final replacementPin = reopenedStore.pinnedCertificates[key];
        expect(replacementPin, contains('BEGIN CERTIFICATE'));
        expect(replacementPin, isNot(originalPin));
        expect(await retrusted.fetchVersion(), 9);
        expect(
            (await LocalStore.open()).pinnedCertificates[key], replacementPin);
      }, _RealHttpOverrides());
    } finally {
      for (final client in clients) {
        client.close();
      }
      process.stdin.writeln('stop');
      try {
        await process.stdin.flush();
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill();
        await process.exitCode;
      }
      await lines.cancel();
      await stderr.cancel();
      await temporary.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
