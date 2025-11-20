// Fallback no-op key-value storage for non-web platforms.

String? webGetItem(String key) => null;
void webSetItem(String key, String value) {}
void webRemoveItem(String key) {}
