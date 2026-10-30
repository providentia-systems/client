import 'package:flutter/material.dart';
import 'package:providentia/core/domain/household_product_lookup.dart';
import 'package:providentia/core/presentation/quantity_field.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';
import 'package:providentia/features/shopping/presentation/shopping_relink_dialog.dart';

class ShoppingWorkspace extends StatefulWidget {
  const ShoppingWorkspace({required this.controller, super.key});

  final ShoppingController controller;

  @override
  State<ShoppingWorkspace> createState() => _ShoppingWorkspaceState();
}

class _ShoppingWorkspaceState extends State<ShoppingWorkspace> {
  bool _showRemoved = false;
  final TextEditingController _draft = TextEditingController();
  final TextEditingController _quantityDraft = TextEditingController(text: '1');
  String? _selectedProductId;
  String? _selectedPackId;
  final _instructions = TextEditingController();
  String? _entryError;
  var _quantityReset = 0;

  InventoryItem? get _selectedProduct => widget.controller.items
      .where((item) => item.id == _selectedProductId)
      .firstOrNull;

  String _productLabel(InventoryItem item) =>
      '${item.canonicalName}${item.brand.isEmpty ? '' : ' · ${item.brand}'} · ${item.packSize} (${item.unit})';

  void _textChanged() {
    if (!mounted) return;
    final selected = _selectedProduct;
    setState(() {
      if (selected == null || _draft.text != _productLabel(selected)) {
        _selectedProductId = null;
        _selectedPackId = null;
      }
      _entryError = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _draft.addListener(_textChanged);
    widget.controller.start();
  }

  @override
  void didUpdateWidget(covariant ShoppingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _selectedProductId = null;
      _draft.clear();
      _quantityDraft.text = '1';
      _quantityReset++;
      _entryError = null;
      widget.controller.start();
    }
  }

  @override
  void dispose() {
    _draft.removeListener(_textChanged);
    _draft.dispose();
    _quantityDraft.dispose();
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final list = state.list;
        return ListView(
          key: const Key('shopping-workspace'),
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Text(
              'Shopping list',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            if (widget.controller.canManageLists) ...<Widget>[
              if (widget.controller.lists.isNotEmpty)
                DropdownButtonFormField<String>(
                  key: ValueKey('selected-shopping-list-${list?.id}'),
                  initialValue:
                      widget.controller.lists.any(
                        (entry) => entry.id == list?.id,
                      )
                      ? list?.id
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Your shopping lists',
                  ),
                  items: widget.controller.lists
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.id,
                          child: Text(
                            '${entry.name}${entry.archived ? ' (removed)' : ''}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id != null) widget.controller.selectList(id);
                  },
                ),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => _editListName(create: true),
                    icon: const Icon(Icons.add),
                    label: const Text('New list'),
                  ),
                  if (list != null) ...<Widget>[
                    TextButton(
                      onPressed: () => _editListName(create: false),
                      child: const Text('Rename list'),
                    ),
                    TextButton(
                      onPressed: () => _archiveList(list),
                      child: Text(
                        list.archived ? 'Restore list' : 'Remove list',
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (list?.archived != true) ...<Widget>[
              KeyedSubtree(
                key: ObjectKey(widget.controller),
                child: _manualEntry(),
              ),
              if (_selectedProduct case final product?) ...[
                Text(
                  'Selected household product: ${product.canonicalName}. Choose its stock measurement or compatible buying pack.',
                  key: const Key('shopping-selected-product'),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('shopping-manual-pack-${product.id}'),
                  initialValue: _selectedPackId ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Quantity refers to',
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text('Stock measurement (${product.unit})'),
                    ),
                    if (_selectedPackId != null &&
                        !widget.controller
                            .packChoices(product.id)
                            .any((pack) => pack.id == _selectedPackId))
                      DropdownMenuItem(
                        value: _selectedPackId,
                        enabled: false,
                        child: const Text(
                          'Selected pack unavailable — choose again',
                        ),
                      ),
                    for (final pack in widget.controller.packChoices(
                      product.id,
                    ))
                      DropdownMenuItem(
                        value: pack.id,
                        child: Text('Packs: ${pack.label}'),
                      ),
                  ],
                  onChanged: widget.controller.manualBusy
                      ? null
                      : (value) => setState(
                          () => _selectedPackId = value == '' ? null : value,
                        ),
                ),
                TextField(
                  key: const Key('shopping-manual-instructions'),
                  controller: _instructions,
                  enabled: !widget.controller.manualBusy,
                  maxLength: 191,
                  decoration: const InputDecoration(
                    labelText: 'Purchasing instructions (optional)',
                    helperText:
                        'Instructions do not change the selected product.',
                  ),
                ),
              ] else if (_draft.text.trim().isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('shopping-add-custom'),
                    onPressed: widget.controller.manualBusy
                        ? null
                        : () => _add(asCustom: true),
                    child: Text('Add “${_draft.text.trim()}” as a custom item'),
                  ),
                ),
              if (_entryError != null)
                Text(
                  _entryError!,
                  key: const Key('shopping-entry-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (widget.controller.manualBusy) const LinearProgressIndicator(),
            ],
            if (state.safeError != null) Text(state.safeError!),
            if (widget
                .controller
                .capabilities
                .onlineSuggestionsComposed) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                'Evidence-based suggestions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'These legacy deterministic recommendations stay separate '
                'from your list until you choose Add to list.',
              ),
              if (state.suggestionsFromVerifiedCache)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.offline_pin_outlined),
                    title: Text('Last verified offline suggestions'),
                    subtitle: Text(
                      'Live explanations require a connection. Decisions '
                      'are saved on this device and synchronized when online.',
                    ),
                  ),
                ),
              if (widget.controller.canGenerateSuggestions)
                OutlinedButton.icon(
                  onPressed: state.suggestionsLoading
                      ? null
                      : widget.controller.generateSuggestions,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Generate recommendations'),
                ),
              if (state.suggestionsLoading)
                const LinearProgressIndicator(
                  key: Key('shopping-suggestions-loading'),
                )
              else if (state.suggestions.isEmpty)
                const Card(
                  key: Key('shopping-suggestions-empty'),
                  child: ListTile(
                    title: Text('No active suggestions'),
                    subtitle: Text('Manual shopping items remain available.'),
                  ),
                )
              else
                for (final suggestion in state.suggestions)
                  _OnlineSuggestionCard(
                    suggestion: suggestion,
                    feedbackAvailable: widget
                        .controller
                        .capabilities
                        .canRecordSuggestionFeedback,
                    onAdd: () => _addSuggestion(suggestion),
                    onExplain: () => _showOnlineExplanation(suggestion),
                    onDecision: (decision) =>
                        _onlineDecision(suggestion, decision),
                  ),
            ],
            if (list != null) ...<Widget>[
              const SizedBox(height: 12),
              if (!widget.controller.capabilities.onlineSuggestionsComposed &&
                  !list.lines.any(
                    (line) => line.origin == ShoppingLineOrigin.suggestion,
                  ))
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lightbulb_outline_rounded),
                    title: const Text('Online suggestions are not connected'),
                    subtitle: const Text(
                      'This workspace currently shows synchronized list lines '
                      'and manual additions only.',
                    ),
                  ),
                ),
              LinearProgressIndicator(value: list.progress),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '${list.completedCount}/${list.activeLines.length} complete',
                ),
              ),
              if (list.lines.any((line) => line.archived))
                SwitchListTile(
                  title: const Text('Show removed items'),
                  value: _showRemoved,
                  onChanged: (value) => setState(() => _showRemoved = value),
                ),
              for (final line in list.lines.where(
                (line) => !line.archived || _showRemoved,
              ))
                _ShoppingLineTile(
                  line: line,
                  productLabel: widget.controller.linkedProductLabel(line),
                  quantityLabel: widget.controller.quantityLabel(line),
                  onRelink:
                      widget.controller.canRelinkLines &&
                          !list.archived &&
                          !line.archived
                      ? () => showDialog<void>(
                          context: context,
                          builder: (_) => ShoppingRelinkDialog(
                            controller: widget.controller,
                            line: line,
                          ),
                        )
                      : null,
                  onToggle: list.archived || line.archived
                      ? null
                      : () => widget.controller.toggle(line.id),
                  onEdit: widget.controller.canManageLists && !list.archived
                      ? () => _editLine(line)
                      : null,
                  onArchive: widget.controller.canManageLists && !list.archived
                      ? () => _archiveLine(line)
                      : null,
                  canEditQuantity:
                      widget
                          .controller
                          .capabilities
                          .canEditExistingQuantities &&
                      !list.archived &&
                      !line.archived,
                  canRecordFeedback: widget
                      .controller
                      .capabilities
                      .canRecordSuggestionFeedback,
                  onEditQuantity: () => _editQuantity(line),
                  onShowExplanation: () => _showExplanation(line),
                  onFeedback: (kind) => _feedback(line, kind),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _manualEntry() {
    final products = widget.controller.items;
    final productField = DropdownMenu<String>(
      key: const Key('manual-list-input'),
      controller: _draft,
      expandedInsets: EdgeInsets.zero,
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      enabled: !widget.controller.manualBusy,
      label: const Text('Manual shopping item'),
      helperText: 'Browse household products or type a custom item.',
      dropdownMenuEntries: <DropdownMenuEntry<String>>[
        for (final item in products)
          DropdownMenuEntry(value: item.id, label: _productLabel(item)),
      ],
      filterCallback: (entries, query) => const HouseholdProductLookup().rank(
        query: query,
        products: entries,
        describe: (entry) {
          final item = products.firstWhere((item) => item.id == entry.value);
          return ProductLookupText(
            name: item.canonicalName,
            brand: item.brand,
            pack: item.packSize,
            category: item.category,
            aliases: item.aliases,
          );
        },
      ),
      onSelected: (id) => setState(() {
        _selectedProductId = id;
        _selectedPackId = null;
        _entryError = null;
      }),
    );
    final quantityAndAdd = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 110,
          child: QuantityField(
            key: const Key('manual-list-quantity'),
            controller: _quantityDraft,
            resetToken: _quantityReset,
            enabled: !widget.controller.manualBusy,
            decoration: const InputDecoration(labelText: 'Quantity'),
            onFieldSubmitted: (_) => _add(),
          ),
        ),
        IconButton(
          key: const Key('manual-list-add'),
          tooltip: 'Add to shopping list',
          onPressed: widget.controller.manualBusy ? null : _add,
          icon: const Icon(Icons.add),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 520
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                productField,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: quantityAndAdd),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: productField),
                const SizedBox(width: 8),
                quantityAndAdd,
              ],
            ),
    );
  }

  Future<void> _editListName({required bool create}) async {
    final currentList = widget.controller.state.list;
    var name = create ? '' : currentList!.name;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(create ? 'New shopping list' : 'Rename shopping list'),
        content: TextFormField(
          initialValue: name,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'List name'),
          onChanged: (value) => name = value,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(context, name.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    if (create) {
      await widget.controller.createList(value);
    } else {
      await widget.controller.updateList(
        name: value,
        expectedList: currentList,
      );
    }
  }

  Future<bool> _confirmRemoval(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
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
      ) ??
      false;

  Future<void> _archiveList(ShoppingList list) async {
    if (!list.archived &&
        !await _confirmRemoval(
          'Remove this list?',
          'Its items and history will be kept. You can restore the list later.',
        )) {
      return;
    }
    await widget.controller.updateList(
      archived: !list.archived,
      expectedList: list,
    );
  }

  Future<void> _archiveLine(ShoppingListLine line) async {
    if (!line.archived &&
        !await _confirmRemoval(
          'Remove this item?',
          'The item will be hidden. Show removed items to restore it later.',
        )) {
      return;
    }
    await widget.controller.editLine(line, archived: !line.archived);
  }

  Future<void> _editLine(ShoppingListLine line) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ShoppingLineEditor(
        line: line,
        save: (name, quantity) =>
            widget.controller.editLine(line, name: name, quantity: quantity),
      ),
    );
  }

  Future<void> _add({bool asCustom = false}) async {
    final controller = widget.controller;
    if (controller.manualBusy) return;
    final quantity = double.tryParse(_quantityDraft.text.trim());
    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      setState(() => _entryError = 'Enter a quantity greater than zero.');
      return;
    }
    if (!asCustom && _selectedProductId != null && _selectedProduct == null) {
      setState(
        () => _entryError =
            'The selected product is unavailable. Choose it again or explicitly add a custom item.',
      );
      return;
    }
    final product = asCustom ? null : _selectedProduct;
    final value = product?.canonicalName ?? _draft.text.trim();
    if (value.isEmpty || value.length > 191) {
      setState(
        () => _entryError = 'Enter an item name of 1 to 191 characters.',
      );
      return;
    }
    final listId = controller.state.list?.id;
    final duplicate = product == null
        ? null
        : controller.duplicateForProduct(
            product.id,
            selectedPackId: _selectedPackId,
          );
    var separate = false;
    if (duplicate != null) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Product already on this list'),
          content: Text(
            '${duplicate.name} already has quantity ${_formatQuantity(duplicate.quantity)}. '
            'Add ${_formatQuantity(quantity)} to that quantity or keep a separate line? Existing instructions are retained when quantities are combined.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Keep separate line'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Add to existing quantity'),
            ),
          ],
        ),
      );
      if (!mounted || widget.controller != controller || choice == null) return;
      separate = choice;
    }
    if (widget.controller != controller) return;
    if (controller.state.list?.id != listId) {
      setState(
        () => _entryError =
            'The selected list changed. Review your entry before adding.',
      );
      return;
    }
    final saved = duplicate != null && !separate
        ? await controller.increaseDuplicateQuantity(duplicate, quantity)
        : await controller.addManual(
            value,
            quantity: quantity,
            homeProductId: product?.id,
            allowDuplicate: separate,
            selectedPackId: product == null ? null : _selectedPackId,
            instructions: product == null ? null : _instructions.text,
          );
    if (mounted && widget.controller == controller && saved) {
      setState(() {
        _selectedProductId = null;
        _selectedPackId = null;
        _instructions.clear();
        _draft.clear();
        _quantityDraft.text = '1';
        _quantityReset++;
        _entryError = null;
      });
    }
  }

  Future<void> _addSuggestion(OnlineShoppingSuggestion suggestion) async {
    final quantity = await showDialog<ExactDecimal>(
      context: context,
      builder: (context) => _SuggestionQuantityDialog(suggestion: suggestion),
    );
    if (quantity == null || !mounted) return;
    final added = await widget.controller.addOnlineSuggestion(
      suggestion,
      quantity: quantity,
    );
    if (added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suggestion added to the shopping list.')),
      );
    }
  }

  Future<void> _showOnlineExplanation(
    OnlineShoppingSuggestion suggestion,
  ) async {
    final explanation = await widget.controller.loadSuggestionExplanation(
      suggestion,
    );
    if (explanation == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Why ${suggestion.productName} was suggested'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              Text(
                'Evidence factors',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final factor in explanation.factors)
                Text(_factorDescription(factor)),
              const SizedBox(height: 12),
              Text(
                'Limitations',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (explanation.limitations.isEmpty)
                const Text('No limitations were reported for this run.')
              else
                for (final limitation in explanation.limitations)
                  Text('• $limitation'),
              if (explanation.packOptions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'Pack options',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final option in explanation.packOptions)
                  Text(
                    '${option.packCount} pack(s) · ${option.currency} '
                    '${option.effectiveTotal.value} · ${option.reason}',
                  ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _onlineDecision(
    OnlineShoppingSuggestion suggestion,
    OnlineSuggestionDecision decision,
  ) async {
    final recorded = await widget.controller.decideOnlineSuggestion(
      suggestion,
      decision,
    );
    if (recorded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suggestion decision recorded.')),
      );
    }
  }

  Future<void> _editQuantity(ShoppingListLine line) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ShoppingLineEditor(
        line: line,
        quantityOnly: true,
        save: (_, quantity) =>
            widget.controller.tryUpdateQuantity(line, quantity),
      ),
    );
  }

  Future<void> _showExplanation(ShoppingListLine line) {
    final explanation = line.explanation?.trim();
    if (explanation == null || explanation.isEmpty) {
      return Future<void>.value();
    }
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Why this was suggested'),
        content: Text(explanation),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _feedback(
    ShoppingListLine line,
    SuggestionFeedbackKind kind,
  ) async {
    final recorded = await widget.controller.submitSuggestionFeedback(
      line,
      kind,
    );
    if (recorded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suggestion feedback recorded.')),
      );
    }
  }
}

