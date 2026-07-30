enum InventoryView { counted, itemMaster }

enum CountSessionStatus { open, closed, cancelled }

enum CountLineStatus { outstanding, confirmed }

enum CountSource { manual, photo }

enum StockMovementKind {
  openingBalance,
  purchase,
  countAdjustment,
  manualAdjustment,
  consumption,
  waste,
  transferIn,
  transferOut,
  reversal,
}

final class InventoryItem {
  InventoryItem({
    required this.id,
    required this.homeId,
    required this.canonicalName,
    required this.packSize,
    required this.category,
    this.brand = '',
    this.unit = 'units',
    List<String> aliases = const <String>[],
    this.currentQuantity,
    this.isHomeProduct = false,
  }) : aliases = List<String>.unmodifiable(aliases) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(canonicalName, 'canonicalName');
    _requireText(packSize, 'packSize');
    _requireText(category, 'category');
    _requireText(unit, 'unit');
    _requireQuantity(currentQuantity, 'currentQuantity', nullable: true);
  }

  final String id;
  final String homeId;
  final String canonicalName;
  final String packSize;
  final String category;
  final String brand;
  final String unit;
  final List<String> aliases;
  final double? currentQuantity;
  final bool isHomeProduct;

  bool get isCounted => currentQuantity != null;

  InventoryItem copyWith({
    double? currentQuantity,
    bool clearQuantity = false,
  }) {
    return InventoryItem(
      id: id,
      homeId: homeId,
      canonicalName: canonicalName,
      packSize: packSize,
      category: category,
      brand: brand,
      unit: unit,
      aliases: aliases,
      currentQuantity: clearQuantity
          ? null
          : (currentQuantity ?? this.currentQuantity),
      isHomeProduct: isHomeProduct,
    );
  }
}

final class InventorySearchCriteria {
  const InventorySearchCriteria({
    this.query = '',
    this.category,
    this.view = InventoryView.counted,
    this.confirmedItemIds = const <String>{},
  });

  final String query;
  final String? category;
  final InventoryView view;
  final Set<String> confirmedItemIds;
}

final class StockPhotoReference {
  StockPhotoReference({
    required this.id,
    required this.localReference,
    required this.addedAt,
    this.name = '',
    this.mimeType,
  }) {
    _requireText(id, 'id');
    _requireText(localReference, 'localReference');
  }

  final String id;
  final String localReference;
  final DateTime addedAt;
  final String name;
  final String? mimeType;
}

final class StockCountLine {
  StockCountLine({
    required this.id,
    required this.itemId,
    required this.status,
    required this.source,
    this.observedQuantity,
    this.photoId,
    this.possibleDuplicate = false,
    this.duplicateReviewed = false,
  }) {
    _requireText(id, 'id');
    _requireText(itemId, 'itemId');
    _requireQuantity(observedQuantity, 'observedQuantity', nullable: true);
    if (status == CountLineStatus.confirmed && observedQuantity == null) {
      throw ArgumentError('A confirmed count line requires a quantity.');
    }
    if (source == CountSource.photo && (photoId == null || photoId!.isEmpty)) {
      throw ArgumentError('A photo count line requires a photoId.');
    }
  }

  final String id;
  final String itemId;
  final CountLineStatus status;
  final CountSource source;
  final double? observedQuantity;
  final String? photoId;
  final bool possibleDuplicate;
  final bool duplicateReviewed;

  StockCountLine copyWith({
    CountLineStatus? status,
    double? observedQuantity,
    bool? possibleDuplicate,
    bool? duplicateReviewed,
  }) {
    return StockCountLine(
      id: id,
      itemId: itemId,
      status: status ?? this.status,
      source: source,
      observedQuantity: observedQuantity ?? this.observedQuantity,
      photoId: photoId,
      possibleDuplicate: possibleDuplicate ?? this.possibleDuplicate,
      duplicateReviewed: duplicateReviewed ?? this.duplicateReviewed,
    );
  }
}

