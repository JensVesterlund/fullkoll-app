import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import '../services/analytics.dart';

/// Shows a human-friendly message for network/async failures while logging the full error payload.
void showFriendlyError(
  BuildContext context,
  Object error,
  StackTrace stackTrace, {
  String? userMessage,
  String hint = 'network',
  Map<String, Object?>? contextData,
}) {
  AnalyticsService.logError(error, stackTrace, hint: hint, context: contextData);

  final l10n = context.l10n;
  final message = userMessage ?? l10n.translate('errors.genericNetwork');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}