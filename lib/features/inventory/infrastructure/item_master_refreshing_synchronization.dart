import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';
import 'package:providentia/features/inventory/infrastructure/generated_published_category_source.dart';

typedef HomeItemMasterCacheWriter =
    Future<void> Function({
      required String homeId,
      required List<InventoryItem> items,
      List<PublishedInventoryCategory>? categories,
    });

/// Refreshes the complete item-master cache after each successful household
/// synchronization run.
///
/// Fetch failures and malformed partial pages preserve the last verified
/// cache. Authentication and authorization failures remain visible to the
/// application so revoked-home handling can stop synchronization and purge
/// every home-scoped record, including this cache.
final class ItemMasterRefreshingSynchronization implements AppSynchronization {
  const ItemMasterRefreshingSynchronization({
    required AppSynchronization delegate,
    required HomeItemMasterSource source,
    required HomeItemMasterCacheWriter replaceCache,
    required String homeId,
    PublishedCategorySource? categorySource,
  }) : this._(delegate, source, replaceCache, homeId, categorySource);

  const ItemMasterRefreshingSynchronization._(
    this._delegate,
    this._source,
    this._replaceCache,
    this._homeId,
    this._categorySource,
  );

  final AppSynchronization _delegate;
  final HomeItemMasterSource _source;
  final PublishedCategorySource? _categorySource;
  final HomeItemMasterCacheWriter _replaceCache;
  final String _homeId;

  @override
  Future<ConnectivityResult> connectivity() => _delegate.connectivity();

  @override
  Future<SyncRunOutcome> synchronize(String homeId) async {
    _requireBoundHome(homeId);
    final outcome = await _delegate.synchronize(homeId);
    if (!outcome.completed && !outcome.pullCompleted) return outcome;

    late final List<InventoryItem> items;
    List<PublishedInventoryCategory>? categories;
    try {
      items = await _source.loadAll(homeId: homeId);
      categories = await _categorySource?.loadAll();
    } on HomeItemMasterSourceException catch (error) {
      return switch (error.failure) {
        HomeItemMasterSourceFailure.authenticationRequired =>
          const SyncRunOutcome(
            status: SyncRunStatus.authenticationRequired,
            safeMessage: 'Sign in again before refreshing the item master.',
          ),
        HomeItemMasterSourceFailure.authorizationDenied => const SyncRunOutcome(
          status: SyncRunStatus.authorizationFailure,
          safeMessage: 'Access to this home changed. Synchronization stopped.',
        ),
        HomeItemMasterSourceFailure.unavailable => _staleCatalog(outcome),
      };
    } on FormatException {
      return _staleCatalog(outcome);
    } on Exception {
      return _staleCatalog(outcome);
    }

    // Keep storage failures visible. Reporting a successful refresh after a
    // failed transaction would make the offline cache guarantee untruthful.
    await _replaceCache(homeId: homeId, items: items, categories: categories);
    return outcome;
  }

  @override
  Stream<SyncSummary> watchSummary({required String homeId}) {
    _requireBoundHome(homeId);
    return _delegate.watchSummary(homeId: homeId);
  }

  SyncRunOutcome _staleCatalog(SyncRunOutcome outcome) => SyncRunOutcome(
    status:
        outcome.status == SyncRunStatus.uploadsBlocked ||
            outcome.status == SyncRunStatus.uploadsPending
        ? outcome.status
        : SyncRunStatus.retryableFailure,
    acknowledgedCount: outcome.acknowledgedCount,
    pulledChangeCount: outcome.pulledChangeCount,
    pullCompleted: outcome.pullCompleted,
    remainingUploads: outcome.remainingUploads,
    safeMessage: outcome.completed
        ? 'Home changes synchronized, but the catalog could not be refreshed. The last verified catalog is shown; retry synchronization.'
        : 'The catalog could not be refreshed. Queued or blocked uploads remain unresolved; the last verified catalog is shown.',
  );

  void _requireBoundHome(String homeId) {
    if (homeId != _homeId) {
      throw ArgumentError.value(
        homeId,
        'homeId',
        'must match this isolated item-master cache',
      );
    }
  }
}
