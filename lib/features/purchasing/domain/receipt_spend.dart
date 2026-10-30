import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/receipt_amounts.dart';

/// Matches the backend PurchaseAmounts policy. A declared amount wins even
/// when product pricing is incomplete; a subtotal never certifies unknown spend.
enum ReceiptSpendSource { declared, derived, partial, unknown }

final class ReceiptSpendAmount {
  const ReceiptSpendAmount._({
    required this.amount,
    required this.knownSubtotal,
    required this.source,
    required this.products,
    required this.lineCount,
    required this.pricedLineCount,
  });

  factory ReceiptSpendAmount.fromReceipt(PurchaseReceiptCapture receipt) {
    final products = ReceiptAmounts.fromReceipt(receipt);
    final priced = receipt.lines.length - products.unpricedLineCount;
    final declared = products.expectedTotal;
    final completeProducts = receipt.lines.isNotEmpty && products.isComplete;
    final known = declared ?? (priced > 0 ? products.knownTotal : null);
    // An invalid entered header is unavailable evidence, never permission to
    // replace that physical amount with the product subtotal.
    final complete =
        products.expectedTotalError == null &&
        (declared != null || completeProducts);
    return ReceiptSpendAmount._(
      amount: complete ? known : null,
      knownSubtotal: known,
      source: declared != null
          ? ReceiptSpendSource.declared
          : complete
          ? ReceiptSpendSource.derived
          : priced > 0
          ? ReceiptSpendSource.partial
          : ReceiptSpendSource.unknown,
      products: products,
      lineCount: receipt.lines.length,
      pricedLineCount: priced,
    );
  }

  final Money? amount;
  final Money? knownSubtotal;
  final ReceiptSpendSource source;
  final ReceiptAmounts products;
  final int lineCount;
  final int pricedLineCount;
  bool get pricingComplete => amount != null;
}

/// One currency only. Known subtotals of incomplete receipts remain visibly
/// partial and never appear in [amount] as complete household spending.
final class ReceiptSpendCurrencySummary {
  ReceiptSpendCurrencySummary._(
    this.currency,
    List<ReceiptSpendAmount> receipts,
  ) : receiptCount = receipts.length,
      completeReceiptCount = receipts
          .where((row) => row.pricingComplete)
          .length,
      partialReceiptCount = receipts
          .where((row) => row.source == ReceiptSpendSource.partial)
          .length,
      unknownReceiptCount = receipts
          .where((row) => row.source == ReceiptSpendSource.unknown)
          .length,
      declaredReceiptCount = receipts
          .where((row) => row.source == ReceiptSpendSource.declared)
          .length,
      derivedReceiptCount = receipts
          .where((row) => row.source == ReceiptSpendSource.derived)
          .length,
      knownSubtotal = _sumKnown(currency, receipts),
      productsPricingComplete = receipts.every(
        (row) => row.lineCount > 0 && row.products.isComplete,
      );

  final String currency;
  final int receiptCount;
  final int completeReceiptCount;
  final int partialReceiptCount;
  final int unknownReceiptCount;
  final int declaredReceiptCount;
  final int derivedReceiptCount;
  final Money? knownSubtotal;
  final bool productsPricingComplete;
  bool get pricingComplete => completeReceiptCount == receiptCount;
  Money? get amount => pricingComplete ? knownSubtotal : null;
  bool get totalOutsideExactRange => pricingComplete && knownSubtotal == null;

  static Money? _sumKnown(String currency, List<ReceiptSpendAmount> receipts) {
    var known = false;
    var total = BigInt.zero;
    for (final row in receipts) {
      if (row.knownSubtotal == null) continue;
      known = true;
      total += BigInt.from(row.knownSubtotal!.minorUnits);
    }
    if (!known || total > BigInt.parse('9007199254740991')) return null;
    return Money(currency: currency, minorUnits: total.toInt());
  }
}

final class ReceiptSpendSummary {
  ReceiptSpendSummary._(this.currencies);

  /// Calendar-date bounds are inclusive, like backend purchase reports. Draft
  /// and cancelled receipts are excluded. No clock-derived window is invented;
  /// the workspace includes all saved finished receipt dates and states this.
  factory ReceiptSpendSummary.fromReceipts({
    required String homeId,
    required Iterable<PurchaseReceiptCapture> receipts,
    DateTime? fromDate,
    DateTime? throughDate,
  }) {
    if (fromDate != null &&
        throughDate != null &&
        _calendarDate(fromDate).isAfter(_calendarDate(throughDate))) {
      throw ArgumentError('The receipt date range is reversed.');
    }
    final grouped = <String, List<ReceiptSpendAmount>>{};
    final ids = <String>{};
    for (final receipt in receipts) {
      if (receipt.homeId != homeId) {
        throw StateError('Cross-home receipt spending is not permitted.');
      }
      if (!ids.add(receipt.id)) {
        throw StateError('A receipt cannot be counted twice.');
      }
      if (receipt.status != PurchaseReceiptStatus.committed) continue;
      final date = _calendarDate(receipt.purchaseDate);
      if (fromDate != null && date.isBefore(_calendarDate(fromDate))) continue;
      if (throughDate != null && date.isAfter(_calendarDate(throughDate))) {
        continue;
      }
      grouped
          .putIfAbsent(receipt.currency, () => [])
          .add(ReceiptSpendAmount.fromReceipt(receipt));
    }
    final currencies = grouped.keys.toList()..sort();
    return ReceiptSpendSummary._(
      List.unmodifiable([
        for (final currency in currencies)
          ReceiptSpendCurrencySummary._(currency, grouped[currency]!),
      ]),
    );
  }

  final List<ReceiptSpendCurrencySummary> currencies;
  int get receiptCount =>
      currencies.fold(0, (count, row) => count + row.receiptCount);
  bool get pricingComplete => currencies.every((row) => row.pricingComplete);
  Money? get singleCurrencyAmount =>
      currencies.length == 1 ? currencies.single.amount : null;
}

DateTime _calendarDate(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);
