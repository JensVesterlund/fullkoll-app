import 'dart:convert';

// Web KV store for web; stubbed on other platforms.
import 'web_kv_store_stub.dart'
    if (dart.library.html) 'web_kv_store_web.dart';

class OfflineCache {
  OfflineCache._();

  static T? readJson<T>(String key, T Function(Map<String, dynamic> map) fromMap) {
    try {
      final raw = webGetItem(key);
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return fromMap(map);
    } catch (_) {
      return null;
    }
  }

  static List<T> readJsonList<T>(String key, T Function(Map<String, dynamic> map) fromMap) {
    try {
      final raw = webGetItem(key);
      if (raw == null || raw.isEmpty) return <T>[];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => fromMap(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return <T>[];
    }
  }

  static void writeJson(String key, Map<String, dynamic> data) {
    try {
      webSetItem(key, jsonEncode(data));
    } catch (_) {}
  }

  static void writeJsonList(String key, Iterable<Map<String, dynamic>> data) {
    try {
      webSetItem(key, jsonEncode(data.toList()));
    } catch (_) {}
  }
}
