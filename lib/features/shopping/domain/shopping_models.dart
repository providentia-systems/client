import 'package:providentia/features/purchasing/domain/purchase_models.dart';

enum ShoppingLineOrigin { manual, suggestion }

enum EstimateConfidence { insufficient, low, medium, high }

enum SuggestionFeedbackKind { accepted, dismissed, snoozed, quantityEdited }

final class ShoppingListLine {
  ShoppingListLine({
    required this.id,
    required this.homeId,
    required this.name,
    required this.quantity,
    required this.origin,
    required this.createdAt,
    this.suggestionId,
    this.homeProductId,
    this.selectedPackId,
    @Deprecated(
      'Legacy field retained until the Drift shopping projection is migrated. '
      'New suggestion lines must use suggestionId, homeProductId, and '
      'selectedPackId.',
    )
    this.productPackId,
    this.checked = false,
    this.explanation,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(name, 'name');
    _requireNonNegative(quantity, 'quantity');
    for (final (value, label) in <(String?, String)>[
      (suggestionId, 'suggestionId'),
      (homeProductId, 'homeProductId'),
      (selectedPackId, 'selectedPackId'),
      (productPackId, 'productPackId'),
    ]) {
      if (value != null) _requireText(value, label);
    }
    if (suggestionId != null &&
        (origin != ShoppingLineOrigin.suggestion || homeProductId == null)) {
      throw ArgumentError(
        'A server suggestion line requires suggestion origin and a distinct '
        'home-product identity.',
      );
    }
  }

  final String id;
  final String homeId;
  final String name;
  final double quantity;
  final ShoppingLineOrigin origin;
  final DateTime createdAt;
  final String? suggestionId;
  final String? homeProductId;
  final String? selectedPackId;

  /// Legacy local suggestion identity. It was historically populated with a
  /// home-product ID despite its name, so it must not be used by new code.
  @Deprecated(
    'Use suggestionId, homeProductId, and selectedPackId. This remains only '
    'as the narrow migration hook for the existing Drift projection.',
  )
  final String? productPackId;
  final bool checked;
  final String? explanation;

  ShoppingListLine copyWith({double? quantity, bool? checked}) {
    return ShoppingListLine(
      id: id,
      homeId: homeId,
      name: name,
      quantity: quantity ?? this.quantity,
      origin: origin,
      createdAt: createdAt,
      suggestionId: suggestionId,
      homeProductId: homeProductId,
      selectedPackId: selectedPackId,
      productPackId: productPackId,
      checked: checked ?? this.checked,
      explanation: explanation,
    );
  }
}

final class ShoppingList {
  ShoppingList({
    required this.id,
    required this.homeId,
    required this.name,
    required this.createdAt,
    List<ShoppingListLine> lines = const <ShoppingListLine>[],
  }) : lines = List<ShoppingListLine>.unmodifiable(lines) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(name, 'name');
    if (lines.any((line) => line.homeId != homeId)) {
      throw StateError('Shopping-list lines must belong to the same home.');
    }
  }

  final String id;
  final String homeId;
  final String name;
  final DateTime createdAt;
  final List<ShoppingListLine> lines;

  int get completedCount => lines.where((line) => line.checked).length;
  double get progress => lines.isEmpty ? 0 : completedCount / lines.length;

  ShoppingList add(ShoppingListLine line) {
    if (line.homeId != homeId) {
      throw StateError('Cannot add a line from another home.');
    }
    if (lines.any((entry) => entry.id == line.id)) {
      throw StateError('Shopping-list line IDs must be unique.');
    }
    return _copy(<ShoppingListLine>[...lines, line]);
  }

  ShoppingList toggle(String lineId) {
    if (!lines.any((line) => line.id == lineId)) {
      throw StateError('Unknown shopping-list line.');
    }
    return _copy(
      lines
          .map(
            (line) => line.id == lineId
                ? line.copyWith(checked: !line.checked)
                : line,
          )
          .toList(growable: false),
    );
  }

  ShoppingList updateQuantity(String lineId, double quantity) {
    _requireNonNegative(quantity, 'quantity');
    if (!lines.any((line) => line.id == lineId)) {
      throw StateError('Unknown shopping-list line.');
    }
    return _copy(
      lines
          .map(
            (line) =>
                line.id == lineId ? line.copyWith(quantity: quantity) : line,
          )
          .toList(growable: false),
    );
  }

  ShoppingList _copy(List<ShoppingListLine> next) => ShoppingList(
    id: id,
    homeId: homeId,
    name: name,
    createdAt: createdAt,
    lines: next,
  );
}

final class ReliableCountPoint {
  ReliableCountPoint({required this.observedAt, required this.quantity}) {
    _requireNonNegative(quantity, 'quantity');
  }

