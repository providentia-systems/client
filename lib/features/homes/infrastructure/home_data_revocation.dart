import 'dart:async';

import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

/// Serializes home-data purge after every synchronization run that was already
/// admitted before membership revocation.
///
/// Marking a home revoked is synchronous. A late remote response may finish its
/// already-admitted local transaction, but purge waits for that whole run and
/// therefore remains the final database writer. New runs fail closed.
final class HomeSyncRevocationGate {
  final Map<String, _HomeSyncState> _states = <String, _HomeSyncState>{};

  Future<SyncRunOutcome> run(
    String homeId,
    Future<SyncRunOutcome> Function() synchronization,
  ) {
    final state = _states.putIfAbsent(homeId, _HomeSyncState.new);
    if (state.revoked) {
      return Future<SyncRunOutcome>.value(
        const SyncRunOutcome(
          status: SyncRunStatus.authorizationFailure,
          safeMessage: 'Access to this home changed. Synchronization stopped.',
        ),
      );
    }
    state.activeRuns++;
    return Future<SyncRunOutcome>.sync(synchronization).whenComplete(() {
      state.activeRuns--;
      if (state.revoked && state.activeRuns == 0) {
        state.quiesced?.complete();
        state.quiesced = null;
      }
    });
  }

  /// Prevents new runs immediately and completes after admitted runs finish.
  Future<void> revokeAndWait(String homeId) {
    final state = _states.putIfAbsent(homeId, _HomeSyncState.new);
    state.revoked = true;
    if (state.activeRuns == 0) {
      return Future<void>.value();
    }
    return (state.quiesced ??= Completer<void>()).future;
  }

  /// Called only after revoked local data has been purged successfully.
  void reauthorize(String homeId) {
    final state = _states.putIfAbsent(homeId, _HomeSyncState.new);
    if (state.activeRuns != 0 || state.quiesced != null) {
      throw StateError('Home synchronization has not quiesced.');
    }
    state.revoked = false;
  }
}

final class _HomeSyncState {
  bool revoked = false;
  int activeRuns = 0;
  Completer<void>? quiesced;
}

/// Binds an [AppSynchronization] instance to one revocable home.
final class RevocationGuardedSynchronization implements AppSynchronization {
  factory RevocationGuardedSynchronization({
    required AppSynchronization delegate,
    required HomeSyncRevocationGate gate,
    required String homeId,
  }) => RevocationGuardedSynchronization._(delegate, gate, homeId);

  RevocationGuardedSynchronization._(this._delegate, this._gate, this._homeId);

  final AppSynchronization _delegate;
  final HomeSyncRevocationGate _gate;
  final String _homeId;

  @override
  Future<ConnectivityResult> connectivity() => _delegate.connectivity();

  @override
  Future<SyncRunOutcome> synchronize(String homeId) {
    _requireBoundHome(homeId);
    return _gate.run(homeId, () => _delegate.synchronize(homeId));
  }

  @override
  Stream<SyncSummary> watchSummary({required String homeId}) {
    _requireBoundHome(homeId);
    return _delegate.watchSummary(homeId: homeId);
  }

  void _requireBoundHome(String homeId) {
    if (homeId != _homeId) {
      throw ArgumentError.value(
        homeId,
        'homeId',
        'must match this isolated home workspace',
      );
    }
  }
}

/// Deletes every Drift-backed cache and pending command scoped to one home.
final class RevokedHomeDataPurger {
  const RevokedHomeDataPurger(this._database);

  final AppDatabase _database;

  Future<void> purge(String homeId) {
    return _database.transaction(() async {
      await (_database.delete(
        _database.syncConflictRecords,
      )..where((row) => row.homeId.equals(homeId))).go();
      await (_database.delete(
        _database.clientOperations,
      )..where((row) => row.homeId.equals(homeId))).go();
      await (_database.delete(
        _database.localSyncCursors,
      )..where((row) => row.homeId.equals(homeId))).go();
      await (_database.delete(
        _database.recordTombstones,
      )..where((row) => row.homeId.equals(homeId))).go();
      await (_database.delete(
        _database.localMediaMetadata,
      )..where((row) => row.homeId.equals(homeId))).go();
      await (_database.delete(
        _database.localRecords,
      )..where((row) => row.homeId.equals(homeId))).go();
    });
  }
}
