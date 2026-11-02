import '../localization.dart';

class Faculty {
  final int id;
  final String nameRu;
  final String? nameEn;

  Faculty({required this.id, required String name, this.nameEn})
      : nameRu = name;

  String get name => Strings.current == AppLocale.en &&
          nameEn != null &&
          nameEn!.trim().isNotEmpty
      ? nameEn!
      : nameRu;

  factory Faculty.fromJson(Map<String, dynamic> json) => Faculty(
        id: json['id'] as int,
        name: json['name'] as String,
        nameEn: json['nameEn'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': nameRu,
        'nameEn': nameEn,
      };
}
