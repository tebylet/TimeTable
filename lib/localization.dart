/// Язык интерфейса приложения. У групп и предметов сервер также может
/// прислать необязательный английский вариант; при его отсутствии модели
/// автоматически показывают обязательное русское название.
/// Хранится и восстанавливается между запусками, см. LocalStore.
enum AppLocale { ru, en }

extension AppLocaleX on AppLocale {
  String get label {
    switch (this) {
      case AppLocale.ru:
        return 'Русский';
      case AppLocale.en:
        return 'English';
    }
  }

  static AppLocale fromName(String? name) {
    return AppLocale.values
        .firstWhere((l) => l.name == name, orElse: () => AppLocale.ru);
  }
}

/// Тексты интерфейса на двух языках. Аналогично AppColors из theme.dart —
/// лёгкий фасад поверх мутируемого статического поля `current`: весь экран
/// пересобирается при смене языка (ScheduleController.setLocale вызывает
/// notifyListeners, а main.dart слушает контроллер), поэтому виджеты,
/// читающие Strings.xxx в build(), сразу получают перевод на новом языке.
class Strings {
  Strings._();

  static AppLocale current = AppLocale.ru;

  static bool get _ru => current == AppLocale.ru;

  // Общее
  static String get schedule => _ru ? 'Расписание' : 'Schedule';
  static String get mySchedule => _ru ? 'Моё расписание' : 'My schedule';
  static String get settingsTitle => _ru ? 'Настройки' : 'Settings';
  static String get scheduleSections =>
      _ru ? 'Разделы расписания' : 'Schedule sections';
  static String get statistics => _ru ? 'Статистика' : 'Statistics';

  // Экзамены
  static String get exams => _ru ? 'Экзамены' : 'Exams';
  static String get examsByDate => _ru ? 'По дате' : 'By date';
  static String get examsBySubject => _ru ? 'По предмету' : 'By subject';
  static String get selectExamSubject =>
      _ru ? 'Выберите предмет' : 'Select a subject';
  static String get allExamSubjects => _ru ? 'Все предметы' : 'All subjects';
  static String get noExamsOnDate =>
      _ru ? 'На эту дату экзаменов нет' : 'No exams on this date';
  static String get noExamsScheduled =>
      _ru ? 'Расписание экзаменов пока не добавлено' : 'No exams scheduled yet';
  static String get noExamsForSubject =>
      _ru ? 'По этому предмету экзаменов нет' : 'No exams for this subject';
  static String get examSubjectHint => _ru
      ? 'Выберите предмет, чтобы увидеть все даты его экзаменов.'
      : 'Select a subject to see all its exam dates.';
  static String get nextExam => _ru ? 'Ближайший экзамен' : 'Next exam';
  static String get viewExamDay => _ru ? 'Показать день' : 'Show this day';
  static String get previousDay => _ru ? 'Предыдущий день' : 'Previous day';
  static String get nextDay => _ru ? 'Следующий день' : 'Next day';

  // Выбор факультета, курса и группы
  static String get groupSelectionTitle =>
      _ru ? 'Выбор группы' : 'Choose your group';
  static String get facultyLabel => _ru ? 'Факультет' : 'Faculty';
  static String get courseLabel => _ru ? 'Курс' : 'Year';
  static String get choose => _ru ? 'Выбрать' : 'Choose';
  static String get backToFaculties =>
      _ru ? 'К выбору факультета' : 'Back to faculties';
  static String get backToCourses => _ru ? 'К выбору курса' : 'Back to years';
  static String get selectFaculty =>
      _ru ? 'Выберите факультет' : 'Select a faculty';
  static String get selectCourse => _ru ? 'Выберите курс' : 'Select a year';
  static String get selectGroup => _ru ? 'Выберите группу' : 'Select a group';
  static String course(int number) => _ru ? '$number курс' : 'Year $number';
  static String groupsCount(int count) => _ru
      ? '$count ${count == 1 ? 'группа' : count >= 2 && count <= 4 ? 'группы' : 'групп'}'
      : '$count ${count == 1 ? 'group' : 'groups'}';
  static String get noFacultiesAvailable => _ru
      ? 'Список факультетов пока недоступен.'
      : 'The faculty list is not available yet.';
  static String get noGroupsForCourse => _ru
      ? 'Для этого курса группы пока не добавлены.'
      : 'No groups have been added for this year yet.';
  static String get changeGroup => _ru ? 'Сменить группу' : 'Change group';
  static String get currentGroup => _ru ? 'Текущая группа' : 'Current group';
  static String get noGroupsAvailable => _ru
      ? 'Список групп пока недоступен.\nПроверьте подключение к интернету.'
      : 'The list of groups isn\'t available yet.\nCheck your internet connection.';
  static String get refresh => _ru ? 'Обновить' : 'Refresh';

