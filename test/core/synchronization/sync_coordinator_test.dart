import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

void main() {
  late AppDatabase database;
  late DriftLocalSyncRepository local;
  late DateTime now;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    local = DriftLocalSyncRepository(database);
    now = DateTime.utc(2026, 7, 29, 12);
  });

  tearDown(() => database.close());

  test('lost response applies the immutable status receipt once', () async {
    await local.commitLocalMutation(_mutation());
    final remote = _FakeGateway(
      pushHandler: (_, operations) async {
        throw const RetryableSyncException('Response was lost.');
      },
      operationStatusesHandler: (homeId, deviceId, operationIds) async {
        expect(homeId, 'home-1');
        expect(deviceId, 'device-1');
        expect(operationIds, const <String>['operation-1']);
        return OperationStatusResponse(
          operations: <OperationStatusItem>[
            OperationStatusItem(
              operationId: 'operation-1',
              result: PushOperationResult(
                operationId: 'operation-1',
                kind: PushResultKind.acknowledged,
                acceptedRevision: 1,
                changeCursor: 'cursor-1',
              ),
            ),
          ],
        );
      },
    );
    final coordinator = SyncCoordinator(
      local: local,
      remote: remote,
      connectivity: const _OnlineProbe(),
      retryPolicy: RetryPolicy(baseDelay: Duration(seconds: 1)),
      clock: () => now,
    );

    final completedOutcome = await coordinator.synchronize('home-1');
    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    expect(completedOutcome.status, SyncRunStatus.completed);
    expect(operation.state, ClientOperationState.acknowledged.storageValue);
    expect(remote.pushedOperationIds, const <String>['operation-1']);
    expect(remote.statusOperationIds, const <List<String>>[
      <String>['operation-1'],
    ]);

    // An acknowledged row is never recovered, applied, or pushed twice.
    expect(
      (await coordinator.synchronize('home-1')).status,
      SyncRunStatus.completed,
    );
    expect(remote.pushedOperationIds, const <String>['operation-1']);
    expect(remote.statusOperationIds, hasLength(1));
  });

  test(
    'unknown status exact-retries once with the same operation identity',
    () async {
      await local.commitLocalMutation(_mutation());
      var pushes = 0;
      final remote = _FakeGateway(
        pushHandler: (_, operations) async {
          pushes++;
          if (pushes == 1) {
            throw const RetryableSyncException('Response was lost.');
          }
          return PushResponse(
            results: <PushOperationResult>[
              PushOperationResult(
                operationId: operations.single.operationId,
                kind: PushResultKind.acknowledged,
              ),
            ],
          );
        },
      );
      final coordinator = SyncCoordinator(
        local: local,
        remote: remote,
        connectivity: const _OnlineProbe(),
        clock: () => now,
      );

      final outcome = await coordinator.synchronize('home-1');

      expect(outcome.status, SyncRunStatus.completed);
      expect(remote.pushedOperationIds, const <String>[
        'operation-1',
        'operation-1',
      ]);
      expect(remote.statusOperationIds.single, const <String>['operation-1']);
    },
  );

  test('restart checks an interrupted operation before exact retry', () async {
    await local.commitLocalMutation(_mutation());
    await local.markSyncing(const <String>['operation-1']);
    final remote = _FakeGateway(
      pushHandler: (_, _) async {
        fail('A known interrupted operation must not be pushed again.');
      },
      operationStatusesHandler: (_, _, operationIds) async {
        return OperationStatusResponse(
          operations: <OperationStatusItem>[
            OperationStatusItem(
              operationId: operationIds.single,
              result: PushOperationResult(
                operationId: operationIds.single,
                kind: PushResultKind.acknowledged,
                acceptedRevision: 3,
              ),
            ),
          ],
        );
      },
    );
    final coordinator = SyncCoordinator(
      local: local,
      remote: remote,
      connectivity: const _OnlineProbe(),
      clock: () => now,
    );

    final outcome = await coordinator.synchronize('home-1');

    expect(outcome.status, SyncRunStatus.completed);
    expect(remote.pushedOperationIds, isEmpty);
    expect(remote.statusOperationIds.single, const <String>['operation-1']);
    expect(
      (await database.select(database.clientOperations).getSingle()).state,
      ClientOperationState.acknowledged.storageValue,
    );
  });

  for (final statusCode in <int>[403, 404]) {
    test(
      'operation status HTTP $statusCode is a purge-class authorization outcome',
      () async {
        await local.commitLocalMutation(_mutation());
        final remote = _FakeGateway(
          pushHandler: (_, _) async {
            throw const RetryableSyncException('Response was lost.');
          },
          operationStatusesHandler: (_, _, _) async {
            throw AuthorizationSyncException(
              'Home access is unavailable ($statusCode).',
            );
          },
        );
        final coordinator = SyncCoordinator(
          local: local,
          remote: remote,
          connectivity: const _OnlineProbe(),
          clock: () => now,
        );

        final outcome = await coordinator.synchronize('home-1');

        expect(outcome.status, SyncRunStatus.authorizationFailure);
        expect(outcome.safeMessage, contains('$statusCode'));
        expect(remote.pushedOperationIds, const <String>['operation-1']);
      },
    );
  }

  test('malformed status falls back without issuing a second push', () async {
    await local.commitLocalMutation(_mutation());
    final remote = _FakeGateway(
      pushHandler: (_, _) async {
        throw const RetryableSyncException('Response was lost.');
      },
      operationStatusesHandler: (_, _, _) async => OperationStatusResponse(
        operations: const <OperationStatusItem>[
          OperationStatusItem(operationId: 'another-operation'),
        ],
      ),
    );
    final coordinator = SyncCoordinator(
      local: local,
      remote: remote,
      connectivity: const _OnlineProbe(),
      clock: () => now,
    );

    final outcome = await coordinator.synchronize('home-1');

    expect(outcome.status, SyncRunStatus.retryableFailure);
    expect(remote.pushedOperationIds, const <String>['operation-1']);
    expect(
      (await database.select(database.clientOperations).getSingle()).state,
      ClientOperationState.retryWait.storageValue,
    );
  });

  test('unavailable status defers an ambiguous command safely', () async {
    await local.commitLocalMutation(_mutation());
    final remote = _FakeGateway(
      pushHandler: (_, _) async {
        throw const RetryableSyncException('Response was lost.');
      },
      operationStatusesHandler: (_, _, _) async {
        throw const RetryableSyncException('Status lookup is unavailable.');
      },
    );
    final coordinator = SyncCoordinator(
      local: local,
      remote: remote,
      connectivity: const _OnlineProbe(),
      clock: () => now,
    );

    final outcome = await coordinator.synchronize('home-1');

    expect(outcome.status, SyncRunStatus.retryableFailure);
    expect(remote.pushedOperationIds, const <String>['operation-1']);
    expect(remote.statusOperationIds.single, const <String>['operation-1']);
  });

  test('expired token refreshes once without blocking authorization', () async {
    await local.commitLocalMutation(_mutation());
    var calls = 0;
    final remote = _FakeGateway(
      pushHandler: (_, operations) async {
        calls++;
        if (calls == 1) {
          throw const AuthenticationSyncException('Access token expired.');
        }
        return PushResponse(
          results: <PushOperationResult>[
            PushOperationResult(
              operationId: operations.single.operationId,
              kind: PushResultKind.acknowledged,
              acceptedRevision: 1,
            ),
          ],
        );
      },
    );
    final recovery = _Recovery(succeeds: true);
    final coordinator = SyncCoordinator(
      local: local,
      remote: remote,
      connectivity: const _OnlineProbe(),
      authenticationRecovery: recovery,
      clock: () => now,
    );

    final outcome = await coordinator.synchronize('home-1');

    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    expect(recovery.calls, 1);
    expect(outcome.status, SyncRunStatus.completed);
    expect(operation.state, ClientOperationState.acknowledged.storageValue);
  });

  test('failed token recovery preserves retryable local intent', () async {
    await local.commitLocalMutation(_mutation());
    final coordinator = SyncCoordinator(
      local: local,
      remote: _FakeGateway(
        pushHandler: (_, operations) async {
          throw const AuthenticationSyncException(
            'Sign in again to continue synchronizing.',
          );
        },
      ),
      connectivity: const _OnlineProbe(),
      authenticationRecovery: _Recovery(succeeds: false),
      clock: () => now,
    );

    final outcome = await coordinator.synchronize('home-1');

    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    expect(operation.state, ClientOperationState.retryWait.storageValue);
    expect(
      operation.state,
      isNot(ClientOperationState.blockedAuthorization.storageValue),
    );
    expect(operation.lastSafeError, contains('Sign in again'));
    expect(outcome.status, SyncRunStatus.authenticationRequired);
  });

  test('revoked membership is a blocked authorization result', () async {
    await local.commitLocalMutation(_mutation());
    final coordinator = SyncCoordinator(
      local: local,
      remote: _FakeGateway(
        pushHandler: (_, operations) async {
          return PushResponse(
            results: <PushOperationResult>[
              PushOperationResult(
                operationId: operations.single.operationId,
                kind: PushResultKind.authorizationFailure,
                safeMessage: 'Your membership no longer permits this change.',
              ),
            ],
          );
        },
      ),
      connectivity: const _OnlineProbe(),
      clock: () => now,
    );

    await coordinator.synchronize('home-1');

    final operation = await database
        .select(database.clientOperations)
        .getSingle();
    expect(
      operation.state,
      ClientOperationState.blockedAuthorization.storageValue,
    );
  });

  test(
    'a blocked command remains a durable barrier across synchronization runs',
    () async {
      await local.commitLocalMutation(
        _mutation(
          operationId: 'operation-1',
          entityId: 'record-1',
          clientTimestamp: now,
        ),
      );
      await local.commitLocalMutation(
        _mutation(
          operationId: 'operation-2',
          entityId: 'record-2',
          clientTimestamp: now.add(const Duration(seconds: 1)),
        ),
      );
      await local.commitLocalMutation(
        _mutation(
          operationId: 'operation-3',
          entityId: 'record-3',
          clientTimestamp: now.add(const Duration(seconds: 2)),
        ),
      );
      final remote = _FakeGateway(
        pushHandler: (_, operations) async {
          final operationId = operations.single.operationId;
          if (operationId == 'operation-3') {
            fail('A dependent command crossed an unresolved queue barrier.');
          }
          return PushResponse(
            results: <PushOperationResult>[
              PushOperationResult(
                operationId: operationId,
                kind: operationId == 'operation-1'
                    ? PushResultKind.acknowledged
                    : PushResultKind.conflict,
                safeMessage: operationId == 'operation-2'
                    ? 'Resolve the earlier revision conflict.'
                    : null,
              ),
            ],
          );
        },
      );
      final coordinator = SyncCoordinator(
        local: local,
        remote: remote,
        connectivity: const _OnlineProbe(),
        clock: () => now,
      );

      expect(
        (await coordinator.synchronize('home-1')).status,
        SyncRunStatus.completed,
      );
      expect(remote.pushedOperationIds, <String>['operation-1', 'operation-2']);
      var operations =
          await (database.select(database.clientOperations)
                ..orderBy(<OrderingTerm Function(ClientOperations)>[
                  (row) => OrderingTerm.asc(row.clientTimestamp),
                ]))
              .get();
      expect(operations.map((operation) => operation.state), <String>[
        ClientOperationState.acknowledged.storageValue,
        ClientOperationState.blockedConflict.storageValue,
        ClientOperationState.pending.storageValue,
      ]);

      expect(
        (await coordinator.synchronize('home-1')).status,
        SyncRunStatus.completed,
      );
      expect(remote.pushedOperationIds, <String>['operation-1', 'operation-2']);
      operations = await database.select(database.clientOperations).get();
      expect(
        operations
            .singleWhere((operation) => operation.operationId == 'operation-3')
            .state,
        ClientOperationState.pending.storageValue,
      );
    },
  );

  test(
    'bootstrap membership loss is a truthful authorization outcome',
    () async {
      final coordinator = SyncCoordinator(
        local: local,
        remote: _FakeGateway(
          pushHandler: (_, _) async {
            return const PushResponse(results: <PushOperationResult>[]);
          },
          bootstrapHandler: (_) async {
            throw const AuthorizationSyncException(
              'Access to this home was removed.',
            );
          },
        ),
        connectivity: const _OnlineProbe(),
        clock: () => now,
      );

      final outcome = await coordinator.synchronize('home-1');

      expect(outcome.status, SyncRunStatus.authorizationFailure);
      expect(outcome.safeMessage, contains('removed'));
    },
  );

  test('expired cursor performs one authorized snapshot replacement', () async {
    await local.applyPullPage(
      homeId: 'home-1',
      page: const PullPage(
        protocolVersion: 1,
        fromCursor: 'expired-cursor',
        changes: <RemoteChange>[],
        pageCursor: 'expired-cursor',
        highWaterCursor: 'expired-cursor',
        hasMore: false,
        requestId: 'seed',
      ),
    );
    var pullCalls = 0;
    var bootstrapCalls = 0;
    final remote = _FakeGateway(
      pushHandler: (_, _) async {
        return const PushResponse(results: <PushOperationResult>[]);
      },
      bootstrapHandler: (homeId) async {
        bootstrapCalls++;
        return PullPage(
          protocolVersion: 1,
          fromCursor: 'snapshot-cursor',
          changes: <RemoteChange>[
            RemoteChange(
              cursor: 'snapshot-cursor',
              homeId: homeId,
              entityType: 'home-preference',
              entityId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
              kind: RemoteChangeKind.upsert,
              revision: 4,
              serverTimestamp: now,
              payload: const <String, Object?>{'theme': 'fresh'},
            ),
          ],
          pageCursor: 'snapshot-cursor',
          highWaterCursor: 'snapshot-cursor',
          hasMore: false,
          requestId: 'bootstrap',
        );
      },
      pullHandler: (homeId, cursor) async {
        pullCalls++;
        if (pullCalls == 1) {
          throw const ResyncRequiredSyncException('Cursor expired.');
        }
        return PullPage(
          protocolVersion: 1,
          fromCursor: cursor,
          changes: const <RemoteChange>[],
          pageCursor: cursor!,
          highWaterCursor: cursor,
          hasMore: false,
          requestId: 'pull-after-bootstrap',
        );
      },
    );
    final coordinator = SyncCoordinator(
      local: local,
      remote: remote,
      connectivity: const _OnlineProbe(),
      clock: () => now,
    );

    final outcome = await coordinator.synchronize('home-1');

    expect(outcome.status, SyncRunStatus.completed);
    expect(bootstrapCalls, 1);
    expect(pullCalls, 2);
    expect(await local.cursorForHome('home-1'), 'snapshot-cursor');
    expect(await database.select(database.localRecords).get(), hasLength(1));
  });

  test(
    'concurrent synchronization returns an explicit running outcome',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final remote = _FakeGateway(
        pushHandler: (_, _) async =>
            const PushResponse(results: <PushOperationResult>[]),
        bootstrapHandler: (homeId) async {
          entered.complete();
          await release.future;
          return PullPage(
            protocolVersion: 1,
            fromCursor: 'cursor-0',
            changes: const <RemoteChange>[],
            pageCursor: 'cursor-0',
            highWaterCursor: 'cursor-0',
            hasMore: false,
            requestId: 'bootstrap',
          );
        },
      );
      final coordinator = SyncCoordinator(
        local: local,
        remote: remote,
        connectivity: const _OnlineProbe(),
        clock: () => now,
      );

      final first = coordinator.synchronize('home-1');
      await entered.future;
      final overlapping = await coordinator.synchronize('home-1');
      release.complete();

      expect(overlapping.status, SyncRunStatus.alreadyRunning);
      expect((await first).status, SyncRunStatus.completed);
    },
  );

  test('a paged response must advance its cursor', () async {
    await local.applyPullPage(
      homeId: 'home-1',
      page: const PullPage(
        protocolVersion: 1,
        fromCursor: 'cursor-0',
        changes: <RemoteChange>[],
        pageCursor: 'cursor-0',
        highWaterCursor: 'high-water',
        hasMore: false,
        requestId: 'seed',
      ),
    );
    final coordinator = SyncCoordinator(
      local: local,
      remote: _FakeGateway(
        pushHandler: (_, _) async =>
            const PushResponse(results: <PushOperationResult>[]),
        pullHandler: (homeId, cursor) async => PullPage(
          protocolVersion: 1,
          fromCursor: cursor,
          changes: const <RemoteChange>[],
          pageCursor: cursor!,
          highWaterCursor: 'high-water',
          hasMore: true,
          requestId: 'stalled-page',
        ),
      ),
      connectivity: const _OnlineProbe(),
      clock: () => now,
    );

    final outcome = await coordinator.synchronize('home-1');

    expect(outcome.status, SyncRunStatus.retryableFailure);
    expect(outcome.safeMessage, contains('did not advance'));
    expect(await local.cursorForHome('home-1'), 'cursor-0');
  });

  test('pull page count has a configurable safety limit', () async {
    await local.applyPullPage(
      homeId: 'home-1',
      page: const PullPage(
        protocolVersion: 1,
        fromCursor: 'cursor-0',
        changes: <RemoteChange>[],
        pageCursor: 'cursor-0',
        highWaterCursor: 'seed-high-water',
        hasMore: false,
        requestId: 'seed',
      ),
    );
    var calls = 0;
    final coordinator = SyncCoordinator(
      local: local,
      remote: _FakeGateway(
        pushHandler: (_, _) async =>
            const PushResponse(results: <PushOperationResult>[]),
        pullHandler: (homeId, cursor) async {
          calls++;
          return PullPage(
            protocolVersion: 1,
            fromCursor: cursor,
            changes: const <RemoteChange>[],
            pageCursor: 'cursor-$calls',
            highWaterCursor: 'run-high-water',
            hasMore: true,
            requestId: 'page-$calls',
          );
        },
      ),
      connectivity: const _OnlineProbe(),
      clock: () => now,
      maximumPullPages: 1,
    );

    final outcome = await coordinator.synchronize('home-1');

    expect(outcome.status, SyncRunStatus.retryableFailure);
    expect(outcome.safeMessage, contains('too many pages'));
    expect(calls, 1);
    expect(await local.cursorForHome('home-1'), 'cursor-1');
    expect(
      () => SyncCoordinator(
        local: local,
        remote: _FakeGateway(
          pushHandler: (_, _) async =>
              const PushResponse(results: <PushOperationResult>[]),
        ),
        connectivity: const _OnlineProbe(),
        maximumPullPages: 0,
      ),
      throwsArgumentError,
    );
  });

  test('deterministic retry policy applies bounded jitter', () {
    final policy = RetryPolicy(
      baseDelay: Duration(seconds: 2),
      maximumDelay: Duration(seconds: 30),
    );

    final first = policy.delayFor(operationId: 'same-id', retryCount: 3);
    final second = policy.delayFor(operationId: 'same-id', retryCount: 3);
    final capped = policy.delayFor(operationId: 'same-id', retryCount: 30);

    expect(first, second);
    expect(first, greaterThanOrEqualTo(const Duration(seconds: 16)));
    expect(capped, lessThanOrEqualTo(const Duration(seconds: 36)));
  });
}

