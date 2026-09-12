import 'package:flutter/material.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/inventory/presentation/stock_preference_editor.dart';

Future<void> showInventoryProductEditor(
  BuildContext context,
  InventoryController controller,
  InventoryItem item, {
  bool archived = false,
}) async {
  var categoryId = item.homeCategoryId;
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => _OwnedTextControllers(
      initialValues: {
        'name': item.canonicalName,
        'pack': item.packSize == 'Unspecified pack' ? '' : item.packSize,
      },
      builder: (context, fields) {
        final name = fields['name']!;
        final pack = fields['pack']!;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Edit ${item.canonicalName}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      enabled: item.productId == null,
                      maxLength: 191,
                      decoration: const InputDecoration(
                        labelText: 'Product name',
                      ),
                    ),
                    TextField(
                      controller: pack,
                      enabled: item.productId == null,
                      maxLength: 191,
                      decoration: const InputDecoration(
                        labelText: 'Pack and measure',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: categoryId ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Home category',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Uncategorized'),
                        ),
                        for (final category in controller.homeCategories)
                          if (!category.archived || category.id == categoryId)
                            DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name),
                            ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => categoryId = value == '' ? null : value,
                    ),
                    if (!archived && controller.canManageStockPreferences)
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
                    const Text(
                      'Changes are queued for synchronization. Removing a product requires zero stock and no active count or receipt references. History is retained.',
                    ),
                    if (error != null) Text(error!),
                  ],
                ),
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
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dialog, true),
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
                            archived: true,
                          );
                          if (!context.mounted) return;
                          if (saved) {
                            Navigator.pop(context);
                          } else {
                            setState(() {
                              busy = false;
                              error = 'The product could not be removed.';
                            });
                          }
                        },
                  child: const Text('Remove product'),
                ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (name.text.trim().isEmpty) {
                          setState(() => error = 'Enter a product name.');
                          return;
                        }
                        setState(() => busy = true);
                        final saved = await controller.editProduct(
                          item: item,
                          name: name.text,
                          pack: pack.text,
                          categoryId: categoryId,
                        );
                        if (!context.mounted) return;
                        if (saved) {
                          Navigator.pop(context);
                        } else {
                          setState(() {
                            busy = false;
                            error = 'The product could not be saved.';
                          });
                        }
                      },
                child: Text(archived ? 'Restore product' : 'Save locally'),
              ),
            ],
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
      title: const Text('Home categories'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Private categories synchronize with your home. Remove or reassign active products before archiving a category.',
              ),
              for (final category in controller.homeCategories)
                ListTile(
                  title: Text(category.name),
                  subtitle: category.archived ? const Text('Archived') : null,
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
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 191,
                    decoration: const InputDecoration(
                      labelText: 'Category name',
                    ),
                  ),
                  if (error != null) Text(error!),
                ],
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
