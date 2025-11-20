import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Lightweight error/event logging inspired by Sentry so we can hook in full telemetry later.
class AnalyticsService {
  AnalyticsService._();

  /// Reports an unexpected error together with stacktrace and optional context metadata.
  static Future<void> logError(
    Object error,
    StackTrace stackTrace, {
    String? hint,
    Map<String, Object?>? context,
  }) async {
    final payload = LoggedError(
      error: error,
      stackTrace: stackTrace,
      hint: hint,
      context: context == null ? const {} : Map.unmodifiable(context),
      timestamp: DateTime.now(),
    );

    if (kDebugMode) {
      debugPrint('[Analytics] ERROR ${payload.summary}');
    }

    developer.log(
      payload.summary,
      name: 'full_koll.analytics',
      error: error,
      stackTrace: stackTrace,
      time: payload.timestamp,
      level: 1000,
    );

    ErrorReporter.instance.report(payload);
  }

  /// Stores a simple breadcrumb for future diagnostics.
  static Future<void> logBreadcrumb(String message, {Map<String, Object?>? context}) async {
    if (kDebugMode) {
      debugPrint('[Analytics] BREADCRUMB $message ${context ?? {}}');
    }
    BreadcrumbBuffer.instance.add(Breadcrumb(
      message: message,
      context: context == null ? const {} : Map.unmodifiable(context),
      timestamp: DateTime.now(),
    ));
  }
}

/// Immutable error container to expose useful data to the UI overlay.
class LoggedError {
  final Object error;
  final StackTrace stackTrace;
  final DateTime timestamp;
  final String? hint;
  final Map<String, Object?> context;

  const LoggedError({
    required this.error,
    required this.stackTrace,
    required this.timestamp,
    this.hint,
    this.context = const {},
  });

  String get summary => hint != null ? '$hint :: ${error.runtimeType}' : 'Unhandled ${error.runtimeType}';

  String get displayHint {
    if (hint != null && hint!.isNotEmpty) return hint!;
    return 'Ett oväntat fel inträffade';
  }
}

class ErrorReporter extends ChangeNotifier {
  ErrorReporter._();

  static final ErrorReporter instance = ErrorReporter._();

  final Queue<LoggedError> _queue = Queue();
  final List<LoggedError> _history = <LoggedError>[];
  static const int _historyCap = 50;

  LoggedError? get current => _queue.isEmpty ? null : _queue.first;

  void report(LoggedError error) {
    _queue.add(error);
    _history.add(error);
    if (_history.length > _historyCap) {
      _history.removeRange(0, _history.length - _historyCap);
    }
    notifyListeners();
  }

  void dismissCurrent() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst();
      notifyListeners();
    }
  }

  void clear() {
    if (_queue.isEmpty) return;
    _queue.clear();
    notifyListeners();
  }

  /// Returns a snapshot list of the last [limit] errors, newest last.
  List<LoggedError> last({int limit = 50}) {
    if (_history.isEmpty) return const <LoggedError>[];
    final start = (_history.length - limit).clamp(0, _history.length);
    return List<LoggedError>.from(_history.sublist(start));
  }
}

class Breadcrumb {
  final String message;
  final DateTime timestamp;
  final Map<String, Object?> context;

  const Breadcrumb({
    required this.message,
    required this.timestamp,
    this.context = const {},
  });
}

class BreadcrumbBuffer {
  BreadcrumbBuffer._();

  static final BreadcrumbBuffer instance = BreadcrumbBuffer._();

  final List<Breadcrumb> _items = <Breadcrumb>[];
  static const int _maxSize = 50;

  List<Breadcrumb> get items => List.unmodifiable(_items);

  void add(Breadcrumb breadcrumb) {
    _items.add(breadcrumb);
    if (_items.length > _maxSize) {
      _items.removeRange(0, _items.length - _maxSize);
    }
  }

  void clear() => _items.clear();
}