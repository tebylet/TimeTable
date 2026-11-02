import 'dart:convert';

import 'app_message.dart';
import 'cancelled_lesson.dart';
import 'exam_entry.dart';
import 'faculty.dart';
import 'group.dart';
import 'lesson_update.dart';
import '../utils/week_parity.dart';
import 'schedule_entry.dart';

/// Полный снимок расписания, как его отдаёт сервер (и как он кэшируется
/// локально на телефоне для работы без интернета). Помимо самого расписания
/// содержит отменённые конкретные занятия (cancelledLessons) и ленту
/// сообщений от преподавателей/админов (messages) — они приходят тем же
/// запросом и обновляются тем же механизмом синхронизации по версии.
class ScheduleData {
  final int version;
  final String? serverId;
  final String? semesterStartDate; // "YYYY-MM-DD"
  final List<Faculty> faculties;
  final List<Group> groups;
  final List<ScheduleEntry> entries;
  final List<ExamEntry> exams;
  final List<CancelledLesson> cancelledLessons;
  final List<AppMessage> messages;
  final List<LessonUpdate> lessonUpdates;
  final Map<String, LessonUpdate> _updatesByOccurrence = {};
  final Map<String, List<LessonUpdate>> _movedToDate = {};
  late final Map<int, ScheduleEntry> _entriesById;
  final DateTime fetchedAt;
  late final Map<int, List<ScheduleEntry>> _entriesByGroup;
  late final Map<int, List<ScheduleEntry>> _entriesByTeacher;
  late final Map<int, List<ExamEntry>> _examsByGroup;
  late final Map<int, List<ExamEntry>> _examsByTeacher;
  late final Map<int, Map<int, List<ScheduleEntry>>> _groupDays;
  late final Map<int, Map<int, List<ScheduleEntry>>> _teacherDays;
  late final Map<int, Set<int>> _teacherGroupIds;
  late final Map<String, Map<int, CancelledLesson>> _cancelledByDate;
  late final Map<int, Group> _groupsById;
  late final Set<String> _splitSlots;
  final Map<int?, List<AppMessage>> _messagesForGroup = {};

  ScheduleData({
    required this.version,
    this.serverId,
    required this.semesterStartDate,
    List<Faculty> faculties = const [],
    required List<Group> groups,
    required List<ScheduleEntry> entries,
    List<ExamEntry> exams = const [],
    required List<CancelledLesson> cancelledLessons,
    required List<AppMessage> messages,
    List<LessonUpdate> lessonUpdates = const [],
    required this.fetchedAt,
  })  : faculties = List.unmodifiable(faculties),
        groups = List.unmodifiable(groups),
        entries = List.unmodifiable(entries),
        exams = List.unmodifiable(
            List<ExamEntry>.of(exams)..sort(ExamEntry.compare)),
        cancelledLessons = List.unmodifiable(cancelledLessons),
        messages = List.unmodifiable(messages),
        lessonUpdates = List.unmodifiable(lessonUpdates) {
    _entriesById =
        Map.unmodifiable({for (final entry in this.entries) entry.id: entry});
    _examsByGroup = _indexExams(this.exams, (exam) => exam.groupId);
    _examsByTeacher = _indexExams(
        this.exams.where((exam) => exam.teacherId != null),
        (exam) => exam.teacherId!);
    for (final update in this.lessonUpdates) {
      _updatesByOccurrence['${update.entryId}:${update.date}'] = update;
      if (update.kind == 'rescheduled') {
        (_movedToDate[update.newDate!] ??= []).add(update);
      }
    }
    _entriesByGroup = _indexEntries(this.entries, (entry) => entry.groupId);
    _entriesByTeacher = _indexEntries(
        this.entries.where((entry) => entry.teacherId != null),
        (entry) => entry.teacherId!);
    _groupDays = _indexDays(_entriesByGroup);
    _teacherDays = _indexDays(_entriesByTeacher);
    _teacherGroupIds = Map.unmodifiable(_entriesByTeacher.map((id, entries) =>
        MapEntry(id, Set<int>.unmodifiable(entries.map((e) => e.groupId)))));
    _groupsById =
        Map.unmodifiable({for (final group in this.groups) group.id: group});
    final cancellations = <String, Map<int, CancelledLesson>>{};
    for (final cancellation in this.cancelledLessons) {
      if (cancellation.isRescheduled) continue;
      (cancellations[cancellation.date] ??= {})[cancellation.entryId] =
          cancellation;
    }
    _cancelledByDate = Map.unmodifiable(cancellations.map((date, entries) =>
        MapEntry(date, Map<int, CancelledLesson>.unmodifiable(entries))));
    final parities = <String, Set<WeekParity>>{};
    for (final entry in this.entries) {
      (parities[_slotKey(entry)] ??= {}).add(entry.weekParity);
    }
    _splitSlots = Set.unmodifiable(parities.entries
        .where((slot) =>
            slot.value.contains(WeekParity.odd) &&
            slot.value.contains(WeekParity.even))
        .map((slot) => slot.key));
  }

