import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/purchase_quantity.dart';

// Dart's native and browser targets share this exact integer range. Values
// outside it must not silently lose cents on a browser build.
final BigInt _maximumExactMinorUnits = BigInt.parse('9007199254740991');

/// A valid amount calculation cannot be represented exactly on every target.
/// Kept distinct from malformed input so an explicit receipt amount can still
/// be retained when only its optional arithmetic comparison is unavailable.
final class ReceiptAmountRangeException extends ArgumentError {
  ReceiptAmountRangeException(super.message);
}

/// Multiplies the purchased quantity (pack count or purchased measurement,
/// never converted stock quantity) by the price per purchased unit.
///
/// Each line is rounded independently to the nearest minor unit using HALF_UP,
/// matching the backend's two-decimal purchasing calculation. All intermediate
/// arithmetic uses BigInt; binary floating point is not used for money.
Money calculatePurchasedLineTotal({
  required String quantityText,
  required Money unitPrice,
}) {
  _validateMoney(unitPrice);
  final quantity = PurchaseQuantity.parse(
    quantityText.trim(),
    positive: true,
  ).toString();
  final parts = quantity.split('.');
  final fraction = parts.length == 1 ? '' : parts.last;
  final denominator = BigInt.from(10).pow(fraction.length);
  final numerator =
      BigInt.parse('${parts.first}$fraction') *
      BigInt.from(unitPrice.minorUnits);
  final rounded =
      (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
  return Money(
    minorUnits: _exactMinorUnits(rounded),
    currency: unitPrice.currency,
  );
}

/// Parses an optional, non-negative two-decimal receipt amount exactly.
/// An empty value is missing; an explicitly entered zero remains a price.
Money? parseReceiptMoney(String text, {required String currency}) {
  _validateCurrency(currency);
  final value = text.trim();
  if (value.isEmpty) return null;
  if (!RegExp(r'^\d{1,12}(?:\.\d{1,2})?$').hasMatch(value)) {
    throw ArgumentError(
      'Use a non-negative amount with at most two decimal places.',
    );
  }
  final parts = value.split('.');
  final minor =
      BigInt.parse(parts.first) * BigInt.from(100) +
      (parts.length == 1
          ? BigInt.zero
          : BigInt.parse(parts.last.padRight(2, '0')));
  return Money(minorUnits: _exactMinorUnits(minor), currency: currency);
}

/// Formats cents without dividing through a double, including large amounts.
String formatReceiptMoney(Money money) {
  final minor = BigInt.from(money.minorUnits);
  final absolute = minor.abs();
  return '${money.currency} ${minor.isNegative ? '-' : ''}'
      '${absolute ~/ BigInt.from(100)}.'
      '${(absolute % BigInt.from(100)).toString().padLeft(2, '0')}';
}

/// The canonical purchased quantity retained by a receipt line. Legacy lines
/// may only have a double projection; its shortest decimal representation is
/// expanded without floating-point multiplication before exact calculation.
String purchasedLineQuantityText(PurchaseReceiptLineCapture line) =>
    line.quantityText ?? _expandDecimal(line.quantity.toString());

final class ReceiptLineAmounts {
  const ReceiptLineAmounts._({
    required this.total,
    required this.calculatedTotal,
    required this.hasDiscrepancy,
    required this.currencyMismatch,
    this.error,
  });

  factory ReceiptLineAmounts.resolve(
    PurchaseReceiptLineCapture line, {
    required String currency,
  }) {
    final mismatch =
        (line.unitPrice != null && line.unitPrice!.currency != currency) ||
        (line.lineTotal != null && line.lineTotal!.currency != currency);
    if (mismatch) {
      return const ReceiptLineAmounts._(
        total: null,
        calculatedTotal: null,
        hasDiscrepancy: false,
        currencyMismatch: true,
        error: 'The line currency differs from the receipt currency.',
      );
    }
    try {
      _validateCurrency(currency);
      PurchaseQuantity.parse(purchasedLineQuantityText(line), positive: true);
      if (line.lineTotal != null) _validateMoney(line.lineTotal!);
      if (line.unitPrice != null) _validateMoney(line.unitPrice!);
      Money? calculated;
      String? calculationError;
      if (line.unitPrice != null) {
        try {
          calculated = calculatePurchasedLineTotal(
            quantityText: purchasedLineQuantityText(line),
            unitPrice: line.unitPrice!,
          );
        } on ReceiptAmountRangeException {
          calculationError = line.lineTotal == null
              ? 'The calculated amount exceeds the supported range. Enter a valid receipt line total or review the quantity and unit price.'
              : 'The calculated amount exceeds the supported range. The entered line total is retained; arithmetic comparison is unavailable.';
        }
      }
      return ReceiptLineAmounts._(
        total: line.lineTotal ?? calculated,
        calculatedTotal: calculated,
        hasDiscrepancy:
            line.lineTotal != null &&
            calculated != null &&
            line.lineTotal != calculated,
        currencyMismatch: false,
        error: calculationError,
      );
    } on ArgumentError {
      return const ReceiptLineAmounts._(
        total: null,
        calculatedTotal: null,
        hasDiscrepancy: false,
        currencyMismatch: false,
        error: 'Check the purchased quantity and non-negative line amounts.',
      );
    }
  }

  /// Explicit receipt total takes precedence, including discounted lines.
  final Money? total;
  final Money? calculatedTotal;
  final bool hasDiscrepancy;
  final bool currencyMismatch;
  final String? error;
}

/// Reconciliation over the currently saved, visible receipt lines. Approval
/// and stock application do not determine whether an entered price is counted.
/// No stock or persistence mutation is performed by this read model.
final class ReceiptAmounts {
  const ReceiptAmounts._({
    required this.knownTotal,
    required this.unpricedLineCount,
    required this.currencyMismatchCount,
    required this.expectedTotal,
    this.expectedTotalError,
  });

  factory ReceiptAmounts.fromReceipt(PurchaseReceiptCapture receipt) {
    var total = BigInt.zero;
    var unpriced = 0;
    var mismatches = 0;
    for (final line in receipt.lines) {
      final amounts = ReceiptLineAmounts.resolve(
        line,
        currency: receipt.currency,
      );
      if (amounts.currencyMismatch) mismatches++;
      if (amounts.total == null) {
        unpriced++;
        continue;
      }
      final next = total + BigInt.from(amounts.total!.minorUnits);
      if (next > _maximumExactMinorUnits) {
        // Retain the safe known subtotal and disclose the excluded line rather
        // than rounding/overflowing an apparently complete receipt sum.
        unpriced++;
        continue;
      }
      total = next;
    }
    Money? expected;
    String? expectedError;
    if (receipt.total != null) {
      if (receipt.total!.currency != receipt.currency) {
        expectedError = 'Receipt total uses a different currency.';
      } else {
        try {
          _validateMoney(receipt.total!);
          expected = receipt.total;
        } on ArgumentError {
          expectedError = 'Check the non-negative receipt total.';
        }
      }
    }
    return ReceiptAmounts._(
      knownTotal: Money(
        minorUnits: _exactMinorUnits(total),
        currency: receipt.currency,
      ),
      unpricedLineCount: unpriced,
      currencyMismatchCount: mismatches,
      expectedTotal: expected,
      expectedTotalError: expectedError,
    );
  }

  final Money knownTotal;
  final int unpricedLineCount;
  final int currencyMismatchCount;
  final Money? expectedTotal;
  final String? expectedTotalError;

  bool get isComplete => unpricedLineCount == 0;

  /// Positive means remaining, negative means over. Unknown amounts suppress
  /// comparison, even if the known subtotal happens to equal the receipt total.
  Money? get difference =>
      isComplete && expectedTotal != null ? expectedTotal! - knownTotal : null;
}

void _validateCurrency(String currency) {
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
    throw ArgumentError('Use a three-letter uppercase currency code.');
  }
}

void _validateMoney(Money value) {
  _validateCurrency(value.currency);
  if (value.minorUnits < 0) {
    throw ArgumentError('Receipt amounts must not be negative.');
  }
  _exactMinorUnits(BigInt.from(value.minorUnits));
}

int _exactMinorUnits(BigInt value) {
  if (value < BigInt.zero || value > _maximumExactMinorUnits) {
    throw ReceiptAmountRangeException(
      'The receipt amount exceeds the supported range.',
    );
  }
  return value.toInt();
}

String _expandDecimal(String text) {
  final match = RegExp(r'^(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$').firstMatch(text);
  if (match == null) return text;
  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  final digits = '$whole$fraction';
  final point = whole.length + int.parse(match.group(3)!);
  if (point <= 0) return '0.${'0' * -point}$digits';
  if (point >= digits.length) return digits.padRight(point, '0');
  return '${digits.substring(0, point)}.${digits.substring(point)}';
}
