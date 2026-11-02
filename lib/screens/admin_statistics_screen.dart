import 'dart:async';
import 'package:flutter/material.dart';
import '../localization.dart';
import '../models/app_user.dart';
import '../services/sync_service.dart';
import '../theme.dart';

String _label(String ru, String en) =>
    Strings.current == AppLocale.ru ? ru : en;
String _date(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
}

class AdminStatisticsScreen extends StatefulWidget {
  final ScheduleController controller;
  final Widget? navigationTitle;
  const AdminStatisticsScreen(
      {super.key, required this.controller, this.navigationTitle});
  @override
  State<AdminStatisticsScreen> createState() => _AdminStatisticsScreenState();
}

class _AdminStatisticsScreenState extends State<AdminStatisticsScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _refreshingStatistics = false;
  Map<String, dynamic>? _stats;
  final List<Map<String, dynamic>> _events = [];
  int? _cursor;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startRefresh();
  }

  void _startRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted ||
          _loading ||
          _refreshingStatistics ||
          ModalRoute.of(context)?.isCurrent != true ||
          widget.controller.appUser?.role != AppRole.admin) {
        return;
      }
      _refreshingStatistics = true;
      final user = widget.controller.appUser?.id;
      final server = widget.controller.serverUrl;
      try {
        final stats = await widget.controller.loadAdminStatistics();
        if (mounted &&
            user == widget.controller.appUser?.id &&
            server == widget.controller.serverUrl &&
            widget.controller.appUser?.role == AppRole.admin) {
          setState(() {
            _stats = stats;
            _error = null;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _stats = null;
            _events.clear();
            _cursor = null;
            _error = _label(
                'Не удалось обновить статистику. Проверьте подключение и права.',
                'Could not refresh statistics. Check connection and permissions.');
          });
        }
      } finally {
        _refreshingStatistics = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefresh();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || _refreshingStatistics) return;
    final userId = widget.controller.appUser?.id;
    final server = widget.controller.serverUrl;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        if (!more) widget.controller.loadAdminStatistics(),
        widget.controller.loadAdminAudit(before: more ? _cursor : null),
      ]);
      if (!mounted ||
          userId != widget.controller.appUser?.id ||
          server != widget.controller.serverUrl ||
          widget.controller.appUser?.role != AppRole.admin) {
        return;
      }
      setState(() {
        if (!more) {
          _stats = result.first;
          _events.clear();
        }
        final audit = result.last;
        _events.addAll((audit['items'] as List).cast<Map<String, dynamic>>());
        _cursor = audit['nextCursor'] as int?;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _label(
              'Не удалось загрузить данные. Проверьте подключение и права аккаунта.',
              'Could not load data. Check your connection and account permissions.');
          _stats = null;
          _events.clear();
          _cursor = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
              title: widget.navigationTitle ??
                  Text(_label('Статистика и журнал', 'Statistics and audit')),
              actions: [
                IconButton(
                    onPressed: _loading ? null : () => _load(),
                    tooltip: _label('Обновить', 'Refresh'),
                    icon: const Icon(Icons.refresh))
              ]),
          body: widget.controller.appUser?.role != AppRole.admin
              ? Center(
                  child: Text(_label('Доступ только для администратора',
                      'Administrators only')))
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16, 16, 16,
                        24 + MediaQuery.viewPaddingOf(context).bottom),
                    children: [
                      if (_loading) const LinearProgressIndicator(),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_error!)),
                      Text(
                          _label(
                              'Активные — приложение открыто на экране. При сворачивании статус снимается; при обрыве связи — в течение минуты. '
                                  'Новое посещение — после 30 минут отсутствия. Это число установок, а не людей.',
                              'Active means the app is on screen. Backgrounding clears the status; a lost connection expires within a minute. A new visit starts after 30 minutes away. Counts represent installations, not people.'),
                          style: TextStyle(color: AppColors.textMuted)),
                      const SizedBox(height: 12),
                      if (_stats != null) ...[
                        _metric(_label('Активные сейчас', 'Active now'),
                            _stats!['activeNow']),
                        for (final period in _stats!['periods'] as List)
                          _metric(_periodLabel(period['period'] as String),
                              period['visits']),
                        const SizedBox(height: 8),
                        Text(
                            _label('Календарные периоды, неделя с понедельника. Часовой пояс: ',
                                    'Calendar periods; weeks start on Monday. Time zone: ') +
                                _stats!['timeZone'],
                            style: TextStyle(color: AppColors.textMuted)),
                        Text(
                            _label('Учёт с: ', 'Tracking since: ') +
                                _date(_stats!['startedAt']),
                            style: TextStyle(color: AppColors.textMuted)),
                        Text(
                            _label('Обновлено: ', 'Updated: ') +
                                _date(_stats!['generatedAt']),
                            style: TextStyle(color: AppColors.textMuted)),
                      ],
                      const SizedBox(height: 24),
                      Text(_label('Действия сотрудников', 'Staff actions'),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600)),
                      Text(
                          _label('До 90 дней · до 50 000 событий',
                              'Up to 90 days · up to 50,000 events'),
                          style: TextStyle(color: AppColors.textMuted)),
                      if (_events.isEmpty && !_loading && _error == null)
                        Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16,
                                24 + MediaQuery.viewPaddingOf(context).bottom),
                            child: Text(
                                _label('Действий пока нет', 'No actions yet'))),
                      for (final event in _events) _event(event),
                      if (_cursor != null)
                        TextButton(
                            onPressed:
                                _loading ? null : () => _load(more: true),
                            child: Text(_label('Показать ещё', 'Show more'))),
                    ],
                  )),
        ),
      );

  String _periodLabel(String period) => switch (period) {
        'day' => _label('Посещения сегодня', 'Visits today'),
        'week' => _label('За эту неделю', 'This week'),
        'month' => _label('За этот месяц', 'This month'),
        _ => _label('За этот год', 'This year'),
      };

  Widget _metric(String label, Object count) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text('$count',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700))
        ]),
      );

  Widget _event(Map<String, dynamic> event) {
    final details = event['details'] as Map<String, dynamic>;
    final outcome = switch (event['outcome']) {
      'success' => _label('Успешно', 'Success'),
      'partial' => _label('Частично', 'Partial'),
      _ => _label('Ошибка / отказ', 'Failed / denied'),
    };
    final role = event['actorRole'] == 'system'
        ? _label('Автоматически', 'Automatic')
        : event['actorRole'] == 'admin'
            ? _label('Администратор', 'Administrator')
            : event['actorRole'] == 'coordinator'
                ? _label('Координатор курса', 'Course coordinator')
                : _label('Преподаватель', 'Teacher');
    final source = event['source'] == 'sync'
        ? _label('Синхронизация', 'Synchronization')
        : event['source'] == 'web'
            ? _label('Веб-панель', 'Web panel')
            : _label('Приложение', 'App');
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${event['action']}${event['target'] == null ? '' : ' · #${event['target']}'}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${event['actorName']} · $role · $source'),
            Text('${_date(event['createdAt'])} · $outcome',
                style: TextStyle(color: AppColors.textMuted)),
            if (details['date'] != null)
              Text(_label('Дата занятия: ', 'Lesson date: ') + details['date']),
            if (details['imported'] != null)
              Text(
                  '${_label('Импортировано: ', 'Imported: ')}${details['imported']}'),
            if (details['deleted'] != null)
              Text('${_label('Удалено: ', 'Deleted: ')}${details['deleted']}'),
          ],
        ));
  }
}
