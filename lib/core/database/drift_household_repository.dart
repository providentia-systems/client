import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';

final class BaselineImportReport {
  const BaselineImportReport({
    required this.alreadyImported,
    required this.itemMasterRows,
    required this.currentStockRows,
    required this.currentUnits,
    required this.recentPurchaseRows,
    required this.historicalPurchaseRows,
    required this.monthlyPurchaseRows,
    required this.exactStockMatches,
    required this.unresolvedStockRows,
    required this.unresolvedRecentPurchaseRows,
  });

  final bool alreadyImported;
  final int itemMasterRows;
  final int currentStockRows;
  final double currentUnits;
  final int recentPurchaseRows;
  final int historicalPurchaseRows;
  final int monthlyPurchaseRows;
  final int exactStockMatches;
  final int unresolvedStockRows;
  final int unresolvedRecentPurchaseRows;
}

/// Local fallback for Phase 5–8 controller projections.
///
/// API 1.7 publishes online household resources, but its generic synchronization
/// contract still permits only home preferences and private notes. This adapter
/// therefore preserves the richer controller aggregates locally without adding
/// unsupported entity types to the synchronization outbox. Production-backed
/// online reads and compatible commands live behind the household_sync ports.
final class DriftHouseholdRepository
    implements InventoryRepository, PurchaseRepository, ShoppingRepository {
  DriftHouseholdRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const String _inventoryItemType = 'phase5.inventory-item';
  static const String _countSessionType = 'phase5.stock-count-session';
  static const String _movementType = 'phase5.stock-movement';
  static const String _adjustmentIntentType = 'phase5.adjustment-intent';
  static const String _purchaseLineType = 'phase5.purchase-line';
  static const String _priceObservationType = 'phase8.price-observation';
  static const String _shoppingListType = 'phase5.shopping-list';
  static const String _feedbackType = 'phase8.suggestion-feedback';
  static const String _baselineImportType = 'migration.baseline-v1';
  static const String _baselineSourceType = 'migration.baseline-source-v1';

  final AppDatabase _database;
  final DateTime Function() _clock;

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) {
    return _watchRecords(homeId: homeId, entityType: _inventoryItemType).map(
      (rows) =>
          rows
              .map((row) => _decodeInventoryItem(row.payload))
              .toList(growable: false)
            ..sort((left, right) {
              final category = left.category.compareTo(right.category);
              if (category != 0) return category;
              final name = left.canonicalName.compareTo(right.canonicalName);
              if (name != 0) return name;
              return left.packSize.compareTo(right.packSize);
            }),
    );
  }

  @override
  Stream<StockCountSession?> watchActiveCountSession({required String homeId}) {
    return _watchRecords(homeId: homeId, entityType: _countSessionType).map((
      rows,
    ) {
      final open =
          rows
              .map((row) => _decodeCountSession(row.payload))
              .where((session) => session.status == CountSessionStatus.open)
              .toList(growable: false)
            ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
      return open.isEmpty ? null : open.first;
    });
  }

  @override
  Future<void> saveCountSession(StockCountSession session) {
    return _database.transaction(() async {
      final existing =
          await (_database.select(_database.localRecords)..where(
                (record) =>
                    record.homeId.equals(session.homeId) &
                    record.entityType.equals(_countSessionType) &
                    record.entityId.equals(session.id),
              ))
              .getSingleOrNull();
      final wasOpen =
          existing != null &&
          _decodeCountSession(existing.payload).status ==
              CountSessionStatus.open;

      await _writeRecord(
        homeId: session.homeId,
        entityType: _countSessionType,
        entityId: session.id,
        payload: _encodeCountSession(session),
      );
      if (!wasOpen || session.status != CountSessionStatus.closed) {
        return;
      }

      for (final line in session.confirmedLines) {
        final record =
            await (_database.select(_database.localRecords)..where(
                  (row) =>
                      row.homeId.equals(session.homeId) &
                      row.entityType.equals(_inventoryItemType) &
                      row.entityId.equals(line.itemId),
                ))
                .getSingleOrNull();
        if (record == null) {
          throw StateError('A counted inventory item no longer exists.');
        }
        final item = _decodeInventoryItem(record.payload);
        if (item.homeId != session.homeId) {
          throw StateError('Cross-home count application was rejected.');
        }
        final observed = line.observedQuantity!;
        final previous = item.currentQuantity ?? 0;
        await _writeRecord(
          homeId: session.homeId,
          entityType: _inventoryItemType,
          entityId: item.id,
          payload: _encodeInventoryItem(
            item.copyWith(currentQuantity: observed),
          ),
        );
        final delta = observed - previous;
        if (delta.abs() <= 0.000001) continue;
        final movement = StockMovement(
          id: 'count:${session.id}:${line.id}',
          homeId: session.homeId,
          itemId: item.id,
          locationId: session.locationId,
          quantityDelta: delta,
          kind: StockMovementKind.countAdjustment,
          occurredAt: session.closedAt!,
          sourceId: session.id,
        );
        await _writeRecord(
          homeId: session.homeId,
          entityType: _movementType,
          entityId: movement.id,
          payload: _encodeMovement(movement),
        );
      }
    });
  }

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) {
    return _database.transaction(() async {
      final row =
          await (_database.select(_database.localRecords)..where(
                (record) =>
                    record.homeId.equals(intent.homeId) &
                    record.entityType.equals(_inventoryItemType) &
                    record.entityId.equals(intent.itemId),
              ))
              .getSingleOrNull();
      if (row == null) {
        throw StateError('The inventory item no longer exists.');
      }
      final item = _decodeInventoryItem(row.payload);
      final projected = item.currentQuantity ?? 0;
      if ((projected - intent.projectedQuantity).abs() > 0.000001) {
        throw StateError(
          'The inventory quantity changed before the adjustment was saved.',
        );
      }

      await _writeRecord(
        homeId: intent.homeId,
        entityType: _inventoryItemType,
        entityId: intent.itemId,
        payload: _encodeInventoryItem(
          item.copyWith(currentQuantity: intent.observedQuantity),
        ),
      );
      await _writeRecord(
        homeId: intent.homeId,
        entityType: _adjustmentIntentType,
        entityId: intent.id,
        payload: <String, Object?>{
          'id': intent.id,
          'homeId': intent.homeId,
          'itemId': intent.itemId,
          'locationId': intent.locationId,
          'projectedQuantity': intent.projectedQuantity,
          'observedQuantity': intent.observedQuantity,
          'reason': intent.reason,
          'createdAt': intent.createdAt.toUtc().toIso8601String(),
        },
      );
      if (movement != null) {
        await _writeRecord(
          homeId: movement.homeId,
          entityType: _movementType,
          entityId: movement.id,
          payload: _encodeMovement(movement),
        );
      }
    });
  }

  @override
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId}) {
    return _watchRecords(homeId: homeId, entityType: _purchaseLineType).map(
      (rows) =>
          rows
              .map((row) => _decodePurchaseLine(row.payload))
              .toList(growable: false)
            ..sort(
              (left, right) => right.purchasedAt.compareTo(left.purchasedAt),
            ),
    );
  }

  @override
  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  }) {
    return _watchRecords(homeId: homeId, entityType: _priceObservationType).map(
      (rows) =>
          rows
              .map((row) => _decodePriceObservation(row.payload))
              .where(
                (observation) =>
                    productPackId == null ||
                    observation.productPackId == productPackId,
              )
              .toList(growable: false)
            ..sort(
              (left, right) => right.observedAt.compareTo(left.observedAt),
            ),
    );
  }

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) {
    return _watchRecords(homeId: homeId, entityType: _shoppingListType).map((
      rows,
    ) {
      if (rows.isEmpty) {
        return ShoppingList(
          id: 'manual-list:$homeId',
          homeId: homeId,
          name: 'Shopping list',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
      }
      final lists =
          rows
              .map((row) => _decodeShoppingList(row.payload))
              .toList(growable: false)
            ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      return lists.first;
    });
  }

  @override
  Future<void> saveList(ShoppingList list) {
    return _database.transaction(
      () => _writeRecord(
        homeId: list.homeId,
        entityType: _shoppingListType,
        entityId: list.id,
        payload: _encodeShoppingList(list),
      ),
    );
  }

  @override
  Future<void> recordFeedback(SuggestionFeedback feedback) {
    return _database.transaction(
      () => _writeRecord(
        homeId: feedback.homeId,
        entityType: _feedbackType,
        entityId: feedback.id,
        payload: <String, Object?>{
          'id': feedback.id,
          'homeId': feedback.homeId,
          'productPackId': feedback.productPackId,
          'kind': feedback.kind.name,
          'recordedAt': feedback.recordedAt.toUtc().toIso8601String(),
          'originalQuantity': feedback.originalQuantity,
          'updatedQuantity': feedback.updatedQuantity,
        },
      ),
    );
  }

  Future<void> ensureHomeInitialized({required String homeId}) async {
    final listId = 'manual-list:$homeId';
    final existing =
        await (_database.select(_database.localRecords)..where(
              (row) =>
                  row.homeId.equals(homeId) &
                  row.entityType.equals(_shoppingListType) &
                  row.entityId.equals(listId),
            ))
            .getSingleOrNull();
    if (existing != null) return;

    await saveList(
      ShoppingList(
        id: listId,
        homeId: homeId,
        name: 'Shopping list',
        createdAt: _clock().toUtc(),
      ),
    );
  }

  Future<BaselineImportReport> importBaseline({
    required String homeId,
    required String encodedPantryData,
    required String encodedProductRules,
    String importId = 'providentia-baseline-v1',
  }) async {
    final marker =
        await (_database.select(_database.localRecords)..where(
              (row) =>
                  row.homeId.equals(homeId) &
                  row.entityType.equals(_baselineImportType) &
                  row.entityId.equals(importId),
            ))
            .getSingleOrNull();
    if (marker != null) {
      return _decodeImportReport(marker.payload, alreadyImported: true);
    }

    final pantryData = _decodeObject(encodedPantryData, 'pantry data');
    final productRules = _decodeObject(encodedProductRules, 'product rules');
    final itemRows = _objectList(pantryData['itemMaster'], 'itemMaster');
    final stockRows = _objectList(pantryData['currentStock'], 'currentStock');
    final recentRows = _objectList(pantryData['purchases'], 'purchases');
    final historyRows = _objectList(pantryData['history'], 'history');
    final monthlyRows = _objectList(
      pantryData['monthlyPurchases'],
      'monthlyPurchases',
    );
    _requireBaselineCount(itemRows.length, 292, 'itemMaster');
    _requireBaselineCount(stockRows.length, 60, 'currentStock');
    _requireBaselineCount(recentRows.length, 16, 'purchases');
    _requireBaselineCount(historyRows.length, 452, 'history');
    _requireBaselineCount(monthlyRows.length, 261, 'monthlyPurchases');

    final aliasGroups = _objectMap(productRules['aliases'], 'aliases');
    final aliasesByProduct = <String, List<String>>{};
    for (final entry in aliasGroups.entries) {
      aliasesByProduct[_normalize(entry.key)] = _stringList(
        entry.value,
        'aliases.${entry.key}',
      );
    }
    _requireBaselineCount(aliasGroups.length, 13, 'alias groups');
    _requireBaselineCount(
      aliasesByProduct.values.fold<int>(
        0,
        (total, aliases) => total + aliases.length,
      ),
      19,
      'aliases',
    );
    _requireBaselineCount(
      _objectList(productRules['identityRules'], 'identityRules').length,
      19,
      'identityRules',
    );
    _requireBaselineCount(
      _stringList(
        productRules['unresolvedCurrentStock'],
        'unresolvedCurrentStock',
      ).length,
      8,
      'unresolvedCurrentStock',
    );

    final itemCandidates = <String, List<InventoryItem>>{};
    for (final row in itemRows) {
      final product = _requiredString(row, 'product');
      final packSize = _requiredString(row, 'packSize');
      final item = InventoryItem(
        id: _requiredString(row, 'id'),
        homeId: homeId,
        canonicalName: product,
        packSize: packSize,
        category: _requiredString(row, 'category'),
        brand: _optionalString(row['brand']),
        unit: _optionalString(row['unit'], fallback: 'units'),
        aliases: aliasesByProduct[_normalize(product)] ?? const <String>[],
      );
      itemCandidates
          .putIfAbsent(
            _productPackKey(product, packSize),
            () => <InventoryItem>[],
          )
          .add(item);
    }

    var exactStockMatches = 0;
    var currentUnits = 0.0;
    final importedItems = <String, InventoryItem>{
      for (final candidates in itemCandidates.values)
        for (final item in candidates) item.id: item,
    };
    for (final row in stockRows) {
      final product = _requiredString(row, 'product');
      final packSize = _requiredString(row, 'packSize');
      final quantity = _requiredNumber(row, 'quantity');
      currentUnits += quantity;
      final matches =
          itemCandidates[_productPackKey(product, packSize)] ??
          const <InventoryItem>[];
      if (matches.length == 1) {
        exactStockMatches++;
        importedItems[matches.single.id] = matches.single.copyWith(
          currentQuantity: quantity,
        );
      } else {
        final sourceId = _requiredString(row, 'id');
        importedItems['baseline-$sourceId'] = InventoryItem(
          id: 'baseline-$sourceId',
          homeId: homeId,
          canonicalName: product,
          packSize: packSize,
          category: _requiredString(row, 'category'),
          brand: _optionalString(row['brand']),
          unit: _optionalString(row['unit'], fallback: 'units'),
          currentQuantity: quantity,
          isHomeProduct: true,
        );
      }
    }
    if ((currentUnits - 159).abs() > 0.000001) {
      throw const FormatException(
        'The baseline current-stock quantity must total 159.',
      );
    }

    final purchaseLines = <PurchaseLine>[];
    var unresolvedRecentPurchaseRows = 0;
    for (final row in recentRows) {
      final rawProduct = _requiredString(row, 'product');
      final canonicalName = _optionalString(row['canonicalItem']);
      final canonicalPack = _optionalString(row['canonicalPackSize']);
      final matches = canonicalName.isEmpty || canonicalPack.isEmpty
          ? const <InventoryItem>[]
          : itemCandidates[_productPackKey(canonicalName, canonicalPack)] ??
                const <InventoryItem>[];
      if (matches.length != 1) unresolvedRecentPurchaseRows++;
      purchaseLines.add(
        PurchaseLine(
          id: _requiredString(row, 'id'),
          homeId: homeId,
          purchasedAt: _parseDateOnly(_requiredString(row, 'date')),
          datePrecision: PurchaseDatePrecision.exactDay,
          storeName: _requiredString(row, 'store'),
          rawDescription: rawProduct,
          packSize: _requiredString(row, 'packSize'),
          quantity: _requiredNumber(row, 'quantity'),
          source: PurchaseSource.recentReceipt,
          canonicalItemId: matches.length == 1 ? matches.single.id : null,
          canonicalName: canonicalName.isEmpty ? null : canonicalName,
          lineTotal: Money(
            minorUnits: (_requiredNumber(row, 'totalCost') * 100).round(),
            currency: 'NAD',
          ),
        ),
      );
    }
    for (final row in historyRows) {
      final canonicalName = _optionalString(row['canonicalItem']);
      final canonicalPack = _optionalString(row['canonicalPackSize']);
      final matches = canonicalName.isEmpty || canonicalPack.isEmpty
          ? const <InventoryItem>[]
          : itemCandidates[_productPackKey(canonicalName, canonicalPack)] ??
                const <InventoryItem>[];
      purchaseLines.add(
        PurchaseLine(
          id: _requiredString(row, 'id'),
          homeId: homeId,
          purchasedAt: _parseDateOnly(_requiredString(row, 'date')),
          datePrecision: PurchaseDatePrecision.monthOnly,
          storeName: 'Historical import',
          rawDescription: _requiredString(row, 'fullName'),
          packSize: _requiredString(row, 'size'),
          quantity: _requiredNumber(row, 'quantity'),
          source: PurchaseSource.historicalImport,
          canonicalItemId: matches.length == 1 ? matches.single.id : null,
          canonicalName: canonicalName.isEmpty ? null : canonicalName,
        ),
      );
    }

    final report = BaselineImportReport(
      alreadyImported: false,
      itemMasterRows: itemRows.length,
      currentStockRows: stockRows.length,
      currentUnits: currentUnits,
      recentPurchaseRows: recentRows.length,
      historicalPurchaseRows: historyRows.length,
      monthlyPurchaseRows: monthlyRows.length,
      exactStockMatches: exactStockMatches,
      unresolvedStockRows: stockRows.length - exactStockMatches,
      unresolvedRecentPurchaseRows: unresolvedRecentPurchaseRows,
    );

    await _database.transaction(() async {
      for (final item in importedItems.values) {
        await _writeRecord(
          homeId: homeId,
          entityType: _inventoryItemType,
          entityId: item.id,
          payload: _encodeInventoryItem(item),
        );
      }
      for (final line in purchaseLines) {
        await _writeRecord(
          homeId: homeId,
          entityType: _purchaseLineType,
          entityId: line.id,
          payload: _encodePurchaseLine(line),
        );
        if (line.lineTotal != null && line.canonicalItemId != null) {
          final observation = PriceObservation(
            id: 'price:${line.id}',
            homeId: homeId,
            productPackId: line.canonicalItemId!,
            storeName: line.storeName,
            observedAt: line.purchasedAt,
            quantity: line.quantity,
            total: line.lineTotal!,
          );
          await _writeRecord(
            homeId: homeId,
            entityType: _priceObservationType,
            entityId: observation.id,
            payload: _encodePriceObservation(observation),
          );
        }
      }
      await _writeRecord(
        homeId: homeId,
        entityType: _shoppingListType,
        entityId: 'manual-list:$homeId',
        payload: _encodeShoppingList(
          ShoppingList(
            id: 'manual-list:$homeId',
            homeId: homeId,
            name: 'Shopping list',
            createdAt: _clock().toUtc(),
          ),
        ),
      );
      await _writeRecord(
        homeId: homeId,
        entityType: _baselineSourceType,
        entityId: importId,
        payload: <String, Object?>{
          // Preserve source material needed for later audit/reconciliation
          // without bundling the household's private baseline into the app.
          'monthlyPurchases': monthlyRows,
          'productRules': productRules,
        },
      );
      await _writeRecord(
        homeId: homeId,
        entityType: _baselineImportType,
        entityId: importId,
        payload: _encodeImportReport(report),
      );
    });
    return report;
  }

  Stream<List<LocalRecord>> _watchRecords({
    required String homeId,
    required String entityType,
  }) {
    final query = _database.select(_database.localRecords)
      ..where(
        (row) => row.homeId.equals(homeId) & row.entityType.equals(entityType),
      );
    return query.watch();
  }

  Future<void> _writeRecord({
    required String homeId,
    required String entityType,
    required String entityId,
    required Object payload,
  }) {
    return _database
        .into(_database.localRecords)
        .insertOnConflictUpdate(
          LocalRecordsCompanion.insert(
            homeId: homeId,
            entityType: entityType,
            entityId: entityId,
            payload: jsonEncode(payload),
            updatedAt: _clock().toUtc(),
          ),
        );
  }
}

