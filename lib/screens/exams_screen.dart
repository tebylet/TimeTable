import 'package:flutter/material.dart';

import '../localization.dart';
import '../models/exam_entry.dart';
import '../models/schedule_data.dart';
import '../models/schedule_entry.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../widgets/schedule_date_strip.dart';
import '../widgets/schedule_day_view.dart';

/// Exam dates use the same timeline as classes, with a separate subject lookup.
class ExamsScreen extends StatefulWidget {
  final ScheduleController controller;
  final String scopeTitle;
  final DateTime? initialDate;

  const ExamsScreen(
      {super.key,
      required this.controller,
      this.scopeTitle = '',
      this.initialDate});

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  late DateTime _date;
  bool _bySubject = false;
  int? _subjectId;

  @override
  void initState() {
    super.initState();
    final date = widget.initialDate ?? DateTime.now();
    _date = DateTime(date.year, date.month, date.day);
  }

  void _selectDate(DateTime value) => setState(() {
        _date = DateTime(value.year, value.month, value.day);
      });

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(_date.year - 10),
        lastDate: DateTime(_date.year + 10, 12, 31),
        helpText: Strings.chooseDate,
        cancelText: Strings.dialogCancel);
    if (selected != null && mounted) _selectDate(selected);
  }

  String _dateLabel(String date) {
    final day = DateTime.parse(date);
    return '${Strings.dayFull(day.weekday)}, ${day.day} '
        '${Strings.monthShort(day.month)} ${day.year}';
  }

  String _subjectLabel(
      ExamEntry exam, List<ExamEntry> exams, List<ExamEntry> choices) {
    if (choices.where((item) => item.subject == exam.subject).length < 2) {
      return exam.subject;
    }
    final matching = exams.where((item) => item.subjectId == exam.subjectId);
    return [
      exam.subject,
      matching
          .map((item) => item.groupName)
          .where((name) => name.isNotEmpty)
          .toSet()
          .join(', '),
      matching
          .map((item) => item.teacherDisplay)
          .where((name) => name.isNotEmpty)
          .toSet()
          .join(', '),
      _dateLabel(matching.first.date),
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  ScheduleEntry _timelineEntry(ExamEntry exam) => ScheduleEntry(
      id: exam.id,
      groupId: exam.groupId,
      dayOfWeek: DateTime.parse(exam.date).weekday,
      period: 1,
      startTime: exam.startTime,
      endTime: exam.endTime,
      subject: exam.subjectRu,
      subjectEn: exam.subjectEn,
      groupNameRu: exam.groupNameRu,
      groupNameEn: exam.groupNameEn,
      teacherId: exam.teacherId,
      teacher: exam.teacher,
      teacherTitle: exam.teacherTitle,
      room: exam.room,
      notes: exam.notes);

  void _showDetails(ExamEntry exam) {
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        builder: (sheet) => SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppEyebrow(text: Strings.exams),
                      const SizedBox(height: 8),
                      Text(exam.subject,
                          style: Theme.of(sheet).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      Text(_dateLabel(exam.date)),
                      Text('${exam.startTime}–${exam.endTime}'),
                      if (exam.groupName.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                                '${Strings.groupLabel}: ${exam.groupName}')),
                      if (exam.teacherDisplay.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(exam.teacherDisplay)),
                      if (exam.room?.isNotEmpty == true)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: RoomBadge(room: exam.room!)),
                      if (exam.notes?.isNotEmpty == true)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(exam.notes!)),
                      const SizedBox(height: 16),
                      Wrap(spacing: 12, children: [
                        TextButton(
                            onPressed: () => Navigator.pop(sheet),
                            child: Text(Strings.close)),
                        FilledButton.tonal(
                            onPressed: () {
                              Navigator.pop(sheet);
                              setState(() {
                                _bySubject = false;
                                _date = DateTime.parse(exam.date);
                              });
                            },
                            child: Text(Strings.viewExamDay))
                      ])
                    ]))));
  }

  Widget _empty(String text) => CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 16)))))
          ]);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final exams = controller.visibleExams;
        final subjects = <int, ExamEntry>{};
        for (final exam in exams) {
          subjects.putIfAbsent(exam.subjectId, () => exam);
        }
        final choices = subjects.values.toList()
          ..sort((a, b) => a.subject.compareTo(b.subject));
        if (_subjectId != null && !subjects.containsKey(_subjectId)) {
          _subjectId = null;
        }
        final filtered = _subjectId == null
            ? exams
            : exams.where((exam) => exam.subjectId == _subjectId).toList();
        final iso = ScheduleData.isoDate(_date);
        final dayExams = exams.where((exam) => exam.date == iso).toList();
        final now = DateTime.now();
        final today = ScheduleData.isoDate(now);
        final time = '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}';
        final upcoming = exams.where((exam) =>
            exam.date.compareTo(today) > 0 ||
            (exam.date == today && exam.endTime.compareTo(time) >= 0));
        final next = upcoming.isEmpty ? null : upcoming.first;
        return Column(children: [
          if (!controller.lastSyncOk && controller.lastSyncAt != null)
            Container(
                width: double.infinity,
                color: AppColors.amber.withValues(alpha: 0.12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(Strings.noServerConnection,
                    style: TextStyle(color: AppColors.amber))),
          if (controller.isSyncing) const LinearProgressIndicator(),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.scopeTitle.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppEyebrow(text: widget.scopeTitle)),
                    SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                              value: false,
                              icon: const Icon(Icons.calendar_month),
                              label: Text(Strings.examsByDate)),
                          ButtonSegment(
                              value: true,
                              icon: const Icon(Icons.menu_book_outlined),
                              label: Text(Strings.examsBySubject))
                        ],
                        selected: {
                          _bySubject
                        },
                        onSelectionChanged: (selection) => setState(() {
                              _bySubject = selection.first;
                            })),
                  ])),
          if (_bySubject) ...[
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: InputDecorator(
                    decoration: InputDecoration(
                        labelText: Strings.selectExamSubject,
                        border: const OutlineInputBorder()),
                    child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                            key: const ValueKey('exam-subject-filter'),
                            value: _subjectId ?? 0,
                            isExpanded: true,
                            isDense: true,
                            items: [
                              DropdownMenuItem(
                                  value: 0,
                                  child: Text(Strings.allExamSubjects)),
                              for (final exam in choices)
                                DropdownMenuItem(
                                    key: ValueKey(
                                        'exam-subject-${exam.subjectId}'),
                                    value: exam.subjectId,
                                    child: Text(
                                        _subjectLabel(exam, exams, choices),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis))
                            ],
                            onChanged: (id) => setState(() {
                                  _subjectId = id == 0 ? null : id;
                                }))))),
          ] else ...[
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  IconButton(
                      tooltip: Strings.previousDay,
                      onPressed: () => _selectDate(
                          DateTime(_date.year, _date.month, _date.day - 1)),
                      icon: const Icon(Icons.chevron_left)),
                  Expanded(
                      child: Text(_dateLabel(iso),
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  IconButton(
                      tooltip: Strings.nextDay,
                      onPressed: () => _selectDate(
                          DateTime(_date.year, _date.month, _date.day + 1)),
                      icon: const Icon(Icons.chevron_right)),
                  IconButton(
                      tooltip: Strings.chooseDate,
                      onPressed: _chooseDate,
                      icon: const Icon(Icons.calendar_month_outlined)),
                ])),
            ScheduleDateStrip(selectedDate: _date, onSelect: _selectDate),
            if (next != null && next.date != iso)
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: () => _selectDate(DateTime.parse(next.date)),
                      icon: const Icon(Icons.event_available, size: 18),
                      label: Text(Strings.nextExam))),
          ],
          Expanded(
              child: RefreshIndicator(
                  onRefresh: () => controller.sync(force: true),
                  child: _bySubject
                      ? (filtered.isEmpty
                          ? _empty(exams.isEmpty
                              ? Strings.noExamsScheduled
                              : Strings.noExamsForSubject)
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final exam = filtered[index];
                                return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          if (index == 0 ||
                                              filtered[index - 1].date !=
                                                  exam.date)
                                            Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 12),
                                                child: Text(
                                                    _dateLabel(exam.date),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700))),
                                          Material(
                                              color: AppColors.surface,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  side: BorderSide(
                                                      color: AppColors.border)),
                                              clipBehavior: Clip.antiAlias,
                                              child: ListTile(
                                                  onTap: () =>
                                                      _showDetails(exam),
                                                  title: Text(exam.subject),
                                                  subtitle: Text([
                                                    '${exam.startTime}–${exam.endTime}',
                                                    if (controller
                                                            .hasStaffSchedule &&
                                                        exam.groupName
                                                            .isNotEmpty)
                                                      '${Strings.groupLabel}: ${exam.groupName}',
                                                    if (exam.teacherDisplay
                                                        .isNotEmpty)
                                                      exam.teacherDisplay,
                                                    if (exam.room?.isNotEmpty ==
                                                        true)
                                                      '${Strings.roomShort} ${exam.room}',
                                                  ].join('\n')),
                                                  trailing: const Icon(
                                                      Icons.chevron_right))),
                                        ]));
                              }))
                      : ScheduleDayView(
                          key: ValueKey('exam-day-$iso'),
                          entries: dayExams.map(_timelineEntry).toList(),
                          isToday: iso == today,
                          showGroup: controller.hasStaffSchedule,
                          emptyMessage: exams.isEmpty
                              ? Strings.noExamsScheduled
                              : Strings.noExamsOnDate,
                          onEntryTap: (entry) => _showDetails(dayExams
                              .firstWhere((exam) => exam.id == entry.id)),
                        )))
        ]);
      });
}
