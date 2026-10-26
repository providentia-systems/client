import 'package:flutter/material.dart';
import 'package:providentia/core/presentation/place_management_dialog.dart';
import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/inventory/application/home_location_repository.dart';
import 'package:providentia/features/inventory/application/stock_photo_count_controller.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/count_evidence_dialog.dart';
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
                  if (!state.loading &&
                      state.safeError == null &&
                      widget.controller.visibleItems.isEmpty)
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

  Future<void> _showAddPrivateProduct() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PrivateHomeProductDialog(controller: widget.controller),
  );
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
  final _quantity = TextEditingController();
  final _clientProductId = UuidV4Generator().call();
  DateTime? _observedAt;
  bool _confirmedCount = false;
  String? _safeError;
  String? _categoryId;
  String? _globalCategoryId;
  String _unit = 'units';

  @override
  void dispose() {
    _name.dispose();
    _pack.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final busy = widget.controller.state.productCreationBusy;
      return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: const Text('Add private product'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This product stays private to your home, even when you select a global category.',
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('inventory-private-product-name'),
                  controller: _name,
                  enabled: !busy,
                  maxLength: 191,
                  decoration: const InputDecoration(labelText: 'Private name'),
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const Key('inventory-private-product-pack'),
                  controller: _pack,
                  enabled: !busy,
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
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => _unit = value);
                        },
                ),
                const SizedBox(height: 20),
                InventoryCategoryField(
                  localCategories: widget.controller.homeCategories,
                  globalCategories: widget.controller.publishedCategories,
                  localId: _categoryId,
                  globalId: _globalCategoryId,
                  enabled: !busy,
                  onChanged: (local, global) => setState(() {
                    _categoryId = local;
                    _globalCategoryId = global;
                  }),
                ),
                const SizedBox(height: 20),
                _OpeningCountFields(
                  quantity: _quantity,
                  unit: _unit,
                  confirmed: _confirmedCount,
                  enabled: !busy,
                  onConfirmed: (value) =>
                      setState(() => _confirmedCount = value),
                ),
                if (_safeError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _safeError!,
                    key: const Key('inventory-private-product-validation'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('inventory-save-private-product'),
              onPressed: busy ? null : _save,
              child: Text(busy ? 'Saving…' : 'Save locally'),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _save() async {
    try {
      final quantity = _openingQuantity(_quantity.text, _confirmedCount);
      if (quantity != null) _observedAt ??= DateTime.now().toUtc();
      final saved = await widget.controller.createPrivateProduct(
        privateName: _name.text.trim(),
        originalPackText: _pack.text.trim(),
        homeCategoryId: _categoryId,
        globalCategoryId: _globalCategoryId,
        unit: _unit,
        clientProductId: _clientProductId,
        openingQuantity: quantity,
        openingObservedAt: _observedAt,
        openingCountConfirmed: _confirmedCount,
      );
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
      } else {
        setState(
          () => _safeError =
              widget.controller.state.productCreationError ??
              'The product and opening count could not be saved. Your entry is retained.',
        );
      }
    } on ArgumentError catch (error) {
      setState(
        () => _safeError = error.message is String
            ? error.message as String
            : 'Check the product and opening quantity.',
      );
    }
  }
}

class _CatalogHomeProductDialog extends StatefulWidget {
  const _CatalogHomeProductDialog({
    required this.controller,
    required this.item,
  });
  final InventoryController controller;
  final InventoryItem item;
  @override
  State<_CatalogHomeProductDialog> createState() =>
      _CatalogHomeProductDialogState();
}

