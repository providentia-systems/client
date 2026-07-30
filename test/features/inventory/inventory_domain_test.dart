import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/domain/inventory_services.dart';

void main() {
  group('InventoryItemSearch', () {
    final items = <InventoryItem>[
      InventoryItem(
        id: '1',
        homeId: 'home-a',
        canonicalName: 'Coke',
        aliases: const <String>['Coca-Cola'],
        brand: 'Coca-Cola',
        packSize: '2 L',
        category: 'Beverages',
        currentQuantity: 2,
      ),
      InventoryItem(
        id: '2',
        homeId: 'home-a',
        canonicalName: 'Tea Rooibos Bags',
        aliases: const <String>['Laager Rooibos'],
        packSize: '80 tea bags',
        category: 'Tea & Coffee',
      ),
    ];

    test('searches aliases, brand, pack, and category', () {
      const search = InventoryItemSearch();
      for (final query in <String>[
        'coca cola',
        'Coca-Cola',
        '2 l',
        'beverages',
      ]) {
        expect(
          search.filter(
            items,
            InventorySearchCriteria(
              query: query,
              view: InventoryView.itemMaster,
            ),
          ),
          hasLength(1),
        );
      }
    });

    test('counted view excludes uncounted items and category composes', () {
      const search = InventoryItemSearch();
      expect(
        search.filter(
          items,
          const InventorySearchCriteria(
            view: InventoryView.counted,
            category: 'Beverages',
          ),
        ),
        hasLength(1),
      );
      expect(
        search.filter(
          items,
          const InventorySearchCriteria(
            view: InventoryView.counted,
            category: 'Tea & Coffee',
          ),
        ),
        isEmpty,
      );
    });

    test('confirmed photo rows sort after outstanding rows', () {
      const search = InventoryItemSearch();
      final result = search.filter(
        items,
        const InventorySearchCriteria(
          view: InventoryView.itemMaster,
          confirmedItemIds: <String>{'1'},
        ),
      );
      expect(result.map((item) => item.id), <String>['2', '1']);
    });
  });

  group('manual adjustments and movement balances', () {
    test('manual intent creates the exact audited delta', () {
      final intent = ManualAdjustmentIntent(
        id: 'intent',
        homeId: 'home-a',
        itemId: 'rice',
        locationId: 'pantry',
        projectedQuantity: 8,
        observedQuantity: 5.5,
        reason: 'Physical recount',
        createdAt: DateTime.utc(2026, 7, 30),
      );
      final movement = intent.toMovement('movement')!;
      expect(movement.quantityDelta, -2.5);
      expect(movement.kind, StockMovementKind.manualAdjustment);
      expect(movement.reason, 'Physical recount');
    });

    test('no-op manual intent does not create a movement', () {
      final intent = ManualAdjustmentIntent(
        id: 'intent',
        homeId: 'home-a',
        itemId: 'rice',
        locationId: 'pantry',
        projectedQuantity: 5,
        observedQuantity: 5,
        reason: 'Verified',
        createdAt: DateTime.utc(2026, 7, 30),
      );
      expect(intent.toMovement('movement'), isNull);
    });

    test('ledger projector derives balances deterministically', () {
      final movements = <StockMovement>[
        _movement('b', 4, DateTime.utc(2026, 2), StockMovementKind.purchase),
        _movement(
          'a',
          10,
          DateTime.utc(2026),
          StockMovementKind.openingBalance,
        ),
        _movement(
          'c',
          -3.5,
          DateTime.utc(2026, 3),
          StockMovementKind.consumption,
        ),
      ];
      final balances = const InventoryBalanceProjector().project(
        homeId: 'home-a',
        movements: movements,
        asOf: DateTime.utc(2026, 4),
      );
      expect(balances.single.quantity, 10.5);
    });

    test('ledger projector rejects cross-home data', () {
      expect(
        () => const InventoryBalanceProjector().project(
          homeId: 'home-a',
          movements: <StockMovement>[
            StockMovement(
              id: 'x',
              homeId: 'home-b',
              itemId: 'rice',
              locationId: 'pantry',
              quantityDelta: 1,
              kind: StockMovementKind.purchase,
              occurredAt: DateTime.utc(2026),
              sourceId: 'receipt',
            ),
          ],
        ),
        throwsStateError,
      );
    });

    test('manual movement requires a reason', () {
      expect(
        () => StockMovement(
          id: 'x',
          homeId: 'home-a',
          itemId: 'rice',
          locationId: 'pantry',
          quantityDelta: 1,
          kind: StockMovementKind.manualAdjustment,
          occurredAt: DateTime.utc(2026),
          sourceId: 'manual',
        ),
        throwsArgumentError,
      );
    });
  });

  group('StockCountSession', () {
    final photoA = StockPhotoReference(
      id: 'photo-a',
      localReference: 'local://photo-a',
      addedAt: DateTime.utc(2026),
    );
    final photoB = StockPhotoReference(
      id: 'photo-b',
      localReference: 'local://photo-b',
      addedAt: DateTime.utc(2026),
    );

    test('keeps photos and confirmed lines in immutable session state', () {
      final session = _session()
          .attachPhoto(photoA)
          .recordLine(
            StockCountLine(
              id: 'line-a',
              itemId: 'rice',
              status: CountLineStatus.confirmed,
              source: CountSource.photo,
              observedQuantity: 3,
              photoId: 'photo-a',
            ),
          );
      expect(session.photos.single.id, 'photo-a');
      expect(session.confirmedLines.single.itemId, 'rice');
      expect(session.outstandingLines, isEmpty);
      expect(
        session.close(DateTime.utc(2026, 1, 2)).status,
        CountSessionStatus.closed,
      );
    });

    test('detects possible duplicate counting across photos', () {
      final session = _session()
          .attachPhoto(photoA)
          .attachPhoto(photoB)
          .recordLine(
            StockCountLine(
              id: 'line-a',
              itemId: 'rice',
              status: CountLineStatus.confirmed,
              source: CountSource.photo,
              observedQuantity: 2,
              photoId: 'photo-a',
            ),
          )
          .recordLine(
            StockCountLine(
              id: 'line-b',
              itemId: 'rice',
              status: CountLineStatus.confirmed,
              source: CountSource.photo,
              observedQuantity: 2,
              photoId: 'photo-b',
            ),
          );
      expect(session.lines.every((line) => line.possibleDuplicate), isTrue);
      expect(() => session.close(DateTime.utc(2026, 1, 2)), throwsStateError);
    });

    test('closed sessions are append-only', () {
      final closed = _session().close(DateTime.utc(2026, 1, 2));
      expect(() => closed.attachPhoto(photoA), throwsStateError);
    });
  });
}

StockMovement _movement(
  String id,
  double delta,
  DateTime at,
  StockMovementKind kind,
) {
  return StockMovement(
    id: id,
    homeId: 'home-a',
    itemId: 'rice',
    locationId: 'pantry',
    quantityDelta: delta,
    kind: kind,
    occurredAt: at,
    sourceId: 'source-$id',
  );
}

StockCountSession _session() => StockCountSession(
  id: 'session',
  homeId: 'home-a',
  locationId: 'pantry',
  startedAt: DateTime.utc(2026),
);
