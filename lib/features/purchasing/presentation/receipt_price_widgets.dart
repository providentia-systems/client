import 'package:flutter/material.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/receipt_amounts.dart';

/// Saved receipt amounts include priced lines regardless of review status.
/// They describe purchase entry and do not authorize any stock mutation.
class ReceiptAmountSummary extends StatelessWidget {
  const ReceiptAmountSummary({required this.receipt, super.key});

  final PurchaseReceiptCapture receipt;

  @override
  Widget build(BuildContext context) {
    final amounts = ReceiptAmounts.fromReceipt(receipt);
    final difference = amounts.difference;
    final hasUnreviewed = receipt.lines.any((line) => !line.approved);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Receipt total: ${amounts.expectedTotal == null ? 'Not entered' : formatReceiptMoney(amounts.expectedTotal!)}',
              key: const Key('receipt-expected-total'),
            ),
            Text(
              'Products entered${amounts.isComplete ? '' : ' (known subtotal)'}: ${formatReceiptMoney(amounts.knownTotal)}',
              key: const Key('receipt-products-total'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (amounts.expectedTotalError != null)
              Text(
                amounts.expectedTotalError!,
                key: const Key('receipt-expected-total-error'),
              ),
            if (!amounts.isComplete)
              Text(
                '${amounts.unpricedLineCount} line${amounts.unpricedLineCount == 1 ? '' : 's'} with missing or invalid prices. Comparison is incomplete.',
                key: const Key('receipt-incomplete-prices'),
              ),
            if (amounts.currencyMismatchCount > 0)
              Text(
                '${amounts.currencyMismatchCount} line${amounts.currencyMismatchCount == 1 ? '' : 's'} use a different currency; review their amounts.',
                key: const Key('receipt-currency-mismatch'),
              ),
            Text(
              difference == null
                  ? amounts.expectedTotal == null
                        ? 'Difference unavailable: enter the physical receipt total to compare.'
                        : 'Difference unavailable until all line prices are valid.'
                  : difference.minorUnits < 0
                  ? 'Over by: ${formatReceiptMoney(Money(minorUnits: -difference.minorUnits, currency: difference.currency))}'
                  : difference.minorUnits > 0
                  ? 'Remaining: ${formatReceiptMoney(difference)}'
                  : 'Difference: ${formatReceiptMoney(difference)}',
              key: const Key('receipt-total-difference'),
            ),
            if (hasUnreviewed)
              const Text(
                'Includes priced imported and unresolved lines; this total does not mean they are approved for stock.',
              ),
          ],
        ),
      ),
    );
  }
}

class ReceiptLinePriceDetails extends StatelessWidget {
  const ReceiptLinePriceDetails({
    required this.line,
    required this.currency,
    super.key,
  });

  final PurchaseReceiptLineCapture line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final amounts = ReceiptLineAmounts.resolve(line, currency: currency);
    final quantity = purchasedLineQuantityText(line);
    final pack = line.originalPackText?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$quantity × ${pack == null || pack.isEmpty ? 'purchased unit' : pack}'
          '${line.unitPrice == null ? '' : ' @ ${formatReceiptMoney(line.unitPrice!)}'}'
          ' = ${amounts.total == null ? 'Price unknown ($currency)' : formatReceiptMoney(amounts.total!)}',
          key: Key('receipt-line-price-${line.id}'),
        ),
        if (amounts.error != null)
          Text(amounts.error!, key: Key('receipt-line-price-error-${line.id}')),
        if (amounts.hasDiscrepancy)
          Text(
            'Entered amount differs from quantity × unit price (${formatReceiptMoney(amounts.calculatedTotal!)}). Check discounts, promotions or receipt rounding.',
            key: Key('receipt-line-discrepancy-${line.id}'),
          ),
      ],
    );
  }
}

/// This preview never enters the saved receipt sum until the save succeeds.
class ReceiptLinePricePreview extends StatelessWidget {
  const ReceiptLinePricePreview({
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.currency,
    super.key,
  });

  final TextEditingController quantity;
  final TextEditingController unitPrice;
  final TextEditingController lineTotal;
  final String currency;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([quantity, unitPrice, lineTotal]),
    builder: (context, _) {
      String? error;
      Money? calculated;
      Money? entered;
      String? comparisonWarning;
      try {
        final price = parseReceiptMoney(unitPrice.text, currency: currency);
        entered = parseReceiptMoney(lineTotal.text, currency: currency);
        if (price != null) {
          try {
            calculated = calculatePurchasedLineTotal(
              quantityText: quantity.text.trim(),
              unitPrice: price,
            );
          } on ReceiptAmountRangeException {
            if (entered == null) rethrow;
            comparisonWarning =
                'The calculated amount exceeds the supported range. The entered line total is retained; arithmetic comparison is unavailable.';
          }
        }
      } on ArgumentError catch (failure) {
        error = failure.message?.toString() ?? 'Check the quantity and prices.';
      } on FormatException catch (failure) {
        error = failure.message;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            error != null
                ? 'Unsaved line preview: $error'
                : entered == null && calculated == null
                ? 'Unsaved line preview: enter a unit price or line total.'
                : 'Unsaved line preview: ${formatReceiptMoney((entered ?? calculated)!)}${entered == null ? ' (calculated)' : ' (entered amount)'}. Not included in Products entered.',
            key: const Key('receipt-line-price-preview'),
          ),
          if (comparisonWarning != null)
            Text(
              comparisonWarning,
              key: const Key('receipt-line-preview-comparison-unavailable'),
            ),
          if (entered != null && calculated != null && entered != calculated)
            Text(
              'Entered amount differs from quantity × unit price (${formatReceiptMoney(calculated)}). Keep the entered total for a discount, promotion or receipt rounding if correct.',
              key: const Key('receipt-line-preview-discrepancy'),
            ),
        ],
      );
    },
  );
}
