import 'package:flutter_test/flutter_test.dart';
import 'package:ymtimetable/localization.dart';
import 'package:ymtimetable/models/app_user.dart';
import 'package:ymtimetable/models/exam_entry.dart';
import 'package:ymtimetable/models/group.dart';
import 'package:ymtimetable/models/schedule_data.dart';
import 'package:ymtimetable/services/sync_service.dart';
import 'package:ymtimetable/services/update_channel.dart';

Map<String, dynamic> examJson({
  int id = 1,
  int groupId = 1,
  int subjectId = 5,
  int? teacherId = 7,
  String date = '2026-12-15',
  String startTime = '09:00',
}) =>
    {
      'id': id,
      'groupId': groupId,
      'subjectId': subjectId,
      'subject': 'Математика',
      'subjectEn': 'Mathematics',
      'groupName': 'Группа $groupId',
      'groupNameEn': 'Group $groupId',
      'date': date,
      'startTime': startTime,
      'endTime': '12:00',
      'teacherId': teacherId,
      'teacher': 'Иванов И. И.',
      'teacherTitle': 'доцент',
      'room': '315',
      'notes': 'Принести калькулятор',
    };

ScheduleData snapshot(List<ExamEntry> exams) => ScheduleData(
      version: 12,
      serverId: 'exams-test',
      semesterStartDate: '2026-09-01',
      groups: [
        Group(id: 1, name: 'A', facultyId: 1, courseNumber: 1),
        Group(id: 2, name: 'B', facultyId: 1, courseNumber: 2),
        Group(id: 3, name: 'C', facultyId: 2, courseNumber: 1),
        Group(id: 4, name: 'D', facultyId: 1, courseNumber: 1),
      ],
      entries: [],
      exams: exams,
      cancelledLessons: [],
      messages: [],
      fetchedAt: DateTime(2026, 10, 30),
    );

