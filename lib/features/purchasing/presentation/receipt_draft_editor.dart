import 'package:flutter/material.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';

/// Keeps the opened revision until save so a remote edit cannot be overwritten.
class ReceiptDraftEditor extends StatefulWidget {
  const ReceiptDraftEditor({
    required this.controller,
    required this.receipt,
    this.line,
    super.key,
  });

  final PurchasingController controller;
  final PurchaseReceiptCapture receipt;
  final PurchaseReceiptLineCapture? line;

  @override
  State<ReceiptDraftEditor> createState() => _ReceiptDraftEditorState();
}

class _ReceiptDraftEditorState extends State<ReceiptDraftEditor> {
  late final Map<String, TextEditingController> _fields;
  String? _storeId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final receipt = widget.receipt;
    final line = widget.line;
    _storeId = receipt.storeId;
    final values = line == null
        ? <String, String>{
            'date': receipt.purchaseDate.toIso8601String().split('T').first,
            'currency': receipt.currency,
            'total': _amount(receipt.total),
            'notes': receipt.notes,
          }
        : <String, String>{
            'description': line.rawDescription,
            'pack': line.originalPackText ?? '',
            'quantity': line.quantity.toString(),
            'unitPrice': _amount(line.unitPrice),
            'total': _amount(line.lineTotal),
          };
    _fields = values.map(
      (key, value) => MapEntry(key, TextEditingController(text: value)),
    );
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _amount(Money? money) =>
      money == null ? '' : (money.minorUnits / 100).toStringAsFixed(2);

  Widget _field(
    String name,
    String label, {
    int? maxLength,
    bool number = false,
  }) => TextField(
    key: Key('receipt-edit-$name'),
    controller: _fields[name],
    enabled: !_saving,
    maxLength: maxLength,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(labelText: label),
  );

  @override
  Widget build(BuildContext context) {
    final stores = widget.controller.stores
        .where((store) => !store.archived)
        .toList();
    return AlertDialog(
      title: Text(widget.line == null ? 'Edit receipt' : 'Edit receipt line'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.line == null) ...[
                DropdownButtonFormField<String>(
                  key: const Key('receipt-edit-store'),
                  initialValue: stores.any((store) => store.id == _storeId)
                      ? _storeId
                      : null,
                  decoration: const InputDecoration(labelText: 'Store'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No store'),
                    ),
                    for (final store in stores)
                      DropdownMenuItem(
                        value: store.id,
                        child: Text(store.name),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _storeId = value),
                ),
                _field('date', 'Purchase date (YYYY-MM-DD)'),
                _field('currency', 'Currency', maxLength: 3),
                _field('total', 'Receipt total (optional)', number: true),
                _field('notes', 'Notes', maxLength: 2000),
              ] else ...[
                _field('description', 'Receipt line text', maxLength: 500),
                _field('pack', 'Pack text (optional)', maxLength: 191),
                _field('quantity', 'Quantity', number: true),
                _field('unitPrice', 'Unit price (optional)', number: true),
                _field('total', 'Line total (optional)', number: true),
                const Text(
                  'Review the edited line again before committing this receipt.',
                ),
              ],
              if (_error != null)
                Text(_error!, key: const Key('receipt-edit-error')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('receipt-edit-save'),
          onPressed: _saving ? null : _save,
          child: const Text('Save changes'),
        ),
      ],
    );
  }

  Money? _money(String field, String currency) {
    final text = _fields[field]!.text.trim();
    if (text.isEmpty) return null;
    if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(text)) {
      throw const FormatException(
        'Use non-negative amounts with at most two decimals.',
      );
    }
    final parts = text.split('.');
    return Money(
      minorUnits:
          int.parse(parts.first) * 100 +
          (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0'))),
      currency: currency,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final line = widget.line;
      bool saved;
      if (line == null) {
        final text = _fields['date']!.text.trim();
        final date = DateTime.tryParse(text);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
            date == null ||
            date.toIso8601String().split('T').first != text) {
          throw const FormatException(
            'Enter a valid calendar date as YYYY-MM-DD.',
          );
        }
        final currency = _fields['currency']!.text.trim().toUpperCase();
        saved = await widget.controller.updateDraft(
          original: widget.receipt,
          purchaseDate: date,
          currency: currency,
          storeId: _storeId,
          total: _money('total', currency),
          notes: _fields['notes']!.text,
        );
      } else {
        saved = await widget.controller.updateLine(
          original: line,
          rawDescription: _fields['description']!.text,
          quantity: double.tryParse(_fields['quantity']!.text) ?? double.nan,
          originalPackText: _fields['pack']!.text,
          unitPrice: _money('unitPrice', widget.receipt.currency),
          lineTotal: _money('total', widget.receipt.currency),
        );
      }
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
        return;
      }
      setState(
        () => _error =
            widget.controller.state.captureError ??
            'The draft change could not be saved.',
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on ArgumentError catch (_) {
      if (mounted) {
        setState(() => _error = 'Check the receipt values and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
