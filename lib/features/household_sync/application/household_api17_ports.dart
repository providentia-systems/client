import 'dart:collection';

enum HouseholdApiFailureKind {
  authentication,
  authorization,
  conflict,
  validation,
  unavailable,
  network,
  invalidResponse,
}

final class HouseholdApiException implements Exception {
  const HouseholdApiException({
    required this.kind,
    required this.safeMessage,
    this.statusCode,
  });

  final HouseholdApiFailureKind kind;
  final String safeMessage;
  final int? statusCode;

  @override
  String toString() => 'HouseholdApiException(${kind.name})';
}

final class HouseholdContractUnsupportedException implements Exception {
  const HouseholdContractUnsupportedException({
    required this.operation,
    required this.reason,
  });

  final String operation;
  final String reason;

  @override
  String toString() => 'HouseholdContractUnsupportedException($operation)';
}

final class Api17HomeStockRecord {
  Api17HomeStockRecord({
    required this.id,
    required this.homeId,
    required this.quantity,
    required this.revision,
    this.productId,
    this.packId,
    this.privateName,
    this.originalPackText,
    this.productName,
    this.brandName,
    this.categoryId,
  }) {
    _nonEmpty(id, 'id');
    _nonEmpty(homeId, 'homeId');
    if (!quantity.isFinite) {
      throw ArgumentError.value(quantity, 'quantity', 'must be finite');
    }
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  final String id;
  final String homeId;
  final String? productId;
  final String? packId;
  final String? privateName;
  final String? originalPackText;
  final String? productName;
  final String? brandName;
  final String? categoryId;
  final double quantity;
  final int revision;
}

final class Api17HomeLevelStockAdjustment {
  Api17HomeLevelStockAdjustment({
    required this.operationId,
    required this.homeId,
    required this.homeProductId,
    required this.quantityDelta,
    required this.reason,
  }) {
    _nonEmpty(operationId, 'operationId');
    _nonEmpty(homeId, 'homeId');
    _nonEmpty(homeProductId, 'homeProductId');
    _nonEmpty(reason, 'reason');
    if (!quantityDelta.isFinite || quantityDelta == 0) {
      throw ArgumentError.value(
        quantityDelta,
        'quantityDelta',
        'must be finite and non-zero',
      );
    }
  }

  final String operationId;
  final String homeId;
  final String homeProductId;
  final double quantityDelta;
  final String reason;
}

final class Api17StockMovementReceipt {
  Api17StockMovementReceipt({
    required this.id,
    required this.homeId,
    required this.homeProductId,
    required this.quantityDelta,
    required this.sourceId,
    required this.occurredAt,
  });

  final String id;
  final String homeId;
  final String homeProductId;
  final double quantityDelta;
  final String sourceId;
  final DateTime occurredAt;
}

abstract interface class HouseholdApi17Gateway {
  Future<List<Api17HomeStockRecord>> listHomeStock(String homeId);

  Future<Api17StockMovementReceipt> createHomeLevelStockAdjustment(
    Api17HomeLevelStockAdjustment adjustment,
  );
}

/// Safe 1.7 operation that does not pretend the server has a location axis.
final class Api17HomeLevelStockAdjustmentService {
  const Api17HomeLevelStockAdjustmentService(this._gateway);

  final HouseholdApi17Gateway _gateway;

  Future<Api17StockMovementReceipt> commit(
    Api17HomeLevelStockAdjustment adjustment,
  ) {
    return _gateway.createHomeLevelStockAdjustment(adjustment);
  }
}

List<T> immutableList<T>(Iterable<T> values) =>
    UnmodifiableListView<T>(List<T>.of(values));

void _nonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
