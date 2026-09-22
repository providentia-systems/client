import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';

/// Uses the existing private outbox and its acknowledgements before a separate,
/// consent-bound catalog submission. No new operation or public payload is made.
final class DriftCatalogProductSourcePreparation
    implements CatalogProductSourcePreparation {
  const DriftCatalogProductSourcePreparation({
    required AppDatabase database,
    required AppSynchronization synchronization,
    required String homeId,
  }) : this._(database, synchronization, homeId);

  const DriftCatalogProductSourcePreparation._(
    this._database,
    this._synchronization,
    this._homeId,
  );

  final AppDatabase _database;
  final AppSynchronization _synchronization;
  final String _homeId;

  @override
  Future<void> prepare({
    required String homeId,
    required String homeProductId,
  }) async {
    if (homeId != _homeId) {
      throw const CatalogContributionForbiddenException();
    }
    if (await _isAcknowledged(homeProductId)) return;
    final outcome = await _synchronization.synchronize(homeId);
    switch (outcome.status) {
      case SyncRunStatus.authenticationRequired:
        throw const CatalogContributionAuthenticationRequiredException();
      case SyncRunStatus.authorizationFailure:
        throw const CatalogContributionForbiddenException();
      case SyncRunStatus.uploadsBlocked:
      case SyncRunStatus.uploadsPending:
      case SyncRunStatus.completed:
      case SyncRunStatus.alreadyRunning:
      case SyncRunStatus.offline:
      case SyncRunStatus.retryableFailure:
        // Other sources may still be blocked, and a catalog refresh
        // failure may follow a successful source acknowledgement. Read the
        // selected source's evidence instead of trusting the run's label.
        if (!await _isAcknowledged(homeProductId)) {
          throw const CatalogContributionSourcePendingException();
        }
    }
  }

  Future<bool> _isAcknowledged(String homeProductId) =>
      _database.transaction(() async {
        final record =
            await (_database.select(_database.localRecords)..where(
                  (row) =>
                      row.homeId.equals(_homeId) &
                      row.entityType.equals('inventory-home-product') &
                      row.entityId.equals(homeProductId),
                ))
                .getSingleOrNull();
        if (record == null || record.isTombstone) {
          throw const CatalogContributionSourceUnavailableException();
        }
        final payload = jsonDecode(record.payload);
        if (payload is! Map<String, Object?> || payload['status'] != 'active') {
          throw const CatalogContributionSourceUnavailableException();
        }
        if (record.revision < 1 || record.synchronizedAt == null) return false;
        final unresolved =
            await (_database.select(_database.clientOperations)
                  ..where(
                    (row) =>
                        row.homeId.equals(_homeId) &
                        row.entityType.equals('inventory-home-product') &
                        row.entityId.equals(homeProductId) &
                        row.state.isNotIn(<String>[
                          ClientOperationState.acknowledged.storageValue,
                          ClientOperationState.superseded.storageValue,
                        ]),
                  )
                  ..limit(1))
                .get();
        return unresolved.isEmpty;
      });
}
