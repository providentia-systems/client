import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/core/presentation/quantity_field.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/receipt_amounts.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/receipt_price_widgets.dart';

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
  final _formKey = GlobalKey<FormState>();
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, GlobalKey> _fieldKeys = {};
  String? _invalidField;
  String? _storeId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final receipt = widget.receipt;
    final line = widget.line;
    _storeId = receipt.storeId;
    widget.controller.addListener(_handleControllerChange);
    if (line == null) {
      _focusNodes['store'] = FocusNode();
      _fieldKeys['store'] = GlobalKey();
    }
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
            'quantity': line.quantityText ?? line.quantity.toString(),
            'unitPrice': _amount(line.unitPrice),
            'total': _amount(line.lineTotal),
          };
    for (final name in values.keys) {
      _focusNodes[name] = FocusNode();
      _fieldKeys[name] = GlobalKey();
    }
    _fields = values.map(
      (key, value) => MapEntry(key, TextEditingController(text: value)),
    );
  }

  void _handleControllerChange() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ReceiptDraftEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChange);
      widget.controller.addListener(_handleControllerChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    for (final controller in _fields.values) {
      controller.dispose();
    }
    for (final focus in _focusNodes.values) {
      focus.dispose();
    }
    super.dispose();
  }

  String _amount(Money? money) => money == null
      ? ''
      : formatReceiptMoney(money).substring(money.currency.length + 1);

  Widget _field(
    String name,
    String label, {
    int? maxLength,
    bool number = false,
    bool readOnly = false,
  }) {
    final decoration = InputDecoration(labelText: label);
    final field = name == 'quantity'
        ? QuantityField(
            key: Key('receipt-edit-$name'),
            controller: _fields[name]!,
            focusNode: _focusNodes[name],
            enabled: !_saving,
            decoration: decoration,
            validator: (value) => _validateField(name, value ?? ''),
          )
        : TextFormField(
            key: Key('receipt-edit-$name'),
            controller: _fields[name],
            focusNode: _focusNodes[name],
            enabled: !_saving,
            readOnly: readOnly,
            maxLength: maxLength,
            keyboardType: number
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: decoration,
            validator: (value) => _validateField(name, value ?? ''),
          );
    return KeyedSubtree(key: _fieldKeys[name], child: field);
  }

  String? _validateField(String name, String value) {
    final text = value.trim();
    String? error;
    if (name == 'date') {
      final date = DateTime.tryParse('${text}T00:00:00Z');
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
          date == null ||
          date.toIso8601String().split('T').first != text) {
        error = 'Enter a valid calendar date as YYYY-MM-DD.';
      }
    } else if (name == 'currency' && !RegExp(r'^[A-Za-z]{3}$').hasMatch(text)) {
      error = 'Use a three-letter currency code.';
    } else if (name == 'description' && text.isEmpty) {
      error = 'Enter the receipt line description.';
    } else if (name == 'quantity') {
      final quantity = double.tryParse(text);
      if (!RegExp(r'^\d+(\.\d{1,8})?$').hasMatch(text) ||
          quantity == null ||
          !quantity.isFinite ||
          quantity <= 0) {
        error = 'Enter a positive quantity with at most eight decimals.';
      }
    } else if ((name == 'total' || name == 'unitPrice') &&
        text.isNotEmpty &&
        !RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(text)) {
      error = 'Use a non-negative amount with at most two decimals.';
    }
    if (error != null) _invalidField ??= name;
    return error;
  }

  void _focusInvalidField() {
    final name = _invalidField;
    if (name == null) return;
    _focusNodes[name]?.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fieldContext = _fieldKeys[name]?.currentContext;
      if (fieldContext != null) {
        unawaited(Scrollable.ensureVisible(fieldContext, alignment: 0.1));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allStores = widget.controller.stores;
    final stores = allStores.where((store) => !store.archived).toList();
    final originalId = widget.receipt.storeId;
    final historicalStore = allStores
        .where((store) => store.id == originalId)
        .firstOrNull;
    final originalUnavailable =
        originalId != null && !stores.any((store) => store.id == originalId);
    final selectedUnavailable =
        _storeId != null &&
        _storeId != originalId &&
        !stores.any((store) => store.id == _storeId);
    final unavailableSelection = allStores
        .where((store) => store.id == _storeId)
        .firstOrNull;
    final historicalLabel = historicalStore != null
        ? '${historicalStore.name} (archived · current store)'
        : '${widget.receipt.storeName == null || widget.receipt.storeName == 'Unavailable store' ? 'Historical store' : widget.receipt.storeName} (unavailable · current store)';
    return AlertDialog(
      title: Text(widget.line == null ? 'Edit receipt' : 'Edit receipt line'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.line == null) ...[
                  KeyedSubtree(
                    key: _fieldKeys['store'],
                    child: DropdownButtonFormField<String>(
                      key: const Key('receipt-edit-store'),
                      initialValue: _storeId,
                      focusNode: _focusNodes['store'],
                      isExpanded: true,
                      hint: const Text('No store'),
                      decoration: const InputDecoration(labelText: 'Store'),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: (value) {
                        if (value == null ||
                            value == originalId ||
                            stores.any((store) => store.id == value)) {
                          return null;
                        }
                        _invalidField ??= 'store';
                        return 'Choose an active store from this home, or keep the current historical store.';
                      },
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('No store'),
                        ),
                        if (originalUnavailable)
                          DropdownMenuItem(
                            value: originalId,
                            child: Text(historicalLabel),
                          ),
                        for (final store in stores)
                          DropdownMenuItem(
                            value: store.id,
                            child: Text(store.name),
                          ),
                        if (selectedUnavailable)
                          DropdownMenuItem(
                            value: _storeId,
                            enabled: false,
                            child: Text(
                              '${unavailableSelection?.name ?? 'Selected store'} (unavailable · choose another store)',
                            ),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _storeId = value),
                    ),
                  ),
                  if (originalUnavailable && _storeId == originalId)
                    Text(
                      historicalStore == null
                          ? 'This historical store is unavailable. Its saved association stays on this receipt unless you choose another store or No store.'
                          : 'This store is archived. It stays on this receipt unless you choose another store or No store.',
                      key: const Key('receipt-edit-historical-store'),
                    ),
                  _field(
                    'date',
                    'Purchase date (YYYY-MM-DD)',
                    readOnly: widget.receipt.purchaseBasisFixed,
                  ),
                  _field(
                    'currency',
                    'Currency',
                    maxLength: 3,
                    readOnly: widget.receipt.purchaseBasisFixed,
                  ),
                  _field('total', 'Receipt total (optional)', number: true),
                  _field('notes', 'Notes', maxLength: 2000),
                ] else ...[
                  _field('description', 'Receipt line text', maxLength: 500),
                  _field('pack', 'Pack text (optional)', maxLength: 191),
                  _field('quantity', 'Quantity', number: true),
                  _field('unitPrice', 'Unit price (optional)', number: true),
                  _field('total', 'Line total (optional)', number: true),
                  ReceiptLinePricePreview(
                    quantity: _fields['quantity']!,
                    unitPrice: _fields['unitPrice']!,
                    lineTotal: _fields['total']!,
                    currency: widget.receipt.currency,
                  ),
                  Text(
                    widget.line!.stockApplied
                        ? 'Saving this correction adjusts stock by the difference. The selected product and pack stay the same.'
                        : widget.receipt.status ==
                              PurchaseReceiptStatus.committed
                        ? 'This line remains intentionally unresolved. Editing its details does not add stock. Use Resolve purchase to record it.'
                        : 'Review the edited line again before committing this receipt.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (_saving || _error != null)
          SizedBox(
            width: 420,
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_saving) ...[
                    const LinearProgressIndicator(),
                    const Text('Saving on this device…'),
                  ],
                  if (_error != null) ...[
                    Text(
                      _error!,
                      key: const Key('receipt-edit-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const Text(
                      'Your entries are retained. Nothing will be overwritten automatically.',
                    ),
                    TextButton(
                      key: const Key('receipt-edit-review-current'),
                      onPressed: _saving ? null : _reviewCurrent,
                      child: const Text('Review current saved values'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('receipt-edit-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save changes'),
        ),
      ],
    );
  }

  Future<void> _reviewCurrent() async {
    final current = widget.controller.state.capture;
    final sameReceipt = current?.id == widget.receipt.id;
    final line = sameReceipt && widget.line != null
        ? current!.lines
              .where((value) => value.id == widget.line!.id)
              .firstOrNull
        : null;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Current saved values'),
        content: SingleChildScrollView(
          child: Text(
            !sameReceipt
                ? 'The selected receipt changed. Your editor entries are retained. Close this editor only when ready to return to the selected receipt.'
                : widget.line == null
                ? 'Saved revision ${current!.revision} (opened revision ${widget.receipt.revision}).\n'
                      'Date: ${current.purchaseDate.toIso8601String().split('T').first}\n'
                      'Currency: ${current.currency}\n'
                      'Receipt total: ${_amount(current.total)}\n'
                      'Notes: ${current.notes}\n\n'
                      'Review differences before closing this editor and reopening the latest receipt. Your typed values remain in the editor.'
                : line == null
                ? 'This line is no longer present in the current receipt. Your typed values remain in the editor.'
                : 'Saved revision ${line.revision} (opened revision ${widget.line!.revision}).\n'
                      'Description: ${line.rawDescription}\n'
                      'Quantity: ${line.quantityText ?? line.quantity.toString()}\n'
                      'Pack: ${line.originalPackText ?? ''}\n'
                      'Unit price: ${_amount(line.unitPrice)}\n'
                      'Line total: ${_amount(line.lineTotal)}\n\n'
                      'Your typed values remain in the editor; no saved values have been replaced.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Return to my entries'),
          ),
        ],
      ),
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
    _invalidField = null;
    if (!_formKey.currentState!.validate()) {
      setState(
        () => _error = 'Correct the highlighted field. Nothing was saved.',
      );
      _focusInvalidField();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final line = widget.line;
      bool saved;
      if (line == null) {
        final text = _fields['date']!.text.trim();
        final date = DateTime.tryParse('${text}T00:00:00Z');
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
          quantityText: _fields['quantity']!.text.trim(),
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
