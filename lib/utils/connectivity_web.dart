// Connectivity provider for Flutter web using navigator.onLine and online/offline events.
import 'dart:html' as html;
import 'dart:async';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  ConnectivityService() : _isOnline = (html.window.navigator.onLine ?? true) {
    _subOnline = html.window.onOnline.listen((_) {
      _isOnline = true;
      notifyListeners();
    });
    _subOffline = html.window.onOffline.listen((_) {
      _isOnline = false;
      notifyListeners();
    });
  }

  late final html.EventListener? _noop = null;
  bool _isOnline;
  StreamSubscription<html.Event>? _subOnline;
  StreamSubscription<html.Event>? _subOffline;

  bool get isOnline => _isOnline;

  void disposeService() {
    _subOnline?.cancel();
    _subOffline?.cancel();
  }
}
