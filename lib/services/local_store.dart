import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/schedule_data.dart';

/// Обёртка над SharedPreferences — вся локально сохранённая информация:
/// адрес сервера, выбранная группа и последний скачанный снимок расписания
/// (чтобы приложение работало и без интернета).
class LocalStore {
  static const _keyServerUrl = 'server_url';
  static const _keyGroupId = 'selected_group_id';
  static const _keyScheduleCache = 'schedule_cache';
  static const _keyLastSyncAt = 'last_sync_at';
  static const _keyLastSyncOk = 'last_sync_ok';
  static const _keyThemeVariant = 'theme_variant';
  static const _keyLocale = 'app_locale';
  static const _keySubgroupPreferences = 'subgroup_preferences';
  static const _keyAppAuthToken = 'app_auth_token';
  static const _keyAppAuthUser = 'app_auth_user';
  static const _keyLastSeenMessageId = 'last_seen_message_id';
  static const _keyPinnedCertificates = 'pinned_certificates';

  final SharedPreferences _prefs;
  final String? _scope;
  LocalStore._(this._prefs, [this._scope]);

  String _profile(String key) =>
      _scope == null ? key : '$key@${Uri.encodeComponent(_scope)}';

  /// Each explicitly selected address has isolated offline data and credentials.
  /// Automatic backup addresses continue using the same profile.
  Future<LocalStore> forServer(String origin) async {
    final scoped = LocalStore._(_prefs, origin);
    if (!_prefs.containsKey('legacy_profile_migrated')) {
      for (final key in _serverKeys) {
        final value = _prefs.get(key);
        if (value is String) {
          await _prefs.setString(scoped._profile(key), value);
        }
        if (value is int) await _prefs.setInt(scoped._profile(key), value);
        if (value is bool) await _prefs.setBool(scoped._profile(key), value);
        if (value is List<String>) {
          await _prefs.setStringList(scoped._profile(key), value);
        }
        await _prefs.remove(key);
      }
      await _prefs.setBool('legacy_profile_migrated', true);
    }
    return scoped;
  }

  static const _serverKeys = [
    _keyGroupId,
    _keyScheduleCache,
    _keyLastSyncAt,
    _keyLastSyncOk,
    _keySubgroupPreferences,
    _keyAppAuthToken,
    _keyAppAuthUser,
    _keyLastSeenMessageId,
    'update_reminder_build',
    'update_reminder_until',
    'connection_server_id',
    'connection_addresses',
    'active_server_url',
    'connection_requires_https',
  ];

  Future<void> clearServerData() async {
    for (final key in _serverKeys) {
      await _prefs.remove(_profile(key));
    }
  }

  String? get serverId => _prefs.getString(_profile('connection_server_id'));
  List<String> get connectionAddresses =>
      _prefs.getStringList(_profile('connection_addresses')) ?? [];
  String? get activeServerUrl =>
      _prefs.getString(_profile('active_server_url'));
  bool get requiresHttps =>
      _prefs.getBool(_profile('connection_requires_https')) ?? false;

  Future<void> saveConnection(
      {required String? serverId,
      required List<String> addresses,
      required String activeUrl,
      required bool requiresHttps}) async {
    if (serverId != null) {
      await _prefs.setString(_profile('connection_server_id'), serverId);
    }
    await _prefs.setStringList(_profile('connection_addresses'), addresses);
    await _prefs.setString(_profile('active_server_url'), activeUrl);
    await _prefs.setBool(_profile('connection_requires_https'), requiresHttps);
  }

