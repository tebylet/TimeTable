import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'localization.dart';
import 'screens/group_select_screen.dart';
import 'screens/schedule_screen.dart';
import 'services/sync_service.dart';
import 'theme.dart';

void main() {
  runApp(const YmTimeTableApp());
}

class YmTimeTableApp extends StatefulWidget {
  const YmTimeTableApp({super.key});

  @override
  State<YmTimeTableApp> createState() => _YmTimeTableAppState();
}

class _YmTimeTableAppState extends State<YmTimeTableApp> {
  final ScheduleController _controller = ScheduleController();
  late AppThemeVariant _themeVariant;
  late AppLocale _locale;

  @override
  void initState() {
    super.initState();
    _themeVariant = _controller.themeVariant;
    _locale = _controller.locale;
    _controller.addListener(_onPresentationChanged);
    _controller.init();
  }

  void _onPresentationChanged() {
    if (_themeVariant == _controller.themeVariant &&
        _locale == _controller.locale) {
      return;
    }
    setState(() {
      _themeVariant = _controller.themeVariant;
      _locale = _controller.locale;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onPresentationChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Network/update progress only rebuilds its consumers. The application
    // shell and theme change when the user's presentation preferences change.
    return MaterialApp(
      title: 'Para',
      debugShowCheckedModeBanner: false,
      locale: Locale(_locale.name),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Тема выбирается пользователем в настройках (тёмная/светлая/
      // жёлтая/зелёная) и не привязана к системной теме телефона —
      // см. lib/theme.dart.
      theme: AppTheme.themeDataFor(_themeVariant),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (!_controller.isReady) {
            return Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            );
          }
          final isTeacher = _controller.hasStaffSchedule;
          if (_controller.selectedGroupId == null && !isTeacher) {
            return GroupSelectScreen(controller: _controller);
          }
          return ScheduleScreen(controller: _controller);
        },
      ),
    );
  }
}
