enum PurchaseSource { recentReceipt, historicalImport }

enum PurchaseDatePrecision { exactDay, monthOnly }

final class Money implements Comparable<Money> {
  Money({required this.minorUnits, required this.currency}) {
    if (currency.trim().isEmpty) {
      throw ArgumentError.value(currency, 'currency', 'must not be empty');
    }
  }

  final int minorUnits;
  final String currency;

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits: minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits: minorUnits - other.minorUnits, currency: currency);
  }

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  void _requireSameCurrency(Money other) {
    if (currency != other.currency) {
      throw StateError('Cannot combine different currencies.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      minorUnits == other.minorUnits &&
      currency == other.currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);
}

final class PurchaseLine {
  PurchaseLine({
    required this.id,
    required this.homeId,
    required this.purchasedAt,
    required this.datePrecision,
    required this.storeName,
    required this.rawDescription,
    required this.packSize,
    required this.quantity,
    required this.source,
    this.receiptId,
    this.canonicalItemId,
    this.canonicalName,
    this.lineTotal,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(storeName, 'storeName');
    _requireText(rawDescription, 'rawDescription');
    _requireText(packSize, 'packSize');
    _requirePositive(quantity, 'quantity');
  }

  final String id;
  final String homeId;
  final DateTime purchasedAt;
  final PurchaseDatePrecision datePrecision;
  final String storeName;
  final String rawDescription;
  final String packSize;
  final double quantity;
  final PurchaseSource source;
  final String? receiptId;
  final String? canonicalItemId;
  final String? canonicalName;
  final Money? lineTotal;

  String get displayName => canonicalName?.trim().isNotEmpty == true
      ? canonicalName!
      : rawDescription;
}

final class PurchaseGroup {
  PurchaseGroup({
    required this.id,
    required this.purchasedAt,
    required this.storeName,
    required List<PurchaseLine> lines,
    required this.inferred,
  }) : lines = List<PurchaseLine>.unmodifiable(lines);

  final String id;
  final DateTime purchasedAt;
  final String storeName;
  final List<PurchaseLine> lines;

  /// True when legacy data had no receipt identity and date/store grouping was
  /// used only for display parity.
  final bool inferred;

  Money? get total {
    final priced = lines.where((line) => line.lineTotal != null).toList();
    if (priced.isEmpty || priced.length != lines.length) {
      return null;
    }
    return priced
        .map((line) => line.lineTotal!)
        .reduce((left, right) => left + right);
  }
}

final class MonthlyPurchaseSummary {
  const MonthlyPurchaseSummary({
    required this.month,
    required this.lineCount,
    required this.quantity,
  });

  final DateTime month;
  final int lineCount;
  final double quantity;
}

final class PriceObservation {
  PriceObservation({
    required this.id,
    required this.homeId,
    required this.productPackId,
    required this.storeName,
    required this.observedAt,
    required this.quantity,
    required this.total,
    this.baseUnitsPerPurchasedUnit = 1,
    this.isSale = false,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(productPackId, 'productPackId');
    _requireText(storeName, 'storeName');
    _requirePositive(quantity, 'quantity');
    _requirePositive(baseUnitsPerPurchasedUnit, 'baseUnitsPerPurchasedUnit');
    if (total.minorUnits < 0) {
      throw ArgumentError.value(
        total.minorUnits,
        'total',
        'must not be negative',
      );
    }
  }

  final String id;
  final String homeId;
  final String productPackId;
  final String storeName;
  final DateTime observedAt;
  final double quantity;
  final double baseUnitsPerPurchasedUnit;
  final Money total;
  final bool isSale;

  double get minorUnitsPerBaseUnit =>
      total.minorUnits / (quantity * baseUnitsPerPurchasedUnit);
}

final class PriceStatistics {
  const PriceStatistics({
    required this.homeId,
    required this.productPackId,
    required this.currency,
    required this.observationCount,
    required this.averageMinorUnitsPerBaseUnit,
    required this.lowest,
    required this.highest,
    required this.latest,
  });

  final String homeId;
  final String productPackId;
  final String currency;
  final int observationCount;
  final double averageMinorUnitsPerBaseUnit;
  final PriceObservation lowest;
  final PriceObservation highest;
  final PriceObservation latest;
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requirePositive(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive and finite');
  }
}
