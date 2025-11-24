import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import '../i18n/app_localizations.dart';

/// Formats a currency value in SEK with thin spacing for readability.
String formatCurrency(num amount, {String currency = 'SEK', String locale = 'sv-SE'}) {
  final formatter = NumberFormat.currency(locale: locale, name: currency, decimalDigits: 2, symbol: '');
  final formatted = formatter.format(amount).trim();
  return '$formatted ${currency.toUpperCase()}'.trim();
}

/// Formats a compact date (e.g. 2025-01-31) using ISO ordering for export lists.
String formatDateIso(DateTime date, {String locale = 'sv-SE'}) => DateFormat('yyyy-MM-dd', locale).format(date.toLocal());

/// Masks a sensitive identifier while keeping the last [visibleDigits] characters readable.
String maskSensitive(String input, {int visibleDigits = 4, String maskChar = '*'}) {
  if (input.isEmpty || visibleDigits <= 0 || input.length <= visibleDigits) {
    return input;
  }
  final maskedLength = input.length - visibleDigits;
  return maskChar * maskedLength + input.substring(maskedLength);
}

/// Return current `ll-CC` tag from context.
String localeTagOf(BuildContext context) => context.localeTag;

/// Formats a currency value using current locale (decimal separators) and app currency.
String formatCurrencyLocalized(BuildContext context, num amount, {String currency = 'SEK', int? decimalDigits}) {
  final tag = localeTagOf(context);
  final formatter = NumberFormat.currency(
    locale: tag,
    name: currency,
    decimalDigits: decimalDigits ?? 0,
    symbol: '',
  );
  final formatted = formatter.format(amount).trim();
  return '$formatted ${currency.toUpperCase()}'.trim();
}

/// Formats a short human date according to locale guidelines.
/// sv-SE → d MMM yyyy
/// en-US → MMM d, yyyy
String formatDateShortLocalized(BuildContext context, DateTime date) {
  final tag = localeTagOf(context);
  final isSv = tag.toLowerCase().startsWith('sv');
  final pattern = isSv ? 'd MMM yyyy' : 'MMM d, yyyy';
  return DateFormat(pattern, tag).format(date);
}

/// Formats date+time in a compact way (keeps 24h time).
String formatDateTimeShortLocalized(BuildContext context, DateTime dateTime) {
  final tag = localeTagOf(context);
  final isSv = tag.toLowerCase().startsWith('sv');
  final pattern = isSv ? 'd MMM yyyy HH:mm' : 'MMM d, yyyy HH:mm';
  return DateFormat(pattern, tag).format(dateTime);
}

/// Formats a month header like "January 2025" according to locale.
String formatMonthYearLocalized(BuildContext context, DateTime month) {
  final tag = localeTagOf(context);
  return DateFormat('MMMM yyyy', tag).format(month);
}