Map<String, Object?> _encodeInventoryItem(InventoryItem item) =>
    <String, Object?>{
      'id': item.id,
      'homeId': item.homeId,
      'canonicalName': item.canonicalName,
      'packSize': item.packSize,
      'category': item.category,
      'brand': item.brand,
      'unit': item.unit,
      'aliases': item.aliases,
      'currentQuantity': item.currentQuantity,
      'isHomeProduct': item.isHomeProduct,
    };

InventoryItem _decodeInventoryItem(String encoded) {
  final json = _decodeObject(encoded, 'inventory item');
  return InventoryItem(
    id: _requiredString(json, 'id'),
    homeId: _requiredString(json, 'homeId'),
    canonicalName: _requiredString(json, 'canonicalName'),
    packSize: _requiredString(json, 'packSize'),
    category: _requiredString(json, 'category'),
    brand: _optionalString(json['brand']),
    unit: _optionalString(json['unit'], fallback: 'units'),
    aliases: _stringList(json['aliases'], 'aliases'),
    currentQuantity: _optionalNumber(json['currentQuantity']),
    isHomeProduct: json['isHomeProduct'] == true,
  );
}

Map<String, Object?> _encodeCountSession(StockCountSession session) =>
    <String, Object?>{
      'id': session.id,
      'homeId': session.homeId,
      'locationId': session.locationId,
      'startedAt': session.startedAt.toUtc().toIso8601String(),
      'status': session.status.name,
      'closedAt': session.closedAt?.toUtc().toIso8601String(),
      'photos': session.photos
          .map(
            (photo) => <String, Object?>{
              'id': photo.id,
              'localReference': photo.localReference,
              'addedAt': photo.addedAt.toUtc().toIso8601String(),
              'name': photo.name,
              'mimeType': photo.mimeType,
            },
          )
          .toList(growable: false),
      'lines': session.lines
          .map(
            (line) => <String, Object?>{
              'id': line.id,
              'itemId': line.itemId,
              'status': line.status.name,
              'source': line.source.name,
              'observedQuantity': line.observedQuantity,
              'photoId': line.photoId,
              'possibleDuplicate': line.possibleDuplicate,
              'duplicateReviewed': line.duplicateReviewed,
            },
          )
          .toList(growable: false),
    };