  final DateTime observedAt;
  final double quantity;
}

final class RestockEvent {
  RestockEvent({required this.occurredAt, required this.quantity}) {
    _requireNonNegative(quantity, 'quantity');
  }

  final DateTime occurredAt;
  final double quantity;
}

final class ConsumptionEstimate {
  const ConsumptionEstimate({
    required this.confidence,
    required this.dailyRate,
    required this.coveredDays,
    required this.intervalCount,
    required this.explanation,
  });

  const ConsumptionEstimate.insufficient(String reason)
    : confidence = EstimateConfidence.insufficient,
      dailyRate = 0,
      coveredDays = 0,
      intervalCount = 0,
      explanation = reason;

  final EstimateConfidence confidence;
  final double dailyRate;
  final int coveredDays;
  final int intervalCount;
  final String explanation;

  bool get hasEnoughEvidence => confidence != EstimateConfidence.insufficient;
}

final class PackOption {
  PackOption({
    required this.id,
    required this.unitsPerPack,
    this.price,
    this.preferred = false,
    this.available = true,
  }) {
    _requireText(id, 'id');
    if (!unitsPerPack.isFinite || unitsPerPack <= 0) {
      throw ArgumentError.value(
        unitsPerPack,
        'unitsPerPack',
        'must be positive and finite',
      );
    }
  }

  final String id;
  final double unitsPerPack;
  final Money? price;
  final bool preferred;
  final bool available;
}

final class PackRecommendation {
  const PackRecommendation({
    required this.option,
    required this.packCount,
    required this.requiredUnits,
  });

  final PackOption option;
  final int packCount;
  final double requiredUnits;

  double get suppliedUnits => option.unitsPerPack * packCount;
  double get overage => suppliedUnits - requiredUnits;
  Money? get totalPrice => option.price == null
      ? null
      : Money(
          minorUnits: option.price!.minorUnits * packCount,
          currency: option.price!.currency,
        );
}

final class ShoppingSuggestion {
  const ShoppingSuggestion({
    required this.homeId,
    required this.productPackId,
    required this.quantityNeeded,
    required this.confidence,
    required this.explanation,
    required this.dataCoverageDays,
    this.packRecommendation,
  });

  final String homeId;
  final String productPackId;
  final double quantityNeeded;
  final EstimateConfidence confidence;
  final String explanation;
  final int dataCoverageDays;
  final PackRecommendation? packRecommendation;

  bool get shouldSuggest => quantityNeeded > 0;
}

final class SuggestionFeedback {
  SuggestionFeedback({
    required this.id,
    required this.homeId,
    required this.productPackId,
    required this.kind,
    required this.recordedAt,
    this.originalQuantity,
    this.updatedQuantity,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(productPackId, 'productPackId');
    _requireNonNegative(originalQuantity, 'originalQuantity', nullable: true);
    _requireNonNegative(updatedQuantity, 'updatedQuantity', nullable: true);
    if (kind == SuggestionFeedbackKind.quantityEdited &&
        updatedQuantity == null) {
      throw ArgumentError('Edited feedback requires updatedQuantity.');
    }
  }

  final String id;
  final String homeId;
  final String productPackId;
  final SuggestionFeedbackKind kind;
  final DateTime recordedAt;
  final double? originalQuantity;
  final double? updatedQuantity;
}

final class SuggestionFeedbackSummary {
  const SuggestionFeedbackSummary({
    required this.total,
    required this.accepted,
    required this.dismissed,
    required this.snoozed,
    required this.edited,
  });

  final int total;
  final int accepted;
  final int dismissed;
  final int snoozed;
  final int edited;

  double get acceptanceRate => total == 0 ? 0 : accepted / total;
  double get overrideRate => total == 0 ? 0 : edited / total;
}

final class HistoricalDemand {
  HistoricalDemand({required this.day, required this.quantity}) {
    _requireNonNegative(quantity, 'quantity');
  }

  final DateTime day;
  final double quantity;
}

typedef DemandForecaster =
    double Function(List<HistoricalDemand> training, int horizonDays);

final class BacktestResult {
  const BacktestResult({
    required this.sampleCount,
    required this.meanAbsoluteError,
    required this.bias,
    required this.overbuyRate,
    required this.missedDemandRate,
    required this.totalOverbuy,
    required this.totalMissedDemand,
  });

  final int sampleCount;
  final double meanAbsoluteError;
  final double bias;
  final double overbuyRate;
  final double missedDemandRate;
  final double totalOverbuy;
  final double totalMissedDemand;
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requireNonNegative(double? value, String name, {bool nullable = false}) {
  if (value == null && nullable) return;
  if (value == null || !value.isFinite || value < 0) {
    throw ArgumentError.value(value, name, 'must be non-negative and finite');
  }
}
