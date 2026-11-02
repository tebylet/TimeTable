import '../localization.dart';

/// Чётность недели, к которой относится занятие.
enum WeekParity { all, odd, even }

WeekParity weekParityFromString(String? value) {
  switch (value) {
    case 'odd':
      return WeekParity.odd;
    case 'even':
      return WeekParity.even;
    default:
      return WeekParity.all;
  }
}

class ScheduleEntry {
  static final _timePattern = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  final int id;
  final int groupId;
  final int dayOfWeek; // 1 = понедельник .. 6 = суббота
  final int period;
  final String startTime; // "HH:MM"
  final String endTime;
  final String subjectRu;
  final String? subjectEn;
  final String? groupNameRu;
  final String? groupNameEn;
  final int? teacherId;
  final String? teacher;
  final String? teacherTitle;
  final String? room;
  final WeekParity weekParity;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? sourceWeekStart;
  final String? notes;
  final String? originalDate;
  final String? updateKind;

  ScheduleEntry({
    required this.id,
    required this.groupId,
    required this.dayOfWeek,
    required this.period,
    required this.startTime,
    required this.endTime,
    required String subject,
    this.subjectEn,
    this.groupNameRu,
    this.groupNameEn,
    this.teacherId,
    this.teacher,
    this.teacherTitle,
    this.room,
    this.weekParity = WeekParity.all,
    this.startDate,
    this.endDate,
    this.sourceWeekStart,
    this.notes,
    this.originalDate,
    this.updateKind,
  }) : subjectRu = subject;

  static String _localized(String ru, String? en) =>
      Strings.current == AppLocale.en && en != null && en.trim().isNotEmpty
          ? en
          : ru;

  String get subject => _localized(subjectRu, subjectEn);
  String get groupName =>
      groupNameRu == null ? '' : _localized(groupNameRu!, groupNameEn);

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) {
    final startTime = _readTime(json['startTime'], 'startTime');
    final endTime = _readTime(json['endTime'], 'endTime');
    if (endTime.compareTo(startTime) <= 0) {
      throw const FormatException('Lesson must end after it starts');
    }
    final startDate = _readDate(json['startDate'], 'startDate');
    final endDate = _readDate(json['endDate'], 'endDate');
    if (startDate != null && endDate != null && !endDate.isAfter(startDate)) {
      throw const FormatException('Lesson date range must be increasing');
    }
    final parity = json['weekParity'];
    if (parity != null &&
        parity != 'all' &&
        parity != 'odd' &&
        parity != 'even') {
      throw const FormatException('Invalid week parity');
    }
    return ScheduleEntry(
      id: _readInt(json['id'], 'id'),
      groupId: _readInt(json['groupId'], 'groupId'),
      dayOfWeek: _readInt(json['dayOfWeek'], 'dayOfWeek', maximum: 7),
      period: _readInt(json['period'], 'period', maximum: 8),
      startTime: startTime,
      endTime: endTime,
      subject: json['subject'] as String,
      subjectEn: json['subjectEn'] as String?,
      groupNameRu: json['groupName'] as String?,
      groupNameEn: json['groupNameEn'] as String?,
      teacherId: json['teacherId'] == null
          ? null
          : _readInt(json['teacherId'], 'teacherId'),
      teacher: json['teacher'] as String?,
      teacherTitle: json['teacherTitle'] as String?,
      room: json['room'] as String?,
      weekParity: weekParityFromString(json['weekParity'] as String?),
      startDate: startDate,
      endDate: endDate,
      sourceWeekStart: _readDate(json['sourceWeekStart'], 'sourceWeekStart'),
      notes: json['notes'] as String?,
    );
  }

  static int _readInt(dynamic value, String field, {int? maximum}) {
    if (value is! num ||
        !value.isFinite ||
        value != value.roundToDouble() ||
        value < 1 ||
        (maximum != null && value > maximum)) {
      throw FormatException('Invalid integer $field');
    }
    return value.toInt();
  }

  static String _readTime(dynamic value, String field) {
    if (value is! String || !_timePattern.hasMatch(value)) {
      throw FormatException('Invalid $field');
    }
    return value;
  }

  static DateTime? _readDate(dynamic value, String field) {
    if (value == null) return null;
    if (value is! String || !_datePattern.hasMatch(value)) {
      throw FormatException('Invalid $field');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw FormatException('Invalid calendar date $field');
    }
    return parsed;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'dayOfWeek': dayOfWeek,
        'period': period,
        'startTime': startTime,
        'endTime': endTime,
        'subject': subjectRu,
        'subjectEn': subjectEn,
        'groupName': groupNameRu,
        'groupNameEn': groupNameEn,
        'teacherId': teacherId,
        'teacher': teacher,
        'teacherTitle': teacherTitle,
        'room': room,
        'weekParity': weekParity.name,
        'startDate': startDate?.toIso8601String().substring(0, 10),
        'endDate': endDate?.toIso8601String().substring(0, 10),
        'sourceWeekStart': sourceWeekStart?.toIso8601String().substring(0, 10),
        'notes': notes,
      };

  /// Проходит ли занятие в конкретный день с учётом чётности недели, даты
  /// начала и даты окончания (например, практика сменяется лекциями с
  /// середины семестра — у практики будет endDate, у лекций — startDate).
  ///
  /// [subgroupPreference] — необязательный выбор пользователя "к какой
  /// подгруппе я отношусь" для этого конкретного слота (тот же день+пара),
  /// см. ScheduleController.subgroupPreferenceFor(). Если он задан и не
  /// совпадает с чётностью ЭТОГО занятия — занятие считается "не моим" и не
  /// показывается вообще, даже если формально совпадает с настоящей
  /// чётностью текущей недели (это и есть занятие другой подгруппы). Если
  /// совпадает (или предпочтение не задано) — поведение как раньше: занятие
  /// показывается только на тех неделях, чётность которых у него указана.
  bool occursOn(DateTime date, WeekParity currentWeekParity,
      {WeekParity? subgroupPreference}) {
    if (startDate != null && date.isBefore(startDate!)) return false;
    if (endDate != null && !date.isBefore(endDate!)) return false;
    if (weekParity == WeekParity.all) return true;
    if (subgroupPreference != null && weekParity != subgroupPreference) {
      return false;
    }
    return weekParity == currentWeekParity;
  }

  String get teacherDisplay {
    if (teacher == null) return '';
    if (teacherTitle == null || teacherTitle!.isEmpty) return teacher!;
    return '$teacherTitle $teacher';
  }
}
