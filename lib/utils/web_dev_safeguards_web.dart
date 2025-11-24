// Web-only implementation: aggressively clears Service Workers and Cache Storage
// in development to avoid stale previews and zone mismatch side-effects.
// This runs before runApp and reloads the page once per tab session.
import 'dart:async';
import 'dart:html' as html;

Future<void> ensureCleanWebStartIfNeeded({required bool devMode}) async {
  if (!devMode) return;

  final ss = html.window.sessionStorage;
  // Bump this key to force a one-time hard reload and cache clear in dev when
  // code has changed in a way that may be cached by SW/CacheStorage.
  const flagKey = 'fk_cache_cleared_v3';
  final alreadyCleared = ss[flagKey] == '1';
  if (alreadyCleared) {
    return;
  }

  // Try to unregister all service workers.
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final regs = await sw.getRegistrations();
      for (final r in regs) {
        try {
          await r.unregister();
        } catch (_) {}
      }
    }
  } catch (_) {}

  // Try to clear Cache Storage to prevent stale assets.
  try {
    final caches = html.window.caches;
    if (caches != null) {
      final keys = await caches.keys();
      for (final k in keys) {
        try {
          await caches.delete(k);
        } catch (_) {}
      }
    }
  } catch (_) {}

  // Mark as done for this tab session and reload once.
  ss[flagKey] = '1';
  // Ensure the reload is executed after current microtask.
  scheduleMicrotask(() {
    html.window.location.reload();
  });
  // Await a tiny delay so callers can await and not race the reload.
  await Future<void>.delayed(const Duration(milliseconds: 1));
}
