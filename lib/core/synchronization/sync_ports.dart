import 'package:providentia/core/synchronization/sync_models.dart';

/// Application-facing synchronization use cases.
///
/// Presentation depends on this abstraction rather than the concrete
/// coordinator, keeping orchestration replaceable and independently testable.
abstract interface class AppSynchronization {
  Stream<SyncSummary> watchSummary({required String homeId});

  Future<ConnectivityResult> connectivity();

  Future<SyncRunOutcome> synchronize(String homeId);
}

/// Atomic local domain mutation and durable outbox boundary.
///
/// Feature code that writes local state does not need access to cursor,
/// recovery, or transport synchronization operations.
abstract interface class LocalMutationRepository {
  Future<void> commitLocalMutation(LocalMutation mutation);
}

/// Persistence operations required only by synchronization orchestration.
abstract interface class LocalSyncStore {
  Stream<SyncSummary> watchSummary({required String homeId});

  Future<List<PendingClientOperation>> pendingOperations({
    required String homeId,
    required DateTime now,
    int limit = 100,
  });

  Future<void> markSyncing(List<String> operationIds);

  Future<List<String>> recoverInterruptedOperations({
    required String homeId,
    required DateTime now,
  });

  Future<void> applyPushResults({
    required List<PushOperationResult> results,
    required DateTime now,
    required RetryPolicy retryPolicy,
  });

  Future<String?> cursorForHome(String homeId);

  Future<void> applyPullPage({required String homeId, required PullPage page});

  Future<void> replaceWithBootstrap({
    required String homeId,
    required PullPage page,
  });

  Future<void> requeueRetryableOperations({
    required String homeId,
    required DateTime now,
  });

  Future<void> requeueOperation({
    required String homeId,
    required String operationId,
    required DateTime now,
  });
}

/// Atomic persistence boundary for explicit, home-scoped conflict review.
abstract interface class LocalSyncConflictStore {
  Stream<List<SyncConflict>> watchUnresolvedConflicts({required String homeId});

  Future<List<SyncConflict>> unresolvedConflicts({required String homeId});

  Future<void> acceptRemoteConflict({
    required String homeId,
    required String conflictId,
    required DateTime resolvedAt,
  });

  Future<void> reapplyLocalConflict({
    required String homeId,
    required String conflictId,
    required String newOperationId,
    required DateTime resolvedAt,
  });

  Future<void> reconcileCountConflict({
    required String homeId,
    required String conflictId,
    required DateTime resolvedAt,
  });
}

/// Convenience aggregate implemented by the Drift adapter.
///
/// Consumers should request the smallest port they need.
abstract interface class LocalSyncRepository
    implements
        LocalMutationRepository,
        LocalSyncStore,
        LocalSyncConflictStore {}

abstract interface class SyncRemoteGateway {
  Future<PullPage> bootstrap({required String homeId});

  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
  });

  Future<OperationStatusResponse> operationStatuses({
    required String homeId,
    required String deviceId,
    required List<String> operationIds,
  });

  Future<PullPage> pull({required String homeId, String? afterCursor});
}

abstract interface class ConnectivityProbe {
  Future<ConnectivityResult> check();
}

abstract interface class AuthenticationRecovery {
  Future<bool> tryRecover();
}

final class NoAuthenticationRecovery implements AuthenticationRecovery {
  const NoAuthenticationRecovery();

  @override
  Future<bool> tryRecover() async => false;
}

abstract interface class SyncMetrics {
  void recordAttempt({required int operationCount});

  void recordSuccess({
    required int acknowledgedCount,
    required int pulledChangeCount,
  });

  void recordFailure({required String classification});

  void recordDuration({required Duration elapsed});
}

final class NoopSyncMetrics implements SyncMetrics {
  const NoopSyncMetrics();

  @override
  void recordAttempt({required int operationCount}) {}

  @override
  void recordFailure({required String classification}) {}

  @override
  void recordDuration({required Duration elapsed}) {}

  @override
  void recordSuccess({
    required int acknowledgedCount,
    required int pulledChangeCount,
  }) {}
}

final class RetryPolicy {
  factory RetryPolicy({
    Duration baseDelay = const Duration(seconds: 2),
    Duration maximumDelay = const Duration(minutes: 15),
  }) {
    if (baseDelay <= Duration.zero) {
      throw ArgumentError.value(baseDelay, 'baseDelay', 'must be positive');
    }
    if (maximumDelay < baseDelay) {
      throw ArgumentError.value(
        maximumDelay,
        'maximumDelay',
        'must not be shorter than baseDelay',
      );
    }
    return RetryPolicy._(baseDelay, maximumDelay);
  }

  const RetryPolicy._(this.baseDelay, this.maximumDelay);

  final Duration baseDelay;
  final Duration maximumDelay;

  Duration delayFor({required String operationId, required int retryCount}) {
    final exponent = retryCount.clamp(0, 20);
    final baseMilliseconds = baseDelay.inMilliseconds * (1 << exponent);
    final capped = baseMilliseconds.clamp(
      baseDelay.inMilliseconds,
      maximumDelay.inMilliseconds,
    );
    final jitterRange = (capped * 0.2).round();
    final jitter = jitterRange == 0
        ? 0
        : _stableHash(operationId) % (jitterRange + 1);
    return Duration(milliseconds: (capped + jitter).round());
  }

  int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
