import 'package:flutter/material.dart';
import 'package:providentia/core/domain/household_product_lookup.dart';
import 'package:providentia/core/presentation/place_management_dialog.dart';
import 'package:providentia/core/presentation/quantity_field.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/receipt_amounts.dart';
import 'package:providentia/features/purchasing/domain/receipt_spend.dart';
import 'package:providentia/features/purchasing/presentation/finished_receipt_line_editor.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/receipt_draft_editor.dart';
import 'package:providentia/features/purchasing/presentation/receipt_price_widgets.dart';
import 'package:providentia/features/purchasing/presentation/receipt_spend_card.dart';

class PurchasingWorkspace extends StatefulWidget {
  const PurchasingWorkspace({
    required this.controller,
    this.onImportReceipt,
    super.key,
  });

  final PurchasingController controller;
  final VoidCallback? onImportReceipt;

  @override
  State<PurchasingWorkspace> createState() => _PurchasingWorkspaceState();
}

class _PurchasingWorkspaceState extends State<PurchasingWorkspace> {
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
        return ListView(
          key: const Key('purchasing-workspace'),
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Purchases',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                if (widget.controller.canEditStores)
                  IconButton(
                    tooltip: 'Manage stores',
                    icon: const Icon(Icons.store_outlined),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => PlaceManagementDialog(
                        title: 'Stores',
                        singular: 'store',
                        detailLabel: 'Location (optional)',
                        listenable: widget.controller,
                        entries: () => widget.controller.stores
                            .map(
                              (place) => PlaceDetails(
                                id: place.id,
                                name: place.name,
                                detail: place.location,
                                archived: place.archived,
                                revision: place.revision,
                              ),
                            )
                            .toList(),
                        save: (place) => widget.controller.saveStore(
                          id: place.id,
                          name: place.name,
                          location: place.detail,
                          archived: place.archived,
                          expectedRevision: place.revision,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<PurchaseView>(
              segments: const <ButtonSegment<PurchaseView>>[
                ButtonSegment(
                  value: PurchaseView.recent,
                  label: Text('Recent receipts'),
                ),
                ButtonSegment(
                  value: PurchaseView.history,
                  label: Text('History'),
                ),
              ],
              selected: <PurchaseView>{state.view},
              onSelectionChanged: (selection) =>
                  widget.controller.selectView(selection.single),
            ),
            const SizedBox(height: 12),
            if (state.safeError != null) Text(state.safeError!),
            if (state.view == PurchaseView.recent) ...<Widget>[
              _PurchaseCapturePanel(
                key: ValueKey('purchase-home-${widget.controller.homeId}'),
                controller: widget.controller,
                onImportReceipt: widget.onImportReceipt,
              ),
              const SizedBox(height: 12),
              if (widget.controller.canSelectReceipts)
                ReceiptSpendCard(summary: widget.controller.receiptSpendSummary)
              else
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Entered-products subtotal'),
                    subtitle: Text(
                      '${widget.controller.recentGroups.length} receipt group'
                      '${widget.controller.recentGroups.length == 1 ? '' : 's'}',
                    ),
                    trailing: Text(
                      widget.controller.recentProductSubtotal == null
                          ? 'Incomplete prices or mixed currencies'
                          : _money(widget.controller.recentProductSubtotal!),
                    ),
                  ),
                ),
              for (final group in widget.controller.recentGroups)
                _PurchaseGroupCard(group: group),
            ] else
              for (final summary in widget.controller.monthlyHistory)
                ListTile(
                  title: Text(
                    '${summary.month.year}-${summary.month.month.toString().padLeft(2, '0')}',
                  ),
                  subtitle: Text('${summary.lineCount} purchase lines'),
                  trailing: Text(_quantity(summary.quantity)),
                ),
          ],
        );
      },
    );
  }
}

class _PurchaseCapturePanel extends StatefulWidget {
  const _PurchaseCapturePanel({
    required this.controller,
    this.onImportReceipt,
    super.key,
  });

  final PurchasingController controller;
  final VoidCallback? onImportReceipt;

  @override
  State<_PurchaseCapturePanel> createState() => _PurchaseCapturePanelState();
}

