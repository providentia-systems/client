import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/synchronization_recovery.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

/// Authenticated original-binding recovery. Diagnostic and revalidation calls
/// are read-only; only ordinary synchronization may execute saved commands.
final class GeneratedSyncRecoveryGateway implements SyncRecoveryGateway {
  const GeneratedSyncRecoveryGateway({
    required this.client,
    required this.accountId,
    required this.deviceId,
    required this.homeId,
    required this.isCurrent,
  });

  final generated.ProvidentiaApiClient client;
  final String accountId;
  final String deviceId;
  final String homeId;
  final bool Function() isCurrent;

  void _requireCurrent(String requestedHome) {
    if (!isCurrent() || requestedHome != homeId) {
      throw const AuthenticationSyncException(
        'Reopen the original account and home before recovery.',
      );
    }
  }

  Future<Map<String, Object?>> _invoke(
    String operationId,
    String requestedHome, {
    Map<String, Object?>? body,
  }) async {
    _requireCurrent(requestedHome);
    try {
      final result = (await client.invokeOperation(
        operationId: operationId,
        pathParameters: {'homeId': requestedHome},
        body: body,
      )).requireObject();
      _requireCurrent(requestedHome);
      if (result['homeId'] != homeId ||
          result['accountId'] != accountId ||
          result['deviceId'] != deviceId) {
        throw const BindingSyncException(
          'Recovery requires the original account, device and home. Saved work has not been reassigned.',
          code: 'device_binding_mismatch',
        );
      }
      return result;
    } on generated.ProvidentiaApiException catch (error) {
      if (error.statusCode == 401) {
        throw const AuthenticationSyncException(
          'Sign in with the original account before recovery.',
        );
      }
      // A resource-level 403/404 does not verify membership revocation.
      throw const RetryableSyncException(
        'Recovery could not verify this home and original session. Saved work remains preserved.',
      );
    }
  }

  @override
  Future<SyncRecoveryDiagnostics> diagnostics({required String homeId}) async {
    final result = await _invoke('getSynchronizationDiagnostics', homeId);
    final deployment = result['deployment'];
    if (deployment is! Map<String, Object?> ||
        deployment['contractHash'] is! String ||
        deployment['migrationStatus'] is! String ||
        deployment['contractMatchesLock'] is! bool ||
        (deployment['buildRevision'] != null &&
            deployment['buildRevision'] is! String)) {
      throw const FormatException('Incomplete deployed recovery evidence.');
    }
    return SyncRecoveryDiagnostics(
      accountId: accountId,
      deviceId: deviceId,
      homeId: homeId,
      contractHash: deployment['contractHash']! as String,
      buildRevision: deployment['buildRevision'] as String?,
      migrationStatus: deployment['migrationStatus']! as String,
      contractMatchesLock: deployment['contractMatchesLock']! as bool,
    );
  }

  @override
  Future<List<SyncRecoveryDecision>> revalidate({
    required String homeId,
    required List<SyncRecoveryOperation> operations,
  }) async {
    if (operations.isEmpty || operations.length > 100) {
      throw ArgumentError('Recovery requires one to 100 saved operations.');
    }
    for (final saved in operations) {
      final operation = saved.operation;
      if (operation.homeId != homeId ||
          operation.deviceId != deviceId ||
          operation.originatingAccountId != accountId) {
        throw const BindingSyncException(
          'Restore the original account and device session. Unknown or different operation provenance requires review; no saved identities were changed.',
          code: 'device_binding_mismatch',
        );
      }
    }
    final result = await _invoke(
      'revalidateSynchronizationOperations',
      homeId,
      body: {
        'accountId': accountId,
        'deviceId': deviceId,
        'operations': operations
            .map((saved) {
              final operation = saved.operation;
              return <String, Object?>{
                'blockedCode': saved.blockedCode ?? 'review_required',
                'command': <String, Object?>{
                  'operationId': operation.operationId,
                  'commandType': operation.operationType,
                  'entityId': operation.entityId,
                  if (operation.baseRevision != null)
                    'baseRevision': operation.baseRevision,
                  'clientTimestamp': operation.clientTimestamp
                      .toUtc()
                      .toIso8601String(),
                  'payloadSchemaVersion': operation.payloadSchemaVersion,
                  'payload': operation.payload,
                },
              };
            })
            .toList(growable: false),
      },
    );
    final results = result['operations'];
    if (result['protocolVersion'] != 2 ||
        results is! List<Object?> ||
        results.length != operations.length) {
      throw const FormatException('Incomplete recovery response.');
    }
    return List<SyncRecoveryDecision>.generate(results.length, (index) {
      final item = results[index];
      if (item is! Map<String, Object?> ||
          item['operationId'] != operations[index].operation.operationId) {
        throw const FormatException(
          'Recovery operation identity or ordering changed.',
        );
      }
      final action = switch (item['action']) {
        'readback' => SyncRecoveryAction.readback,
        'retry_same_operation' => SyncRecoveryAction.retrySameOperation,
        'await_predecessor' => SyncRecoveryAction.awaitPredecessor,
        'review_required' => SyncRecoveryAction.reviewRequired,
        _ => throw const FormatException('Unsupported recovery decision.'),
      };
      final code = item['code'];
      final validCode = switch (action) {
        SyncRecoveryAction.readback => code == 'execution_receipt_found',
        SyncRecoveryAction.retrySameOperation =>
          code == 'unknown_under_original_binding',
        SyncRecoveryAction.awaitPredecessor => code == 'dependency_pending',
        SyncRecoveryAction.reviewRequired => const {
          'execution_receipt_found',
          'immutable_request_mismatch',
          'block_not_eligible',
          'permission_denied',
        }.contains(code),
      };
      if (!validCode) {
        throw const FormatException(
          'Recovery decision classification is inconsistent.',
        );
      }
      if (action == SyncRecoveryAction.awaitPredecessor &&
          !operations
              .take(index)
              .any(
                (saved) => saved.operation.operationId == item['predecessorId'],
              )) {
        throw const FormatException(
          'Recovery dependency is not a preserved predecessor.',
        );
      }
      return SyncRecoveryDecision(
        operationId: item['operationId']! as String,
        action: action,
      );
    }, growable: false);
  }
}