LocalMutation _mutation({
  String operationId = 'operation-1',
  String entityId = 'record-1',
  DateTime? clientTimestamp,
}) {
  return LocalMutation(
    operationId: operationId,
    deviceId: 'device-1',
    homeId: 'home-1',
    entityType: 'inventory_balance',
    entityId: entityId,
    operationType: 'create',
    clientTimestamp: clientTimestamp ?? DateTime.utc(2026, 7, 29, 12),
    payloadSchemaVersion: 1,
    payload: const <String, Object?>{'quantity': 1},
  );
}

typedef _Push =
    Future<PushResponse> Function(
      String homeId,
      List<PendingClientOperation> operations,
    );
typedef _Bootstrap = Future<PullPage> Function(String homeId);
typedef _Pull = Future<PullPage> Function(String homeId, String? afterCursor);
typedef _OperationStatuses =
    Future<OperationStatusResponse> Function(
      String homeId,
      String deviceId,
      List<String> operationIds,
    );

final class _FakeGateway implements SyncRemoteGateway {
  _FakeGateway({
    required this.pushHandler,
    this.bootstrapHandler,
    this.pullHandler,
    this.operationStatusesHandler,
  });

  _Push pushHandler;
  final _Bootstrap? bootstrapHandler;
  final _Pull? pullHandler;
  final _OperationStatuses? operationStatusesHandler;
  final List<String> pushedOperationIds = <String>[];
  final List<List<String>> statusOperationIds = <List<String>>[];