  static Future<LocalStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStore._(prefs);
  }

  int? get updateReminderBuild =>
      _prefs.getInt(_profile('update_reminder_build'));
  DateTime? get updateReminderUntil {
    final value = _prefs.getInt(_profile('update_reminder_until'));
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> snoozeUpdate(int build) async {
    await _prefs.setInt(_profile('update_reminder_build'), build);
    await _prefs.setInt(_profile('update_reminder_until'),
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch);
  }

  Future<String> installationId() async {
    final existing = _prefs.getString('anonymous_installation_id');
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    await _prefs.setString('anonymous_installation_id', id);
    return id;
  }

  String? get serverUrl => _prefs.getString(_keyServerUrl);
  Future<void> setServerUrl(String url) => _prefs.setString(_keyServerUrl, url);

  int? get selectedGroupId => _prefs.getInt(_profile(_keyGroupId));
  Future<void> setSelectedGroupId(int id) =>
      _prefs.setInt(_profile(_keyGroupId), id);
  Future<void> clearSelectedGroup() => _prefs.remove(_profile(_keyGroupId));

  ScheduleData loadCachedSchedule() {
    final raw = _prefs.getString(_profile(_keyScheduleCache));
    if (raw == null) return ScheduleData.empty();
    try {
      return ScheduleData.decode(raw);
    } catch (_) {
      return ScheduleData.empty();
    }
  }

  Future<ScheduleData> loadCachedScheduleAsync() async {
    final raw = _prefs.getString(_profile(_keyScheduleCache));
    if (raw == null) return ScheduleData.empty();
    try {
      return raw.length > 65536
          ? await compute(ScheduleData.decode, raw)
          : ScheduleData.decode(raw);
    } catch (_) {
      return ScheduleData.empty();
    }
  }

  Future<void> saveSchedule(ScheduleData data) async {
    final encoded = data.entries.length > 200
        ? await compute(_encodeSchedule, data)
        : data.encode();
    await _prefs.setString(_profile(_keyScheduleCache), encoded);
  }

  DateTime? get lastSyncAt {
    final ms = _prefs.getInt(_profile(_keyLastSyncAt));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get lastSyncOk => _prefs.getBool(_profile(_keyLastSyncOk)) ?? false;

  Future<void> markSyncResult(bool ok) async {
    await _prefs.setInt(
        _profile(_keyLastSyncAt), DateTime.now().millisecondsSinceEpoch);
    await _prefs.setBool(_profile(_keyLastSyncOk), ok);
  }

  String? get themeVariant => _prefs.getString(_keyThemeVariant);
  Future<void> setThemeVariant(String name) =>
      _prefs.setString(_keyThemeVariant, name);

  String? get locale => _prefs.getString(_keyLocale);
  Future<void> setLocale(String name) => _prefs.setString(_keyLocale, name);

  // Подгруппы (по чётности недели) — какую именно чётность показывать для
  // конкретного слота "группа:день:пара", если пользователь её выбрал (см.
  // ScheduleController.setSubgroupPreference). Только на этом телефоне —
  // у разных студентов одной группы могут быть разные подгруппы, поэтому
  // это не часть данных с сервера.
  Map<String, String> get subgroupPreferences {
    final raw = _prefs.getString(_profile(_keySubgroupPreferences));
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> setSubgroupPreferences(Map<String, String> prefs) =>
      _prefs.setString(_profile(_keySubgroupPreferences), jsonEncode(prefs));

  // Вход преподавателя/администратора (см. ScheduleController.loginStaff) —
  // токен и данные пользователя сохраняются на телефоне, чтобы не запрашивать
  // логин/пароль заново при каждом запуске приложения.
  String? get appAuthToken => _prefs.getString(_profile(_keyAppAuthToken));

  Future<void> setAppAuthToken(String? token) => token == null
      ? _prefs.remove(_profile(_keyAppAuthToken))
      : _prefs.setString(_profile(_keyAppAuthToken), token);

  AppUser? get appAuthUser {
    final raw = _prefs.getString(_profile(_keyAppAuthUser));
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> setAppAuthUser(AppUser? user) => user == null
      ? _prefs.remove(_profile(_keyAppAuthUser))
      : _prefs.setString(_profile(_keyAppAuthUser), jsonEncode(user.toJson()));

  // Id последнего сообщения, которое пользователь уже видел (открывал вкладку
  // "Чат") — по нему считается значок непрочитанных на иконке чата (см.
  // ScheduleController.unreadMessagesCount/markMessagesSeen). Id сообщений
  // растут монотонно (автоинкремент на сервере), поэтому простого числа
  // достаточно — не нужно хранить список прочитанных id по отдельности.
  int? get lastSeenMessageId => _prefs.getInt(_profile(_keyLastSeenMessageId));
  Future<void> clearLastSeenMessageId() =>
      _prefs.remove(_profile(_keyLastSeenMessageId));
  Future<void> setLastSeenMessageId(int id) =>
      _prefs.setInt(_profile(_keyLastSeenMessageId), id);

  // Самоподписанные сертификаты серверов, к которым приложение уже
  // подключалось по HTTPS с доверием — ключ "host:port", значение —
  // сертификат в формате PEM. Модель доверия — "довериться при первом
  // подключении" (TOFU), см. подробный комментарий в
  // services/pinned_http.dart. Для обычных http:// адресов не используется.
  Map<String, String> get pinnedCertificates {
    final raw = _prefs.getString(_keyPinnedCertificates);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> setPinnedCertificate(String hostPort, String pem) async {
    final current = Map<String, String>.from(pinnedCertificates);
    current[hostPort] = pem;
    await _prefs.setString(_keyPinnedCertificates, jsonEncode(current));
  }

  /// Забывает запомненный сертификат конкретного адреса — используется,
  /// когда администратор перегенерировал сертификат сервера (см.
  /// ScheduleController.retrustServerCertificate) и старый запомненный
  /// сертификат больше не совпадает с тем, что предъявляет сервер.
  Future<void> clearPinnedCertificate(String hostPort) async {
    final current = Map<String, String>.from(pinnedCertificates);
    current.remove(hostPort);
    await _prefs.setString(_keyPinnedCertificates, jsonEncode(current));
  }
}

String _encodeSchedule(ScheduleData data) => data.encode();
