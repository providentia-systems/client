import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

const _home = '0198a0b1-c2d3-7e4f-8123-456789abcdea';
const _otherHome = '0198a0b1-c2d3-7e4f-8123-456789abcdeb';
const _product = '0198a0b1-c2d3-7e4f-8123-456789abcdec';
const _device = '0198a0b1-c2d3-7e4f-8123-456789abcded';

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;
  final now = DateTime.utc(2026, 10, 26);

  Future<void> seed(
    String type,
    Map<String, Object?> data, {
    String home = _home,
    String id = _product,
  }) => database
      .into(database.localRecords)
      .insert(
        LocalRecordsCompanion.insert(
          homeId: home,
          entityType: type,
          entityId: id,
          revision: const Value(1),
          payload: jsonEncode({'homeId': home, ...data}),
          updatedAt: now,
          synchronizedAt: Value(now),
        ),
      );

  Future<void> changeUnit({String? unit = 'kg', String name = 'Rice'}) =>
      repository.updateHomeProduct(
        homeId: _home,
        productId: _product,
        privateName: name,
        unit: unit,
        archived: false,
        expectedRevision: 1,
      );

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(
      database,
      clock: () => now,
      deviceId: _device,
    );
    await seed('inventory-home-product', {
      'privateName': 'Rice',
      'unit': 'units',
      'status': 'active',
    });
  });
  tearDown(() => database.close());

  for (final evidence in <(String, Map<String, Object?>)>[
    ('inventory-balance', {'homeProductId': _product, 'quantity': '-0.25'}),
    (
      'inventory-balance',
      {
        'homeProductId': _product,
        'quantity': '0',
        'lastMovementId': 'synthetic-movement',
      },
    ),
    (
      'inventory-count-line',
      {'homeProductId': _product, 'quantity': '0', 'status': 'confirmed'},
    ),
    ('shopping-list-line', {'homeProductId': _product, 'quantity': '1'}),
    (
      'shopping-stock-preference',
      {'homeProductId': _product, 'minimumQuantity': '0', 'alwaysKeep': false},
    ),
    (
      'shopping-stock-preference',
      {'homeProductId': _product, 'minimumQuantity': null, 'alwaysKeep': true},
    ),
  ]) {
    test(
      '${evidence.$1} prevents relabeling before projection/outbox changes',
      () async {
        await seed(evidence.$1, evidence.$2);
        expect(
          await repository.unitChangeEligibility(
            homeId: _home,
            productId: _product,
          ),
          InventoryUnitChangeEligibility.inUse,
        );
        await expectLater(
          changeUnit(name: 'Typed name'),
          throwsA(isA<InventoryUnitChangeException>()),
        );
        final product =
            await (database.select(database.localRecords)..where(
                  (row) => row.entityType.equals('inventory-home-product'),
                ))
                .getSingle();
        expect(jsonDecode(product.payload), containsPair('unit', 'units'));
        expect(
          jsonDecode(product.payload),
          containsPair('privateName', 'Rice'),
        );
        expect(await database.select(database.clientOperations).get(), isEmpty);
        // Other metadata remains editable without reinterpreting the unit.
        await changeUnit(unit: 'units', name: 'Typed name');
        final operation = await database
            .select(database.clientOperations)
            .getSingle();
        expect(jsonDecode(operation.payload), isNot(contains('unit')));
        expect(
          jsonDecode(operation.payload),
          containsPair('privateName', 'Typed name'),
        );
      },
    );
  }

  test(
    'unused unit request retains old label across restart and rejection',
    () async {
      await changeUnit(name: 'Brown rice');
      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(jsonDecode(operation.payload), containsPair('unit', 'kg'));
      final restarted = DriftHouseholdRepository(database, deviceId: _device);
      final product = (await restarted.watchItems(homeId: _home).first).single;
      expect(product.unit, 'units');
      expect(product.canonicalName, 'Brown rice');
      await (database.update(
        database.clientOperations,
      )..where((row) => row.operationId.equals(operation.operationId))).write(
        const ClientOperationsCompanion(
          state: Value('blocked_validation'),
          safeFailureCode: Value('home-product-unit-in-use'),
        ),
      );
      expect(
        (await restarted.watchItems(homeId: _home).first).single.unit,
        'units',
      );
      await expectLater(
        restarted.commitManualAdjustment(
          intent: ManualAdjustmentIntent(
            id: '0198a0b1-c2d3-7e4f-8123-456789abcdee',
            homeId: _home,
            itemId: _product,
            locationId: 'primary',
            projectedQuantity: 0,
            observedQuantity: 1,
            reason: 'Physical check',
            createdAt: now,
          ),
          movement: null,
        ),
        throwsA(isA<InventoryUnitChangeException>()),
      );
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(1),
      );
      expect(
        await (database.select(
          database.localRecords,
        )..where((row) => row.entityType.equals('inventory-balance'))).get(),
        isEmpty,
      );
    },
  );

  for (final laterMetadata in [false, true]) {
    test(
      'unit acknowledgement with later metadata $laterMetadata waits for authoritative readback',
      () async {
        await changeUnit();
        if (laterMetadata) {
          await repository.updateHomeProduct(
            homeId: _home,
            productId: _product,
            privateName: 'Brown rice',
            unit: 'units',
            archived: false,
            expectedRevision: 2,
          );
        }
        final operations = await (database.select(
          database.clientOperations,
        )..orderBy([(row) => OrderingTerm.asc(row.enqueueSequence)])).get();
        if (laterMetadata) {
          expect(jsonDecode(operations.last.payload), isNot(contains('unit')));
        }
        final authoritativeRevision = laterMetadata ? 3 : 2;
        final sync = DriftLocalSyncRepository(database);
        await sync.applyPushResults(
          results: [
            for (var index = 0; index < operations.length; index++)
              PushOperationResult(
                operationId: operations[index].operationId,
                kind: PushResultKind.acknowledged,
                acceptedRevision: index + 2,
              ),
          ],
          now: now,
          retryPolicy: RetryPolicy(),
        );
        final pending =
            await (database.select(database.localRecords)..where(
                  (row) => row.entityType.equals('inventory-home-product'),
                ))
                .getSingle();
        expect(pending.synchronizedAt, isNull);
        expect(jsonDecode(pending.payload), containsPair('unit', 'units'));
        await expectLater(
          repository.commitManualAdjustment(
            intent: ManualAdjustmentIntent(
              id: '0198a0b1-c2d3-7e4f-8123-456789abcdee',
              homeId: _home,
              itemId: _product,
              locationId: 'primary',
              projectedQuantity: 0,
              observedQuantity: 1,
              reason: 'Physical check',
              createdAt: now,
            ),
            movement: null,
          ),
          throwsA(isA<InventoryUnitChangeException>()),
        );
        await sync.applyPullPage(
          homeId: _home,
          page: PullPage(
            protocolVersion: 1,
            fromCursor: 'synthetic-1',
            pageCursor: 'synthetic-1',
            highWaterCursor: 'synthetic-1',
            hasMore: false,
            requestId: 'synthetic-request',
            changes: [
              RemoteChange(
                cursor: 'synthetic-1',
                homeId: _home,
                entityType: 'inventory-home-product',
                entityId: _product,
                kind: RemoteChangeKind.upsert,
                revision: authoritativeRevision,
                serverTimestamp: now,
                payload: {
                  'homeId': _home,
                  'privateName': laterMetadata ? 'Brown rice' : 'Rice',
                  'unit': 'kg',
                  'status': 'active',
                },
              ),
            ],
          ),
        );
        expect(
          (await repository.watchItems(homeId: _home).first).single.unit,
          'kg',
        );
        await repository.commitManualAdjustment(
          intent: ManualAdjustmentIntent(
            id: '0198a0b1-c2d3-7e4f-8123-456789abcdee',
            homeId: _home,
            itemId: _product,
            locationId: 'primary',
            projectedQuantity: 0,
            observedQuantity: 1,
            reason: 'Physical check',
            createdAt: now,
          ),
          movement: null,
        );
        expect(
          await database.select(database.clientOperations).get(),
          hasLength(laterMetadata ? 3 : 2),
        );
      },
    );
  }

  test(
    'another home evidence cannot block or certify this home unit',
    () async {
      await seed('inventory-balance', {
        'homeProductId': _product,
        'quantity': '20',
      }, home: _otherHome);
      expect(
        await repository.unitChangeEligibility(
          homeId: _home,
          productId: _product,
        ),
        InventoryUnitChangeEligibility.serverConfirmationRequired,
      );
      await changeUnit();
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(1),
      );
    },
  );

  test(
    'unsupported unit and stale revision cannot enqueue a request',
    () async {
      await expectLater(changeUnit(unit: 'tonnes'), throwsArgumentError);
      await expectLater(
        repository.updateHomeProduct(
          homeId: _home,
          productId: _product,
          privateName: 'Rice',
          unit: 'kg',
          archived: false,
          expectedRevision: 99,
        ),
        throwsStateError,
      );
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );
}
