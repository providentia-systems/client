abstract interface class HomeScopedReportLine {
  String get homeId;
}

enum HouseholdReportKind { inventory, purchases, consumption, suggestions }

/// Metadata carried by each independently audited home-report response.
final class HouseholdReportMetadata implements HomeScopedReportLine {
  const HouseholdReportMetadata({
    required this.homeId,
    required this.kind,
    required this.asOf,
    this.quantitySemantics,
    this.currencyPolicy,
    this.from,
    this.through,
  });

  @override
  final String homeId;
  final HouseholdReportKind kind;
  final DateTime asOf;
  final String? quantitySemantics;
  final String? currencyPolicy;
  final DateTime? from;
  final DateTime? through;
}

/// Complete factual inventory row from the current HomeReport contract.
final class InventoryReportFact implements HomeScopedReportLine {
  const InventoryReportFact({
    required this.homeId,
    required this.homeProductId,
    required this.productName,
    required this.packText,
    required this.factualQuantity,
    this.balanceRevision,
    this.lastMovementId,
    this.balanceUpdatedAt,
    this.configuredMinimum,
    this.alwaysKeep,
    this.neverSuggest,
  });

  @override
  final String homeId;
  final String homeProductId;
  final String productName;
  final String packText;
  final String factualQuantity;
  final int? balanceRevision;
  final String? lastMovementId;
  final DateTime? balanceUpdatedAt;
  final String? configuredMinimum;
  final bool? alwaysKeep;
  final bool? neverSuggest;
}

/// Currency-isolated monthly/store purchase aggregate.
final class PurchaseReportTotal implements HomeScopedReportLine {
  const PurchaseReportTotal({
    required this.homeId,
    required this.month,
    required this.currency,
    required this.receiptCount,
    required this.total,
    this.storeId,
    this.storeName,
  });

  @override
  final String homeId;
  final String month;
  final String currency;
  final String? storeId;
  final String? storeName;
  final int receiptCount;
  final String total;
}

final class ConsumptionReportEstimate implements HomeScopedReportLine {
  ConsumptionReportEstimate({
    required this.homeId,
    required this.id,
    required this.homeProductId,
    required this.productName,
    required this.method,
    required this.dailyRate,
    required this.variability,
    required this.sampleIntervals,
    required this.coverageDays,
    required this.purchaseSamples,
    required this.confidenceScore,
    required this.confidenceBand,
    required List<String> limitations,
    required this.asOf,
    required this.inputWatermark,
    this.purchaseCadenceDays,
    this.nextExpectedShoppingAt,
    this.evidenceFrom,
    this.evidenceTo,
  }) : limitations = List<String>.unmodifiable(limitations);

  @override
  final String homeId;
  final String id;
  final String homeProductId;
  final String productName;
  final String method;
  final String dailyRate;
  final String variability;
  final int sampleIntervals;
  final int coverageDays;
  final int purchaseSamples;
  final int? purchaseCadenceDays;
  final DateTime? nextExpectedShoppingAt;
  final String confidenceScore;
  final EvidenceConfidence confidenceBand;
  final DateTime? evidenceFrom;
  final DateTime? evidenceTo;
  final List<String> limitations;
  final DateTime asOf;
  final String inputWatermark;
}

final class ShoppingSuggestionReportLine implements HomeScopedReportLine {
  const ShoppingSuggestionReportLine({
    required this.homeId,
    required this.id,
    required this.homeProductId,
    required this.productName,
    required this.packText,
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
    this.selectedPackId,
    this.packCount,
  });

  @override
  final String homeId;
  final String id;
  final String homeProductId;
  final String productName;
  final String packText;
  final String expectedDemand;
  final String safetyStock;
  final String factualStock;
  final String usableStock;
  final String requiredQuantity;
  final String? selectedPackId;
  final int? packCount;
  final String confidenceScore;
  final EvidenceConfidence confidenceBand;
  final String status;
  final DateTime expiresAt;
  final String modelVersion;
  final DateTime asOf;
  final String inputWatermark;
}

final class SuggestionPriceComparisonReportLine
    implements HomeScopedReportLine {
  const SuggestionPriceComparisonReportLine({
    required this.homeId,
    required this.packId,
    required this.currency,
    required this.packCount,
    required this.effectiveTotal,
    required this.excessQuantity,
    required this.priceObservedAt,
    required this.selected,
    required this.reason,
    this.suggestionId,
    this.homeProductId,
    this.productName,
    this.packText,
    this.storeId,
    this.storeName,
  });

  @override
  final String homeId;
  final String? suggestionId;
  final String? homeProductId;
  final String? productName;
  final String packId;
  final String? packText;
  final String? storeId;
  final String? storeName;
  final String currency;
  final int packCount;
  final String effectiveTotal;
  final String excessQuantity;
  final DateTime priceObservedAt;
  final bool selected;
  final String reason;
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
    List<HouseholdReportMetadata> sourceReports =
        const <HouseholdReportMetadata>[],
    List<InventoryReportFact> inventoryFacts = const <InventoryReportFact>[],
    List<PurchaseReportTotal> purchaseTotals = const <PurchaseReportTotal>[],
    List<ConsumptionReportEstimate> consumptionEstimates =
        const <ConsumptionReportEstimate>[],
    List<ShoppingSuggestionReportLine> shoppingSuggestions =
        const <ShoppingSuggestionReportLine>[],
    List<SuggestionPriceComparisonReportLine> suggestionPriceComparisons =
        const <SuggestionPriceComparisonReportLine>[],
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
  }) : sourceReports = List<HouseholdReportMetadata>.unmodifiable(
         sourceReports,
       ),
       inventoryFacts = List<InventoryReportFact>.unmodifiable(inventoryFacts),
       purchaseTotals = List<PurchaseReportTotal>.unmodifiable(purchaseTotals),
       consumptionEstimates = List<ConsumptionReportEstimate>.unmodifiable(
         consumptionEstimates,
       ),
       shoppingSuggestions = List<ShoppingSuggestionReportLine>.unmodifiable(
         shoppingSuggestions,
       ),
       suggestionPriceComparisons =
           List<SuggestionPriceComparisonReportLine>.unmodifiable(
             suggestionPriceComparisons,
           ),
       balances = List<InventoryBalanceReportLine>.unmodifiable(balances),
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
  final List<HouseholdReportMetadata> sourceReports;
  final List<InventoryReportFact> inventoryFacts;
  final List<PurchaseReportTotal> purchaseTotals;
  final List<ConsumptionReportEstimate> consumptionEstimates;
  final List<ShoppingSuggestionReportLine> shoppingSuggestions;
  final List<SuggestionPriceComparisonReportLine> suggestionPriceComparisons;
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
    yield* sourceReports;
    yield* inventoryFacts;
    yield* purchaseTotals;
    yield* consumptionEstimates;
    yield* shoppingSuggestions;
    yield* suggestionPriceComparisons;
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
