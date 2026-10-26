import 'package:flutter/material.dart';
import 'package:providentia/features/purchasing/domain/purchase_calendar.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/receipt_amounts.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';

String receiptLifecycleLabel(PurchaseReceiptCapture receipt) {
  if (receipt.status == PurchaseReceiptStatus.cancelled) {
    if (receipt.auditEntries.any(
      (entry) =>
          entry.kind == 'Receipt cancellation' &&
          entry.state == PurchaseReceiptAuditState.failed,
    )) {
      return 'Cancellation needs review; server acceptance not confirmed';
    }
    if (!receipt.cancellationConfirmed) {
      return 'Cancellation queued; awaiting server confirmation';
    }
    return receipt.synchronizationState == PurchaseSynchronizationState.pending
        ? 'Cancellation accepted; details refreshing'
        : 'Cancelled';
  }
  if (receipt.emptyAfterCorrection) {
    return '${receipt.status == PurchaseReceiptStatus.committed ? 'Finished' : 'Draft'} · empty after correction';
  }
  return receipt.status == PurchaseReceiptStatus.committed
      ? 'Finished'
      : 'Draft';
}

class ReceiptHistoryDetails extends StatelessWidget {
  const ReceiptHistoryDetails({
    required this.receipt,
    required this.controller,
    this.showRetainedLines = false,
    super.key,
  });
  final PurchaseReceiptCapture receipt;
  final PurchasingController controller;
  final bool showRetainedLines;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Purchase day: ${formatPurchaseDay(receipt.purchaseDate)}',
        key: Key('receipt-purchase-day-${receipt.id}'),
      ),
      Text(
        receipt.createdAt == null
            ? 'Server creation time is not in this saved snapshot. Refresh history online to view it.'
            : 'Created: ${receipt.createdAt!.toUtc().toIso8601String()} (automatic; immutable)',
        key: Key('receipt-created-at-${receipt.id}'),
      ),
      if (receipt.recordedAt != null)
        Text(
          'Recorded on this device: ${receipt.recordedAt!.toUtc().toIso8601String()}',
        ),
      Text('${receiptLifecycleLabel(receipt)} · revision ${receipt.revision}'),
      if (receipt.total != null)
        Text(
          '${receipt.status == PurchaseReceiptStatus.cancelled ? 'Historical receipt total (excluded from active spend)' : 'Receipt total'}: ${formatReceiptMoney(receipt.total!)}',
        ),
      if (receipt.lines.isEmpty)
        Text(
          receipt.emptyAfterCorrection
              ? 'All entered lines were removed. The receipt still exists and was not cancelled automatically.'
              : 'No active product lines are recorded on this receipt.',
        ),
      if (receipt.notes.isNotEmpty) Text('Notes: ${receipt.notes}'),
      if (showRetainedLines && receipt.lines.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Retained receipt lines'),
        for (final line in receipt.lines)
          ListTile(
            dense: true,
            key: Key('receipt-retained-line-${line.id}'),
            title: Text(line.rawDescription),
            subtitle: Text(
              [
                line.unresolved
                    ? 'Unresolved; no stock applied'
                    : 'Recorded purchase',
                'Purchased quantity ${line.quantityText ?? line.quantity}',
                if (line.originalPackText != null) line.originalPackText!,
                line.lineTotal != null
                    ? 'Line total ${formatReceiptMoney(line.lineTotal!)}'
                    : line.unitPrice != null
                    ? 'Unit price ${formatReceiptMoney(line.unitPrice!)}'
                    : 'Price not recorded',
              ].join(' · '),
            ),
          ),
      ],
      if (receipt.removedLines.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Removed lines (retained history)'),
        for (final line in receipt.removedLines)
          ListTile(
            dense: true,
            key: Key('receipt-removed-line-${line.id}'),
            title: Text(line.rawDescription),
            subtitle: Text(
              'Removed · purchased quantity ${line.quantityText ?? line.quantity}${line.originalPackText == null ? '' : ' · ${line.originalPackText}'} · line revision ${line.revision}',
            ),
          ),
      ],
      if (receipt.auditEntries.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Corrections and saved operations'),
        for (final event in [
          ...receipt.auditEntries,
        ]..sort((a, b) => b.at.compareTo(a.at)))
          ListTile(
            dense: true,
            key: Key('receipt-audit-${event.id}'),
            title: Text(
              '${event.kind} · ${switch (event.state) {
                PurchaseReceiptAuditState.accepted => 'accepted',
                PurchaseReceiptAuditState.pending => 'saved locally; pending',
                PurchaseReceiptAuditState.failed => 'needs review',
              }}',
            ),
            subtitle: Text(
              [
                if (event.originalPurchaseDay != null ||
                    event.purchaseDay != null)
                  '${event.originalPurchaseDay ?? 'Purchase day'} → ${event.purchaseDay ?? 'unchanged'}',
                if (event.lineDescription != null) event.lineDescription!,
                event.reason,
                '${event.at.toUtc().toIso8601String()}${event.recordedLocally ? ' (local operation recording time)' : ''}',
                if (event.safeFailure != null) event.safeFailure!,
              ].join('\n'),
            ),
          ),
      ],
      if (controller.historyError(receipt.id) case final String error)
        Text(error, key: Key('receipt-history-error-${receipt.id}')),
      OutlinedButton.icon(
        key: Key('receipt-refresh-history-${receipt.id}'),
        onPressed: controller.historyRefreshing(receipt.id)
            ? null
            : () => controller.refreshReceiptHistory(receipt.id),
        icon: const Icon(Icons.history),
        label: Text(
          controller.historyRefreshing(receipt.id)
              ? 'Refreshing receipt history…'
              : 'Refresh receipt creation and correction history',
        ),
      ),
    ],
  );
}

