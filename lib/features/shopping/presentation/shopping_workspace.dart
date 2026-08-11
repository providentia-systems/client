import 'package:flutter/material.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';

class ShoppingWorkspace extends StatefulWidget {
  const ShoppingWorkspace({required this.controller, super.key});

  final ShoppingController controller;

  @override
  State<ShoppingWorkspace> createState() => _ShoppingWorkspaceState();
}

class _ShoppingWorkspaceState extends State<ShoppingWorkspace> {
  final TextEditingController _draft = TextEditingController();
  final TextEditingController _quantityDraft = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void dispose() {
    _draft.dispose();
    _quantityDraft.dispose();
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('manual-list-input'),
                    controller: _draft,
                    decoration: const InputDecoration(
                      labelText: 'Manual shopping item',
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 92,
                  child: TextField(
                    key: const Key('manual-list-quantity'),
                    controller: _quantityDraft,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton(
                  key: const Key('manual-list-add'),
                  tooltip: 'Add to shopping list',
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
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
                      'Live explanations require a connection. Feedback is '
                      'unavailable pending retry-safe support.',
                    ),
                  ),
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
                  '${list.completedCount}/${list.lines.length} complete',
                ),
              ),
              for (final line in list.lines)
                _ShoppingLineTile(
                  line: line,
                  onToggle: () => widget.controller.toggle(line.id),
                  canEditQuantity:
                      widget.controller.capabilities.canEditExistingQuantities,
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

  Future<void> _add() async {
    final value = _draft.text;
    final quantity = double.tryParse(_quantityDraft.text.trim());
    final saved = quantity != null
        ? await widget.controller.addManual(value, quantity: quantity)
        : false;
    if (mounted && saved) {
      _draft.clear();
      _quantityDraft.text = '1';
    }
  }

  Future<void> _addSuggestion(OnlineShoppingSuggestion suggestion) async {
    var input = suggestion.requiredQuantity.value;
    final quantity = await showDialog<ExactDecimal>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${suggestion.productName} to the list'),
        content: TextFormField(
          key: Key('online-suggestion-quantity-${suggestion.id}'),
          initialValue: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Quantity greater than zero',
          ),
          onChanged: (value) => input = value,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('confirm-add-online-suggestion-${suggestion.id}'),
            onPressed: () {
              try {
                final parsed = ExactDecimal(input);
                if (parsed.isPositive) Navigator.pop(context, parsed);
              } on ArgumentError {
                // Invalid values remain in the dialog for correction.
              }
            },
            child: const Text('Add to list'),
          ),
        ],
      ),
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
    var input = _formatQuantity(line.quantity);
    final quantity = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${line.name} quantity'),
        content: TextFormField(
          key: Key('shopping-quantity-editor-${line.id}'),
          initialValue: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Quantity greater than zero',
          ),
          onChanged: (value) => input = value,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('save-shopping-quantity-${line.id}'),
            onPressed: () {
              final value = double.tryParse(input.trim());
              if (value != null && value.isFinite && value > 0) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Save quantity'),
          ),
        ],
      ),
    );
    if (quantity != null && mounted) {
      await widget.controller.tryUpdateQuantity(line, quantity);
    }
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
    required this.canEditQuantity,
    required this.canRecordFeedback,
    required this.onEditQuantity,
    required this.onShowExplanation,
    required this.onFeedback,
  });

  final ShoppingListLine line;
  final VoidCallback onToggle;
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
                Checkbox(value: line.checked, onChanged: (_) => onToggle()),
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
              child: Row(
                children: <Widget>[
                  Text('Quantity: ${_formatQuantity(line.quantity)}'),
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

String _formatQuantity(double quantity) =>
    quantity.toStringAsFixed(quantity == quantity.roundToDouble() ? 0 : 2);

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
