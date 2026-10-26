import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

void main() {
  test(
    'delayed foreground synchronization cannot acknowledge a still-pending count',
    () async {
      final database = _database();
      await _seedLocalCount(database);
      final operationBefore = await database
          .select(database.clientOperations)
          .getSingle();
      final recordsBefore = await database.select(database.localRecords).get();
      final entered = Completer<void>();
      final synchronization = Completer<void>();
      var triggers = 0;
      final repository = _repository(
        database,
        onMutationCommitted: () async {
          triggers++;
          if (!entered.isCompleted) entered.complete();
          await synchronization.future;
        },
      );
      var finished = false;
      final ready = repository
          .ensureCountSessionAcknowledged(
            homeId: _homeId,
            sessionId: _sessionId,
          )
          .then((result) {
            finished = true;
            return result;
          });
      await entered.future;
      expect(finished, isFalse);
      expect(
        await database.select(database.clientOperations).getSingle(),
        operationBefore,
      );

      synchronization.complete();
      expect(await ready, isFalse);
      expect(triggers, 1);
      expect(
        await database.select(database.clientOperations).getSingle(),
        operationBefore,
      );
      expect(await database.select(database.localRecords).get(), recordsBefore);
      expect(
        await repository.ensureCountSessionAcknowledged(
          homeId: _homeId,
          sessionId: _sessionId,
        ),
        isFalse,
      );
      expect(
        await database.select(database.clientOperations).get(),
        <ClientOperation>[operationBefore],
      );
    },
  );

  test('acknowledgement cannot borrow another originating account', () async {
    final database = _database();
    await _seedLocalCount(database);
    await _acknowledgeCreation(database);
    await _serverReadback(database, synchronized: true);
    await database
        .update(database.clientOperations)
        .write(
          const ClientOperationsCompanion(
            originatingAccountId: Value(_otherHomeId),
          ),
        );
    final repository = _repository(database, onMutationCommitted: () async {});
    expect(
      await repository.ensureCountSessionAcknowledged(
        homeId: _homeId,
        sessionId: _sessionId,
      ),
      isFalse,
    );
    expect(
      await database.select(database.clientOperations).get(),
      hasLength(1),
    );
  });

  test(
    'acknowledged original-device creation and open readback allow analysis without another create',
    () async {
      final database = _database();
      await _seedLocalCount(database);
      final before = await database
          .select(database.clientOperations)
          .getSingle();
      var triggers = 0;
      final repository = _repository(
        database,
        onMutationCommitted: () async {
          triggers++;
          await _acknowledgeCreation(database);
          await _serverReadback(database, synchronized: true);
        },
      );

      expect(
        await repository.ensureCountSessionAcknowledged(
          homeId: _homeId,
          sessionId: _sessionId,
        ),
        isTrue,
      );
      expect(
        await repository.ensureCountSessionAcknowledged(
          homeId: _homeId,
          sessionId: _sessionId,
        ),
        isTrue,
      );
      expect(triggers, 2);
      final after = await database
          .select(database.clientOperations)
          .getSingle();
      expect(after.state, ClientOperationState.acknowledged.storageValue);
      expect(after.acknowledgedAt?.toUtc(), _now);
      final immutableBefore = before.toJson()
        ..remove('state')
        ..remove('acknowledgedAt');
      final immutableAfter = after.toJson()
        ..remove('state')
        ..remove('acknowledgedAt');
      expect(immutableAfter, immutableBefore);
      expect(after.operationId, _operationId);
      expect(after.deviceId, _deviceId);
      expect(after.originatingAccountId, _accountId);
      expect(after.homeId, _homeId);
      expect(after.entityId, _sessionId);
    },
  );

  test(
    'an acknowledged creation from another device cannot authorize this device target',
    () async {
      final database = _database();
      await _seedLocalCount(database, deviceId: _otherDeviceId);
      await _acknowledgeCreation(database);
      await _serverReadback(database, synchronized: true);
      final before = await database
          .select(database.clientOperations)
          .getSingle();
      final repository = _repository(
        database,
        onMutationCommitted: () async {},
      );

      expect(
        await repository.ensureCountSessionAcknowledged(
          homeId: _homeId,
          sessionId: _sessionId,
        ),
        isFalse,
      );
      expect(
        await database.select(database.clientOperations).getSingle(),
        before,
      );
    },
  );

  for (final status in <String>['accepted', 'cancelled']) {
    test(
      '$status count is not an open extraction target after acknowledgement',
      () async {
        final database = _database();
        await _seedLocalCount(database);
        await _acknowledgeCreation(database);
        await _serverReadback(database, synchronized: true, status: status);
        final before = await database
            .select(database.clientOperations)
            .getSingle();
        final repository = _repository(
          database,
          onMutationCommitted: () async {},
        );

        expect(
          await repository.ensureCountSessionAcknowledged(
            homeId: _homeId,
            sessionId: _sessionId,
          ),
          isFalse,
        );
        expect(
          await database.select(database.clientOperations).getSingle(),
          before,
        );
      },
    );
  }

  test(
    'a count without a foreground synchronization trigger remains pending',
    () async {
      final database = _database();
      await _seedLocalCount(database);
      final before = await database
          .select(database.clientOperations)
          .getSingle();
      final repository = _repository(database);

      expect(
        await repository.ensureCountSessionAcknowledged(
          homeId: _homeId,
          sessionId: _sessionId,
        ),
        isFalse,
      );
      expect(
        await database.select(database.clientOperations).getSingle(),
        before,
      );
    },
  );

  test(
    'offline synchronization failure preserves the original count and outbox',
    () async {
      final database = _database();
      await _seedLocalCount(database);
      final operationsBefore = await database
          .select(database.clientOperations)
          .get();
      final recordsBefore = await database.select(database.localRecords).get();
      final repository = _repository(
        database,
        onMutationCommitted: () async {
          throw StateError('Synthetic offline synchronization');
        },
      );

      expect(
        await repository.ensureCountSessionAcknowledged(
          homeId: _homeId,
          sessionId: _sessionId,
        ),
        isFalse,
      );
      expect(
        await database.select(database.clientOperations).get(),
        operationsBefore,
      );
      expect(await database.select(database.localRecords).get(), recordsBefore);
    },
  );

  test(
    'a synchronized server-origin open count is usable without a local creation operation',
    () async {
      final database = _database();
      await _seedLocalCount(database);
      await database.delete(database.clientOperations).go();
      await _serverReadback(database, synchronized: true);
      var triggers = 0;
      final repository = _repository(
        database,
        onMutationCommitted: () async {
          triggers++;
        },
      );

      expect(
        await repository.ensureCountSessionAcknowledged(
          homeId: _homeId,
          sessionId: _sessionId,
        ),
        isTrue,
      );
      expect(triggers, 1);
      expect(await database.select(database.clientOperations).get(), isEmpty);
      expect(await database.select(database.localRecords).get(), hasLength(1));
    },
  );

  test(
    'an unsynchronized row without its original creation is not server acknowledgement',
    () async {
      final database = _database();
      await _seedLocalCount(database);
      await database.delete(database.clientOperations).go();
      final repository = _repository(
        database,
        onMutationCommitted: () async {},
      );

      expect(
        await repository.ensureCountSessionAcknowledged(
          homeId: _homeId,
          sessionId: _sessionId,
        ),
        isFalse,
      );
      expect(await database.select(database.clientOperations).get(), isEmpty);
      expect(
        (await database.select(database.localRecords).getSingle())
            .synchronizedAt,
        isNull,
      );
    },
  );

  test(
    'another home and a changed active binding cannot acknowledge the saved target',
    () async {
      final database = _database();
      await _seedLocalCount(database);
      await _acknowledgeCreation(database);
      await _serverReadback(database, synchronized: true);
      var triggers = 0;
      final repository = _repository(
        database,
        onMutationCommitted: () async {
          triggers++;
        },
      );

      expect(
        await repository.ensureCountSessionAcknowledged(
          homeId: _otherHomeId,
          sessionId: _sessionId,
        ),
        isFalse,
      );
      expect(triggers, 1);
      final stale = _repository(
        database,
        isCurrent: () => false,
        onMutationCommitted: () async {
          triggers++;
        },
      );
      expect(
        await stale.ensureCountSessionAcknowledged(
          homeId: _homeId,
          sessionId: _sessionId,
        ),
        isFalse,
      );
      expect(triggers, 1);
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(1),
      );
      expect(await database.select(database.localRecords).get(), hasLength(1));
    },
  );
}

