import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../localization.dart';
import '../models/cancelled_lesson.dart';
import '../models/schedule_entry.dart';
import '../theme.dart';

/// Раскладка одного дня в виде временной шкалы (как в календаре): каждое
/// занятие — блок, расположенный и растянутый пропорционально времени, часы
/// подписаны слева. Для сегодняшнего дня через шкалу проходит "линия
/// текущего времени" — она сама сдвигается вниз, пока экран открыт.
class ScheduleDayView extends StatefulWidget {
  final List<ScheduleEntry> entries;
  final bool isToday;
  final bool showGroup;
  final String? emptyMessage;

  /// Supplies local wall time; tests can advance it across lesson boundaries.
  final DateTime Function()? clock;
  final ValueChanged<ScheduleEntry>? onEntryTap;
  // Отменённые конкретно на отображаемую дату занятия (ключ — id записи в
  // расписании) — см. ScheduleData.cancelledLessonsOn(). Такие занятия не
  // прячутся из расписания, а показываются перечёркнутыми, с пометкой.
  final Map<int, CancelledLesson> cancelledLessons;
  final CancelledLesson? Function(ScheduleEntry)? cancelledForEntry;

  const ScheduleDayView({
    super.key,
    required this.entries,
    required this.isToday,
    this.showGroup = false,
    this.emptyMessage,
    this.clock,
    this.onEntryTap,
    this.cancelledLessons = const {},
    this.cancelledForEntry,
  });

  @override
  State<ScheduleDayView> createState() => _ScheduleDayViewState();
}

class _ScheduleDayViewState extends State<ScheduleDayView> {
  static const double _pxPerMinute = 1.35;
  static const int _defaultStartMinute = 8 * 60; // 08:00
  static const int _defaultEndMinute = 21 * 60; // 21:00
  static const double _gutterWidth = 56; // ширина колонки с подписями часов

  Timer? _ticker;
  final ScrollController _scrollController = ScrollController();
  bool _scrolledToNow = false;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  DateTime _readNow() => widget.clock?.call() ?? DateTime.now();

