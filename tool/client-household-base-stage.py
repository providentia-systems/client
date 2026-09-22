from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'lib/core/database/client_local_record_types.dart'
s=p.read_text().replace('  static const String itemMasterCache', "  static const String catalogProductBase = 'client.catalog.product-base-v1';\n  static const String itemMasterCache").replace('    publishedCategoryCache,','    publishedCategoryCache,\n    catalogProductBase,');p.write_text(s)
p=root/'lib/core/database/drift_household_repository.dart'
s=p.read_text().replace('  static const String _homeProductType','  static const String _catalogBaseType = ClientLocalRecordTypes.catalogProductBase;\n  static const String _homeProductType')
s=s.replace('        _publishedCategoryType,','        _publishedCategoryType,\n        _catalogBaseType,')
s=s.replace('    final publicItems = <InventoryItem>[];', '    final publicItems = <InventoryItem>[];\n    final productBases = <String, Map<String, Object?>>{};')
s=s.replace('      if (!hasPublicIdentity) continue;', '''      if (item.productId != null && item.catalogName != null) {
        if (item.catalogCategoryId != null) _requireUuid(item.catalogCategoryId!, 'catalog category');
        final base = <String, Object?>{
          'homeId': homeId, 'name': item.catalogName,
          'categoryId': item.catalogCategoryId, 'categoryName': item.catalogCategoryName,
        };
        final previous = productBases[item.productId];
        if (previous != null && jsonEncode(previous) != jsonEncode(base)) {
          throw const FormatException('Catalog base metadata changed during pagination.');
        }
        productBases[item.productId!] = base;
      }
      if (!hasPublicIdentity) continue;''')
s=s.replace('      if (categories != null) {', '''      await (_database.delete(_database.localRecords)..where(
        (row) => row.homeId.equals(homeId) & row.entityType.equals(_catalogBaseType),
      )).go();
      for (final entry in productBases.entries) {
        await _writeRecord(homeId: homeId, entityType: _catalogBaseType,
          entityId: entry.key, payload: entry.value);
      }
      if (categories != null) {''',1)
s=s.replace('    final catalogItems = <String, InventoryItem>{};', '''    final catalogItems = <String, InventoryItem>{};
    final productBases = <String, Map<String, Object?>>{};
    for (final row in rows.where((row) => row.entityType == _catalogBaseType)) {
      final base = _decodeObject(row.payload, 'catalog product base');
      if (row.homeId != homeId || base['homeId'] != homeId) {
        throw StateError('Cross-home catalog base metadata was rejected.');
      }
      productBases[row.entityId] = base;
    }''')
s=s.replace("      final inheritedCategoryId = catalogItem?.categoryId ?? _nullableUuid(payload['categoryId'], 'categoryId');", "      final base = productBases[productId];\n      final inheritedCategoryId = catalogItem?.categoryId ?? _nullableUuid(base?['categoryId'] ?? payload['categoryId'], 'categoryId');")
s=s.replace("final inheritedCategoryName = catalogItem?.category ?? _nullableString(payload['categoryName']);", "final inheritedCategoryName = catalogItem?.category ?? _nullableString(base?['categoryName'] ?? payload['categoryName']);")
s=s.replace('            catalogItem?.canonicalName ??\n            productName', "            catalogItem?.canonicalName ??\n            _nullableString(base?['name']) ??\n            productName")
s=s.replace('catalogName: catalogItem?.canonicalName ?? productName,', "catalogName: catalogItem?.canonicalName ?? _nullableString(base?['name']) ?? productName,")
p.write_text(s)
p=root/'lib/features/inventory/infrastructure/generated_home_item_master_source.dart'
s=p.read_text().replace("  final packText = _string(record, 'packText').trim();", "  final unit = _nullableString(record, 'unit') ?? 'units';\n  if (!householdStockUnits.contains(unit)) {\n    throw const FormatException('The stock unit is unsupported.');\n  }\n  final packText = _string(record, 'packText').trim();").replace("unit: _nullableString(record, 'unit') ?? 'units',",'unit: unit,');p.write_text(s)
p=root/'lib/features/inventory/infrastructure/item_master_refreshing_synchronization.dart'
s=p.read_text().replace("import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';", "import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';\nimport 'package:providentia/features/inventory/infrastructure/generated_published_category_source.dart';")
s=s.replace('required List<InventoryItem> items,','required List<InventoryItem> items,\n      List<PublishedInventoryCategory>? categories,')
s=s.replace('required String homeId,\n  }) : this._(delegate, source, replaceCache, homeId);','required String homeId,\n    PublishedCategorySource? categorySource,\n  }) : this._(delegate, source, replaceCache, homeId, categorySource);')
s=s.replace('this._homeId,\n  );','this._homeId,\n    this._categorySource,\n  );')
s=s.replace('final HomeItemMasterSource _source;', 'final HomeItemMasterSource _source;\n  final PublishedCategorySource? _categorySource;')
s=s.replace('late final List<InventoryItem> items;', 'late final List<InventoryItem> items;\n    List<PublishedInventoryCategory>? categories;')
s=s.replace('items = await _source.loadAll(homeId: homeId);','items = await _source.loadAll(homeId: homeId);\n      categories = await _categorySource?.loadAll();')
s=s.replace('await _replaceCache(homeId: homeId, items: items);','await _replaceCache(homeId: homeId, items: items, categories: categories);')
p.write_text(s)
p=root/'lib/app/production_bootstrap_app.dart';s=p.read_text()
s=s.replace("import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';", "import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';\nimport 'package:providentia/features/inventory/infrastructure/generated_published_category_source.dart';")
s=s.replace('source: GeneratedHomeItemMasterSource(widget.api),','source: GeneratedHomeItemMasterSource(widget.api),\n        categorySource: GeneratedPublishedCategorySource(widget.api),')
s=s.replace('replaceCache: ({required homeId, required items})', 'replaceCache: ({required homeId, required items, categories})')
s=s.replace('await household.replaceCatalogItemMaster(\n            homeId: homeId,\n            items: items,','await household.replaceCatalogItemMaster(\n            homeId: homeId,\n            items: items,\n            categories: categories,')
p.write_text(s)
p=root/'test/features/inventory/item_master_refreshing_synchronization_test.dart';s=p.read_text().replace('replaceCache: ({required homeId, required items})','replaceCache: ({required homeId, required items, categories})');p.write_text(s)
