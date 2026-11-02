import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Тонкая обёртка над flutter_local_notifications — показывает системное
/// уведомление о новом сообщении от преподавателя/администратора, пока
/// приложение открыто или было недавно свёрнуто (сама подписка на новые
/// сообщения — в ScheduleController.sync(), см. там подробный комментарий
/// про то, почему это НЕ настоящий push, а только локальное уведомление).
class NotificationService {
  static const _channelId = 'messages';
  static const _channelName = 'Сообщения';
  static const _channelDescription =
      'Новые сообщения от преподавателей и администраторов';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    try {
      await _plugin.initialize(settings);
      if (Platform.isAndroid) {
        // На Android 13+ показ уведомлений требует разового разрешения
        // пользователя — на более старых версиях этот вызов ничего не делает.
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    } catch (_) {
      // Уведомления — не критичная для работы приложения функция: если
      // плагин недоступен на какой-то платформе или разрешение не дали,
      // просто не будем их показывать, остальное приложение работает.
    }
  }

  Future<void> showMessage(
      {required int id, required String title, required String body}) async {
    if (!_initialized) return;
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);
    try {
      await _plugin.show(id, title, body, details);
    } catch (_) {
      // См. комментарий в init() — уведомления не должны ронять синхронизацию.
    }
  }
}
