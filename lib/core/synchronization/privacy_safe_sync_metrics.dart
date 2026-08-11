import 'package:providentia/core/synchronization/sync_ports.dart';

/// Fixed numeric telemetry with no home IDs, operation IDs, cursors, payloads,
/// item names, error messages, timestamps, or other household content.
final class SyncMetricsSnapshot {
  const SyncMetricsSnapshot({
    required this.attemptCount,
    required this.attemptedOperationCount,
    required this.successCount,
    required this.acknowledgedOperationCount,
    required this.pulledChangeCount,
    required this.offlineFailureCount,
    required this.authenticationFailureCount,
    required this.authorizationFailureCount,
    required this.retryableFailureCount,
    required this.otherFailureCount,
    required this.completedDurationCount,
    required this.totalDurationMicroseconds,
    required this.maximumDurationMicroseconds,
  });

  final int attemptCount;
  final int attemptedOperationCount;
  final int successCount;
  final int acknowledgedOperationCount;
  final int pulledChangeCount;
  final int offlineFailureCount;
  final int authenticationFailureCount;
  final int authorizationFailureCount;
  final int retryableFailureCount;
  final int otherFailureCount;
  final int completedDurationCount;
  final int totalDurationMicroseconds;
  final int maximumDurationMicroseconds;
}

abstract interface class SyncMetricsSnapshotSink {
  void publish(SyncMetricsSnapshot snapshot);
}

final class CallbackSyncMetricsSnapshotSink implements SyncMetricsSnapshotSink {
  const CallbackSyncMetricsSnapshotSink(this.callback);

  final void Function(SyncMetricsSnapshot snapshot) callback;

  @override
  void publish(SyncMetricsSnapshot snapshot) => callback(snapshot);
}

/// Production-safe aggregate sink. Unknown failure text is reduced to a fixed
/// `other` counter and is never retained or forwarded.
final class PrivacySafeSyncMetrics implements SyncMetrics {
  PrivacySafeSyncMetrics({required SyncMetricsSnapshotSink sink})
    : this._(sink);

  PrivacySafeSyncMetrics._(this._sink);

  final SyncMetricsSnapshotSink _sink;
  int _attemptCount = 0;
  int _attemptedOperationCount = 0;
  int _successCount = 0;
  int _acknowledgedOperationCount = 0;
  int _pulledChangeCount = 0;
  int _offlineFailureCount = 0;
  int _authenticationFailureCount = 0;
  int _authorizationFailureCount = 0;
  int _retryableFailureCount = 0;
  int _otherFailureCount = 0;
  int _completedDurationCount = 0;
  int _totalDurationMicroseconds = 0;
  int _maximumDurationMicroseconds = 0;

  SyncMetricsSnapshot get snapshot => SyncMetricsSnapshot(
    attemptCount: _attemptCount,
    attemptedOperationCount: _attemptedOperationCount,
    successCount: _successCount,
    acknowledgedOperationCount: _acknowledgedOperationCount,
    pulledChangeCount: _pulledChangeCount,
    offlineFailureCount: _offlineFailureCount,
    authenticationFailureCount: _authenticationFailureCount,
    authorizationFailureCount: _authorizationFailureCount,
    retryableFailureCount: _retryableFailureCount,
    otherFailureCount: _otherFailureCount,
    completedDurationCount: _completedDurationCount,
    totalDurationMicroseconds: _totalDurationMicroseconds,
    maximumDurationMicroseconds: _maximumDurationMicroseconds,
  );

  @override
  void recordAttempt({required int operationCount}) {
    _requireCount(operationCount, 'operationCount');
    _attemptCount++;
    _attemptedOperationCount += operationCount;
    _publish();
  }

  @override
  void recordSuccess({
    required int acknowledgedCount,
    required int pulledChangeCount,
  }) {
    _requireCount(acknowledgedCount, 'acknowledgedCount');
    _requireCount(pulledChangeCount, 'pulledChangeCount');
    _successCount++;
    _acknowledgedOperationCount += acknowledgedCount;
    _pulledChangeCount += pulledChangeCount;
    _publish();
  }

  @override
  void recordFailure({required String classification}) {
    switch (classification) {
      case 'offline':
        _offlineFailureCount++;
      case 'authenticationRequired' || 'authentication_required':
        _authenticationFailureCount++;
      case 'authorizationDenied' || 'authorization_failure':
        _authorizationFailureCount++;
      case 'temporarilyUnavailable' || 'retryable':
        _retryableFailureCount++;
      default:
        _otherFailureCount++;
    }
    _publish();
  }

  @override
  void recordDuration({required Duration elapsed}) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must not be negative');
    }
    final microseconds = elapsed.inMicroseconds;
    _completedDurationCount++;
    _totalDurationMicroseconds += microseconds;
    if (microseconds > _maximumDurationMicroseconds) {
      _maximumDurationMicroseconds = microseconds;
    }
    _publish();
  }

  void _publish() {
    // Telemetry must never change synchronization behavior.
    try {
      _sink.publish(snapshot);
    } catch (_) {}
  }

  void _requireCount(int value, String name) {
    if (value < 0) {
      throw ArgumentError.value(value, name, 'must not be negative');
    }
  }
}
