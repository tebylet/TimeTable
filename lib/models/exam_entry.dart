import '../localization.dart';

/// A single dated examination, independent of the recurring class timetable.
class ExamEntry {
  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _timePattern = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
  final int id;
  final int groupId;
  final int subjectId;
  final String subjectRu;
  final String? subjectEn;
  final String? groupNameRu;
  final String? groupNameEn;
  final String date;
  final String startTime;
  final String endTime;
  final int? teacherId;
  final String? teacher;
  final String? teacherTitle;
  final String? room;
  final String? notes;

  const ExamEntry({
    required this.id,
    required this.groupId,
    required this.subjectId,
    required String subject,
    this.subjectEn,
    this.groupNameRu,
    this.groupNameEn,
    required this.date,
    required this.startTime,
    required this.endTime,
    this.teacherId,
    this.teacher,
    this.teacherTitle,
    this.room,
    this.notes,
  }) : subjectRu = subject;

  static String _localized(String ru, String? en) =>
      Strings.current == AppLocale.en && en != null && en.trim().isNotEmpty
          ? en
          : ru;

  String get subject => _localized(subjectRu, subjectEn);
  String get groupName =>
      groupNameRu == null ? '' : _localized(groupNameRu!, groupNameEn);

  String get teacherDisplay {
    if (teacher == null || teacher!.isEmpty) return '';
    if (teacherTitle == null || teacherTitle!.isEmpty) return teacher!;
    return '$teacherTitle $teacher';
  }

  /// Stable ordering for calendar views and subject search results.
  static int compare(ExamEntry a, ExamEntry b) {
    final dateOrder = a.date.compareTo(b.date);
    if (dateOrder != 0) return dateOrder;
    final timeOrder = a.startTime.compareTo(b.startTime);
    return timeOrder != 0 ? timeOrder : a.id.compareTo(b.id);
  }

  factory ExamEntry.fromJson(Map<String, dynamic> json) {
    final date = _readDate(json['date']);
    final startTime = _readTime(json['startTime'], 'startTime');
    final endTime = _readTime(json['endTime'], 'endTime');
    if (endTime.compareTo(startTime) <= 0) {
      throw const FormatException('Exam must end after it starts');
    }
    final subject = _readString(json['subject'], 'subject');
    if (subject == null || subject.trim().isEmpty) {
      throw const FormatException('Invalid subject');
    }
    return ExamEntry(
      id: _readId(json['id'], 'id'),
      groupId: _readId(json['groupId'], 'groupId'),
      subjectId: _readId(json['subjectId'], 'subjectId'),
      subject: subject,
      subjectEn: _readString(json['subjectEn'], 'subjectEn'),
      groupNameRu: _readString(json['groupName'], 'groupName'),
      groupNameEn: _readString(json['groupNameEn'], 'groupNameEn'),
      date: date,
      startTime: startTime,
      endTime: endTime,
      teacherId: json['teacherId'] == null
          ? null
          : _readId(json['teacherId'], 'teacherId'),
      teacher: _readString(json['teacher'], 'teacher'),
      teacherTitle: _readString(json['teacherTitle'], 'teacherTitle'),
      room: _readString(json['room'], 'room'),
      notes: _readString(json['notes'], 'notes'),
    );
  }

  static int _readId(dynamic value, String field) {
    if (value is! num ||
        !value.isFinite ||
        value != value.roundToDouble() ||
        value < 1 ||
        value > 9007199254740991) {
      throw FormatException('Invalid integer $field');
    }
    return value.toInt();
  }

  static String _readDate(dynamic value) {
    if (value is! String || !_datePattern.hasMatch(value)) {
      throw const FormatException('Invalid exam date');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year < 1 ||
        parsed.toIso8601String().substring(0, 10) != value) {
      throw const FormatException('Invalid exam calendar date');
    }
    return value;
  }

  static String _readTime(dynamic value, String field) {
    if (value is! String || !_timePattern.hasMatch(value)) {
      throw FormatException('Invalid $field');
    }
    return value;
  }

  static String? _readString(dynamic value, String field) {
    if (value != null && value is! String) {
      throw FormatException('Invalid $field');
    }
    return value as String?;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'subjectId': subjectId,
        'subject': subjectRu,
        'subjectEn': subjectEn,
        'groupName': groupNameRu,
        'groupNameEn': groupNameEn,
        'date': date,
        'startTime': startTime,
        'endTime': endTime,
        'teacherId': teacherId,
        'teacher': teacher,
        'teacherTitle': teacherTitle,
        'room': room,
        'notes': notes,
      };
}
