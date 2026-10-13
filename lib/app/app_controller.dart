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

  Future<void> refresh() async {
    final synchronization = _synchronization;
    if (synchronization == null || _refreshing || _disposed) {
      return;
    }

    _refreshing = true;
    _syncSummary = _syncSummary.copyWith(isSynchronizing: true);
    _notifyIfActive();
    try {
      final availability = await synchronization.connectivity();
      if (_disposed) return;
      _syncSummary = _syncSummary.copyWith(
        availability: availability.availability,
        isSynchronizing: true,
        lastSafeError: availability.safeMessage,
        clearError: availability.safeMessage == null,
      );
      _notifyIfActive();

      if (availability.availability != SyncAvailability.online) {
        return;
      }

      final outcome = await synchronization.synchronize(activeHomeId);
      if (_disposed) return;
      final after = await synchronization.connectivity();
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
        isSynchronizing: false,
        lastSuccessfulSync: outcome.completed ? _clock().toUtc() : null,
        lastSafeError: outcome.safeMessage ?? after.safeMessage,
        clearError:
            outcome.completed &&
            outcome.safeMessage == null &&
            after.safeMessage == null,
      );
      _notifyIfActive();
    } on Exception {
      _syncSummary = _syncSummary.copyWith(
        availability: SyncAvailability.temporarilyUnavailable,
        lastSafeError: 'Synchronization was interrupted. Try again safely.',
      );
    } finally {
      _refreshing = false;
      _syncSummary = _syncSummary.copyWith(isSynchronizing: false);
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
