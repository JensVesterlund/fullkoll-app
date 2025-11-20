// Fallback connectivity provider for non-web platforms.
// Always reports online.
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  ConnectivityService() : _isOnline = true;

  bool _isOnline;

  bool get isOnline => _isOnline;

  // For API parity; no-op here.
  void disposeService() {}
}
