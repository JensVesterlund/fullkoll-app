import 'package:intl/intl.dart';

class ReceiptBarcodeData {
  final String? store;
  final double? amount;
  final DateTime? purchaseDate;
  final String? raw;

  const ReceiptBarcodeData({this.store, this.amount, this.purchaseDate, this.raw});

  bool get hasAny => store != null || amount != null || purchaseDate != null;
}

class GiftCardBarcodeData {
  final String? brand;
  final String? cardNumber;
  final String? pin;
  final double? balance;
  final DateTime? expiresAt;
  final String? raw;

  const GiftCardBarcodeData({this.brand, this.cardNumber, this.pin, this.balance, this.expiresAt, this.raw});

  bool get hasAny => brand != null || cardNumber != null || pin != null || balance != null || expiresAt != null;
}

class BarcodeParser {
  static final _numberRegex = RegExp(r'(\d{4,})');
  static final _amountRegex = RegExp(r'(?:total|summa|amount|belopp|kr)[:\s]*(-?\d+[\.,]\d{1,2})', caseSensitive: false);
  static final _dateRegexIso = RegExp(r'20\d{2}[-/.]?\d{2}[-/.]?\d{2}');
  static final _dateRegexShort = RegExp(r'\d{2}[-/.]\d{2}[-/.]\d{2}');

  static ReceiptBarcodeData parseReceipt(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const ReceiptBarcodeData();

    final normalized = raw.replaceAll('\n', ' ').replaceAll('\r', ' ');

    String? store;
    final parts = normalized.split(RegExp(r'[;|]')).map((p) => p.trim()).toList();
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      store = _maybeStore(parts.first);
    }

    final amountMatch = _amountRegex.firstMatch(normalized);
    double? amount;
    if (amountMatch != null) {
      amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', '.'));
    }

    DateTime? purchaseDate;
    final isoMatch = _dateRegexIso.firstMatch(normalized);
    if (isoMatch != null) {
      purchaseDate = _parseDateToken(isoMatch.group(0)!);
    } else {
      final shortMatch = _dateRegexShort.firstMatch(normalized);
      if (shortMatch != null) {
        purchaseDate = _parseDateToken(shortMatch.group(0)!);
      }
    }

    return ReceiptBarcodeData(
      store: store,
      amount: amount,
      purchaseDate: purchaseDate,
      raw: raw,
    );
  }

  static GiftCardBarcodeData parseGiftCard(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const GiftCardBarcodeData();

    final normalized = raw.replaceAll('\n', ' ').replaceAll('\r', ' ');
    final tokens = normalized.split(RegExp(r'[;|,]')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

    String? brand;
    String? cardNumber;
    String? pin;
    double? balance;
    DateTime? expiresAt;

    for (final token in tokens) {
      final lower = token.toLowerCase();
      if (lower.contains('brand') || lower.contains('varum')) {
        brand = _valueAfterSeparator(token);
      } else if (lower.contains('pin')) {
        pin = _digits(token);
      } else if (lower.contains('saldo') || lower.contains('amount') || lower.contains('value')) {
        balance = _parseAmount(token);
      } else if (lower.contains('giltig') || lower.contains('expire') || lower.contains('valid')) {
        expiresAt = _parseDateToken(_valueAfterSeparator(token) ?? token);
      }

      final maybeNumber = _digits(token);
      if (maybeNumber != null && maybeNumber.length >= 8) {
        if (cardNumber == null || maybeNumber.length > (cardNumber?.length ?? 0)) {
          cardNumber = maybeNumber;
        }
      }
    }

    if (brand == null && tokens.isNotEmpty) {
      brand = tokens.firstWhere(
        (t) => !_numberRegex.hasMatch(t),
        orElse: () => tokens.first,
      );
    }

    return GiftCardBarcodeData(
      brand: brand,
      cardNumber: cardNumber,
      pin: pin,
      balance: balance,
      expiresAt: expiresAt,
      raw: raw,
    );
  }

  static String? _valueAfterSeparator(String token) {
    final parts = token.split(RegExp(r'[:=]'));
    if (parts.length < 2) return null;
    return parts.sublist(1).join(':').trim();
  }

  static String? _digits(String token) {
    final match = RegExp(r'(\d{4,})').firstMatch(token.replaceAll(' ', ''));
    return match?.group(1);
  }

  static double? _parseAmount(String token) {
    final match = _amountRegex.firstMatch(token);
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.'));
    }
    final fallback = RegExp(r'-?\d+[\.,]\d{1,2}').firstMatch(token);
    if (fallback != null) {
      return double.tryParse(fallback.group(0)!.replaceAll(',', '.'));
    }
    return null;
  }

  static DateTime? _parseDateToken(String? token) {
    if (token == null) return null;
    final cleaned = token.replaceAll(RegExp(r'[^0-9]'), '');
    try {
      if (cleaned.length == 8) {
        final year = int.parse(cleaned.substring(0, 4));
        final month = int.parse(cleaned.substring(4, 6));
        final day = int.parse(cleaned.substring(6, 8));
        return DateTime(year, month, day);
      } else if (cleaned.length == 6) {
        final year = int.parse('20${cleaned.substring(4, 6)}');
        final month = int.parse(cleaned.substring(2, 4));
        final day = int.parse(cleaned.substring(0, 2));
        return DateTime(year, month, day);
      }
    } catch (_) {
      return null;
    }
    for (final pattern in ['yyyy-MM-dd', 'yyyy/MM/dd', 'dd-MM-yy', 'dd/MM/yy']) {
      try {
        return DateFormat(pattern).parse(token, true).toLocal();
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static String? _maybeStore(String token) {
    if (token.isEmpty) return null;
    if (_numberRegex.hasMatch(token)) return null;
    if (token.length < 3) return null;
    return token;
  }
}