StockCountSession _decodeCountSession(String encoded) {
  final json = _decodeObject(encoded, 'stock count session');
  return StockCountSession(
    id: _requiredString(json, 'id'),
    homeId: _requiredString(json, 'homeId'),
    locationId: _requiredString(json, 'locationId'),
    startedAt: DateTime.parse(_requiredString(json, 'startedAt')).toUtc(),
    status: CountSessionStatus.values.byName(_requiredString(json, 'status')),
    closedAt: _optionalDateTime(json['closedAt']),
    photos: _objectList(json['photos'], 'photos')
        .map(
          (photo) => StockPhotoReference(
            id: _requiredString(photo, 'id'),
            localReference: _requiredString(photo, 'localReference'),
            addedAt: DateTime.parse(_requiredString(photo, 'addedAt')).toUtc(),
            name: _optionalString(photo['name']),
            mimeType: _nullableString(photo['mimeType']),
          ),
        )
        .toList(growable: false),
    lines: _objectList(json['lines'], 'lines')
        .map(
          (line) => StockCountLine(
            id: _requiredString(line, 'id'),
            itemId: _requiredString(line, 'itemId'),
            status: CountLineStatus.values.byName(
              _requiredString(line, 'status'),
            ),
            source: CountSource.values.byName(_requiredString(line, 'source')),
            observedQuantity: _optionalNumber(line['observedQuantity']),
            photoId: _nullableString(line['photoId']),
            possibleDuplicate: line['possibleDuplicate'] == true,
            duplicateReviewed: line['duplicateReviewed'] == true,
          ),
        )
        .toList(growable: false),
  );
}

