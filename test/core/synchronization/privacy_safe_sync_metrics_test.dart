import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/synchronization/privacy_safe_sync_metrics.dart';

void main() {
  test('publishes only fixed count and duration aggregates', () {
    final published = <SyncMetricsSnapshot>[];
    final metrics = PrivacySafeSyncMetrics(
      sink: CallbackSyncMetricsSnapshotSink(published.add),
    );

    metrics.recordAttempt(operationCount: 3);
    metrics.recordSuccess(acknowledgedCount: 2, pulledChangeCount: 5);
    metrics.recordFailure(classification: 'offline');
    metrics.recordFailure(classification: 'authorization_failure');
    metrics.recordDuration(elapsed: const Duration(milliseconds: 1250));

    final snapshot = published.last;
    expect(snapshot.attemptCount, 1);
    expect(snapshot.attemptedOperationCount, 3);
    expect(snapshot.successCount, 1);
    expect(snapshot.acknowledgedOperationCount, 2);
    expect(snapshot.pulledChangeCount, 5);
    expect(snapshot.offlineFailureCount, 1);
    expect(snapshot.authorizationFailureCount, 1);
    expect(snapshot.completedDurationCount, 1);
    expect(snapshot.totalDurationMicroseconds, 1250000);
    expect(snapshot.maximumDurationMicroseconds, 1250000);
  });

  test('unknown failure text is reduced to other and never forwarded', () {
    final published = <SyncMetricsSnapshot>[];
    final metrics = PrivacySafeSyncMetrics(
      sink: CallbackSyncMetricsSnapshotSink(published.add),
    );
    const sensitive = 'home-123 item Milk operation 0198 payload quantity=999';

    metrics.recordFailure(classification: sensitive);

    expect(metrics.snapshot.otherFailureCount, 1);
    expect(published, hasLength(1));
    expect(published.single.toString(), isNot(contains(sensitive)));
  });

  test('telemetry sink failure cannot break synchronization metrics calls', () {
    final metrics = PrivacySafeSyncMetrics(sink: const _ThrowingSink());

    expect(() => metrics.recordAttempt(operationCount: 1), returnsNormally);
    expect(metrics.snapshot.attemptCount, 1);
  });

  test('rejects impossible negative measurements before publishing', () {
    final published = <SyncMetricsSnapshot>[];
    final metrics = PrivacySafeSyncMetrics(
      sink: CallbackSyncMetricsSnapshotSink(published.add),
    );

    expect(
      () => metrics.recordAttempt(operationCount: -1),
      throwsArgumentError,
    );
    expect(
      () => metrics.recordDuration(elapsed: const Duration(microseconds: -1)),
      throwsArgumentError,
    );
    expect(published, isEmpty);
  });
}

final class _ThrowingSink implements SyncMetricsSnapshotSink {
  const _ThrowingSink();

  @override
  void publish(SyncMetricsSnapshot snapshot) {
    throw StateError('telemetry unavailable');
  }
}