  static String _slotKey(ScheduleEntry entry) =>
      '${entry.groupId}:${entry.dayOfWeek}:${entry.period}';

  static Map<int, List<ExamEntry>> _indexExams(
      Iterable<ExamEntry> exams, int Function(ExamEntry) keyFor) {
    final index = <int, List<ExamEntry>>{};
    for (final exam in exams) {
      (index[keyFor(exam)] ??= []).add(exam);
    }
    return Map.unmodifiable(index.map(
        (key, exams) => MapEntry(key, List<ExamEntry>.unmodifiable(exams))));
  }

  static Map<int, List<ScheduleEntry>> _indexEntries(
      Iterable<ScheduleEntry> entries, int Function(ScheduleEntry) keyFor) {
    final index = <int, List<ScheduleEntry>>{};
    for (final entry in entries) {
      (index[keyFor(entry)] ??= []).add(entry);
    }
    return Map.unmodifiable(index.map((key, entries) {
      entries.sort((a, b) {
        final day = a.dayOfWeek.compareTo(b.dayOfWeek);
        if (day != 0) return day;
        final period = a.period.compareTo(b.period);
        if (period != 0) return period;
        final group = a.groupId.compareTo(b.groupId);
        return group != 0 ? group : a.id.compareTo(b.id);
      });
      return MapEntry(key, List<ScheduleEntry>.unmodifiable(entries));
    }));
  }

  static Map<int, Map<int, List<ScheduleEntry>>> _indexDays(
          Map<int, List<ScheduleEntry>> entriesByOwner) =>
      Map.unmodifiable(entriesByOwner.map((owner, entries) {
        final days = <int, List<ScheduleEntry>>{};
        for (final entry in entries) {
          (days[entry.dayOfWeek] ??= []).add(entry);
        }
        return MapEntry(
            owner,
            Map<int, List<ScheduleEntry>>.unmodifiable(days.map(
                (day, entries) =>
                    MapEntry(day, List<ScheduleEntry>.unmodifiable(entries)))));
      }));