class _SuggestionQuantityDialog extends StatefulWidget {
  const _SuggestionQuantityDialog({required this.suggestion});
  final OnlineShoppingSuggestion suggestion;

  @override
  State<_SuggestionQuantityDialog> createState() =>
      _SuggestionQuantityDialogState();
}

class _SuggestionQuantityDialogState extends State<_SuggestionQuantityDialog> {
  late final TextEditingController _quantity = TextEditingController(
    text: widget.suggestion.requiredQuantity.value,
  );
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  void _confirm() {
    try {
      final parsed = ExactDecimal(_quantity.text.trim());
      if (parsed.isPositive) {
        Navigator.pop(context, parsed);
        return;
      }
    } on ArgumentError {
      // Invalid input remains visible for correction.
    }
    setState(() => _error = 'Enter a quantity greater than zero.');
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Add ${widget.suggestion.productName} to the list'),
    content: QuantityField(
      key: Key('online-suggestion-quantity-${widget.suggestion.id}'),
      controller: _quantity,
      autofocus: true,
      decoration: InputDecoration(
        labelText: 'Quantity greater than zero',
        errorText: _error,
      ),
      onFieldSubmitted: (_) => _confirm(),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: Key('confirm-add-online-suggestion-${widget.suggestion.id}'),
        onPressed: _confirm,
        child: const Text('Add to list'),
      ),
    ],
  );
}

