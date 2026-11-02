import 'api_client.dart';
import 'local_store.dart';
import 'update_channel.dart';

class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String notes;
  final bool apkAvailable;
  final String? apkUrl;
  final String? sha256;
  final String? storeUrl;
  final String? migrationUrl;
  final String? distribution;
  final bool published;

  const AppUpdateInfo(
      {required this.versionCode,
      required this.versionName,
      this.notes = '',
      this.apkAvailable = false,
      this.apkUrl,
      this.sha256,
      this.storeUrl,
      this.migrationUrl,
      this.distribution,
      this.published = true});

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        versionCode: json['versionCode'] as int? ?? 0,
        versionName: json['versionName'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        apkAvailable: json['apkAvailable'] as bool? ?? false,
        apkUrl: json['apkUrl'] as String?,
        sha256: json['sha256'] as String?,
        storeUrl: json['storeUrl'] as String?,
        migrationUrl: json['migrationUrl'] as String?,
        distribution: json['distribution'] as String?,
        published: json['published'] as bool? ?? true,
      );

  bool availableFor(UpdateChannel channel, int installedBuild) {
    if (!published || installedBuild <= 0 || versionCode <= installedBuild) {
      return false;
    }
    if (channel == UpdateChannel.website) {
      return (distribution == null || distribution == 'website') &&
          apkAvailable &&
          apkUrl != null &&
          RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256 ?? '');
    }
    return distribution == channel.name &&
        isAllowedStoreUrl(storeUrl ?? '', channel);
  }
}

class UpdateCheckException implements Exception {
  final String message;
  UpdateCheckException(this.message);
  @override
  String toString() => message;
}

class UpdateService {
  final String baseUrl;
  final LocalStore store;
  late final ApiClient _api;
  final bool _ownsApi;
  UpdateService(
      {required this.baseUrl,
      required this.store,
      Duration timeout = const Duration(seconds: 6),
      ApiClient? api})
      : _ownsApi = api == null {
    _api = api ?? ApiClient(baseUrl: baseUrl, store: store, timeout: timeout);
  }

  Future<AppUpdateInfo> fetchLatestVersion(UpdateChannel channel) async =>
      AppUpdateInfo.fromJson(
          await _api.getJson('/api/app-version?distribution=${channel.name}'));

  void close() {
    if (_ownsApi) _api.close();
  }

  // Use the same pinned connection for metadata and APK. Never downgrade HTTPS.
  Uri downloadUrl(AppUpdateInfo info) {
    final base = Uri.parse('${_api.activeBaseUrl}/');
    final url = base.resolve(info.apkUrl!);
    if (url.origin != base.origin || !['http', 'https'].contains(url.scheme)) {
      throw UpdateCheckException('Недопустимый адрес APK');
    }
    return url;
  }
}
