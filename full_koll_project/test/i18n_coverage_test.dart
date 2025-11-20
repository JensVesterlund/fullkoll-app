import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('en-US coverage >= 99%', () async {
    final svRaw = await File('assets/i18n/sv-SE.json').readAsString();
    final enRaw = await File('assets/i18n/en-US.json').readAsString();
    final sanitizedSv = svRaw
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
        .replaceAll(RegExp(r'([^:])//.*$', multiLine: true), r'$1');
    final sanitizedEn = enRaw
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
        .replaceAll(RegExp(r'([^:])//.*$', multiLine: true), r'$1');
    final sv = Map<String, dynamic>.from(json.decode(sanitizedSv) as Map);
    final en = Map<String, dynamic>.from(json.decode(sanitizedEn) as Map);
    final total = sv.length;
    final present = sv.keys.where(en.containsKey).length;
    final coverage = present / total;
    expect(coverage >= 0.99, true, reason: 'Coverage ${coverage * 100}% < 99%');
  });
}
