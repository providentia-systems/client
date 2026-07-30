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
  }) => AppController._(
    synchronization,
    activeHomeId,
    clock ?? DateTime.now,
  );

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

  AppSection get section => _section;
  SyncSummary get syncSummary => _syncSummary;

  Future<void> start() async {
    if (_started || _synchronization == null) {
      return;
    }
    _started = true;
    _summarySubscription = _synchronization
        .watchSummary(homeId: activeHomeId)
        .listen((summary) {
          _syncSummary = summary.copyWith(
            availability: _syncSummary.availability,
            lastSuccessfulSync: _syncSummary.lastSuccessfulSync,
          );
          notifyListeners();
        });
    await refresh();
  }

  void selectSection(AppSection section) {
    if (_section == section) {
      return;
    }
    _section = section;
    notifyListeners();
  }

  Future<void> refresh() async {
    final synchronization = _synchronization;
    if (synchronization == null || _refreshing) {
      return;
    }

    _refreshing = true;
    try {
      final availability = await synchronization.connectivity();
      _syncSummary = _syncSummary.copyWith(
        availability: availability.availability,
        isSynchronizing: availability.availability == SyncAvailability.online,
        lastSafeError: availability.safeMessage,
        clearError: availability.safeMessage == null,
      );
      notifyListeners();

      if (availability.availability != SyncAvailability.online) {
        return;
      }

      final outcome = await synchronization.synchronize(activeHomeId);
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
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    unawaited(_summarySubscription?.cancel());
    super.dispose();
  }
}