class _ShoppingLineEditor extends StatefulWidget {
  const _ShoppingLineEditor({
    required this.line,
    required this.save,
    this.quantityOnly = false,
  });

  final ShoppingListLine line;
  final Future<bool> Function(String name, double quantity) save;
  final bool quantityOnly;

  @override
  State<_ShoppingLineEditor> createState() => _ShoppingLineEditorState();
}

class _ShoppingLineEditorState extends State<_ShoppingLineEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.line.name,
  );
  late final TextEditingController _quantity = TextEditingController(
    text: widget.line.quantity.toString(),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final quantity = double.tryParse(_quantity.text.trim());
    if (quantity == null ||
        !quantity.isFinite ||
        quantity <= 0 ||
        _name.text.trim().isEmpty ||
        _name.text.trim().length > 191) {
      setState(
        () => _error = 'Enter a description and a quantity greater than zero.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    var saved = false;
    try {
      saved = await widget.save(_name.text.trim(), quantity);
    } catch (_) {
      // Keep all entered values available for correction or retry.
    }
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error =
            'The item could not be saved. Your entry is retained; review the current list and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.quantityOnly
          ? 'Edit ${widget.line.name} quantity'
          : 'Edit shopping item',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!widget.quantityOnly)
            TextFormField(
              controller: _name,
              maxLength: 191,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: widget.line.homeProductId == null
                    ? 'Description'
                    : 'Shopping description / instructions',
                helperText: widget.line.homeProductId == null
                    ? null
                    : 'The household product identity and master name stay linked.',
              ),
            ),
          QuantityField(
            key: Key('shopping-quantity-editor-${widget.line.id}'),
            controller: _quantity,
            enabled: !_saving,
            autofocus: widget.quantityOnly,
            decoration: const InputDecoration(
              labelText: 'Quantity greater than zero',
            ),
            onFieldSubmitted: (_) => _save(),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_saving) const LinearProgressIndicator(),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: Key('save-shopping-quantity-${widget.line.id}'),
        onPressed: _saving ? null : _save,
        child: Text(widget.quantityOnly ? 'Save quantity' : 'Save'),
      ),
    ],
  );
}

