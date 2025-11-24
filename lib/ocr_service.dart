import 'dart:async';
import 'dart:math';

/// OCR-modulen bestar av tre steg:
/// 1. UI-lagret hamtar bild via kamera eller filvaljare.
/// 2. [OcrService] tar emot bytes + filnamn och gor heuristisk parsing
///    (kan ersattas med riktig OCR-motor senare) och returnerar [OcrSuggestion].
/// 3. UI mappar falten till formulären, markerar osakra traffar och later
///    anvandaren justera innan sparande.
///
/// Vid byte till riktig OCR ersatter man endast logiken i
/// [_mockAnalyseReceipt] och [_mockAnalyseGiftCard]; UI:t paverkas inte.

const _confidenceThreshold = 0.75;

class OcrSuggestion<T> {
  final T? value;
  final double confidence;
  final String? raw;

  const OcrSuggestion({this.value, this.confidence = 0, this.raw});

  bool get hasValue => value != null;
  bool get isConfident => confidence >= _confidenceThreshold;
}

class ReceiptOcrResult {
  final OcrSuggestion<String> store;
  final OcrSuggestion<DateTime> purchaseDate;
  final OcrSuggestion<double> amount;
  final OcrSuggestion<double> vat;
  final String currency;

  const ReceiptOcrResult({
    this.store = const OcrSuggestion(),
    this.purchaseDate = const OcrSuggestion(),
    this.amount = const OcrSuggestion(),
    this.vat = const OcrSuggestion(),
    this.currency = 'SEK',
  });

  bool get hasAnyData =>
      store.hasValue || purchaseDate.hasValue || amount.hasValue || vat.hasValue;
}

class GiftCardOcrResult {
  final OcrSuggestion<String> brand;
  final OcrSuggestion<String> cardNumber;
  final OcrSuggestion<double> amount;
  final OcrSuggestion<DateTime> expiresAt;

  const GiftCardOcrResult({
    this.brand = const OcrSuggestion(),
    this.cardNumber = const OcrSuggestion(),
    this.amount = const OcrSuggestion(),
    this.expiresAt = const OcrSuggestion(),
  });

  bool get hasAnyData =>
      brand.hasValue || cardNumber.hasValue || amount.hasValue || expiresAt.hasValue;
}

class OcrService {
  static Future<ReceiptOcrResult> analyzeReceipt({
    required List<int> bytes,
    required String fileName,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    return _mockAnalyseReceipt(fileName);
  }

  static Future<GiftCardOcrResult> analyzeGiftCard({
    required List<int> bytes,
    required String fileName,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    return _mockAnalyseGiftCard(fileName);
  }

  static ReceiptOcrResult _mockAnalyseReceipt(String fileName) {
    final lower = fileName.toLowerCase();

    if (lower.contains('ica')) {
      return ReceiptOcrResult(
        store: const OcrSuggestion(value: 'ICA Maxi', confidence: 0.92),
        purchaseDate: OcrSuggestion(
          value: DateTime.now().subtract(const Duration(days: 1)),
          confidence: 0.88,
        ),
        amount: const OcrSuggestion(value: 437.0, confidence: 0.9),
        vat: const OcrSuggestion(value: 43.7, confidence: 0.78),
      );
    }

    if (lower.contains('hm') || lower.contains('h&m')) {
      return ReceiptOcrResult(
        store: const OcrSuggestion(value: 'H&M', confidence: 0.85),
        purchaseDate: OcrSuggestion(
          value: DateTime.now().subtract(const Duration(days: 5)),
          confidence: 0.64,
        ),
        amount: const OcrSuggestion(value: 599.0, confidence: 0.73),
        vat: const OcrSuggestion(value: 119.8, confidence: 0.55),
      );
    }

    final digits = RegExp(r'(\d+[,.]\d{2})').firstMatch(lower);
    final amount = digits != null
        ? double.tryParse(digits.group(0)!.replaceAll(',', '.'))
        : null;

    return ReceiptOcrResult(
      store: const OcrSuggestion(value: 'Okand butik', confidence: 0.3),
      amount: OcrSuggestion(value: amount, confidence: 0.45, raw: digits?.group(0)),
      vat: amount != null
          ? OcrSuggestion(value: (amount / 5).roundToDouble(), confidence: 0.3)
          : const OcrSuggestion(),
    );
  }

  static GiftCardOcrResult _mockAnalyseGiftCard(String fileName) {
    final lower = fileName.toLowerCase();

    if (lower.contains('spotify')) {
      return GiftCardOcrResult(
        brand: const OcrSuggestion(value: 'Spotify', confidence: 0.94),
        cardNumber: const OcrSuggestion(value: '1234 5678 9012 3456', confidence: 0.88),
        amount: const OcrSuggestion(value: 500.0, confidence: 0.9),
        expiresAt: OcrSuggestion(
          value: DateTime.now().add(const Duration(days: 185)),
          confidence: 0.8,
        ),
      );
    }

    if (lower.contains('ahlens')) {
      return GiftCardOcrResult(
        brand: const OcrSuggestion(value: 'Ahlens', confidence: 0.87),
        cardNumber: const OcrSuggestion(value: '9876 5432 1098 7654', confidence: 0.7),
        amount: const OcrSuggestion(value: 1000.0, confidence: 0.75),
        expiresAt: OcrSuggestion(
          value: DateTime.now().add(const Duration(days: 335)),
          confidence: 0.6,
        ),
      );
    }

    final random = Random(fileName.hashCode);
    final guessedAmount = (random.nextInt(20) + 1) * 50;
    final guessedDigits = List.generate(4, (_) => (random.nextInt(9000) + 1000).toString())
        .join(' ');

    return GiftCardOcrResult(
      brand: const OcrSuggestion(value: 'Okant presentkort', confidence: 0.25),
      cardNumber: OcrSuggestion(value: guessedDigits, confidence: 0.4),
      amount: OcrSuggestion(value: guessedAmount.toDouble(), confidence: 0.35),
      expiresAt: OcrSuggestion(
        value: DateTime.now().add(Duration(days: 90 + random.nextInt(270))),
        confidence: 0.28,
      ),
    );
  }
}