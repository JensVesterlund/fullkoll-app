// Simple localStorage wrapper for Flutter web.
import 'dart:html' as html;

String? webGetItem(String key) => html.window.localStorage[key];
void webSetItem(String key, String value) => html.window.localStorage[key] = value;
void webRemoveItem(String key) => html.window.localStorage.remove(key);
