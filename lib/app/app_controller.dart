import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';

enum AppSection { home, stock, purchases, lists }

final class AppController extends ChangeNotifier {
  AppController({
    required SyncCoordinator coordinator,
    required this.activeHomeId,
  }) : _coordinator = coordinator;

  AppController.preview({
    this.activeHomeId = 'preview-home',
    SyncSummary summary = const SyncSummary.initial(),
  }) : _coordinator = null,
       _syncSummary = summary;

  final SyncCoordinator? _coordinator;
  final String activeHomeId;
  StreamSubscription<SyncSummary>? _summarySubscription;

  AppSection _section = AppSection.home;
  SyncSummary _syncSummary = const SyncSummary.initial();
  bool _started = false;

  AppSection get section => _section;
  SyncSummary get syncSummary => _syncSummary;

  Future<void> start() async {
    if (_started || _coordinator == null) {
      return;
    }
    _started = true;
    _summarySubscription = _coordinator.watchSummary().listen((summary) {
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
    final coordinator = _coordinator;
    if (coordinator == null || _syncSummary.isSynchronizing) {
      return;
    }
    final availability = await coordinator.connectivity();
    _syncSummary = _syncSummary.copyWith(
      availability: availability.availability,
      isSynchronizing: availability.availability == SyncAvailability.online,
      lastSafeError: availability.safeMessage,
      clearError: availability.safeMessage == null,
    );
    notifyListeners();

    if (availability.availability == SyncAvailability.online) {
      final outcome = await coordinator.synchronize(activeHomeId);
      final after = await coordinator.connectivity();
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
        lastSuccessfulSync: outcome.completed ? DateTime.now().toUtc() : null,
        lastSafeError: outcome.safeMessage ?? after.safeMessage,
        clearError:
            outcome.completed &&
            outcome.safeMessage == null &&
            after.safeMessage == null,
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_summarySubscription?.cancel());
    super.dispose();
  }
}
