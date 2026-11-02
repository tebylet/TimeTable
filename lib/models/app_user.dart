/// Роль вошедшего в приложении сотрудника — учётные записи заводятся в
/// панели администратора сервера (вкладка "Аккаунты"), см.
/// server/src/services/appAuth.js. И admin, и teacher могут отменять
/// занятия (teacher — только свои, см. ScheduleController.canCancelLesson)
/// и отправлять сообщения группам.
enum AppRole { admin, teacher, coordinator }

AppRole appRoleFromString(String? value) {
  if (value == 'coordinator') return AppRole.coordinator;
  return value == 'admin' ? AppRole.admin : AppRole.teacher;
}

/// Вошедший в приложении администратор/преподаватель. Не путать с учётными
/// записями студентов — их в приложении нет, студенты просто выбирают
/// группу (см. GroupSelectScreen).
class AppUser {
  final int id;
  final String username;
  final AppRole role;
  final String displayName;
  final int? teacherId;
  final int? facultyId;
  final int? courseNumber;

  AppUser({
    required this.id,
    required this.username,
    required this.role,
    required this.displayName,
    this.teacherId,
    this.facultyId,
    this.courseNumber,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      username: json['username'] as String,
      role: appRoleFromString(json['role'] as String?),
      displayName: json['displayName'] as String? ?? json['username'] as String,
      teacherId: json['teacherId'] as int?,
      facultyId: json['facultyId'] as int?,
      courseNumber: json['courseNumber'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'role': role.name,
        'displayName': displayName,
        'teacherId': teacherId,
        'facultyId': facultyId,
        'courseNumber': courseNumber,
      };
}