Map<String, Object?> _encodeMovement(StockMovement movement) =>
    <String, Object?>{
      'id': movement.id,
      'homeId': movement.homeId,
      'itemId': movement.itemId,
      'locationId': movement.locationId,
      'quantityDelta': movement.quantityDelta,
      'kind': movement.kind.name,
      'occurredAt': movement.occurredAt.toUtc().toIso8601String(),
      'sourceId': movement.sourceId,
      'reason': movement.reason,
      'reversalOf': movement.reversalOf,
    };

Map<String, Object?> _encodePurchaseLine(PurchaseLine line) =>
    <String, Object?>{
      'id': line.id,
      'homeId': line.homeId,
      'purchasedAt': line.purchasedAt.toUtc().toIso8601String(),
      'datePrecision': line.datePrecision.name,
      'storeName': line.storeName,
      'rawDescription': line.rawDescription,
      'packSize': line.packSize,
      'quantity': line.quantity,
      'source': line.source.name,
      'receiptId': line.receiptId,
      'canonicalItemId': line.canonicalItemId,
      'canonicalName': line.canonicalName,
      'lineTotalMinorUnits': line.lineTotal?.minorUnits,
      'lineTotalCurrency': line.lineTotal?.currency,
    };

PurchaseLine _decodePurchaseLine(String encoded) {
  final json = _decodeObject(encoded, 'purchase line');
  final minorUnits = json['lineTotalMinorUnits'];
  final currency = json['lineTotalCurrency'];
  return PurchaseLine(
    id: _requiredString(json, 'id'),
    homeId: _requiredString(json, 'homeId'),
    purchasedAt: DateTime.parse(_requiredString(json, 'purchasedAt')).toUtc(),
    datePrecision: PurchaseDatePrecision.values.byName(
      _requiredString(json, 'datePrecision'),
    ),
    storeName: _requiredString(json, 'storeName'),
    rawDescription: _requiredString(json, 'rawDescription'),
    packSize: _requiredString(json, 'packSize'),
    quantity: _requiredNumber(json, 'quantity'),
    source: PurchaseSource.values.byName(_requiredString(json, 'source')),
    receiptId: _nullableString(json['receiptId']),
    canonicalItemId: _nullableString(json['canonicalItemId']),
    canonicalName: _nullableString(json['canonicalName']),
    lineTotal: minorUnits is num && currency is String
        ? Money(minorUnits: minorUnits.toInt(), currency: currency)
        : null,
  );
}

