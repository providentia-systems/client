import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

void main() {
  test('retry policy is deterministic, exponential, and bounded', () {
    final policy = RetryPolicy(
      baseDelay: Duration(seconds: 2),
      maximumDelay: Duration(seconds: 30),
    );

    final first = policy.delayFor(operationId: 'same-id', retryCount: 0);
    final later = policy.delayFor(operationId: 'same-id', retryCount: 3);
    final repeated = policy.delayFor(operationId: 'same-id', retryCount: 3);
    final capped = policy.delayFor(operationId: 'same-id', retryCount: 30);

    expect(first, greaterThanOrEqualTo(const Duration(seconds: 2)));
    expect(later, greaterThan(first));
    expect(repeated, later);
    expect(capped, lessThanOrEqualTo(const Duration(seconds: 36)));
  });

  test('retry policy rejects impossible delay ranges', () {
    expect(() => RetryPolicy(baseDelay: Duration.zero), throwsArgumentError);
    expect(
      () => RetryPolicy(
        baseDelay: const Duration(seconds: 2),
        maximumDelay: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
  });

  test('default authentication recovery never invents a session', () async {
    expect(await const NoAuthenticationRecovery().tryRecover(), isFalse);
  });

  test('no-op metrics accept every lifecycle event', () {
    const metrics = NoopSyncMetrics();

    expect(() {
      metrics.recordAttempt(operationCount: 2);
      metrics.recordSuccess(acknowledgedCount: 1, pulledChangeCount: 3);
      metrics.recordFailure(classification: 'offline');
      metrics.recordDuration(elapsed: const Duration(milliseconds: 5));
    }, returnsNormally);
  });
}
