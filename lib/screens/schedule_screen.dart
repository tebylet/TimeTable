import '../widgets/schedule_date_strip.dart';
import 'admin_statistics_screen.dart';
import 'exams_screen.dart';
import '../models/app_user.dart';
import 'package:flutter/material.dart';

import '../localization.dart';
import '../models/schedule_entry.dart';
import '../models/schedule_data.dart';
import 'lesson_update_dialog.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../utils/week_parity.dart';
import '../widgets/schedule_day_view.dart';
import 'chat_screen.dart';
import 'group_select_screen.dart';
import 'settings_screen.dart';

class ScheduleScreen extends StatefulWidget {
  final ScheduleController controller;

  const ScheduleScreen({super.key, required this.controller});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int _selectedSection = 0;
  late DateTime _selectedDate; // всегда дата без времени (год/месяц/день)

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(DateTime.now());
  }

  void _selectDate(DateTime date) {
    setState(() => _selectedDate = _dateOnly(date));
  }

  Future<void> _openCalendar() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: Strings.chooseDate,
      cancelText: Strings.dialogCancel,
    );
    if (selected != null && mounted) _selectDate(selected);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    final teacherMode = controller.hasStaffSchedule;
    if (controller.selectedGroupId == null && !teacherMode) {
      return GroupSelectScreen(controller: controller);
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isAdmin = controller.appUser?.role == AppRole.admin;
        if (!isAdmin && _selectedSection > 1) _selectedSection = 0;
        final showExams = _selectedSection == 1;
        final showStatistics = isAdmin && _selectedSection == 2;
        final isTeacherSchedule = controller.hasStaffSchedule;
        final groupId = controller.selectedGroupId;
        final group = controller.data.groupById(groupId);
        final groupName = isTeacherSchedule
            ? (controller.appUser?.role == AppRole.coordinator
                ? Strings.courseSchedule
                : Strings.mySchedule)
            : group?.name ?? Strings.schedule;
        final sectionMenu = _ScheduleSectionMenu(
          selectedSection: _selectedSection,
          isAdmin: isAdmin,
          scopeTitle: showStatistics ? null : groupName,
          onSelected: (section) => setState(() => _selectedSection = section),
        );

        final todayDateOnly = _dateOnly(DateTime.now());
        final isToday = _selectedDate.year == todayDateOnly.year &&
            _selectedDate.month == todayDateOnly.month &&
            _selectedDate.day == todayDateOnly.day;

        // Чётность недели считается для выбранной даты, а не всегда для
        // "сегодня" — иначе при пролистывании на другие недели расписание
        // показывало бы не те занятия.
        final currentParity =
            weekParityOn(controller.data.semesterStartDate, _selectedDate);

        final dayEntries = controller.entriesOnDate(_selectedDate);
        final usesPreviousWeek = dayEntries.any((entry) =>
            entry.sourceWeekStart != null &&
            !_selectedDate
                .isBefore(entry.sourceWeekStart!.add(const Duration(days: 7))));

        return Scaffold(
          appBar: showStatistics
              ? null
              : AppBar(
                  toolbarHeight:
                      (MediaQuery.textScalerOf(context).scale(18) * 1.2 +
                              MediaQuery.textScalerOf(context).scale(12) * 1.2 +
                              12)
                          .clamp(kToolbarHeight, double.infinity),
                  title: sectionMenu,
                  actions: [
                    IconButton(
                      icon: Badge(
                        isLabelVisible: controller.unreadMessagesCount > 0,
                        label: Text('${controller.unreadMessagesCount}'),
                        child: const Icon(Icons.chat_bubble_outline_rounded),
                      ),
                      tooltip: Strings.chatTitle,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(controller: controller)),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded),
                      tooltip: Strings.settingsTitle,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                SettingsScreen(controller: controller)),
                      ),
                    ),
                  ],
                ),
          body: SafeArea(
            top: false,
            child: showStatistics
                ? AdminStatisticsScreen(
                    key: ValueKey(
                        '${controller.serverUrl}/${controller.appUser!.id}'),
                    controller: controller,
                    navigationTitle: sectionMenu,
                  )
                : showExams
                    ? ExamsScreen(controller: controller)
                    : Column(
                        children: [
                          if (controller.showUpdateBanner)
                            _UpdateBanner(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        SettingsScreen(controller: controller)),
                              ),
                            ),
                          if (!controller.lastSyncOk &&
                              controller.lastSyncAt != null)
                            _StatusBanner(
                              color: AppColors.amber,
                              icon: Icons.cloud_off_rounded,
                              text: Strings.noServerConnection,
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _ParityBadge(parity: currentParity),
                                  ),
                                ),
                                if (!isToday)
                                  IconButton(
                                    tooltip: Strings.today,
                                    icon: Icon(Icons.today_rounded,
                                        color: AppColors.accent),
                                    onPressed: () =>
                                        _selectDate(DateTime.now()),
                                  ),
                                IconButton(
                                  tooltip: Strings.chooseDate,
                                  icon: Icon(Icons.calendar_month_rounded,
                                      color: AppColors.accent),
                                  onPressed: _openCalendar,
                                ),
                              ],
                            ),
                          ),
                          ScheduleDateStrip(
                              selectedDate: _selectedDate,
                              onSelect: _selectDate),
                          const SizedBox(height: 4),
                          if (usesPreviousWeek)
                            _StatusBanner(
                              color: AppColors.textMuted,
                              icon: Icons.repeat_rounded,
                              text: Strings.repeatedSchedule,
                            ),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: () => controller.sync(force: true),
                              color: AppColors.accent,
                              backgroundColor: AppColors.surface,
                              child: ScheduleDayView(
                                entries: dayEntries,
                                isToday: isToday,
                                showGroup: isTeacherSchedule,
                                cancelledForEntry: (entry) => controller.data
                                    .cancelledLessonsOn(DateTime.parse(
                                        entry.originalDate ??
                                            ScheduleData.isoDate(
                                                _selectedDate)))[entry.id],
                                cancelledLessons: controller.data
                                    .cancelledLessonsOn(_selectedDate),
                                onEntryTap: (entry) => _showEntrySheet(
                                    context, controller, entry, _selectedDate),
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        );
      },
    );
  }
}

