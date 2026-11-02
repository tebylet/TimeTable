import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'local_store.dart';
import 'pinned_http.dart';

String normalizeServerUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      value.trim().length > 2048 ||
      RegExp(r'[\\\s@?#]').hasMatch(value.trim()) ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.port < 1 ||
      uri.port > 65535) {
    throw const FormatException(
        'Укажите адрес HTTP/HTTPS без пути, логина и параметров');
  }
  return uri.origin;
}

class ServerConnectionException implements Exception {
  final String message;
  final bool certificateMismatch;
  final bool identityMismatch;
  const ServerConnectionException(this.message,
      {this.certificateMismatch = false, this.identityMismatch = false});
  @override
  String toString() => message;
}

typedef ServerClientFactory = http.Client Function(String origin);

/// One logical server may advertise multiple addresses. Probe an address
/// without credentials before using it, and never replay a write after sending.
class ServerConnection {
  final String primary;
  final LocalStore store;
  final Duration timeout;
  final ServerClientFactory _factory;
  final Map<String, http.Client> _clients = {};
  final Map<String, DateTime> _failedUntil = {};
  late final http.Client client = _ConnectionClient(this);
  String? _serverId;
  List<String> _addresses = [];
  String? _active;
  bool _secure = false;
  bool _closed = false;
  Future<_VerifiedAddress>? _probing;
  String? lastFailedAddress;
  String? certificateFailureAddress;

  ServerConnection({
    required String baseUrl,
    required this.store,
    this.timeout = const Duration(seconds: 6),
    ServerClientFactory? clientFactory,
  })  : primary = normalizeServerUrl(baseUrl),
        _factory = clientFactory ?? ((url) => buildClientFor(url, store)) {
    _serverId = store.serverId;
    _addresses = _normalizeAddresses(store.connectionAddresses);
    _secure = primary.startsWith('https:') || store.requiresHttps;
    // Persisted address is a preference, not proof of identity. It is probed
    // again before credentials or application data are sent after restart.
  }

  String get activeUrl => _active ?? primary;
  String? get serverId => _serverId;
  List<String> get addresses => List.unmodifiable(_addresses);

  List<String> _normalizeAddresses(Iterable<dynamic> values) {
    final result = <String>[];
    for (final value in values.take(8)) {
      if (value is! String) continue;
      try {
        final url = normalizeServerUrl(value);
        if (!result.contains(url)) result.add(url);
      } on FormatException {
        // An older server or damaged preferences must not add unsafe URLs.
      }
    }
    return result;
  }

  Iterable<String> _candidates({Set<String> exclude = const {}}) sync* {
    final now = DateTime.now();
    final preferred = _active ?? store.activeServerUrl;
    final ordered = <String>[
      if (!(_failedUntil[primary]?.isAfter(now) ?? false)) primary,
      if (preferred != null &&
          (preferred == primary || _addresses.contains(preferred)))
        preferred,
      ..._addresses,
      primary,
    ];
    final seen = <String>{};
    for (final url in ordered) {
      if (!seen.add(url) || exclude.contains(url)) continue;
      if (_secure && !url.startsWith('https:')) continue;
      yield url;
    }
  }