  // Настройки — темы и язык
  static String get themeSection => _ru ? 'Тема оформления' : 'Theme';
  static String get languageSection => _ru ? 'Язык' : 'Language';

  // Настройки — восстановление синхронизации после смены сертификата
  static String get certificateMismatchNotice => _ru
      ? 'Сертификат сервера не подтверждён — возможно, администратор его '
          'перегенерировал (например, после смены IP-адреса). Обновите доверенный '
          'сертификат ниже.'
      : 'The server\'s certificate isn\'t confirmed — the administrator may have '
          'regenerated it (for example, after an IP address change). Trust the '
          'certificate again below.';
  static String get trustServerCertificateAgain => _ru
      ? 'Обновить доверенный сертификат сервера'
      : 'Trust server certificate again';

  // Настройки — синхронизация
  static String get syncSection => _ru ? 'Синхронизация' : 'Sync';
  static String get neverSynced =>
      _ru ? 'Ещё не синхронизировалось' : 'Not synced yet';
  static String lastSyncStatus(String syncedAt, bool ok) {
    final result = ok
        ? (_ru ? 'успешно' : 'success')
        : (_ru
            ? 'не удалось (нет интернета/сервера)'
            : 'failed (no internet/server)');
    return _ru
        ? 'Последняя синхронизация: $syncedAt\nРезультат: $result'
        : 'Last sync: $syncedAt\nResult: $result';
  }

  static String get syncing => _ru ? 'Синхронизация...' : 'Syncing...';
  static String get syncNow => _ru ? 'Синхронизировать сейчас' : 'Sync now';
  static String get developerCredit =>
      _ru ? 'Разработчик: YM' : 'Developer: YM';

  // Настройки — обновление приложения
  static String get finishUpdate =>
      _ru ? 'Установить и перезапустить' : 'Install and restart';
  static String get updateWithGooglePlay =>
      _ru ? 'Обновить через Google Play' : 'Update with Google Play';
  static String get openGooglePlay =>
      _ru ? 'Открыть Google Play' : 'Open Google Play';
  static String get openAppStore =>
      _ru ? 'Открыть App Store' : 'Open App Store';
  static String get openTestFlight =>
      _ru ? 'Открыть TestFlight' : 'Open TestFlight';
  static String get remindLater =>
      _ru ? 'Напомнить завтра' : 'Remind me tomorrow';
  static String get updateReady => _ru
      ? 'Обновление загружено. Установите его, когда будет удобно.'
      : 'Update downloaded. Install when you are ready.';
  static String get updateSection =>
      _ru ? 'Обновление приложения' : 'App update';
  static String currentVersion(String versionName) => _ru
      ? 'Установленная версия: $versionName'
      : 'Installed version: $versionName';
  static String get checkForUpdates =>
      _ru ? 'Проверить обновления' : 'Check for updates';
  static String get checkingForUpdates => _ru ? 'Проверка...' : 'Checking...';
  static String get noUpdateAvailable =>
      _ru ? 'Доступных обновлений нет' : 'No updates available';
  static String get updateCheckFailed =>
      _ru ? 'Не удалось проверить обновления' : 'Couldn\'t check for updates';
  static String newVersionAvailable(String versionName) => versionName.isEmpty
      ? (_ru ? 'Доступна новая версия' : 'An update is available')
      : (_ru
          ? 'Доступна новая версия $versionName'
          : 'Version $versionName is available');
  static String get downloadAndInstall =>
      _ru ? 'Скачать и установить' : 'Download and install';
  static String get updateNotesTitle => _ru ? 'Что нового:' : 'What\'s new:';
  static String get updateBannerText =>
      _ru ? 'Вышла новая версия приложения' : 'A new app version is available';
  static String get updateBannerAction => _ru ? 'Подробнее' : 'Details';

  // Настройки — процесс скачивания/установки обновления (см. installUpdate()
  // в ScheduleController — установка через выбранный канал,
  // без перехода в браузер).
  static String downloadingUpdate(int? percent) {
    final p = percent != null ? ' $percent%' : '';
    return _ru ? 'Загрузка обновления...$p' : 'Downloading update...$p';
  }

  static String get installingUpdate => _ru ? 'Установка...' : 'Installing...';
  static String get updateInstallCanceled =>
      _ru ? 'Установка отменена' : 'Installation canceled';
  static String get updateInstallGenericError =>
      _ru ? 'Не удалось установить обновление' : 'Couldn\'t install the update';
  static String get updateInstallPermissionNeeded => _ru
      ? 'Разрешите установку из этого источника в открывшихся настройках Android и попробуйте снова'
      : 'Allow installs from this source in the Android settings that just opened, then try again';

