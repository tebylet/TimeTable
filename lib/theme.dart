import 'package:flutter/material.dart';

import 'localization.dart';

/// Один набор цветов приложения — "тема оформления". Все 4 темы (тёмная,
/// светлая, жёлтая, зелёная) построены по одному и тому же принципу:
/// холодные/тёплые акценты, тонкие контурные рамки вместо теней, чёткие
/// прямоугольные формы — "футуристично, но строго".
class AppPalette {
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color borderStrong;

  final Color accent; // основной акцент (primary)
  final Color onAccent;
  final Color secondaryAccent; // вторичный акцент
  final Color amber; // предупреждения (нет связи с сервером)
  final Color nowLine; // линия "текущее время"
  final Color error;

  final Color textPrimary;
  final Color textMuted;

  // Два цвета, которыми поочерёдно подсвечиваются карточки предметов в
  // расписании (чтобы соседние занятия было проще отличить друг от друга).
  final Color cardColorA;
  final Color cardColorB;

  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.onAccent,
    required this.secondaryAccent,
    required this.amber,
    required this.nowLine,
    required this.error,
    required this.textPrimary,
    required this.textMuted,
    required this.cardColorA,
    required this.cardColorB,
  });
}

class AppPalettes {
  AppPalettes._();

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0A0E14),
    surface: Color(0xFF10161D),
    surfaceRaised: Color(0xFF161D26),
    border: Color(0x332BD9C9),
    borderStrong: Color(0x662BD9C9),
    accent: Color(0xFF2BD9C9),
    onAccent: Color(0xFF00201C),
    secondaryAccent: Color(0xFF7C6CF0),
    amber: Color(0xFFF5B942),
    nowLine: Color(0xFFFF3B5C),
    error: Color(0xFFFF5470),
    textPrimary: Color(0xFFE8EEF2),
    textMuted: Color(0xFF7C8A99),
    cardColorA: Color(0xFF2BD9C9),
    cardColorB: Color(0xFF7C6CF0),
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF3F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    border: Color(0x332B3A55),
    borderStrong: Color(0x662B3A55),
    accent: Color(0xFF2457D6),
    onAccent: Color(0xFFFFFFFF),
    secondaryAccent: Color(0xFF7A3FE0),
    amber: Color(0xFFC98A00),
    nowLine: Color(0xFFD6314F),
    error: Color(0xFFD6314F),
    textPrimary: Color(0xFF12161C),
    textMuted: Color(0xFF5B6472),
    cardColorA: Color(0xFF2457D6),
    cardColorB: Color(0xFF7A3FE0),
  );

  static const yellow = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF14120A),
    surface: Color(0xFF1C1810),
    surfaceRaised: Color(0xFF241E13),
    border: Color(0x33F5B942),
    borderStrong: Color(0x66F5B942),
    accent: Color(0xFFF5B942),
    onAccent: Color(0xFF241900),
    secondaryAccent: Color(0xFFE8823C),
    amber: Color(0xFFFFC94D),
    nowLine: Color(0xFFFF5470),
    error: Color(0xFFFF5470),
    textPrimary: Color(0xFFF5EFE3),
    textMuted: Color(0xFFA69A82),
    cardColorA: Color(0xFFF5B942),
    cardColorB: Color(0xFFE8823C),
  );

  static const green = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0A140F),
    surface: Color(0xFF0F1D16),
    surfaceRaised: Color(0xFF15271C),
    border: Color(0x3336D98A),
    borderStrong: Color(0x6636D98A),
    accent: Color(0xFF36D98A),
    onAccent: Color(0xFF00241A),
    secondaryAccent: Color(0xFFA6D936),
    amber: Color(0xFFE0C23A),
    nowLine: Color(0xFFFF5470),
    error: Color(0xFFFF5470),
    textPrimary: Color(0xFFE7F5EE),
    textMuted: Color(0xFF7FA592),
    cardColorA: Color(0xFF36D98A),
    cardColorB: Color(0xFFA6D936),
  );
}