Map<String, Object?> _encodePriceObservation(PriceObservation observation) =>
    <String, Object?>{
      'id': observation.id,
      'homeId': observation.homeId,
      'productPackId': observation.productPackId,
      'storeName': observation.storeName,
      'observedAt': observation.observedAt.toUtc().toIso8601String(),
      'quantity': observation.quantity,
      'baseUnitsPerPurchasedUnit': observation.baseUnitsPerPurchasedUnit,
      'totalMinorUnits': observation.total.minorUnits,
      'currency': observation.total.currency,
      'isSale': observation.isSale,
    };

PriceObservation _decodePriceObservation(String encoded) {
  final json = _decodeObject(encoded, 'price observation');
  return PriceObservation(
    id: _requiredString(json, 'id'),
    homeId: _requiredString(json, 'homeId'),
    productPackId: _requiredString(json, 'productPackId'),
    storeName: _requiredString(json, 'storeName'),
    observedAt: DateTime.parse(_requiredString(json, 'observedAt')).toUtc(),
    quantity: _requiredNumber(json, 'quantity'),
    baseUnitsPerPurchasedUnit: _requiredNumber(
      json,
      'baseUnitsPerPurchasedUnit',
    ),
    total: Money(
      minorUnits: _requiredNumber(json, 'totalMinorUnits').toInt(),
      currency: _requiredString(json, 'currency'),
    ),
    isSale: json['isSale'] == true,
  );
}

