import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/domain/stock_preference.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

Future<void> showStockPreferenceEditor(
  BuildContext context,
  InventoryController controller,
  InventoryItem item,
) => showDialog<void>(
  context: context,
  builder: (_) => _StockPreferenceEditor(controller: controller, item: item),
);

final class _StockPreferenceEditor extends StatefulWidget {
  const _StockPreferenceEditor({required this.controller, required this.item});
  final InventoryController controller;
  final InventoryItem item;
  @override
  State<_StockPreferenceEditor> createState() => _StockPreferenceEditorState();
}

final class _StockPreferenceEditorState extends State<_StockPreferenceEditor> {
  final _minimum = TextEditingController();
  final _leadTime = TextEditingController();
  final _coverage = TextEditingController();
  final _snooze = TextEditingController();
  StockPreference? _preference;
  var _alwaysKeep = false;
  var _neverSuggest = false;
  String? _pack;
  var _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preference = await widget.controller.loadStockPreference(
        widget.item,
      );
      if (!mounted) return;
      _minimum.text = preference.minimumQuantity ?? '';
      _leadTime.text = '${preference.leadTimeDays}';
      _coverage.text = preference.targetCoverageDays?.toString() ?? '';
      _snooze.text = preference.snoozeUntil ?? '';
      setState(() {
        _preference = preference;
        _alwaysKeep = preference.alwaysKeep;
        _neverSuggest = preference.neverSuggest;
        _pack = preference.preferredPackId;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _preference = null;
          _error =
              'Stock preferences could not be loaded. Connect and reload before editing.';
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String? optional(TextEditingController field) =>
          field.text.trim().isEmpty ? null : field.text.trim();
      final value = StockPreference(
        homeId: widget.item.homeId,
        homeProductId: widget.item.id,
        revision: _preference!.revision,
        minimumQuantity: optional(_minimum),
        alwaysKeep: _alwaysKeep,
        neverSuggest: _neverSuggest,
        preferredPackId: _pack,
        leadTimeDays: int.parse(_leadTime.text.trim()),
        targetCoverageDays: optional(_coverage) == null
            ? null
            : int.parse(_coverage.text.trim()),
        snoozeUntil: optional(_snooze),
      );
      await widget.controller.saveStockPreference(value);
      if (mounted) Navigator.pop(context);
    } on ArgumentError catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Check the minimum, days and date. Minimum must be non-negative; lead time 0–365 and coverage 1–365 days.';
        });
      }
    } on FormatException catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Enter valid numbers and a date as YYYY-MM-DD.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'The preference changed or could not be saved. Reload before trying again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _minimum.dispose();
    _leadTime.dispose();
    _coverage.dispose();
    _snooze.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packs = <String, String>{
      ?_pack: 'Saved preferred pack',
      if (widget.item.productId != null)
        for (final item in widget.controller.state.items)
          if (item.productId == widget.item.productId && item.packId != null)
            item.packId!: item.packSize,
    };
    return AlertDialog(
      title: const Text('Stock limits and recommendations'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.item.canonicalName),
              if (_busy) const LinearProgressIndicator(),
              if (_preference != null) ...[
                const Text(
                  'These preferences guide recommendations. They do not change the quantity in stock.',
                ),
                TextField(
                  key: const Key('stock-preference-minimum'),
                  controller: _minimum,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Minimum stock (optional)',
                  ),
                ),
                SwitchListTile(
                  title: const Text('Always keep in stock'),
                  value: _alwaysKeep,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _alwaysKeep = value),
                ),
                SwitchListTile(
                  title: const Text('Exclude from recommendations'),
                  value: _neverSuggest,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _neverSuggest = value),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(_pack),
                  initialValue: _pack ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Preferred pack',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Choose automatically'),
                    ),
                    for (final pack in packs.entries)
                      DropdownMenuItem(
                        value: pack.key,
                        child: Text(pack.value),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _pack = value == '' ? null : value),
                ),
                TextField(
                  key: const Key('stock-preference-lead'),
                  controller: _leadTime,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Lead time (days)',
                  ),
                ),
                TextField(
                  key: const Key('stock-preference-coverage'),
                  controller: _coverage,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Days to cover (optional)',
                  ),
                ),
                TextField(
                  key: const Key('stock-preference-snooze'),
                  controller: _snooze,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Pause suggestions until (YYYY-MM-DD, optional)',
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _minimum.clear();
                          _leadTime.text = '0';
                          _coverage.clear();
                          _snooze.clear();
                          _alwaysKeep = false;
                          _neverSuggest = false;
                          _pack = null;
                        }),
                  child: const Text('Reset to defaults'),
                ),
              ],
              if (_error != null) Text(_error!),
              if (_error != null)
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Reload'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _preference == null ? null : _save,
          child: const Text('Save preferences'),
        ),
      ],
    );
  }
}
