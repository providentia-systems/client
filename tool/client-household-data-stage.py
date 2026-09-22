from pathlib import Path
root = Path(__file__).resolve().parents[1]
def edit(path, f):
    p=root/path; s=p.read_text(); n=f(s); assert n!=s,path; p.write_text(n)

def models(s):
    s=s.replace('final class PrivateHomeProductDraft {', '''/// Stock-unit labels do not implicitly convert existing quantities or history.
const householdStockUnits = <String>['units', 'g', 'kg', 'ml', 'l'];

final class PublishedInventoryCategory {
  PublishedInventoryCategory({required this.id, required this.name, required this.revision}) {
    _requireText(id, 'id');
    _requireText(name, 'name');
    if (name.length > 191 || revision < 1) {
      throw ArgumentError('The published category is invalid.');
    }
  }
  final String id;
  final String name;
  final int revision;
}

final class PrivateHomeProductDraft {''')
    a=s.index('final class PrivateHomeProductDraft'); b=s.index('final class CatalogHomeProductDraft')
    c=s[a:b].replace('    this.homeCategoryId,', "    this.homeCategoryId,\n    this.globalCategoryId,\n    this.unit = 'units',")
    c=c.replace("    _requireText(homeId, 'homeId');", """    _requireText(homeId, 'homeId');
    if (!householdStockUnits.contains(unit)) {
      throw ArgumentError.value(unit, 'unit', 'Choose a supported stock unit.');
    }
    if (globalCategoryId != null &&
        (globalCategoryId!.trim().isEmpty || homeCategoryId != null)) {
      throw ArgumentError('Choose a global or a local category, not both.');
    }""")
    c=c.replace('  final String? homeCategoryId;', '  final String? homeCategoryId;\n  final String? globalCategoryId;\n  final String unit;'); s=s[:a]+c+s[b:]
    a=s.index('final class InventoryItem {'); b=s.index('\n}',a)+2; c=s[a:b]
    c=c.replace('    this.homeCategoryId,', '''    this.homeCategoryId,
    this.globalCategoryId,
    this.catalogName,
    this.catalogPackText,
    this.catalogCategoryId,
    this.catalogCategoryName,''')
    c=c.replace('  final String? homeCategoryId;', '''  final String? homeCategoryId;
  final String? globalCategoryId;
  final String? catalogName;
  final String? catalogPackText;
  final String? catalogCategoryId;
  final String? catalogCategoryName;''')
    c=c.replace('      homeCategoryId: homeCategoryId,', '''      homeCategoryId: homeCategoryId,
      globalCategoryId: globalCategoryId,
      catalogName: catalogName,
      catalogPackText: catalogPackText,
      catalogCategoryId: catalogCategoryId,
      catalogCategoryName: catalogCategoryName,''')
    return s[:a]+c+s[b:]
edit('lib/features/inventory/domain/inventory_models.dart',models)
edit('lib/features/inventory/application/inventory_repository.dart',lambda s:s.replace('  Stream<List<HomeInventoryCategory>> watchHomeCategories(String homeId);', '''  Stream<List<HomeInventoryCategory>> watchHomeCategories(String homeId);
  Stream<List<PublishedInventoryCategory>> watchPublishedCategories(String homeId);''').replace('required String privateName,','required String? privateName,').replace('    String? homeCategoryId,\n    required bool archived,','    String? homeCategoryId,\n    String? globalCategoryId,\n    String? unit,\n    required bool archived,'))
edit('lib/core/database/client_local_record_types.dart',lambda s:s.replace('  static const String itemMasterCache', "  static const String publishedCategoryCache = 'client.catalog.published-category-v1';\n  static const String itemMasterCache").replace('    itemMasterCache,','    itemMasterCache,\n    publishedCategoryCache,'))

