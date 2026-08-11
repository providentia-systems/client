import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';
import 'package:providentia/features/inventory/infrastructure/item_master_refreshing_synchronization.dart';

const String _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const String _otherHomeId = '0198a0b1-c2d3-7e4f-8123-456789abcdee';

void main() {
  test('refreshes the verified cache after every completed sync run', () async {
    final item = InventoryItem(
      id: '0198a0b1-c2d3-7e4f-9234-56789abcdef0',
      homeId: _homeId,
      productId: '0198a0b1-c2d3-7e4f-a345-6789abcdef01',
      packId: '0198a0b1-c2d3-7e4f-9234-56789abcdef0',
      canonicalName: 'Rice',
      packSize: '2 kg',
      category: 'Grains',
    );
    final source = _Source(<InventoryItem>[item]);
    final delegate = _Synchronization(
      const SyncRunOutcome(status: SyncRunStatus.completed),
    );
    var replacements = 0;
    final synchronization = ItemMasterRefreshingSynchronization(
      delegate: delegate,
      source: source,
      replaceCache: ({required homeId, required items}) async {
        expect(homeId, _homeId);
        expect(items, same(source.items));
        replacements++;
      },
      homeId: _homeId,
    );

    expect((await synchronization.synchronize(_homeId)).completed, isTrue);
    expect((await synchronization.synchronize(_homeId)).completed, isTrue);
    expect(source.loads, 2);
    expect(replacements, 2);
  });

  test('preserves the prior cache on offline or malformed refreshes', () async {
    var replacements = 0;
    final offlineSource = _Source(const <InventoryItem>[]);
    final offline = ItemMasterRefreshingSynchronization(
      delegate: _Synchronization(
        const SyncRunOutcome(status: SyncRunStatus.offline),
      ),
      source: offlineSource,
      replaceCache: ({required homeId, required items}) async {
        replacements++;
      },
      homeId: _homeId,
    );
    expect((await offline.synchronize(_homeId)).status, SyncRunStatus.offline);
    expect(offlineSource.loads, 0);

    final malformed = ItemMasterRefreshingSynchronization(
      delegate: _Synchronization(
        const SyncRunOutcome(status: SyncRunStatus.completed),
      ),
      source: _Source.failure(const FormatException('partial page')),
      replaceCache: ({required homeId, required items}) async {
        replacements++;
      },
      homeId: _homeId,
    );
    expect((await malformed.synchronize(_homeId)).completed, isTrue);
    expect(replacements, 0);
  });

  test(
    'maps item-master authorization loss and rejects a foreign home',
    () async {
      final synchronization = ItemMasterRefreshingSynchronization(
        delegate: _Synchronization(
          const SyncRunOutcome(status: SyncRunStatus.completed),
        ),
        source: _Source.failure(
          const HomeItemMasterSourceException(
            HomeItemMasterSourceFailure.authorizationDenied,
          ),
        ),
        replaceCache: ({required homeId, required items}) async {},
        homeId: _homeId,
      );

      expect(
        (await synchronization.synchronize(_homeId)).status,
        SyncRunStatus.authorizationFailure,
      );
      await expectLater(
        synchronization.synchronize(_otherHomeId),
        throwsArgumentError,
      );
    },
  );
}

final class _Source implements HomeItemMasterSource {
  _Source(this.items) : failure = null;

  _Source.failure(this.failure) : items = const <InventoryItem>[];

  final List<InventoryItem> items;
  final Object? failure;
  int loads = 0;

  @override
  Future<List<InventoryItem>> loadAll({required String homeId}) async {
    loads++;
    if (homeId != _homeId) throw StateError('foreign home');
    final error = failure;
    if (error != null) throw error;
    return items;
  }
}

final class _Synchronization implements AppSynchronization {
  const _Synchronization(this.outcome);

  final SyncRunOutcome outcome;

  @override
  Future<ConnectivityResult> connectivity() async =>
      const ConnectivityResult.online();

  @override
  Future<SyncRunOutcome> synchronize(String homeId) async => outcome;

  @override
  Stream<SyncSummary> watchSummary({required String homeId}) =>
      Stream<SyncSummary>.value(const SyncSummary.initial());
}