class _OnlineSuggestionCard extends StatelessWidget {
  const _OnlineSuggestionCard({
    required this.suggestion,
    required this.feedbackAvailable,
    required this.onAdd,
    required this.onExplain,
    required this.onDecision,
  });

  final OnlineShoppingSuggestion suggestion;
  final bool feedbackAvailable;
  final VoidCallback onAdd;
  final VoidCallback onExplain;
  final ValueChanged<OnlineSuggestionDecision> onDecision;

  @override
  Widget build(BuildContext context) {
    final lowConfidence =
        suggestion.confidenceBand == ShoppingSuggestionConfidenceBand.low;
    return Card(
      key: Key('online-shopping-suggestion-${suggestion.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    suggestion.productName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Chip(
                  avatar: Icon(Icons.analytics_outlined, size: 16),
                  label: Text('Evidence-based · legacy'),
                ),
              ],
            ),
            Text(
              'Suggested quantity: ${suggestion.requiredQuantity.value}'
              '${suggestion.packText == null ? '' : ' · ${suggestion.packText}'}',
            ),
            Text(
              '${_confidenceLabel(suggestion.confidenceBand)} confidence '
              '(${suggestion.confidenceScore.value})',
            ),
            if (lowConfidence)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Limited evidence: review the explanation and its '
                  'limitations before adding this item.',
                ),
              ),
            TextButton.icon(
              key: Key('online-suggestion-explanation-${suggestion.id}'),
              onPressed: onExplain,
              icon: const Icon(Icons.info_outline),
              label: const Text('Review factors and limitations'),
            ),
            Wrap(
              spacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  key: Key('add-online-suggestion-${suggestion.id}'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Add to list'),
                ),
                if (feedbackAvailable) ...<Widget>[
                  TextButton(
                    key: Key('dismiss-online-suggestion-${suggestion.id}'),
                    onPressed: () =>
                        onDecision(OnlineSuggestionDecision.dismissed),
                    child: const Text('Dismiss'),
                  ),
                  TextButton(
                    key: Key('snooze-online-suggestion-${suggestion.id}'),
                    onPressed: () =>
                        onDecision(OnlineSuggestionDecision.snoozed),
                    child: const Text('Snooze'),
                  ),
                ] else
                  const Text(
                    'Online suggestion feedback is unavailable pending '
                    'retry-safe support.',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShoppingLineTile extends StatelessWidget {
  const _ShoppingLineTile({
    required this.line,
    required this.onToggle,
    required this.productLabel,
    required this.quantityLabel,
    this.onRelink,
    this.onEdit,
    this.onArchive,
    required this.canEditQuantity,
    required this.canRecordFeedback,
    required this.onEditQuantity,
    required this.onShowExplanation,
    required this.onFeedback,
  });

  final ShoppingListLine line;
  final VoidCallback? onToggle;
  final String productLabel;
  final String quantityLabel;
  final VoidCallback? onRelink;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;
  final bool canEditQuantity;
  final bool canRecordFeedback;
  final VoidCallback onEditQuantity;
  final VoidCallback onShowExplanation;
  final ValueChanged<SuggestionFeedbackKind> onFeedback;

  @override
  Widget build(BuildContext context) {
    final suggested = line.origin == ShoppingLineOrigin.suggestion;
    final explanation = line.explanation?.trim();
    final feedbackAvailable =
        suggested &&
        canRecordFeedback &&
        (line.suggestionId != null || line.productPackId != null);
    return Card(
      key: Key('shopping-line-${line.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Checkbox(
                  value: line.checked,
                  onChanged: onToggle == null ? null : (_) => onToggle!(),
                ),
                Expanded(
                  child: Text(
                    line.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  key: Key('shopping-origin-${line.id}'),
                  avatar: Icon(
                    suggested ? Icons.auto_awesome : Icons.person_outline,
                    size: 16,
                  ),
                  label: Text(suggested ? 'Suggested' : 'Manual'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text('Quantity: ${_formatQuantity(line.quantity)}'),
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(quantityLabel),
                  ),
                  if (onEdit != null && !line.archived)
                    IconButton(
                      tooltip: 'Edit item',
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_note),
                    ),
                  if (onArchive != null)
                    IconButton(
                      tooltip: line.archived ? 'Restore item' : 'Remove item',
                      onPressed: onArchive,
                      icon: Icon(
                        line.archived ? Icons.restore : Icons.delete_outline,
                      ),
                    ),
                  if (canEditQuantity) ...<Widget>[
                    const SizedBox(width: 4),
                    IconButton(
                      key: Key('edit-shopping-quantity-${line.id}'),
                      tooltip: 'Edit quantity',
                      onPressed: onEditQuantity,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('Product: $productLabel'),
            ),
            if (line.pending)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text('Saved locally · awaiting synchronization'),
              ),
            if (onRelink != null)
              TextButton.icon(
                key: Key('relink-shopping-line-${line.id}'),
                onPressed: onRelink,
                icon: const Icon(Icons.link),
                label: const Text('Change product or pack'),
              ),
            if (suggested) ...<Widget>[
              if (explanation != null && explanation.isNotEmpty)
                TextButton.icon(
                  key: Key('shopping-explanation-${line.id}'),
                  onPressed: onShowExplanation,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Why this was suggested'),
                )
              else
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Text(
                    'No explanation is available for this suggestion.',
                  ),
                ),
              if (feedbackAvailable)
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    TextButton(
                      key: Key('accept-suggestion-${line.id}'),
                      onPressed: () =>
                          onFeedback(SuggestionFeedbackKind.accepted),
                      child: const Text('Useful'),
                    ),
                    TextButton(
                      key: Key('dismiss-suggestion-${line.id}'),
                      onPressed: () =>
                          onFeedback(SuggestionFeedbackKind.dismissed),
                      child: const Text('Not for me'),
                    ),
                    TextButton(
                      key: Key('snooze-suggestion-${line.id}'),
                      onPressed: () =>
                          onFeedback(SuggestionFeedbackKind.snoozed),
                      child: const Text('Snooze'),
                    ),
                  ],
                )
              else
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Text(
                    'Suggestion feedback is not available in this workspace.',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatQuantity(double quantity) {
  if (quantity == quantity.roundToDouble()) return quantity.toStringAsFixed(0);
  final precise = quantity.toStringAsFixed(8).replaceFirst(RegExp(r'0+$'), '');
  return precise.split('.').last.length < 2
      ? quantity.toStringAsFixed(2)
      : precise;
}

String _confidenceLabel(ShoppingSuggestionConfidenceBand band) =>
    switch (band) {
      ShoppingSuggestionConfidenceBand.low => 'Low',
      ShoppingSuggestionConfidenceBand.medium => 'Medium',
      ShoppingSuggestionConfidenceBand.high => 'High',
    };

String _factorDescription(ShoppingSuggestionFactor factor) {
  final details = <String>[
    if (factor.value != null) factor.value!.value,
    if (factor.days != null) '${factor.days} day(s)',
    if (factor.nextExpectedShoppingAt != null)
      'next ${factor.nextExpectedShoppingAt!.toLocal()}',
  ];
  return '${factor.key.replaceAll('-', ' ')}: '
      '${details.isEmpty ? 'reported' : details.join(' · ')}';
}
