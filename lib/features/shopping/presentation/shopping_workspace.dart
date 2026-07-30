import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void dispose() {
    _draft.dispose();
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
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('manual-list-input'),
                    controller: _draft,
                    decoration: const InputDecoration(
                      labelText: 'Add something else',
                    ),
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
            if (list != null) ...<Widget>[
              const SizedBox(height: 12),
              if (!list.lines.any(
                (line) => line.origin == ShoppingLineOrigin.suggestion,
              ))
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.lightbulb_outline_rounded),
                    title: Text('No evidence-backed suggestions yet'),
                    subtitle: Text(
                      'Suggestions appear after reliable stock-count intervals '
                      'or an explicit household minimum is configured.',
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
                ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _add() async {
    final value = _draft.text;
    await widget.controller.addManual(value);
    if (mounted && value.trim().isNotEmpty) {
      _draft.clear();
    }
  }
}

class _ShoppingLineTile extends StatelessWidget {
  const _ShoppingLineTile({required this.line, required this.onToggle});

  final ShoppingListLine line;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: line.checked,
      onChanged: (_) => onToggle(),
      title: Text(line.name),
      subtitle: Text(
        line.origin == ShoppingLineOrigin.manual
            ? 'Manual list item'
            : line.explanation ?? 'Suggested item',
      ),
      secondary: Text(
        line.quantity.toStringAsFixed(
          line.quantity == line.quantity.roundToDouble() ? 0 : 2,
        ),
      ),
    );
  }
}
