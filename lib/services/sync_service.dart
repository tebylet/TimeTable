import 'dart:async';
import 'activity_reporter.dart';
import 'package:in_app_update/in_app_update.dart' as play;
import 'package:url_launcher/url_launcher.dart';
import 'update_channel.dart';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../localization.dart';
import '../models/app_message.dart';
import '../models/app_user.dart';
import '../models/exam_entry.dart';
import '../models/schedule_data.dart';
import '../models/schedule_entry.dart';
import '../models/group.dart';
import '../theme.dart';
import 'api_client.dart';
import 'local_store.dart';
import 'notification_service.dart';
import 'pinned_http.dart';
import 'server_connection.dart';
import 'update_installer.dart';
import 'update_service.dart';

/// Встроенный адрес сервера; ручная настройка подключения в приложении не нужна.
const String defaultServerUrl = 'http://80.242.59.206:3000';

/// Центральный объект состояния приложения: хранит расписание, выбранную
/// группу и адрес сервера, умеет синхронизироваться с сервером, если есть
/// интернет, и всегда доступен для отображения из локального кэша.
class ScheduleController extends ChangeNotifier with WidgetsBindingObserver {
  late LocalStore _store;
  late ApiClient _api;
  late UpdateService _updateApi;
  ActivityReporter? _activity;
  String? _installationId;
  final NotificationService _notifications;
  final ApiClient Function(String, LocalStore) _apiFactory;
  final Duration pollInterval;
  Timer? _syncTimer;
  Future<void>? _syncFuture;
  Future<void>? _connectionChange;
  bool _changingConnection = false;
  bool _pendingForce = false;
  bool _disposed = false;
  bool _backgroundEnabled = true;
  int _generation = 0;

  ScheduleData data = ScheduleData.empty();
  int? selectedGroupId;
  String serverUrl = defaultServerUrl;
  bool isSyncing = false;
  bool lastSyncOk = false;
  DateTime? lastSyncAt;
  String? lastError;
  // true, если последняя ошибка синхронизации — именно несовпадение
  // TLS-сертификата сервера (см. ApiException.certificateMismatch), а не
  // обычная сетевая проблема. Settings-экран в этом случае показывает
  // отдельную подсказку с кнопкой "обновить доверенный сертификат" вместо
  // обычного "нет связи с сервером" (см. retrustServerCertificate ниже).
  bool lastErrorIsCertificateMismatch = false;
  bool lastErrorIsServerIdentityMismatch = false;
  AppThemeVariant themeVariant = AppThemeVariant.dark;
  AppLocale locale = AppLocale.ru;
  bool _initialized = false;

  // Установленная версия приложения (из package_info_plus) и результат
  // последней проверки обновлений на сервере.
  String installedVersionName = '';
  int installedVersionCode = 0;
  bool isCheckingUpdate = false;
  bool hasCheckedUpdate = false;
  bool updateAvailable = false;
  bool updateCheckFailed = false;
  AppUpdateInfo? latestUpdate;
  String _packageName = '';
  final UpdateChannel updateChannel;
  ScheduleController(
      {UpdateChannel? channel,
      ApiClient Function(String, LocalStore)? apiFactory,
      NotificationService? notifications,
      this.pollInterval = const Duration(seconds: 30)})
      : updateChannel = channel ?? currentUpdateChannel,
        _apiFactory = apiFactory ??
            ((url, store) => ApiClient(baseUrl: url, store: store)),
        _notifications = notifications ?? NotificationService();

  String get activeServerUrl => _initialized ? _api.activeBaseUrl : serverUrl;
  List<String> get backupServerAddresses =>
      _initialized ? _api.connectionAddresses : const [];
  String? get serverIdentity => _initialized ? _api.serverId : null;
  bool get hasStaffSchedule =>
      (appUser?.role == AppRole.teacher && appUser?.teacherId != null) ||
      (appUser?.role == AppRole.coordinator &&
          appUser?.facultyId != null &&
          appUser?.courseNumber != null);
  List<Group> get messageTargetGroups => appUser?.role == AppRole.coordinator
      ? data.groups
          .where((group) =>
              group.facultyId == appUser!.facultyId &&
              group.courseNumber == appUser!.courseNumber)
          .toList()
      : data.groups;
  List<ScheduleEntry> entriesOnDate(DateTime date) {
    if (appUser?.role == AppRole.coordinator) {
      return data.entriesOnDate(date,
          groupIds: messageTargetGroups.map((group) => group.id).toSet());
    }
    if (appUser?.role == AppRole.teacher) {
      return data.entriesOnDate(date, teacherId: appUser!.teacherId ?? -1);
    }
    return data.entriesOnDate(date,
        groupId: selectedGroupId, subgroupFor: subgroupPreferenceFor);
  }

