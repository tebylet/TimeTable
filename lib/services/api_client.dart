import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_user.dart';
import '../models/schedule_data.dart';
import 'local_store.dart';
import 'server_connection.dart';

class ApiException implements Exception {
  final String message;
  // true, если запрос упал именно из-за несовпадения TLS-сертификата
  // сервера с тем, что было запомнено раньше (см. pinned_http.dart) — а не
  // из-за обычной сетевой проблемы. UI показывает в этом случае отдельную,
  // более полезную подсказку (см. ScheduleController.lastErrorIsCertificateMismatch
  // и settings_screen.dart) вместо общего "нет связи с сервером".
  final bool certificateMismatch;
  final bool serverIdentityMismatch;
  ApiException(this.message,
      {this.certificateMismatch = false, this.serverIdentityMismatch = false});
  @override
  String toString() => message;
}

/// Результат попытки входа преподавателя/администратора в приложение (см.
/// ApiClient.appLogin). error — уже готовый для показа пользователю текст с
/// сервера (в т.ч. про блокировку и число оставшихся попыток, см.
/// server/src/services/appAuth.js), locked — true, если вход временно
/// заблокирован из-за трёх неверных попыток подряд.
class AppLoginResult {
  final bool ok;
  final String? token;
  final AppUser? user;
  final String? error;
  final bool locked;

  AppLoginResult(
      {required this.ok,
      this.token,
      this.user,
      this.error,
      this.locked = false});
}

/// Тонкий клиент к REST API сервера расписания.
/// baseUrl — адрес сервера, например "https://192.168.1.50:3443" (или
/// "http://..." для старого сервера без HTTPS). store нужен для доверия
/// самоподписанному сертификату — см. pinned_http.dart.
class ApiClient {
  final String baseUrl;
  final LocalStore store;
  final Duration timeout;
  late final ServerConnection connection;

  ApiClient(
      {required this.baseUrl,
      required this.store,
      this.timeout = const Duration(seconds: 6),
      ServerClientFactory? clientFactory}) {
    connection = ServerConnection(
        baseUrl: baseUrl,
        store: store,
        timeout: timeout,
        clientFactory: clientFactory);
  }

  String get activeBaseUrl => connection.activeUrl;
  String? get serverId => connection.serverId;
  List<String> get connectionAddresses => connection.addresses;
  void close() => connection.close();

  Future<Map<String, dynamic>> getJson(String path) => _run((client) async {
        final response = await client.get(_uri(path));
        if (response.statusCode != 200) {
          throw ApiException('Сервер ответил с ошибкой ${response.statusCode}');
        }
        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      });

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Reuses verified connections until this server profile is replaced.
  Future<T> _run<T>(Future<T> Function(http.Client client) body) async {
    final client = connection.client;
    try {
      return await body(client);
    } on ApiException {
      rethrow;
    } on ServerConnectionException catch (error) {
      throw ApiException(error.message,
          certificateMismatch: error.certificateMismatch,
          serverIdentityMismatch: error.identityMismatch);
    } on HandshakeException {
      throw ApiException(
        'Сертификат сервера не подтверждён — возможно, он изменился. '
        'Обновите доверенный сертификат в настройках.',
        certificateMismatch: true,
      );
    } catch (e) {
      throw ApiException('Не удалось связаться с сервером: $e');
    }
  }