final class StockCountSession {
  StockCountSession({
    required this.id,
    required this.homeId,
    required this.locationId,
    required this.startedAt,
    this.status = CountSessionStatus.open,
    this.closedAt,
    List<StockPhotoReference> photos = const <StockPhotoReference>[],
    List<StockCountLine> lines = const <StockCountLine>[],
  }) : photos = List<StockPhotoReference>.unmodifiable(photos),
       lines = List<StockCountLine>.unmodifiable(lines) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(locationId, 'locationId');
    if (status == CountSessionStatus.closed && closedAt == null) {
      throw ArgumentError('A closed session requires closedAt.');
    }
  }

  final String id;
  final String homeId;
  final String locationId;
  final DateTime startedAt;
  final CountSessionStatus status;
  final DateTime? closedAt;
  final List<StockPhotoReference> photos;
  final List<StockCountLine> lines;

  Iterable<StockCountLine> get outstandingLines =>
      lines.where((line) => line.status == CountLineStatus.outstanding);

  Iterable<StockCountLine> get confirmedLines =>
      lines.where((line) => line.status == CountLineStatus.confirmed);

  StockCountSession attachPhoto(StockPhotoReference photo) {
    _requireOpen();
    if (photos.any((entry) => entry.id == photo.id)) {
      return this;
    }
    return _copy(photos: <StockPhotoReference>[...photos, photo]);
  }

  StockCountSession recordLine(StockCountLine line) {
    _requireOpen();
    if (line.source == CountSource.photo &&
        !photos.any((photo) => photo.id == line.photoId)) {
      throw StateError('The count line references an unattached photo.');
    }
    final sameItemFromAnotherPhoto = lines.any(
      (entry) =>
          entry.itemId == line.itemId &&
          entry.source == CountSource.photo &&
          entry.photoId != line.photoId,
    );
    final next = <StockCountLine>[
      ...lines.where((entry) => entry.id != line.id),
      line.copyWith(
        possibleDuplicate: line.possibleDuplicate || sameItemFromAnotherPhoto,
      ),
    ];
    if (sameItemFromAnotherPhoto) {
      for (var index = 0; index < next.length; index++) {
        if (next[index].itemId == line.itemId) {
          next[index] = next[index].copyWith(possibleDuplicate: true);
        }
      }
    }
    return _copy(lines: next);
  }

  StockCountSession markDuplicateReviewed(String lineId) {
    _requireOpen();
    return _copy(
      lines: lines
          .map(
            (line) => line.id == lineId
                ? line.copyWith(duplicateReviewed: true)
                : line,
          )
          .toList(growable: false),
    );
  }

  StockCountSession close(DateTime at) {
    _requireOpen();
    if (outstandingLines.isNotEmpty) {
      throw StateError('Outstanding count lines must be resolved first.');
    }
    if (lines.any(
      (line) => line.possibleDuplicate && !line.duplicateReviewed,
    )) {
      throw StateError('Possible duplicate photo counts require review.');
    }
    return _copy(status: CountSessionStatus.closed, closedAt: at.toUtc());
  }

  StockCountSession cancel() {
    _requireOpen();
    return _copy(status: CountSessionStatus.cancelled);
  }

  StockCountSession _copy({
    CountSessionStatus? status,
    DateTime? closedAt,
    List<StockPhotoReference>? photos,
    List<StockCountLine>? lines,
  }) {
    return StockCountSession(
      id: id,
      homeId: homeId,
      locationId: locationId,
      startedAt: startedAt,
      status: status ?? this.status,
      closedAt: closedAt ?? this.closedAt,
      photos: photos ?? this.photos,
      lines: lines ?? this.lines,
    );
  }

  void _requireOpen() {
    if (status != CountSessionStatus.open) {
      throw StateError('Only an open count session can be changed.');
    }
  }
}

final class StockMovement {
  StockMovement({
    required this.id,
    required this.homeId,
    required this.itemId,
    required this.locationId,
    required this.quantityDelta,
    required this.kind,
    required this.occurredAt,
    required this.sourceId,
    this.reason,
    this.reversalOf,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(itemId, 'itemId');
    _requireText(locationId, 'locationId');
    _requireText(sourceId, 'sourceId');
    _requireQuantity(quantityDelta, 'quantityDelta', allowNegative: true);
    if (quantityDelta == 0) {
      throw ArgumentError.value(
        quantityDelta,
        'quantityDelta',
        'must not be zero',
      );
    }
    if ((kind == StockMovementKind.manualAdjustment ||
            kind == StockMovementKind.reversal) &&
        (reason == null || reason!.trim().isEmpty)) {
      throw ArgumentError('Manual adjustments and reversals require a reason.');
    }
    if (kind == StockMovementKind.reversal &&
        (reversalOf == null || reversalOf!.isEmpty)) {
      throw ArgumentError('A reversal requires the original movement ID.');
    }
  }

  final String id;
  final String homeId;
  final String itemId;
  final String locationId;
  final double quantityDelta;
  final StockMovementKind kind;
  final DateTime occurredAt;
  final String sourceId;
  final String? reason;
  final String? reversalOf;
}

final class InventoryBalance {
  const InventoryBalance({
    required this.homeId,
    required this.itemId,
    required this.locationId,
    required this.quantity,
    required this.asOf,
  });

  final String homeId;
  final String itemId;
  final String locationId;
  final double quantity;
  final DateTime asOf;
}

final class ManualAdjustmentIntent {
  ManualAdjustmentIntent({
    required this.id,
    required this.homeId,
    required this.itemId,
    required this.locationId,
    required this.projectedQuantity,
    required this.observedQuantity,
    required this.reason,
    required this.createdAt,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(itemId, 'itemId');
    _requireText(locationId, 'locationId');
    _requireText(reason, 'reason');
    _requireQuantity(projectedQuantity, 'projectedQuantity');
    _requireQuantity(observedQuantity, 'observedQuantity');
  }

  final String id;
  final String homeId;
  final String itemId;
  final String locationId;
  final double projectedQuantity;
  final double observedQuantity;
  final String reason;
  final DateTime createdAt;

  double get delta => observedQuantity - projectedQuantity;

  StockMovement? toMovement(String movementId) {
    if (delta == 0) {
      return null;
    }
    return StockMovement(
      id: movementId,
      homeId: homeId,
      itemId: itemId,
      locationId: locationId,
      quantityDelta: delta,
      kind: StockMovementKind.manualAdjustment,
      occurredAt: createdAt,
      sourceId: id,
      reason: reason.trim(),
    );
  }
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requireQuantity(
  double? value,
  String name, {
  bool nullable = false,
  bool allowNegative = false,
}) {
  if (value == null && nullable) {
    return;
  }
  if (value == null || !value.isFinite || (!allowNegative && value < 0)) {
    throw ArgumentError.value(value, name, 'must be a valid quantity');
  }
}
