import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/synchronization/sync_models.dart';

void main() {
  test('every client operation state round-trips through storage', () {
    for (final state in ClientOperationState.values) {
      expect(ClientOperationState.fromStorage(state.storageValue), state);
    }
    expect(
      () => ClientOperationState.fromStorage('unknown-state'),
      throwsFormatException,
    );
  });

  test('local mutation copies its payload and encodes an object', () {
    final source = <String, Object?>{'quantity': 2};
    final mutation = LocalMutation(
      operationId: 'operation-1',
      deviceId: 'device-1',
      homeId: 'home-1',
      entityType: 'inventory_balance',
      entityId: 'record-1',
      operationType: 'put',
      clientTimestamp: DateTime.utc(2026, 7, 30, 12),
      payloadSchemaVersion: 1,
      payload: source,
    );

    source['quantity'] = 3;

    expect(mutation.payload, <String, Object?>{'quantity': 2});
    expect(jsonDecode(mutation.encodedPayload), <String, Object?>{'quantity': 2});
    expect(
      () => mutation.payload['quantity'] = 4,
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('push result copies and freezes its remote representation', () {
    final source = <String, Object?>{'revision': 4};
    final result = PushOperationResult(
      operationId: 'operation-1',
      kind: PushResultKind.conflict,
      remotePayload: source,
    );

    source['revision'] = 5;

    expect(result.remotePayload, <String, Object?>{'revision': 4});
    expect(
      () => result.remotePayload!['revision'] = 6,
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('summary derives waiting work and can clear a safe error', () {
    final synchronizedAt = DateTime.utc(2026, 7, 30, 12);
    final summary = SyncSummary(
      pending: 1,
      syncing: 2,
      retryWaiting: 3,
      blockedConflicts: 1,
      blockedValidation: 1,
      blockedAuthorization: 1,
      acknowledged: 4,
      availability: SyncAvailability.offline,
      isSynchronizing: true,
      lastSuccessfulSync: synchronizedAt,
      lastSafeError: 'Offline.',
    );

    final cleared = summary.copyWith(
      availability: SyncAvailability.online,
      isSynchronizing: false,
      clearError: true,
    );

    expect(summary.waiting, 6);
    expect(cleared.lastSafeError, isNull);
    expect(cleared.lastSuccessfulSync, synchronizedAt);
    expect(cleared.acknowledged, 4);
  });

  test('connectivity result constructors expose truthful states', () {
    const online = ConnectivityResult.online();
    const offline = ConnectivityResult.offline('No network.');
    const authentication = ConnectivityResult.authenticationRequired(
      'Sign in.',
    );

    expect(online.availability, SyncAvailability.online);
    expect(online.safeMessage, isNull);
    expect(offline.availability, SyncAvailability.offline);
    expect(offline.safeMessage, 'No network.');
    expect(
      authentication.availability,
      SyncAvailability.authenticationRequired,
    );
    expect(authentication.safeMessage, 'Sign in.');
  });
}