  /// Быстрая проверка версии расписания на сервере. Бросает [ApiException]
  /// при любой сетевой проблеме — вызывающий код в этом случае должен
  /// считать сервер недоступным и работать с локальным кэшем.
  Future<int> fetchVersion() {
    return _run((client) async {
      final res = await client.get(_uri('/api/version'));
      if (res.statusCode != 200) {
        throw ApiException('Сервер ответил с ошибкой ${res.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return data['version'] as int? ?? 0;
    });
  }

  Future<void> sendActivity(String installationId, bool active) =>
      _run((client) async {
        final response = await client.post(_uri('/api/activity'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'installationId': installationId, 'active': active}));
        if (response.statusCode != 204) {
          throw ApiException('Статистика недоступна');
        }
      });

  Future<Map<String, dynamic>> adminStatistics(String token) =>
      _adminGet('/api/admin/statistics', token);
  Future<Map<String, dynamic>> adminAudit(String token, {int? before}) =>
      _adminGet(
          '/api/admin/audit${before == null ? '' : '?before=$before'}', token);

  Future<Map<String, dynamic>> _adminGet(String path, String token) =>
      _run((client) async {
        final response =
            await client.get(_uri(path), headers: _authHeaders(token));
        if (response.statusCode != 200) {
          throw ApiException(
              response.statusCode == 401 || response.statusCode == 403
                  ? 'Доступ только для администратора. Войдите снова.'
                  : 'Не удалось загрузить данные');
        }
        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      });

  Future<ScheduleData> fetchSchedule() {
    return _run((client) async {
      final res = await client.get(_uri('/api/schedule'));
      if (res.statusCode != 200) {
        throw ApiException('Сервер ответил с ошибкой ${res.statusCode}');
      }
      return res.bodyBytes.length > 65536
          ? await compute(_decodeSchedule, res.bodyBytes)
          : _decodeSchedule(res.bodyBytes);
    });
  }

  /// Вход преподавателя/администратора. Не бросает исключение при неверном
  /// логине/пароле или блокировке — это ожидаемый результат, который экран
  /// входа должен показать пользователю (см. AppLoginResult.error/locked).
  /// Бросает [ApiException] только при настоящей сетевой проблеме.
  Future<AppLoginResult> appLogin(String username, String password) {
    return _run((client) async {
      final res = await client.post(
        _uri('/api/app-login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        return AppLoginResult(
          ok: true,
          token: data['token'] as String,
          user: AppUser.fromJson(data['user'] as Map<String, dynamic>),
        );
      }
      return AppLoginResult(
        ok: false,
        error: data['error'] as String? ?? 'Не удалось войти',
        locked: data['locked'] == true,
      );
    });
  }

  Future<void> appLogout(String token) async {
    try {
      await _run(
        (client) =>
            client.post(_uri('/api/app-logout'), headers: _authHeaders(token)),
      );
    } catch (_) {
      // Разлогинивание на сервере — best-effort: локально токен уже стёрт
      // вызывающим кодом (ScheduleController.logoutStaff), поэтому сетевая
      // проблема здесь не должна мешать пользователю выйти из приложения.
    }
  }

  /// Проверяет, что сохранённый токен ещё действителен, и возвращает
  /// актуальные данные пользователя. null — токен недействителен (истёк,
  /// либо аккаунт удалён/изменён администратором) и его нужно забыть.
  /// Бросает [ApiException] при сетевой проблеме — в этом случае токен
  /// трогать не нужно, сервер просто сейчас недоступен.
  Future<AppUser?> appMe(String token) {
    return _run((client) async {
      final res =
          await client.get(_uri('/api/app-me'), headers: _authHeaders(token));
      if (res.statusCode == 401) return null;
      if (res.statusCode != 200) {
        throw ApiException('Сервер ответил с ошибкой ${res.statusCode}');
      }
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return AppUser.fromJson(data['user'] as Map<String, dynamic>);
    });
  }

  Future<void> cancelLesson(String token, int entryId, String dateIso,
      {String? reason}) {
    return _run((client) async {
      final res = await client.post(
        _uri('/api/lessons/$entryId/cancel'),
        headers: _authHeaders(token),
        body:
            jsonEncode({'date': dateIso, if (reason != null) 'reason': reason}),
      );
      if (res.statusCode != 201) {
        throw ApiException(_errorFrom(res) ?? 'Не удалось отменить занятие');
      }
    });
  }

  Future<void> restoreLesson(String token, int entryId, String dateIso) {
    return _run((client) async {
      final res = await client.delete(
        _uri('/api/lessons/$entryId/cancel')
            .replace(queryParameters: {'date': dateIso}),
        headers: _authHeaders(token),
      );
      if (res.statusCode != 200) {
        throw ApiException(
            _errorFrom(res) ?? 'Не удалось восстановить занятие');
      }
    });
  }

  Future<void> deleteMessage(String token, int messageId) =>
      _run((client) async {
        final response = await client.delete(_uri('/api/messages/$messageId'),
            headers: _authHeaders(token));
        if (response.statusCode != 200) {
          throw ApiException(
              _errorFrom(response) ?? 'Не удалось удалить сообщение');
        }
      });

  Future<void> sendMessage(String token,
      {int? targetGroupId, required String body}) {
    return _run((client) async {
      final res = await client.post(
        _uri('/api/messages'),
        headers: _authHeaders(token),
        body: jsonEncode({'targetGroupId': targetGroupId, 'body': body}),
      );
      if (res.statusCode != 201) {
        throw ApiException(_errorFrom(res) ?? 'Не удалось отправить сообщение');
      }
    });
  }

  Future<void> updateLesson(
          String token, int entryId, Map<String, dynamic> update) =>
      _run((client) async {
        final response = await client.put(_uri('/api/lessons/$entryId/update'),
            headers: _authHeaders(token), body: jsonEncode(update));
        if (response.statusCode != 200) {
          throw ApiException(
              _errorFrom(response) ?? 'Не удалось изменить занятие');
        }
      });
  Future<void> restoreLessonUpdate(String token, int entryId, String date) =>
      _run((client) async {
        final response = await client.delete(
            _uri('/api/lessons/$entryId/update')
                .replace(queryParameters: {'date': date}),
            headers: _authHeaders(token));
        if (response.statusCode != 200) {
          throw ApiException(
              _errorFrom(response) ?? 'Не удалось восстановить расписание');
        }
      });

  String? _errorFrom(http.Response res) {
    try {
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return data['error'] as String?;
    } catch (_) {
      return null;
    }
  }
}

ScheduleData _decodeSchedule(List<int> bytes) {
  final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  return ScheduleData.fromJson(
      {...data, 'fetchedAt': DateTime.now().toIso8601String()});
}
