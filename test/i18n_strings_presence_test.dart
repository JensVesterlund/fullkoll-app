import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Essential en-US strings present (nav, details, toasts)', () async {
    final enRaw = await File('assets/i18n/en-US.json').readAsString();
    final sanitizedEn = enRaw
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
        .replaceAll(RegExp(r'([^:])//.*$', multiLine: true), r'$1');
    final en = Map<String, dynamic>.from(json.decode(sanitizedEn) as Map);

    // Nav
    final navKeys = [
      'nav.home',
      'nav.receipts',
      'nav.giftcards',
      'nav.budget',
      'nav.split',
      'nav.autogiro',
      'nav.settings',
    ];

    for (final k in navKeys) {
      expect(en.containsKey(k), true, reason: 'Missing nav key $k');
      expect((en[k] as String).startsWith('[MISSING:'), false);
    }

    // 5 detail page keys
    final detailKeys = [
      'giftcards.title',
      'giftcards.detail.balance',
      'autogiro.title',
      'autogiro.detail.nextCharge',
      'sharing.owner.fullAccess',
    ];
    for (final k in detailKeys) {
      expect(en.containsKey(k), true, reason: 'Missing detail key $k');
      expect((en[k] as String).startsWith('[MISSING:'), false);
    }

    // 3 toasts/snackbars/feedback
    final toastKeys = [
      'giftcards.feedback.saved',
      'giftcards.feedback.updated',
      'split.reminder.enabled',
    ];
    for (final k in toastKeys) {
      expect(en.containsKey(k), true, reason: 'Missing toast key $k');
      expect((en[k] as String).startsWith('[MISSING:'), false);
    }
  });
}
