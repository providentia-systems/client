import 'package:flutter/material.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

/// A scoped selection never copies a global category into the private namespace.
class InventoryCategoryField extends StatelessWidget {
  const InventoryCategoryField({
    required this.localCategories,
    required this.globalCategories,
    required this.onChanged,
    this.localId,
    this.globalId,
    this.inheritedName,
    this.enabled = true,
    super.key,
  });

  final List<HomeInventoryCategory> localCategories;
  final List<PublishedInventoryCategory> globalCategories;
  final String? localId;
  final String? globalId;
  final String? inheritedName;
  final bool enabled;
  final void Function(String? localId, String? globalId) onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = localId != null
        ? 'home:$localId'
        : globalId != null
        ? 'global:$globalId'
        : '';
    final options = <String, String>{
      '': inheritedName == null
          ? 'Uncategorized'
          : 'Use global product category: $inheritedName',
      for (final category in globalCategories)
        'global:${category.id}': '${category.name} · Global',
      for (final category in localCategories)
        if (!category.archived || category.id == localId)
          'home:${category.id}':
              '${category.name} · Local${category.archived ? ' (archived)' : ''}',
    };
    // Retain retired selections until deliberately changed by the household.
    options.putIfAbsent(
      selected,
      () => globalId != null
          ? 'Unavailable global category'
          : 'Unavailable local category',
    );
    return DropdownButtonFormField<String>(
      key: ValueKey('inventory-category-selection-$selected'),
      initialValue: selected,
      isExpanded: true,
      menuMaxHeight: 360,
      decoration: const InputDecoration(
        labelText: 'Category',
        helperText:
            'Global categories are shared. Local categories stay in your home.',
        helperMaxLines: 3,
      ),
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: !enabled
          ? null
          : (value) {
              if (value == null) return;
              onChanged(
                value.startsWith('home:') ? value.substring(5) : null,
                value.startsWith('global:') ? value.substring(7) : null,
              );
            },
    );
  }
}
