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
    expect(jsonDecode(mutation.encodedPayload), <String, Object?>{
      'quantity': 2,
    });
    expect(
      () => mutation.payload['quantity'] = 4,
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('local mutation rejects invalid durable identity and revisions', () {
    LocalMutation build({
      String operationId = 'operation-1',
      int? baseRevision,
      int payloadSchemaVersion = 1,
    }) {
      return LocalMutation(
        operationId: operationId,
        deviceId: 'device-1',
        homeId: 'home-1',
        entityType: 'inventory_balance',
        entityId: 'record-1',
        operationType: 'put',
        baseRevision: baseRevision,
        clientTimestamp: DateTime.utc(2026, 7, 30, 12),
        payloadSchemaVersion: payloadSchemaVersion,
        payload: const <String, Object?>{'quantity': 2},
      );
    }

    expect(() => build(operationId: '  '), throwsArgumentError);
    expect(() => build(baseRevision: -1), throwsArgumentError);
    expect(() => build(payloadSchemaVersion: 0), throwsArgumentError);
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
      failureCode: 'device_binding_mismatch',
      blockedOperationType: 'purchasing.receipt.create',
      nextRetryAt: synchronizedAt.add(const Duration(minutes: 1)),
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
    expect(cleared.failureCode, 'device_binding_mismatch');
    expect(cleared.blockedOperationType, 'purchasing.receipt.create');
    expect(cleared.nextRetryAt, synchronizedAt.add(const Duration(minutes: 1)));
    expect(cleared.waitingBehindFirst, 8);
    final resolved = cleared.copyWith(clearDiagnostics: true);
    expect(resolved.failureCode, isNull);
    expect(resolved.blockedOperationType, isNull);
    expect(resolved.nextRetryAt, isNull);
    expect(const SyncSummary.initial().waitingBehindFirst, 0);
  });

  test('failure diagnostics use allowlisted codes rather than prose', () {
    expect(
      sanitizedSyncFailureCode('device_binding_mismatch'),
      'device_binding_mismatch',
    );
    expect(
      sanitizedSyncFailureCode('authentication_required'),
      'authentication_required',
    );
    expect(
      sanitizedSyncFailureCode('network_unavailable'),
      'network_unavailable',
    );
    expect(
      sanitizedSyncFailureCode('Access to this home changed'),
      'unclassified_failure',
    );
    expect(sanitizedSyncFailureCode(null), isNull);
  });

  test('recovery headings never infer home denial from a binding block', () {
    expect(
      syncFailureHeading('device_binding_mismatch'),
      'Review this device and session',
    );
    expect(
      syncFailureHeading('account_binding_mismatch'),
      'Use the original account',
    );
    expect(
      syncFailureHeading('origin_account_unknown'),
      'Review saved-operation provenance',
    );
    expect(
      syncFailureHeading('home_access_denied'),
      'Access to this home changed',
    );
    expect(
      syncFailureHeading('unclassified_http_denial'),
      'Review synchronization',
    );
    expect(
      syncRecoveryInstruction('device_binding_mismatch'),
      contains('Saved operations are preserved'),
    );
    expect(syncRecoveryInstruction('revision_conflict'), contains('compare'));
    expect(syncRecoveryInstruction(null), contains('queue is preserved'));
  });

  test('operation labels expose only known human-readable actions', () {
    expect(syncOperationLabel('purchasing.receipt.commit'), 'Finish receipt');
    expect(
      syncOperationLabel('purchasing.receipt-line.purchase'),
      'Save purchased receipt line',
    );
    expect(
      syncOperationLabel('shopping.list-line.create'),
      'Add shopping item',
    );
    expect(
      syncOperationLabel('inventory.count-session.close'),
      'Finish stock count',
    );
    expect(
      syncOperationLabel('private receipt description'),
      'Household change',
    );
    expect(syncOperationLabel(null), 'Household change');
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