class _PurchaseCapturePanelState extends State<_PurchaseCapturePanel> {
  final _currency = TextEditingController(text: 'NAD');
  final _receiptTotal = TextEditingController();
  final _notes = TextEditingController();
  final _sourceReference = TextEditingController();
  final _description = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  int _quantityReset = 0;
  String? _entryProductLabel;
  String? _draftReceiptId;
  final _packText = TextEditingController();
  final _unitPrice = TextEditingController();
  final _lineTotal = TextEditingController();
  final Map<String, String> _selectedProducts = <String, String>{};
  final Map<String, String> _selectedReviewPacks = <String, String>{};
  final Map<String, bool> _reviewInStockUnits = <String, bool>{};
  bool _showDraftForm = false;
  String? _storeId;
  String? _entryProductId;
  String? _entryPackId;
  final _productFocus = FocusNode();
  final _productSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    _productSearch.addListener(_clearChangedProductSelection);
  }

  void _clearChangedProductSelection() {
    if (_entryProductId != null && _productSearch.text != _entryProductLabel) {
      setState(() {
        _entryProductId = null;
        _entryPackId = null;
        _entryProductLabel = null;
      });
    }
  }

  @override
  void dispose() {
    _productSearch.removeListener(_clearChangedProductSelection);
    _productFocus.dispose();
    _productSearch.dispose();
    _currency.dispose();
    _receiptTotal.dispose();
    _notes.dispose();
    _sourceReference.dispose();
    _description.dispose();
    _quantity.dispose();
    _packText.dispose();
    _unitPrice.dispose();
    _lineTotal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state;
    final capture = state.capture;
    if (_draftReceiptId != capture?.id) {
      _draftReceiptId = capture?.id;
      _entryProductId = null;
      _entryPackId = null;
      _entryProductLabel = null;
      _productSearch.clear();
      _description.clear();
      _packText.clear();
      _unitPrice.clear();
      _lineTotal.clear();
      _quantity.text = '1';
      _quantityReset++;
      _selectedProducts.clear();
      _selectedReviewPacks.clear();
      _reviewInStockUnits.clear();
    }
    if (!controller.captureEnabled) {
      return const Card(
        key: Key('purchase-capture-read-only'),
        child: ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Receipt capture is read-only'),
          subtitle: Text('Purchase write permission is required.'),
        ),
      );
    }
    return Card(
      key: const Key('purchase-capture-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Capture receipt',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (state.captureNotice != null &&
                state.captureNotice !=
                    controller.receiptSynchronizationNotice) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                state.captureNotice!,
                key: const Key('purchase-capture-notice'),
              ),
            ],
            if (controller.receiptSynchronizationNotice != null) ...<Widget>[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  controller.receiptSynchronizationNotice!,
                  key: const Key('receipt-synchronization-outcome'),
                ),
              ),
              if (controller.canReviewSynchronization)
                TextButton(
                  key: const Key('purchase-review-sync'),
                  onPressed: controller.reviewSynchronization,
                  child: const Text('Review synchronization'),
                ),
            ],
            if (state.captureError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                state.captureError!,
                key: const Key('purchase-capture-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('purchase-import-receipt'),
              onPressed: state.captureBusy ? null : widget.onImportReceipt,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import photo or PDF'),
            ),
            if (widget.onImportReceipt == null)
              const Text(
                'Receipt import requires household AI access. Review Account & access for availability.',
              ),
            if (controller.canSelectReceipts &&
                controller.receipts.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('purchase-receipt-selector-${capture?.id}'),
                initialValue: capture?.id,
                decoration: const InputDecoration(labelText: 'Open receipts'),
                isExpanded: true,
                items: [
                  for (final receipt in controller.receipts)
                    DropdownMenuItem(
                      value: receipt.id,
                      child: Text(
                        '${receipt.purchaseDate.toIso8601String().substring(0, 10)} · ${receipt.storeName ?? 'Unspecified store'} · ${receipt.lines.length} items${receipt.status == PurchaseReceiptStatus.committed ? ' · submitted' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: state.captureBusy
                    ? null
                    : (value) {
                        if (value != null) {
                          controller.selectReceipt(value);
                          setState(() => _showDraftForm = false);
                        }
                      },
              ),
              TextButton.icon(
                key: const Key('purchase-another-receipt'),
                onPressed: state.captureBusy
                    ? null
                    : () {
                        controller.startAnotherReceipt();
                        setState(() => _showDraftForm = true);
                      },
                icon: const Icon(Icons.add),
                label: const Text('Start another receipt'),
              ),
            ],
            if (capture == null)
              if (_showDraftForm)
                _draftForm(context)
              else
                FilledButton.icon(
                  key: const Key('purchase-start-receipt'),
                  onPressed: state.captureBusy
                      ? null
                      : () => setState(() => _showDraftForm = true),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Start receipt'),
                )
            else
              _captureEditor(context, capture),
          ],
        ),
      ),
    );
  }

  Widget _draftForm(BuildContext context) {
    final state = widget.controller.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: ValueKey(
            'receipt-store-${widget.controller.stores.map((store) => '${store.id}:${store.archived}').join(',')}',
          ),
          initialValue:
              widget.controller.stores.any(
                (store) => store.id == _storeId && !store.archived,
              )
              ? _storeId
              : '',
          decoration: const InputDecoration(labelText: 'Store'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Unspecified store')),
            for (final store in widget.controller.stores.where(
              (store) => !store.archived,
            ))
              DropdownMenuItem(
                value: store.id,
                child: Text(
                  store.location.isEmpty
                      ? store.name
                      : '${store.name} · ${store.location}',
                ),
              ),
          ],
          onChanged: state.captureBusy
              ? null
              : (value) =>
                    setState(() => _storeId = value == '' ? null : value),
        ),
        if (widget.controller.canEditStores)
          TextButton.icon(
            key: const Key('purchase-add-store'),
            onPressed: state.captureBusy ? null : _addStore,
            icon: const Icon(Icons.add),
            label: const Text('Add store'),
          ),
        TextField(
          key: const Key('purchase-receipt-currency'),
          controller: _currency,
          maxLength: 3,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Currency'),
        ),
        TextField(
          key: const Key('purchase-receipt-total'),
          controller: _receiptTotal,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Receipt total (optional)',
          ),
        ),
        TextField(
          key: const Key('purchase-receipt-notes'),
          controller: _notes,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: 'Private receipt notes (this home only)',
          ),
        ),
        TextField(
          key: const Key('purchase-receipt-reference'),
          controller: _sourceReference,
          decoration: const InputDecoration(
            labelText: 'Private source reference (optional)',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: state.captureBusy
                    ? null
                    : () => setState(() => _showDraftForm = false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const Key('purchase-create-draft'),
                onPressed: state.captureBusy ? null : _createDraft,
                child: const Text('Save draft'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _captureEditor(BuildContext context, PurchaseReceiptCapture capture) {
    final pending =
        capture.synchronizationState == PurchaseSynchronizationState.pending;
    if (capture.status == PurchaseReceiptStatus.committed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Receipt revision ${capture.revision}'),
          ReceiptAmountSummary(receipt: capture),
          const SizedBox(height: 4),
          Text(
            capture.commitConfirmed && pending
                ? 'Commit confirmed by the server; receipt details are refreshing.'
                : pending
                ? 'Commit queued locally; awaiting server confirmation.'
                : 'Commit synchronized.',
            key: const Key('purchase-commit-state'),
          ),
          if (widget.controller.canMaintainDraft)
            OutlinedButton.icon(
              key: const Key('purchase-edit-receipt'),
              onPressed: widget.controller.state.captureBusy
                  ? null
                  : () => _editDraft(capture),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit receipt details'),
            ),
          if (widget.controller.canCorrectFinishedReceipt)
            OutlinedButton.icon(
              key: const Key('purchase-add-omitted-line'),
              onPressed: widget.controller.state.captureBusy
                  ? null
                  : () => _completeFinishedLine(capture),
              icon: const Icon(Icons.add),
              label: const Text('Add omitted purchase'),
            )
          else if (widget.controller.canMaintainDraft)
            const Text(
              'Refresh receipt details from the supported backend to correct omitted or unresolved purchases. Pending stock confirmation must finish first.',
              key: Key('purchase-finished-correction-unavailable'),
            ),
          for (final line in capture.lines) ...[
            _lineReview(context, line),
            if (widget.controller.canMaintainDraft &&
                (line.stockApplied ||
                    (line.unresolved &&
                        widget.controller.canCorrectFinishedReceipt)))
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    key: Key('purchase-edit-line-${line.id}'),
                    onPressed: widget.controller.state.captureBusy
                        ? null
                        : () => _editDraft(capture, line),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit line'),
                  ),
                  TextButton.icon(
                    key: Key('purchase-remove-line-${line.id}'),
                    onPressed: widget.controller.state.captureBusy
                        ? null
                        : () => _removeLine(line),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Remove line'),
                  ),
                ],
              ),
          ],
          if (pending) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('purchase-retry-commit'),
              onPressed:
                  widget.controller.state.captureBusy ||
                      widget.controller.synchronizationBusy ||
                      !widget.controller.canRetrySynchronization
                  ? null
                  : widget.controller.retrySynchronization,
              child: Text(
                widget.controller.synchronizationBusy
                    ? 'Synchronizing…'
                    : 'Retry synchronization',
              ),
            ),
            if (!widget.controller.canRetrySynchronization)
              const Text(
                'Synchronization is unavailable in this view. Open Home to review the saved upload queue.',
              ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Draft revision ${capture.revision} · '
          '${pending ? 'awaiting authoritative confirmation' : 'synchronized'}',
          key: const Key('purchase-draft-state'),
        ),
        if (pending) ...<Widget>[
          const SizedBox(height: 4),
          const Text(
            'Line commands may already be accepted; the receipt stays pending '
            'until its parent revision is confirmed.',
            key: Key('purchase-authoritative-confirmation'),
          ),
        ],
        const SizedBox(height: 12),
        ReceiptAmountSummary(receipt: capture),
        if (widget.controller.canMaintainDraft)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('purchase-edit-receipt'),
                onPressed: widget.controller.state.captureBusy
                    ? null
                    : () => _editDraft(capture),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit receipt'),
              ),
              TextButton(
                key: const Key('purchase-cancel-draft'),
                onPressed: widget.controller.state.captureBusy
                    ? null
                    : () => _cancelDraft(capture),
                child: const Text('Cancel draft'),
              ),
            ],
          ),
        if (widget.controller.canQuickEntry)
          _quickEntry(context)
        else ...[
          TextField(
            key: const Key('purchase-line-description'),
            controller: _description,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Receipt line text'),
          ),
          TextField(
            key: const Key('purchase-line-pack'),
            controller: _packText,
            maxLength: 191,
            decoration: const InputDecoration(
              labelText: 'Pack text (optional)',
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: QuantityField(
                  key: const Key('purchase-line-quantity'),
                  controller: _quantity,
                  resetToken: _quantityReset,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('purchase-line-total'),
                  controller: _lineTotal,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Line total'),
                ),
              ),
            ],
          ),
          TextField(
            key: const Key('purchase-line-unit-price'),
            controller: _unitPrice,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Unit price (optional)',
            ),
          ),
          ReceiptLinePricePreview(
            quantity: _quantity,
            unitPrice: _unitPrice,
            lineTotal: _lineTotal,
            currency: capture.currency,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('purchase-add-line'),
            onPressed: widget.controller.state.captureBusy ? null : _addLine,
            icon: const Icon(Icons.add),
            label: const Text('Add receipt line'),
          ),
        ],
        const SizedBox(height: 8),
        for (final line in capture.lines) ...[
          _lineReview(context, line),
          if (widget.controller.canMaintainDraft)
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: Key('purchase-edit-line-${line.id}'),
                  onPressed: widget.controller.state.captureBusy
                      ? null
                      : () => _editDraft(capture, line),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit line'),
                ),
                TextButton.icon(
                  key: Key('purchase-remove-line-${line.id}'),
                  onPressed: widget.controller.state.captureBusy
                      ? null
                      : () => _removeLine(line),
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Remove line'),
                ),
              ],
            ),
        ],
        if (capture.lines.length > 4) ReceiptAmountSummary(receipt: capture),
        if (!capture.reviewComplete)
          const Text(
            'Every line must be approved or intentionally left unresolved before commit.',
            key: Key('purchase-review-required'),
          ),
        FilledButton(
          key: const Key('purchase-commit-receipt'),
          onPressed:
              widget.controller.state.captureBusy || !capture.reviewComplete
              ? null
              : widget.controller.commitDraft,
          child: Text(
            widget.controller.canQuickEntry
                ? 'Finish receipt'
                : 'Queue receipt commit',
          ),
        ),
      ],
    );
  }

  Widget _quickEntry(BuildContext context) {
    final candidates = widget.controller.state.matchCandidates;
    final products = candidates
        .where((candidate) => candidate.homeProductId != null)
        .toList();
    PurchaseMatchCandidate? product;
    for (final candidate in products) {
      if (candidate.homeProductId == _entryProductId) product = candidate;
    }
    final packs = product == null || product.productId == null
        ? <PurchaseMatchCandidate>[]
        : candidates
              .where(
                (candidate) =>
                    candidate.productId == product!.productId &&
                    candidate.packId != null &&
                    candidate.packStatus == 'published',
              )
              .toList();
    if (!packs.any((candidate) => candidate.packId == _entryPackId)) {
      _entryPackId = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text(
          'Add purchased product',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        DropdownMenu<String>(
          key: const Key('purchase-product-search'),
          focusNode: _productFocus,
          controller: _productSearch,
          initialSelection: _entryProductId,
          expandedInsets: EdgeInsets.zero,
          enableFilter: true,
          requestFocusOnTap: true,
          filterCallback: (entries, query) =>
              const HouseholdProductLookup().rank<DropdownMenuEntry<String>>(
                query: query,
                products: entries,
                describe: (entry) {
                  final candidate = products.firstWhere(
                    (candidate) => candidate.homeProductId == entry.value,
                  );
                  return ProductLookupText(
                    name: candidate.name,
                    brand: candidate.brand,
                    pack: candidate.packSize,
                    category: candidate.category,
                    aliases: candidate.aliases,
                  );
                },
              ),
          label: const Text('Find product'),
          dropdownMenuEntries: [
            for (final candidate in products)
              DropdownMenuEntry(
                value: candidate.homeProductId!,
                label:
                    '${candidate.name}${candidate.brand.isEmpty ? '' : ' · ${candidate.brand}'} · ${candidate.packSize}',
              ),
          ],
          onSelected: widget.controller.state.captureBusy
              ? null
              : (value) => setState(() {
                  _entryProductId = value;
                  _entryPackId = null;
                  _entryProductLabel = _productSearch.text;
                }),
        ),
        if (products.isEmpty)
          const Text(
            'Add a product in Stock first. Imported receipt lines can also create a private product during review.',
          ),
        if (product != null) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('purchase-pack-$_entryProductId-$_entryPackId'),
            initialValue: _entryPackId ?? '',
            decoration: const InputDecoration(
              labelText: 'Purchased pack or measurement',
            ),
            isExpanded: true,
            items: [
              DropdownMenuItem(
                value: '',
                child: Text('Quantity in ${product.stockUnit}'),
              ),
              for (final pack in packs)
                DropdownMenuItem(
                  value: pack.packId!,
                  child: Text(pack.packSize),
                ),
            ],
            onChanged: widget.controller.state.captureBusy
                ? null
                : (value) =>
                      setState(() => _entryPackId = value == '' ? null : value),
          ),
          Text(
            'Stock is tracked in ${product.stockUnit}.${product.stockUnit == 'units' ? ' Selected packs are converted to the home product base pack when available.' : ''}',
          ),
        ],
        Row(
          children: [
            Expanded(
              child: QuantityField(
                key: const Key('purchase-line-quantity'),
                controller: _quantity,
                resetToken: _quantityReset,
                decoration: InputDecoration(
                  labelText: _entryPackId == null
                      ? 'Purchased quantity (${product?.stockUnit ?? 'stock units'})'
                      : 'Number of packs',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('purchase-line-total'),
                controller: _lineTotal,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Line total'),
              ),
            ),
          ],
        ),
        TextField(
          key: const Key('purchase-line-unit-price'),
          controller: _unitPrice,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Price per purchased unit (optional)',
          ),
        ),
        if (_entryPackId == null)
          TextField(
            key: const Key('purchase-line-pack'),
            controller: _packText,
            maxLength: 191,
            decoration: const InputDecoration(
              labelText: 'Packaging description (optional)',
            ),
          ),
        ReceiptLinePricePreview(
          quantity: _quantity,
          unitPrice: _unitPrice,
          lineTotal: _lineTotal,
          currency: widget.controller.state.capture!.currency,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('purchase-add-line'),
          onPressed: widget.controller.state.captureBusy || product == null
              ? null
              : _addPurchasedLine,
          icon: const Icon(Icons.add),
          label: const Text('Add purchase'),
        ),
        const Text(
          'Add saves this purchase and increases stock immediately. Items remain grouped under this receipt.',
        ),
      ],
    );
  }

  Future<void> _addPurchasedLine() async {
    final capture = widget.controller.state.capture;
    if (capture == null || _entryProductId == null) return;
    final candidates = widget.controller.state.matchCandidates;
    final product = candidates.firstWhere(
      (candidate) => candidate.homeProductId == _entryProductId,
    );
    final unitPrice = _parseMoney(_unitPrice.text, capture.currency);
    final lineTotal = _parseMoney(_lineTotal.text, capture.currency);
    if ((_unitPrice.text.trim().isNotEmpty && unitPrice == null) ||
        (_lineTotal.text.trim().isNotEmpty && lineTotal == null) ||
        (unitPrice == null && lineTotal == null)) {
      widget.controller.reportCaptureValidation(
        'Add a valid price or line total with at most two decimals.',
      );
      return;
    }
    String packText = _packText.text;
    for (final candidate in candidates) {
      if (_entryPackId != null && candidate.packId == _entryPackId) {
        packText = candidate.packSize;
      }
    }
    final saved = await widget.controller.addPurchasedLine(
      homeProductId: product.homeProductId!,
      packId: _entryPackId,
      rawDescription: product.name,
      quantityText: _quantity.text.trim(),
      originalPackText: packText,
      unitPrice: unitPrice,
      lineTotal: lineTotal,
    );
    if (saved && mounted && widget.controller.state.capture?.id == capture.id) {
      _quantity.text = '1';
      _quantityReset++;
      _entryProductId = null;
      _entryProductLabel = null;
      _productSearch.clear();
      _unitPrice.clear();
      _lineTotal.clear();
      _packText.clear();
      setState(() {
        _entryProductId = null;
        _entryPackId = null;
      });
      _productFocus.requestFocus();
    }
  }

  Future<void> _addStore() async {
    final name = TextEditingController();
    final location = TextEditingController();
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add store'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('purchase-new-store-name'),
                controller: name,
                maxLength: 191,
                enabled: !saving,
                decoration: const InputDecoration(labelText: 'Store name'),
              ),
              TextField(
                controller: location,
                maxLength: 191,
                enabled: !saving,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                ),
              ),
              if (error != null) Text(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('purchase-new-store-save'),
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        setDialogState(() => error = 'Enter a store name.');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      final saved = await widget.controller.saveStore(
                        name: name.text.trim(),
                        location: location.text.trim(),
                        archived: false,
                      );
                      if (!dialogContext.mounted) return;
                      if (saved) {
                        Navigator.pop(dialogContext);
                      } else {
                        setDialogState(() {
                          saving = false;
                          error = 'The store could not be saved. Try again.';
                        });
                      }
                    },
              child: const Text('Save store'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    location.dispose();
  }

  Future<void> _editDraft(
    PurchaseReceiptCapture receipt, [
    PurchaseReceiptLineCapture? line,
  ]) => showDialog<void>(
    context: context,
    builder: (_) => ReceiptDraftEditor(
      controller: widget.controller,
      receipt: receipt,
      line: line,
    ),
  );

  Future<bool> _confirmRemoval(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep draft'),
            ),
            FilledButton(
              key: const Key('purchase-confirm-removal'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _cancelDraft(PurchaseReceiptCapture receipt) async {
    if (await _confirmRemoval(
          'Cancel draft?',
          'This receipt will be cancelled. Purchases already added from this receipt will be reversed in stock; history is kept.',
        ) &&
        mounted) {
      await widget.controller.cancelDraft(receipt);
    }
  }

  Future<void> _completeFinishedLine(
    PurchaseReceiptCapture receipt, [
    PurchaseReceiptLineCapture? line,
  ]) => showDialog<void>(
    context: context,
    builder: (context) => FinishedReceiptLineEditor(
      controller: widget.controller,
      receipt: receipt,
      line: line,
    ),
  );

  Future<void> _removeLine(PurchaseReceiptLineCapture line) async {
    if (await _confirmRemoval(
          'Remove line?',
          line.stockApplied
              ? 'This purchase will be removed and its quantity reversed in stock. History is kept.'
              : 'This line will be excluded from receipt approval and commit.',
        ) &&
        mounted) {
      await widget.controller.removeLine(line);
    }
  }

  Widget _lineReview(BuildContext context, PurchaseReceiptLineCapture line) {
    final capture = widget.controller.state.capture!;
    if (capture.status == PurchaseReceiptStatus.committed && !line.approved) {
      return Card.outlined(
        key: Key('purchase-line-${line.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(line.rawDescription),
              ReceiptLinePriceDetails(line: line, currency: capture.currency),
              Text(
                '${line.unresolved ? 'Intentionally unresolved; no stock applied' : 'Stock confirmation is uncertain; refresh receipt details before correcting'} · ${line.synchronizationState == PurchaseSynchronizationState.pending ? 'synchronization pending' : 'synchronized'}',
              ),
              if (line.unresolved &&
                  widget.controller.canCorrectFinishedReceipt)
                TextButton.icon(
                  key: Key('purchase-resolve-line-${line.id}'),
                  onPressed: widget.controller.state.captureBusy
                      ? null
                      : () => _completeFinishedLine(capture, line),
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Resolve purchase'),
                ),
            ],
          ),
        ),
      );
    }
    if (line.approved) {
      PurchaseMatchCandidate? match;
      for (final candidate in widget.controller.state.matchCandidates) {
        if (candidate.id == line.homeProductId) {
          match = candidate;
          break;
        }
      }
      return ListTile(
        key: Key('purchase-line-${line.id}'),
        leading: const Icon(Icons.check_circle_outline),
        title: Text(line.rawDescription),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReceiptLinePriceDetails(
              line: line,
              currency: widget.controller.state.capture!.currency,
            ),
            Text(
              line.stockApplied
                  ? 'Stock added: ${line.stockQuantity} ${line.stockUnit ?? match?.stockUnit ?? 'stock units'} · ${line.synchronizationState == PurchaseSynchronizationState.pending ? 'synchronization pending' : 'synchronized'}'
                  : capture.status == PurchaseReceiptStatus.committed
                  ? 'Stock confirmation is uncertain. Refresh receipt details before correcting this purchase.'
                  : 'Approved: ${match?.name ?? 'Private home product'} · revision ${line.revision}${line.stockQuantityPerPack == null ? '' : ' · ${widget.controller.approvedStockPreview(line)}'}',
            ),
          ],
        ),
        trailing: line.stockApplied
            ? const Icon(Icons.check_circle_outline)
            : capture.status == PurchaseReceiptStatus.committed
            ? const Icon(Icons.sync_problem_outlined)
            : TextButton(
                key: Key('purchase-leave-unresolved-${line.id}'),
                onPressed: widget.controller.state.captureBusy
                    ? null
                    : () => widget.controller.leaveLineUnresolved(line.id),
                child: const Text('Leave unresolved'),
              ),
      );
    }
    final ranked = widget.controller.rankedCandidatesFor(line);
    final candidates = ranked.map((entry) => entry.candidate).toList();
    RankedPurchaseMatchCandidate? selected;
    final selectedId = _selectedProducts[line.id];
    for (final entry in ranked) {
      if (entry.candidate.id == selectedId) {
        selected = entry;
        break;
      }
    }
    return Card.outlined(
      key: Key('purchase-line-${line.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(line.rawDescription),
            ReceiptLinePriceDetails(
              line: line,
              currency: widget.controller.state.capture!.currency,
            ),
            if (line.unresolved)
              Text(
                'Intentionally unresolved · revision ${line.revision}. You may still approve it later.',
                key: Key('purchase-unresolved-state-${line.id}'),
              ),
            if (ranked.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Top suggestion: ${_matchBasisLabel(ranked.first.basis)}',
                key: Key('purchase-match-basis-top-${line.id}'),
              ),
            ],
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: Key('purchase-line-match-${line.id}'),
              initialValue: selected?.candidate.id,
              items: candidates
                  .map(
                    (candidate) => DropdownMenuItem<String>(
                      value: candidate.id,
                      child: Text('${candidate.name} · ${candidate.packSize}'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() {
                _selectedReviewPacks.remove(line.id);
                _reviewInStockUnits.remove(line.id);
                if (value == null) {
                  _selectedProducts.remove(line.id);
                } else {
                  _selectedProducts[line.id] = value;
                }
              }),
              decoration: const InputDecoration(labelText: 'Match product'),
            ),
            if (selected != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Why this match: ${_matchBasisLabel(selected.basis)} · '
                '${selected.candidate.brand.isEmpty ? 'No brand listed' : selected.candidate.brand} · '
                '${selected.candidate.category}',
                key: Key('purchase-match-basis-${line.id}'),
              ),
            ],
            if (widget.controller.canReviewPacks && selected != null) ...[
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'purchase-review-measurement-${line.id}-${selected.candidate.id}',
                ),
                initialValue:
                    _reviewInStockUnits[line.id] == true ||
                        selected.candidate.packStatus != 'published'
                    ? ''
                    : _selectedReviewPacks[line.id] ??
                          selected.candidate.packId ??
                          '',
                decoration: const InputDecoration(
                  labelText: 'Quantity refers to',
                ),
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(
                      'Stock measurement (${widget.controller.reviewTargetForCandidate(selected.candidate).stockUnit})',
                    ),
                  ),
                  for (final pack
                      in widget.controller.state.matchCandidates.where(
                        (candidate) =>
                            candidate.productId != null &&
                            candidate.productId ==
                                selected!.candidate.productId &&
                            candidate.packId != null &&
                            candidate.packStatus == 'published',
                      ))
                    DropdownMenuItem(
                      value: pack.packId!,
                      child: Text('Packs: ${pack.packSize}'),
                    ),
                ],
                onChanged: widget.controller.state.captureBusy
                    ? null
                    : (value) => setState(() {
                        _reviewInStockUnits[line.id] = value == '';
                        if (value != null && value != '') {
                          _selectedReviewPacks[line.id] = value;
                        }
                      }),
              ),
              Text(
                widget.controller.reviewedStockPreview(
                  line: line,
                  product: selected.candidate,
                  packId:
                      _selectedReviewPacks[line.id] ??
                      (selected.candidate.packStatus == 'published'
                          ? selected.candidate.packId
                          : null),
                  quantityInStockUnits: _reviewInStockUnits[line.id] == true,
                ),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: Key('purchase-approve-line-${line.id}'),
              onPressed:
                  widget.controller.state.captureBusy ||
                      _selectedProducts[line.id] == null
                  ? null
                  : () => widget.controller.approveCandidate(
                      lineId: line.id,
                      candidateId: _selectedProducts[line.id]!,
                      purchasedPackId: _selectedReviewPacks[line.id],
                      quantityInStockUnits:
                          _reviewInStockUnits[line.id] == true,
                    ),
              child: Text(
                _matchActionLabel(
                  selected == null
                      ? null
                      : widget.controller.reviewTargetForCandidate(
                          selected.candidate,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: Key('purchase-create-private-${line.id}'),
              onPressed:
                  widget.controller.state.captureBusy ||
                      !widget.controller.canCreatePrivateProduct
                  ? null
                  : () => _createPrivateProduct(line),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Create private home product'),
            ),
            TextButton(
              key: Key('purchase-leave-unresolved-${line.id}'),
              onPressed: widget.controller.state.captureBusy
                  ? null
                  : () {
                      setState(() => _selectedProducts.remove(line.id));
                      widget.controller.leaveLineUnresolved(line.id);
                    },
              child: Text(
                line.unresolved
                    ? 'Retry unresolved decision'
                    : 'Leave unresolved',
              ),
            ),
            Text(
              'Matches and private products stay within this home. This action does not publish aliases or create catalog proposals; use the separate catalog contribution workflow for that.',
              key: Key('purchase-no-alias-publication-${line.id}'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createPrivateProduct(PurchaseReceiptLineCapture line) async {
    final draft = await showDialog<({String name, String pack})>(
      context: context,
      builder: (context) => _PrivateProductDialog(
        suggestedName: line.rawDescription,
        suggestedPack: line.originalPackText ?? '',
      ),
    );
    if (!mounted || draft == null) return;
    await widget.controller.createPrivateProductAndApprove(
      lineId: line.id,
      privateName: draft.name,
      originalPackText: draft.pack,
    );
  }

  Future<void> _createDraft() async {
    final currency = _currency.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      widget.controller.reportCaptureValidation(
        'Currency must use a three-letter uppercase code.',
      );
      return;
    }
    final total = _parseMoney(_receiptTotal.text, currency);
    if (_receiptTotal.text.trim().isNotEmpty && total == null) {
      widget.controller.reportCaptureValidation(
        'Receipt total must be a non-negative amount with at most two decimals.',
      );
      return;
    }
    final saved = await widget.controller.createDraft(
      purchaseDate: DateTime.now().toUtc(),
      storeId:
          widget.controller.stores.any(
            (store) => store.id == _storeId && !store.archived,
          )
          ? _storeId
          : null,
      currency: currency,
      total: total,
      notes: _notes.text,
      sourceReference: _sourceReference.text,
    );
    if (saved && mounted) {
      setState(() => _showDraftForm = false);
    }
  }

  Future<void> _addLine() async {
    final capture = widget.controller.state.capture;
    if (capture == null) return;
    final unitPrice = _parseMoney(_unitPrice.text, capture.currency);
    final lineTotal = _parseMoney(_lineTotal.text, capture.currency);
    if ((_unitPrice.text.trim().isNotEmpty && unitPrice == null) ||
        (_lineTotal.text.trim().isNotEmpty && lineTotal == null) ||
        (unitPrice == null && lineTotal == null)) {
      widget.controller.reportCaptureValidation(
        'Add a valid unit price or line total with at most two decimals.',
      );
      return;
    }
    final saved = await widget.controller.addLine(
      rawDescription: _description.text,
      quantity: double.tryParse(_quantity.text) ?? double.nan,
      quantityText: _quantity.text.trim(),
      originalPackText: _packText.text,
      unitPrice: unitPrice,
      lineTotal: lineTotal,
    );
    if (saved && mounted && widget.controller.state.capture?.id == capture.id) {
      _description.clear();
      _packText.clear();
      _unitPrice.clear();
      _lineTotal.clear();
      _quantity.text = '1';
      setState(() => _quantityReset++);
    }
  }
}

class _PrivateProductDialog extends StatefulWidget {
  const _PrivateProductDialog({
    required this.suggestedName,
    required this.suggestedPack,
  });

  final String suggestedName;
  final String suggestedPack;

  @override
  State<_PrivateProductDialog> createState() => _PrivateProductDialogState();
}

class _PrivateProductDialogState extends State<_PrivateProductDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.suggestedName,
  );
  late final TextEditingController _pack = TextEditingController(
    text: widget.suggestedPack,
  );

  @override
  void dispose() {
    _name.dispose();
    _pack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create private home product'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            key: const Key('purchase-private-product-name'),
            controller: _name,
            maxLength: 191,
            decoration: const InputDecoration(labelText: 'Private name'),
          ),
          TextField(
            key: const Key('purchase-private-product-pack'),
            controller: _pack,
            maxLength: 191,
            decoration: const InputDecoration(labelText: 'Original pack text'),
          ),
          const Text(
            'This creates only a home-private product. It does not publish a global alias or catalog proposal.',
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('purchase-private-product-confirm'),
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, (name: _name.text, pack: _pack.text));
          },
          child: const Text('Create and approve'),
        ),
      ],
    );
  }
}