  // Расписание дня
  static String get noClassesToday =>
      _ru ? 'На этот день занятий нет' : 'No classes on this day';
  static String get repeatedSchedule => _ru
      ? 'Новая неделя ещё не опубликована — показано последнее расписание'
      : 'The new week is not published yet — showing the latest timetable';
  static String get noServerConnection => _ru
      ? 'Нет связи с сервером — показано последнее сохранённое расписание'
      : 'No connection to the server — showing the last saved schedule';
  static String get today => _ru ? 'Сегодня' : 'Today';
  static String get chooseDate => _ru ? 'Выбрать дату' : 'Choose a date';
  static String get groupLabel => _ru ? 'Группа' : 'Group';
  static String get evenWeek => _ru ? 'Чётная неделя' : 'Even week';
  static String get oddWeek => _ru ? 'Нечётная неделя' : 'Odd week';
  static String get roomShort => _ru ? 'ауд.' : 'room';

  // Подгруппы: у некоторых занятий на один и тот же слот стоят две записи —
  // "нечётная" и "чётная" — это на самом деле не "раз в две недели", а две
  // разные подгруппы, каждая ходит по своей чётности. Студент выбирает
  // свою подгруппу тапом по занятию в расписании (хранится только на
  // телефоне, см. ScheduleController.setSubgroupPreference).
  static String get subgroupSectionTitle => _ru ? 'Подгруппа' : 'Subgroup';
  static String get subgroupHint => _ru
      ? 'У этого занятия чередуются подгруппы. Выберите свою — тогда занятия '
          'другой подгруппы больше не будут показываться в вашем расписании.'
      : 'This class alternates between two subgroups. Pick yours and the '
          'other subgroup’s classes will stop showing up in your schedule.';
  static String get subgroupByActualWeek =>
      _ru ? 'По факту недели (по умолчанию)' : 'By actual week (default)';
  static String get subgroupOddOnly =>
      _ru ? 'Я хожу по нечётным неделям' : 'I attend on odd weeks';
  static String get subgroupEvenOnly =>
      _ru ? 'Я хожу по чётным неделям' : 'I attend on even weeks';
  static String get close => _ru ? 'Закрыть' : 'Close';

  // Вход преподавателей/администраторов (настройки приложения). Сама
  // проверка логина/пароля и блокировка после неверных попыток — на
  // сервере (см. appAuth.js), здесь только UI и готовые тексты для
  // ошибок, которые приложение не может предсказать заранее.
  static String get staffLoginSection => _ru ? 'Авторизация' : 'Authorization';
  static String get usernameLabel => _ru ? 'Логин' : 'Username';
  static String get passwordLabel => _ru ? 'Пароль' : 'Password';
  static String get showPassword => _ru ? 'Показать пароль' : 'Show password';
  static String get hidePassword => _ru ? 'Скрыть пароль' : 'Hide password';
  static String get loginButton => _ru ? 'Войти' : 'Sign in';
  static String get loggingIn => _ru ? 'Вход...' : 'Signing in...';
  static String get loginNetworkError => _ru
      ? 'Не удалось связаться с сервером. Проверьте подключение к интернету.'
      : 'Couldn\'t reach the server. Check your internet connection.';
  static String get loginFieldsRequired =>
      _ru ? 'Введите логин и пароль' : 'Enter your username and password';
  static String get notLoggedIn =>
      _ru ? 'Нужно войти в приложении' : 'You need to sign in first';
  static String loggedInAs(String name) =>
      _ru ? 'Вы вошли как $name' : 'Signed in as $name';
  static String get roleAdmin => _ru ? 'Администратор' : 'Administrator';
  static String get roleTeacher => _ru ? 'Преподаватель' : 'Teacher';
  static String get roleCoordinator =>
      _ru ? 'Координатор курса' : 'Course coordinator';
  static String get courseSchedule =>
      _ru ? 'Расписание курса' : 'Course schedule';
  static String get messageTargetCourse =>
      _ru ? 'Все группы моего курса' : 'All groups in my course';
  static String get changeLessonAction =>
      _ru ? 'Перенести / обновить занятие' : 'Reschedule / update session';
  static String get restoreOriginalLesson =>
      _ru ? 'Вернуть исходное расписание' : 'Restore original session';
  static String get lessonUpdateNote =>
      _ru ? 'Обновление занятия' : 'Session update';
  static String get rescheduleLesson => _ru ? 'Перенос' : 'Reschedule';
  static String get changeLessonRoom => _ru ? 'Новая аудитория' : 'Room change';
  static String get lessonNoteLabel =>
      _ru ? 'Причина / примечание' : 'Reason / note';
  static String get newLessonDate => _ru ? 'Новая дата' : 'New date';
  static String get lessonStartTime => _ru ? 'Начало (HH:mm)' : 'Start (HH:mm)';
  static String get lessonEndTime => _ru ? 'Окончание (HH:mm)' : 'End (HH:mm)';
  static String get lessonRoomLabel => _ru ? 'Аудитория' : 'Room';
  static String get saveAndNotify =>
      _ru ? 'Сохранить и уведомить группу' : 'Save and notify group';
  static String get fillLessonFields => _ru
      ? 'Проверьте дату, время и обязательные поля'
      : 'Check the date, times and required fields';
  static String newRoom(String room) =>
      _ru ? 'Новая аудитория: $room' : 'New room: $room';
  static String rescheduledTo(String date, String start, String end) => _ru
      ? 'Перенесено на $date, $start–$end'
      : 'Rescheduled to $date, $start–$end';
  static String originalSessionDate(String date) => _ru
      ? 'Исходная дата: $date. Изменяется только одно занятие.'
      : 'Original date: $date. Only this session changes.';
  static String get logoutButton => _ru ? 'Выйти' : 'Sign out';

