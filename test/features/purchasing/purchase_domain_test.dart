import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/purchase_services.dart';

void main() {
  group('PurchaseHistoryGrouper', () {
    test(
      'preserves receipt identity and marks legacy grouping as inferred',
      () {
        final groups = const PurchaseHistoryGrouper().groupRecent(
          homeId: 'home-a',
          lines: <PurchaseLine>[
            _line('1', receiptId: 'receipt-a'),
            _line('2', receiptId: 'receipt-a'),
            _line('3'),
          ],
        );
        expect(groups, hasLength(2));
        expect(
          groups
              .singleWhere((group) => group.id == 'receipt:receipt-a')
              .inferred,
          isFalse,
        );
        expect(
          groups.singleWhere((group) => group.inferred).lines,
          hasLength(1),
        );
      },
    );

    test('groups historical quantities by month without dropping lines', () {
      final summaries = const PurchaseHistoryGrouper().summarizeHistory(
        homeId: 'home-a',
        lines: <PurchaseLine>[
          _line(
            '1',
            source: PurchaseSource.historicalImport,
            date: DateTime.utc(2026, 4),
            quantity: 1.25,
          ),
          _line(
            '2',
            source: PurchaseSource.historicalImport,
            date: DateTime.utc(2026, 4),
            quantity: 2,
          ),
          _line(
            '3',
            source: PurchaseSource.historicalImport,
            date: DateTime.utc(2026, 5),
            quantity: 4,
          ),
        ],
      );
      expect(summaries.map((row) => row.lineCount), <int>[1, 2]);
      expect(summaries.last.quantity, 3.25);
    });

    test('recent spend uses private priced lines and exact minor units', () {
      final spend = const PurchaseHistoryGrouper().recentSpend(
        homeId: 'home-a',
        lines: <PurchaseLine>[
          _line('1', total: Money(minorUnits: 7996, currency: 'NAD')),
          _line('2', total: Money(minorUnits: 15999, currency: 'NAD')),
        ],
      );
      expect(spend, Money(minorUnits: 23995, currency: 'NAD'));
    });

    test('all read models reject cross-home lines', () {
      expect(
        () => const PurchaseHistoryGrouper().groupRecent(
          homeId: 'home-a',
          lines: <PurchaseLine>[_line('x', homeId: 'home-b')],
        ),
        throwsStateError,
      );
    });
  });

  group('PrivateHomePriceComparison', () {
    test('normalizes price by purchased quantity and base units', () {
      final service = const PrivateHomePriceComparison();
      final observations = <PriceObservation>[
        _price('a', 10000, quantity: 2, baseUnits: 1),
        _price('b', 6000, quantity: 1, baseUnits: 1),
        _price('c', 24000, quantity: 2, baseUnits: 2),
      ];
      final statistics = service.summarize(
        homeId: 'home-a',
        productPackId: 'rice-1kg',
        observations: observations,
      );
      expect(statistics.lowest.id, 'a');
      expect(statistics.highest.id, 'c');
      expect(statistics.averageMinorUnitsPerBaseUnit, closeTo(5666.666, 0.01));
    });

    test('rejects foreign-home observations even if product differs', () {
      expect(
        () => const PrivateHomePriceComparison().summarize(
          homeId: 'home-a',
          productPackId: 'rice-1kg',
          observations: <PriceObservation>[
            _price('a', 1000),
            _price('b', 1000, homeId: 'home-b'),
          ],
        ),
        throwsStateError,
      );
    });
  });

  test('Money refuses accidental cross-currency arithmetic', () {
    expect(
      () =>
          Money(minorUnits: 1, currency: 'NAD') +
          Money(minorUnits: 1, currency: 'USD'),
      throwsStateError,
    );
  });
}

PurchaseLine _line(
  String id, {
  String homeId = 'home-a',
  String? receiptId,
  PurchaseSource source = PurchaseSource.recentReceipt,
  DateTime? date,
  double quantity = 1,
  Money? total,
}) {
  return PurchaseLine(
    id: id,
    homeId: homeId,
    purchasedAt: date ?? DateTime.utc(2026, 7, 18),
    datePrecision: source == PurchaseSource.recentReceipt
        ? PurchaseDatePrecision.exactDay
        : PurchaseDatePrecision.monthOnly,
    storeName: 'Metro Fresh',
    rawDescription: 'Rice',
    packSize: '1 kg',
    quantity: quantity,
    source: source,
    receiptId: receiptId,
    lineTotal: total,
  );
}

PriceObservation _price(
  String id,
  int minorUnits, {
  String homeId = 'home-a',
  double quantity = 1,
  double baseUnits = 1,
}) {
  return PriceObservation(
    id: id,
    homeId: homeId,
    productPackId: 'rice-1kg',
    storeName: 'Store $id',
    observedAt: DateTime.utc(2026, 7, id.codeUnitAt(0)),
    quantity: quantity,
    baseUnitsPerPurchasedUnit: baseUnits,
    total: Money(minorUnits: minorUnits, currency: 'NAD'),
  );
}
