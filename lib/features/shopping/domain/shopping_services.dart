import 'dart:math' as math;

import 'package:providentia/features/shopping/domain/shopping_models.dart';

final class ReliableConsumptionEstimator {
  const ReliableConsumptionEstimator({
    this.minimumCoveredDays = 14,
    this.minimumIntervals = 1,
  });

  final int minimumCoveredDays;
  final int minimumIntervals;

  ConsumptionEstimate estimate({
    required Iterable<ReliableCountPoint> counts,
    required Iterable<RestockEvent> restocks,
  }) {
    final orderedCounts = counts.toList(growable: false)
      ..sort((left, right) => left.observedAt.compareTo(right.observedAt));
    if (orderedCounts.length < 2) {
      return const ConsumptionEstimate.insufficient(
        'At least two reliable physical counts are required.',
      );
    }
    var totalConsumption = 0.0;
    var coveredDays = 0;
    var intervals = 0;
    var inconsistent = 0;
    for (var index = 1; index < orderedCounts.length; index++) {
      final start = orderedCounts[index - 1];
      final end = orderedCounts[index];
      final duration = end.observedAt.difference(start.observedAt).inDays;
      if (duration <= 0) continue;
      final purchased = restocks
          .where(
            (event) =>
                event.occurredAt.isAfter(start.observedAt) &&
                !event.occurredAt.isAfter(end.observedAt),
          )
          .fold<double>(0.0, (sum, event) => sum + event.quantity);
      final consumed = start.quantity + purchased - end.quantity;
      if (consumed < -1e-9) {
        inconsistent++;
        continue;
      }
      totalConsumption += math.max(0.0, consumed);
      coveredDays += duration;
      intervals++;
    }
    if (intervals < minimumIntervals || coveredDays < minimumCoveredDays) {
      return ConsumptionEstimate.insufficient(
        'Only $coveredDays reliable day${coveredDays == 1 ? '' : 's'} '
        'of count evidence are available.',
      );
    }
    final confidence = coveredDays >= 90 && intervals >= 3
        ? EstimateConfidence.high
        : coveredDays >= 45 && intervals >= 2
        ? EstimateConfidence.medium
        : EstimateConfidence.low;
    return ConsumptionEstimate(
      confidence: confidence,
      dailyRate: totalConsumption / coveredDays,
      coveredDays: coveredDays,
      intervalCount: intervals,
      explanation:
          'Estimated from $intervals reliable count interval'
          '${intervals == 1 ? '' : 's'} over $coveredDays days'
          '${inconsistent == 0 ? '.' : '; $inconsistent inconsistent interval was excluded.'}',
    );
  }
}

enum PackOptimizationPolicy { minimizeWaste, minimizeKnownCost }

final class DeterministicPackOptimizer {
  const DeterministicPackOptimizer();

  PackRecommendation? optimize({
    required double requiredUnits,
    required Iterable<PackOption> options,
    PackOptimizationPolicy policy = PackOptimizationPolicy.minimizeWaste,
  }) {
    if (!requiredUnits.isFinite || requiredUnits <= 0) return null;
    final candidates = options
        .where((option) => option.available)
        .map(
          (option) => PackRecommendation(
            option: option,
            packCount: (requiredUnits / option.unitsPerPack).ceil(),
            requiredUnits: requiredUnits,
          ),
        )
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    candidates.sort((left, right) {
      if (policy == PackOptimizationPolicy.minimizeKnownCost) {
        final leftPrice = left.totalPrice;
        final rightPrice = right.totalPrice;
        if (leftPrice != null && rightPrice != null) {
          if (leftPrice.currency != rightPrice.currency) {
            throw StateError('Pack-price optimization requires one currency.');
          }
          final price = leftPrice.minorUnits.compareTo(rightPrice.minorUnits);
          if (price != 0) return price;
        } else if (leftPrice != null || rightPrice != null) {
          return leftPrice == null ? 1 : -1;
        }
      }
      final waste = left.overage.compareTo(right.overage);
      if (waste != 0) return waste;
      if (left.option.preferred != right.option.preferred) {
        return left.option.preferred ? -1 : 1;
      }
      final packs = left.packCount.compareTo(right.packCount);
      return packs != 0 ? packs : left.option.id.compareTo(right.option.id);
    });
    return candidates.first;
  }
}

final class ExplainableSuggestionEngine {
  const ExplainableSuggestionEngine({
    this.packOptimizer = const DeterministicPackOptimizer(),
  });

  final DeterministicPackOptimizer packOptimizer;

