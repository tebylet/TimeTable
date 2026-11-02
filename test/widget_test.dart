import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ymtimetable/services/local_store.dart';
import 'package:ymtimetable/services/update_channel.dart';
import 'package:ymtimetable/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('APK download preserves HTTPS and rejects a foreign origin', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    final service =
        UpdateService(baseUrl: 'https://school.example:3443', store: store);
    final info = AppUpdateInfo.fromJson(
        {'apkUrl': '/api/app-download', 'httpPort': 3000});
    expect(service.downloadUrl(info).toString(),
        'https://school.example:3443/api/app-download');
    final foreign = AppUpdateInfo.fromJson(
        {'apkUrl': 'http://school.example:3000/api/app-download'});
    expect(() => service.downloadUrl(foreign),
        throwsA(isA<UpdateCheckException>()));
  });
  test('APK releases never appear in store builds', () {
    final apk = AppUpdateInfo.fromJson({
      'versionCode': 20,
      'versionName': '2.0',
      'apkAvailable': true,
      'apkUrl': '/api/app-download',
      'sha256': 'a' * 64,
    });
    expect(apk.availableFor(UpdateChannel.website, 1), isTrue);
    for (final channel in [
      UpdateChannel.googlePlay,
      UpdateChannel.appStore,
      UpdateChannel.testFlight
    ]) {
      expect(apk.availableFor(channel, 1), isFalse);
    }
    expect(apk.availableFor(UpdateChannel.website, 20), isFalse);
    expect(apk.availableFor(UpdateChannel.website, 0), isFalse);
  });
  test('unpublished, foreign-channel and missing-hash releases are ignored',
      () {
    const draft = AppUpdateInfo(
        versionCode: 20,
        versionName: '2.0',
        distribution: 'appStore',
        storeUrl: 'https://apps.apple.com/app/id123',
        published: false);
    expect(draft.availableFor(UpdateChannel.appStore, 1), isFalse);
    const live = AppUpdateInfo(
        versionCode: 20,
        versionName: '2.0',
        distribution: 'appStore',
        storeUrl: 'https://apps.apple.com/app/id123');
    expect(live.availableFor(UpdateChannel.appStore, 1), isTrue);
    expect(live.availableFor(UpdateChannel.testFlight, 1), isFalse);
    const noHash = AppUpdateInfo(
        versionCode: 20,
        versionName: '2.0',
        apkAvailable: true,
        apkUrl: '/api/app-download');
    expect(noHash.availableFor(UpdateChannel.website, 1), isFalse);
  });
  test('store links are constrained to the correct HTTPS destination', () {
    expect(
        isAllowedStoreUrl(
            'https://apps.apple.com/by/app/para/id123', UpdateChannel.appStore),
        isTrue);
    expect(
        isAllowedStoreUrl('https://testflight.apple.com/join/AbCd123',
            UpdateChannel.testFlight),
        isTrue);
    for (final url in [
      'http://apps.apple.com/app/id123',
      'https://apps.apple.com.evil.test/app/id123',
      'https://user@apps.apple.com/app/id123',
      'https://apps.apple.com:444/app/id123',
      'https://testflight.apple.com/join/abc'
    ]) {
      expect(isAllowedStoreUrl(url, UpdateChannel.appStore), isFalse);
    }
  });
}
