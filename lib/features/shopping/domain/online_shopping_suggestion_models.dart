import 'dart:collection';

enum ShoppingSuggestionConfidenceBand { low, medium, high }

enum OnlineShoppingSuggestionStatus { active, accepted, dismissed, snoozed }

enum OnlineSuggestionDecision { accepted, edited, dismissed, snoozed }

/// An exact API fixed-point decimal. The original representation is retained
/// so transport and feedback never round-trip through binary floating point.
final class ExactDecimal implements Comparable<ExactDecimal> {
  factory ExactDecimal(String value) {
    if (!_fixedDecimal.hasMatch(value)) {
      throw ArgumentError.value(value, 'value', 'must be a fixed decimal');
    }
    return ExactDecimal._(value);
  }

  const ExactDecimal._(this.value);

  final String value;

  bool get isNegative => value.startsWith('-') && !isZero;
  bool get isZero => _scaled == BigInt.zero;
  bool get isPositive => _scaled > BigInt.zero;
  bool get isNonNegative => _scaled >= BigInt.zero;

  /// Shopping-list quantities are currently represented as doubles. This is
  /// the single explicit conversion point; API/cache/feedback keep [value].
  double toListQuantity() => double.parse(value);

  BigInt get _scaled {
    final negative = value.startsWith('-');
    final unsigned = negative ? value.substring(1) : value;
    final pieces = unsigned.split('.');
    final whole = pieces.first;
    final fraction = pieces.length == 1 ? '' : pieces.last;
    final scaled = BigInt.parse('$whole${fraction.padRight(8, '0')}');
    return negative ? -scaled : scaled;
  }

  @override
  int compareTo(ExactDecimal other) => _scaled.compareTo(other._scaled);

  @override
  String toString() => value;
}

final class OnlineShoppingSuggestion {
  OnlineShoppingSuggestion({
    required this.id,
    required this.homeId,
    required this.homeProductId,
    required this.productName,
    required this.expectedDemand,
    required this.safetyStock,
    required this.factualStock,
    required this.usableStock,
    required this.requiredQuantity,
    required this.confidenceScore,
    required this.confidenceBand,
    required this.status,
    required this.expiresAt,
    required this.modelVersion,
    required this.asOf,
    required this.inputWatermark,
    this.packText,
    this.selectedPackId,
    this.packCount,
  }) {
    _requireText(id, 'id');
    _requireText(homeId, 'homeId');
    _requireText(homeProductId, 'homeProductId');
    _requireText(productName, 'productName');
    _requireText(modelVersion, 'modelVersion');
    _requireText(inputWatermark, 'inputWatermark');
    if (requiredQuantity.isNegative) {
      throw ArgumentError.value(
        requiredQuantity,
        'requiredQuantity',
        'must not be negative',
      );
    }
    if (confidenceScore.isNegative ||
        confidenceScore.compareTo(ExactDecimal('1')) > 0) {
      throw ArgumentError.value(
        confidenceScore,
        'confidenceScore',
        'must be between zero and one',
      );
    }
    if (!asOf.isUtc || !expiresAt.isUtc || !expiresAt.isAfter(asOf)) {
      throw ArgumentError('Suggestion timestamps must be UTC and advance.');
    }
    if ((selectedPackId == null) != (packCount == null) ||
        (packCount != null && packCount! < 0)) {
      throw ArgumentError(
        'Selected pack identity and a non-negative pack count must coexist.',
      );
    }
  }

  final String id;
  final String homeId;
  final String homeProductId;
  final String productName;
  final String? packText;
  final ExactDecimal expectedDemand;
  final ExactDecimal safetyStock;
  final ExactDecimal factualStock;
  final ExactDecimal usableStock;
  final ExactDecimal requiredQuantity;
  final String? selectedPackId;
  final int? packCount;
  final ExactDecimal confidenceScore;
  final ShoppingSuggestionConfidenceBand confidenceBand;
  final OnlineShoppingSuggestionStatus status;
  final DateTime expiresAt;
  final String modelVersion;
  final DateTime asOf;
  final String inputWatermark;

  bool activeAt(DateTime now) =>
      status == OnlineShoppingSuggestionStatus.active &&
      expiresAt.isAfter(now.toUtc());
}

final class ShoppingSuggestionFactor {
  const ShoppingSuggestionFactor({
    required this.key,
    this.value,
    this.days,
    this.nextExpectedShoppingAt,
  });

  final String key;
  final ExactDecimal? value;
  final int? days;
  final DateTime? nextExpectedShoppingAt;
}

final class SuggestionPackOption {
  const SuggestionPackOption({
    required this.packId,
    required this.currency,
    required this.packCount,
    required this.effectiveTotal,
    required this.excessQuantity,
    required this.priceObservedAt,
    required this.selected,
    required this.reason,
    this.storeId,
  });

  final String packId;
  final String? storeId;
  final String currency;
  final int packCount;
  final ExactDecimal effectiveTotal;
  final ExactDecimal excessQuantity;
  final DateTime priceObservedAt;
  final bool selected;
  final String reason;
}

final class OnlineShoppingSuggestionExplanation {
  OnlineShoppingSuggestionExplanation({
    required this.id,
    required this.homeId,
    required this.homeProductId,
    required this.requiredQuantity,
    required this.confidenceScore,
    required this.confidenceBand,
    required List<ShoppingSuggestionFactor> factors,
    required List<String> limitations,
    required List<SuggestionPackOption> packOptions,
    required this.modelVersion,
    required this.asOf,
    required this.inputWatermark,
  }) : factors = UnmodifiableListView<ShoppingSuggestionFactor>(factors),
       limitations = UnmodifiableListView<String>(limitations),
       packOptions = UnmodifiableListView<SuggestionPackOption>(packOptions);

  final String id;
  final String homeId;
  final String homeProductId;
  final ExactDecimal requiredQuantity;
  final ExactDecimal confidenceScore;
  final ShoppingSuggestionConfidenceBand confidenceBand;
  final List<ShoppingSuggestionFactor> factors;
  final List<String> limitations;
  final List<SuggestionPackOption> packOptions;
  final String modelVersion;
  final DateTime asOf;
  final String inputWatermark;
}

final class OnlineSuggestionFeedback {
  OnlineSuggestionFeedback({
    required this.homeId,
    required this.suggestionId,
    required this.decision,
    required this.resultQuantity,
    required this.reason,
  }) {
    _requireText(homeId, 'homeId');
    _requireText(suggestionId, 'suggestionId');
    _requireText(reason, 'reason');
    if (reason.length > 191) {
      throw ArgumentError.value(reason, 'reason', 'must be at most 191 chars');
    }
    if (resultQuantity?.isNegative ?? false) {
      throw ArgumentError.value(
        resultQuantity,
        'resultQuantity',
        'must not be negative',
      );
    }
    final requiresQuantity =
        decision == OnlineSuggestionDecision.accepted ||
        decision == OnlineSuggestionDecision.edited;
    if (requiresQuantity != (resultQuantity != null)) {
      throw ArgumentError(
        'Accepted/edited feedback requires a result quantity; '
        'dismissed/snoozed feedback must not include one.',
      );
    }
  }

  final String homeId;
  final String suggestionId;
  final OnlineSuggestionDecision decision;
  final ExactDecimal? resultQuantity;
  final String reason;
}

final class OnlineSuggestionFeedbackReceipt {
  const OnlineSuggestionFeedbackReceipt({required this.id});

  final String id;
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

final RegExp _fixedDecimal = RegExp(r'^-?(?:0|[1-9]\d{0,8})(?:\.\d{1,8})?$');