  Future<http.Response> _perform(String origin, String method, Uri original,
      Map<String, String> headers, List<int> body) async {
    if (_closed) throw const ServerConnectionException('Подключение закрыто');
    final uri = Uri.parse(origin).replace(
        path: original.path, query: original.hasQuery ? original.query : null);
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers)
      ..bodyBytes = body;
    final pooled = _clients.putIfAbsent(origin, () => _factory(origin));
    try {
      return await (() async =>
              http.Response.fromStream(await pooled.send(request)))()
          .timeout(timeout);
    } on HandshakeException {
      certificateFailureAddress = origin;
      throw const ServerConnectionException(
          'Сертификат сервера изменился. Проверьте доверенный сертификат в настройках.',
          certificateMismatch: true);
    }
  }

  void _failed(String url) {
    lastFailedAddress = url;
    _failedUntil[url] = DateTime.now().add(const Duration(minutes: 1));
    _clients.remove(url)?.close();
    if (_active == url) _active = null;
  }

  Future<void> _accept(String url, http.Response response) async {
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data['version'] is! int) {
      throw const ServerConnectionException('Некорректный ответ сервера');
    }
    final id = data['serverId'] as String?;
    if ((_serverId != null && id != _serverId) ||
        (url != primary && (id == null || _serverId == null))) {
      throw const ServerConnectionException(
          'По этому адресу другой сервер. Сохраните адрес снова для смены сервера.',
          identityMismatch: true);
    }
    if (_closed) throw const ServerConnectionException('Подключение закрыто');
    _serverId = id;
    // Only a server with a stable identity may advertise automatic failover.
    _addresses = id == null
        ? []
        : _normalizeAddresses(data['connectionAddresses'] as List? ?? []);
    _active = url;
    certificateFailureAddress = null;
    _secure = _secure || url.startsWith('https:');
    _failedUntil.remove(url);
    await store.saveConnection(
        serverId: id,
        addresses: _addresses,
        activeUrl: url,
        requiresHttps: _secure);
  }

  Future<_VerifiedAddress> _probe({Set<String> exclude = const {}}) async {
    ServerConnectionException? securityFailure;
    Object? lastError;
    // Keep the candidate set stable while accepted metadata replaces addresses.
    final candidates = _candidates(exclude: exclude).toList();
    for (final url in candidates) {
      try {
        final response =
            await _perform(url, 'GET', Uri.parse('$url/api/version'), {}, []);
        if (response.statusCode != 200) {
          throw ServerConnectionException(
              'Сервер ответил с ошибкой ${response.statusCode}');
        }
        await _accept(url, response);
        return _VerifiedAddress(url, response);
      } on HandshakeException {
        certificateFailureAddress = url;
        securityFailure = const ServerConnectionException(
            'Сертификат сервера изменился. Проверьте доверенный сертификат в настройках.',
            certificateMismatch: true);
        _failed(url);
      } on ServerConnectionException catch (error) {
        if (error.identityMismatch || error.certificateMismatch) {
          securityFailure = error;
        }
        lastError = error;
        _failed(url);
      } catch (error) {
        lastError = error;
        _failed(url);
      }
    }
    throw securityFailure ??
        ServerConnectionException(
            'Не удалось связаться с сервером: ${lastError ?? 'нет доступных адресов'}');
  }

  Future<_VerifiedAddress> _select({Set<String> exclude = const {}}) async {
    while (_probing != null) {
      final result = await _probing!;
      if (!exclude.contains(result.origin)) return result;
    }
    final future = _probe(exclude: exclude);
    _probing = future;
    try {
      return await future;
    } finally {
      if (identical(_probing, future)) _probing = null;
    }
  }

  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    if (request.url.origin != primary) {
      throw const ServerConnectionException('Запрос к неизвестному серверу');
    }
    http.Response response;
    if (request.method == 'GET' && request.url.path == '/api/version') {
      response = (await _select()).response;
    } else {
      var verifiedOrigin = _active ?? (await _select()).origin;
      final attempted = <String>{};
      while (true) {
        final url = verifiedOrigin;
        attempted.add(url);
        try {
          response = await _perform(
              url, request.method, request.url, request.headers, body);
          if (request.method == 'GET' &&
              [502, 503, 504].contains(response.statusCode)) {
            throw ServerConnectionException(
                'Сервер недоступен (${response.statusCode})');
          }
          break;
        } catch (error) {
          _failed(url);
          if (request.method != 'GET' || attempted.length >= 9) rethrow;
          try {
            verifiedOrigin = (await _select(exclude: attempted)).origin;
          } catch (_) {
            if (error is ServerConnectionException &&
                error.certificateMismatch) {
              throw error;
            }
            rethrow;
          }
        }
      }
    }
    return http.StreamedResponse(
        Stream.value(response.bodyBytes), response.statusCode,
        contentLength: response.bodyBytes.length,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
        request: request);
  }

  void close() {
    _closed = true;
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }
}

class _ConnectionClient extends http.BaseClient {
  final ServerConnection connection;
  _ConnectionClient(this.connection);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      connection.send(request);
  @override
  void close() => connection.close();
}

class _VerifiedAddress {
  final String origin;
  final http.Response response;
  const _VerifiedAddress(this.origin, this.response);
}