AppDatabase _database() {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

DriftHouseholdRepository _repository(
  AppDatabase database, {
  String deviceId = _deviceId,
  Future<void> Function()? onMutationCommitted,
  bool Function()? isCurrent,
}) => DriftHouseholdRepository(
  database,
  deviceId: deviceId,
  originatingAccountId: _accountId,
  clock: () => _now,
  idGenerator: () => _operationId,
  onMutationCommitted: onMutationCommitted,
  isCurrent: isCurrent,
);

Future<void> _seedLocalCount(
  AppDatabase database, {
  String deviceId = _deviceId,
}) async {
  await _repository(database, deviceId: deviceId).saveCountSession(
    StockCountSession(
      id: _sessionId,
      homeId: _homeId,
      locationId: 'primary',
      startedAt: _now,
      observedAt: _now.subtract(const Duration(hours: 1)),
      observedTimezone: 'UTC',
      scopeComplete: false,
      reliability: 'unassessed',
    ),
  );
}

Future<void> _acknowledgeCreation(AppDatabase database) async {
  await (database.update(
    database.clientOperations,
  )..where((row) => row.operationId.equals(_operationId))).write(
    ClientOperationsCompanion(
      state: Value(ClientOperationState.acknowledged.storageValue),
      acknowledgedAt: Value(_now),
    ),
  );
}

Future<void> _serverReadback(
  AppDatabase database, {
  required bool synchronized,
  String status = 'open',
}) async {
  final record = await database.select(database.localRecords).getSingle();
  final payload = jsonDecode(record.payload) as Map<String, Object?>;
  payload['status'] = status;
  await (database.update(database.localRecords)..where(
        (row) => row.homeId.equals(_homeId) & row.entityId.equals(_sessionId),
      ))
      .write(
        LocalRecordsCompanion(
          payload: Value(jsonEncode(payload)),
          synchronizedAt: Value(synchronized ? _now : null),
        ),
      );
}

final _now = DateTime.utc(2026, 10, 26, 8);
const _homeId = '01912345-6789-7abc-8def-0123456789ab';
const _otherHomeId = '01912345-6789-7abc-8def-1123456789ab';
const _deviceId = '01912345-6789-7abc-8def-2123456789ab';
const _otherDeviceId = '01912345-6789-7abc-8def-3123456789ab';
const _accountId = '01912345-6789-7abc-8def-4123456789ab';
const _sessionId = '01912345-6789-7abc-8def-5123456789ab';
const _operationId = '01912345-6789-7abc-8def-6123456789ab';
