import 'package:flutter/material.dart';
import 'package:providentia/core/presentation/quantity_field.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/receipt_amounts.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/receipt_price_widgets.dart';

/// Holds the opened aggregate/line revisions and typed values until a durable
/// correction is saved. It never reopens or recommits the original receipt.
class FinishedReceiptLineEditor extends StatefulWidget {
  const FinishedReceiptLineEditor({
    required this.controller,
    required this.receipt,
    this.line,
    super.key,
  });

  final PurchasingController controller;
  final PurchaseReceiptCapture receipt;
  final PurchaseReceiptLineCapture? line;

  @override
  State<FinishedReceiptLineEditor> createState() =>
      _FinishedReceiptLineEditorState();
}

class _FinishedReceiptLineEditorState extends State<FinishedReceiptLineEditor> {
  final _form = GlobalKey<FormState>();
  late final _description = TextEditingController(
    text: widget.line?.rawDescription ?? '',
  );
  late final _quantity = TextEditingController(
    text: widget.line?.quantityText ?? '1',
  );
  late final _pack = TextEditingController(
    text: widget.line?.originalPackText ?? '',
  );
  late final _unitPrice = TextEditingController(
    text: _amount(widget.line?.unitPrice),
  );
  late final _total = TextEditingController(
    text: _amount(widget.line?.lineTotal),
  );
  final _reason = TextEditingController();
  String? _productId;
  String? _packId;
  bool _saving = false;
  String? _error;

  String _amount(Money? money) => money == null
      ? ''
      : formatReceiptMoney(money).substring(money.currency.length + 1);

  @override
  void dispose() {
    for (final field in [
      _description,
      _quantity,
      _pack,
      _unitPrice,
      _total,
      _reason,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  Money? _money(String text) {
    if (text.trim().isEmpty) return null;
    final parts = text.trim().split('.');
    return Money(
      minorUnits:
          int.parse(parts.first) * 100 +
          int.parse((parts.length == 1 ? '' : parts.last).padRight(2, '0')),
      currency: widget.receipt.currency,
    );
  }

  String? _priceError(String? value) =>
      value == null ||
          value.trim().isEmpty ||
          RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(value.trim())
      ? null
      : 'Use a non-negative amount with at most two decimals.';

  @override
  Widget build(BuildContext context) {
    final products = <String, PurchaseMatchCandidate>{};
    for (final candidate in widget.controller.state.matchCandidates) {
      if (candidate.homeProductId != null) {
        products.putIfAbsent(candidate.homeProductId!, () => candidate);
      }
    }
    final selected = products[_productId];
    final packs = <String, PurchaseMatchCandidate>{};
    if (selected?.productId != null) {
      for (final candidate in widget.controller.state.matchCandidates) {
        if (candidate.productId == selected!.productId &&
            candidate.packId != null &&
            candidate.packStatus == 'published') {
          packs[candidate.packId!] = candidate;
        }
      }
    }
    return AlertDialog(
      title: Text(
        widget.line == null ? 'Add omitted purchase' : 'Resolve purchase',
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Receipt date: ${widget.receipt.purchaseDate.toIso8601String().split('T').first} · ${widget.receipt.currency}',
                ),
                const Text(
                  'This correction adds only this purchase. The finished receipt and existing stock contributions stay in place.',
                ),
                DropdownButtonFormField<String>(
                  key: const Key('finished-line-product'),
                  initialValue: _productId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Home product'),
                  items: products.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            '${entry.value.name} · ${entry.value.packSize}',
                          ),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Choose an existing home product.' : null,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _productId = value;
                          _packId = null;
                          if (_description.text.trim().isEmpty &&
                              value != null) {
                            _description.text = products[value]!.name;
                          }
                        }),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('finished-line-measurement-$_productId'),
                  initialValue: _packId ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Quantity refers to',
                  ),
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        'Stock measurement (${selected?.stockUnit ?? 'choose a product'})',
                      ),
                    ),
                    for (final entry in packs.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text('Packs: ${entry.value.packSize}'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _packId = value == '' ? null : value;
                          if (value != null && packs[value] != null) {
                            _pack.text = packs[value]!.packSize;
                          }
                        }),
                ),
                TextFormField(
                  key: const Key('finished-line-description'),
                  controller: _description,
                  enabled: !_saving,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Receipt line text',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a description.'
                      : null,
                ),
                QuantityField(
                  key: const Key('finished-line-quantity'),
                  controller: _quantity,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    final quantity = double.tryParse(text);
                    return RegExp(r'^\d+(\.\d{1,8})?$').hasMatch(text) &&
                            quantity != null &&
                            quantity.isFinite &&
                            quantity > 0
                        ? null
                        : 'Enter a positive quantity with at most eight decimals.';
                  },
                ),
                TextFormField(
                  controller: _pack,
                  enabled: !_saving,
                  maxLength: 191,
                  decoration: const InputDecoration(
                    labelText: 'Pack text (optional)',
                  ),
                ),
                TextFormField(
                  key: const Key('finished-line-unit-price'),
                  controller: _unitPrice,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Unit price (optional)',
                  ),
                  validator: _priceError,
                ),
                TextFormField(
                  key: const Key('finished-line-total'),
                  controller: _total,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Explicit line total (optional)',
                  ),
                  validator: _priceError,
                ),
                ReceiptLinePricePreview(
                  quantity: _quantity,
                  unitPrice: _unitPrice,
                  lineTotal: _total,
                  currency: widget.receipt.currency,
                ),
                const Text(
                  'Leave missing prices blank. An explicit line total is retained for discounts and receipt rounding.',
                ),
                TextFormField(
                  key: const Key('finished-line-reason'),
                  controller: _reason,
                  enabled: !_saving,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Correction reason',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Explain why this purchase is being corrected.'
                      : null,
                ),
                if (_error != null) ...[
                  Text(
                    _error!,
                    key: const Key('finished-line-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const Text(
                    'Your entries are retained. Reopen the latest receipt if its revision changed; the correction has not been replaced automatically.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('finished-line-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save purchase correction'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.controller.completeFinishedLine(
      originalReceipt: widget.receipt,
      originalLine: widget.line,
      homeProductId: _productId!,
      packId: _packId,
      rawDescription: _description.text,
      quantityText: _quantity.text.trim(),
      originalPackText: _pack.text,
      unitPrice: _money(_unitPrice.text),
      lineTotal: _money(_total.text),
      reason: _reason.text,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error =
            widget.controller.state.captureError ??
            'The correction could not be saved. Your entries are retained.';
      });
    }
  }
}
