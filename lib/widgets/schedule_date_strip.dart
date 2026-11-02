import 'package:flutter/material.dart';
import '../localization.dart';
import '../theme.dart';

/// Непрерывная лента дат: дни идут друг за другом (не только текущая
/// неделя), у каждого — день недели и число. При открытии экрана сама
/// прокручивается к сегодняшнему дню, а дальше можно листать вперёд и назад
/// на несколько лет в обе стороны.
class ScheduleDateStrip extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;

  const ScheduleDateStrip(
      {super.key, required this.selectedDate, required this.onSelect});

  @override
  State<ScheduleDateStrip> createState() => _ScheduleDateStripState();
}

class _ScheduleDateStripState extends State<ScheduleDateStrip> {
  // ~5.5 года в каждую сторону от сегодня — с запасом достаточно, чтобы
  // ощущаться как бесконечная прокрутка, но список остаётся конечным и
  // строится лениво (ListView.builder), так что размер диапазона почти не
  // влияет на производительность.
  static const int _rangeDays = 2000;
  static const double _chipWidth = 54;
  static const double _chipGap = 6;

  late final DateTime _today;
  late final DateTime _anchorDate;
  final ScrollController _scrollController = ScrollController();
  bool _didInitialScroll = false;
  DateTime? _lastScrolledDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _anchorDate = DateTime(_today.year, _today.month, _today.day - _rangeDays);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToDate(DateTime date, {bool animate = false}) {
    final index = DateTime.utc(date.year, date.month, date.day)
        .difference(
            DateTime.utc(_anchorDate.year, _anchorDate.month, _anchorDate.day))
        .inDays;
    const itemExtent = _chipWidth + _chipGap * 2;
    final target = index * itemExtent - 90;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final clamped = target < 0 ? 0.0 : (target > max ? max : target);
      if (animate) {
        _scrollController.animateTo(clamped,
            duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(clamped);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_didInitialScroll) {
      _didInitialScroll = true;
      _lastScrolledDate = widget.selectedDate;
      _scrollToDate(widget.selectedDate);
    } else if (_lastScrolledDate?.year != widget.selectedDate.year ||
        _lastScrolledDate?.month != widget.selectedDate.month ||
        _lastScrolledDate?.day != widget.selectedDate.day) {
      _lastScrolledDate = widget.selectedDate;
      _scrollToDate(widget.selectedDate, animate: true);
    }

    const totalDays = _rangeDays * 2 + 1;
    final textScaler = MediaQuery.textScalerOf(context);
    final height =
        ((textScaler.scale(11) + textScaler.scale(15) + textScaler.scale(9.5)) *
                    1.2 +
                16)
            .clamp(60.0, double.infinity);

    return SizedBox(
      height: height,
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: totalDays,
        itemBuilder: (context, index) {
          final date = DateTime(
              _anchorDate.year, _anchorDate.month, _anchorDate.day + index);
          final selected = date.year == widget.selectedDate.year &&
              date.month == widget.selectedDate.month &&
              date.day == widget.selectedDate.day;
          final isToday = date.year == _today.year &&
              date.month == _today.month &&
              date.day == _today.day;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: _chipGap),
            child: GestureDetector(
              onTap: () => widget.onSelect(date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _chipWidth,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? AppColors.accent
                        : (isToday ? AppColors.borderStrong : AppColors.border),
                    width: isToday && !selected ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      Strings.dayShort(date.weekday),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        height: 1.2,
                        letterSpacing: 0.3,
                        color:
                            selected ? AppColors.onAccent : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${date.day}',
                      maxLines: 1,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.2,
                        color: selected
                            ? AppColors.onAccent
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      Strings.monthShort(date.month),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 9.5,
                        height: 1.2,
                        color: selected
                            ? AppColors.onAccent.withValues(alpha: 0.85)
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