def database(s):
    s=s.replace("  static const String _homeCategoryType = 'inventory-home-category';", "  static const String _homeCategoryType = 'inventory-home-category';\n  static const String _publishedCategoryType = ClientLocalRecordTypes.publishedCategoryCache;")
    s=s.replace('        _homeCategoryType,\n', '        _homeCategoryType,\n        _publishedCategoryType,\n')
    a=s.index('  @override\n  bool get supportsStockPreferences')
    s=s[:a]+'''  @override
  Stream<List<PublishedInventoryCategory>> watchPublishedCategories(String homeId) =>
      _watchRecordTypes(homeId: homeId, entityTypes: const {_publishedCategoryType})
          .map((rows) => rows.map((row) {
            final data = _decodeObject(row.payload, 'published category');
            if (data['homeId'] != homeId || row.homeId != homeId) {
              throw StateError('Cross-home category cache was rejected.');
            }
            return PublishedInventoryCategory(
              id: row.entityId,
              name: _requiredString(data, 'name'),
              revision: data['revision'] as int,
            );
          }).toList()..sort((a, b) => a.name.compareTo(b.name)));

'''+s[a:]
    a=s.index('  Future<void> updateHomeProduct({'); b=s.index('  @override\n  Future<InventoryProductCreationResult> createPrivateHomeProduct',a)
    c=s[a:b].replace('required String privateName,','required String? privateName,').replace('    String? homeCategoryId,','    String? homeCategoryId,\n    String? globalCategoryId,\n    String? unit,')
    c=c.replace('      privateName: privateName,', "      privateName: privateName ?? 'Linked product',").replace('      homeCategoryId: homeCategoryId,\n    );', "      homeCategoryId: homeCategoryId,\n      globalCategoryId: globalCategoryId,\n      unit: unit ?? 'units',\n    );")
    c=c.replace("    if (homeCategoryId != null) _requireUuid(homeCategoryId, 'home category');", "    if (homeCategoryId != null) _requireUuid(homeCategoryId, 'home category');\n    if (globalCategoryId != null) _requireUuid(globalCategoryId, 'global category');")
    c=c.replace("      final catalogBacked = data['productId'] != null;", """      if (data['productId'] == null && privateName == null) {
        throw ArgumentError('A private product must retain a name.');
      }""")
    c=c.replace("        if (!catalogBacked) 'privateName': draft.privateName.trim(),\n        if (!catalogBacked)\n          'originalPackText': _trimToNull(draft.originalPackText),", "        'privateName': privateName == null ? null : draft.privateName.trim(),\n        'originalPackText': _trimToNull(draft.originalPackText),")
    c=c.replace("        'homeCategoryId': draft.homeCategoryId,", "        'homeCategoryId': draft.homeCategoryId,\n        'globalCategoryId': draft.globalCategoryId,\n        if (unit != null) 'unit': unit,")
    s=s[:a]+c+s[b:]
    a=s.index('  Future<InventoryProductCreationResult> createPrivateHomeProduct'); b=s.index('  @override\n  Future<InventoryProductCreationResult> createCatalogHomeProduct',a)
    c=s[a:b].replace('    final privateName = draft.privateName.trim();', "    if (draft.globalCategoryId != null) _requireUuid(draft.globalCategoryId!, 'global category');\n    final privateName = draft.privateName.trim();")
    c=c.replace("'homeCategoryId': draft.homeCategoryId,", "'homeCategoryId': draft.homeCategoryId,\n          'globalCategoryId': draft.globalCategoryId,\n          'unit': draft.unit,")
    c=c.replace('_database.transaction<InventoryProductCreationResult>', '_transaction<InventoryProductCreationResult>')
    s=s[:a]+c+s[b:]
    a=s.index('  Future<InventoryProductCreationResult> createCatalogHomeProduct'); b=s.index('  /// Atomically replaces',a)
    c=s[a:b].replace("          'homeCategoryId': null,\n          'status': 'active',", "          'homeCategoryId': null,\n          'globalCategoryId': null,\n          'unit': 'units',\n          'status': 'active',")
    s=s[:a]+c+s[b:]
    a=s.index('  Future<void> replaceCatalogItemMaster({'); b=s.index('  @override\n  Stream<StockCountSession?>',a)
    c=s[a:b].replace('    required List<InventoryItem> items,','    required List<InventoryItem> items,\n    List<PublishedInventoryCategory>? categories,')
    c=c.replace('          (hasPublicIdentity &&\n              item.categorySource == InventoryCategorySource.home) ||\n          (hasPrivateIdentity &&\n              item.categorySource == InventoryCategorySource.global)', '          (hasPublicIdentity &&\n              item.categorySource == InventoryCategorySource.home &&\n              (item.catalogName == null || item.catalogCategoryId == null)) ||\n          (hasPrivateIdentity &&\n              item.categorySource == InventoryCategorySource.global &&\n              item.globalCategoryId != item.categoryId)')
    c=c.replace('          canonicalName: item.canonicalName,','          canonicalName: item.catalogName ?? item.canonicalName,')
    c=c.replace('          packSize: item.packSize,', "          packSize: item.catalogName == null ? item.packSize\n              : item.catalogPackText == null || item.catalogPackText!.isEmpty\n                  ? 'Unspecified pack' : item.catalogPackText!,")
    c=c.replace('          category: item.category,','          category: item.catalogCategoryName ?? item.category,')
    c=c.replace('          unit: item.unit,', "          unit: 'units',")
    c=c.replace('          categoryId: item.categoryId,\n          homeCategoryId: item.homeCategoryId,\n          categorySource: item.categorySource,', '''          categoryId: item.catalogCategoryId ?? item.categoryId,
          categorySource: (item.catalogCategoryId ?? item.categoryId) == null
              ? null : InventoryCategorySource.global,''')
    c=c.replace('    await _transaction(() async {', '''    final categoryIds = <String>{};
    for (final category in categories ?? const <PublishedInventoryCategory>[]) {
      _requireUuid(category.id, 'global category');
      if (!categoryIds.add(category.id)) {
        throw const FormatException('The published category snapshot contains duplicates.');
      }
    }
    await _transaction(() async {''')
    ending='''      if (categories != null) {
        await (_database.delete(_database.localRecords)..where(
          (row) => row.homeId.equals(homeId) & row.entityType.equals(_publishedCategoryType),
        )).go();
        for (final category in categories) {
          await _writeRecord(
            homeId: homeId, entityType: _publishedCategoryType, entityId: category.id,
            payload: {'homeId': homeId, 'name': category.name, 'revision': category.revision},
          );
        }
      }
'''
    idx=c.rindex('    });'); c=c[:idx]+ending+c[idx:]; s=s[:a]+c+s[b:]
    a=s.index('  List<InventoryItem> _projectInventoryItems('); b=s.index('  StockCountSession? _projectActiveCountSession',a)
    c=s[a:b]; idx=c.index('    final homeCategories')
    c=c[:idx]+'''    final globalCategories = <String, String>{
      for (final row in rows.where((row) => row.entityType == _publishedCategoryType))
        row.entityId: _requiredString(_decodeObject(row.payload, 'published category'), 'name'),
    };
'''+c[idx:]
    c=c.replace('      final usesHomeCategory = homeCategoryId != null;', '''      final selectedGlobalCategoryId = _nullableUuid(payload['globalCategoryId'], 'globalCategoryId');
      if (homeCategoryId != null && selectedGlobalCategoryId != null) {
        throw const FormatException('A product cannot select both category scopes.');
      }
      final inheritedCategoryId = catalogItem?.categoryId ?? _nullableUuid(payload['categoryId'], 'categoryId');
      final inheritedCategoryName = catalogItem?.category ?? _nullableString(payload['categoryName']);
      final usesHomeCategory = homeCategoryId != null;''')
    c=c.replace("          : catalogItem?.category ?? 'Uncategorized';", """          : selectedGlobalCategoryId != null
              ? globalCategories[selectedGlobalCategoryId] ?? 'Unavailable global category'
              : inheritedCategoryName ?? 'Uncategorized';""")
    c=c.replace('            productName ??\n            catalogItem?.canonicalName ??', '            catalogItem?.canonicalName ??\n            productName ??')
    c=c.replace('        category: category,\n        brand:', "        category: category,\n        unit: _optionalString(payload['unit'], fallback: 'units'),\n        brand:")
    c=c.replace('        categoryId: usesHomeCategory ? null : catalogItem?.categoryId,', '''        categoryId: usesHomeCategory ? null : selectedGlobalCategoryId ?? inheritedCategoryId,
        globalCategoryId: selectedGlobalCategoryId,
        catalogName: catalogItem?.canonicalName ?? productName,
        catalogPackText: catalogItem?.packSize,
        catalogCategoryId: inheritedCategoryId,
        catalogCategoryName: inheritedCategoryName,''')
    c=c.replace('            : catalogItem?.categorySource,','            : (selectedGlobalCategoryId ?? inheritedCategoryId) == null ? null : InventoryCategorySource.global,')
    s=s[:a]+c+s[b:]
    fields=['globalCategoryId','catalogName','catalogPackText','catalogCategoryId','catalogCategoryName']
    anchor="  if (item.homeCategoryId != null) 'homeCategoryId': item.homeCategoryId,"
    s=s.replace(anchor,anchor+'\n'+''.join(f"  if (item.{v} != null) '{v}': item.{v},\n" for v in fields))
    a=s.index('InventoryItem _decodeInventoryItem'); b=s.index('Map<String, Object?> _encodeCountSession',a)
    c=s[a:b].replace('    categorySource: categorySource,','    categorySource: categorySource,\n'+''.join(f"    {v}: _nullableString(json['{v}']),\n" for v in fields)); s=s[:a]+c+s[b:]
    return s