  void _scheduleTick() {
    _ticker?.cancel();
    if (!widget.isToday) return;
    // Keep the existing half-minute cadence, aligned to wall time so every
    // lesson's HH:mm start/end is refreshed at the boundary itself.
    const interval = 30 * Duration.microsecondsPerSecond;
    final delay = interval - _readNow().microsecondsSinceEpoch % interval;
    _ticker = Timer(Duration(microseconds: delay), () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  void didUpdateWidget(covariant ScheduleDayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isToday != widget.isToday ||
        oldWidget.clock != widget.clock) {
      _scrolledToNow = false;
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  static int _parseMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.emptyMessage ?? Strings.noClassesToday,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Видимый диапазон шкалы — учебный день с 8 до 21, но расширяется, если
    // реальные занятия выходят за эти границы (например, ранняя практика).
    var startMinute = _defaultStartMinute;
    var endMinute = _defaultEndMinute;
    for (final e in widget.entries) {
      final s = _parseMinutes(e.startTime);
      final en = _parseMinutes(e.endTime);
      if (s < startMinute) startMinute = s;
      if (en > endMinute) endMinute = en;
    }
    startMinute = (startMinute ~/ 60) * 60;
    endMinute = ((endMinute + 59) ~/ 60) * 60;
    if (endMinute <= startMinute) endMinute = startMinute + 60;

    final totalMinutes = endMinute - startMinute;
    final totalHeight = totalMinutes * _pxPerMinute;

    final now = _readNow();
    final nowMinute = now.hour * 60 +
        now.minute +
        now.second / 60 +
        now.millisecond / 60000 +
        now.microsecond / 60000000;
    double yForMinute(num minute) => (minute - startMinute) * _pxPerMinute;
    final showNowLine =
        widget.isToday && nowMinute >= startMinute && nowMinute <= endMinute;

    if (showNowLine && !_scrolledToNow) {
      _scrolledToNow = true;
      final target = yForMinute(nowMinute) - 160;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final max = _scrollController.position.maxScrollExtent;
        _scrollController
            .jumpTo(target < 0 ? 0 : (target > max ? max : target));
      });
    }

    final placedEntries = _layoutColumns(widget.entries);

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: SizedBox(
        height: totalHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final usableWidth = constraints.maxWidth - _gutterWidth - 12;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                _HourGrid(
                    startMinute: startMinute,
                    endMinute: endMinute,
                    pxPerMinute: _pxPerMinute,
                    gutterWidth: _gutterWidth),
                for (final p in placedEntries)
                  _EntryBlock(
                    key: ObjectKey(p.entry),
                    entry: p.entry,
                    colorIndex: p.colorIndex,
                    top: yForMinute(_parseMinutes(p.entry.startTime)),
                    height: (_parseMinutes(p.entry.endTime) -
                            _parseMinutes(p.entry.startTime)) *
                        _pxPerMinute,
                    left:
                        _gutterWidth + p.column * (usableWidth / p.columnCount),
                    width: (usableWidth / p.columnCount) - 6,
                    onTap: widget.onEntryTap == null
                        ? null
                        : () => widget.onEntryTap!(p.entry),
                    cancelled: widget.cancelledForEntry != null
                        ? widget.cancelledForEntry!(p.entry)
                        : widget.cancelledLessons[p.entry.id],
                    showGroup: widget.showGroup,
                  ),
                if (showNowLine)
                  Positioned(
                    top: yForMinute(nowMinute) - 1,
                    left: _gutterWidth,
                    right: 12,
                    height: 2,
                    child: IgnorePointer(
                        child: CustomPaint(
                            key: const ValueKey('current-time-line'),
                            painter: _NowLinePainter(
                                color: AppColors.nowLine,
                                excluded: [
                                  // Stroke thickness must never paint over a card
                                  // before its start or at/after its exclusive end.
                                  for (final p in placedEntries)
                                    if (nowMinute <
                                            _parseMinutes(p.entry.startTime) ||
                                        nowMinute >=
                                            _parseMinutes(p.entry.endTime))
                                      Rect.fromLTWH(
                                          p.column *
                                              (usableWidth / p.columnCount),
                                          yForMinute(_parseMinutes(
                                                  p.entry.startTime)) -
                                              (yForMinute(nowMinute) - 1),
                                          (usableWidth / p.columnCount) - 6,
                                          (_parseMinutes(p.entry.endTime) -
                                                  _parseMinutes(
                                                      p.entry.startTime)) *
                                              _pxPerMinute),
                                ]))),
                  ),
                if (showNowLine)
                  Positioned(
                    top: yForMinute(nowMinute),
                    left: 4,
                    width: _gutterWidth - 12,
                    child: FractionalTranslation(
                        translation: const Offset(0, -0.5),
                        child: _NowTimeLabel(time: now)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Раскладывает занятия по колонкам: пересекающиеся по времени (например,
  /// параллельные подгруппы в одном слоте) делят ширину экрана между собой,
  /// а не накладываются друг на друга. Также присваивает каждому занятию
  /// индекс 0/1 по порядку начала — по нему карточки в _EntryBlock
  /// раскрашиваются в два чередующихся цвета.
  List<_PlacedEntry> _layoutColumns(List<ScheduleEntry> entries) {
    final sorted = [...entries]..sort((a, b) =>
        _parseMinutes(a.startTime).compareTo(_parseMinutes(b.startTime)));

    final colorIndexById = <int, int>{
      for (var i = 0; i < sorted.length; i++) sorted[i].id: i % 2,
    };

    final result = <_PlacedEntry>[];
    var i = 0;
    while (i < sorted.length) {
      var clusterEnd = _parseMinutes(sorted[i].endTime);
      var j = i + 1;
      while (j < sorted.length &&
          _parseMinutes(sorted[j].startTime) < clusterEnd) {
        final en = _parseMinutes(sorted[j].endTime);
        if (en > clusterEnd) clusterEnd = en;
        j++;
      }

      final cluster = sorted.sublist(i, j);
      final columnEnds = <int>[];
      final clusterPlacements = <_PlacedEntry>[];

      for (final e in cluster) {
        final start = _parseMinutes(e.startTime);
        var col = -1;
        for (var c = 0; c < columnEnds.length; c++) {
          if (columnEnds[c] <= start) {
            col = c;
            break;
          }
        }
        if (col == -1) {
          col = columnEnds.length;
          columnEnds.add(_parseMinutes(e.endTime));
        } else {
          columnEnds[col] = _parseMinutes(e.endTime);
        }
        clusterPlacements.add(_PlacedEntry(
          entry: e,
          column: col,
          columnCount: 0,
          colorIndex: colorIndexById[e.id] ?? 0,
        ));
      }

      final columnCount = columnEnds.length;
      for (final p in clusterPlacements) {
        result.add(_PlacedEntry(
          entry: p.entry,
          column: p.column,
          columnCount: columnCount,
          colorIndex: p.colorIndex,
        ));
      }
      i = j;
    }
    return result;
  }
}

class _PlacedEntry {
  final ScheduleEntry entry;
  final int column;
  final int columnCount;
  final int colorIndex;

  _PlacedEntry({
    required this.entry,
    required this.column,
    required this.columnCount,
    required this.colorIndex,
  });
}

class _HourGrid extends StatelessWidget {
  final int startMinute;
  final int endMinute;
  final double pxPerMinute;
  final double gutterWidth;

  const _HourGrid(
      {required this.startMinute,
      required this.endMinute,
      required this.pxPerMinute,
      required this.gutterWidth});

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    for (var m = startMinute; m <= endMinute; m += 60) {
      final top = (m - startMinute) * pxPerMinute;
      final hh = (m ~/ 60).toString().padLeft(2, '0');
      lines.add(Positioned(
        top: top - 0.5,
        left: gutterWidth,
        right: 12,
        height: 1,
        child:
            ColoredBox(key: ValueKey('hour-line-$m'), color: AppColors.border),
      ));
      lines.add(Positioned(
        top: top,
        left: 12,
        width: gutterWidth - 24,
        child: FractionalTranslation(
          translation: const Offset(0, -0.5),
          child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$hh:00',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              )),
        ),
      ));
    }
    return Positioned.fill(
        child: Stack(clipBehavior: Clip.none, children: lines));
  }
}

class _EntryBlock extends StatelessWidget {
  final ScheduleEntry entry;
  final int colorIndex;
  final double top;
  final double height;
  final double left;
  final double width;
  final VoidCallback? onTap;
  final CancelledLesson? cancelled;
  final bool showGroup;

  const _EntryBlock({
    super.key,
    required this.entry,
    required this.colorIndex,
    required this.top,
    required this.height,
    required this.left,
    required this.width,
    this.onTap,
    this.cancelled,
    this.showGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final isCancelled = cancelled != null;
    final stripeColor = isCancelled
        ? AppColors.error
        : (colorIndex.isEven ? AppColors.cardColorA : AppColors.cardColorB);

    final safeWidth = width < 0 ? 0.0 : width;
    // A minimum card height would extend short sessions past their end time.
    final safeHeight = height < 0 ? 0.0 : height;

    return Positioned(
      top: top,
      left: left,
      width: safeWidth,
      height: safeHeight,
      child: Opacity(
        opacity: isCancelled ? 0.62 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isCancelled
                    ? AppColors.error.withValues(alpha: 0.5)
                    : AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: stripeColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: SingleChildScrollView(
                        physics: const NeverScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${entry.startTime}–${entry.endTime}',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                if (isCancelled) ...[
                                  const SizedBox(width: 6),
                                  _CancelledTag(),
                                ],
                              ],
                            ),
                            Text(
                              entry.subject,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                                decoration: isCancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: AppColors.error,
                              ),
                            ),
                            if (showGroup && entry.groupName.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '${Strings.groupLabel}: ${entry.groupName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (entry.teacherDisplay.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  entry.teacherDisplay,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.textMuted, fontSize: 11),
                                ),
                              ),
                            if (entry.room != null && entry.room!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: RoomBadge(room: entry.room!),
                              ),
                            if (entry.notes != null && entry.notes!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  entry.notes!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 10.5,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CancelledTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        Strings.lessonCancelledBadge,
        style: TextStyle(
          color: AppColors.error,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Небольшой цветной "чип" с номером аудитории — вынесен из обычного
/// приглушённого текста, чтобы кабинет было легко найти взглядом в карточке
/// занятия. Публичный виджет: переиспользуется и в карточке занятия
/// (ScheduleDayView), и в нижнем листе с подробностями (schedule_screen.dart).
class RoomBadge extends StatelessWidget {
  final String room;

  const RoomBadge({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.meeting_room_rounded, size: 11, color: AppColors.accent),
          const SizedBox(width: 3),
          Text(
            '${Strings.roomShort} $room',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NowTimeLabel extends StatelessWidget {
  final DateTime time;

  const _NowTimeLabel({required this.time});

  @override
  Widget build(BuildContext context) {
    final label =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return IgnorePointer(
      child: Container(
        key: const ValueKey('current-time-label'),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.nowLine,
          borderRadius: BorderRadius.circular(4),
        ),
        child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            )),
      ),
    );
  }
}

class _NowLinePainter extends CustomPainter {
  final Color color;
  final List<Rect> excluded;
  const _NowLinePainter({required this.color, required this.excluded});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    var visible = Path()..addRect(bounds);
    for (final rect in excluded) {
      if (rect.overlaps(bounds)) {
        visible = Path.combine(
            PathOperation.difference, visible, Path()..addRect(rect));
      }
    }
    canvas.save();
    canvas.clipPath(visible, doAntiAlias: false);
    canvas.drawRect(bounds, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NowLinePainter oldDelegate) =>
      color != oldDelegate.color || !listEquals(excluded, oldDelegate.excluded);
}