class _CatalogHomeProductDialogState extends State<_CatalogHomeProductDialog> {
  final _quantity = TextEditingController();
  final _clientProductId = UuidV4Generator().call();
  DateTime? _observedAt;
  bool _confirmedCount = false;
  String? _error;
  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final busy = widget.controller.state.productCreationBusy;
      return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: Text('Add ${widget.item.canonicalName}'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${widget.item.packSize} · Stock unit: units'),
                const SizedBox(height: 20),
                _OpeningCountFields(
                  quantity: _quantity,
                  unit: 'units',
                  confirmed: _confirmedCount,
                  enabled: !busy,
                  onConfirmed: (value) =>
                      setState(() => _confirmedCount = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('inventory-catalog-product-validation'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('inventory-save-catalog-product'),
              onPressed: busy ? null : _save,
              child: Text(busy ? 'Saving…' : 'Save locally'),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _save() async {
    try {
      final quantity = _openingQuantity(_quantity.text, _confirmedCount);
      if (quantity != null) _observedAt ??= DateTime.now().toUtc();
      final saved = await widget.controller.addCatalogProduct(
        widget.item,
        clientProductId: _clientProductId,
        openingQuantity: quantity,
        openingObservedAt: _observedAt,
        openingCountConfirmed: _confirmedCount,
      );
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
      } else {
        setState(
          () => _error =
              widget.controller.state.productCreationError ??
              'The product and opening count could not be saved. Your entry is retained.',
        );
      }
    } on ArgumentError catch (error) {
      setState(
        () => _error = error.message is String
            ? error.message as String
            : 'Check the opening quantity.',
      );
    }
  }
}

class _OpeningCountFields extends StatelessWidget {
  const _OpeningCountFields({
    required this.quantity,
    required this.unit,
    required this.confirmed,
    required this.enabled,
    required this.onConfirmed,
  });
  final TextEditingController quantity;
  final String unit;
  final bool confirmed;
  final bool enabled;
  final ValueChanged<bool> onConfirmed;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const Key('inventory-opening-quantity'),
        controller: quantity,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Opening quantity observed now (optional)',
          suffixText: unit,
          helperText:
              'Leave blank to add without a count. Explicit zero records an observed empty stock.',
          helperMaxLines: 4,
        ),
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        key: const Key('inventory-opening-count-confirmed'),
        contentPadding: EdgeInsets.zero,
        value: confirmed,
        onChanged: enabled ? (value) => onConfirmed(value ?? false) : null,
        title: const Text('I observed this product’s quantity now.'),
        subtitle: const Text(
          'This records one product as partial count evidence. Other products are omitted; this observation does not certify complete home stock.',
        ),
      ),
    ],
  );
}