class _PurchaseGroupCard extends StatelessWidget {
  const _PurchaseGroupCard({required this.group});

  final PurchaseGroup group;

  @override
  Widget build(BuildContext context) {
    final receipt = group.receipt;
    final spend = receipt == null
        ? null
        : ReceiptSpendAmount.fromReceipt(receipt);
    final amount = spend?.amount;
    return Card(
      child: ExpansionTile(
        title: Text(group.storeName),
        subtitle: Text(
          group.inferred
              ? 'Legacy date/store grouping'
              : group.pendingSynchronization
              ? 'Receipt pending synchronization'
              : 'Receipt',
        ),
        trailing: spend == null
            ? group.total == null
                  ? null
                  : Text(_money(group.total!))
            : Text(amount == null ? 'Spend incomplete' : _money(amount)),
        children: [
          if (receipt != null && spend != null) ...[
            Text(
              'Purchase date: ${receipt.purchaseDate.toIso8601String().substring(0, 10)}',
            ),
            Text(
              amount != null
                  ? 'Receipt spend: ${_money(amount)} (${spend.source.name})'
                  : spend.knownSubtotal == null
                  ? 'Receipt spend: unknown'
                  : 'Receipt spend: incomplete; ${_money(spend.knownSubtotal!)} known subtotal',
            ),
            ReceiptAmountSummary(receipt: receipt),
          ] else
            const Text(
              'Only entered-product amounts are available for this group; a physical receipt total is unavailable.',
            ),
          if (group.lines.isEmpty)
            const ListTile(
              title: Text(
                'No entered product lines. The saved receipt remains visible.',
              ),
            ),
          for (final line in group.lines)
            ListTile(
              title: Text(line.displayName),
              subtitle: Text(line.packSize),
              trailing: line.lineTotal == null
                  ? Text(_quantity(line.quantity))
                  : Text(_money(line.lineTotal!)),
            ),
        ],
      ),
    );
  }
}