  ShoppingSuggestion suggest({
    required String homeId,
    required String productPackId,
    required DateTime now,
    required DateTime nextShoppingDate,
    required double usableStock,
    required double safetyStock,
    required ConsumptionEstimate consumption,
    required Iterable<PackOption> packOptions,
    Duration supplierLeadTime = Duration.zero,
    double? fallbackMinimum,
  }) {
    if (homeId.trim().isEmpty || productPackId.trim().isEmpty) {
      throw ArgumentError('Home and product-pack identity are required.');
    }
    if (!usableStock.isFinite ||
        !safetyStock.isFinite ||
        usableStock < 0 ||
        safetyStock < 0) {
      throw ArgumentError('Stock values must not be negative.');
    }
    if (supplierLeadTime.isNegative) {
      throw ArgumentError.value(
        supplierLeadTime,
        'supplierLeadTime',
        'must not be negative',
      );
    }
    final replenishmentAt = nextShoppingDate.add(supplierLeadTime);
    final demandDays = math.max(
      0.0,
      replenishmentAt.difference(now).inHours / 24,
    );
    late final double need;
    late final EstimateConfidence confidence;
    late final String explanation;
    if (consumption.hasEnoughEvidence) {
      final expectedDemand = consumption.dailyRate * demandDays;
      need = math.max(0.0, expectedDemand + safetyStock - usableStock);
      confidence = consumption.confidence;
      explanation =
          '${consumption.explanation} Expected demand is '
          '${expectedDemand.toStringAsFixed(2)} units before replenishment, '
          'with ${safetyStock.toStringAsFixed(2)} units held in reserve and '
          '${usableStock.toStringAsFixed(2)} currently usable.';
    } else if (fallbackMinimum != null) {
      if (!fallbackMinimum.isFinite || fallbackMinimum < 0) {
        throw ArgumentError.value(
          fallbackMinimum,
          'fallbackMinimum',
          'must not be negative',
        );
      }
      need = math.max(0.0, fallbackMinimum - usableStock);
      confidence = EstimateConfidence.low;
      explanation =
          '${consumption.explanation} A user-configured minimum of '
          '${fallbackMinimum.toStringAsFixed(2)} units is used instead.';
    } else {
      need = 0;
      confidence = EstimateConfidence.insufficient;
      explanation =
          '${consumption.explanation} Configure a minimum before a quantity '
          'is suggested.';
    }
    return ShoppingSuggestion(
      homeId: homeId,
      productPackId: productPackId,
      quantityNeeded: need,
      confidence: confidence,
      explanation: explanation,
      dataCoverageDays: consumption.coveredDays,
      packRecommendation: packOptimizer.optimize(
        requiredUnits: need,
        options: packOptions,
      ),
    );
  }
}

final class SuggestionFeedbackAnalyzer {
  const SuggestionFeedbackAnalyzer();

  SuggestionFeedbackSummary summarize({
    required String homeId,
    required Iterable<SuggestionFeedback> feedback,
  }) {
    final rows = feedback.toList(growable: false);
    if (rows.any((entry) => entry.homeId != homeId)) {
      throw StateError('Cross-home suggestion feedback is not permitted.');
    }
    int count(SuggestionFeedbackKind kind) =>
        rows.where((entry) => entry.kind == kind).length;
    return SuggestionFeedbackSummary(
      total: rows.length,
      accepted: count(SuggestionFeedbackKind.accepted),
      dismissed: count(SuggestionFeedbackKind.dismissed),
      snoozed: count(SuggestionFeedbackKind.snoozed),
      edited: count(SuggestionFeedbackKind.quantityEdited),
    );
  }
}

final class RollingOriginBacktester {
  const RollingOriginBacktester();

  BacktestResult evaluate({
    required Iterable<HistoricalDemand> history,
    required int minimumTrainingDays,
    required int horizonDays,
    required DemandForecaster forecaster,
  }) {
    if (minimumTrainingDays < 1 || horizonDays < 1) {
      throw ArgumentError('Training and horizon lengths must be positive.');
    }
    final ordered = history.toList(growable: false)
      ..sort((left, right) => left.day.compareTo(right.day));
    if (ordered.length < minimumTrainingDays + horizonDays) {
      throw StateError('Insufficient history for rolling-origin backtesting.');
    }
    var samples = 0;
    var absoluteError = 0.0;
    var signedError = 0.0;
    var overbuyCount = 0;
    var missedCount = 0;
    var totalOverbuy = 0.0;
    var totalMissed = 0.0;
    for (
      var origin = minimumTrainingDays;
      origin + horizonDays <= ordered.length;
      origin++
    ) {
      final training = List<HistoricalDemand>.unmodifiable(
        ordered.sublist(0, origin),
      );
      final actual = ordered
          .sublist(origin, origin + horizonDays)
          .fold<double>(0.0, (sum, point) => sum + point.quantity);
      final predicted = forecaster(training, horizonDays);
      if (!predicted.isFinite || predicted < 0) {
        throw StateError('The forecaster returned an invalid demand.');
      }
      final error = predicted - actual;
      samples++;
      absoluteError += error.abs();
      signedError += error;
      if (error > 0) {
        overbuyCount++;
        totalOverbuy += error;
      } else if (error < 0) {
        missedCount++;
        totalMissed += -error;
      }
    }
    return BacktestResult(
      sampleCount: samples,
      meanAbsoluteError: absoluteError / samples,
      bias: signedError / samples,
      overbuyRate: overbuyCount / samples,
      missedDemandRate: missedCount / samples,
      totalOverbuy: totalOverbuy,
      totalMissedDemand: totalMissed,
    );
  }
}