double? _openingQuantity(String text, bool confirmed) {
  if (text.trim().isEmpty) return null;
  final quantity = double.tryParse(text.trim());
  if (quantity == null || !quantity.isFinite || quantity < 0) {
    throw ArgumentError(
      'Enter a finite opening quantity of zero or more, or leave it blank.',
    );
  }
  if (!confirmed) {
    throw ArgumentError(
      'Confirm that you observed this product’s quantity now, or leave the opening quantity blank.',
    );
  }
  return quantity;
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
    final history = controller.countHistory.where(
      (session) => session.status != CountSessionStatus.open,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active == null)
          FilledButton.icon(
            key: const Key('start-stock-count'),
            onPressed: () => _startCount(context),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Start manual stock count'),
          )
        else
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${active.confirmedLines.length} products counted'),
                  Text(
                    active.serverAccepted
                        ? 'Server accepted'
                        : 'Pending server acceptance',
                  ),
                  Text(
                    active.locationId == 'primary'
                        ? 'Whole-home scope'
                        : 'Selected-location scope',
                  ),
                  Text(
                    'Evidence: ${active.reliability ?? 'unassessed'} · '
                    '${active.scopeComplete == true ? 'Complete scope declared' : 'Scope completeness not confirmed'}',
                  ),
                  const Text(
                    'Review the actual observation time and evidence when finishing. '
                    'Unlisted products stay unchanged; observations do not overwrite stock locally.',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: controller.cancelCount,
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        key: const Key('finish-stock-count'),
                        onPressed: active.lines.isEmpty
                            ? null
                            : () => showCountEvidenceDialog(
                                context: context,
                                controller: controller,
                                session: active,
                              ),
                        child: const Text('Review and finish count'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (controller.countNotice != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(controller.countNotice!),
          ),
        if (controller.countError != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(controller.countError!),
          ),
        if (history.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Count history and evidence'),
          ),
          for (final session in history)
            Card(
              child: ListTile(
                title: Text(
                  '${session.status == CountSessionStatus.closed ? 'Finished count' : 'Cancelled count'} · '
                  '${session.confirmedLines.length} products',
                ),
                subtitle: Text(
                  '${session.serverAccepted ? 'Server accepted revision ${session.revision}' : 'Pending server acceptance'}'
                  '${session.reviewPending ? ' · Audited review pending' : ''} · '
                  '${session.reliability ?? 'unassessed'} · '
                  '${session.scopeComplete == true ? 'Complete scope' : 'Partial or unassessed scope'}\n'
                  '${session.observedAt == null ? 'Observation time unavailable; evidence remains unassessed' : 'Observed ${session.observedAt!.toUtc().toIso8601String()}'}'
                  '${session.observedTimezone == null ? '' : ' · ${session.observedTimezone}'}',
                ),
                trailing:
                    controller.canReviewCounts &&
                        session.serverAccepted &&
                        !session.reviewPending &&
                        session.status == CountSessionStatus.closed
                    ? TextButton(
                        onPressed: controller.countBusy
                            ? null
                            : () => showCountEvidenceDialog(
                                context: context,
                                controller: controller,
                                session: session,
                                acceptedReview: true,
                              ),
                        child: const Text('Review evidence'),
                      )
                    : null,
              ),
            ),
        ],
      ],
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
              if (belongsToHome && item.currentQuantity != null)
                Text(
                  item.currentQuantity! < 0
                      ? 'Signed ledger balance; this is not a physical count.'
                      : item.stockUncertain == true
                      ? 'Stock estimate has unresolved evidence.'
                      : item.stockUncertain == null
                      ? 'Stock evidence has not been assessed by this response.'
                      : 'Ledger balance; physical observation confidence is separate.',
                ),
              if (item.pendingOpeningQuantity != null)
                Text(
                  'Opening observation: ${item.pendingOpeningQuantity} ${item.unit} (partial); awaiting stock review/server readback.',
                ),
              if (item.pendingStockQuantity != null)
                Text(
                  'Pending chronology: ${item.pendingStockQuantity} ${item.unit} (not added again).',
                ),
              if (item.localPendingStockQuantity != null)
                Text(
                  'Unsynchronized purchase effect: ${item.localPendingStockQuantity} ${item.unit}. '
                  '${item.localStockPendingIsDeferred ? 'Current stock awaits authoritative count chronology; this effect is not added locally.' : 'Displayed stock includes a local estimate until server readback.'}',
                ),
              if (item.stockLimitations.isNotEmpty)
                Text('Limitations: ${item.stockLimitations.join(', ')}'),
              if (belongsToHome)
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.currentQuantity == null
                          ? item.pendingOpeningQuantity == null
                                ? 'Not counted'
                                : 'Stock balance awaiting review'
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
                        ? () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => _CatalogHomeProductDialog(
                              controller: controller,
                              item: item,
                            ),
                          )
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

  Future<void> _editQuantity(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _InventoryQuantityDialog(
      item: item,
      countSessionActive: countSessionActive,
      save: (quantity) async {
        if (countSessionActive) {
          await controller.recordManualCount(
            item: item,
            observedQuantity: quantity,
          );
        } else {
          await controller.adjustQuantity(
            item: item,
            locationId: 'primary',
            observedQuantity: quantity,
            reason: 'Stock count correction',
          );
        }
      },
    ),
  );

  int _decimals(double value) => value == value.roundToDouble() ? 0 : 2;
}

class _InventoryQuantityDialog extends StatefulWidget {
  const _InventoryQuantityDialog({
    required this.item,
    required this.countSessionActive,
    required this.save,
  });
  final InventoryItem item;
  final bool countSessionActive;
  final Future<void> Function(double) save;
  @override
  State<_InventoryQuantityDialog> createState() =>
      _InventoryQuantityDialogState();
}

class _InventoryQuantityDialogState extends State<_InventoryQuantityDialog> {
  late final TextEditingController _quantity;
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(
      text: widget.item.currentQuantity?.toString() ?? '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _quantity.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _quantity.text.length,
      );
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(
        widget.countSessionActive
            ? 'Record count: ${widget.item.canonicalName}'
            : 'Adjust ${widget.item.canonicalName}',
      ),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('${widget.item.packSize} · Stock unit: ${widget.item.unit}'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('inventory-quantity-input'),
              controller: _quantity,
              focusNode: _focus,
              autofocus: true,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Observed quantity',
                suffixText: widget.item.unit,
              ),
            ),
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
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    final parsed = double.tryParse(_quantity.text.trim());
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      setState(() => _error = 'Enter a finite quantity of zero or more.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(parsed);
      if (mounted) Navigator.pop(context);
    } on InventoryUnitChangeException catch (failure) {
      if (mounted) setState(() => _error = failure.safeMessage);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The quantity could not be saved. Your entry is retained. Refresh this home and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
