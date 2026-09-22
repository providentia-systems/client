import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';
import 'package:providentia/features/inventory/infrastructure/generated_published_category_source.dart';
import 'package:providentia/features/inventory/infrastructure/item_master_refreshing_synchronization.dart';

void main() {
  for (final status in [
    SyncRunStatus.completed,
    SyncRunStatus.uploadsPending,
    SyncRunStatus.uploadsBlocked,
  ]) {
    test(
      'category refresh failure preserves $status upload evidence and prior caches',
      () async {
        final delegate = _Sync(
          SyncRunOutcome(
            status: status,
            pullCompleted: true,
            remainingUploads: status == SyncRunStatus.completed ? 0 : 2,
            acknowledgedCount: 1,
            pulledChangeCount: 3,
          ),
        );
        var writes = 0;
        final sync = ItemMasterRefreshingSynchronization(
          delegate: delegate,
          homeId: 'home',
          source: const _Items(),
          categorySource: const _Categories(fail: true),
          replaceCache: ({required homeId, required items, categories}) async {
            writes++;
          },
        );
        final outcome = await sync.synchronize('home');
        expect(writes, 0);
        expect(
          outcome.status,
          status == SyncRunStatus.completed
              ? SyncRunStatus.retryableFailure
              : status,
        );
        expect(outcome.completed, isFalse);
        expect(outcome.pullCompleted, isTrue);
        expect(outcome.remainingUploads, delegate.outcome.remainingUploads);
        expect(outcome.acknowledgedCount, 1);
        expect(outcome.pulledChangeCount, 3);
        if (status != SyncRunStatus.completed) {
          expect(
            outcome.safeMessage,
            isNot(contains('Home changes synchronized')),
          );
        }
      },
    );
  }
  test(
    'complete published category snapshot reaches the atomic cache writer with item master',
    () async {
      var writes = 0;
      final sync = ItemMasterRefreshingSynchronization(
        delegate: const _Sync(SyncRunOutcome(status: SyncRunStatus.completed)),
        homeId: 'home',
        source: const _Items(),
        categorySource: const _Categories(),
        replaceCache: ({required homeId, required items, categories}) async {
          expect(homeId, 'home');
          expect(items, isEmpty);
          expect(categories!.single.name, 'Produce');
          writes++;
        },
      );
      expect((await sync.synchronize('home')).completed, isTrue);
      expect(writes, 1);
    },
  );
}

final class _Items implements HomeItemMasterSource {
  const _Items();
  @override
  Future<List<InventoryItem>> loadAll({required String homeId}) async => [];
}

final class _Categories implements PublishedCategorySource {
  const _Categories({this.fail = false});
  final bool fail;
  @override
  Future<List<PublishedInventoryCategory>> loadAll() async {
    if (fail) throw const FormatException('Interrupted category snapshot');
    return [
      PublishedInventoryCategory(id: 'global', name: 'Produce', revision: 1),
    ];
  }
}

final class _Sync implements AppSynchronization {
  const _Sync(this.outcome);
  final SyncRunOutcome outcome;
  @override
  Future<SyncRunOutcome> synchronize(String homeId) async => outcome;
  @override
  Stream<SyncSummary> watchSummary({required String homeId}) =>
      const Stream.empty();
  @override
  Future<ConnectivityResult> connectivity() async =>
      const ConnectivityResult.online();
}