  /// Dated exams use the same group, instructor, or course scope as classes.
  /// Past exams stay available for calendar navigation and subject lookup.
  List<ExamEntry> get visibleExams {
    if (appUser?.role == AppRole.teacher) {
      return data.examsForTeacher(appUser!.teacherId ?? -1);
    }
    if (appUser?.role == AppRole.coordinator) {
      final groupIds = messageTargetGroups.map((group) => group.id).toSet();
      return List.unmodifiable(
          data.exams.where((exam) => groupIds.contains(exam.groupId)));
    }
    return data.examsForGroup(selectedGroupId ?? -1);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool get canMoveToGooglePlay {
    final url = latestUpdate?.migrationUrl ?? '';
    return updateChannel == UpdateChannel.website &&
        isAllowedStoreUrl(url, UpdateChannel.googlePlay) &&
        Uri.parse(url).queryParameters['id'] == _packageName;
  }

  bool get supportsUpdates => updateChannel != UpdateChannel.unsupported;
  bool get showUpdateBanner =>
      updateAvailable &&
      installPhase != InstallPhase.downloading &&
      (_store.updateReminderUntil?.isAfter(DateTime.now()) != true ||
          _store.updateReminderBuild != latestUpdate?.versionCode);
  String get updateActionLabel => installPhase == InstallPhase.ready
      ? Strings.finishUpdate
      : switch (updateChannel) {
          UpdateChannel.website => Strings.downloadAndInstall,
          UpdateChannel.googlePlay => Strings.updateWithGooglePlay,
          UpdateChannel.testFlight => Strings.openTestFlight,
          _ => Strings.openAppStore,
        };

  Future<void> remindUpdateLater() async {
    await _store.snoozeUpdate(latestUpdate?.versionCode ?? 0);
    notifyListeners();
  }

  Future<void> openGooglePlay() async {
    if (_packageName.isEmpty ||
        !await launchUrl(
            Uri.https(
                'play.google.com', '/store/apps/details', {'id': _packageName}),
            mode: LaunchMode.externalApplication)) {
      throw StateError('Cannot open Google Play');
    }
  }

  // Состояние скачивания/установки обновления (см. installUpdate()).
  InstallPhase? installPhase;
  double? installPercent;
  String? installError;

  // Подгруппы (чередование чётная/нечётная неделя, см. schedule_entry.dart
  // occursOn() и setSubgroupPreference() ниже). Ключ — "groupId:day:period".
  Map<String, WeekParity> _subgroupPreferences = {};

  // Вход преподавателя/администратора (см. LOGIN_SECTION ниже). appUser ==
  // null означает, что в приложении никто не вошёл — обычный режим студента.
  String? _appAuthToken;
  AppUser? appUser;
  bool isLoggingIn = false;
  String? loginError;
  bool loginLocked = false;

  // Id последнего сообщения, которое пользователь уже видел (открывал вкладку
  // "Чат") — см. LocalStore.lastSeenMessageId и unreadMessagesCount/
  // markMessagesSeen ниже.
  int? _lastSeenMessageId;

  bool get isReady => _initialized;

  Future<void> init({bool startBackgroundTasks = true}) async {
    final globalStore = await LocalStore.open();
    final savedServerUrl = globalStore.serverUrl;
    // Старый адрес Android-эмулятора больше не является рабочим дефолтом.
    // Ранее настроенные пользователем серверы сохраняют собственные профили.
    serverUrl =
        savedServerUrl == null || savedServerUrl == 'http://10.0.2.2:3000'
            ? defaultServerUrl
            : normalizeServerUrl(savedServerUrl);
    _store = await globalStore.forServer(serverUrl);
    _backgroundEnabled = startBackgroundTasks;
    _api = _apiFactory(serverUrl, _store);
    _updateApi = UpdateService(baseUrl: serverUrl, store: _store, api: _api);
    data = await _store.loadCachedScheduleAsync();
    selectedGroupId = _store.selectedGroupId;
    lastSyncOk = _store.lastSyncOk;
    lastSyncAt = _store.lastSyncAt;
    themeVariant = AppThemeVariantX.fromName(_store.themeVariant);
    AppColors.current = themeVariant.palette;
    locale = AppLocaleX.fromName(_store.locale);
    Strings.current = locale;
    _subgroupPreferences = _store.subgroupPreferences.map(
      (key, value) => MapEntry(key, weekParityFromString(value)),
    );
    _appAuthToken = _store.appAuthToken;
    appUser = _store.appAuthUser;
    _lastSeenMessageId = _store.lastSeenMessageId;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _packageName = packageInfo.packageName;
      installedVersionName = packageInfo.version;
      installedVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
    } catch (_) {
      // На случай, если плагин недоступен на какой-то платформе — тогда
      // просто не будем предлагать обновления, остальное приложение работает.
    }

    _installationId = await _store.installationId();
    if (_disposed) {
      _api.close();
      _updateApi.close();
      return;
    }
    _configureActivity();
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
    notifyListeners();

    // Проверяем сервер в фоне — если интернета/сервера нет, приложение уже
    // отрисовано на основе кэша и просто останется с ним работать.
    if (startBackgroundTasks && !_disposed) {
      _fireAndForget(_notifications.init());
      _fireAndForget(sync());
      _fireAndForget(checkForUpdate());
      _startPolling();
      if (_appAuthToken != null) _fireAndForget(_validateAppAuth());
    }
  }