class _ScheduleSectionMenu extends StatelessWidget {
  final int selectedSection;
  final bool isAdmin;
  final String? scopeTitle;
  final ValueChanged<int> onSelected;

  const _ScheduleSectionMenu({
    required this.selectedSection,
    required this.isAdmin,
    required this.scopeTitle,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final labels = [
      Strings.schedule,
      Strings.exams,
      if (isAdmin) Strings.statistics
    ];
    return PopupMenuButton<int>(
      key: const ValueKey('schedule-section-menu'),
      tooltip: Strings.scheduleSections,
      position: PopupMenuPosition.under,
      color: AppColors.surfaceRaised,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.borderStrong),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (var index = 0; index < labels.length; index++)
          CheckedPopupMenuItem<int>(
            value: index,
            checked: selectedSection == index,
            child: Text(labels[index],
                style: TextStyle(
                    color: selectedSection == index
                        ? AppColors.accent
                        : AppColors.textPrimary)),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(labels[selectedSection],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18,
                          height: 1.2,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more_rounded, size: 22),
              ],
            ),
            if (scopeTitle != null && scopeTitle != labels[selectedSection])
              Text(scopeTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12, height: 1.2)),
          ],
        ),
      ),
    );
  }
}

/// Открывает карточку занятия снизу экрана. Для обычных занятий — просто
/// подробности (на случай, если текст в блоке был обрезан). Для занятий,
/// которые чередуются по подгруппам (см. ScheduleController.hasSubgroupSplit
/// — то же время/пара, но одна запись "нечётная", другая "чётная"), там же
/// можно выбрать свою подгруппу — тогда занятия другой подгруппы перестанут
/// показываться в расписании этого телефона.
void _showEntrySheet(
  BuildContext context,
  ScheduleController controller,
  ScheduleEntry entry,
  DateTime date,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final isTeacher = controller.hasStaffSchedule;
          final split = !isTeacher && controller.hasSubgroupSplit(entry);
          final current = controller.subgroupPreferenceFor(entry);
          final cancelledInfo = controller.data.cancelledLessonsOn(
              DateTime.parse(
                  entry.originalDate ?? ScheduleData.isoDate(date)))[entry.id];
          final canManage = controller.canCancelLesson(entry);
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.subject,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        decoration: cancelledInfo != null
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${Strings.dayFull(entry.dayOfWeek)} · ${entry.startTime}–${entry.endTime}',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                    if (isTeacher && entry.groupName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${Strings.groupLabel}: ${entry.groupName}',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (cancelledInfo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.event_busy_rounded,
                                  size: 15, color: AppColors.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  Strings.lessonCancelledNotice(
                                      cancelledInfo.reason),
                                  style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (entry.teacherDisplay.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          entry.teacherDisplay,
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 13.5),
                        ),
                      ),
                    if (entry.room != null && entry.room!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: RoomBadge(room: entry.room!),
                      ),
                    if (entry.notes != null && entry.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          entry.notes!,
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    if (split) ...[
                      const SizedBox(height: 16),
                      Divider(color: AppColors.border, height: 1),
                      const SizedBox(height: 14),
                      Text(
                        Strings.subgroupSectionTitle,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Strings.subgroupHint,
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      _SubgroupOption(
                        label: Strings.subgroupByActualWeek,
                        selected: current == null,
                        onTap: () async {
                          await controller.setSubgroupPreference(entry, null);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                      ),
                      _SubgroupOption(
                        label: Strings.subgroupOddOnly,
                        selected: current == WeekParity.odd,
                        onTap: () async {
                          await controller.setSubgroupPreference(
                              entry, WeekParity.odd);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                      ),
                      _SubgroupOption(
                        label: Strings.subgroupEvenOnly,
                        selected: current == WeekParity.even,
                        onTap: () async {
                          await controller.setSubgroupPreference(
                              entry, WeekParity.even);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                      ),
                    ],
                    if (canManage) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          icon: const Icon(Icons.edit_calendar),
                          label: Text(Strings.changeLessonAction),
                          onPressed: () => editSessionUpdate(
                              sheetContext, controller, entry, date)),
                      if (entry.updateKind != null)
                        OutlinedButton.icon(
                            icon: const Icon(Icons.undo),
                            label: Text(Strings.restoreOriginalLesson),
                            onPressed: () => restoreSessionUpdate(
                                sheetContext, controller, entry, date)),
                      const SizedBox(height: 16),
                      Divider(color: AppColors.border, height: 1),
                      const SizedBox(height: 14),
                      Text(
                        Strings.lessonManageSectionTitle,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: cancelledInfo != null
                            ? OutlinedButton.icon(
                                icon: const Icon(Icons.event_available_rounded,
                                    size: 17),
                                label: Text(Strings.restoreLessonAction),
                                onPressed: () => _restoreLesson(
                                    sheetContext, controller, entry, date),
                              )
                            : OutlinedButton.icon(
                                icon: Icon(Icons.event_busy_rounded,
                                    size: 17, color: AppColors.error),
                                label: Text(Strings.cancelLessonAction,
                                    style: TextStyle(color: AppColors.error)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: AppColors.error
                                          .withValues(alpha: 0.5)),
                                ),
                                onPressed: () => _confirmCancelLesson(
                                    sheetContext, controller, entry, date),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// Диалог с необязательной причиной перед отменой конкретного занятия —
/// отменяется только это одно занятие на конкретную дату, повторяющаяся
/// запись в расписании остаётся и снова появится на следующей неделе.
Future<void> _confirmCancelLesson(
  BuildContext sheetContext,
  ScheduleController controller,
  ScheduleEntry entry,
  DateTime date,
) async {
  final reason = await showDialog<String>(
    context: sheetContext,
    builder: (_) => const _CancelReasonDialog(),
  );
  if (reason == null || !sheetContext.mounted) return;

  final messenger = ScaffoldMessenger.of(sheetContext);
  try {
    await controller.cancelLesson(entry, date,
        reason: reason.isEmpty ? null : reason);
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
  } catch (e) {
    if (messenger.mounted) {
      messenger.showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : '$e')));
    }
  }
}

class _CancelReasonDialog extends StatefulWidget {
  const _CancelReasonDialog();

  @override
  State<_CancelReasonDialog> createState() => _CancelReasonDialogState();
}

class _CancelReasonDialogState extends State<_CancelReasonDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(Strings.cancelLessonDialogTitle,
          style: TextStyle(color: AppColors.textPrimary)),
      content: TextField(
        controller: _reasonController,
        autofocus: true,
        style: TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(hintText: Strings.cancelLessonReasonHint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(Strings.dialogCancel),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pop(_reasonController.text.trim()),
          child: Text(Strings.cancelLessonConfirm),
        ),
      ],
    );
  }
}

