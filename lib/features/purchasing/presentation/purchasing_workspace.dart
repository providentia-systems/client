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

class _PurchaseGroupCard extends StatelessWidget {
  const _PurchaseGroupCard({required this.group});

  final PurchaseGroup group;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(group.storeName),
        subtitle: Text(
          group.inferred ? 'Legacy date/store grouping' : 'Receipt',
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
