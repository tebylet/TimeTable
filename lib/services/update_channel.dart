import 'dart:io';
import 'package:flutter/services.dart';

enum UpdateChannel { website, googlePlay, appStore, testFlight, unsupported }

// Android is selected by the native flavor; iOS defaults to App Store.
UpdateChannel get currentUpdateChannel {
  if (Platform.isAndroid) {
    return appFlavor == 'website'
        ? UpdateChannel.website
        : UpdateChannel.googlePlay;
  }
  if (Platform.isIOS) {
    return const String.fromEnvironment('IOS_DISTRIBUTION') == 'testFlight'
        ? UpdateChannel.testFlight
        : UpdateChannel.appStore;
  }
  return UpdateChannel.unsupported;
}

bool isAllowedStoreUrl(String value, UpdateChannel channel) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    return false;
  }
  return switch (channel) {
    UpdateChannel.googlePlay => uri.host == 'play.google.com' &&
        uri.path == '/store/apps/details' &&
        (uri.queryParameters['id']?.isNotEmpty ?? false),
    UpdateChannel.appStore =>
      uri.host == 'apps.apple.com' && RegExp(r'/id[0-9]+$').hasMatch(uri.path),
    UpdateChannel.testFlight => uri.host == 'testflight.apple.com' &&
        RegExp(r'^/join/[a-zA-Z0-9]+$').hasMatch(uri.path),
    _ => false,
  };
}
