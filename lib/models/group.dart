import '../localization.dart';

class Group {
  final int id;
  final int facultyId;
  final int courseNumber;
  final String? facultyNameRu;
  final String? facultyNameEn;
  final String nameRu;
  final String? nameEn;
  final String? specializationRu;
  final String? specializationEn;

  Group({
    required this.id,
    this.facultyId = 1,
    this.courseNumber = 1,
    this.facultyNameRu,
    this.facultyNameEn,
    required String name,
    this.nameEn,
    String? specialization,
    this.specializationEn,
  })  : nameRu = name,
        specializationRu = specialization;

  static String _localized(String ru, String? en) =>
      Strings.current == AppLocale.en && en != null && en.trim().isNotEmpty
          ? en
          : ru;

  String get name => _localized(nameRu, nameEn);
  String get facultyName =>
      facultyNameRu == null ? '' : _localized(facultyNameRu!, facultyNameEn);
  String? get specialization {
    if (Strings.current == AppLocale.en &&
        specializationEn != null &&
        specializationEn!.trim().isNotEmpty) {
      return specializationEn;
    }
    return specializationRu;
  }

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as int,
      facultyId: json['facultyId'] as int? ?? 1,
      courseNumber: json['courseNumber'] as int? ?? 1,
      facultyNameRu: json['facultyName'] as String?,
      facultyNameEn: json['facultyNameEn'] as String?,
      name: json['name'] as String,
      nameEn: json['nameEn'] as String?,
      specialization: json['specialization'] as String?,
      specializationEn: json['specializationEn'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'facultyId': facultyId,
        'courseNumber': courseNumber,
        'facultyName': facultyNameRu,
        'facultyNameEn': facultyNameEn,
        'name': nameRu,
        'nameEn': nameEn,
        'specialization': specializationRu,
        'specializationEn': specializationEn,
      };
}
