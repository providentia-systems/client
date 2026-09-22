from pathlib import Path
r=Path(__file__).resolve().parents[1]
p=r/'lib/features/inventory/presentation/inventory_workspace.dart'; s=p.read_text()
s=s.replace("import 'package:providentia/features/inventory/presentation/inventory_controller.dart';", "import 'package:providentia/features/inventory/presentation/inventory_category_field.dart';\nimport 'package:providentia/features/inventory/presentation/inventory_controller.dart';")
s=s.replace('''                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Stock',
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                      ),''', '''                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text('Stock', style: Theme.of(context).textTheme.headlineLarge),''')
s=s.replace("                    initialValue: state.criteria.category ?? 'All',\n                    items:", "                    initialValue: state.criteria.category ?? 'All',\n                    isExpanded: true,\n                    items:")
s=s.replace('child: Text(category),', 'child: Text(category, overflow: TextOverflow.ellipsis),')
s=s.replace('showDialog<(String, String?, String?)>(', 'showDialog<PrivateHomeProductDraft>(')
s=s.replace('''      builder: (_) => _PrivateHomeProductDialog(
        categories: widget.controller.homeCategories,
      ),''', '''      barrierDismissible: false,
      builder: (_) => _PrivateHomeProductDialog(controller: widget.controller),''')
s=s.replace('''      privateName: draft.$1,
      originalPackText: draft.$2,
      homeCategoryId: draft.$3,''', '''      privateName: draft.privateName,
      originalPackText: draft.originalPackText,
      homeCategoryId: draft.homeCategoryId,
      globalCategoryId: draft.globalCategoryId,
      unit: draft.unit,''')
a=s.index('class _PrivateHomeProductDialog extends'); b=s.index('class _CountSessionBar',a)
s=s[:a]+(r/'tool/client-household-private.template').read_text()+s[b:]
a=s.index('class _InventoryQuantityDialog extends'); s=s[:a]+(r/'tool/client-household-quantity.template').read_text()
s=s.replace('                  SegmentedButton<InventoryView>(\n', '''                  if (MediaQuery.textScalerOf(context).scale(14) > 20)
                    DropdownButtonFormField<InventoryView>(
                      initialValue: state.criteria.view,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: InventoryView.counted, child: Text('Counted')),
                        DropdownMenuItem(value: InventoryView.itemMaster, child: Text('Item master')),
                      ],
                      onChanged: (value) { if (value != null) widget.controller.selectView(value); },
                    )
                  else SegmentedButton<InventoryView>(
''')
a=s.index('    return Card(\n      child: ListTile(',s.index('class _InventoryRow')); b=s.index('\n  String get _metadata',a)
s=s[:a]+'''    return Card(
      child: InkWell(
        onTap: belongsToHome ? () => _editQuantity(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text(item.canonicalName, style: Theme.of(context).textTheme.titleMedium)),
                if (belongsToHome && controller.canEditMetadata)
                  IconButton(
                    tooltip: 'Edit product',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => showInventoryProductEditor(context, controller, item),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(_metadata),
              const SizedBox(height: 8),
              if (belongsToHome)
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(item.currentQuantity == null ? 'Not counted' : '${item.currentQuantity!.toStringAsFixed(_decimals(item.currentQuantity!))} ${item.unit}'),
                    if (countSessionActive && controller.state.activeSession!.lines.any((line) => line.itemId == item.id))
                      IconButton(tooltip: 'Remove from this count', icon: const Icon(Icons.undo), onPressed: () => _removeCount(context)),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: Key('inventory-add-catalog-${item.packId ?? item.id}'),
                    onPressed: controller.canAddCatalogProduct && !controller.state.productCreationBusy
                        ? () => controller.addCatalogProduct(item) : null,
                    child: const Text('Add to home'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
'''+s[b:]; p.write_text(s)
p=r/'lib/features/inventory/presentation/inventory_metadata_dialogs.dart'; s=p.read_text()
s=s.replace("import 'package:providentia/features/inventory/presentation/inventory_controller.dart';", "import 'package:providentia/features/inventory/presentation/inventory_category_field.dart';\nimport 'package:providentia/features/inventory/presentation/inventory_controller.dart';")
a=s.index('Future<void> showInventoryProductEditor('); b=s.index('Future<void> showArchivedInventoryProducts(',a)
s=s[:a]+(r/'tool/client-household-editor.template').read_text()+s[b:]
s=s.replace("title: const Text('Home categories'),", "title: const Text('Categories'),")
s=s.replace("                'Private categories synchronize with your home. Remove or reassign active products before archiving a category.',", "                'Use any global category on your products. Create a local category only when you need one that is not available globally. Local categories remain private to your home.',")
s=s.replace('              for (final category in controller.homeCategories)', '''              const SizedBox(height: 20),
              Text('Global categories', style: Theme.of(context).textTheme.titleMedium),
              if (controller.publishedCategories.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No published categories are cached. Synchronize to refresh them.')),
              for (final category in controller.publishedCategories)
                ListTile(
                  title: Text(category.name),
                  subtitle: const Text('Global · available to select on any home product'),
                ),
              const SizedBox(height: 20),
              Text('Local categories', style: Theme.of(context).textTheme.titleMedium),
              for (final category in controller.homeCategories)''')
s=s.replace("subtitle: category.archived ? const Text('Archived') : null,", "subtitle: Text(category.archived ? 'Local · Archived' : 'Local · Private to your home'),")
a=s.index('Future<void> _editCategory(');c=s[a:]
c=c.replace('              content: Column(', '              scrollable: true,\n              content: SizedBox(width: 420, child: Column(')
c=c.replace('                  if (error != null) Text(error!),\n                ],\n              ),', '                  if (error != null) ...[const SizedBox(height: 12), Text(error!)],\n                ],\n              )),')
s=s[:a]+c;p.write_text(s)
# Extend the narrow existing infrastructure allowlists, not feature-layer permissions.
for name in ('test/architecture/layer_boundaries_test.dart','tool/verify_structure.mjs'):
    p=r/name;s=p.read_text().replace("'lib/features/inventory/infrastructure/generated_home_item_master_source.dart',", "'lib/features/inventory/infrastructure/generated_home_item_master_source.dart',\n      'lib/features/inventory/infrastructure/generated_published_category_source.dart',");p.write_text(s)
p=r/'test/features/inventory/inventory_metadata_dialogs_test.dart';s=p.read_text().replace('class _Repository implements InventoryRepository, InventoryMetadataRepository {', '''class _Repository implements InventoryRepository, InventoryMetadataRepository {
  @override
  Stream<List<PublishedInventoryCategory>> watchPublishedCategories(String homeId) => Stream.value([]);''').replace('required String privateName,','required String? privateName,').replace('    String? homeCategoryId,\n    required bool archived,','    String? homeCategoryId,\n    String? globalCategoryId,\n    String? unit,\n    required bool archived,');p.write_text(s)
p=r/'test/features/inventory/inventory_workflow_coverage_test.dart';s=p.read_text().replace('''        await tester.enterText(
          find.byKey(const ValueKey<String>('inventory-adjustment-reason')),
          'Cycle count correction',
        );''', '''        final reason = find.byKey(const ValueKey<String>('inventory-adjustment-reason'));
        await tester.ensureVisible(reason);
        await tester.tap(reason);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Other').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('inventory-adjustment-explanation')), 'Cycle count correction');''');p.write_text(s)
