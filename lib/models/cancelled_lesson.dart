/// Отмена ОДНОГО конкретного занятия на конкретную дату (не всей повторяющейся
/// записи в расписании — она остаётся как есть и снова появится на
/// следующей неделе). Заводится преподавателем/админом из приложения, см.
/// ScheduleController.cancelLesson / server/src/routes/api.js.
class CancelledLesson {
  final int entryId;
  final String date; // "YYYY-MM-DD"
  final String? reason;
  final bool isRescheduled;

  CancelledLesson(
      {required this.entryId,
      required this.date,
      this.reason,
      this.isRescheduled = false});

  factory CancelledLesson.fromJson(Map<String, dynamic> json) {
    return CancelledLesson(
      entryId: json['entryId'] as int,
      date: json['date'] as String,
      reason: json['reason'] as String?,
      isRescheduled: json['kind'] == 'rescheduled',
    );
  }

  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'date': date,
        'reason': reason,
        if (isRescheduled) 'kind': 'rescheduled',
      };
}
