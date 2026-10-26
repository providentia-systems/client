import 'package:flutter/material.dart';
import 'package:providentia/features/purchasing/domain/receipt_amounts.dart';
import 'package:providentia/features/purchasing/domain/receipt_spend.dart';

class ReceiptSpendCard extends StatelessWidget {
  const ReceiptSpendCard({
    required this.summary,
    this.hasLoaded = true,
    this.readFailed = false,
    super.key,
  });

  final ReceiptSpendSummary summary;
  final bool hasLoaded;
  final bool readFailed;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Recent spend', style: Theme.of(context).textTheme.titleMedium),
          if (!hasLoaded)
            Text(
              readFailed
                  ? 'Receipt spending is unavailable; the saved receipt view could not be read.'
                  : 'Loading saved receipt spending…',
            ),
          if (hasLoaded && readFailed)
            const Text('Last known receipt spending; the latest read failed.'),
          if (hasLoaded) ...[
            Text(
              '${summary.receiptCount} finished receipt${summary.receiptCount == 1 ? '' : 's'} · all saved purchase dates',
            ),
            const Text(
              'Declared receipt totals take priority; otherwise complete product subtotals are used. Drafts and cancellations are excluded. Pending local corrections are included until verified by synchronization.',
            ),
            if (summary.currencies.isEmpty)
              const Text('No finished receipt spending recorded.'),
            for (final row in summary.currencies) ...[
              const SizedBox(height: 8),
              Text(
                row.amount != null
                    ? formatReceiptMoney(row.amount!)
                    : row.knownSubtotal != null
                    ? '${formatReceiptMoney(row.knownSubtotal!)} known subtotal · incomplete spending'
                    : row.totalOutsideExactRange
                    ? '${row.currency}: total exceeds the exact supported range'
                    : '${row.currency}: spending unavailable',
                key: Key('receipt-spend-${row.currency}'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${row.completeReceiptCount} complete, ${row.partialReceiptCount} partly priced, ${row.unknownReceiptCount} unknown receipt${row.receiptCount == 1 ? '' : 's'}',
              ),
              if (!row.productsPricingComplete)
                const Text(
                  'The entered-products breakdown is incomplete even when a declared receipt total is known.',
                ),
            ],
            if (summary.currencies.length > 1)
              const Text(
                'Currencies are shown separately and are never added together.',
              ),
          ],
        ],
      ),
    ),
  );
}
