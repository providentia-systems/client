import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/domain/shopping_services.dart';

void main() {
  group('ShoppingList', () {
    test('manual and suggested lines share deterministic progress', () {
      final list = _list()
          .add(_line('a', ShoppingLineOrigin.manual))
          .add(_line('b', ShoppingLineOrigin.suggestion))
          .toggle('a');
      expect(list.completedCount, 1);
      expect(list.progress, 0.5);
      expect(list.lines.singleWhere((line) => line.id == 'a').checked, isTrue);
    });

    test('rejects lines from another home', () {
      expect(
        () => _list().add(
          ShoppingListLine(
            id: 'foreign',
            homeId: 'home-b',
            name: 'Tea',
            quantity: 1,
            origin: ShoppingLineOrigin.manual,
            createdAt: DateTime.utc(2026),
          ),
        ),
        throwsStateError,
      );
    });

    test('server suggestion identities remain distinct', () {
      final line = ShoppingListLine(
        id: 'line',
        homeId: 'home-a',
        name: 'Oats',
        quantity: 2,
        origin: ShoppingLineOrigin.suggestion,
        createdAt: DateTime.utc(2026),
        suggestionId: 'suggestion-id',
        homeProductId: 'home-product-id',
        selectedPackId: 'pack-id',
      );

      expect(line.suggestionId, 'suggestion-id');
      expect(line.homeProductId, 'home-product-id');
      expect(line.selectedPackId, 'pack-id');
      // ignore: deprecated_member_use_from_same_package
      expect(line.productPackId, isNull);
    });
  });

  group('ReliableConsumptionEstimator', () {
    test('estimates consumption between counts plus purchases', () {
      final estimate = const ReliableConsumptionEstimator().estimate(
        counts: <ReliableCountPoint>[
          ReliableCountPoint(observedAt: DateTime.utc(2026, 1), quantity: 10),
          ReliableCountPoint(
            observedAt: DateTime.utc(2026, 1, 31),
            quantity: 4,
          ),
          ReliableCountPoint(observedAt: DateTime.utc(2026, 3, 2), quantity: 3),
        ],
        restocks: <RestockEvent>[
          RestockEvent(occurredAt: DateTime.utc(2026, 1, 15), quantity: 5),
          RestockEvent(occurredAt: DateTime.utc(2026, 2, 15), quantity: 5),
        ],
      );
      expect(estimate.dailyRate, closeTo(17 / 60, 1e-9));
      expect(estimate.coveredDays, 60);
      expect(estimate.intervalCount, 2);
      expect(estimate.confidence, EstimateConfidence.medium);
    });

    test('reports insufficient evidence truthfully', () {
      final estimate = const ReliableConsumptionEstimator().estimate(
        counts: <ReliableCountPoint>[
          ReliableCountPoint(observedAt: DateTime.utc(2026), quantity: 10),
        ],
        restocks: const <RestockEvent>[],
      );
      expect(estimate.hasEnoughEvidence, isFalse);
      expect(estimate.explanation, contains('two reliable'));
    });

    test('excludes inconsistent intervals', () {
      final estimate = const ReliableConsumptionEstimator(minimumCoveredDays: 1)
          .estimate(
            counts: <ReliableCountPoint>[
              ReliableCountPoint(
                observedAt: DateTime.utc(2026, 1),
                quantity: 1,
              ),
              ReliableCountPoint(
                observedAt: DateTime.utc(2026, 2),
                quantity: 5,
              ),
              ReliableCountPoint(
                observedAt: DateTime.utc(2026, 3),
                quantity: 2,
              ),
            ],
            restocks: const <RestockEvent>[],
          );
      expect(estimate.intervalCount, 1);
      expect(estimate.explanation, contains('excluded'));
    });
  });

  group('pack optimization and suggestions', () {
    final options = <PackOption>[
      PackOption(id: 'small', unitsPerPack: 2),
      PackOption(id: 'bulk', unitsPerPack: 5, preferred: true),
    ];

    test('minimizes waste with deterministic tie breakers', () {
      final result = const DeterministicPackOptimizer().optimize(
        requiredUnits: 7,
        options: options,
      )!;
      expect(result.option.id, 'small');
      expect(result.packCount, 4);
      expect(result.overage, 1);
    });

    test('can minimize known total cost', () {
      final result = const DeterministicPackOptimizer().optimize(
        requiredUnits: 6,
        policy: PackOptimizationPolicy.minimizeKnownCost,
        options: <PackOption>[
          PackOption(
            id: 'small',
            unitsPerPack: 2,
            price: Money(minorUnits: 300, currency: 'NAD'),
          ),
          PackOption(
            id: 'bulk',
            unitsPerPack: 6,
            price: Money(minorUnits: 800, currency: 'NAD'),
          ),
        ],
      )!;
      expect(result.option.id, 'bulk');
      expect(result.totalPrice!.minorUnits, 800);
    });

    test('suggestion explains demand, reserve, and usable stock', () {
      final result = const ExplainableSuggestionEngine().suggest(
        homeId: 'home-a',
        productPackId: 'rice',
        now: DateTime.utc(2026, 7, 1),
        nextShoppingDate: DateTime.utc(2026, 7, 11),
        usableStock: 2,
        safetyStock: 1,
        consumption: ConsumptionEstimate(
          confidence: EstimateConfidence.medium,
          dailyRate: 0.5,
          coveredDays: 60,
          intervalCount: 2,
          explanation: 'Reliable count evidence.',
        ),
        packOptions: options,
      );
      expect(result.quantityNeeded, 4);
      expect(result.packRecommendation!.packCount, 2);
      expect(result.explanation, contains('reserve'));
      expect(result.confidence, EstimateConfidence.medium);
    });

    test('insufficient evidence uses explicit fallback only', () {
      final withoutFallback = const ExplainableSuggestionEngine().suggest(
        homeId: 'home-a',
        productPackId: 'tea',
        now: DateTime.utc(2026, 7, 1),
        nextShoppingDate: DateTime.utc(2026, 7, 8),
        usableStock: 1,
        safetyStock: 0,
        consumption: const ConsumptionEstimate.insufficient('Not enough data.'),
        packOptions: options,
      );
      expect(withoutFallback.shouldSuggest, isFalse);
      expect(withoutFallback.confidence, EstimateConfidence.insufficient);

      final fallback = const ExplainableSuggestionEngine().suggest(
        homeId: 'home-a',
        productPackId: 'tea',
        now: DateTime.utc(2026, 7, 1),
        nextShoppingDate: DateTime.utc(2026, 7, 8),
        usableStock: 1,
        safetyStock: 0,
        fallbackMinimum: 3,
        consumption: const ConsumptionEstimate.insufficient('Not enough data.'),
        packOptions: options,
      );
      expect(fallback.quantityNeeded, 2);
      expect(fallback.confidence, EstimateConfidence.low);
    });
  });

  group('feedback and rolling-origin evaluation', () {
    test('feedback summary remains home-private', () {
      final summary = const SuggestionFeedbackAnalyzer().summarize(
        homeId: 'home-a',
        feedback: <SuggestionFeedback>[
          _feedback('a', SuggestionFeedbackKind.accepted),
          _feedback('b', SuggestionFeedbackKind.quantityEdited),
        ],
      );
      expect(summary.acceptanceRate, 0.5);
      expect(summary.overrideRate, 0.5);
      expect(
        () => const SuggestionFeedbackAnalyzer().summarize(
          homeId: 'home-a',
          feedback: <SuggestionFeedback>[
            _feedback('x', SuggestionFeedbackKind.accepted, homeId: 'home-b'),
          ],
        ),
        throwsStateError,
      );
    });

    test('rolling origins report error, bias, overbuy, and missed demand', () {
      final history = List<HistoricalDemand>.generate(
        6,
        (index) => HistoricalDemand(
          day: DateTime.utc(2026, 1, index + 1),
          quantity: (index + 1).toDouble(),
        ),
      );
      final result = const RollingOriginBacktester().evaluate(
        history: history,
        minimumTrainingDays: 3,
        horizonDays: 1,
        forecaster: _lastDemand,
      );
      expect(result.sampleCount, 3);
      expect(result.meanAbsoluteError, 1);
      expect(result.bias, -1);
      expect(result.overbuyRate, 0);
      expect(result.missedDemandRate, 1);
      expect(result.totalMissedDemand, 3);
    });
  });
}

double _lastDemand(List<HistoricalDemand> training, int _) =>
    training.last.quantity;

ShoppingList _list() => ShoppingList(
  id: 'list',
  homeId: 'home-a',
  name: 'Weekly',
  createdAt: DateTime.utc(2026),
);

ShoppingListLine _line(String id, ShoppingLineOrigin origin) =>
    ShoppingListLine(
      id: id,
      homeId: 'home-a',
      name: id,
      quantity: 1,
      origin: origin,
      createdAt: DateTime.utc(2026),
    );

SuggestionFeedback _feedback(
  String id,
  SuggestionFeedbackKind kind, {
  String homeId = 'home-a',
}) => SuggestionFeedback(
  id: id,
  homeId: homeId,
  productPackId: 'rice',
  kind: kind,
  recordedAt: DateTime.utc(2026),
  updatedQuantity: kind == SuggestionFeedbackKind.quantityEdited ? 2 : null,
);