String _matchActionLabel(PurchaseMatchCandidate? candidate) =>
    switch (candidate?.kind) {
      PurchaseMatchCandidateKind.unselectedPublishedPack =>
        'Add pack to home and approve',
      PurchaseMatchCandidateKind.privateHomeProduct =>
        'Approve private home product',
      PurchaseMatchCandidateKind.selectedCatalogPack =>
        'Approve existing home product',
      null => 'Approve match',
    };

String _matchBasisLabel(PurchaseMatchBasis basis) => switch (basis) {
  PurchaseMatchBasis.exactDescriptionAndPack =>
    'exact normalized description and pack',
  PurchaseMatchBasis.exactDescriptionOrAlias =>
    'exact canonical name or approved alias',
  PurchaseMatchBasis.exactPack => 'exact normalized pack text',
  PurchaseMatchBasis.partialDescription => 'description contains the item name',
  PurchaseMatchBasis.metadataOverlap =>
    'shared canonical, brand, category, pack, or alias terms',
  PurchaseMatchBasis.itemMasterFallback =>
    'available in the verified offline item master',
};

String _money(Money money) => formatReceiptMoney(money);

String _quantity(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 3);

Money? _parseMoney(String value, String currency) {
  try {
    return parseReceiptMoney(value, currency: currency);
  } on ArgumentError {
    return null;
  }
}
