import 'dart:async';

import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

/// Foreground synchronization orchestrator.
///
/// Mobile background execution remains best effort. The composition root calls
/// this coordinator on start, resume, home switch, manual refresh, and after
/// foreground mutations.
final class SyncCoordinator implements AppSynchronization {
  factory SyncCoordinator({
    required LocalSyncStore local,
    required SyncRemoteGateway remote,
    required ConnectivityProbe connectivity,
    SyncMetrics metrics = const NoopSyncMetrics(),
    AuthenticationRecovery authenticationRecovery =
        const NoAuthenticationRecovery(),
    RetryPolicy? retryPolicy,
    DateTime Function()? clock,
    int maximumPullPages = 1000,
  }) {
    if (maximumPullPages < 1) {
      throw ArgumentError.value(
        maximumPullPages,
        'maximumPullPages',
        'must be at least one',
      );
    }
    return SyncCoordinator._(
      local,
      remote,
      connectivity,
      metrics,
      authenticationRecovery,
      retryPolicy ?? RetryPolicy(),
      clock ?? DateTime.now,
      maximumPullPages,
    );
  }

  SyncCoordinator._(
    this._local,
    this._remote,
    this._connectivity,
    this._metrics,
    this._authenticationRecovery,
    this._retryPolicy,
    this._clock,
    this._maximumPullPages,
  );

  final LocalSyncStore _local;
  final SyncRemoteGateway _remote;
  final ConnectivityProbe _connectivity;
  final SyncMetrics _metrics;
  final AuthenticationRecovery _authenticationRecovery;
  final RetryPolicy _retryPolicy;
  final DateTime Function() _clock;
  final int _maximumPullPages;

  bool _running = false;

  @override
  Stream<SyncSummary> watchSummary({required String homeId}) {
    return _local.watchSummary(homeId: homeId);
  }

  @override
  Future<ConnectivityResult> connectivity() => _connectivity.check();

