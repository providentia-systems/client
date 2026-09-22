import 'package:flutter/material.dart';
import 'package:providentia/core/presentation/place_management_dialog.dart';
import 'package:providentia/features/inventory/application/home_location_repository.dart';
import 'package:providentia/features/inventory/application/stock_photo_count_controller.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_category_field.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/inventory/presentation/inventory_metadata_dialogs.dart';
import 'package:providentia/features/inventory/presentation/stock_photo_count_panel.dart';

class InventoryWorkspace extends StatefulWidget {
  const InventoryWorkspace({
    required this.controller,
    this.stockPhotoController,
    this.contributionPageBuilder,
    this.stockPhotoAcquisition,
    super.key,
  });

  final WidgetBuilder? contributionPageBuilder;
  final InventoryController controller;
  final StockPhotoCountController? stockPhotoController;
  final StockPhotoAcquisitionActions? stockPhotoAcquisition;

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
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        'Stock',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      if (widget.controller.canEditMetadata)
                        IconButton(
                          tooltip: 'Removed products',
                          icon: const Icon(Icons.inventory_2_outlined),
                          onPressed: () => showArchivedInventoryProducts(
                            context,
                            widget.controller,
                          ),
                        ),
                      if (widget.controller.canEditMetadata)
                        IconButton(
                          tooltip: 'Manage categories',
                          icon: const Icon(Icons.category_outlined),
                          onPressed: () => showInventoryCategories(
                            context,
                            widget.controller,
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
                  if (widget.controller.canEditLocations)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => PlaceManagementDialog(
                            title: 'Home locations',
                            singular: 'location',
                            detailLabel: 'Kind',
                            listenable: widget.controller,
                            detailOptions: HomeLocation.kinds,
                            maxNameLength: 120,
                            entries: () => widget.controller.locations
                                .map(
                                  (place) => PlaceDetails(
                                    id: place.id,
                                    name: place.name,
                                    detail: place.kind,
                                    archived: place.archived,
                                    revision: place.revision,
                                  ),
                                )
                                .toList(),
                            save: (place) => widget.controller.saveLocation(
                              id: place.id,
                              name: place.name,
                              kind: place.detail,
                              archived: place.archived,
                              expectedRevision: place.revision,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.shelves),
                        label: const Text('Manage locations'),
                      ),
                    ),
                  if (widget.contributionPageBuilder != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: widget.contributionPageBuilder!,
                          ),
                        ),
                        icon: const Icon(Icons.volunteer_activism_outlined),
                        label: const Text('Share a product for catalog review'),
                      ),
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
                  if (MediaQuery.textScalerOf(context).scale(14) > 20)
                    DropdownButtonFormField<InventoryView>(
                      initialValue: state.criteria.view,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: InventoryView.counted,
                          child: Text('Counted'),
                        ),
                        DropdownMenuItem(
                          value: InventoryView.itemMaster,
                          child: Text('Item master'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) widget.controller.selectView(value);
                      },
                    )
                  else
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
                    isExpanded: true,
                    items: categories
                        .map(
                          (category) => DropdownMenuItem<String>(
                            value: category,
                            child: Text(
                              category,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (category) => widget.controller.selectCategory(
                      category == 'All' ? null : category,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CountSessionBar(controller: widget.controller),
                  if (state.activeSession != null &&
                      widget.stockPhotoController != null) ...<Widget>[
                    const SizedBox(height: 12),
                    StockPhotoCountPanel(
                      controller: widget.stockPhotoController!,
                      acquisition: widget.stockPhotoAcquisition,
                    ),
                  ],
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
    final draft = await showDialog<PrivateHomeProductDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PrivateHomeProductDialog(controller: widget.controller),
    );
    if (draft == null || !mounted) return;
    await widget.controller.createPrivateProduct(
      privateName: draft.privateName,
      originalPackText: draft.originalPackText,
      homeCategoryId: draft.homeCategoryId,
      globalCategoryId: draft.globalCategoryId,
      unit: draft.unit,
    );
  }
}

class _PrivateHomeProductDialog extends StatefulWidget {
  const _PrivateHomeProductDialog({required this.controller});
  final InventoryController controller;
  @override
  State<_PrivateHomeProductDialog> createState() =>
      _PrivateHomeProductDialogState();
}

class _PrivateHomeProductDialogState extends State<_PrivateHomeProductDialog> {
  final _name = TextEditingController();
  final _pack = TextEditingController();
  String? _safeError;
  String? _categoryId;
  String? _globalCategoryId;
  String _unit = 'units';

  @override
  void dispose() {
    _name.dispose();
    _pack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Add private product'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'This product stays private to your home, even when you select a global category.',
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('inventory-private-product-name'),
              controller: _name,
              maxLength: 191,
              decoration: const InputDecoration(labelText: 'Private name'),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('inventory-private-product-pack'),
              controller: _pack,
              maxLength: 191,
              decoration: const InputDecoration(
                labelText: 'Original pack text (optional)',
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              key: const Key('inventory-private-product-unit'),
              initialValue: _unit,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Stock unit'),
              items: [
                for (final unit in householdStockUnits)
                  DropdownMenuItem(value: unit, child: Text(unit)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _unit = value);
              },
            ),
            const SizedBox(height: 20),
            InventoryCategoryField(
              localCategories: widget.controller.homeCategories,
              globalCategories: widget.controller.publishedCategories,
              localId: _categoryId,
              globalId: _globalCategoryId,
              onChanged: (local, global) => setState(() {
                _categoryId = local;
                _globalCategoryId = global;
              }),
            ),
            if (_safeError != null) ...[
              const SizedBox(height: 12),
              Text(
                _safeError!,
                key: const Key('inventory-private-product-validation'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
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
    ),
  );

  void _save() {
    try {
      final pack = _pack.text.trim();
      final draft = PrivateHomeProductDraft(
        homeId: widget.controller.homeId,
        privateName: _name.text.trim(),
        originalPackText: pack.isEmpty ? null : pack,
        homeCategoryId: _categoryId,
        globalCategoryId: _globalCategoryId,
        unit: _unit,
      );
      Navigator.pop(context, draft);
    } on ArgumentError {
      setState(
        () => _safeError =
            'Enter a private product name of at most 191 characters.',
      );
    }
  }
}

class _CountSessionBar extends StatelessWidget {
  const _CountSessionBar({required this.controller});

  final InventoryController controller;

  Future<void> _startCount(BuildContext context) async {
    final locations = controller.locations
        .where((place) => !place.archived)
        .toList();
    if (locations.isEmpty) {
      await controller.startCount();
      return;
    }
    final locationId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Count location'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'primary'),
            child: const Text('No location label'),
          ),
          for (final place in locations)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, place.id),
              child: Text(place.name),
            ),
        ],
      ),
    );
    if (locationId != null) await controller.startCount(locationId: locationId);
  }

  @override
  Widget build(BuildContext context) {
    final active = controller.state.activeSession;
    if (active == null) {
      return FilledButton.icon(
        key: const Key('start-stock-count'),
        onPressed: () => _startCount(context),
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
    // Legacy/local projections with an observed balance predate the explicit
    // isHomeProduct flag, but a counted balance is necessarily home-scoped.
    final belongsToHome = item.isHomeProduct || item.isCounted;
    return Card(
      child: InkWell(
        onTap: belongsToHome ? () => _editQuantity(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.canonicalName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (belongsToHome && controller.canEditMetadata)
                    IconButton(
                      tooltip: 'Edit product',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () =>
                          showInventoryProductEditor(context, controller, item),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_metadata),
              const SizedBox(height: 8),
              if (belongsToHome)
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.currentQuantity == null
                          ? 'Not counted'
                          : '${item.currentQuantity!.toStringAsFixed(_decimals(item.currentQuantity!))} ${item.unit}',
                    ),
                    if (countSessionActive &&
                        controller.state.activeSession!.lines.any(
                          (line) => line.itemId == item.id,
                        ))
                      IconButton(
                        tooltip: 'Remove from this count',
                        icon: const Icon(Icons.undo),
                        onPressed: () => _removeCount(context),
                      ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: Key('inventory-add-catalog-${item.packId ?? item.id}'),
                    onPressed:
                        controller.canAddCatalogProduct &&
                            !controller.state.productCreationBusy
                        ? () => controller.addCatalogProduct(item)
                        : null,
                    child: const Text('Add to home'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _metadata => <String>[
    item.packSize,
    if (item.hasUnresolvedCatalogPack) 'Catalog pack not selected',
    if (item.brand.isNotEmpty) item.brand,
    item.category,
    if (item.aliases.isNotEmpty) 'Aliases: ${item.aliases.join(', ')}',
  ].join(' · ');

  Future<void> _removeCount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from this count?'),
        content: Text(
          '${item.canonicalName} will be left out when this count is applied. Existing stock is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.removeCountForItem(item);
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
  final _explanation = TextEditingController();
  String _reason = 'Stock count correction';
  String? _error;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(
      text: widget.item.currentQuantity?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _quantity.dispose();
    _explanation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.countSessionActive
          ? 'Record count'
          : 'Adjust ${widget.item.canonicalName}',
    ),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('inventory-quantity-input'),
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Observed quantity',
              suffixText: widget.item.unit,
            ),
          ),
          if (!widget.countSessionActive) ...<Widget>[
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              key: const Key('inventory-adjustment-reason'),
              initialValue: _reason,
              isExpanded: true,
              menuMaxHeight: 360,
              decoration: const InputDecoration(
                labelText: 'Reason for adjustment',
              ),
              items: [
                for (final reason in const [
                  'Stock count correction',
                  'Stock received',
                  'Used or consumed',
                  'Spoiled or expired',
                  'Damaged or lost',
                  'Given away',
                  'Other',
                ])
                  DropdownMenuItem(
                    value: reason,
                    child: Text(reason, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _reason = value;
                    _error = null;
                  });
                }
              },
            ),
            if (_reason == 'Other') ...[
              const SizedBox(height: 20),
              TextField(
                key: const Key('inventory-adjustment-explanation'),
                controller: _explanation,
                maxLength: 191,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Explanation for Other',
                ),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('inventory-adjustment-validation'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  void _save() {
    final parsed = double.tryParse(_quantity.text.trim());
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      setState(() => _error = 'Enter a finite quantity of zero or more.');
      return;
    }
    final explanation = _explanation.text.trim();
    if (!widget.countSessionActive &&
        _reason == 'Other' &&
        (explanation.isEmpty || explanation.length > 191)) {
      setState(() => _error = 'Explain Other in 1 to 191 characters.');
      return;
    }
    Navigator.pop(context, (
      parsed,
      widget.countSessionActive
          ? ''
          : _reason == 'Other'
          ? explanation
          : _reason,
    ));
  }
}