AppUser staff(AppRole role,
        {int? teacherId, int? facultyId, int? courseNumber}) =>
    AppUser(
        id: 9,
        username: 'staff',
        role: role,
        displayName: 'Staff',
        teacherId: teacherId,
        facultyId: facultyId,
        courseNumber: courseNumber);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => Strings.current = AppLocale.ru);

  test('exam snapshot roundtrip retains source names and exact dated fields',
      () {
    final original = examJson();
    final data = snapshot([ExamEntry.fromJson(original)]);
    Strings.current = AppLocale.en;
    expect(data.exams.single.subject, 'Mathematics');
    expect(data.exams.single.groupName, 'Group 1');
    expect(data.exams.single.teacherDisplay, 'доцент Иванов И. И.');
    final restored = ScheduleData.decode(data.encode());
    expect(restored.exams.single.toJson(), original);
    Strings.current = AppLocale.ru;
    expect(restored.exams.single.subject, 'Математика');
    expect(restored.exams.single.groupName, 'Группа 1');
    expect(restored.exams.single.date, '2026-12-15');
    expect(restored.exams.single.room, '315');
    expect(restored.exams.single.notes, 'Принести калькулятор');
  });

  test('old snapshots and empty data do not require an exams field', () {
    final legacy = snapshot([]).toJson()..remove('exams');
    final restored = ScheduleData.fromJson(legacy);
    expect(restored.exams, isEmpty);
    expect(restored.examsForGroup(1), isEmpty);
    expect(restored.examsForTeacher(7), isEmpty);
    expect(ScheduleData.empty().exams, isEmpty);
  });

  test('exam identities, real calendar dates, and clock ranges are validated',
      () {
    for (final change in <Map<String, dynamic>>[
      {'id': 0},
      {'id': -1},
      {'groupId': '1'},
      {'subjectId': 1.5},
      {'teacherId': double.infinity},
      {'id': 9007199254740992},
      {'date': null},
      {'date': '2026-2-15'},
      {'date': '2026-02-29'},
      {'date': '2026-04-31'},
      {'date': '0000-01-01'},
      {'date': '2026-12-15T00:00:00'},
      {'startTime': '24:00'},
      {'startTime': '9:00'},
      {'endTime': '12:60'},
      {'startTime': '12:00', 'endTime': '12:00'},
      {'startTime': '13:00', 'endTime': '12:00'},
    ]) {
      expect(() => ExamEntry.fromJson({...examJson(), ...change}),
          throwsFormatException,
          reason: change.toString());
    }
    expect(ExamEntry.fromJson(examJson(date: '2028-02-29')).date, '2028-02-29');
  });

  test('names fall back to Russian and optional instructor data is supported',
      () {
    Strings.current = AppLocale.en;
    final exam = ExamEntry.fromJson({
      ...examJson(),
      'subjectEn': ' ',
      'groupNameEn': null,
      'teacherId': null,
      'teacher': null,
      'teacherTitle': null,
      'room': null,
      'notes': null,
    });
    expect(exam.subject, 'Математика');
    expect(exam.groupName, 'Группа 1');
    expect(exam.teacherDisplay, isEmpty);
    expect(exam.teacherId, isNull);
    expect(ExamEntry.fromJson(exam.toJson()).toJson(), exam.toJson());
  });

  test('exam snapshots and indexes are immutable and ordered by date/time/id',
      () {
    final input = [
      ExamEntry.fromJson(examJson(id: 5, date: '2026-12-16')),
      ExamEntry.fromJson(examJson(id: 4, startTime: '11:00')),
      ExamEntry.fromJson(examJson(id: 3)),
      ExamEntry.fromJson(examJson(id: 2)),
      ExamEntry.fromJson(examJson(id: 1, groupId: 2, teacherId: null)),
    ];
    final data = snapshot(input);
    expect(input.map((exam) => exam.id), [5, 4, 3, 2, 1]);
    input.clear();
    expect(data.exams.map((exam) => exam.id), [1, 2, 3, 4, 5]);
    expect(data.examsForGroup(1).map((exam) => exam.id), [2, 3, 4, 5]);
    expect(data.examsForTeacher(7).map((exam) => exam.id), [2, 3, 4, 5]);
    expect(() => data.exams.clear(), throwsUnsupportedError);
    expect(() => data.examsForGroup(1).clear(), throwsUnsupportedError);
    expect(() => data.examsForTeacher(7).clear(), throwsUnsupportedError);
  });

  test('visible exams follow student/admin group and instructor assignment',
      () {
    final controller = ScheduleController(channel: UpdateChannel.unsupported)
      ..data = snapshot([
        ExamEntry.fromJson(examJson(id: 1, teacherId: 7)),
        ExamEntry.fromJson(examJson(id: 2, groupId: 2, teacherId: 7)),
        ExamEntry.fromJson(examJson(id: 3, groupId: 2, teacherId: 8)),
      ]);
    addTearDown(controller.dispose);
    expect(controller.visibleExams, isEmpty);
    controller.selectedGroupId = 2;
    expect(controller.visibleExams.map((exam) => exam.id), [2, 3]);
    controller.appUser = staff(AppRole.admin);
    expect(controller.visibleExams.map((exam) => exam.id), [2, 3]);
    controller.appUser = staff(AppRole.teacher, teacherId: 7);
    expect(controller.visibleExams.map((exam) => exam.id), [1, 2]);
    controller.appUser = staff(AppRole.teacher);
    expect(controller.visibleExams, isEmpty);
  });

  test('coordinator exams span only assigned course and retain subject IDs',
      () {
    final controller = ScheduleController(channel: UpdateChannel.unsupported)
      ..data = snapshot([
        ExamEntry.fromJson(examJson(id: 4, groupId: 4, subjectId: 15)),
        ExamEntry.fromJson(examJson(id: 3, groupId: 3)),
        ExamEntry.fromJson(examJson(id: 2, groupId: 2)),
        ExamEntry.fromJson(examJson(id: 1, subjectId: 5, date: '2026-01-01')),
      ])
      ..appUser = staff(AppRole.coordinator, facultyId: 1, courseNumber: 1);
    addTearDown(controller.dispose);
    expect(controller.visibleExams.map((exam) => exam.id), [1, 4]);
    expect(controller.visibleExams.map((exam) => exam.subjectId), [5, 15]);
    expect(controller.visibleExams.map((exam) => exam.subjectRu).toSet(),
        {'Математика'});
    expect(() => controller.visibleExams.clear(), throwsUnsupportedError);
    controller.appUser = staff(AppRole.coordinator, facultyId: 1);
    expect(controller.visibleExams, isEmpty);
  });
}
