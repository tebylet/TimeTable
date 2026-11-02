import 'dart:async';

/// Foreground heartbeat + immediate lifecycle transitions. Only the latest
/// state is queued; offline signals are discarded, not replayed on reconnect.
class ActivityReporter {
  final Future<void> Function(bool active) send;
  final Duration interval;
  Timer? _timer;
  bool? _pending;
  bool _foreground = false;
  bool _sending = false;
  bool _disposed = false;

  ActivityReporter(
      {required this.send, this.interval = const Duration(seconds: 30)});

  void setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    _timer?.cancel();
    _enqueue(value);
    if (value) _timer = Timer.periodic(interval, (_) => _enqueue(true));
  }

  void _enqueue(bool active) {
    if (_disposed) return;
    _pending = active;
    if (!_sending) unawaited(_drain());
  }

  Future<void> _drain() async {
    _sending = true;
    while (_pending != null && !_disposed) {
      final active = _pending!;
      _pending = null;
      try {
        await send(active);
      } catch (_) {
        // Telemetry must never affect opening or reading the timetable.
      }
    }
    _sending = false;
  }

  void dispose() {
    _disposed = true;
    _pending = null;
    _timer?.cancel();
  }
}
