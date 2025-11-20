import 'dart:collection';
import 'package:flutter/material.dart';

/// Lightweight performance tracker for dev/preview to approximate
/// time-to-interactive and per-route first-render timings.
class PerfTracker {
  PerfTracker._();

  static DateTime? _appStart;
  static DateTime? _firstFrame;

  static final Map<String, Duration> _routeFirstPush = <String, Duration>{};

  static void markAppStart() {
    _appStart = DateTime.now();
  }

  static void markFirstFrame() {
    _firstFrame ??= DateTime.now();
  }

  static Duration? get tti {
    if (_appStart == null || _firstFrame == null) return null;
    return _firstFrame!.difference(_appStart!);
  }

  static UnmodifiableMapView<String, Duration> get routeFirstRender => UnmodifiableMapView(_routeFirstPush);

  static final NavigatorObserver routeObserver = _PerfNavigatorObserver();
}

class _PerfNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name ?? route.toString();
    if (!PerfTracker._routeFirstPush.containsKey(name) && PerfTracker._appStart != null) {
      PerfTracker._routeFirstPush[name] = DateTime.now().difference(PerfTracker._appStart!);
    }
    super.didPush(route, previousRoute);
  }
}
