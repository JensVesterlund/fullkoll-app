// No-op stub for non-web platforms or when not needed.
import 'package:flutter/foundation.dart';

Future<void> ensureCleanWebStartIfNeeded({required bool devMode}) async {
  // Only relevant on web; on other platforms do nothing.
  if (!kIsWeb) return;
  // If not in dev mode, do nothing.
  if (!devMode) return;
}
