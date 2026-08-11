import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
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

/// Local-first current pinned API projection and protocol-v2 command adapter.
///
/// Server change-feed representations and client commands deliberately use
/// different shapes. This repository materializes the former for controllers
/// while atomically recording the latter in the durable synchronization outbox.
final class DriftHouseholdRepository
    implements
        InventoryProductCreationRepository,
        PurchaseCaptureRepository,
        ShoppingRepository {
  factory DriftHouseholdRepository(
    AppDatabase database, {
    DateTime Function()? clock,
    String? deviceId,
    String Function()? idGenerator,
    Future<void> Function()? onMutationCommitted,
  }) {
    if (deviceId != null && !isUuid(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'must be a UUID');
    }
    if (deviceId == null && onMutationCommitted != null) {
      throw ArgumentError(
        'A foreground synchronization trigger requires a device identity.',
      );
    }
    return DriftHouseholdRepository._(
      database,
      clock ?? DateTime.now,
      deviceId,
      idGenerator ?? UuidV4Generator().call,
      onMutationCommitted,
    );
  }

  DriftHouseholdRepository._(
    this._database,
    this._clock,
    this._deviceId,
    this._idGenerator,
    this._onMutationCommitted,
  );

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

  static const String _homeProductType = 'inventory-home-product';
  static const String _balanceType = 'inventory-balance';
  static const String _serverCountSessionType = 'inventory-count-session';
  static const String _serverCountLineType = 'inventory-count-line';
  static const String _storeType = 'purchasing-store';
  static const String _receiptType = 'purchasing-receipt';
  static const String _receiptLineType = 'purchasing-receipt-line';
  static const String _serverShoppingListType = 'shopping-list';
  static const String _serverShoppingLineType = 'shopping-list-line';

  final AppDatabase _database;
  final DateTime Function() _clock;
  final String? _deviceId;
  final String Function() _idGenerator;
  final Future<void> Function()? _onMutationCommitted;
  final Map<String, String> _emptyShoppingListIds = <String, String>{};

  bool get _synchronizesMutations => _deviceId != null;

  @override
  bool get supportsPrivateHomeProductCreation => _synchronizesMutations;

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) {
    return _watchRecordTypes(
      homeId: homeId,
      entityTypes: const <String>{
        _inventoryItemType,
        _homeProductType,
        _balanceType,
      },
    ).map((rows) => _projectInventoryItems(homeId, rows));
  }

  @override
  Future<InventoryProductCreationResult> createPrivateHomeProduct(
    PrivateHomeProductDraft draft,
  ) async {
    if (!_synchronizesMutations) {
      throw const InventoryProductCreationException(
        'Private product creation requires the synchronized household workspace.',
      );
    }
    _requireHomeUuid(draft.homeId);
    final privateName = draft.privateName.trim();
    final originalPackText = _trimToNull(draft.originalPackText);
    final at = _clock().toUtc();
    final result = await _database.transaction<InventoryProductCreationResult>(
      () async {
        final homeProductId = _nextUuid('private home product');
        final representation = <String, Object?>{
          'productId': null,
          'packId': null,
          'privateName': privateName,
          'originalPackText': originalPackText,
          'status': 'active',
        };
        await _writeProjection(
          homeId: draft.homeId,
          entityType: _homeProductType,
          entityId: homeProductId,
          revision: 1,
          representation: representation,
          at: at,
        );
        await _insertGeneratedCommand(
          homeId: draft.homeId,
          entityType: _homeProductType,
          entityId: homeProductId,
          commandType: 'inventory.home-product.create',
          baseRevision: null,
          payload: <String, Object?>{
            'productId': null,
            'packId': null,
            'privateName': privateName,
            'originalPackText': originalPackText,
          },
          at: at,
        );
        return InventoryProductCreationResult(
          homeProductId: homeProductId,
          revision: 1,
          disposition: InventoryProductCreationDisposition.queued,
        );
      },
    );
    _triggerForegroundSync();
    return result;
  }

  @override
  Stream<StockCountSession?> watchActiveCountSession({required String homeId}) {
    return _watchRecordTypes(
      homeId: homeId,
      entityTypes: const <String>{
        _countSessionType,
        _serverCountSessionType,
        _serverCountLineType,
      },
    ).map((rows) => _projectActiveCountSession(homeId, rows));
  }

  @override
  Future<void> saveCountSession(StockCountSession session) {
    if (_synchronizesMutations) {
      return _saveSynchronizedCountSession(session);
    }
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
    if (_synchronizesMutations) {
      return _commitSynchronizedManualAdjustment(
        intent: intent,
        movement: movement,
      );
    }
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
    return _watchRecordTypes(
      homeId: homeId,
      entityTypes: const <String>{
        _purchaseLineType,
        _storeType,
        _receiptType,
        _receiptLineType,
        _homeProductType,
      },
    ).map((rows) => _projectPurchaseLines(homeId, rows));
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
  Stream<PurchaseReceiptCapture?> watchActiveReceiptCapture({
    required String homeId,
  }) {
    return _watchRecordTypes(
      homeId: homeId,
      entityTypes: const <String>{_receiptType, _receiptLineType, _storeType},
    ).map((rows) => _projectActiveReceiptCapture(homeId, rows));
  }

  @override
  Stream<List<PurchaseMatchCandidate>> watchPurchaseMatchCandidates({
    required String homeId,
  }) {
    return _watchRecords(
      homeId: homeId,
      entityType: _homeProductType,
    ).map((rows) => _projectPurchaseMatchCandidates(homeId, rows));
  }

  @override
  Future<PurchaseMutationResult> createReceiptDraft(
    PurchaseReceiptDraftRequest request,
  ) async {
    _requireSynchronizedPurchasing();
    _requireHomeUuid(request.homeId);
    final storeId = request.storeId;
    if (storeId != null) {
      _requireUuid(storeId, 'purchase store');
    }
    final purchaseDate = _dateOnly(request.purchaseDate);
    final currency = request.currency.trim().toUpperCase();
    final notes = request.notes.trim();
    final sourceReference = _trimToNull(request.sourceReference);
    final totalAmount = request.total == null
        ? null
        : _moneyDecimal(request.total!);
    final at = _clock().toUtc();
    final result = await _database.transaction<PurchaseMutationResult>(() async {
      if (await _activeReceiptRecord(homeId: request.homeId) != null) {
        throw const PurchaseCaptureException(
          'Finish or synchronize the current receipt before starting another.',
        );
      }
      if (storeId != null) {
        final store = await _record(
          homeId: request.homeId,
          entityType: _storeType,
          entityId: storeId,
        );
        if (store == null ||
            _optionalString(
                  _validatedProjection(store, request.homeId)['status'],
                  fallback: 'active',
                ) !=
                'active') {
          throw const PurchaseCaptureException(
            'The selected store is unavailable in this home.',
          );
        }
      }
      final receiptId = _nextUuid('purchase receipt');
      final representation = <String, Object?>{
        'storeId': storeId,
        'purchaseDate': purchaseDate,
        'currency': currency,
        'totalAmount': totalAmount,
        'status': 'draft',
        'source': 'manual',
        'sourceReference': sourceReference,
        // Receipt text is written only to this home-scoped private resource.
        'notes': notes,
        '_clientCreatedAt': at.toIso8601String(),
      };
      await _writeProjection(
        homeId: request.homeId,
        entityType: _receiptType,
        entityId: receiptId,
        revision: 1,
        representation: representation,
        at: at,
      );
      await _insertGeneratedCommand(
        homeId: request.homeId,
        entityType: _receiptType,
        entityId: receiptId,
        commandType: 'purchasing.receipt.create',
        baseRevision: null,
        payload: <String, Object?>{
          'storeId': storeId,
          'purchaseDate': purchaseDate,
          'currency': currency,
          'totalAmount': totalAmount,
          'notes': notes,
          'sourceReference': sourceReference,
        },
        at: at,
      );
      return PurchaseMutationResult(
        entityId: receiptId,
        revision: 1,
        disposition: PurchaseMutationDisposition.queued,
      );
    });
    _triggerForegroundSync();
    return result;
  }

  @override
  Future<PurchaseMutationResult> addReceiptLine(
    PurchaseReceiptLineRequest request,
  ) async {
    _requireSynchronizedPurchasing();
    _requireHomeUuid(request.homeId);
    _requireUuid(request.receiptId, 'purchase receipt');
    final at = _clock().toUtc();
    final result = await _database.transaction<PurchaseMutationResult>(
      () async {
        final receipt = await _requiredDraftReceipt(
          homeId: request.homeId,
          receiptId: request.receiptId,
        );
        final receiptPayload = _validatedProjection(receipt, request.homeId);
        final currency = _requiredString(receiptPayload, 'currency');
        _requireRequestMoneyCurrency(request.unitPrice, currency);
        _requireRequestMoneyCurrency(request.lineTotal, currency);
        final lineId = _nextUuid('purchase receipt line');
        final rawDescription = request.rawDescription.trim();
        final originalPackText = _trimToNull(request.originalPackText);
        final unitPrice = request.unitPrice == null
            ? null
            : _moneyDecimal(request.unitPrice!);
        final lineTotal = request.lineTotal == null
            ? null
            : _moneyDecimal(request.lineTotal!);
        final lineRepresentation = <String, Object?>{
          'receiptId': request.receiptId,
          // Raw text remains within this home-private receipt projection.
          'rawDescription': rawDescription,
          'quantity': _decimal(request.quantity),
          'originalPackText': originalPackText,
          'unitPrice': unitPrice,
          'lineTotal': lineTotal,
          'homeProductId': null,
          'approvalStatus': 'unreviewed',
        };
        await _writeProjection(
          homeId: request.homeId,
          entityType: _receiptLineType,
          entityId: lineId,
          revision: 1,
          representation: lineRepresentation,
          at: at,
        );
        await _writeProjection(
          homeId: request.homeId,
          entityType: _receiptType,
          entityId: request.receiptId,
          revision: receipt.revision + 1,
          representation: _withoutProjectionMetadata(receiptPayload),
          at: at,
        );
        await _insertGeneratedCommand(
          homeId: request.homeId,
          entityType: _receiptLineType,
          entityId: lineId,
          commandType: 'purchasing.receipt-line.create',
          baseRevision: receipt.revision,
          payload: <String, Object?>{
            'receiptId': request.receiptId,
            'rawDescription': rawDescription,
            'quantity': _decimal(request.quantity),
            'originalPackText': originalPackText,
            'unitPrice': unitPrice,
            'lineTotal': lineTotal,
          },
          at: at,
        );
        return PurchaseMutationResult(
          entityId: lineId,
          revision: 1,
          disposition: PurchaseMutationDisposition.queued,
        );
      },
    );
    _triggerForegroundSync();
    return result;
  }

  @override
  Future<PurchaseMutationResult> approveReceiptLine({
    required String homeId,
    required String receiptId,
    required String lineId,
    required String homeProductId,
  }) async {
    _requireSynchronizedPurchasing();
    _requireHomeUuid(homeId);
    _requireUuid(receiptId, 'purchase receipt');
    _requireUuid(lineId, 'purchase receipt line');
    _requireUuid(homeProductId, 'purchase home product');
    final at = _clock().toUtc();
    final result = await _database.transaction<PurchaseMutationResult>(
      () async {
        final receipt = await _requiredDraftReceipt(
          homeId: homeId,
          receiptId: receiptId,
        );
        final line = await _record(
          homeId: homeId,
          entityType: _receiptLineType,
          entityId: lineId,
        );
        if (line == null) {
          throw const PurchaseCaptureException(
            'The receipt line is unavailable in this home.',
          );
        }
        final linePayload = _validatedProjection(line, homeId);
        if (_requiredString(linePayload, 'receiptId') != receiptId) {
          throw const PurchaseCaptureException(
            'The receipt line does not belong to this receipt.',
          );
        }
        final product = await _record(
          homeId: homeId,
          entityType: _homeProductType,
          entityId: homeProductId,
        );
        if (product == null ||
            _optionalString(
                  _validatedProjection(product, homeId)['status'],
                  fallback: 'active',
                ) !=
                'active') {
          throw const PurchaseCaptureException(
            'The selected product is unavailable in this home.',
          );
        }
        final approvalStatus = _requiredString(linePayload, 'approvalStatus');
        if (approvalStatus == 'approved') {
          if (_nullableString(linePayload['homeProductId']) != homeProductId) {
            throw const PurchaseCaptureException(
              'An approved receipt line cannot be rematched offline.',
            );
          }
          return _existingMutationResult(
            row: line,
            entityId: lineId,
            commandType: 'purchasing.receipt-line.approve',
          );
        }
        if (approvalStatus != 'unreviewed') {
          throw const PurchaseCaptureException(
            'The receipt line has an unsupported review state.',
          );
        }
        final receiptPayload = _validatedProjection(receipt, homeId);
        await _writeProjection(
          homeId: homeId,
          entityType: _receiptLineType,
          entityId: lineId,
          revision: line.revision + 1,
          representation: <String, Object?>{
            ..._withoutProjectionMetadata(linePayload),
            'homeProductId': homeProductId,
            'approvalStatus': 'approved',
          },
          at: at,
        );
        // The backend advances the parent receipt revision when a line is
        // approved even though the change feed publishes only the line.
        await _writeProjection(
          homeId: homeId,
          entityType: _receiptType,
          entityId: receiptId,
          revision: receipt.revision + 1,
          representation: _withoutProjectionMetadata(receiptPayload),
          at: at,
        );
        await _insertGeneratedCommand(
          homeId: homeId,
          entityType: _receiptLineType,
          entityId: lineId,
          commandType: 'purchasing.receipt-line.approve',
          baseRevision: line.revision,
          payload: <String, Object?>{
            'receiptId': receiptId,
            'homeProductId': homeProductId,
          },
          at: at,
        );
        return PurchaseMutationResult(
          entityId: lineId,
          revision: line.revision + 1,
          disposition: PurchaseMutationDisposition.queued,
        );
      },
    );
    if (result.awaitsServerConfirmation) {
      _triggerForegroundSync();
    }
    return result;
  }

  @override
  Future<PurchaseMutationResult> commitReceipt({
    required String homeId,
    required String receiptId,
  }) async {
    _requireSynchronizedPurchasing();
    _requireHomeUuid(homeId);
    _requireUuid(receiptId, 'purchase receipt');
    final at = _clock().toUtc();
    final result = await _database.transaction<PurchaseMutationResult>(
      () async {
        final receipt = await _record(
          homeId: homeId,
          entityType: _receiptType,
          entityId: receiptId,
        );
        if (receipt == null) {
          throw const PurchaseCaptureException(
            'The receipt is unavailable in this home.',
          );
        }
        final receiptPayload = _validatedProjection(receipt, homeId);
        final status = _requiredString(receiptPayload, 'status');
        if (status == 'committed') {
          return _existingMutationResult(
            row: receipt,
            entityId: receiptId,
            commandType: 'purchasing.receipt.commit',
          );
        }
        if (status != 'draft') {
          throw const PurchaseCaptureException(
            'Only a draft receipt can be committed.',
          );
        }
        final lines = await _receiptLineRecords(
          homeId: homeId,
          receiptId: receiptId,
        );
        if (lines.isEmpty) {
          throw const PurchaseCaptureException(
            'Add and approve at least one receipt line before commit.',
          );
        }
        for (final line in lines.values) {
          final payload = _validatedProjection(line, homeId);
          final homeProductId = _nullableString(payload['homeProductId']);
          if (_requiredString(payload, 'approvalStatus') != 'approved' ||
              homeProductId == null) {
            throw const PurchaseCaptureException(
              'Every receipt line must be explicitly matched and approved.',
            );
          }
          final product = await _record(
            homeId: homeId,
            entityType: _homeProductType,
            entityId: homeProductId,
          );
          if (product == null ||
              _optionalString(
                    _validatedProjection(product, homeId)['status'],
                    fallback: 'active',
                  ) !=
                  'active') {
            throw const PurchaseCaptureException(
              'An approved receipt product is unavailable in this home.',
            );
          }
        }
        await _writeProjection(
          homeId: homeId,
          entityType: _receiptType,
          entityId: receiptId,
          revision: receipt.revision + 1,
          representation: <String, Object?>{
            ..._withoutProjectionMetadata(receiptPayload),
            'status': 'committed',
            '_clientCommitQueuedAt': at.toIso8601String(),
          },
          at: at,
        );
        await _insertGeneratedCommand(
          homeId: homeId,
          entityType: _receiptType,
          entityId: receiptId,
          commandType: 'purchasing.receipt.commit',
          baseRevision: receipt.revision,
          payload: const <String, Object?>{},
          at: at,
        );
        return PurchaseMutationResult(
          entityId: receiptId,
          revision: receipt.revision + 1,
          disposition: PurchaseMutationDisposition.queued,
        );
      },
    );
    if (result.awaitsServerConfirmation) {
      _triggerForegroundSync();
    }
    return result;
  }

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) {
    return _watchRecordTypes(
      homeId: homeId,
      entityTypes: const <String>{
        _shoppingListType,
        _serverShoppingListType,
        _serverShoppingLineType,
      },
    ).map((rows) => _projectActiveShoppingList(homeId, rows));
  }

  @override
  Future<void> saveList(ShoppingList list) {
    if (_synchronizesMutations) {
      return _saveSynchronizedList(list);
    }
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
    if (_synchronizesMutations) {
      throw UnsupportedError(
        'Suggestion feedback is not published by sync protocol v2.',
      );
    }
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
    final listType = _synchronizesMutations
        ? _serverShoppingListType
        : _shoppingListType;
    final existing =
        await (_database.select(_database.localRecords)..where(
              (row) =>
                  row.homeId.equals(homeId) & row.entityType.equals(listType),
            ))
            .getSingleOrNull();
    if (existing != null) return;

    final listId = _synchronizesMutations
        ? _nextUuid('shopping list')
        : 'manual-list:$homeId';

    await saveList(
      ShoppingList(
        id: listId,
        homeId: homeId,
        name: 'Shopping list',
        createdAt: _clock().toUtc(),
      ),
    );
  }

  List<InventoryItem> _projectInventoryItems(
    String homeId,
    List<LocalRecord> rows,
  ) {
    final items = <String, InventoryItem>{};
    final balances = <String, double>{};

    for (final row in rows.where((row) => row.entityType == _balanceType)) {
      final payload = _validatedProjection(row, homeId);
      final homeProductId = _requiredString(payload, 'homeProductId');
      if (homeProductId != row.entityId) {
        throw const FormatException(
          'Inventory balance identity does not match its projection key.',
        );
      }
      balances[homeProductId] = _requiredDecimal(payload, 'quantity');
    }

    for (final row in rows.where(
      (row) => row.entityType == _inventoryItemType,
    )) {
      final item = _decodeInventoryItem(row.payload);
      if (row.homeId != homeId || item.homeId != homeId) {
        throw StateError('Cross-home inventory projection was rejected.');
      }
      items[item.id] = item;
    }

    for (final row in rows.where((row) => row.entityType == _homeProductType)) {
      final payload = _validatedProjection(row, homeId);
      final status = _optionalString(payload['status'], fallback: 'active');
      if (status != 'active') continue;
      final privateName = _nullableString(payload['privateName']);
      final productName = _nullableString(payload['productName']);
      final productId = _nullableString(payload['productId']);
      final originalPackText = _nullableString(payload['originalPackText']);
      final category =
          _nullableString(payload['categoryName']) ??
          _nullableString(payload['category']) ??
          'Uncategorized';
      items[row.entityId] = InventoryItem(
        id: row.entityId,
        homeId: homeId,
        canonicalName:
            privateName ??
            productName ??
            (productId == null
                ? 'Private item ${row.entityId.substring(0, 8)}'
                : 'Product ${productId.substring(0, 8)}'),
        packSize: originalPackText ?? 'Unspecified pack',
        category: category,
        brand: _optionalString(payload['brandName']),
        currentQuantity: balances[row.entityId],
        isHomeProduct: true,
      );
    }

    final projected = items.values.toList(growable: false)
      ..sort((left, right) {
        final category = left.category.compareTo(right.category);
        if (category != 0) return category;
        final name = left.canonicalName.compareTo(right.canonicalName);
        if (name != 0) return name;
        return left.packSize.compareTo(right.packSize);
      });
    return projected;
  }

  StockCountSession? _projectActiveCountSession(
    String homeId,
    List<LocalRecord> rows,
  ) {
    final sessions = <StockCountSession>[];
    for (final row in rows.where(
      (row) => row.entityType == _countSessionType,
    )) {
      final session = _decodeCountSession(row.payload);
      if (row.homeId != homeId || session.homeId != homeId) {
        throw StateError('Cross-home count-session projection was rejected.');
      }
      sessions.add(session);
    }

    final serverSessions = <String, LocalRecord>{
      for (final row in rows.where(
        (row) => row.entityType == _serverCountSessionType,
      ))
        row.entityId: row,
    };
    final linesBySession = <String, List<StockCountLine>>{};
    for (final row in rows.where(
      (row) => row.entityType == _serverCountLineType,
    )) {
      final payload = _validatedProjection(row, homeId);
      final sessionId = _requiredString(payload, 'sessionId');
      if (!serverSessions.containsKey(sessionId)) {
        throw const FormatException(
          'A count line references an unavailable count session.',
        );
      }
      final statusName = _requiredString(payload, 'status');
      final status = switch (statusName) {
        'confirmed' => CountLineStatus.confirmed,
        'outstanding' => CountLineStatus.outstanding,
        _ => throw FormatException(
          'Unsupported count-line status "$statusName".',
        ),
      };
      linesBySession
          .putIfAbsent(sessionId, () => <StockCountLine>[])
          .add(
            StockCountLine(
              id: row.entityId,
              itemId: _requiredString(payload, 'homeProductId'),
              status: status,
              // Remote photo evidence is deliberately not represented as a local
              // file reference. The factual count remains visible and read-only.
              source: CountSource.manual,
              observedQuantity: _requiredDecimal(payload, 'quantity'),
            ),
          );
    }

    for (final row in serverSessions.values) {
      final payload = _validatedProjection(row, homeId);
      final statusName = _requiredString(payload, 'status');
      final status = switch (statusName) {
        'open' => CountSessionStatus.open,
        'closed' => CountSessionStatus.closed,
        'cancelled' => CountSessionStatus.cancelled,
        _ => throw FormatException(
          'Unsupported count-session status "$statusName".',
        ),
      };
      final occurredAt =
          _optionalDateTime(payload['_clientStartedAt']) ??
          row.updatedAt.toUtc();
      sessions.add(
        StockCountSession(
          id: row.entityId,
          homeId: homeId,
          locationId: _nullableString(payload['locationId']) ?? 'primary',
          startedAt: occurredAt,
          status: status,
          closedAt: status == CountSessionStatus.closed
              ? (_optionalDateTime(payload['_clientClosedAt']) ??
                    row.updatedAt.toUtc())
              : null,
          lines: linesBySession[row.entityId] ?? const <StockCountLine>[],
        ),
      );
    }

    final open =
        sessions
            .where((session) => session.status == CountSessionStatus.open)
            .toList(growable: false)
          ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return open.isEmpty ? null : open.first;
  }

  PurchaseReceiptCapture? _projectActiveReceiptCapture(
    String homeId,
    List<LocalRecord> rows,
  ) {
    final stores = <String, String>{};
    for (final row in rows.where((row) => row.entityType == _storeType)) {
      final payload = _validatedProjection(row, homeId);
      if (_optionalString(payload['status'], fallback: 'active') == 'active') {
        stores[row.entityId] = _requiredString(payload, 'name');
      }
    }

    final activeReceipts = <LocalRecord>[];
    for (final row in rows.where((row) => row.entityType == _receiptType)) {
      final payload = _validatedProjection(row, homeId);
      final status = _requiredString(payload, 'status');
      if (status == 'draft' ||
          (status == 'committed' && row.synchronizedAt == null)) {
        activeReceipts.add(row);
      } else if (status != 'committed') {
        throw FormatException('Unsupported receipt status "$status".');
      }
    }
    if (activeReceipts.isEmpty) return null;
    if (activeReceipts.length > 1) {
      throw const PurchaseCaptureException(
        'Multiple unfinished receipts require synchronization before editing.',
      );
    }

    final receipt = activeReceipts.single;
    final payload = _validatedProjection(receipt, homeId);
    final currency = _requiredString(payload, 'currency');
    final lines = <PurchaseReceiptLineCapture>[];
    for (final row in rows.where((row) => row.entityType == _receiptLineType)) {
      final linePayload = _validatedProjection(row, homeId);
      if (_requiredString(linePayload, 'receiptId') != receipt.entityId) {
        continue;
      }
      final approvalName = _requiredString(linePayload, 'approvalStatus');
      final approvalStatus = switch (approvalName) {
        'unreviewed' => PurchaseLineApprovalStatus.unreviewed,
        'approved' => PurchaseLineApprovalStatus.approved,
        _ => throw FormatException(
          'Unsupported receipt-line approval status "$approvalName".',
        ),
      };
      final unitPrice = _nullableString(linePayload['unitPrice']);
      final lineTotal = _nullableString(linePayload['lineTotal']);
      lines.add(
        PurchaseReceiptLineCapture(
          id: row.entityId,
          homeId: homeId,
          receiptId: receipt.entityId,
          rawDescription: _requiredString(linePayload, 'rawDescription'),
          quantity: _requiredDecimal(linePayload, 'quantity'),
          originalPackText: _nullableString(linePayload['originalPackText']),
          unitPrice: unitPrice == null
              ? null
              : Money(
                  minorUnits: _moneyMinorUnits(unitPrice),
                  currency: currency,
                ),
          lineTotal: lineTotal == null
              ? null
              : Money(
                  minorUnits: _moneyMinorUnits(lineTotal),
                  currency: currency,
                ),
          homeProductId: _nullableString(linePayload['homeProductId']),
          revision: row.revision,
          approvalStatus: approvalStatus,
          synchronizationState: row.synchronizedAt == null
              ? PurchaseSynchronizationState.pending
              : PurchaseSynchronizationState.synchronized,
        ),
      );
    }
    lines.sort((left, right) => left.id.compareTo(right.id));
    final totalAmount = _nullableString(payload['totalAmount']);
    final storeId = _nullableString(payload['storeId']);
    final receiptStatus = switch (_requiredString(payload, 'status')) {
      'draft' => PurchaseReceiptStatus.draft,
      'committed' => PurchaseReceiptStatus.committed,
      final value => throw FormatException(
        'Unsupported receipt status "$value".',
      ),
    };
    return PurchaseReceiptCapture(
      id: receipt.entityId,
      homeId: homeId,
      storeId: storeId,
      storeName: storeId == null
          ? null
          : (stores[storeId] ?? 'Unavailable store'),
      purchaseDate: _parseDateOnly(_requiredString(payload, 'purchaseDate')),
      currency: currency,
      total: totalAmount == null
          ? null
          : Money(
              minorUnits: _moneyMinorUnits(totalAmount),
              currency: currency,
            ),
      notes: _optionalString(payload['notes']),
      sourceReference: _nullableString(payload['sourceReference']),
      revision: receipt.revision,
      status: receiptStatus,
      synchronizationState:
          receipt.synchronizedAt == null ||
              lines.any(
                (line) =>
                    line.synchronizationState ==
                    PurchaseSynchronizationState.pending,
              )
          ? PurchaseSynchronizationState.pending
          : PurchaseSynchronizationState.synchronized,
      lines: lines,
    );
  }

  List<PurchaseMatchCandidate> _projectPurchaseMatchCandidates(
    String homeId,
    List<LocalRecord> rows,
  ) {
    final candidates = <PurchaseMatchCandidate>[];
    for (final row in rows) {
      final payload = _validatedProjection(row, homeId);
      if (_optionalString(payload['status'], fallback: 'active') != 'active') {
        continue;
      }
      candidates.add(
        PurchaseMatchCandidate(
          id: row.entityId,
          homeId: homeId,
          name:
              _nullableString(payload['privateName']) ??
              _nullableString(payload['productName']) ??
              'Private product ${row.entityId.substring(0, 8)}',
          packSize:
              _nullableString(payload['originalPackText']) ??
              'Unspecified pack',
        ),
      );
    }
    candidates.sort((left, right) {
      final name = left.name.compareTo(right.name);
      return name != 0 ? name : left.packSize.compareTo(right.packSize);
    });
    return candidates;
  }

  List<PurchaseLine> _projectPurchaseLines(
    String homeId,
    List<LocalRecord> rows,
  ) {
    final projected = <PurchaseLine>[];
    for (final row in rows.where(
      (row) => row.entityType == _purchaseLineType,
    )) {
      final line = _decodePurchaseLine(row.payload);
      if (row.homeId != homeId || line.homeId != homeId) {
        throw StateError('Cross-home purchase projection was rejected.');
      }
      projected.add(line);
    }

    final stores = <String, String>{};
    for (final row in rows.where((row) => row.entityType == _storeType)) {
      final payload = _validatedProjection(row, homeId);
      stores[row.entityId] = _requiredString(payload, 'name');
    }
    final receipts = <String, Map<String, Object?>>{};
    final pendingReceipts = <String>{};
    for (final row in rows.where((row) => row.entityType == _receiptType)) {
      receipts[row.entityId] = _validatedProjection(row, homeId);
      if (row.synchronizedAt == null) pendingReceipts.add(row.entityId);
    }
    final products = <String, String>{};
    for (final row in rows.where((row) => row.entityType == _homeProductType)) {
      final payload = _validatedProjection(row, homeId);
      products[row.entityId] =
          _nullableString(payload['privateName']) ??
          _nullableString(payload['productName']) ??
          'Product ${row.entityId.substring(0, 8)}';
    }

    for (final row in rows.where((row) => row.entityType == _receiptLineType)) {
      final payload = _validatedProjection(row, homeId);
      final receiptId = _requiredString(payload, 'receiptId');
      final receipt = receipts[receiptId];
      if (receipt == null) {
        throw const FormatException(
          'A receipt line references an unavailable receipt.',
        );
      }
      final receiptStatus = _requiredString(receipt, 'status');
      if (receiptStatus == 'draft') continue;
      if (receiptStatus != 'committed') {
        throw FormatException(
          'Unsupported purchase-history receipt status "$receiptStatus".',
        );
      }
      final currency = _requiredString(receipt, 'currency');
      final lineTotal = _nullableString(payload['lineTotal']);
      final homeProductId = _nullableString(payload['homeProductId']);
      final storeId = _nullableString(receipt['storeId']);
      projected.add(
        PurchaseLine(
          id: row.entityId,
          homeId: homeId,
          purchasedAt: _parseDateOnly(_requiredString(receipt, 'purchaseDate')),
          datePrecision: PurchaseDatePrecision.exactDay,
          storeName: storeId == null
              ? 'Unspecified store'
              : (stores[storeId] ?? 'Unavailable store'),
          rawDescription: _requiredString(payload, 'rawDescription'),
          packSize:
              _nullableString(payload['originalPackText']) ??
              'Unspecified pack',
          quantity: _requiredDecimal(payload, 'quantity'),
          source: PurchaseSource.recentReceipt,
          receiptId: receiptId,
          canonicalItemId: homeProductId,
          canonicalName: homeProductId == null ? null : products[homeProductId],
          lineTotal: lineTotal == null
              ? null
              : Money(
                  minorUnits: _moneyMinorUnits(lineTotal),
                  currency: currency,
                ),
          pendingSynchronization:
              pendingReceipts.contains(receiptId) || row.synchronizedAt == null,
        ),
      );
    }

    projected.sort(
      (left, right) => right.purchasedAt.compareTo(left.purchasedAt),
    );
    return projected;
  }

  ShoppingList _projectActiveShoppingList(
    String homeId,
    List<LocalRecord> rows,
  ) {
    final legacyLists = <ShoppingList>[];
    for (final row in rows.where(
      (row) => row.entityType == _shoppingListType,
    )) {
      final list = _decodeShoppingList(row.payload);
      if (row.homeId != homeId || list.homeId != homeId) {
        throw StateError('Cross-home shopping-list projection was rejected.');
      }
      legacyLists.add(list);
    }

    final serverLists =
        rows
            .where((row) => row.entityType == _serverShoppingListType)
            .where((row) {
              final payload = _validatedProjection(row, homeId);
              return _requiredString(payload, 'status') == 'open';
            })
            .toList(growable: false)
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    for (final row in serverLists) {
      final payload = _validatedProjection(row, homeId);
      final lines = <ShoppingListLine>[];
      for (final lineRow in rows.where(
        (candidate) => candidate.entityType == _serverShoppingLineType,
      )) {
        final linePayload = _validatedProjection(lineRow, homeId);
        if (_requiredString(linePayload, 'listId') != row.entityId) continue;
        final source = _requiredString(linePayload, 'source');
        lines.add(
          ShoppingListLine(
            id: lineRow.entityId,
            homeId: homeId,
            name: _requiredString(linePayload, 'description'),
            quantity: _requiredDecimal(linePayload, 'quantityToBuy'),
            origin: source == 'manual'
                ? ShoppingLineOrigin.manual
                : ShoppingLineOrigin.suggestion,
            createdAt:
                _optionalDateTime(linePayload['_clientCreatedAt']) ??
                lineRow.updatedAt.toUtc(),
            productPackId: _nullableString(linePayload['homeProductId']),
            checked:
                linePayload['checked'] == true ||
                _nullableString(linePayload['checkedAt']) != null,
            explanation: _nullableString(linePayload['explanation']),
          ),
        );
      }
      return ShoppingList(
        id: row.entityId,
        homeId: homeId,
        name: _requiredString(payload, 'name'),
        createdAt:
            _optionalDateTime(payload['_clientCreatedAt']) ??
            row.updatedAt.toUtc(),
        lines: lines,
      );
    }

    if (legacyLists.isNotEmpty) {
      legacyLists.sort(
        (left, right) => right.createdAt.compareTo(left.createdAt),
      );
      return legacyLists.first;
    }
    final emptyId = _synchronizesMutations
        ? _emptyShoppingListIds.putIfAbsent(
            homeId,
            () => _nextUuid('shopping list'),
          )
        : 'manual-list:$homeId';
    return ShoppingList(
      id: emptyId,
      homeId: homeId,
      name: 'Shopping list',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Future<void> _commitSynchronizedManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) async {
    _requireHomeUuid(intent.homeId);
    _requireUuid(intent.id, 'adjustment operation');
    _requireUuid(intent.itemId, 'home product');
    if (movement != null &&
        (movement.homeId != intent.homeId ||
            movement.itemId != intent.itemId)) {
      throw StateError('Cross-home adjustment movement was rejected.');
    }
    final delta = intent.observedQuantity - intent.projectedQuantity;
    if (delta.abs() <= 0.00000001) return;
    final at = intent.createdAt.toUtc();
    await _database.transaction(() async {
      final homeProduct = await _record(
        homeId: intent.homeId,
        entityType: _homeProductType,
        entityId: intent.itemId,
      );
      if (homeProduct == null) {
        throw StateError('The inventory item no longer exists in this home.');
      }
      _validatedProjection(homeProduct, intent.homeId);
      final balance = await _record(
        homeId: intent.homeId,
        entityType: _balanceType,
        entityId: intent.itemId,
      );
      final projected = balance == null
          ? 0.0
          : _requiredDecimal(
              _validatedProjection(balance, intent.homeId),
              'quantity',
            );
      if ((projected - intent.projectedQuantity).abs() > 0.00000001) {
        throw StateError(
          'The inventory quantity changed before the adjustment was saved.',
        );
      }
      await _writeProjection(
        homeId: intent.homeId,
        entityType: _balanceType,
        entityId: intent.itemId,
        revision: balance?.revision ?? 0,
        representation: <String, Object?>{
          'homeProductId': intent.itemId,
          'quantity': _decimal(intent.observedQuantity),
        },
        at: at,
      );
      await _insertCommand(
        operationId: intent.id,
        homeId: intent.homeId,
        entityType: _balanceType,
        entityId: intent.itemId,
        commandType: 'inventory.adjustment.create',
        baseRevision: null,
        payload: <String, Object?>{
          'quantityDelta': _decimal(delta),
          'reason': intent.reason.trim(),
        },
        at: at,
      );
    });
    _triggerForegroundSync();
  }

  Future<void> _saveSynchronizedCountSession(StockCountSession session) async {
    _requireHomeUuid(session.homeId);
    _requireUuid(session.id, 'count session');
    final at = _clock().toUtc();
    var changed = false;
    await _database.transaction(() async {
      final existing = await _record(
        homeId: session.homeId,
        entityType: _serverCountSessionType,
        entityId: session.id,
      );
      if (existing == null) {
        if (session.status != CountSessionStatus.open ||
            session.lines.isNotEmpty ||
            session.photos.isNotEmpty) {
          throw UnsupportedError(
            'A synchronized count must be opened before lines are recorded.',
          );
        }
        await _writeProjection(
          homeId: session.homeId,
          entityType: _serverCountSessionType,
          entityId: session.id,
          revision: 1,
          representation: _countSessionRepresentation(session),
          at: at,
        );
        await _insertGeneratedCommand(
          homeId: session.homeId,
          entityType: _serverCountSessionType,
          entityId: session.id,
          commandType: 'inventory.count-session.create',
          baseRevision: null,
          payload: <String, Object?>{
            'locationId': isUuid(session.locationId)
                ? session.locationId
                : null,
            'notes': '',
            'scopeComplete': false,
            'reliability': 'unassessed',
          },
          at: at,
        );
        changed = true;
        return;
      }

      final existingPayload = _validatedProjection(existing, session.homeId);
      if (_requiredString(existingPayload, 'status') != 'open') {
        throw StateError('Only an open synchronized count can be changed.');
      }
      if (session.status == CountSessionStatus.cancelled) {
        throw UnsupportedError(
          'Count cancellation is not published by sync protocol v2.',
        );
      }
      if (session.photos.isNotEmpty) {
        throw UnsupportedError(
          'Count photo attachment requires the published media workflow.',
        );
      }

      final persistedLines = await _countLineRecords(
        homeId: session.homeId,
        sessionId: session.id,
      );
      final incomingById = <String, StockCountLine>{
        for (final line in session.lines) line.id: line,
      };
      if (persistedLines.keys.any((id) => !incomingById.containsKey(id))) {
        throw UnsupportedError(
          'Removing synchronized count lines is not supported.',
        );
      }
      final changedLines = session.lines
          .where((line) {
            final row = persistedLines[line.id];
            if (row == null) return true;
            final payload = _validatedProjection(row, session.homeId);
            return _requiredString(payload, 'homeProductId') != line.itemId ||
                (_requiredDecimal(payload, 'quantity') -
                            (line.observedQuantity ?? double.nan))
                        .abs() >
                    0.00000001 ||
                _requiredString(payload, 'status') != line.status.name;
          })
          .toList(growable: false);

      if (session.status == CountSessionStatus.closed) {
        if (changedLines.isNotEmpty) {
          throw UnsupportedError(
            'Save count lines before closing the synchronized count.',
          );
        }
        if (session.lines.isEmpty) {
          throw StateError('At least one confirmed count line is required.');
        }
        await _writeProjection(
          homeId: session.homeId,
          entityType: _serverCountSessionType,
          entityId: session.id,
          revision: existing.revision + 1,
          representation: _countSessionRepresentation(session),
          at: at,
        );
        for (final line in session.confirmedLines) {
          final product = await _record(
            homeId: session.homeId,
            entityType: _homeProductType,
            entityId: line.itemId,
          );
          if (product == null) {
            throw StateError('A counted inventory item no longer exists.');
          }
          final balance = await _record(
            homeId: session.homeId,
            entityType: _balanceType,
            entityId: line.itemId,
          );
          await _writeProjection(
            homeId: session.homeId,
            entityType: _balanceType,
            entityId: line.itemId,
            revision: balance?.revision ?? 0,
            representation: <String, Object?>{
              'homeProductId': line.itemId,
              'quantity': _decimal(line.observedQuantity!),
            },
            at: at,
          );
        }
        await _insertGeneratedCommand(
          homeId: session.homeId,
          entityType: _serverCountSessionType,
          entityId: session.id,
          commandType: 'inventory.count-session.close',
          baseRevision: existing.revision,
          payload: const <String, Object?>{},
          at: at,
        );
        changed = true;
        return;
      }

      if (changedLines.isEmpty) return;
      if (changedLines.length != 1) {
        throw UnsupportedError('Save one synchronized count line at a time.');
      }
      final line = changedLines.single;
      _requireUuid(line.id, 'count line');
      _requireUuid(line.itemId, 'home product');
      if (line.status != CountLineStatus.confirmed ||
          line.source != CountSource.manual ||
          line.observedQuantity == null) {
        throw UnsupportedError(
          'Only confirmed manual count lines are supported by this workflow.',
        );
      }
      final product = await _record(
        homeId: session.homeId,
        entityType: _homeProductType,
        entityId: line.itemId,
      );
      if (product == null) {
        throw StateError('The count line references another home or item.');
      }
      final priorLine = persistedLines[line.id];
      await _writeProjection(
        homeId: session.homeId,
        entityType: _serverCountLineType,
        entityId: line.id,
        revision: (priorLine?.revision ?? 0) + 1,
        representation: _countLineRepresentation(session.id, line),
        at: at,
      );
      await _writeProjection(
        homeId: session.homeId,
        entityType: _serverCountSessionType,
        entityId: session.id,
        revision: existing.revision + 1,
        representation: <String, Object?>{...existingPayload, 'status': 'open'},
        at: at,
      );
      await _insertGeneratedCommand(
        homeId: session.homeId,
        entityType: _serverCountLineType,
        entityId: line.id,
        commandType: 'inventory.count-line.upsert',
        // Count-line upsert concurrency is line-scoped: zero creates a new
        // line and the prior line revision updates it. The count-session
        // revision advances independently and is used only when closing.
        baseRevision: priorLine?.revision ?? 0,
        payload: <String, Object?>{
          'sessionId': session.id,
          'homeProductId': line.itemId,
          'quantity': _decimal(line.observedQuantity!),
          'confidence': null,
          'source': 'manual',
          'notes': '',
        },
        at: at,
      );
      changed = true;
    });
    if (changed) _triggerForegroundSync();
  }

  Future<void> _saveSynchronizedList(ShoppingList list) async {
    _requireHomeUuid(list.homeId);
    _requireUuid(list.id, 'shopping list');
    final at = _clock().toUtc();
    var changed = false;
    await _database.transaction(() async {
      final existing = await _record(
        homeId: list.homeId,
        entityType: _serverShoppingListType,
        entityId: list.id,
      );
      if (existing == null) {
        if (list.lines.isNotEmpty) {
          throw UnsupportedError(
            'Create the synchronized shopping list before adding a line.',
          );
        }
        await _writeProjection(
          homeId: list.homeId,
          entityType: _serverShoppingListType,
          entityId: list.id,
          revision: 1,
          representation: <String, Object?>{
            'name': list.name,
            'kind': 'manual',
            'status': 'open',
            '_clientCreatedAt': list.createdAt.toUtc().toIso8601String(),
          },
          at: at,
        );
        await _insertGeneratedCommand(
          homeId: list.homeId,
          entityType: _serverShoppingListType,
          entityId: list.id,
          commandType: 'shopping.list.create',
          baseRevision: null,
          payload: <String, Object?>{'name': list.name, 'kind': 'manual'},
          at: at,
        );
        _emptyShoppingListIds.remove(list.homeId);
        changed = true;
        return;
      }

      final existingPayload = _validatedProjection(existing, list.homeId);
      if (_requiredString(existingPayload, 'status') != 'open') {
        throw StateError('Only an open shopping list can be changed.');
      }
      if (_requiredString(existingPayload, 'name') != list.name) {
        throw UnsupportedError(
          'Shopping-list renaming is not published by sync protocol v2.',
        );
      }
      final persistedLines = await _shoppingLineRecords(
        homeId: list.homeId,
        listId: list.id,
      );
      final incomingById = <String, ShoppingListLine>{
        for (final line in list.lines) line.id: line,
      };
      if (persistedLines.keys.any((id) => !incomingById.containsKey(id))) {
        throw UnsupportedError(
          'Removing shopping-list lines is not published by sync protocol v2.',
        );
      }
      final newLines = list.lines
          .where((line) => !persistedLines.containsKey(line.id))
          .toList(growable: false);
      if (newLines.isNotEmpty) {
        if (newLines.length != 1 ||
            list.lines.length != persistedLines.length + 1) {
          throw UnsupportedError('Add one shopping-list line at a time.');
        }
        final line = newLines.single;
        _validateNewShoppingLine(list, line);
        await _writeProjection(
          homeId: list.homeId,
          entityType: _serverShoppingLineType,
          entityId: line.id,
          revision: 1,
          representation: _shoppingLineRepresentation(list.id, line),
          at: at,
        );
        await _writeProjection(
          homeId: list.homeId,
          entityType: _serverShoppingListType,
          entityId: list.id,
          revision: existing.revision + 1,
          representation: existingPayload,
          at: at,
        );
        await _insertGeneratedCommand(
          homeId: list.homeId,
          entityType: _serverShoppingLineType,
          entityId: line.id,
          commandType: 'shopping.list-line.create',
          baseRevision: existing.revision,
          payload: <String, Object?>{
            'listId': list.id,
            'homeProductId':
                line.productPackId != null && isUuid(line.productPackId!)
                ? line.productPackId
                : null,
            'description': line.name,
            'quantity': _decimal(line.quantity),
          },
          at: at,
        );
        changed = true;
        return;
      }

      final changedLines = <(ShoppingListLine, LocalRecord)>[];
      for (final line in list.lines) {
        final row = persistedLines[line.id]!;
        final payload = _validatedProjection(row, list.homeId);
        final oldQuantity = _requiredDecimal(payload, 'quantityToBuy');
        final oldName = _requiredString(payload, 'description');
        final oldProduct = _nullableString(payload['homeProductId']);
        if ((oldQuantity - line.quantity).abs() > 0.00000001 ||
            oldName != line.name ||
            oldProduct != line.productPackId) {
          throw UnsupportedError(
            'Shopping-line edits are not published by sync protocol v2.',
          );
        }
        if ((payload['checked'] == true) != line.checked) {
          changedLines.add((line, row));
        }
      }
      if (changedLines.isEmpty) return;
      if (changedLines.length != 1) {
        throw UnsupportedError('Check one shopping-list line at a time.');
      }
      final (line, row) = changedLines.single;
      final representation = _validatedProjection(row, list.homeId);
      await _writeProjection(
        homeId: list.homeId,
        entityType: _serverShoppingLineType,
        entityId: line.id,
        revision: row.revision + 1,
        representation: <String, Object?>{
          ...representation,
          'checked': line.checked,
          'checkedAt': line.checked ? at.toIso8601String() : null,
        },
        at: at,
      );
      await _insertGeneratedCommand(
        homeId: list.homeId,
        entityType: _serverShoppingLineType,
        entityId: line.id,
        commandType: 'shopping.list-line.checked',
        baseRevision: row.revision,
        payload: <String, Object?>{'listId': list.id, 'checked': line.checked},
        at: at,
      );
      changed = true;
    });
    if (changed) _triggerForegroundSync();
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

  Map<String, Object?> _countSessionRepresentation(StockCountSession session) =>
      <String, Object?>{
        'locationId': isUuid(session.locationId) ? session.locationId : null,
        'notes': '',
        'scopeComplete': false,
        'reliability': 'unassessed',
        'status': switch (session.status) {
          CountSessionStatus.open => 'open',
          CountSessionStatus.closed => 'closed',
          CountSessionStatus.cancelled => 'cancelled',
        },
        '_clientStartedAt': session.startedAt.toUtc().toIso8601String(),
        '_clientClosedAt': session.closedAt?.toUtc().toIso8601String(),
      };

  Map<String, Object?> _countLineRepresentation(
    String sessionId,
    StockCountLine line,
  ) => <String, Object?>{
    'sessionId': sessionId,
    'homeProductId': line.itemId,
    'quantity': _decimal(line.observedQuantity!),
    'confidence': null,
    'source': 'manual',
    'notes': '',
    'status': 'confirmed',
  };

  Map<String, Object?> _shoppingLineRepresentation(
    String listId,
    ShoppingListLine line,
  ) => <String, Object?>{
    'listId': listId,
    'homeProductId': line.productPackId,
    'description': line.name,
    'source': 'manual',
    'quantityToBuy': _decimal(line.quantity),
    'explanation': 'Added manually.',
    'confidence': null,
    'checkedAt': line.checked ? _clock().toUtc().toIso8601String() : null,
    'checked': line.checked,
    '_clientCreatedAt': line.createdAt.toUtc().toIso8601String(),
  };

  void _validateNewShoppingLine(ShoppingList list, ShoppingListLine line) {
    if (line.homeId != list.homeId) {
      throw StateError('Cross-home shopping-list line was rejected.');
    }
    _requireUuid(line.id, 'shopping-list line');
    if (line.productPackId != null) {
      _requireUuid(line.productPackId!, 'shopping-list home product');
    }
    if (line.origin != ShoppingLineOrigin.manual || line.checked) {
      throw UnsupportedError(
        'Only unchecked manual shopping-list lines can be created offline.',
      );
    }
    if (!line.quantity.isFinite || line.quantity <= 0) {
      throw ArgumentError.value(
        line.quantity,
        'quantity',
        'must be positive and finite',
      );
    }
  }

  void _requireSynchronizedPurchasing() {
    if (!_synchronizesMutations) {
      throw const PurchaseCaptureException(
        'Receipt capture requires the synchronized household workspace.',
      );
    }
  }

  void _requireRequestMoneyCurrency(Money? value, String currency) {
    if (value != null && value.currency != currency) {
      throw const PurchaseCaptureException(
        'Receipt-line prices must use the receipt currency.',
      );
    }
  }

  Future<LocalRecord?> _activeReceiptRecord({required String homeId}) async {
    final rows =
        await (_database.select(_database.localRecords)..where(
              (row) =>
                  row.homeId.equals(homeId) &
                  row.entityType.equals(_receiptType),
            ))
            .get();
    final active = <LocalRecord>[];
    for (final row in rows) {
      final payload = _validatedProjection(row, homeId);
      final status = _requiredString(payload, 'status');
      if (status == 'draft' ||
          (status == 'committed' && row.synchronizedAt == null)) {
        active.add(row);
      }
    }
    if (active.length > 1) {
      throw const PurchaseCaptureException(
        'Multiple unfinished receipts require synchronization before editing.',
      );
    }
    return active.isEmpty ? null : active.single;
  }

  Future<LocalRecord> _requiredDraftReceipt({
    required String homeId,
    required String receiptId,
  }) async {
    final receipt = await _record(
      homeId: homeId,
      entityType: _receiptType,
      entityId: receiptId,
    );
    if (receipt == null) {
      throw const PurchaseCaptureException(
        'The receipt is unavailable in this home.',
      );
    }
    if (_requiredString(_validatedProjection(receipt, homeId), 'status') !=
        'draft') {
      throw const PurchaseCaptureException(
        'Only a draft receipt can be changed.',
      );
    }
    return receipt;
  }

  Future<Map<String, LocalRecord>> _receiptLineRecords({
    required String homeId,
    required String receiptId,
  }) async {
    final rows =
        await (_database.select(_database.localRecords)..where(
              (row) =>
                  row.homeId.equals(homeId) &
                  row.entityType.equals(_receiptLineType),
            ))
            .get();
    final result = <String, LocalRecord>{};
    for (final row in rows) {
      final payload = _validatedProjection(row, homeId);
      if (_requiredString(payload, 'receiptId') == receiptId) {
        result[row.entityId] = row;
      }
    }
    return result;
  }

  Future<PurchaseMutationResult> _existingMutationResult({
    required LocalRecord row,
    required String entityId,
    required String commandType,
  }) async {
    final query = _database.select(_database.clientOperations)
      ..where(
        (operation) =>
            operation.homeId.equals(row.homeId) &
            operation.entityType.equals(row.entityType) &
            operation.entityId.equals(entityId) &
            operation.operationType.equals(commandType),
      )
      ..orderBy(<OrderingTerm Function(ClientOperations)>[
        (operation) => OrderingTerm.desc(operation.clientTimestamp),
      ])
      ..limit(1);
    final operation = await query.getSingleOrNull();
    if (operation == null) {
      if (row.synchronizedAt != null) {
        return PurchaseMutationResult(
          entityId: entityId,
          revision: row.revision,
          disposition: PurchaseMutationDisposition.synchronized,
        );
      }
      throw const PurchaseCaptureException(
        'The local receipt state cannot be retried safely. Synchronize first.',
      );
    }
    final state = ClientOperationState.fromStorage(operation.state);
    final disposition = switch (state) {
      ClientOperationState.acknowledged =>
        PurchaseMutationDisposition.synchronized,
      ClientOperationState.pending ||
      ClientOperationState.syncing ||
      ClientOperationState.retryWait =>
        PurchaseMutationDisposition.alreadyQueued,
      ClientOperationState.blockedConflict ||
      ClientOperationState.blockedValidation ||
      ClientOperationState.blockedAuthorization =>
        throw PurchaseCaptureException(
          operation.lastSafeError ??
              'The queued receipt change needs attention before retry.',
        ),
    };
    return PurchaseMutationResult(
      entityId: entityId,
      revision: row.revision,
      disposition: disposition,
    );
  }

  Future<Map<String, LocalRecord>> _countLineRecords({
    required String homeId,
    required String sessionId,
  }) async {
    final rows =
        await (_database.select(_database.localRecords)..where(
              (row) =>
                  row.homeId.equals(homeId) &
                  row.entityType.equals(_serverCountLineType),
            ))
            .get();
    final result = <String, LocalRecord>{};
    for (final row in rows) {
      final payload = _validatedProjection(row, homeId);
      if (_requiredString(payload, 'sessionId') == sessionId) {
        result[row.entityId] = row;
      }
    }
    return result;
  }

  Future<Map<String, LocalRecord>> _shoppingLineRecords({
    required String homeId,
    required String listId,
  }) async {
    final rows =
        await (_database.select(_database.localRecords)..where(
              (row) =>
                  row.homeId.equals(homeId) &
                  row.entityType.equals(_serverShoppingLineType),
            ))
            .get();
    final result = <String, LocalRecord>{};
    for (final row in rows) {
      final payload = _validatedProjection(row, homeId);
      if (_requiredString(payload, 'listId') == listId) {
        result[row.entityId] = row;
      }
    }
    return result;
  }

  Future<LocalRecord?> _record({
    required String homeId,
    required String entityType,
    required String entityId,
  }) {
    return (_database.select(_database.localRecords)..where(
          (row) =>
              row.homeId.equals(homeId) &
              row.entityType.equals(entityType) &
              row.entityId.equals(entityId),
        ))
        .getSingleOrNull();
  }

  Map<String, Object?> _validatedProjection(
    LocalRecord row,
    String expectedHomeId,
  ) {
    if (row.homeId != expectedHomeId) {
      throw StateError('Cross-home household projection was rejected.');
    }
    final payload = _decodeObject(row.payload, row.entityType);
    final payloadId = payload['id'];
    if (payloadId != null && payloadId != row.entityId) {
      throw const FormatException(
        'Household projection identity does not match its storage key.',
      );
    }
    final payloadHomeId = payload['homeId'];
    if (payloadHomeId != null && payloadHomeId != expectedHomeId) {
      throw StateError('Cross-home household representation was rejected.');
    }
    final payloadRevision = payload['revision'];
    if (payloadRevision != null && payloadRevision != row.revision) {
      throw const FormatException(
        'Household projection revision does not match its storage key.',
      );
    }
    return payload;
  }

  Future<void> _writeProjection({
    required String homeId,
    required String entityType,
    required String entityId,
    required int revision,
    required Map<String, Object?> representation,
    required DateTime at,
  }) {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'must not be negative');
    }
    return _database
        .into(_database.localRecords)
        .insertOnConflictUpdate(
          LocalRecordsCompanion.insert(
            homeId: homeId,
            entityType: entityType,
            entityId: entityId,
            payload: jsonEncode(<String, Object?>{
              ...representation,
              'id': entityId,
              'revision': revision,
            }),
            revision: Value<int>(revision),
            isTombstone: const Value<bool>(false),
            updatedAt: at.toUtc(),
            synchronizedAt: const Value<DateTime?>(null),
          ),
        );
  }

  Future<void> _insertGeneratedCommand({
    required String homeId,
    required String entityType,
    required String entityId,
    required String commandType,
    required int? baseRevision,
    required Map<String, Object?> payload,
    required DateTime at,
  }) {
    return _insertCommand(
      operationId: _nextUuid('client operation'),
      homeId: homeId,
      entityType: entityType,
      entityId: entityId,
      commandType: commandType,
      baseRevision: baseRevision,
      payload: payload,
      at: at,
    );
  }

  Future<void> _insertCommand({
    required String operationId,
    required String homeId,
    required String entityType,
    required String entityId,
    required String commandType,
    required int? baseRevision,
    required Map<String, Object?> payload,
    required DateTime at,
  }) async {
    _requireUuid(operationId, 'client operation');
    _requireUuid(entityId, 'command entity');
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError('Synchronized mutation has no device identity.');
    }
    final latestQuery = _database.select(_database.clientOperations)
      ..where(
        (row) => row.homeId.equals(homeId) & row.deviceId.equals(deviceId),
      )
      ..orderBy(<OrderingTerm Function(ClientOperations)>[
        (row) => OrderingTerm.desc(row.clientTimestamp),
        (row) => OrderingTerm.desc(row.operationId),
      ])
      ..limit(1);
    final latest = await latestQuery.getSingleOrNull();
    var enqueueAt = at.toUtc();
    if (latest != null && !enqueueAt.isAfter(latest.clientTimestamp)) {
      // Drift's portable SQLite date-time encoding is second-granular on all
      // supported targets, so use a full second as the durable tie-breaker.
      enqueueAt = latest.clientTimestamp.add(const Duration(seconds: 1));
    }
    await _database
        .into(_database.clientOperations)
        .insert(
          ClientOperationsCompanion.insert(
            operationId: operationId,
            deviceId: deviceId,
            homeId: homeId,
            entityType: entityType,
            entityId: entityId,
            operationType: commandType,
            baseRevision: Value<int?>(baseRevision),
            // This timestamp is also the durable dependency order. UUIDv4 values
            // are intentionally random and must never decide parent/child order.
            clientTimestamp: enqueueAt,
            payloadSchemaVersion: const Value<int>(1),
            payload: jsonEncode(payload),
            state: ClientOperationState.pending.storageValue,
          ),
          mode: InsertMode.insertOrAbort,
        );
  }

  String _nextUuid(String purpose) {
    final id = _idGenerator();
    _requireUuid(id, purpose);
    return id.toLowerCase();
  }

  void _requireHomeUuid(String homeId) => _requireUuid(homeId, 'home');

  void _requireUuid(String value, String purpose) {
    if (!isUuid(value)) {
      throw ArgumentError.value(value, purpose, 'must be a UUID');
    }
  }

  void _triggerForegroundSync() {
    final trigger = _onMutationCommitted;
    if (trigger == null) return;
    unawaited(
      Future<void>.sync(
        trigger,
      ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Stream<List<LocalRecord>> _watchRecordTypes({
    required String homeId,
    required Set<String> entityTypes,
  }) {
    final query = _database.select(_database.localRecords)
      ..where(
        (row) => row.homeId.equals(homeId) & row.entityType.isIn(entityTypes),
      );
    return query.watch();
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
      'pendingSynchronization': line.pendingSynchronization,
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
    pendingSynchronization: json['pendingSynchronization'] == true,
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

double _requiredDecimal(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is! String) {
    throw FormatException('$name must be a decimal string.');
  }
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite) {
    throw FormatException('$name must be a finite decimal string.');
  }
  return parsed;
}

int _moneyMinorUnits(String value) {
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite || parsed < 0) {
    throw const FormatException('Money must be a non-negative decimal string.');
  }
  return (parsed * 100).round();
}

String _moneyDecimal(Money value) {
  if (value.minorUnits < 0 || value.minorUnits > 99999999999999) {
    throw ArgumentError.value(
      value.minorUnits,
      'minorUnits',
      'must fit the purchasing API money range',
    );
  }
  final whole = value.minorUnits ~/ 100;
  final fraction = value.minorUnits.remainder(100);
  return fraction == 0
      ? whole.toString()
      : '$whole.${fraction.toString().padLeft(2, '0')}';
}

String _dateOnly(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Map<String, Object?> _withoutProjectionMetadata(
  Map<String, Object?> representation,
) => <String, Object?>{
  for (final entry in representation.entries)
    if (entry.key != 'id' && entry.key != 'revision') entry.key: entry.value,
};

String _decimal(double value) {
  if (!value.isFinite || value.abs() > 999999999) {
    throw ArgumentError.value(
      value,
      'value',
      'must be finite and fit the API decimal range',
    );
  }
  final fixed = value.toStringAsFixed(8);
  final trimmed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed == '-0' || trimmed.isEmpty ? '0' : trimmed;
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
