import 'package:flutter/material.dart';

import '../localization.dart';
import '../models/faculty.dart';
import '../models/group.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';

/// Последовательный выбор учебного подразделения: факультет, курс, группа.
/// Сохранять отдельно факультет и курс не нужно: выбранная группа уже содержит
/// оба значения и хранится контроллером между запусками приложения.
class GroupSelectScreen extends StatefulWidget {
  final ScheduleController controller;
  final bool isChangingGroup;

  const GroupSelectScreen({
    super.key,
    required this.controller,
    this.isChangingGroup = false,
  });

  @override
  State<GroupSelectScreen> createState() => _GroupSelectScreenState();
}

class _GroupSelectScreenState extends State<GroupSelectScreen> {
  int? _facultyId;
  int? _courseNumber;

  @override
  void initState() {
    super.initState();
    if (widget.isChangingGroup && widget.controller.selectedGroupId != null) {
      final selected = widget.controller.data.groups.cast<Group?>().firstWhere(
            (group) => group?.id == widget.controller.selectedGroupId,
            orElse: () => null,
          );
      _facultyId = selected?.facultyId;
      _courseNumber = selected?.courseNumber;
    }
  }

  List<Faculty> _faculties() {
    if (widget.controller.data.faculties.isNotEmpty) {
      return widget.controller.data.faculties;
    }

    // Совместимость со снимком расписания, сохранённым старой версией:
    // факультеты восстанавливаются из полей групп до следующей синхронизации.
    final result = <Faculty>[];
    final seen = <int>{};
    for (final group in widget.controller.data.groups) {
      if (!seen.add(group.facultyId)) continue;
      result.add(Faculty(
        id: group.facultyId,
        name: group.facultyNameRu?.trim().isNotEmpty == true
            ? group.facultyNameRu!
            : 'ФРиКТ',
        nameEn: group.facultyNameEn,
      ));
    }
    return result;
  }

  bool _goBackOneStep() {
    if (_courseNumber != null) {
      setState(() => _courseNumber = null);
      return true;
    }
    if (_facultyId != null) {
      setState(() => _facultyId = null);
      return true;
    }
    return false;
  }

  String get _title {
    if (_facultyId == null) return Strings.selectFaculty;
    if (_courseNumber == null) return Strings.selectCourse;
    return Strings.selectGroup;
  }

  String get _backLabel =>
      _courseNumber != null ? Strings.backToCourses : Strings.backToFaculties;

  void _selectFacultyStep() => setState(() {
        _facultyId = null;
        _courseNumber = null;
      });

  void _selectCourseStep() => setState(() => _courseNumber = null);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _facultyId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBackOneStep();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _facultyId != null
              ? IconButton(
                  tooltip: _backLabel,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _goBackOneStep,
                )
              : null,
          title: Text(Strings.groupSelectionTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: Strings.settingsTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(controller: widget.controller),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => Column(
              children: [
                _buildSteps(),
                if (_facultyId != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextButton.icon(
                        key: const ValueKey('group-selection-back'),
                        onPressed: _goBackOneStep,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: Text(_backLabel),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppEyebrow(text: _title),
                  ),
                ),
                Expanded(child: _buildStep()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSteps() {
    final selectedFaculty =
        _faculties().where((faculty) => faculty.id == _facultyId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _SelectionStep(
              key: const ValueKey('faculty-step'),
              number: 1,
              label: Strings.facultyLabel,
              value: selectedFaculty?.name ?? Strings.choose,
              isCurrent: _facultyId == null,
              onTap: _facultyId == null ? null : _selectFacultyStep,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SelectionStep(
              key: const ValueKey('course-step'),
              number: 2,
              label: Strings.courseLabel,
              value: _courseNumber == null
                  ? Strings.choose
                  : Strings.course(_courseNumber!),
              isCurrent: _facultyId != null && _courseNumber == null,
              onTap: _facultyId != null && _courseNumber != null
                  ? _selectCourseStep
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SelectionStep(
              number: 3,
              label: Strings.groupLabel,
              value: Strings.choose,
              isCurrent: _courseNumber != null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    final faculties = _faculties();
    if (_facultyId == null) {
      if (faculties.isEmpty) return _empty(Strings.noFacultiesAvailable);
      return _refreshableList(
        itemCount: faculties.length,
        itemBuilder: (context, index) {
          final faculty = faculties[index];
          final count = widget.controller.data.groups
              .where((group) => group.facultyId == faculty.id)
              .length;
          return _ChoiceTile(
            title: faculty.name,
            subtitle: Strings.groupsCount(count),
            icon: Icons.account_balance_rounded,
            onTap: () => setState(() {
              _facultyId = faculty.id;
              _courseNumber = null;
            }),
          );
        },
      );
    }

    if (_courseNumber == null) {
      return _refreshableList(
        itemCount: 4,
        itemBuilder: (context, index) {
          final course = index + 1;
          final count = widget.controller.data.groups
              .where((group) =>
                  group.facultyId == _facultyId && group.courseNumber == course)
              .length;
          return _ChoiceTile(
            title: Strings.course(course),
            subtitle: Strings.groupsCount(count),
            icon: Icons.school_rounded,
            onTap: () => setState(() => _courseNumber = course),
          );
        },
      );
    }

    final groups = widget.controller.data.groups
        .where((group) =>
            group.facultyId == _facultyId &&
            group.courseNumber == _courseNumber)
        .toList();
    if (groups.isEmpty) return _empty(Strings.noGroupsForCourse);

    return _refreshableList(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return _ChoiceTile(
          title: group.name,
          subtitle: group.specialization,
          icon: Icons.groups_rounded,
          selected: widget.controller.selectedGroupId == group.id,
          onTap: () => _selectGroup(group),
        );
      },
    );
  }

  Widget _refreshableList({
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
  }) {
    return RefreshIndicator(
      onRefresh: () => widget.controller.sync(force: true),
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: itemBuilder,
      ),
    );
  }

  Widget _empty(String message) {
    return RefreshIndicator(
      onRefresh: () => widget.controller.sync(force: true),
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
          if (widget.controller.isSyncing)
            Center(child: CircularProgressIndicator(color: AppColors.accent))
          else ...[
            Icon(Icons.info_outline_rounded,
                size: 44, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: () => widget.controller.sync(force: true),
                child: Text(Strings.refresh),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectGroup(Group group) async {
    await widget.controller.selectGroup(group.id);
    if (!mounted) return;
    if (widget.isChangingGroup) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScheduleScreen(controller: widget.controller),
        ),
      );
    }
  }
}

class _SelectionStep extends StatelessWidget {
  final int number;
  final String label;
  final String value;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _SelectionStep({
    super.key,
    required this.number,
    required this.label,
    required this.value,
    required this.isCurrent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        selected: isCurrent,
        child: Material(
          color: isCurrent
              ? AppColors.accent.withValues(alpha: 0.1)
              : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
                color: isCurrent ? AppColors.accent : AppColors.border),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$number. $label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? AppColors.accent
                              : AppColors.textMuted)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ),
                      if (onTap != null)
                        Icon(Icons.expand_more_rounded,
                            size: 16, color: AppColors.accent),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ChoiceTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (hasSubtitle)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          subtitle!,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? AppColors.accent : AppColors.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
