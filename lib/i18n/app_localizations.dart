import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Custom localization class that loads string resources from JSON assets.
class AppLocalizations {
  AppLocalizations(this.locale, this._values);

  final Locale locale;
  final Map<String, String> _values;

  // Dev-only: when true, clearly mark missing keys in UI.
  static bool debugHighlightMissing = false;

  static const List<Locale> supportedLocales = [
    Locale('sv', 'SE'),
    Locale('en', 'US'),
  ];

  static final Map<String, Map<String, String>> _cache = {};

  static Future<AppLocalizations> load(Locale locale) async {
    final key = _localeKey(locale);
    if (_cache.containsKey(key)) {
      return AppLocalizations(locale, _cache[key]!);
    }

    final assetPath = 'assets/i18n/$key.json';
    Map<String, String> values;
    try {
      final raw = await rootBundle.loadString(assetPath);
      // Allow // comments in JSON files by stripping them before decoding.
      final sanitized = raw
          // Remove full-line // comments
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
          // Remove inline // comments
          .replaceAll(RegExp(r'([^:])//.*$', multiLine: true), r'$1')
          // Remove trailing commas before } or ]
          .replaceAll(RegExp(r',(?=\s*[}\]])'), '');
      values = Map<String, String>.from(json.decode(sanitized) as Map);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[i18n] Failed to load ' + assetPath + ': ' + e.toString());
      }
      // No implicit fallback to Swedish. Use empty map so missing keys are visible.
      values = const {};
    }

    _cache[key] = values;
    return AppLocalizations(locale, values);
  }

  static AppLocalizations? maybeOf(BuildContext context) => Localizations.of<AppLocalizations>(context, AppLocalizations);

  static AppLocalizations of(BuildContext context) {
    final l10n = maybeOf(context);
    if (l10n != null) return l10n;
    // Defensive fallback: during the very first build of MaterialApp (e.g.,
    // onGenerateTitle or a Builder just under MaterialApp), Localizations
    // may not yet have completed initialization. Instead of asserting and
    // crashing the whole app in debug, return an empty localization instance
    // so the UI can render and show [MISSING:key] markers for visibility.
    if (kDebugMode) {
      debugPrint('[i18n] AppLocalizations.of() used before initialization (v2). Returning empty l10n.');
    }
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('sv', 'SE');
    final key = _localeKey(locale);
    final values = _cache[key] ?? const <String, String>{};
    return AppLocalizations(locale, values);
  }

  String translate(String key, {Map<String, dynamic>? params}) {
    final raw = _values[key];
    if (raw == null) {
      // In dev, make missing keys explicit to surface gaps quickly.
      if (kDebugMode) {
        final marker = '[MISSING:$key]';
        if (debugHighlightMissing) return '🔴 $marker';
        return marker;
      }
      // In release, return the key to avoid crashing the UI.
      return key;
    }
    var result = raw;
    if (params != null && params.isNotEmpty) {
      params.forEach((placeholder, value) {
        result = result.replaceAll('{$placeholder}', '$value');
      });
    }
    return result;
  }

  static String _localeKey(Locale locale) {
    final countryCode = locale.countryCode?.isNotEmpty == true ? locale.countryCode! : 'SE';
    final languageCode = locale.languageCode.isNotEmpty ? locale.languageCode : 'sv';
    return '${languageCode.toLowerCase()}-${countryCode.toUpperCase()}';
  }

  /// Expose the normalized `ll-CC` tag for a given locale (e.g., sv-SE, en-US).
  static String tagFor(Locale locale) => _localeKey(locale);
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    for (final supported in AppLocalizations.supportedLocales) {
      if (supported.languageCode == locale.languageCode) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations.load(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}

class LocaleController extends ChangeNotifier {
  LocaleController({Locale? initialLocale}) : _locale = initialLocale ?? const Locale('sv', 'SE');

  Locale _locale;

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (_locale == locale) return;
    _locale = locale;
    // Keep Intl default locale in sync for formatting APIs that rely on it.
    Intl.defaultLocale = AppLocalizations.tagFor(locale);
    notifyListeners();
  }
}

extension LocalizationContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  /// Convenience accessor for current `ll-CC` locale tag.
  String get localeTag {
    final loc = Localizations.maybeLocaleOf(this) ?? const Locale('sv', 'SE');
    return AppLocalizations.tagFor(loc);
  }
}