Map<String, Object?> _encodeShoppingList(ShoppingList list) =>
    <String, Object?>{
      'id': list.id,
      'homeId': list.homeId,
      'name': list.name,
      'createdAt': list.createdAt.toUtc().toIso8601String(),
      'lines': list.lines
          .map(
            (line) => <String, Object?>{
              'id': line.id,
              'homeId': line.homeId,
              'name': line.name,
              'quantity': line.quantity,
              'origin': line.origin.name,
              'createdAt': line.createdAt.toUtc().toIso8601String(),
              'productPackId': line.productPackId,
              'checked': line.checked,
              'explanation': line.explanation,
            },
          )
          .toList(growable: false),
    };

ShoppingList _decodeShoppingList(String encoded) {
  final json = _decodeObject(encoded, 'shopping list');
  return ShoppingList(
    id: _requiredString(json, 'id'),
    homeId: _requiredString(json, 'homeId'),
    name: _requiredString(json, 'name'),
    createdAt: DateTime.parse(_requiredString(json, 'createdAt')).toUtc(),
    lines: _objectList(json['lines'], 'lines')
        .map(
          (line) => ShoppingListLine(
            id: _requiredString(line, 'id'),
            homeId: _requiredString(line, 'homeId'),
            name: _requiredString(line, 'name'),
            quantity: _requiredNumber(line, 'quantity'),
            origin: ShoppingLineOrigin.values.byName(
              _requiredString(line, 'origin'),
            ),
            createdAt: DateTime.parse(
              _requiredString(line, 'createdAt'),
            ).toUtc(),
            productPackId: _nullableString(line['productPackId']),
            checked: line['checked'] == true,
            explanation: _nullableString(line['explanation']),
          ),
        )
        .toList(growable: false),
  );
}