Future<void> _restoreLesson(
  BuildContext sheetContext,
  ScheduleController controller,
  ScheduleEntry entry,
  DateTime date,
) async {
  final messenger = ScaffoldMessenger.of(sheetContext);
  try {
    await controller.restoreLesson(entry, date);
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
  } catch (e) {
    if (messenger.mounted) {
      messenger.showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : '$e')));
    }
  }
}

class _SubgroupOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SubgroupOption(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? AppColors.accent : AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Уведомление о доступном обновлении приложения — показывается вверху
/// экрана расписания, если ScheduleController.checkForUpdate() нашёл на
/// сервере версию новее установленной. Тап открывает настройки, где можно
/// посмотреть подробности и скачать/установить обновление.
class _UpdateBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _UpdateBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.system_update_rounded,
                  size: 15, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Strings.updateBannerText,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                Strings.updateBannerAction,
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _StatusBanner(
      {required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}

class _ParityBadge extends StatelessWidget {
  final WeekParity parity;

  const _ParityBadge({required this.parity});

  @override
  Widget build(BuildContext context) {
    if (parity == WeekParity.all) return const SizedBox.shrink();
    final isOdd = parity == WeekParity.odd;
    final color = isOdd ? AppColors.violet : AppColors.accent;
    final label = isOdd ? Strings.oddWeek : Strings.evenWeek;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
