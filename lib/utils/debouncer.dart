import 'dart:async';

/// Simple debouncer to throttle expensive callbacks (e.g. live search filtering).
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;
  Timer? _timer;

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}