/// Тема оформления, которую пользователь выбирает в настройках. Хранится и
/// восстанавливается между запусками приложения (см. LocalStore).
enum AppThemeVariant { dark, light, yellow, green }

extension AppThemeVariantX on AppThemeVariant {
  AppPalette get palette {
    switch (this) {
      case AppThemeVariant.dark:
        return AppPalettes.dark;
      case AppThemeVariant.light:
        return AppPalettes.light;
      case AppThemeVariant.yellow:
        return AppPalettes.yellow;
      case AppThemeVariant.green:
        return AppPalettes.green;
    }
  }

  String get label {
    final ru = Strings.current == AppLocale.ru;
    switch (this) {
      case AppThemeVariant.dark:
        return ru ? 'Тёмная' : 'Dark';
      case AppThemeVariant.light:
        return ru ? 'Светлая' : 'Light';
      case AppThemeVariant.yellow:
        return ru ? 'Жёлтая' : 'Yellow';
      case AppThemeVariant.green:
        return ru ? 'Зелёная' : 'Green';
    }
  }

  static AppThemeVariant fromName(String? name) {
    return AppThemeVariant.values.firstWhere(
      (v) => v.name == name,
      orElse: () => AppThemeVariant.dark,
    );
  }
}

/// Текущая палитра приложения. Меняется через ScheduleController.setThemeVariant
/// (который также перечитывает и сохраняет выбор), после чего весь экран
/// перестраивается (main.dart слушает тот же контроллер) и виджеты, читающие
/// AppColors.* в build(), получают уже новые цвета.
class AppColors {
  AppColors._();

  static AppPalette current = AppPalettes.dark;

  static Color get background => current.background;
  static Color get surface => current.surface;
  static Color get surfaceRaised => current.surfaceRaised;
  static Color get border => current.border;
  static Color get borderStrong => current.borderStrong;

  static Color get accent => current.accent;
  static Color get onAccent => current.onAccent;
  static Color get violet => current.secondaryAccent;
  static Color get amber => current.amber;
  static Color get nowLine => current.nowLine;
  static Color get error => current.error;

  static Color get textPrimary => current.textPrimary;
  static Color get textMuted => current.textMuted;

  static Color get cardColorA => current.cardColorA;
  static Color get cardColorB => current.cardColorB;
}

/// Строит ThemeData для конкретной темы оформления. Специально не завязано
/// на системную светлую/тёмную тему телефона — пользователь выбирает тему
/// сам, в настройках приложения.
class AppTheme {
  AppTheme._();

  static ThemeData themeDataFor(AppThemeVariant variant) {
    final p = variant.palette;

    final colorScheme = p.brightness == Brightness.dark
        ? ColorScheme.dark(
            surface: p.surface,
            primary: p.accent,
            onPrimary: p.onAccent,
            secondary: p.secondaryAccent,
            onSecondary: Colors.white,
            error: p.error,
            onSurface: p.textPrimary,
          )
        : ColorScheme.light(
            surface: p.surface,
            primary: p.accent,
            onPrimary: p.onAccent,
            secondary: p.secondaryAccent,
            onSecondary: Colors.white,
            error: p.error,
            onSurface: p.textPrimary,
          );

    final base = ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.background,
      dividerColor: p.border,
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accent,
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.accent, width: 1.4),
        ),
        hintStyle: TextStyle(color: p.textMuted),
      ),
      listTileTheme: ListTileThemeData(
        textColor: p.textPrimary,
        iconColor: p.textMuted,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    );
  }
}

/// Бордюрная панель без тени — базовый "строгий" контейнер, которым во всём
/// приложении заменена стандартная материаловская Card с тенью.
class AppPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: child,
    );
  }
}

/// Маленькая заглавная подпись вразрядку — используется вместо обычных
/// подзаголовков там, где нужен более "технический" акцент.
class AppEyebrow extends StatelessWidget {
  final String text;
  final Color? color;

  const AppEyebrow({super.key, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: color ?? AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}
