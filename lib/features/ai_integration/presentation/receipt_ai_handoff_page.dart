import 'package:flutter/material.dart';
import 'package:providentia/features/ai_integration/application/receipt_ai_handoff_controller.dart';

/// Second-confirmation boundary between accepted AI candidates and an
/// ordinary, uncommitted Phase 5 receipt draft.
final class ReceiptAiHandoffPage extends StatefulWidget {
  const ReceiptAiHandoffPage({
    required this.controller,
    required this.onOpenPurchasingReview,
    super.key,
  });

  final ReceiptAiHandoffController controller;
  final ValueChanged<String> onOpenPurchasingReview;

  @override
  State<ReceiptAiHandoffPage> createState() => _ReceiptAiHandoffPageState();
}

final class _ReceiptAiHandoffPageState extends State<ReceiptAiHandoffPage> {
  late final TextEditingController _purchaseDate;
  late final TextEditingController _currency;
  bool _understandsDraftOnly = false;
  final Map<int, TextEditingController> _missingLineTotals =
      <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _purchaseDate = TextEditingController(
      text: _dateText(widget.controller.header?.purchaseDate),
    );
    _currency = TextEditingController(
      text: widget.controller.header?.currency ?? '',
    );
    for (final (index, line) in widget.controller.lines.indexed) {
      if (line.unitPriceMinorUnits == null &&
          line.lineTotalMinorUnits == null) {
        _missingLineTotals[index] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    _purchaseDate.dispose();
    _currency.dispose();
    for (final controller in _missingLineTotals.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create reviewed receipt draft')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, child) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            const Text(
              'Nothing is saved until the final confirmation below. Confirming creates one draft receipt and unreviewed lines only.',
            ),
            const SizedBox(height: 8),
            const Text(
              'No line is matched or approved, no receipt is committed, and no stock movement is created here.',
              key: Key('receipt-ai-no-stock-disclosure'),
            ),
            if (widget.controller.header?.merchant case final merchant?) ...[
              const SizedBox(height: 12),
              Text('Extracted merchant: $merchant'),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const Key('receipt-ai-purchase-date'),
              controller: _purchaseDate,
              enabled: !widget.controller.isBusy,
              decoration: const InputDecoration(
                labelText: 'Purchase date',
                hintText: 'YYYY-MM-DD',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('receipt-ai-currency'),
              controller: _currency,
              enabled: !widget.controller.isBusy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Currency',
                hintText: 'NAD',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${widget.controller.lines.length} accepted line(s)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final (index, line) in widget.controller.lines.indexed)
              Card(
                key: Key('receipt-ai-line-$index'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        line.description,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${line.quantity} × ${line.packText ?? 'pack not provided'}'
                        '${_priceText(line.unitPriceMinorUnits, line.lineTotalMinorUnits)}',
                      ),
                      if (_missingLineTotals[index] case final priceController?)
                        TextField(
                          key: Key('receipt-ai-line-total-$index'),
                          controller: priceController,
                          enabled:
                              !widget.controller.isBusy &&
                              !widget.controller.pricesConfirmed,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Missing line total',
                            hintText: 'Amount paid for this receipt item',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (widget.controller.safeMessage case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                key: const Key('receipt-ai-handoff-message'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('receipt-ai-final-understanding'),
              value: _understandsDraftOnly,
              onChanged: widget.controller.canConfirm
                  ? (value) =>
                        setState(() => _understandsDraftOnly = value ?? false)
                  : null,
              title: const Text(
                'Create a draft only; I will match every line and commit it separately in purchasing review.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('receipt-ai-final-confirm'),
              onPressed: widget.controller.canConfirm && _understandsDraftOnly
                  ? _confirm
                  : null,
              icon: widget.controller.isBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.receipt_long_outlined),
              label: const Text('Create draft and review lines'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    final date = _parseDate(_purchaseDate.text.trim());
    if (date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid YYYY-MM-DD date.')),
      );
      return;
    }
    final missingLineTotals = <int, int>{};
    for (final entry in _missingLineTotals.entries) {
      final total = _parseMinorUnits(entry.value.text.trim());
      if (total == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter each missing line total with no more than two decimal places.',
            ),
          ),
        );
        return;
      }
      missingLineTotals[entry.key] = total;
    }
    final completed = await widget.controller.confirm(
      purchaseDate: date,
      currency: _currency.text,
      missingLineTotals: missingLineTotals,
    );
    if (!mounted || !completed) return;
    widget.onOpenPurchasingReview(widget.controller.receiptId!);
  }
}

String _dateText(DateTime? value) => value == null
    ? ''
    : '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';

DateTime? _parseDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final parsed = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  return _dateText(parsed) == value ? parsed : null;
}

String _priceText(int? unitPrice, int? lineTotal) {
  final values = <String>[
    if (unitPrice != null) 'unit ${_minor(unitPrice)}',
    if (lineTotal != null) 'line ${_minor(lineTotal)}',
  ];
  return values.isEmpty ? '' : ' · ${values.join(' · ')}';
}

String _minor(int value) =>
    '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';

int? _parseMinorUnits(String value) {
  final match = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(value);
  if (match == null) return null;
  final whole = int.tryParse(match.group(1)!);
  final fraction = int.tryParse((match.group(2) ?? '').padRight(2, '0'));
  if (whole == null || fraction == null || whole > 90071992547409) return null;
  final minorUnits = whole * 100 + fraction;
  return minorUnits > 9007199254740991 ? null : minorUnits;
}
