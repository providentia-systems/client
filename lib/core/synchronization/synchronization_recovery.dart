import 'package:providentia/core/synchronization/sync_models.dart';

/// Recovery never creates replacement identities or treats a server export as
/// preservation of the installation's unsynchronized encrypted database.
abstract interface class AppSyncRecovery {
  Future<SyncRecoveryInspection> inspectRecovery(String homeId);
  Future<SyncRecoveryOutcome> rebuildSavedHome(String homeId);
  Future<SyncRecoveryOutcome> revalidateSavedOperations(String homeId);
}

final class SyncRecoveryOperation {
  const SyncRecoveryOperation({
    required this.operation,
    required this.state,
    required this.blockedCode,
  });

  final PendingClientOperation operation;
  final ClientOperationState state;
  final String? blockedCode;
}

final class SyncRecoveryDiagnostics {
  const SyncRecoveryDiagnostics({
    required this.accountId,
    required this.deviceId,
    required this.homeId,
    required this.contractHash,
    required this.buildRevision,
    required this.migrationStatus,
    required this.contractMatchesLock,
  });

  final String accountId;
  final String deviceId;
  final String homeId;
  final String contractHash;
  final String? buildRevision;
  final String migrationStatus;
  final bool contractMatchesLock;
}

final class SyncRecoveryInspection {
  const SyncRecoveryInspection({
    required this.diagnostics,
    required this.saved,
  });
  final SyncRecoveryDiagnostics diagnostics;
  final SyncSummary saved;
}

enum SyncRecoveryAction {
  readback,
  retrySameOperation,
  awaitPredecessor,
  reviewRequired,
}

final class SyncRecoveryDecision {
  const SyncRecoveryDecision({required this.operationId, required this.action});
  final String operationId;
  final SyncRecoveryAction action;
}

final class SyncRecoveryOutcome {
  const SyncRecoveryOutcome({
    required this.message,
    this.recovered = 0,
    this.needsReview = 0,
  });
  final String message;
  final int recovered;
  final int needsReview;
}

abstract interface class SyncRecoveryGateway {
  Future<SyncRecoveryDiagnostics> diagnostics({required String homeId});
  Future<List<SyncRecoveryDecision>> revalidate({
    required String homeId,
    required List<SyncRecoveryOperation> operations,
  });
}

/// Implementations preserve the encrypted durable queue atomically with its
/// optimistic projections. No plaintext payload export is exposed to widgets.
abstract interface class SyncRecoveryStore {
  Future<void> requireOriginalRecoveryBinding({
    required String homeId,
    required String accountId,
    required String deviceId,
  });
  Future<List<SyncRecoveryOperation>> recoveryOperations({
    required String homeId,
  });
  Future<void> replaceWithRecoveryBootstrap({
    required String homeId,
    required PullPage page,
  });
  Future<void> requeueRevalidatedOperation({
    required SyncRecoveryOperation operation,
    required DateTime now,
  });
}
