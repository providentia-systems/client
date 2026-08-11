import 'package:providentia/core/synchronization/sync_models.dart';

final class SyncConflictAccess {
  const SyncConflictAccess({required this.mayReview, required this.mayResolve});

  static const denied = SyncConflictAccess(mayReview: false, mayResolve: false);

  final bool mayReview;
  final bool mayResolve;
}

typedef SyncConflictAccessResolver = SyncConflictAccess Function(String homeId);

/// Conflict review is permanently bound to one active home.
abstract interface class SyncConflictRepository {
  String get homeId;

  SyncConflictAccess get access;

  Stream<List<SyncConflict>> watchUnresolved();

  Future<List<SyncConflict>> unresolved();

  Future<void> acceptRemote(String conflictId);

  Future<void> reapplyLocal(String conflictId);

  Future<void> reconcileCount(String conflictId);

  bool canResolve(SyncConflict conflict);
}