Map<String, Object?> _encodeImportReport(BaselineImportReport report) =>
    <String, Object?>{
      'itemMasterRows': report.itemMasterRows,
      'currentStockRows': report.currentStockRows,
      'currentUnits': report.currentUnits,
      'recentPurchaseRows': report.recentPurchaseRows,
      'historicalPurchaseRows': report.historicalPurchaseRows,
      'monthlyPurchaseRows': report.monthlyPurchaseRows,
      'exactStockMatches': report.exactStockMatches,
      'unresolvedStockRows': report.unresolvedStockRows,
      'unresolvedRecentPurchaseRows': report.unresolvedRecentPurchaseRows,
    };

BaselineImportReport _decodeImportReport(
  String encoded, {
  required bool alreadyImported,
}) {
  final json = _decodeObject(encoded, 'baseline import report');
  return BaselineImportReport(
    alreadyImported: alreadyImported,
    itemMasterRows: _requiredNumber(json, 'itemMasterRows').toInt(),
    currentStockRows: _requiredNumber(json, 'currentStockRows').toInt(),
    currentUnits: _requiredNumber(json, 'currentUnits'),
    recentPurchaseRows: _requiredNumber(json, 'recentPurchaseRows').toInt(),
    historicalPurchaseRows: _requiredNumber(
      json,
      'historicalPurchaseRows',
    ).toInt(),
    monthlyPurchaseRows: _requiredNumber(json, 'monthlyPurchaseRows').toInt(),
    exactStockMatches: _requiredNumber(json, 'exactStockMatches').toInt(),
    unresolvedStockRows: _requiredNumber(json, 'unresolvedStockRows').toInt(),
    unresolvedRecentPurchaseRows: _requiredNumber(
      json,
      'unresolvedRecentPurchaseRows',
    ).toInt(),
  );
}

