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
                  Text(
                    'Stock',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
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
    final quantity = TextEditingController(
      text: item.currentQuantity?.toString() ?? '',
    );
    final reason = TextEditingController();
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          countSessionActive ? 'Record count' : 'Adjust ${item.canonicalName}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('inventory-quantity-input'),
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Observed quantity'),
            ),
            if (!countSessionActive) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                key: const Key('inventory-adjustment-reason'),
                controller: reason,
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
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(quantity.text.trim());
              final explanation = reason.text.trim();
              if (parsed == null ||
                  !parsed.isFinite ||
                  parsed < 0 ||
                  (!countSessionActive && explanation.isEmpty)) {
                return;
              }
              Navigator.pop(context, (parsed, explanation));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    quantity.dispose();
    reason.dispose();
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
