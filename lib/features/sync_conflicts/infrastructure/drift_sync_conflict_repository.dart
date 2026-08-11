import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/sync_conflicts/application/sync_conflict_repository.dart';

/// Authorization-checked, active-home facade over the atomic Drift store.
final class DriftSyncConflictRepository implements SyncConflictRepository {
  DriftSyncConflictRepository({
    required LocalSyncConflictStore conflictStore,
    required this.homeId,
    required SyncConflictAccessResolver accessResolver,
    bool Function(SyncConflict conflict)? resolutionAuthorization,
    DateTime Function()? clock,
    String Function()? operationIdGenerator,
  }) : _store = conflictStore,
       _access = accessResolver,
       _resolutionAuthorization = resolutionAuthorization ?? ((_) => true),
       _clock = clock ?? DateTime.now,
       _operationIdGenerator = operationIdGenerator ?? UuidV4Generator().call {
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
  }

  final LocalSyncConflictStore _store;
  final SyncConflictAccessResolver _access;
  final bool Function(SyncConflict conflict) _resolutionAuthorization;
  final DateTime Function() _clock;
  final String Function() _operationIdGenerator;

  @override
  final String homeId;

  @override
  SyncConflictAccess get access => _access(homeId);

  @override
  Stream<List<SyncConflict>> watchUnresolved() {
    if (!access.mayReview) {
      return Stream<List<SyncConflict>>.error(
        const SyncConflictResolutionException(
          'Your current home role does not allow conflict review.',
        ),
      );
    }
    return _store.watchUnresolvedConflicts(homeId: homeId);
  }

  @override
  Future<List<SyncConflict>> unresolved() async {
    _requireReview();
    return _store.unresolvedConflicts(homeId: homeId);
  }

  @override
  Future<void> acceptRemote(String conflictId) {
    return _withAuthorizedConflict(conflictId, (conflict) {
      if (conflict.requiresCountReconciliation) {
        throw const SyncConflictResolutionException(
          'Count conflicts require the dedicated count reconciliation workflow.',
        );
      }
      if (!conflict.canAcceptRemote) {
        throw const SyncConflictResolutionException(
          'The server version is not ready for this decision.',
        );
      }
      return _store.acceptRemoteConflict(
        homeId: homeId,
        conflictId: conflictId,
        resolvedAt: _clock().toUtc(),
      );
    });
  }

  @override
  Future<void> reapplyLocal(String conflictId) {
    return _withAuthorizedConflict(conflictId, (conflict) {
      if (conflict.requiresCountReconciliation) {
        throw const SyncConflictResolutionException(
          'Count conflicts require the dedicated count reconciliation workflow.',
        );
      }
      if (!conflict.canReapplyLocal) {
        throw const SyncConflictResolutionException(
          'The server revision is not ready for this decision.',
        );
      }
      return _store.reapplyLocalConflict(
        homeId: homeId,
        conflictId: conflictId,
        newOperationId: _operationIdGenerator(),
        resolvedAt: _clock().toUtc(),
      );
    });
  }

  @override
  Future<void> reconcileCount(String conflictId) {
    return _withAuthorizedConflict(conflictId, (conflict) {
      if (!conflict.requiresCountReconciliation ||
          conflict.remote.revision == null ||
          conflict.remote.kind == SyncConflictRemoteKind.unavailable) {
        throw const SyncConflictResolutionException(
          'The server count is not ready for reconciliation.',
        );
      }
      return _store.reconcileCountConflict(
        homeId: homeId,
        conflictId: conflictId,
        resolvedAt: _clock().toUtc(),
      );
    });
  }

  @override
  bool canResolve(SyncConflict conflict) =>
      conflict.homeId == homeId &&
      access.mayResolve &&
      _resolutionAuthorization(conflict);

  Future<void> _withAuthorizedConflict(
    String conflictId,
    Future<void> Function(SyncConflict conflict) action,
  ) async {
    _requireResolution();
    final conflicts = await _store.unresolvedConflicts(homeId: homeId);
    SyncConflict? selected;
    for (final conflict in conflicts) {
      if (conflict.id == conflictId) {
        selected = conflict;
        break;
      }
    }
    if (selected == null) {
      throw const SyncConflictResolutionException(
        'This conflict is not available in the current home.',
      );
    }
    if (!_resolutionAuthorization(selected)) {
      throw const SyncConflictResolutionException(
        'Your current home role cannot resolve this kind of conflict.',
      );
    }
    await action(selected);
  }

  void _requireReview() {
    if (!access.mayReview) {
      throw const SyncConflictResolutionException(
        'Your current home role does not allow conflict review.',
      );
    }
  }

  void _requireResolution() {
    final current = access;
    if (!current.mayReview || !current.mayResolve) {
      throw const SyncConflictResolutionException(
        'Your current home role does not allow conflict resolution.',
      );
    }
  }
}
