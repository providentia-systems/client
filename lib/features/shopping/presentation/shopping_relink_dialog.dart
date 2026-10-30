import 'package:flutter/material.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';

/// Keeps the opened line revision and typed selection until a durable save.
class ShoppingRelinkDialog extends StatefulWidget {
  const ShoppingRelinkDialog({
    required this.controller,
    required this.line,
    super.key,
  });
  final ShoppingController controller;
  final ShoppingListLine line;

  @override
  State<ShoppingRelinkDialog> createState() => _ShoppingRelinkDialogState();
}

class _ShoppingRelinkDialogState extends State<ShoppingRelinkDialog> {
  late String? _productId = widget.line.homeProductId;
  late String? _packId = widget.line.selectedPackId;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty || _reason.text.trim().length > 500) {
      setState(() => _error = 'Give a reason of 1 to 500 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.controller.relinkLine(
      widget.line,
      homeProductId: _productId,
      selectedPackId: _packId,
      reason: _reason.text,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error =
            widget.controller.state.safeError ??
            'The selection could not be saved. Your input is retained.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final products = widget.controller.items;
      final product = products
          .where((item) => item.id == _productId)
          .firstOrNull;
      final packs = _productId == null
          ? const <ShoppingPackChoice>[]
          : widget.controller.packChoices(_productId!);
      final saved =
          widget.controller.state.list?.lines
              .where((line) => line.id == widget.line.id)
              .firstOrNull ??
          widget.line;
      return AlertDialog(
        title: const Text('Change product or pack'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Current saved link: ${widget.controller.linkedProductLabel(saved)} · ${widget.controller.quantityLabel(saved)}',
                ),
                Text('Purchasing instructions: ${widget.line.name}'),
                Text(
                  'The number ${widget.line.quantity} is retained. Choose what that quantity means below. This does not add stock or purchase anything.',
                ),
                DropdownButtonFormField<String>(
                  key: const Key('shopping-relink-product'),
                  initialValue: _productId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Household product',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Custom item (no product link)'),
                    ),
                    if (_productId != null && product == null)
                      DropdownMenuItem(
                        value: _productId,
                        enabled: false,
                        child: const Text(
                          'Previously linked product unavailable',
                        ),
                      ),
                    for (final item in products)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text('${item.canonicalName} · ${item.packSize}'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _productId = value == '' ? null : value;
                          _packId = null;
                        }),
                ),
                if (_productId != null)
                  DropdownButtonFormField<String>(
                    key: ValueKey('shopping-relink-pack-$_productId'),
                    initialValue: _packId ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Quantity refers to',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(
                          'Stock measurement (${product?.unit ?? 'unavailable'})',
                        ),
                      ),
                      if (_packId != null &&
                          !packs.any((pack) => pack.id == _packId))
                        DropdownMenuItem(
                          value: _packId,
                          enabled: false,
                          child: const Text(
                            'Previously selected pack unavailable',
                          ),
                        ),
                      for (final pack in packs)
                        DropdownMenuItem(
                          value: pack.id,
                          child: Text('Packs: ${pack.label}'),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(
                            () => _packId = value == '' ? null : value,
                          ),
                  ),
                TextField(
                  key: const Key('shopping-relink-reason'),
                  controller: _reason,
                  enabled: !_saving,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Reason for changing this link',
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (_saving) const LinearProgressIndicator(),
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
            key: const Key('shopping-relink-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Confirm relink'),
          ),
        ],
      );
    },
  );
}
