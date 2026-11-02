/// Сообщение от преподавателя/администратора студентам — либо всем группам
/// (targetGroupId == null), либо одной конкретной. Отображается в разделе
/// "Чат" (см. screens/chat_screen.dart) и приходит вместе с расписанием
/// (см. ScheduleData.messages), поэтому доставляется тем же механизмом
/// синхронизации, что и само расписание.
class AppMessage {
  static final _timestampPattern = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$');
  final int id;
  final String senderName;
  // Кто из вошедших в приложении пользователей отправил это сообщение — есть
  // только у сообщений, отправленных ИЗ мобильного приложения (см.
  // ScheduleController.sendMessage); у сообщений, отправленных из веб-панели
  // сервера, всегда null. Используется, чтобы вошедший преподаватель/админ
  // мог посмотреть список "что я кому отправил" (см. ChatScreen).
  final int? senderUserId;
  final int? targetGroupId;
  final String body;
  final DateTime createdAt;

  AppMessage({
    required this.id,
    required this.senderName,
    required this.senderUserId,
    required this.targetGroupId,
    required this.body,
    required this.createdAt,
  });

  factory AppMessage.fromJson(Map<String, dynamic> json) {
    return AppMessage(
      id: json['id'] as int,
      senderName: json['senderName'] as String,
      senderUserId: json['senderUserId'] as int?,
      targetGroupId: json['targetGroupId'] as int?,
      body: json['body'] as String,
      createdAt: _parseCreatedAt(json['createdAt']),
    );
  }

  static DateTime _parseCreatedAt(dynamic value) {
    // SQLite's legacy datetime('now') values contain UTC without a suffix.
    // Explicit offsets must retain their meaning when normalizing to UTC.
    if (value is! String) {
      throw const FormatException('Message createdAt must be a timestamp');
    }
    final match = _timestampPattern.firstMatch(value);
    if (match == null) {
      throw const FormatException('Invalid message timestamp');
    }
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime.utc(year, month, day);
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        int.parse(match[4]!) > 23 ||
        int.parse(match[5]!) > 59 ||
        int.parse(match[6] ?? '0') > 59) {
      throw const FormatException('Invalid message timestamp');
    }
    final normalized = value.replaceFirst(' ', 'T');
    final offset = match[7];
    if (offset != null &&
        offset != 'Z' &&
        (int.parse(offset.substring(1, 3)) > 23 ||
            int.parse(offset.substring(offset.length - 2)) > 59)) {
      throw const FormatException('Invalid timestamp offset');
    }
    final parsed =
        DateTime.tryParse(match[7] == null ? '${normalized}Z' : normalized);
    if (parsed == null) {
      throw const FormatException('Invalid message timestamp');
    }
    return parsed.toUtc();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderName': senderName,
        'senderUserId': senderUserId,
        'targetGroupId': targetGroupId,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}
