import 'package:flutter_test/flutter_test.dart';

import 'package:full_koll/utils/formatting.dart';

void main() {
  test('formatCurrency formats SEK with uppercase suffix', () {
    final formatted = formatCurrency(1234.5);
    expect(formatted.endsWith('SEK'), isTrue);
    final normalised = formatted.replaceAll(RegExp(r'\s+'), ' ');
    expect(normalised.contains('1'), isTrue);
  });

  test('maskSensitive keeps trailing digits', () {
    expect(maskSensitive('12345678'), equals('****5678'));
    expect(maskSensitive('1234', visibleDigits: 2), equals('**34'));
  });

  test('formatDateIso returns yyyy-MM-dd', () {
    final value = formatDateIso(DateTime(2025, 1, 31));
    expect(value, equals('2025-01-31'));
  });
}