import 'package:providentia/core/synchronization/sync_models.dart';

abstract interface class LocalSyncRepository {
  Stream<SyncSummary> watchSummary();

  Future<void> commitLocalMutation(LocalMutation mutation);

  Future<List<PendingClientOperation>> pendingOperations({
    required String homeId,
    required DateTime now,
    int limit = 100,
  });

  Future<void> markSyncing(List<String> operationIds);

  Future<void> recoverInterruptedOperations({required DateTime now});

  Future<void> applyPushResults({
    required List<PushOperationResult> results,
    required DateTime now,
    required RetryPolicy retryPolicy,
  });

  Future<String?> cursorForHome(String homeId);

  Future<void> applyPullPage({required String homeId, required PullPage page});

  Future<void> requeueRetryableOperations({
    required String homeId,
    required DateTime now,
  });

  Future<void> requeueOperation({
    required String operationId,
    required DateTime now,
  });
}

abstract interface class SyncRemoteGateway {
  Future<PullPage> bootstrap({required String homeId});

  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
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
}

final class NoopSyncMetrics implements SyncMetrics {
  const NoopSyncMetrics();

  @override
  void recordAttempt({required int operationCount}) {}

  @override
  void recordFailure({required String classification}) {}

  @override
  void recordSuccess({
    required int acknowledgedCount,
    required int pulledChangeCount,
  }) {}
}

final class RetryPolicy {
  const RetryPolicy({
    this.baseDelay = const Duration(seconds: 2),
    this.maximumDelay = const Duration(minutes: 15),
  });

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
