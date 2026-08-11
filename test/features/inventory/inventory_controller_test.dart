import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/inventory/presentation/inventory_workspace.dart';

void main() {
  testWidgets('inventory controller and workspace search aliases locally', (
    tester,
  ) async {
    final repository = _InventoryRepository();
    final controller = InventoryController(
      repository: repository,
      homeId: 'home-a',
      idGenerator: () => 'intent',
      clock: () => DateTime.utc(2026, 7, 30),
    );
    await tester.pumpWidget(
      _TestApp(child: InventoryWorkspace(controller: controller)),
    );
    repository.items.add(<InventoryItem>[
      InventoryItem(
        id: 'coke',
        homeId: 'home-a',
        canonicalName: 'Coke',
        packSize: '2 L',
        category: 'Beverages',
        aliases: const <String>['Coca-Cola'],
        currentQuantity: 2,
      ),
      InventoryItem(
        id: 'tea',
        homeId: 'home-a',
        canonicalName: 'Tea Rooibos Bags',
        packSize: '80 bags',
        category: 'Tea & Coffee',
      ),
    ]);
    repository.session.add(null);
    await tester.pump();

    expect(
      find.byKey(const Key('inventory-add-private-product')),
      findsNothing,
    );
    expect(find.text('Coke'), findsOneWidget);
    expect(find.text('Tea Rooibos Bags'), findsNothing);
    await tester.tap(find.text('Item master'));
    await tester.pump();
    expect(find.text('Tea Rooibos Bags'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('inventory-search')),
      'coca cola',
    );
    await tester.pump();
    expect(find.text('Coke'), findsOneWidget);
    expect(find.text('Tea Rooibos Bags'), findsNothing);

    controller.dispose();
    await repository.close();
  });

  testWidgets(
    'writable creation capability validates private input and reports queued state',
    (tester) async {
      final repository = _CreationInventoryRepository();
      final controller = InventoryController(
        repository: repository,
        homeId: 'home-a',
      );
      await tester.pumpWidget(
        _TestApp(child: InventoryWorkspace(controller: controller)),
      );
      repository.items.add(const <InventoryItem>[]);
      repository.session.add(null);
      await tester.pump();

      await tester.tap(find.byKey(const Key('inventory-add-private-product')));
      await tester.pumpAndSettle();
      expect(find.text('Add private product'), findsOneWidget);
      expect(
        find.text('This name and pack text stay private to the active home.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('inventory-save-private-product')));
      await tester.pump();
      expect(
        find.byKey(const Key('inventory-private-product-validation')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('inventory-private-product-name')),
        'Family spice mix',
      );
      await tester.enterText(
        find.byKey(const Key('inventory-private-product-pack')),
        '250 g jar',
      );
      await tester.tap(find.byKey(const Key('inventory-save-private-product')));
      await tester.pumpAndSettle();

      expect(repository.drafts, hasLength(1));
      expect(repository.drafts.single.homeId, 'home-a');
      expect(repository.drafts.single.privateName, 'Family spice mix');
      expect(repository.drafts.single.originalPackText, '250 g jar');
      expect(
        find.text(
          'The private product is saved locally and queued; server confirmation is pending.',
        ),
        findsOneWidget,
      );
      expect(find.text('The private product is synchronized.'), findsNothing);

      controller.dispose();
      await repository.close();
    },
  );

  test(
    'controller fails closed when creation capability is unavailable',
    () async {
      final repository = _InventoryRepository();
      final controller = InventoryController(
        repository: repository,
        homeId: 'home-a',
      );

      expect(
        await controller.createPrivateProduct(privateName: 'Hidden item'),
        isFalse,
      );
      expect(
        controller.state.productCreationError,
        'Private product creation is unavailable in this workspace.',
      );

      controller.dispose();
      await repository.close();
    },
  );

  testWidgets('an uncounted catalog pack can be added to the active home', (
    tester,
  ) async {
    final repository = _CreationInventoryRepository();
    final controller = InventoryController(
      repository: repository,
      homeId: 'home-a',
    );
    await tester.pumpWidget(
      _TestApp(child: InventoryWorkspace(controller: controller)),
    );
    repository.items.add(<InventoryItem>[
      InventoryItem(
        id: 'pack-a',
        homeId: 'home-a',
        productId: 'product-a',
        packId: 'pack-a',
        canonicalName: 'Long-grain rice',
        packSize: '2 kg',
        category: 'Grains',
        brand: 'Harvest Foods',
        aliases: const <String>['Rice long grain'],
      ),
    ]);
    repository.session.add(null);
    await tester.pump();
    await tester.tap(find.text('Item master'));
    await tester.pump();

    expect(
      find.text('2 kg · Harvest Foods · Grains · Aliases: Rice long grain'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('inventory-add-catalog-pack-a')));
    await tester.pump();

    expect(repository.catalogDrafts, hasLength(1));
    expect(repository.catalogDrafts.single.homeId, 'home-a');
    expect(repository.catalogDrafts.single.productId, 'product-a');
    expect(repository.catalogDrafts.single.packId, 'pack-a');
    expect(
      find.text(
        'The catalog product is added locally and queued; server confirmation is pending.',
      ),
      findsOneWidget,
    );

    controller.dispose();
    await repository.close();
  });

  test(
    'failed creation never reports a successful or queued outcome',
    () async {
      final repository = _FailingCreationInventoryRepository();
      final controller = InventoryController(
        repository: repository,
        homeId: 'home-a',
      );

      expect(
        await controller.createPrivateProduct(privateName: 'Hidden item'),
        isFalse,
      );
      expect(controller.state.productCreationNotice, isNull);
      expect(
        controller.state.productCreationError,
        'The private product could not be queued.',
      );

      controller.dispose();
      await repository.close();
    },
  );

  test('manual adjustment delegates immutable intent and movement', () async {
    final repository = _InventoryRepository();
    final controller = InventoryController(
      repository: repository,
      homeId: 'home-a',
      idGenerator: () => 'adjustment-1',
      clock: () => DateTime.utc(2026, 7, 30),
    );
    final item = InventoryItem(
      id: 'rice',
      homeId: 'home-a',
      canonicalName: 'Rice Basmati',
      packSize: '5 kg',
      category: 'Dry Goods',
      currentQuantity: 10,
    );
    await controller.adjustQuantity(
      item: item,
      locationId: 'pantry',
      observedQuantity: 8,
      reason: 'Physical recount',
    );
    expect(repository.savedIntent!.id, 'adjustment-1');
    expect(repository.savedMovement!.quantityDelta, -2);
    expect(repository.savedMovement!.homeId, 'home-a');
    controller.dispose();
    await repository.close();
  });
}

class _InventoryRepository implements InventoryRepository {
  final items = StreamController<List<InventoryItem>>.broadcast();
  final session = StreamController<StockCountSession?>.broadcast();
  ManualAdjustmentIntent? savedIntent;
  StockMovement? savedMovement;

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
      items.stream;

  @override
  Stream<StockCountSession?> watchActiveCountSession({
    required String homeId,
  }) => session.stream;

  @override
  Future<void> saveCountSession(StockCountSession session) async {}

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) async {
    savedIntent = intent;
    savedMovement = movement;
  }

  Future<void> close() async {
    await items.close();
    await session.close();
  }
}

final class _CreationInventoryRepository extends _InventoryRepository
    implements InventoryProductCreationRepository {
  final List<PrivateHomeProductDraft> drafts = <PrivateHomeProductDraft>[];
  final List<CatalogHomeProductDraft> catalogDrafts =
      <CatalogHomeProductDraft>[];

  @override
  bool get supportsPrivateHomeProductCreation => true;

  @override
  bool get supportsCatalogHomeProductCreation => true;

  @override
  Future<InventoryProductCreationResult> createPrivateHomeProduct(
    PrivateHomeProductDraft draft,
  ) async {
    drafts.add(draft);
    return const InventoryProductCreationResult(
      homeProductId: 'private-product-a',
      revision: 1,
      disposition: InventoryProductCreationDisposition.queued,
    );
  }

  @override
  Future<InventoryProductCreationResult> createCatalogHomeProduct(
    CatalogHomeProductDraft draft,
  ) async {
    catalogDrafts.add(draft);
    return const InventoryProductCreationResult(
      homeProductId: 'catalog-product-a',
      revision: 1,
      disposition: InventoryProductCreationDisposition.queued,
    );
  }
}

final class _FailingCreationInventoryRepository extends _InventoryRepository
    implements InventoryProductCreationRepository {
  @override
  bool get supportsPrivateHomeProductCreation => true;

  @override
  bool get supportsCatalogHomeProductCreation => true;

  @override
  Future<InventoryProductCreationResult> createPrivateHomeProduct(
    PrivateHomeProductDraft draft,
  ) {
    throw const InventoryProductCreationException(
      'The private product could not be queued.',
    );
  }

  @override
  Future<InventoryProductCreationResult> createCatalogHomeProduct(
    CatalogHomeProductDraft draft,
  ) {
    throw const InventoryProductCreationException(
      'The catalog product could not be queued.',
    );
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: child));
}
