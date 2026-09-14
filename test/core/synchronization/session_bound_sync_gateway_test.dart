import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/synchronization/session_bound_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

void main() {
  test('a bound operation reaches push and receipt lookup unchanged', () async {
    final remote = _Gateway();
    final gateway = _bound(remote);
    final operation = _operation('session-device');
    await gateway.push(
      homeId: 'home',
      lastPulledCursor: null,
      operations: <PendingClientOperation>[operation],
    );
    await gateway.operationStatuses(
      homeId: 'home',
      deviceId: 'session-device',
      operationIds: const <String>['operation'],
    );
    expect(remote.pushed!.single, same(operation));
    expect(remote.statusDevice, 'session-device');
    expect(remote.calls, 2);
  });

  test('legacy installation-bound intent is neither rewritten nor sent', () async {
    final remote = _Gateway();
    final gateway = _bound(remote);
    final operation = _operation('installation');
    await expectLater(
      gateway.push(
        homeId: 'home',
        lastPulledCursor: null,
        operations: <PendingClientOperation>[operation],
      ),
      throwsA(isA<AuthenticationSyncException>()),
    );
    expect(operation.deviceId, 'installation');
    expect(operation.operationId, 'operation');
    expect(operation.payload, <String, Object?>{'name': 'saved intent'});
    expect(remote.calls, 0);
  });

  test('receipt lookup cannot borrow the new account device binding', () async {
    final remote = _Gateway();
    await expectLater(
      _bound(remote).operationStatuses(
        homeId: 'home',
        deviceId: 'previous-account-device',
        operationIds: const <String>['operation'],
      ),
      throwsA(isA<AuthenticationSyncException>()),
    );
    expect(remote.calls, 0);
  });

  test('an account change discards a late bootstrap response', () async {
    final remote = _Gateway();
    var current = true;
    final gateway = _bound(remote, isCurrent: () => current);
    final future = gateway.bootstrap(homeId: 'home');
    expect(remote.calls, 1);
    current = false;
    remote.page.complete(_page);
    await expectLater(future, throwsA(isA<AuthenticationSyncException>()));
  });

  test('disposal permanently invalidates an outgoing workspace', () async {
    final remote = _Gateway();
    final gateway = _bound(remote);
    final future = gateway.pull(homeId: 'home', afterCursor: 'cursor');
    gateway.invalidate();
    remote.page.complete(_page);
    await expectLater(future, throwsA(isA<AuthenticationSyncException>()));
    await expectLater(
      gateway.bootstrap(homeId: 'home'),
      throwsA(isA<AuthenticationSyncException>()),
    );
    expect(remote.calls, 1);
  });

  test('another home is rejected before any network request', () async {
    final remote = _Gateway();
    await expectLater(
      _bound(remote).bootstrap(homeId: 'another-home'),
      throwsA(isA<AuthenticationSyncException>()),
    );
    expect(remote.calls, 0);
  });
}

SessionBoundSyncGateway _bound(
  _Gateway remote, {
  bool Function()? isCurrent,
}) => SessionBoundSyncGateway(
  delegate: remote,
  homeId: 'home',
  deviceId: 'session-device',
  isCurrent: isCurrent ?? () => true,
);

PendingClientOperation _operation(String deviceId) => PendingClientOperation(
  operationId: 'operation',
  deviceId: deviceId,
  homeId: 'home',
  entityType: 'inventory-location',
  entityId: 'location',
  operationType: 'inventory.location.create',
  baseRevision: null,
  clientTimestamp: DateTime.utc(2026, 9, 14),
  payloadSchemaVersion: 1,
  payload: const <String, Object?>{'name': 'saved intent'},
  retryCount: 0,
);

const _page = PullPage(
  protocolVersion: 1,
  fromCursor: null,
  changes: <RemoteChange>[],
  pageCursor: 'cursor',
  highWaterCursor: 'cursor',
  hasMore: false,
  requestId: 'request',
);

final class _Gateway implements SyncRemoteGateway {
  int calls = 0;
  final page = Completer<PullPage>();
  List<PendingClientOperation>? pushed;
  String? statusDevice;

  @override
  Future<PullPage> bootstrap({required String homeId}) {
    calls++;
    return page.future;
  }

  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) {
    calls++;
    return page.future;
  }

  @override
  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
  }) async {
    calls++;
    pushed = operations;
    return PushResponse(results: const <PushOperationResult>[]);
  }

  @override
  Future<OperationStatusResponse> operationStatuses({
    required String homeId,
    required String deviceId,
    required List<String> operationIds,
  }) async {
    calls++;
    statusDevice = deviceId;
    return OperationStatusResponse(operations: const <OperationStatusItem>[]);
  }
}