Map<String, Object?> _decodeObject(String encoded, String name) {
  final decoded = jsonDecode(encoded);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('$name must be a JSON object.');
  }
  return decoded;
}

Map<String, Object?> _objectMap(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object.');
  }
  return value;
}

List<Map<String, Object?>> _objectList(Object? value, String name) {
  if (value is! List<Object?>) {
    throw FormatException('$name must be an array.');
  }
  return value
      .map((entry) {
        if (entry is! Map<String, Object?>) {
          throw FormatException('$name entries must be objects.');
        }
        return entry;
      })
      .toList(growable: false);
}

List<String> _stringList(Object? value, String name) {
  if (value is! List<Object?>) {
    throw FormatException('$name must be an array.');
  }
  return value
      .map((entry) {
        if (entry is! String || entry.trim().isEmpty) {
          throw FormatException('$name entries must be non-empty strings.');
        }
        return entry;
      })
      .toList(growable: false);
}

String _requiredString(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$name must be a non-empty string.');
  }
  return value;
}

String _optionalString(Object? value, {String fallback = ''}) =>
    value is String && value.trim().isNotEmpty ? value : fallback;

String? _nullableString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

double _requiredNumber(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('$name must be a finite number.');
  }
  return value.toDouble();
}

double? _optionalNumber(Object? value) =>
    value is num && value.toDouble().isFinite ? value.toDouble() : null;

DateTime? _optionalDateTime(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.parse(value).toUtc() : null;

DateTime _parseDateOnly(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) {
    throw const FormatException('date must use the YYYY-MM-DD format.');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw const FormatException('date must be a valid calendar day.');
  }
  return parsed;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

String _productPackKey(String product, String packSize) =>
    '${_normalize(product)}\u0000${_normalize(packSize)}';

void _requireBaselineCount(int actual, int expected, String name) {
  if (actual != expected) {
    throw FormatException(
      '$name must contain $expected records; received $actual.',
    );
  }
}