class ReceiptHistorySection extends StatefulWidget {
  const ReceiptHistorySection({required this.controller, super.key});
  final PurchasingController controller;
  @override
  State<ReceiptHistorySection> createState() => _ReceiptHistorySectionState();
}

class _ReceiptHistorySectionState extends State<ReceiptHistorySection> {
  String _filter = 'all';
  @override
  Widget build(BuildContext context) {
    final receipts = widget.controller.receipts
        .where(
          (receipt) => switch (_filter) {
            'active' => receipt.status != PurchaseReceiptStatus.cancelled,
            'finished' => receipt.status == PurchaseReceiptStatus.committed,
            'empty' => receipt.lines.isEmpty,
            'cancelled' => receipt.status == PurchaseReceiptStatus.cancelled,
            _ => true,
          },
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Receipt history', style: Theme.of(context).textTheme.titleLarge),
        DropdownButtonFormField<String>(
          key: const Key('receipt-history-filter'),
          initialValue: _filter,
          decoration: const InputDecoration(labelText: 'Show receipts'),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All receipts')),
            DropdownMenuItem(value: 'active', child: Text('Active receipts')),
            DropdownMenuItem(
              value: 'finished',
              child: Text('Finished receipts'),
            ),
            DropdownMenuItem(value: 'empty', child: Text('Empty receipts')),
            DropdownMenuItem(
              value: 'cancelled',
              child: Text('Cancelled receipts'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _filter = value);
          },
        ),
        if (receipts.isEmpty) const Text('No receipts match this filter.'),
        for (final receipt in receipts)
          Card(
            child: ExpansionTile(
              key: Key('receipt-history-${receipt.id}'),
              title: Text(
                '${formatPurchaseDay(receipt.purchaseDate)} · ${receipt.storeName ?? 'Unspecified store'}',
              ),
              subtitle: Text(receiptLifecycleLabel(receipt)),
              childrenPadding: const EdgeInsets.all(12),
              children: [
                ReceiptHistoryDetails(
                  receipt: receipt,
                  controller: widget.controller,
                  showRetainedLines: true,
                ),
                if (widget.controller.captureEnabled)
                  OutlinedButton(
                    key: Key('receipt-select-history-${receipt.id}'),
                    onPressed: () =>
                        widget.controller.selectReceipt(receipt.id),
                    child: const Text('Select this receipt for actions above'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
