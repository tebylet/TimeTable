import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'local_store.dart';
import 'pinned_http.dart';
import 'update_channel.dart';

enum InstallPhase { downloading, installing, ready, done, canceled, error }

class InstallProgress {
  final InstallPhase phase;
  final double? percent;
  final String? errorMessage;
  const InstallProgress(this.phase, {this.percent, this.errorMessage});
}

// Native APK installation exists only in the temporary website flavor.
class UpdateInstaller {
  static const _channel = MethodChannel('para/website_update');

  Stream<InstallProgress> install(
      Uri url, String expectedHash, LocalStore store) async* {
    if (currentUpdateChannel != UpdateChannel.website) {
      yield const InstallProgress(InstallPhase.error);
      return;
    }
    final client = buildClientFor(url.origin, store);
    File? file;
    var handedToInstaller = false;
    try {
      final path = await _channel.invokeMethod<String>('prepare');
      if (path == null || path.isEmpty) {
        throw StateError('Installer did not provide a download path');
      }
      file = File(path);
      final request = http.Request('GET', url)..followRedirects = false;
      final response =
          await client.send(request).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final sink = file.openWrite();
      var received = 0;
      final progressClock = Stopwatch()..start();
      var lastProgressAt = 0;
      yield InstallProgress(InstallPhase.downloading,
          percent: response.contentLength == null ? null : 0);
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 30))) {
          received += chunk.length;
          if (received > 300 * 1024 * 1024) {
            throw const FormatException('APK too large');
          }
          sink.add(chunk);
          // Network chunks can arrive hundreds of times per second. Bound UI
          // notifications while preserving the final completion event.
          final now = progressClock.elapsedMilliseconds;
          if (now - lastProgressAt >= 200) {
            lastProgressAt = now;
            yield InstallProgress(InstallPhase.downloading,
                percent: response.contentLength == null ||
                        response.contentLength == 0
                    ? null
                    : (received * 100 / response.contentLength!).clamp(0, 100));
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      yield const InstallProgress(InstallPhase.downloading, percent: 100);
      final hash = await sha256.bind(file.openRead()).first;
      if (hash.toString() != expectedHash.toLowerCase()) {
        throw const FormatException('APK checksum mismatch');
      }
      yield const InstallProgress(InstallPhase.installing);
      await _channel.invokeMethod<void>('install');
      handedToInstaller = true;
      // The system installer opened; installation success is not assumed.
      yield const InstallProgress(InstallPhase.done);
    } on PlatformException catch (e) {
      yield InstallProgress(InstallPhase.error, errorMessage: e.code);
    } catch (e) {
      yield InstallProgress(InstallPhase.error, errorMessage: e.toString());
    } finally {
      client.close();
      if (!handedToInstaller && file != null && await file.exists()) {
        await file.delete();
      }
    }
  }
}
