import 'package:flutter/material.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_category_field.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/inventory/presentation/stock_preference_editor.dart';

Future<void> showInventoryProductEditor(
  BuildContext context,
  InventoryController controller,
  InventoryItem item, {
  bool archived = false,
}) async {
  var categoryId = item.homeCategoryId;
  var globalCategoryId = item.globalCategoryId;
  var unit = item.unit;
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _OwnedTextControllers(
      initialValues: {
        'name': item.canonicalName,
        'pack': item.packSize == 'Unspecified pack' ? '' : item.packSize,
      },
      builder: (context, fields) {
        final name = fields['name']!;
        final pack = fields['pack']!;
        return StatefulBuilder(
          builder: (context, setState) => ListenableBuilder(
            listenable: controller,
            builder: (context, _) => PopScope(
              canPop: !busy,
              child: AlertDialog(
                title: Text('Edit ${item.canonicalName}'),
                scrollable: true,
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        item.productId == null
                            ? 'Edit this product for your home. Stock and history are retained.'
                            : 'These changes apply only to your home. The shared global product is not changed.',
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const Key('inventory-product-name'),
                        controller: name,
                        enabled: !busy,
                        maxLength: 191,
                        decoration: const InputDecoration(
                          labelText: 'Product name',
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const Key('inventory-product-pack'),
                        controller: pack,
                        enabled: !busy,
                        maxLength: 191,
                        decoration: const InputDecoration(
                          labelText: 'Pack and measure',
                        ),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        key: const Key('inventory-product-unit'),
                        initialValue: unit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Stock unit',
                          helperText:
                              'A unit correction keeps the existing numbers; it does not convert stock quantities.',
                          helperMaxLines: 4,
                        ),
                        items: [
                          for (final value in {...householdStockUnits, unit})
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: busy
                            ? null
                            : (value) {
                                if (value != null) setState(() => unit = value);
                              },
                      ),
                      const SizedBox(height: 20),
                      InventoryCategoryField(
                        localCategories: controller.homeCategories,
                        globalCategories: controller.publishedCategories,
                        localId: categoryId,
                        globalId: globalCategoryId,
                        inheritedName: item.productId == null
                            ? null
                            : item.catalogCategoryName ?? 'Uncategorized',
                        enabled: !busy,
                        onChanged: (local, global) => setState(() {
                          categoryId = local;
                          globalCategoryId = global;
                        }),
                      ),
                      if (item.catalogName != null) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  name.text = item.catalogName!;
                                  pack.text = item.catalogPackText ?? '';
                                  categoryId = null;
                                  globalCategoryId = null;
                                }),
                          icon: const Icon(Icons.restore),
                          label: const Text('Use global product details'),
                        ),
                      ],
                      if (!archived &&
                          controller.canManageStockPreferences) ...[
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => showStockPreferenceEditor(
                                  context,
                                  controller,
                                  item,
                                ),
                          child: const Text('Stock limits and recommendations'),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        'Changes are saved locally and queued for synchronization. Removing a product requires zero stock and no active count or receipt references.',
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
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
                  if (!archived)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialog) => AlertDialog(
                                  title: const Text('Remove product?'),
                                  content: const Text(
                                    'The product will be archived after synchronization. Its history is retained.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialog, true),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true || !context.mounted) return;
                              setState(() => busy = true);
                              final saved = await controller.editProduct(
                                item: item,
                                name: item.canonicalName,
                                pack: item.packSize == 'Unspecified pack'
                                    ? null
                                    : item.packSize,
                                categoryId: item.homeCategoryId,
                                globalCategoryId: item.globalCategoryId,
                                unit: item.unit,
                                archived: true,
                              );
                              if (!context.mounted) return;
                              setState(() => busy = false);
                              if (saved) {
                                Navigator.pop(context);
                              } else {
                                setState(
                                  () => error =
                                      'The product could not be removed.',
                                );
                              }
                            },
                      child: const Text('Remove product'),
                    ),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (name.text.trim().isEmpty ||
                                name.text.trim().length > 191 ||
                                pack.text.trim().length > 191) {
                              setState(
                                () => error =
                                    'Enter a product name; name and pack must be at most 191 characters.',
                              );
                              return;
                            }
                            setState(() => busy = true);
                            final saved = await controller.editProduct(
                              item: item,
                              name: name.text.trim(),
                              pack: pack.text.trim(),
                              categoryId: categoryId,
                              globalCategoryId: globalCategoryId,
                              unit: unit,
                            );
                            if (!context.mounted) return;
                            setState(() => busy = false);
                            if (saved) {
                              Navigator.pop(context);
                            } else {
                              setState(
                                () => error =
                                    'The product could not be saved. Refresh and try again.',
                              );
                            }
                          },
                    child: Text(archived ? 'Restore product' : 'Save locally'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> showArchivedInventoryProducts(
  BuildContext context,
  InventoryController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Removed products'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.archivedProducts.isEmpty)
                const Text('No removed products.'),
              for (final item in controller.archivedProducts)
                ListTile(
                  title: Text(item.canonicalName),
                  subtitle: Text(item.packSize),
                  trailing: const Icon(Icons.restore),
                  onTap: () => showInventoryProductEditor(
                    context,
                    controller,
                    item,
                    archived: true,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  ),
);

Future<void> showInventoryCategories(
  BuildContext context,
  InventoryController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Categories'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Use any global category on your products. Create a local category only when you need one that is not available globally. Local categories remain private to your home.',
              ),
              const SizedBox(height: 20),
              Text(
                'Global categories',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (controller.publishedCategories.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No published categories are cached. Synchronize to refresh them.',
                  ),
                ),
              for (final category in controller.publishedCategories)
                ListTile(
                  title: Text(category.name),
                  subtitle: const Text(
                    'Global · available to select on any home product',
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Local categories',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final category in controller.homeCategories)
                ListTile(
                  title: Text(category.name),
                  subtitle: Text(
                    category.archived
                        ? 'Local · Archived'
                        : 'Local · Private to your home',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editCategory(context, controller, category),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () => _editCategory(context, controller, null),
          icon: const Icon(Icons.add),
          label: const Text('Create category'),
        ),
      ],
    ),
  ),
);

Future<void> _editCategory(
  BuildContext context,
  InventoryController controller,
  HomeInventoryCategory? category,
) async {
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => _OwnedTextControllers(
      initialValues: {'name': category?.name ?? ''},
      builder: (context, fields) {
        final name = fields['name']!;
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> save(bool archived) async {
              if (name.text.trim().isEmpty) {
                setState(() => error = 'Enter a category name.');
                return;
              }
              setState(() => busy = true);
              final saved = await controller.saveCategory(
                category: category,
                name: name.text,
                archived: archived,
              );
              if (!context.mounted) return;
              if (saved) {
                Navigator.pop(context);
              } else {
                setState(() {
                  busy = false;
                  error =
                      'The category changed or could not be saved. Refresh and try again.';
                });
              }
            }

            return AlertDialog(
              title: Text(
                category == null ? 'Create category' : 'Edit category',
              ),
              scrollable: true,
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      maxLength: 191,
                      decoration: const InputDecoration(
                        labelText: 'Category name',
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                if (category != null && !category.archived)
                  TextButton(
                    onPressed: busy ? null : () => save(true),
                    child: const Text('Archive'),
                  ),
                FilledButton(
                  onPressed: busy ? null : () => save(false),
                  child: Text(
                    category?.archived == true ? 'Restore' : 'Save locally',
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class _OwnedTextControllers extends StatefulWidget {
  const _OwnedTextControllers({
    required this.initialValues,
    required this.builder,
  });
  final Map<String, String> initialValues;
  final Widget Function(BuildContext, Map<String, TextEditingController>)
  builder;
  @override
  State<_OwnedTextControllers> createState() => _OwnedTextControllersState();
}

class _OwnedTextControllersState extends State<_OwnedTextControllers> {
  late final fields = <String, TextEditingController>{
    for (final entry in widget.initialValues.entries)
      entry.key: TextEditingController(text: entry.value),
  };
  @override
  Widget build(BuildContext context) => widget.builder(context, fields);
  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
