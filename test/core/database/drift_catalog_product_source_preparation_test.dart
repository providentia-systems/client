import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_catalog_product_source_preparation.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

void main() {
  late AppDatabase database;
  late DriftLocalSyncRepository outbox;
  late _Synchronization synchronization;
  late DriftCatalogProductSourcePreparation preparation;
  final now = DateTime.utc(2026, 9, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    outbox = DriftLocalSyncRepository(database);
    synchronization = _Synchronization();
    preparation = DriftCatalogProductSourcePreparation(
      database: database,
      synchronization: synchronization,
      homeId: _homeId,
    );
    var nextId = 0;
    final household = DriftHouseholdRepository(
      database,
      deviceId: _deviceId,
      clock: () => now,
      idGenerator: () => [_productId, _operationId][nextId++],
    );
    await household.createPrivateHomeProduct(
      PrivateHomeProductDraft(homeId: _homeId, privateName: 'Family oats'),
    );
  });

  tearDown(() async => database.close());

  Future<void> prepare() =>
      preparation.prepare(homeId: _homeId, homeProductId: _productId);

  Future<void> acknowledge() => outbox.applyPushResults(
    results: [
      PushOperationResult(
        operationId: _operationId,
        kind: PushResultKind.acknowledged,
        acceptedRevision: 1,
      ),
    ],
    now: now,
    retryPolicy: RetryPolicy(),
  );

  test(
    'a newly saved private source is synchronized before it is ready',
    () async {
      synchronization.action = acknowledge;
      await prepare();
      expect(synchronization.homes, [_homeId]);
      final operations = await database.select(database.clientOperations).get();
      expect(operations.single.state, 'acknowledged');
      await prepare();
      expect(synchronization.homes, [_homeId]);
    },
  );

  for (final status in [
    SyncRunStatus.completed,
    SyncRunStatus.alreadyRunning,
    SyncRunStatus.offline,
    SyncRunStatus.retryableFailure,
  ]) {
    test('$status cannot confirm an unresolved private source', () async {
      synchronization.status = status;
      await expectLater(
        prepare(),
        throwsA(isA<CatalogContributionSourcePendingException>()),
      );
    });
  }

  test(
    'a failed catalog refresh does not invalidate a private acknowledgement',
    () async {
      synchronization.status = SyncRunStatus.retryableFailure;
      synchronization.action = acknowledge;
      await prepare();
    },
  );

  for (final state in [
    ClientOperationState.pending,
    ClientOperationState.blockedConflict,
    ClientOperationState.blockedValidation,
  ]) {
    test('a previous revision does not conceal a $state edit', () async {
      await acknowledge();
      await (database.update(database.clientOperations)
            ..where((row) => row.operationId.equals(_operationId)))
          .write(ClientOperationsCompanion(state: Value(state.storageValue)));
      await expectLater(
        prepare(),
        throwsA(isA<CatalogContributionSourcePendingException>()),
      );
    });
  }

  for (final status in ['archived', 'deleted']) {
    test('$status private sources cannot be contributed', () async {
      await acknowledge();
      await (database.update(
        database.localRecords,
      )..where((row) => row.entityId.equals(_productId))).write(
        LocalRecordsCompanion(payload: Value(jsonEncode({'status': status}))),
      );
      await expectLater(
        prepare(),
        throwsA(isA<CatalogContributionSourceUnavailableException>()),
      );
      expect(synchronization.homes, isEmpty);
    });
  }

  test('missing and cross-home sources fail before synchronization', () async {
    await expectLater(
      preparation.prepare(homeId: _homeId, homeProductId: 'missing-product'),
      throwsA(isA<CatalogContributionSourceUnavailableException>()),
    );
    await expectLater(
      preparation.prepare(homeId: 'another-home', homeProductId: _productId),
      throwsA(isA<CatalogContributionForbiddenException>()),
    );
    expect(synchronization.homes, isEmpty);
  });

  for (final scenario in [
    (
      SyncRunStatus.authenticationRequired,
      isA<CatalogContributionAuthenticationRequiredException>(),
    ),
    (
      SyncRunStatus.authorizationFailure,
      isA<CatalogContributionForbiddenException>(),
    ),
  ]) {
    test(
      '${scenario.$1} remains authoritative after a source acknowledgement',
      () async {
        synchronization.status = scenario.$1;
        synchronization.action = acknowledge;
        await expectLater(prepare(), throwsA(scenario.$2));
      },
    );
  }
}

const _homeId = '11111111-1111-4111-8111-111111111111';
const _deviceId = '22222222-2222-4222-8222-222222222222';
const _productId = '33333333-3333-4333-8333-333333333333';
const _operationId = '44444444-4444-4444-8444-444444444444';

final class _Synchronization implements AppSynchronization {
  final homes = <String>[];
  SyncRunStatus status = SyncRunStatus.completed;
  Future<void> Function()? action;

  @override
  Future<SyncRunOutcome> synchronize(String homeId) async {
    homes.add(homeId);
    await action?.call();
    return SyncRunOutcome(status: status);
  }

  @override
  Future<ConnectivityResult> connectivity() => throw UnimplementedError();

  @override
  Stream<SyncSummary> watchSummary({required String homeId}) =>
      throw UnimplementedError();
}
