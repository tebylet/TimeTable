import 'package:flutter/material.dart';
import '../localization.dart';
import '../models/lesson_update.dart';
import '../models/schedule_data.dart';
import '../models/schedule_entry.dart';
import '../services/sync_service.dart';

Future<void> editSessionUpdate(BuildContext context,
    ScheduleController controller, ScheduleEntry entry, DateTime date) async {
  final originalDate = entry.originalDate ?? ScheduleData.isoDate(date);
  LessonUpdate? existing;
  for (final update in controller.data.lessonUpdates) {
    if (update.entryId == entry.id && update.date == originalDate) {
      existing = update;
    }
  }
  final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SessionUpdateDialog(
          entry: entry,
          date: date,
          originalDate: originalDate,
          existing: existing));
  if (value == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await controller.saveLessonUpdate(entry, date, value);
    if (context.mounted) Navigator.of(context).pop();
  } catch (error) {
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

Future<void> restoreSessionUpdate(BuildContext context,
    ScheduleController controller, ScheduleEntry entry, DateTime date) async {
  final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
              title: Text(Strings.restoreOriginalLesson),
              content: Text(Strings.originalSessionDate(
                  entry.originalDate ?? ScheduleData.isoDate(date))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: Text(Strings.dialogCancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: Text(Strings.restoreOriginalLesson))
              ]));
  if (accepted != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await controller.restoreLessonUpdate(entry, date);
    if (context.mounted) Navigator.pop(context);
  } catch (error) {
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _SessionUpdateDialog extends StatefulWidget {
  final ScheduleEntry entry;
  final DateTime date;
  final String originalDate;
  final LessonUpdate? existing;
  const _SessionUpdateDialog(
      {required this.entry,
      required this.date,
      required this.originalDate,
      this.existing});
  @override
  State<_SessionUpdateDialog> createState() => _SessionUpdateDialogState();
}

class _SessionUpdateDialogState extends State<_SessionUpdateDialog> {
  final _form = GlobalKey<FormState>();
  late String _kind;
  late final TextEditingController _date, _start, _end, _room, _notes;
  @override
  void initState() {
    super.initState();
    _kind = widget.existing?.kind ?? 'rescheduled';
    _date = TextEditingController(
        text: widget.existing?.newDate ?? ScheduleData.isoDate(widget.date));
    _start = TextEditingController(text: widget.entry.startTime);
    _end = TextEditingController(text: widget.entry.endTime);
    _room = TextEditingController(text: widget.entry.room ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    for (final input in [_date, _start, _end, _room, _notes]) {
      input.dispose();
    }
    super.dispose();
  }

  String? _time(String? value) =>
      value != null && RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)
          ? null
          : Strings.fillLessonFields;
  Future<void> _pickDate() async {
    final current = DateTime.parse(_date.text);
    final picked = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime(current.year - 10),
        lastDate: DateTime(current.year + 10, 12, 31));
    if (picked != null && mounted) _date.text = ScheduleData.isoDate(picked);
  }

  void _save() {
    if (_form.currentState?.validate() != true) return;
    if (_kind == 'rescheduled' && _start.text.compareTo(_end.text) >= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(Strings.fillLessonFields)));
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'kind': _kind,
      'notes': _notes.text.trim(),
      if (_kind == 'rescheduled') ...{
        'newDate': _date.text,
        'startTime': _start.text,
        'endTime': _end.text
      },
      if (_kind != 'note') 'room': _room.text.trim()
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          scrollable: true,
          title: Text(Strings.lessonUpdateNote),
          content: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Strings.originalSessionDate(widget.originalDate)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        initialValue: _kind,
                        items: [
                          DropdownMenuItem(
                              value: 'rescheduled',
                              child: Text(Strings.rescheduleLesson)),
                          DropdownMenuItem(
                              value: 'room_changed',
                              child: Text(Strings.changeLessonRoom)),
                          DropdownMenuItem(
                              value: 'note',
                              child: Text(Strings.lessonUpdateNote)),
                        ],
                        onChanged: (value) => setState(() => _kind = value!)),
                    if (_kind == 'rescheduled') ...[
                      TextFormField(
                          controller: _date,
                          readOnly: true,
                          onTap: _pickDate,
                          decoration: InputDecoration(
                              labelText: Strings.newLessonDate)),
                      TextFormField(
                          controller: _start,
                          validator: _time,
                          keyboardType: TextInputType.datetime,
                          decoration: InputDecoration(
                              labelText: Strings.lessonStartTime)),
                      TextFormField(
                          controller: _end,
                          validator: _time,
                          keyboardType: TextInputType.datetime,
                          decoration: InputDecoration(
                              labelText: Strings.lessonEndTime)),
                    ],
                    if (_kind != 'note')
                      TextFormField(
                          controller: _room,
                          maxLength: 200,
                          validator: (value) => _kind == 'room_changed' &&
                                  (value?.trim().isEmpty ?? true)
                              ? Strings.fillLessonFields
                              : null,
                          decoration: InputDecoration(
                              labelText: Strings.lessonRoomLabel)),
                    TextFormField(
                        controller: _notes,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        validator: (value) =>
                            _kind == 'note' && (value?.trim().isEmpty ?? true)
                                ? Strings.fillLessonFields
                                : null,
                        decoration: InputDecoration(
                            labelText: Strings.lessonNoteLabel)),
                  ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(Strings.dialogCancel)),
            FilledButton(onPressed: _save, child: Text(Strings.saveAndNotify))
          ]);
}