  // Отмена занятий (доступно вошедшим преподавателям/админам)
  static String get lessonManageSectionTitle =>
      _ru ? 'Управление занятием' : 'Manage this class';
  static String get cancelLessonAction =>
      _ru ? 'Отменить это занятие' : 'Cancel this class';
  static String get cancelLessonDialogTitle =>
      _ru ? 'Отменить занятие?' : 'Cancel this class?';
  static String get cancelLessonReasonHint =>
      _ru ? 'Причина (необязательно)' : 'Reason (optional)';
  static String get cancelLessonConfirm =>
      _ru ? 'Отменить занятие' : 'Cancel class';
  static String get dialogCancel => _ru ? 'Отмена' : 'Cancel';
  static String get restoreLessonAction =>
      _ru ? 'Восстановить занятие' : 'Restore class';
  static String get lessonCancelledBadge => _ru ? 'ОТМЕНЕНО' : 'CANCELED';
  static String lessonCancelledNotice(String? reason) {
    if (reason == null || reason.isEmpty) {
      return _ru ? 'Занятие отменено' : 'This class has been canceled';
    }
    return _ru
        ? 'Занятие отменено: $reason'
        : 'This class has been canceled: $reason';
  }

  // Чат (лента сообщений от преподавателей/админов)
  static String get chatTitle => _ru ? 'Чат' : 'Chat';
  static String get deleteMessage =>
      _ru ? 'Удалить сообщение' : 'Delete message';
  static String get deleteMessageConfirmation => _ru
      ? 'Сообщение будет удалено у всех получателей. Удалить?'
      : 'This message will be deleted for all recipients. Delete it?';
  static String get deleteOwnMessagesOnly => _ru
      ? 'Можно удалять только свои сообщения'
      : 'You can only delete your own messages';
  static String get chatEmpty => _ru ? 'Сообщений пока нет' : 'No messages yet';
  static String get messageComposeHint =>
      _ru ? 'Написать сообщение...' : 'Write a message...';
  static String get messageTargetAllGroups => _ru ? 'Все группы' : 'All groups';
  static String get messageSentTagAll => _ru ? 'Всем группам' : 'To all groups';
  static String get messagesFilterAll => _ru ? 'Все сообщения' : 'All messages';
  static String get messagesFilterMine =>
      _ru ? 'Отправленные мной' : 'Sent by me';
  static String get chatEmptyMine =>
      _ru ? 'Вы ещё ничего не отправляли' : 'You haven\'t sent anything yet';

  // Дни недели и месяцы (1-based, индекс 0 не используется)
  static const List<String> _dayShortRu = [
    '',
    'Пн',
    'Вт',
    'Ср',
    'Чт',
    'Пт',
    'Сб',
    'Вс'
  ];
  static const List<String> _dayShortEn = [
    '',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun'
  ];
  static const List<String> _dayFullRu = [
    '',
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];
  static const List<String> _dayFullEn = [
    '',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> _monthShortRu = [
    '',
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];
  static const List<String> _monthShortEn = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String dayShort(int weekday) =>
      (_ru ? _dayShortRu : _dayShortEn)[weekday];
  static String dayFull(int weekday) =>
      (_ru ? _dayFullRu : _dayFullEn)[weekday];
  static String monthShort(int month) =>
      (_ru ? _monthShortRu : _monthShortEn)[month];
}