  void _configureActivity() {
    _activity?.setForeground(false);
    _activity?.dispose();
    final api = _api;
    final installationId = _installationId;
    if (installationId == null || !_backgroundEnabled || _disposed) return;
    _activity = ActivityReporter(
        send: (active) => api.sendActivity(installationId, active));
    _activity!.setForeground(WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
  }

  void _startPolling() {
    _syncTimer?.cancel();
    if (!_backgroundEnabled || _disposed || pollInterval <= Duration.zero) {
      return;
    }
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    _syncTimer = Timer.periodic(pollInterval, (_) => _fireAndForget(sync()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _activity?.setForeground(state == AppLifecycleState.resumed);
    _syncTimer?.cancel();
    if (state == AppLifecycleState.resumed && _initialized && !_disposed) {
      _fireAndForget(sync());
      _fireAndForget(_validateAppAuth());
      _startPolling();
      if (updateChannel == UpdateChannel.googlePlay) {
        _fireAndForget(checkForUpdate());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _syncTimer?.cancel();
    _activity?.dispose();
    if (_initialized) {
      _api.close();
      _updateApi.close();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> checkForUpdate() async {
    if (!supportsUpdates || isCheckingUpdate || isInstallingUpdate) return;
    final generation = _generation;
    isCheckingUpdate = true;
    updateCheckFailed = false;
    notifyListeners();
    try {
      if (updateChannel == UpdateChannel.googlePlay) {
        // Play determines availability for this user, device and release track.
        final info = await play.InAppUpdate.checkForUpdate();
        if (_disposed || generation != _generation) return;
        updateAvailable = info.updateAvailability ==
                play.UpdateAvailability.updateAvailable ||
            info.installStatus == play.InstallStatus.downloaded;
        if (info.installStatus == play.InstallStatus.downloaded) {
          installPhase = InstallPhase.ready;
        }
        latestUpdate = updateAvailable
            ? AppUpdateInfo(
                versionCode: info.availableVersionCode ?? installedVersionCode,
                versionName: '',
                distribution: 'googlePlay')
            : null;
      } else {
        final source = _updateApi;
        final info = await source.fetchLatestVersion(updateChannel);
        if (!identical(source, _updateApi)) return;
        latestUpdate = info;
        updateAvailable =
            info.availableFor(updateChannel, installedVersionCode);
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        updateCheckFailed = true;
        updateAvailable = false;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        isCheckingUpdate = false;
        hasCheckedUpdate = true;
        notifyListeners();
      }
    }
  }

  bool get isInstallingUpdate =>
      installPhase == InstallPhase.downloading ||
      installPhase == InstallPhase.installing;

  Future<void> installUpdate() async {
    if (isInstallingUpdate || isCheckingUpdate || !updateAvailable) return;
    installError = null;
    if (updateChannel == UpdateChannel.googlePlay &&
        installPhase == InstallPhase.ready) {
      installPhase = InstallPhase.installing;
      notifyListeners();
      try {
        await play.InAppUpdate.completeFlexibleUpdate();
        installPhase = InstallPhase.done;
      } catch (_) {
        installPhase = InstallPhase.error;
      }
      notifyListeners();
      return;
    }
    installPhase = InstallPhase.downloading;
    installPercent = null;
    notifyListeners();
    try {
      if (updateChannel == UpdateChannel.website) {
        final info = latestUpdate!;
        if (!info.availableFor(updateChannel, installedVersionCode)) {
          throw StateError('Invalid APK release');
        }
        await for (final progress in UpdateInstaller()
            .install(_updateApi.downloadUrl(info), info.sha256!, _store)) {
          installPhase = progress.phase;
          installPercent = progress.percent;
          installError = progress.errorMessage;
          notifyListeners();
        }
      } else if (updateChannel == UpdateChannel.googlePlay) {
        // Refresh before every attempt: Play update objects are single-use.
        final info = await play.InAppUpdate.checkForUpdate();
        if (info.installStatus == play.InstallStatus.downloaded) {
          installPhase = InstallPhase.ready;
        } else if (info.flexibleUpdateAllowed) {
          final result = await play.InAppUpdate.startFlexibleUpdate();
          installPhase = switch (result) {
            play.AppUpdateResult.success => InstallPhase.ready,
            play.AppUpdateResult.userDeniedUpdate => InstallPhase.canceled,
            play.AppUpdateResult.inAppUpdateFailed => InstallPhase.error,
          };
        } else {
          await openGooglePlay();
          installPhase = InstallPhase.done;
        }
      } else {
        final url = latestUpdate?.storeUrl ?? '';
        if (!isAllowedStoreUrl(url, updateChannel) ||
            !await launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication)) {
          throw StateError('Cannot open store');
        }
        installPhase = InstallPhase.done;
      }
    } catch (e) {
      installPhase = InstallPhase.error;
      installError = e.toString();
    }
    notifyListeners();
  }

  Future<void> setThemeVariant(AppThemeVariant variant) async {
    themeVariant = variant;
    AppColors.current = variant.palette;
    await _store.setThemeVariant(variant.name);
    notifyListeners();
  }

  Future<void> setLocale(AppLocale value) async {
    locale = value;
    Strings.current = value;
    await _store.setLocale(value.name);
    notifyListeners();
  }

  Future<void> _queueConnectionChange(Future<void> Function() change) {
    final previous = _connectionChange ?? Future<void>.value();
    late final Future<void> next;
    next = previous.catchError((_) {}).then((_) => change()).whenComplete(() {
      if (identical(_connectionChange, next)) _connectionChange = null;
    });
    _connectionChange = next;
    return next;
  }

  Future<void> setServerUrl(String url) {
    final normalized = normalizeServerUrl(url);
    return _queueConnectionChange(() => _changeServerUrl(normalized));
  }

  Future<void> _changeServerUrl(String url) async {
    if (isInstallingUpdate || _disposed) return;
    url = normalizeServerUrl(url);
    final resetIdentity = lastErrorIsServerIdentityMismatch;
    if (url == serverUrl && !resetIdentity) {
      await sync(force: true);
      return;
    }
    _changingConnection = true;
    _generation++;
    _syncFuture = null;
    _pendingForce = false;
    isSyncing = false;
    _activity?.dispose();
    _api.close();
    _updateApi.close();
    final nextStore = await _store.forServer(url);
    if (_disposed) return;
    if (resetIdentity && url == serverUrl) await nextStore.clearServerData();
    await nextStore.setServerUrl(url);
    final nextData = await nextStore.loadCachedScheduleAsync();
    if (_disposed) return;
    // Install the entire profile together; old UI callbacks never see a new
    // store paired with the previous server's client or credentials.
    _store = nextStore;
    serverUrl = url;
    _api = _apiFactory(url, _store);
    _updateApi = UpdateService(baseUrl: url, store: _store, api: _api);
    data = nextData;
    selectedGroupId = _store.selectedGroupId;
    _subgroupPreferences = _store.subgroupPreferences
        .map((key, value) => MapEntry(key, weekParityFromString(value)));
    _appAuthToken = _store.appAuthToken;
    appUser = _store.appAuthUser;
    _lastSeenMessageId = _store.lastSeenMessageId;
    lastSyncAt = _store.lastSyncAt;
    lastSyncOk = false;
    lastError = null;
    lastErrorIsCertificateMismatch = false;
    lastErrorIsServerIdentityMismatch = false;
    latestUpdate = null;
    updateAvailable = false;
    hasCheckedUpdate = false;
    isCheckingUpdate = false;
    isLoggingIn = false;
    _changingConnection = false;
    _configureActivity();
    notifyListeners();
    await sync(force: true);
    if (_appAuthToken != null) await _validateAppAuth();
  }

  /// Забывает запомненный сертификат текущего адреса сервера и пробует
  /// подключиться заново — при следующем удачном подключении сертификат,
  /// который сервер предъявит сейчас, будет запомнен снова (см.
  /// pinned_http.dart, модель доверия "первое подключение"). Нужно, если
  /// администратор перегенерировал сертификат сервера (например, после
  /// смены IP-адреса компьютера) и старый запомненный сертификат перестал
  /// совпадать — тогда обычная синхронизация начинает падать с
  /// certificateMismatch (см. lastErrorIsCertificateMismatch выше).
  Future<void> retrustServerCertificate() =>
      _queueConnectionChange(_retrustServerCertificate);

  Future<void> _retrustServerCertificate() async {
    final url = _api.connection.certificateFailureAddress ?? activeServerUrl;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return;
    await _store.clearPinnedCertificate(hostPortKey(uri));
    if (_disposed) return;
    _generation++;
    _syncFuture = null;
    _api.close();
    _api = _apiFactory(serverUrl, _store);
    _updateApi = UpdateService(baseUrl: serverUrl, store: _store, api: _api);
    _configureActivity();
    await sync(force: true);
  }

  Future<void> selectGroup(int groupId) async {
    selectedGroupId = groupId;
    _lastSeenMessageId = null;
    final store = _store;
    await store.clearLastSeenMessageId();
    await store.setSelectedGroupId(groupId);
    notifyListeners();
  }

  /// Ключ слота "день+пара" внутри группы — по нему занятие и его
  /// "напарник" с противоположной чётностью (если есть) считаются одним и
  /// тем же местом в расписании, между которым чередуются подгруппы.
  String _subgroupSlotKey(ScheduleEntry entry) =>
      '${entry.groupId}:${entry.dayOfWeek}:${entry.period}';

  /// true, если у этого занятия в том же слоте (тот же день и номер пары)
  /// есть "напарник" с противоположной чётностью недели — т.е. это не
  /// занятие "раз в две недели", а две разные подгруппы, чередующиеся по
  /// чётности. Только для таких занятий имеет смысл предлагать выбор
  /// подгруппы (см. subgroupPreferenceFor/setSubgroupPreference).
  bool hasSubgroupSplit(ScheduleEntry entry) => data.hasSubgroupSplit(entry);

  /// Подгруппа, выбранная пользователем для слота этого занятия (или null,
  /// если выбор не делали — тогда показывается то, что фактически совпадает
  /// с текущей чётностью недели, как раньше).
  WeekParity? subgroupPreferenceFor(ScheduleEntry entry) =>
      _subgroupPreferences[_subgroupSlotKey(entry)];

  /// Запоминает выбор подгруппы для слота этого занятия — только на этом
  /// телефоне (не на сервере, см. LocalStore.setSubgroupPreferences): у
  /// разных студентов одной группы бывают разные подгруппы. parity == null
  /// сбрасывает выбор обратно на "по факту недели".
  Future<void> setSubgroupPreference(
      ScheduleEntry entry, WeekParity? parity) async {
    final key = _subgroupSlotKey(entry);
    if (parity == null) {
      _subgroupPreferences.remove(key);
    } else {
      _subgroupPreferences[key] = parity;
    }
    await _store.setSubgroupPreferences(
      _subgroupPreferences.map((k, v) => MapEntry(k, v.name)),
    );
    notifyListeners();
  }

  /// Синхронизация с сервером: сначала лёгкая проверка версии, и только если
  /// она отличается от закэшированной (или кэш пуст) — скачивание всего
  /// расписания. force=true (например, при "потянуть вниз для обновления")
  /// всегда скачивает расписание заново.
  ///
  /// Заодно после скачивания сравнивает список сообщений со старым и
  /// показывает системное уведомление о каждом новом (см. NotificationService
  /// и _notifyNewMessages ниже) — это НЕ настоящий push: работает, только
  /// пока приложение открыто или недавно свёрнуто и само выполняет
  /// синхронизацию, а не в полностью закрытом виде. Полноценные push-уведомления
  /// потребовали бы Firebase Cloud Messaging (отдельный сервис, свой аккаунт
  /// разработчика и доступ сервера в интернет для отправки) — вне рамок
  /// текущей задачи, но это можно сделать отдельным шагом при необходимости.
  Future<void> sync({bool force = false}) {
    if (!_initialized || _disposed || _changingConnection) {
      return Future.value();
    }
    _pendingForce = _pendingForce || force;
    if (_syncFuture != null) return _syncFuture!;
    final generation = _generation;
    final source = _api;
    final store = _store;
    isSyncing = true;
    notifyListeners();
    late final Future<void> running;
    running = (() async {
      do {
        final forceRound = _pendingForce;
        _pendingForce = false;
        await _syncOnce(source, store, generation, forceRound);
      } while (_pendingForce && _current(generation, source));
    })()
        .whenComplete(() {
      if (identical(_syncFuture, running)) {
        _syncFuture = null;
        isSyncing = false;
        notifyListeners();
      }
    });
    _syncFuture = running;
    return running;
  }

  bool _current(int generation, ApiClient source) =>
      !_disposed && generation == _generation && identical(source, _api);

  Future<void> _syncOnce(
      ApiClient source, LocalStore store, int generation, bool force) async {
    lastError = null;
    lastErrorIsCertificateMismatch = false;
    lastErrorIsServerIdentityMismatch = false;
    var ok = false;
    try {
      final remoteVersion = await source.fetchVersion();
      if (!_current(generation, source)) return;
      if (force ||
          data.isEmpty ||
          remoteVersion != data.version ||
          source.serverId != data.serverId) {
        final hadSnapshot = data.fetchedAt.millisecondsSinceEpoch > 0;
        final previousIds = data.messages.map((m) => m.id).toSet();
        final fresh = await source.fetchSchedule();
        if (!_current(generation, source)) return;
        if (source.serverId != null && fresh.serverId != source.serverId) {
          throw ApiException('По этому адресу другой сервер',
              serverIdentityMismatch: true);
        }
        await store.saveSchedule(fresh);
        if (!_current(generation, source)) return;
        data = fresh;
        if (selectedGroupId != null &&
            data.groupById(selectedGroupId) == null) {
          selectedGroupId = null;
          await store.clearSelectedGroup();
          if (!_current(generation, source)) return;
        }
        if (hadSnapshot) _notifyNewMessages(fresh, previousIds);
      }
      ok = true;
      lastSyncOk = true;
    } catch (error) {
      if (!_current(generation, source)) return;
      lastSyncOk = false;
      lastError = error.toString();
      lastErrorIsCertificateMismatch =
          error is ApiException && error.certificateMismatch;
      lastErrorIsServerIdentityMismatch =
          error is ApiException && error.serverIdentityMismatch;
    } finally {
      if (_current(generation, source)) {
        await store.markSyncResult(ok);
        if (_current(generation, source)) lastSyncAt = DateTime.now();
      }
    }
  }

  List<AppMessage> _messagesFor(ScheduleData snapshot) {
    final user = appUser;
    if (user?.role == AppRole.coordinator) {
      final ids = snapshot.groups
          .where((g) =>
              g.facultyId == user!.facultyId &&
              g.courseNumber == user.courseNumber)
          .map((g) => g.id)
          .toSet();
      return snapshot.messages
          .where(
              (m) => m.targetGroupId == null || ids.contains(m.targetGroupId))
          .toList();
    }
    if (user?.role != AppRole.teacher || user?.teacherId == null) {
      return snapshot.messagesForGroup(selectedGroupId);
    }
    final groups = snapshot.groupIdsForTeacher(user!.teacherId!);
    return snapshot.messages
        .where(
            (m) => m.targetGroupId == null || groups.contains(m.targetGroupId))
        .toList();
  }

  void _notifyNewMessages(ScheduleData snapshot, Set<int> previousIds) {
    final myId = appUser?.id;
    for (final message in _messagesFor(snapshot)) {
      if (previousIds.contains(message.id) ||
          (myId != null && message.senderUserId == myId)) {
        continue;
      }
      _fireAndForget(_notifications.showMessage(
          id: message.id, title: message.senderName, body: message.body));
    }
  }

  // Бейдж непрочитанных на иконке чата (см. ScheduleScreen) — считает
  // сообщения этой группы (см. ScheduleData.messagesForGroup) с id больше
  // того, что пользователь уже видел в последний раз, когда открывал вкладку
  // "Чат" (см. markMessagesSeen).
  int get unreadMessagesCount {
    final seen = _lastSeenMessageId ?? 0;
    return visibleMessages.where((m) => m.id > seen).length;
  }

  /// Студент видит объявления своей группы, а преподаватель — объявления
  /// всех групп, в которых у него есть занятия. Общие объявления видят все.
  List<AppMessage> get visibleMessages => _messagesFor(data);

  /// Вызывается при открытии вкладки "Чат" — запоминает, что все текущие
  /// сообщения группы уже увидены, и на телефоне (переживает перезапуск
  /// приложения), и в памяти (чтобы бейдж сразу пропал).
  Future<void> markMessagesSeen() async {
    final relevant = visibleMessages;
    if (relevant.isEmpty) return;
    final maxId = relevant.map((m) => m.id).reduce((a, b) => a > b ? a : b);
    if (_lastSeenMessageId != null && maxId <= _lastSeenMessageId!) return;
    _lastSeenMessageId = maxId;
    await _store.setLastSeenMessageId(maxId);
    notifyListeners();
  }

  /// Сообщения, отправленные именно вошедшим в приложении преподавателем/
  /// администратором — см. AppMessage.senderUserId (у сообщений из
  /// веб-панели сервера это поле всегда null, там нет входа через
  /// app_users). Используется на вкладке "Отправленные мной" в ChatScreen,
  /// чтобы автор видел, что кому он отправил.
  List<AppMessage> get myMessages {
    final user = appUser;
    if (user == null) return const [];
    return data.messages.where((m) => m.senderUserId == user.id).toList();
  }

  /* ---------------------------------------------------------------------- */
  /* Вход преподавателей/администраторов в приложение                        */
  /* ---------------------------------------------------------------------- */
  //
  // Учётные записи заводятся в панели администратора сервера (вкладка
  // "Аккаунты") — в приложении их только используют. Логика блокировки после
  // трёх неверных попыток и хранение пароля хэшем — целиком на сервере (см.
  // server/src/services/appAuth.js), здесь только показываем то, что он
  // вернул.

  /// Проверяет при запуске, что сохранённый токен ещё действителен (сервер
  /// мог быть перезапущен с истёкшей сессией, либо администратор сменил
  /// пароль/логин или удалил аккаунт — тогда appAuth.logoutAllSessionsForUser
  /// на сервере сделает этот токен недействительным). Сетевая проблема не
  /// разлогинивает — токен и данные пользователя просто остаются как есть до
  /// следующей попытки.
  Future<void> _validateAppAuth() async {
    final token = _appAuthToken;
    if (token == null || _disposed) return;
    final source = _api;
    final store = _store;
    final generation = _generation;
    try {
      final user = await source.appMe(token);
      if (!_current(generation, source) || token != _appAuthToken) return;
      if (user == null) {
        _appAuthToken = null;
        appUser = null;
        await store.setAppAuthToken(null);
        await store.setAppAuthUser(null);
      } else {
        appUser = user;
        await store.setAppAuthUser(user);
      }
      notifyListeners();
    } catch (_) {
      // Сервер недоступен — оставляем как есть, попробуем при следующей
      // синхронизации.
    }
  }

  /// Возвращает true при успешном входе. При неудаче (неверный пароль или
  /// блокировка) возвращает false — подробности в loginError/loginLocked,
  /// готовые для показа пользователю (текст уже приходит с сервера, включая
  /// упоминание техподдержки при блокировке).
  Future<bool> loginStaff(String username, String password) async {
    if (isLoggingIn || !_initialized || _disposed) return false;
    isLoggingIn = true;
    loginError = null;
    loginLocked = false;
    notifyListeners();

    final source = _api;
    final store = _store;
    final generation = _generation;
    try {
      final result = await source.appLogin(username.trim(), password);
      if (!_current(generation, source)) return false;
      if (result.ok) {
        _appAuthToken = result.token;
        appUser = result.user;
        await store.setAppAuthToken(result.token);
        await store.setAppAuthUser(result.user);
        if (!_current(generation, source)) return false;
        _fireAndForget(sync(force: true));
        return true;
      }
      loginError = result.error;
      loginLocked = result.locked;
      return false;
    } catch (e) {
      if (!_current(generation, source)) return false;
      loginError = e.toString();
      return false;
    } finally {
      if (_current(generation, source)) {
        isLoggingIn = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> loadAdminStatistics() {
    if (appUser?.role != AppRole.admin || _appAuthToken == null) {
      throw ApiException('Доступ только для администратора');
    }
    return _api.adminStatistics(_appAuthToken!);
  }

  Future<Map<String, dynamic>> loadAdminAudit({int? before}) {
    if (appUser?.role != AppRole.admin || _appAuthToken == null) {
      throw ApiException('Доступ только для администратора');
    }
    return _api.adminAudit(_appAuthToken!, before: before);
  }

  Future<void> logoutStaff() async {
    final token = _appAuthToken;
    final source = _api;
    final store = _store;
    final generation = _generation;
    _appAuthToken = null;
    appUser = null;
    await store.setAppAuthToken(null);
    await store.setAppAuthUser(null);
    if (_current(generation, source)) notifyListeners();
    if (token != null) _fireAndForget(source.appLogout(token));
  }

  /* ---------------------------------------------------------------------- */
  /* Отмена занятий и сообщения группам (доступно вошедшим в приложении     */
  /* преподавателям/администраторам)                                        */
  /* ---------------------------------------------------------------------- */

  /// true, если вошедший пользователь может отменить/восстановить именно это
  /// занятие: админ — любое, преподаватель — только своё (по teacherId).
  bool canCancelLesson(ScheduleEntry entry) {
    final user = appUser;
    if (user == null) return false;
    if (user.role == AppRole.admin) return true;
    if (user.role == AppRole.coordinator) {
      final group = data.groupById(entry.groupId);
      return group != null &&
          group.facultyId == user.facultyId &&
          group.courseNumber == user.courseNumber;
    }
    return entry.teacherId != null && entry.teacherId == user.teacherId;
  }

  /// Отправка сообщений группам не ограничена ролью — доступна и
  /// администратору, и преподавателю, как только они вошли в приложении.
  bool get canSendMessages => appUser != null;

  bool canDeleteMessage(AppMessage message) =>
      appUser != null && message.senderUserId == appUser!.id;

  Future<void> deleteMessage(AppMessage message) async {
    final token = _appAuthToken;
    if (token == null) throw ApiException(Strings.notLoggedIn);
    if (!canDeleteMessage(message)) {
      throw ApiException(Strings.deleteOwnMessagesOnly);
    }
    final source = _api;
    final store = _store;
    final generation = _generation;
    await source.deleteMessage(token, message.id);
    // A snapshot requested before deletion must finish before we update the
    // local cache, otherwise its delayed response could restore the message.
    final pendingSync = _syncFuture;
    if (pendingSync != null) await pendingSync.catchError((_) {});
    if (!_current(generation, source) || token != _appAuthToken) return;
    data = data.withoutMessage(message.id);
    notifyListeners();
    await store.saveSchedule(data);
    if (_current(generation, source)) await sync(force: true);
  }

  Future<void> cancelLesson(ScheduleEntry entry, DateTime date,
      {String? reason}) async {
    final token = _appAuthToken;
    if (token == null) throw ApiException(Strings.notLoggedIn);
    await _api.cancelLesson(
        token, entry.id, entry.originalDate ?? ScheduleData.isoDate(date),
        reason: reason);
    await sync(force: true);
  }

  Future<void> restoreLesson(ScheduleEntry entry, DateTime date) async {
    final token = _appAuthToken;
    if (token == null) throw ApiException(Strings.notLoggedIn);
    await _api.restoreLesson(
        token, entry.id, entry.originalDate ?? ScheduleData.isoDate(date));
    await sync(force: true);
  }

  /// targetGroupId == null отправляет сообщение всем группам сразу.
  Future<void> sendMessage({int? targetGroupId, required String body}) async {
    final token = _appAuthToken;
    if (token == null) throw ApiException(Strings.notLoggedIn);
    await _api.sendMessage(token, targetGroupId: targetGroupId, body: body);
    await sync(force: true);
  }

  Future<void> saveLessonUpdate(
      ScheduleEntry entry, DateTime date, Map<String, dynamic> update) async {
    final token = _appAuthToken;
    if (token == null) throw ApiException(Strings.notLoggedIn);
    await _api.updateLesson(token, entry.id,
        {...update, 'date': entry.originalDate ?? ScheduleData.isoDate(date)});
    await sync(force: true);
  }

  Future<void> restoreLessonUpdate(ScheduleEntry entry, DateTime date) async {
    final token = _appAuthToken;
    if (token == null) throw ApiException(Strings.notLoggedIn);
    await _api.restoreLessonUpdate(
        token, entry.id, entry.originalDate ?? ScheduleData.isoDate(date));
    await sync(force: true);
  }
}

// Небольшой помощник вместо dart:async unawaited(), чтобы не тянуть лишний импорт.
void _fireAndForget(Future<void> future) {
  future.catchError((_) {});
}
