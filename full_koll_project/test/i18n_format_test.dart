import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:full_koll/i18n/app_localizations.dart';
import 'package:full_koll/utils/formatting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget _wrap(Widget child, Locale locale) {
    return MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('sv', 'SE'), Locale('en', 'US')],
      localizationsDelegates: const [AppLocalizationsDelegate()],
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('Date and currency formats for sv-SE', (tester) async {
    final date = DateTime(2025, 1, 31, 14, 45);
    final w = Builder(
      builder: (context) => Column(
        children: [
          Text(formatDateShortLocalized(context, date), key: const Key('date_short')),
          Text(formatCurrencyLocalized(context, 12345.67), key: const Key('currency')),
        ],
      ),
    );
    await tester.pumpWidget(_wrap(w, const Locale('sv', 'SE')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('date_short')), findsOneWidget);
    expect(find.text('31 jan 2025'), findsOneWidget); // d MMM yyyy (sv)
    expect(find.byKey(const Key('currency')), findsOneWidget);
    // Decimal comma expected in sv-SE
    expect(find.textContaining(','), findsWidgets);
  });

  testWidgets('Date and currency formats for en-US', (tester) async {
    final date = DateTime(2025, 1, 31, 14, 45);
    final w = Builder(
      builder: (context) => Column(
        children: [
          Text(formatDateShortLocalized(context, date), key: const Key('date_short')),
          Text(formatCurrencyLocalized(context, 12345.67), key: const Key('currency')),
        ],
      ),
    );
    await tester.pumpWidget(_wrap(w, const Locale('en', 'US')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('date_short')), findsOneWidget);
    expect(find.text('Jan 31, 2025'), findsOneWidget); // MMM d, yyyy (en)
    expect(find.byKey(const Key('currency')), findsOneWidget);
    // Decimal dot expected in en-US
    expect(find.textContaining('.'), findsWidgets);
  });
}