  @override
  Future<OperationStatusResponse> operationStatuses({
    required String homeId,
    required String deviceId,
    required List<String> operationIds,
  }) async {
    statusOperationIds.add(List<String>.unmodifiable(operationIds));
    final handler = operationStatusesHandler;
    if (handler != null) {
      return handler(homeId, deviceId, operationIds);
    }
    return OperationStatusResponse(
      operations: operationIds
          .map((operationId) => OperationStatusItem(operationId: operationId))
          .toList(growable: false),
    );
  }

  @override
  Future<PullPage> bootstrap({required String homeId}) async {
    final handler = bootstrapHandler;
    if (handler != null) {
      return handler(homeId);
    }
    return PullPage(
      protocolVersion: 1,
      fromCursor: 'cursor-0',
      changes: const <RemoteChange>[],
      pageCursor: 'cursor-0',
      highWaterCursor: 'cursor-0',
      hasMore: false,
      requestId: 'bootstrap-request',
    );
  }

  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) async {
    final handler = pullHandler;
    if (handler != null) {
      return handler(homeId, afterCursor);
    }
    return PullPage(
      protocolVersion: 1,
      fromCursor: afterCursor,
      changes: const <RemoteChange>[],
      pageCursor: afterCursor ?? 'cursor-0',
      highWaterCursor: afterCursor ?? 'cursor-0',
      hasMore: false,
      requestId: 'pull-request',
    );
  }

  @override
  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
  }) async {
    pushedOperationIds.addAll(
      operations.map((operation) => operation.operationId),
    );
    return pushHandler(homeId, operations);
  }
}

final class _OnlineProbe implements ConnectivityProbe {
  const _OnlineProbe();

  @override
  Future<ConnectivityResult> check() async {
    return const ConnectivityResult.online();
  }
}

final class _Recovery implements AuthenticationRecovery {
  _Recovery({required this.succeeds});

  final bool succeeds;
  int calls = 0;

  @override
  Future<bool> tryRecover() async {
    calls++;
    return succeeds;
  }
}
