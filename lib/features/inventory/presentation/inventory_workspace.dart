import 'package:flutter/material.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

class InventoryWorkspace extends StatefulWidget {
  const InventoryWorkspace({required this.controller, super.key});

  final InventoryController controller;

  @override
  State<InventoryWorkspace> createState() => _InventoryWorkspaceState();
}

class _InventoryWorkspaceState extends State<InventoryWorkspace> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final categories = <String>{
          'All',
          ...state.items.map((item) => item.category),
        }.toList()..sort();
        return CustomScrollView(
          key: const Key('inventory-workspace'),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList.list(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Stock',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                      ),
                      if (widget.controller.canCreatePrivateProduct)
                        FilledButton.icon(
                          key: const Key('inventory-add-private-product'),
                          onPressed: state.productCreationBusy
                              ? null
                              : _showAddPrivateProduct,
                          icon: const Icon(Icons.add),
                          label: const Text('Add product'),
                        ),
                    ],
                  ),
                  if (state.productCreationNotice != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      state.productCreationNotice!,
                      key: const Key('inventory-product-creation-notice'),
                    ),
                  ],
                  if (state.productCreationError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      state.productCreationError!,
                      key: const Key('inventory-product-creation-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SegmentedButton<InventoryView>(
                    segments: const <ButtonSegment<InventoryView>>[
                      ButtonSegment(
                        value: InventoryView.counted,
                        label: Text('Counted'),
                      ),
                      ButtonSegment(
                        value: InventoryView.itemMaster,
                        label: Text('Item master'),
                      ),
                    ],
                    selected: <InventoryView>{state.criteria.view},
                    onSelectionChanged: (selection) =>
                        widget.controller.selectView(selection.single),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('inventory-search'),
                    decoration: const InputDecoration(
                      labelText: 'Search products, aliases, brands, or packs',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: widget.controller.updateSearch,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const Key('inventory-category'),
                    initialValue: state.criteria.category ?? 'All',
                    items: categories
                        .map(
                          (category) => DropdownMenuItem<String>(
                            value: category,
                            child: Text(category),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (category) => widget.controller.selectCategory(
                      category == 'All' ? null : category,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CountSessionBar(controller: widget.controller),
                  if (state.safeError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(state.safeError!),
                    ),
                  const SizedBox(height: 12),
                  for (final item in widget.controller.visibleItems)
                    _InventoryRow(
                      item: item,
                      controller: widget.controller,
                      countSessionActive: state.activeSession != null,
                    ),
                  if (!state.loading && widget.controller.visibleItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No matching inventory items.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddPrivateProduct() async {
    final draft = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => const _PrivateHomeProductDialog(),
    );
    if (draft == null || !mounted) return;
    await widget.controller.createPrivateProduct(
      privateName: draft.$1,
      originalPackText: draft.$2,
    );
  }
}

class _PrivateHomeProductDialog extends StatefulWidget {
  const _PrivateHomeProductDialog();

  @override
  State<_PrivateHomeProductDialog> createState() =>
      _PrivateHomeProductDialogState();
}

class _PrivateHomeProductDialogState extends State<_PrivateHomeProductDialog> {
  final _name = TextEditingController();
  final _pack = TextEditingController();
  String? _safeError;

  @override
  void dispose() {
    _name.dispose();
    _pack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add private product'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'This name and pack text stay private to the active home.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('inventory-private-product-name'),
            controller: _name,
            maxLength: 191,
            decoration: const InputDecoration(labelText: 'Private name'),
          ),
          TextField(
            key: const Key('inventory-private-product-pack'),
            controller: _pack,
            maxLength: 191,
            decoration: const InputDecoration(
              labelText: 'Original pack text (optional)',
            ),
          ),
          if (_safeError != null)
            Text(
              _safeError!,
              key: const Key('inventory-private-product-validation'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('inventory-save-private-product'),
          onPressed: _save,
          child: const Text('Save locally'),
        ),
      ],
    );
  }

  void _save() {
    final name = _name.text.trim();
    final pack = _pack.text.trim();
    if (name.isEmpty || name.length > 191 || pack.length > 191) {
      setState(() {
        _safeError = 'Enter a private product name of at most 191 characters.';
      });
      return;
    }
    Navigator.pop(context, (name, pack.isEmpty ? null : pack));
  }
}

class _CountSessionBar extends StatelessWidget {
  const _CountSessionBar({required this.controller});

  final InventoryController controller;

  @override
  Widget build(BuildContext context) {
    final active = controller.state.activeSession;
    if (active == null) {
      return FilledButton.icon(
        key: const Key('start-stock-count'),
        onPressed: controller.startCount,
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Start manual stock count'),
      );
    }
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            Text(
              '${active.confirmedLines.length} products counted',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            OutlinedButton(
              onPressed: controller.cancelCount,
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('finish-stock-count'),
              onPressed: active.lines.isEmpty ? null : controller.closeCount,
              child: const Text('Finish and apply'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({
    required this.item,
    required this.controller,
    required this.countSessionActive,
  });

  final InventoryItem item;
  final InventoryController controller;
  final bool countSessionActive;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => _editQuantity(context),
        title: Text(item.canonicalName),
        subtitle: Text(
          '${item.packSize} · ${item.brand.isEmpty ? item.category : item.brand}',
        ),
        trailing: Text(
          item.currentQuantity == null
              ? 'Not counted'
              : '${item.currentQuantity!.toStringAsFixed(_decimals(item.currentQuantity!))} ${item.unit}',
        ),
      ),
    );
  }

  Future<void> _editQuantity(BuildContext context) async {
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (_) => _InventoryQuantityDialog(
        item: item,
        countSessionActive: countSessionActive,
      ),
    );
    if (result == null) return;
    if (countSessionActive) {
      await controller.recordManualCount(
        item: item,
        observedQuantity: result.$1,
      );
    } else {
      await controller.adjustQuantity(
        item: item,
        locationId: 'primary',
        observedQuantity: result.$1,
        reason: result.$2,
      );
    }
  }

  int _decimals(double value) => value == value.roundToDouble() ? 0 : 2;
}

class _InventoryQuantityDialog extends StatefulWidget {
  const _InventoryQuantityDialog({
    required this.item,
    required this.countSessionActive,
  });

  final InventoryItem item;
  final bool countSessionActive;

  @override
  State<_InventoryQuantityDialog> createState() =>
      _InventoryQuantityDialogState();
}

class _InventoryQuantityDialogState extends State<_InventoryQuantityDialog> {
  late final TextEditingController _quantity;
  late final TextEditingController _reason;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(
      text: widget.item.currentQuantity?.toString() ?? '',
    );
    _reason = TextEditingController();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.countSessionActive
            ? 'Record count'
            : 'Adjust ${widget.item.canonicalName}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            key: const Key('inventory-quantity-input'),
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Observed quantity'),
          ),
          if (!widget.countSessionActive) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              key: const Key('inventory-adjustment-reason'),
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason for adjustment',
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    final parsed = double.tryParse(_quantity.text.trim());
    final explanation = _reason.text.trim();
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < 0 ||
        (!widget.countSessionActive && explanation.isEmpty)) {
      return;
    }
    Navigator.pop(context, (parsed, explanation));
  }
}