  factory ScheduleData.empty() => ScheduleData(
        version: 0,
        semesterStartDate: null,
        faculties: [],
        groups: [],
        entries: [],
        cancelledLessons: [],
        messages: [],
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  bool get isEmpty => groups.isEmpty && entries.isEmpty && exams.isEmpty;

  factory ScheduleData.fromJson(Map<String, dynamic> json) {
    return ScheduleData(
      version: json['version'] as int? ?? 0,
      serverId: json['serverId'] as String?,
      semesterStartDate: json['semesterStartDate'] as String?,
      faculties: (json['faculties'] as List<dynamic>? ?? [])
          .map((f) => Faculty.fromJson(f as Map<String, dynamic>))
          .toList(),
      groups: (json['groups'] as List<dynamic>? ?? [])
          .map((g) => Group.fromJson(g as Map<String, dynamic>))
          .toList(),
      entries: (json['entries'] as List<dynamic>? ?? [])
          .map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      exams: (json['exams'] as List<dynamic>? ?? [])
          .map((e) => ExamEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      cancelledLessons: (json['cancelledLessons'] as List<dynamic>? ?? [])
          .map((c) => CancelledLesson.fromJson(c as Map<String, dynamic>))
          .toList(),
      lessonUpdates: (json['lessonUpdates'] as List<dynamic>? ?? [])
          .map((item) => LessonUpdate.fromJson(item as Map<String, dynamic>))
          .toList(),
      messages: (json['messages'] as List<dynamic>? ?? [])
          .map((m) => AppMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
      fetchedAt: json['fetchedAt'] != null
          ? DateTime.parse(json['fetchedAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'serverId': serverId,
        'semesterStartDate': semesterStartDate,
        'faculties': faculties.map((f) => f.toJson()).toList(),
        'groups': groups.map((g) => g.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'exams': exams.map((e) => e.toJson()).toList(),
        'cancelledLessons': cancelledLessons.map((c) => c.toJson()).toList(),
        'lessonUpdates': lessonUpdates.map((item) => item.toJson()).toList(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  static ScheduleData decode(String raw) =>
      ScheduleData.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// "YYYY-MM-DD" в местном времени — единый формат даты, которым отмечены
  /// отменённые занятия что на сервере, что здесь.
  static String isoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Group? groupById(int? groupId) => _groupsById[groupId];

  List<ScheduleEntry> entriesForGroup(int groupId) =>
      _entriesByGroup[groupId] ?? const [];

  List<ScheduleEntry> entriesForTeacher(int teacherId) =>
      _entriesByTeacher[teacherId] ?? const [];

  List<ExamEntry> examsForGroup(int groupId) =>
      _examsByGroup[groupId] ?? const [];

  List<ExamEntry> examsForTeacher(int teacherId) =>
      _examsByTeacher[teacherId] ?? const [];

  List<ScheduleEntry> entriesForGroupOnDay(int groupId, int day) =>
      _groupDays[groupId]?[day] ?? const [];

  List<ScheduleEntry> entriesForTeacherOnDay(int teacherId, int day) =>
      _teacherDays[teacherId]?[day] ?? const [];

  Set<int> groupIdsForTeacher(int teacherId) =>
      _teacherGroupIds[teacherId] ?? const {};

  List<ScheduleEntry> entriesOnDate(DateTime date,
      {int? groupId,
      int? teacherId,
      Set<int>? groupIds,
      WeekParity? Function(ScheduleEntry)? subgroupFor}) {
    final day = DateTime(date.year, date.month, date.day);
    final iso = isoDate(day);
    final parity = weekParityOn(semesterStartDate, day);
    bool inScope(ScheduleEntry entry) => teacherId != null
        ? entry.teacherId == teacherId
        : groupIds != null
            ? groupIds.contains(entry.groupId)
            : entry.groupId == groupId;
    final base = teacherId != null
        ? entriesForTeacherOnDay(teacherId, day.weekday)
        : groupIds != null
            ? groupIds.expand((id) => entriesForGroupOnDay(id, day.weekday))
            : entriesForGroupOnDay(groupId ?? -1, day.weekday);
    final result = <ScheduleEntry>[];
    for (final entry in base) {
      if (!entry.occursOn(day, parity,
          subgroupPreference: subgroupFor?.call(entry))) {
        continue;
      }
      final update = _updatesByOccurrence['${entry.id}:$iso'];
      if (update?.kind == 'rescheduled' && update!.newDate != iso) continue;
      result.add(update?.apply(entry) ?? entry);
    }
    for (final update in _movedToDate[iso] ?? const <LessonUpdate>[]) {
      if (update.date == iso) continue;
      final entry = _entriesById[update.entryId];
      if (entry == null || !inScope(entry)) continue;
      final preference = subgroupFor?.call(entry);
      if (preference != null &&
          entry.weekParity != WeekParity.all &&
          entry.weekParity != preference) {
        continue;
      }
      result.add(update.apply(entry));
    }
    result.sort((a, b) {
      final time = a.startTime.compareTo(b.startTime);
      if (time != 0) return time;
      final group = a.groupId.compareTo(b.groupId);
      return group != 0 ? group : a.id.compareTo(b.id);
    });
    return result;
  }

  ScheduleData withoutMessage(int messageId) => ScheduleData(
        version: version,
        serverId: serverId,
        semesterStartDate: semesterStartDate,
        faculties: faculties,
        groups: groups,
        entries: entries,
        exams: exams,
        cancelledLessons: cancelledLessons,
        messages: messages.where((message) => message.id != messageId).toList(),
        lessonUpdates: lessonUpdates,
        fetchedAt: fetchedAt,
      );

  bool hasSubgroupSplit(ScheduleEntry entry) =>
      entry.weekParity != WeekParity.all &&
      _splitSlots.contains(_slotKey(entry));

  /// Отменённые занятия конкретной даты — ключ entryId, чтобы быстро
  /// проверять, отменено ли конкретное занятие на экране расписания.
  Map<int, CancelledLesson> cancelledLessonsOn(DateTime date) {
    return _cancelledByDate[isoDate(date)] ?? const {};
  }

  /// Сообщения, которые должен видеть студент конкретной группы: либо
  /// адресованные всем группам (targetGroupId == null), либо именно этой
  /// группе. Порядок — от старых к новым (как их отдаёт сервер).
  List<AppMessage> messagesForGroup(int? groupId) =>
      _messagesForGroup.putIfAbsent(
          groupId,
          () => List.unmodifiable(messages.where(
              (m) => m.targetGroupId == null || m.targetGroupId == groupId)));
}
