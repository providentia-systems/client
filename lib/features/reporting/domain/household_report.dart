abstract interface class HomeScopedReportLine {
  String get homeId;
}

enum EvidenceConfidence { insufficient, low, medium, high }

final class InventoryBalanceReportLine implements HomeScopedReportLine {
  const InventoryBalanceReportLine({
    required this.homeId,
    required this.homeProductId,
    required this.productName,
    required this.locationName,
    required this.quantity,
    required this.unit,
    required this.asOf,
    required this.hasDataQualityWarning,
  });

  @override
  final String homeId;
  final String homeProductId;
  final String productName;
  final String locationName;
  final double quantity;
  final String unit;
  final DateTime asOf;
  final bool hasDataQualityWarning;
}

final class StockMovementReportLine implements HomeScopedReportLine {
  const StockMovementReportLine({
    required this.homeId,
    required this.movementId,
    required this.productName,
    required this.movementType,
    required this.signedQuantity,
    required this.unit,
    required this.effectiveAt,
    this.reversalOfMovementId,
  });

  @override
  final String homeId;
  final String movementId;
  final String productName;
  final String movementType;
  final double signedQuantity;
  final String unit;
  final DateTime effectiveAt;
  final String? reversalOfMovementId;
}

final class MonthlyPurchaseReportLine implements HomeScopedReportLine {
  const MonthlyPurchaseReportLine({
    required this.homeId,
    required this.productName,
    required this.yearMonth,
    required this.originalQuantity,
    required this.originalUnit,
    this.normalizedBaseQuantity,
    this.normalizedBaseUnit,
  });

  @override
  final String homeId;
  final String productName;
  final String yearMonth;
  final double originalQuantity;
  final String originalUnit;
  final double? normalizedBaseQuantity;
  final String? normalizedBaseUnit;
}

final class ConsumptionEvidenceReportLine implements HomeScopedReportLine {
  const ConsumptionEvidenceReportLine({
    required this.homeId,
    required this.productName,
    required this.confidence,
    required this.eligibleIntervalCount,
    required this.coveredDays,
    required this.limitation,
    this.estimatedDailyBaseQuantity,
    this.baseUnit,
  });

  @override
  final String homeId;
  final String productName;
  final EvidenceConfidence confidence;
  final int eligibleIntervalCount;
  final int coveredDays;
  final String limitation;
  final double? estimatedDailyBaseQuantity;
  final String? baseUnit;

  bool get hasEstimate {
    return estimatedDailyBaseQuantity != null &&
        confidence != EvidenceConfidence.insufficient;
  }
}

final class CountVarianceReportLine implements HomeScopedReportLine {
  const CountVarianceReportLine({
    required this.homeId,
    required this.productName,
    required this.locationName,
    required this.projectedQuantity,
    required this.countedQuantity,
    required this.unit,
    required this.countedAt,
  });

  @override
  final String homeId;
  final String productName;
  final String locationName;
  final double projectedQuantity;
  final double countedQuantity;
  final String unit;
  final DateTime countedAt;

  double get variance => countedQuantity - projectedQuantity;
}

final class PriceObservationReportLine implements HomeScopedReportLine {
  const PriceObservationReportLine({
    required this.homeId,
    required this.productName,
    required this.packText,
    required this.storeName,
    required this.currency,
    required this.netPrice,
    required this.observedAt,
    required this.observationCount,
    required this.comparable,
    this.pricePerBaseUnit,
    this.baseUnit,
  });

  @override
  final String homeId;
  final String productName;
  final String packText;
  final String storeName;
  final String currency;
  final double netPrice;
  final DateTime observedAt;
  final int observationCount;
  final bool comparable;
  final double? pricePerBaseUnit;
  final String? baseUnit;
}

final class UnresolvedLineReportLine implements HomeScopedReportLine {
  const UnresolvedLineReportLine({
    required this.homeId,
    required this.lineId,
    required this.rawDescription,
    required this.sourceType,
    required this.observedAt,
  });

  @override
  final String homeId;
  final String lineId;
  final String rawDescription;
  final String sourceType;
  final DateTime observedAt;
}

