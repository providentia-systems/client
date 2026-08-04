import 'dart:async';

import 'package:providentia/features/household_sync/application/household_api17_ports.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';

/// API 1.7 household projection with strict compatibility boundaries.
///
/// Home stock is authoritative online data. Other Phase 5 interfaces are
/// retained so current controllers can be composed, but operations whose
/// domain semantics cannot be represented by API 1.7 fail explicitly.
final class Api17OnlineHouseholdRepository
    implements InventoryRepository, PurchaseRepository, ShoppingRepository {
  Api17OnlineHouseholdRepository(this._gateway);

  final HouseholdApi17Gateway _gateway;
  final Map<String, StreamController<List<InventoryItem>>> _itemUpdates =
      <String, StreamController<List<InventoryItem>>>{};
  bool _disposed = false;

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) async* {
    _ensureOpen();
    final updates = _controller(homeId);
    yield await refreshItems(homeId);
    yield* updates.stream;
  }

  Future<List<InventoryItem>> refreshItems(String homeId) async {
    _ensureOpen();
    final records = await _gateway.listHomeStock(homeId);
    if (records.any((record) => record.homeId != homeId)) {
      throw const HouseholdApiException(
        kind: HouseholdApiFailureKind.invalidResponse,
        safeMessage: 'The server mixed data from different homes.',
      );
    }
    final items = immutableList(records.map(_inventoryItem));
    final controller = _itemUpdates[homeId];
    if (controller != null && !controller.isClosed) {
      controller.add(items);
    }
    return items;
  }

  @override
  Stream<StockCountSession?> watchActiveCountSession({required String homeId}) {
    return Stream<StockCountSession?>.error(
      _unsupported(
        'watchActiveCountSession',
        'API 1.7 omits startedAt, media references, duplicate review, and the '
            'client revision needed by the Phase 5 count-session model.',
      ),
    );
  }

  @override
  Future<void> saveCountSession(StockCountSession session) {
    return Future<void>.error(
      _unsupported(
        'saveCountSession',
        'API 1.7 count writes require server revisions, reliability, and notes '
            'that the Phase 5 aggregate does not preserve.',
      ),
    );
  }

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) {
    return Future<void>.error(
      _unsupported(
        'commitManualAdjustment',
        'The Phase 5 intent is location-scoped, while API 1.7 adjustments are '
            'home-product totals and have no location field.',
      ),
    );
  }

  @override
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId}) {
    return Stream<List<PurchaseLine>>.error(
      _unsupported(
        'watchPurchaseLines',
        'API 1.7 publishes aggregate purchase reports, not the receipt-line '
            'projection required by PurchaseRepository.',
      ),
    );
  }

  @override
  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  }) {
    return Stream<List<PriceObservation>>.error(
      _unsupported(
        'watchPriceObservations',
        'API 1.7 publishes comparisons, not raw observations with the fields '
            'required by PriceObservation.',
      ),
    );
  }

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) {
    return Stream<ShoppingList>.error(
      _unsupported(
        'watchActiveList',
        'API 1.7 does not identify one active list and omits createdAt and line '
            'origin required by the Phase 5 shopping aggregate.',
      ),
    );
  }

  @override
  Future<void> saveList(ShoppingList list) {
    return Future<void>.error(
      _unsupported(
        'saveList',
        'The Phase 5 aggregate omits server revisions and API 1.7 has no '
            'quantity-update or line-delete operation for atomic replacement.',
      ),
    );
  }

  @override
  Future<void> recordFeedback(SuggestionFeedback feedback) {
    return Future<void>.error(
      _unsupported(
        'recordFeedback',
        'The Phase 5 feedback model has no server suggestion identifier and '
            'cannot target the API 1.7 feedback resource safely.',
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final controllers = _itemUpdates.values.toList(growable: false);
    _itemUpdates.clear();
    await Future.wait<void>(
      controllers.map((controller) => controller.close()),
    );
  }

  StreamController<List<InventoryItem>> _controller(String homeId) {
    return _itemUpdates.putIfAbsent(
      homeId,
      () => StreamController<List<InventoryItem>>.broadcast(sync: true),
    );
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('Api17OnlineHouseholdRepository has been disposed.');
    }
  }
}

InventoryItem _inventoryItem(Api17HomeStockRecord record) {
  final name = record.productName ?? record.privateName ?? 'Unnamed product';
  return InventoryItem(
    id: record.id,
    homeId: record.homeId,
    canonicalName: name,
    packSize: record.originalPackText ?? 'Pack details unavailable',
    category: record.categoryId ?? 'Uncategorised',
    brand: record.brandName ?? '',
    currentQuantity: record.quantity,
    isHomeProduct: record.productId == null,
  );
}

HouseholdContractUnsupportedException _unsupported(
  String operation,
  String reason,
) =>
    HouseholdContractUnsupportedException(operation: operation, reason: reason);
