import '../localization.dart';
import 'schedule_entry.dart';

/// An override of exactly one original occurrence, never the weekly template.
class LessonUpdate {
  final int entryId;
  final String date;
  final String kind;
  final String? newDate;
  final String? startTime;
  final String? endTime;
  final String? room;
  final String notes;
  final String updatedBy;

  LessonUpdate(
      {required this.entryId,
      required this.date,
      required this.kind,
      this.newDate,
      this.startTime,
      this.endTime,
      this.room,
      this.notes = '',
      this.updatedBy = ''});

  factory LessonUpdate.fromJson(Map<String, dynamic> json) {
    final id = json['entryId'];
    final kind = json['kind'];
    if (id is! int ||
        id < 1 ||
        !['rescheduled', 'room_changed', 'note'].contains(kind) ||
        !_date(json['date'])) {
      throw const FormatException('Invalid lesson update');
    }
    if (kind == 'rescheduled' &&
        (!_date(json['newDate']) ||
            !_time(json['startTime']) ||
            !_time(json['endTime']) ||
            (json['startTime'] as String)
                    .compareTo(json['endTime'] as String) >=
                0)) {
      throw const FormatException('Invalid rescheduled session');
    }
    if ((json['room'] != null &&
            (json['room'] is! String ||
                (json['room'] as String).length > 200)) ||
        (json['notes'] != null &&
            (json['notes'] is! String ||
                (json['notes'] as String).length > 1000)) ||
        (kind == 'room_changed' &&
            (json['room'] as String? ?? '').trim().isEmpty) ||
        (kind == 'note' && (json['notes'] as String? ?? '').trim().isEmpty)) {
      throw const FormatException('Invalid session details');
    }
    return LessonUpdate(
        entryId: id,
        date: json['date'] as String,
        kind: kind as String,
        newDate: json['newDate'] as String?,
        startTime: json['startTime'] as String?,
        endTime: json['endTime'] as String?,
        room: json['room'] as String?,
        notes: json['notes'] as String? ?? '',
        updatedBy: json['updatedBy'] as String? ?? '');
  }
  static bool _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final parsed = DateTime.tryParse(value);
    return parsed != null &&
        parsed.year >= 1 &&
        parsed.year.toString().padLeft(4, '0') == value.substring(0, 4) &&
        parsed.month == int.parse(value.substring(5, 7)) &&
        parsed.day == int.parse(value.substring(8, 10));
  }

  static bool _time(Object? value) =>
      value is String && RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value);
  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'date': date,
        'kind': kind,
        'newDate': newDate,
        'startTime': startTime,
        'endTime': endTime,
        'room': room,
        'notes': notes,
        'updatedBy': updatedBy
      };

  ScheduleEntry apply(ScheduleEntry entry) {
    final description = kind == 'rescheduled'
        ? Strings.rescheduledTo(newDate!, startTime!, endTime!)
        : kind == 'room_changed'
            ? Strings.newRoom(room ?? '')
            : Strings.lessonUpdateNote;
    return ScheduleEntry(
        id: entry.id,
        groupId: entry.groupId,
        dayOfWeek: entry.dayOfWeek,
        period: entry.period,
        startTime: kind == 'rescheduled' ? startTime! : entry.startTime,
        endTime: kind == 'rescheduled' ? endTime! : entry.endTime,
        subject: entry.subjectRu,
        subjectEn: entry.subjectEn,
        groupNameRu: entry.groupNameRu,
        groupNameEn: entry.groupNameEn,
        teacherId: entry.teacherId,
        teacher: entry.teacher,
        teacherTitle: entry.teacherTitle,
        room: room ?? entry.room,
        weekParity: entry.weekParity,
        startDate: entry.startDate,
        endDate: entry.endDate,
        sourceWeekStart: entry.sourceWeekStart,
        originalDate: date,
        updateKind: kind,
        notes: [
          if (entry.notes?.isNotEmpty == true) entry.notes!,
          description,
          if (notes.isNotEmpty) notes
        ].join('\n'));
  }
}