final class SuggestionFeedbackReportLine implements HomeScopedReportLine {
  const SuggestionFeedbackReportLine({
    required this.homeId,
    required this.suggestionId,
    required this.productName,
    required this.action,
    required this.algorithmVersion,
    required this.recordedAt,
  });

  @override
  final String homeId;
  final String suggestionId;
  final String productName;
  final String action;
  final String algorithmVersion;
  final DateTime recordedAt;
}

final class BacktestCoverageReport implements HomeScopedReportLine {
  const BacktestCoverageReport({
    required this.homeId,
    required this.algorithmVersion,
    required this.totalCandidatePeriods,
    required this.evaluatedPeriods,
    required this.suggestionCount,
    required this.trueNeedCount,
    required this.missedStockOutCount,
    required this.overbuyBaseQuantity,
    required this.overrideCount,
  });

  @override
  final String homeId;
  final String algorithmVersion;
  final int totalCandidatePeriods;
  final int evaluatedPeriods;
  final int suggestionCount;
  final int trueNeedCount;
  final int missedStockOutCount;
  final double overbuyBaseQuantity;
  final int overrideCount;

  double? get coverage {
    return totalCandidatePeriods == 0
        ? null
        : evaluatedPeriods / totalCandidatePeriods;
  }

  double? get precision {
    return suggestionCount == 0 ? null : trueNeedCount / suggestionCount;
  }

  double? get overrideRate {
    return suggestionCount == 0 ? null : overrideCount / suggestionCount;
  }
}

final class HouseholdReport {
  HouseholdReport({
    required this.homeId,
    required this.generatedAt,
    List<InventoryBalanceReportLine> balances =
        const <InventoryBalanceReportLine>[],
    List<StockMovementReportLine> movements = const <StockMovementReportLine>[],
    List<MonthlyPurchaseReportLine> monthlyPurchases =
        const <MonthlyPurchaseReportLine>[],
    List<ConsumptionEvidenceReportLine> consumption =
        const <ConsumptionEvidenceReportLine>[],
    List<CountVarianceReportLine> countVariances =
        const <CountVarianceReportLine>[],
    List<PriceObservationReportLine> prices =
        const <PriceObservationReportLine>[],
    List<UnresolvedLineReportLine> unresolved =
        const <UnresolvedLineReportLine>[],
    List<SuggestionFeedbackReportLine> suggestionFeedback =
        const <SuggestionFeedbackReportLine>[],
    this.backtest,
  }) : balances = List<InventoryBalanceReportLine>.unmodifiable(balances),
       movements = List<StockMovementReportLine>.unmodifiable(movements),
       monthlyPurchases = List<MonthlyPurchaseReportLine>.unmodifiable(
         monthlyPurchases,
       ),
       consumption = List<ConsumptionEvidenceReportLine>.unmodifiable(
         consumption,
       ),
       countVariances = List<CountVarianceReportLine>.unmodifiable(
         countVariances,
       ),
       prices = List<PriceObservationReportLine>.unmodifiable(prices),
       unresolved = List<UnresolvedLineReportLine>.unmodifiable(unresolved),
       suggestionFeedback = List<SuggestionFeedbackReportLine>.unmodifiable(
         suggestionFeedback,
       );

  final String homeId;
  final DateTime generatedAt;
  final List<InventoryBalanceReportLine> balances;
  final List<StockMovementReportLine> movements;
  final List<MonthlyPurchaseReportLine> monthlyPurchases;
  final List<ConsumptionEvidenceReportLine> consumption;
  final List<CountVarianceReportLine> countVariances;
  final List<PriceObservationReportLine> prices;
  final List<UnresolvedLineReportLine> unresolved;
  final List<SuggestionFeedbackReportLine> suggestionFeedback;
  final BacktestCoverageReport? backtest;

  Iterable<HomeScopedReportLine> get allScopedLines sync* {
    yield* balances;
    yield* movements;
    yield* monthlyPurchases;
    yield* consumption;
    yield* countVariances;
    yield* prices;
    yield* unresolved;
    yield* suggestionFeedback;
    if (backtest != null) {
      yield backtest!;
    }
  }
}