  @override
  Future<SyncRunOutcome> synchronize(String homeId) async {
    if (_running) {
      return const SyncRunOutcome(
        status: SyncRunStatus.alreadyRunning,
        safeMessage: 'Synchronization is already in progress.',
      );
    }
    _running = true;
    var acknowledged = 0;
    var pulled = 0;
    try {
      final connectivity = await _connectivity.check();
      if (connectivity.availability != SyncAvailability.online) {
        _metrics.recordFailure(classification: connectivity.availability.name);
        return SyncRunOutcome(
          status:
              connectivity.availability ==
                  SyncAvailability.authenticationRequired
              ? SyncRunStatus.authenticationRequired
              : SyncRunStatus.offline,
          safeMessage: connectivity.safeMessage,
        );
      }

      final now = _clock().toUtc();
      await _local.recoverInterruptedOperations(now: now);
      await _local.requeueRetryableOperations(homeId: homeId, now: now);
      final operations = await _local.pendingOperations(
        homeId: homeId,
        now: now,
      );
      final lastPulledCursor = await _local.cursorForHome(homeId);
      _metrics.recordAttempt(operationCount: operations.length);

      for (final operation in operations) {
        final operationIds = <String>[operation.operationId];
        await _local.markSyncing(operationIds);
        try {
          PushResponse response;
          try {
            response = await _remote.push(
              homeId: homeId,
              lastPulledCursor: lastPulledCursor,
              operations: <PendingClientOperation>[operation],
            );
          } on AuthenticationSyncException {
            final recovered = await _authenticationRecovery.tryRecover();
            if (!recovered) {
              rethrow;
            }
            response = await _remote.push(
              homeId: homeId,
              lastPulledCursor: lastPulledCursor,
              operations: <PendingClientOperation>[operation],
            );
          }
          if (response.results.length != 1 ||
              response.results.single.operationId != operation.operationId) {
            throw const FormatException(
              'Synchronization returned an invalid command result.',
            );
          }
          await _local.applyPushResults(
            results: response.results,
            now: _clock().toUtc(),
            retryPolicy: _retryPolicy,
          );
          if (response.results.single.kind == PushResultKind.acknowledged) {
            acknowledged++;
            continue;
          }
          // Commands are dependency ordered. Never submit a later command
          // after its predecessor was rejected or deferred.
          break;
        } on AuthenticationSyncException catch (error) {
          // Expired credentials do not mean that the user lost permission.
          // Keep intent retryable and surface authentication-required state.
          await _local.applyPushResults(
            results: operationIds
                .map(
                  (id) => PushOperationResult(
                    operationId: id,
                    kind: PushResultKind.retryableFailure,
                    safeMessage: error.safeMessage,
                  ),
                )
                .toList(growable: false),
            now: _clock().toUtc(),
            retryPolicy: _retryPolicy,
          );
          rethrow;
        } on Exception {
          // A lost response is retryable. Idempotency is provided by the
          // durable operation ID and must be enforced by the server.
          await _local.applyPushResults(
            results: operationIds
                .map(
                  (id) => PushOperationResult(
                    operationId: id,
                    kind: PushResultKind.retryableFailure,
                    safeMessage: 'Connection interrupted. Retrying safely.',
                  ),
                )
                .toList(growable: false),
            now: _clock().toUtc(),
            retryPolicy: _retryPolicy,
          );
          rethrow;
        }
      }

      var cursor = await _local.cursorForHome(homeId);
      if (cursor == null) {
        final bootstrap = await _remote.bootstrap(homeId: homeId);
        await _local.replaceWithBootstrap(homeId: homeId, page: bootstrap);
        pulled += bootstrap.changes.length;
        cursor = bootstrap.pageCursor;
      }
      var hasMore = true;
      var resynchronized = false;
      var pullPageCount = 0;
      String? highWaterCursor;
      while (hasMore) {
        pullPageCount++;
        if (pullPageCount > _maximumPullPages) {
          throw const RetryableSyncException(
            'Synchronization returned too many pages. Try again safely.',
          );
        }

        PullPage page;
        try {
          page = await _remote.pull(homeId: homeId, afterCursor: cursor);
        } on ResyncRequiredSyncException {
          if (resynchronized) {
            throw const RetryableSyncException(
              'Synchronization history changed again. Try again safely.',
            );
          }
          final bootstrap = await _remote.bootstrap(homeId: homeId);
          await _local.replaceWithBootstrap(homeId: homeId, page: bootstrap);
          pulled += bootstrap.changes.length;
          cursor = bootstrap.pageCursor;
          highWaterCursor = null;
          resynchronized = true;
          continue;
        }

        if (highWaterCursor != null &&
            page.highWaterCursor != highWaterCursor) {
          throw const RetryableSyncException(
            'Synchronization page boundary changed. Try again safely.',
          );
        }
        highWaterCursor ??= page.highWaterCursor;
        if (page.hasMore && page.pageCursor == cursor) {
          throw const RetryableSyncException(
            'Synchronization cursor did not advance. Try again safely.',
          );
        }

        await _local.applyPullPage(homeId: homeId, page: page);
        pulled += page.changes.length;
        cursor = page.pageCursor;
        hasMore = page.hasMore;
      }
      _metrics.recordSuccess(
        acknowledgedCount: acknowledged,
        pulledChangeCount: pulled,
      );
      return SyncRunOutcome(
        status: SyncRunStatus.completed,
        acknowledgedCount: acknowledged,
        pulledChangeCount: pulled,
      );
    } on AuthenticationSyncException catch (error) {
      _metrics.recordFailure(classification: 'authentication_required');
      return SyncRunOutcome(
        status: SyncRunStatus.authenticationRequired,
        safeMessage: error.safeMessage,
        acknowledgedCount: acknowledged,
        pulledChangeCount: pulled,
      );
    } on AuthorizationSyncException catch (error) {
      _metrics.recordFailure(classification: 'authorization_failure');
      return SyncRunOutcome(
        status: SyncRunStatus.authorizationFailure,
        safeMessage: error.safeMessage,
        acknowledgedCount: acknowledged,
        pulledChangeCount: pulled,
      );
    } on RetryableSyncException catch (error) {
      _metrics.recordFailure(classification: 'retryable');
      return SyncRunOutcome(
        status: SyncRunStatus.retryableFailure,
        safeMessage: error.safeMessage,
        acknowledgedCount: acknowledged,
        pulledChangeCount: pulled,
      );
    } on Exception {
      _metrics.recordFailure(classification: 'retryable');
      return SyncRunOutcome(
        status: SyncRunStatus.retryableFailure,
        safeMessage: 'Synchronization was interrupted. Try again safely.',
        acknowledgedCount: acknowledged,
        pulledChangeCount: pulled,
      );
    } finally {
      _running = false;
    }
  }

  Future<SyncRunOutcome> retryOperation({
    required String homeId,
    required String operationId,
  }) async {
    await _local.requeueOperation(
      homeId: homeId,
      operationId: operationId,
      now: _clock().toUtc(),
    );
    return synchronize(homeId);
  }
}