edit('lib/core/database/drift_household_repository.dart',database)

def controller(s):
    a=s.index('  InventoryMetadataRepository? get _metadata')
    s=s[:a]+'''  StreamSubscription<List<PublishedInventoryCategory>>? _publishedCategoriesSubscription;
  List<PublishedInventoryCategory> _publishedCategories = const [];
  List<PublishedInventoryCategory> get publishedCategories => _publishedCategories;
'''+s[a:]
    a=s.index('  Future<bool> editProduct({'); b=s.index('  Future<bool> _metadataMutation',a); c=s[a:b]
    c=c.replace('    String? categoryId,','    String? categoryId,\n    String? globalCategoryId,\n    String? unit,')
    c=c.replace('      privateName: name,','      privateName: item.productId != null && name.trim() == item.catalogName\n          ? null : name,')
    c=c.replace('      originalPackText: pack,','      originalPackText: item.productId != null && pack?.trim() == item.catalogPackText\n          ? null : pack,')
    c=c.replace('      homeCategoryId: categoryId,','      homeCategoryId: categoryId,\n      globalCategoryId: globalCategoryId,\n      unit: unit ?? item.unit,')
    s=s[:a]+c+s[b:]
    a=s.index('    _categoriesSubscription = _metadata?.watchHomeCategories')
    s=s[:a]+'''    _publishedCategoriesSubscription = _metadata?.watchPublishedCategories(homeId).listen((rows) {
      _publishedCategories = List.unmodifiable(rows);
      notifyListeners();
    }, onError: (Object _) => _setSafeError('Global categories could not be loaded. Retry synchronization.'));
'''+s[a:]
    s=s.replace('    _categoriesSubscription?.cancel();','    _categoriesSubscription?.cancel();\n    _publishedCategoriesSubscription?.cancel();')
    a=s.index(' createPrivateProduct('); a=s.rfind('  Future',0,a); b=s.index('\n  Future',a+10); c=s[a:b]
    c=c.replace('    String? homeCategoryId,', "    String? homeCategoryId,\n    String? globalCategoryId,\n    String unit = 'units',")
    c=c.replace('        homeCategoryId: homeCategoryId,','        homeCategoryId: homeCategoryId,\n        globalCategoryId: globalCategoryId,\n        unit: unit,')
    s=s[:a]+c+s[b:]
    return s
edit('lib/features/inventory/presentation/inventory_controller.dart',controller)
edit('lib/features/inventory/infrastructure/generated_home_item_master_source.dart',lambda s:s.replace('    homeCategoryId: homeCategoryId,', """    homeCategoryId: homeCategoryId,
    globalCategoryId: _nullableIdentifier(record, 'globalCategoryId'),
    unit: _nullableString(record, 'unit') ?? 'units',
    catalogName: _nullableString(record, 'catalogName'),
    catalogPackText: _nullableString(record, 'catalogPackText'),
    catalogCategoryId: _nullableIdentifier(record, 'catalogCategoryId'),
    catalogCategoryName: _nullableString(record, 'catalogCategoryName'),"""))
