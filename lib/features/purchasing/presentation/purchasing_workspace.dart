import 'package:flutter/material.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';

class PurchasingWorkspace extends StatefulWidget {
  const PurchasingWorkspace({required this.controller, super.key});

  final PurchasingController controller;

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
            Text('Purchases', style: Theme.of(context).textTheme.headlineLarge),
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
              _PurchaseCapturePanel(controller: widget.controller),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Recent spend'),
                  subtitle: Text(
                    '${widget.controller.recentGroups.length} receipt group'
                    '${widget.controller.recentGroups.length == 1 ? '' : 's'}',
                  ),
                  trailing: Text(
                    widget.controller.recentSpend == null
                        ? 'Incomplete prices'
                        : _money(widget.controller.recentSpend!),
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
  const _PurchaseCapturePanel({required this.controller});

  final PurchasingController controller;

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
  final _packText = TextEditingController();
  final _unitPrice = TextEditingController();
  final _lineTotal = TextEditingController();
  final Map<String, String> _selectedProducts = <String, String>{};
  bool _showDraftForm = false;

  @override
  void dispose() {
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
            if (state.captureNotice != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                state.captureNotice!,
                key: const Key('purchase-capture-notice'),
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
          const SizedBox(height: 4),
          Text(
            pending
                ? 'Commit queued locally; awaiting server confirmation.'
                : 'Commit synchronized.',
            key: const Key('purchase-commit-state'),
          ),
          if (pending) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('purchase-retry-commit'),
              onPressed: widget.controller.state.captureBusy
                  ? null
                  : widget.controller.commitDraft,
              child: const Text('Retry synchronization'),
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
        for (final line in capture.lines) _lineReview(context, line),
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
          decoration: const InputDecoration(labelText: 'Pack text (optional)'),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const Key('purchase-line-quantity'),
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
          decoration: const InputDecoration(labelText: 'Unit price (optional)'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('purchase-add-line'),
          onPressed: widget.controller.state.captureBusy ? null : _addLine,
          icon: const Icon(Icons.add),
          label: const Text('Add receipt line'),
        ),
        const SizedBox(height: 8),
        if (!capture.reviewComplete)
          const Text(
            'Every line must be matched and approved before commit.',
            key: Key('purchase-review-required'),
          ),
        FilledButton(
          key: const Key('purchase-commit-receipt'),
          onPressed:
              widget.controller.state.captureBusy || !capture.reviewComplete
              ? null
              : widget.controller.commitDraft,
          child: const Text('Queue receipt commit'),
        ),
      ],
    );
  }

  Widget _lineReview(BuildContext context, PurchaseReceiptLineCapture line) {
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
        subtitle: Text(
          'Approved: ${match?.name ?? 'Private home product'} · '
          'revision ${line.revision}',
        ),
      );
    }
    final candidates = widget.controller.state.matchCandidates;
    return Card.outlined(
      key: Key('purchase-line-${line.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(line.rawDescription),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: Key('purchase-line-match-${line.id}'),
              initialValue: _selectedProducts[line.id],
              items: candidates
                  .map(
                    (candidate) => DropdownMenuItem<String>(
                      value: candidate.id,
                      child: Text('${candidate.name} · ${candidate.packSize}'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() {
                if (value == null) {
                  _selectedProducts.remove(line.id);
                } else {
                  _selectedProducts[line.id] = value;
                }
              }),
              decoration: const InputDecoration(labelText: 'Match product'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: Key('purchase-approve-line-${line.id}'),
              onPressed:
                  widget.controller.state.captureBusy ||
                      _selectedProducts[line.id] == null
                  ? null
                  : () => widget.controller.approveLine(
                      lineId: line.id,
                      homeProductId: _selectedProducts[line.id]!,
                    ),
              child: const Text('Approve match'),
            ),
          ],
        ),
      ),
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
      originalPackText: _packText.text,
      unitPrice: unitPrice,
      lineTotal: lineTotal,
    );
    if (saved) {
      _description.clear();
      _packText.clear();
      _unitPrice.clear();
      _lineTotal.clear();
      _quantity.text = '1';
    }
  }
}

class _PurchaseGroupCard extends StatelessWidget {
  const _PurchaseGroupCard({required this.group});

  final PurchaseGroup group;

  @override
  Widget build(BuildContext context) {
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
        trailing: group.total == null ? null : Text(_money(group.total!)),
        children: group.lines
            .map(
              (line) => ListTile(
                title: Text(line.displayName),
                subtitle: Text(line.packSize),
                trailing: line.lineTotal == null
                    ? Text(_quantity(line.quantity))
                    : Text(_money(line.lineTotal!)),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

String _money(Money money) =>
    '${money.currency} ${(money.minorUnits / 100).toStringAsFixed(2)}';

String _quantity(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 3);

Money? _parseMoney(String value, String currency) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      !RegExp(r'^(?:0|[1-9]\d{0,11})(?:\.\d{1,2})?$').hasMatch(trimmed)) {
    return null;
  }
  final parts = trimmed.split('.');
  final whole = int.parse(parts.first);
  final fraction = parts.length == 1
      ? 0
      : int.parse(parts.last.padRight(2, '0'));
  return Money(minorUnits: whole * 100 + fraction, currency: currency);
}
