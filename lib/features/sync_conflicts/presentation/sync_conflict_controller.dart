import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/features/sync_conflicts/application/sync_conflict_repository.dart';

enum SyncConflictReviewStatus {
  idle,
  loading,
  ready,
  resolving,
  accessDenied,
  failed,
}

final class SyncConflictController extends ChangeNotifier {
  SyncConflictController({required SyncConflictRepository repository})
    : this._(repository);

  SyncConflictController._(this._repository);

  final SyncConflictRepository _repository;
  StreamSubscription<List<SyncConflict>>? _subscription;
  List<SyncConflict> _conflicts = const <SyncConflict>[];
  SyncConflictReviewStatus _status = SyncConflictReviewStatus.idle;
  String? _safeMessage;
  bool _disposed = false;

  String get homeId => _repository.homeId;
  SyncConflictAccess get access => _repository.access;
  List<SyncConflict> get conflicts => _conflicts;
  SyncConflictReviewStatus get status => _status;
  String? get safeMessage => _safeMessage;
  bool get isBusy =>
      _status == SyncConflictReviewStatus.loading ||
      _status == SyncConflictReviewStatus.resolving;

  Future<void> start() async {
    if (_disposed || _subscription != null) return;
    if (!access.mayReview) {
      _status = SyncConflictReviewStatus.accessDenied;
      _safeMessage = 'Your current home role does not allow conflict review.';
      notifyListeners();
      return;
    }
    _status = SyncConflictReviewStatus.loading;
    _safeMessage = null;
    notifyListeners();
    _subscription = _repository.watchUnresolved().listen(
      (conflicts) {
        if (_disposed) return;
        _conflicts = conflicts;
        _status = SyncConflictReviewStatus.ready;
        _safeMessage = null;
        notifyListeners();
      },
      onError: (Object error) {
        if (_disposed) return;
        _status = error is SyncConflictResolutionException
            ? SyncConflictReviewStatus.accessDenied
            : SyncConflictReviewStatus.failed;
        _safeMessage = error is SyncConflictResolutionException
            ? error.safeMessage
            : 'Conflict evidence could not be loaded safely.';
        notifyListeners();
      },
    );
  }

  bool canResolve(SyncConflict conflict) => _repository.canResolve(conflict);

  Future<bool> acceptRemote(SyncConflict conflict) =>
      _resolve(conflict, _repository.acceptRemote);

  Future<bool> reapplyLocal(SyncConflict conflict) =>
      _resolve(conflict, _repository.reapplyLocal);

  Future<bool> reconcileCount(SyncConflict conflict) =>
      _resolve(conflict, _repository.reconcileCount, countOnly: true);

  Future<bool> _resolve(
    SyncConflict conflict,
    Future<void> Function(String conflictId) action, {
    bool countOnly = false,
  }) async {
    if (_disposed || isBusy) return false;
    if (conflict.homeId != homeId ||
        !_conflicts.any((candidate) => candidate.id == conflict.id)) {
      _safeMessage = 'This conflict is not available in the current home.';
      notifyListeners();
      return false;
    }
    if (!canResolve(conflict)) {
      _safeMessage =
          'Your current home role cannot resolve this kind of conflict.';
      notifyListeners();
      return false;
    }
    if (conflict.requiresCountReconciliation != countOnly) {
      _safeMessage = countOnly
          ? 'Only count conflicts use the count reconciliation workflow.'
          : 'Count conflicts require the dedicated count reconciliation workflow.';
      notifyListeners();
      return false;
    }
    _status = SyncConflictReviewStatus.resolving;
    _safeMessage = null;
    notifyListeners();
    try {
      await action(conflict.id);
      if (!_disposed) {
        _status = SyncConflictReviewStatus.ready;
      }
      return true;
    } on SyncConflictResolutionException catch (error) {
      if (!_disposed) {
        _status = SyncConflictReviewStatus.ready;
        _safeMessage = error.safeMessage;
      }
      return false;
    } catch (_) {
      if (!_disposed) {
        _status = SyncConflictReviewStatus.failed;
        _safeMessage = 'The conflict was not changed. Try again safely.';
      }
      return false;
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
