import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

enum AppSection { home, stock, purchases, lists }

final class AppController extends ChangeNotifier {
  factory AppController({
    required AppSynchronization synchronization,
    required String activeHomeId,
    DateTime Function()? clock,
  }) => AppController._(synchronization, activeHomeId, clock ?? DateTime.now);

  AppController._(this._synchronization, this.activeHomeId, this._clock);

  AppController.preview({
    this.activeHomeId = 'preview-home',
    SyncSummary summary = const SyncSummary.initial(),
    DateTime Function()? clock,
  }) : _synchronization = null,
       _clock = clock ?? DateTime.now,
       _syncSummary = summary;

  final AppSynchronization? _synchronization;
  final DateTime Function() _clock;
  final String activeHomeId;
  StreamSubscription<SyncSummary>? _summarySubscription;

  AppSection _section = AppSection.home;
  SyncSummary _syncSummary = const SyncSummary.initial();
  bool _started = false;
  bool _refreshing = false;
  Future<void>? _refreshFuture;
  bool _refreshRequested = false;
  bool _disposed = false;

  AppSection get section => _section;
  SyncSummary get syncSummary => _syncSummary;

  Future<void> start() async {
    if (_started || _synchronization == null || _disposed) {
      return;
    }
    _started = true;
    _summarySubscription = _synchronization
        .watchSummary(homeId: activeHomeId)
        .listen((summary) {
          _syncSummary = summary.copyWith(
            availability: _syncSummary.availability,
            lastSuccessfulSync: _syncSummary.lastSuccessfulSync,
            isSynchronizing: _refreshing || summary.isSynchronizing,
            lastSafeError: summary.lastSafeError ?? _syncSummary.lastSafeError,
          );
          _notifyIfActive();
        });
    await refresh();
  }

  void selectSection(AppSection section) {
    if (_section == section) {
      return;
    }
    _section = section;
    _notifyIfActive();
  }

  /// Every caller observes the same serialized run. A request received during
  /// that run schedules another pass, covering mutations saved after its queue
  /// snapshot without allowing concurrent uploads.
  Future<void> refresh() {
    if (_synchronization == null || _disposed) return Future<void>.value();
    final active = _refreshFuture;
    if (active != null) {
      _refreshRequested = true;
      return active;
    }
    final completer = Completer<void>();
    _refreshFuture = completer.future;
    _refreshing = true;
    _syncSummary = _syncSummary.copyWith(isSynchronizing: true);
    _notifyIfActive();
    unawaited(_drainRefreshRequests(completer));
    return completer.future;
  }

  Future<void> _drainRefreshRequests(Completer<void> completer) async {
    try {
      do {
        _refreshRequested = false;
        await _refreshOnce();
      } while (_refreshRequested && !_disposed);
    } finally {
      _refreshing = false;
      _refreshFuture = null;
      _syncSummary = _syncSummary.copyWith(isSynchronizing: false);
      _notifyIfActive();
      completer.complete();
    }
  }

  Future<void> _refreshOnce() async {
    final synchronization = _synchronization!;
    try {
      final availability = await synchronization.connectivity();
      if (_disposed) return;
      _syncSummary = _syncSummary.copyWith(
        availability: availability.availability,
        isSynchronizing: true,
        lastSafeError: availability.safeMessage,
        clearError:
            availability.safeMessage == null && _syncSummary.unresolved == 0,
      );
      _notifyIfActive();
      if (availability.availability != SyncAvailability.online) return;

      final outcome = await synchronization.synchronize(activeHomeId);
      if (_disposed) return;
      final after = await synchronization.connectivity();
      if (_disposed) return;
      final outcomeAvailability = switch (outcome.status) {
        SyncRunStatus.authenticationRequired =>
          SyncAvailability.authenticationRequired,
        SyncRunStatus.authorizationFailure =>
          SyncAvailability.authorizationDenied,
        SyncRunStatus.offline => SyncAvailability.offline,
        SyncRunStatus.retryableFailure =>
          SyncAvailability.temporarilyUnavailable,
        SyncRunStatus.alreadyRunning => SyncAvailability.checking,
        _ => after.availability,
      };
      _syncSummary = _syncSummary.copyWith(
        availability: outcomeAvailability,
        isSynchronizing: true,
        lastSuccessfulSync: outcome.completed ? _clock().toUtc() : null,
        lastSafeError: outcome.safeMessage ?? after.safeMessage,
        clearError:
            outcome.completed &&
            outcome.safeMessage == null &&
            after.safeMessage == null,
        failureCode: outcome.failureCode,
        blockedOperationType: outcome.blockedOperationType,
        nextRetryAt: outcome.nextRetryAt,
        clearDiagnostics: outcome.completed,
      );
      _notifyIfActive();
    } on Exception {
      if (_disposed) return;
      _syncSummary = _syncSummary.copyWith(
        availability: SyncAvailability.temporarilyUnavailable,
        lastSafeError: 'Synchronization was interrupted. Try again safely.',
        failureCode: 'service_unavailable',
      );
      _notifyIfActive();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_summarySubscription?.cancel());
    super.dispose();
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
