import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/app/household_features.dart';
import 'package:providentia/app/providentia_app.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';

void main() {
  testWidgets('home policy gates every household command surface fail closed', (
    tester,
  ) async {
    final viewerFixture = _FeatureFixture();
    final viewerApp = AppController.preview();
    await tester.pumpWidget(
      ProvidentiaApp(
        controller: viewerApp,
        features: viewerFixture.features,
        access: const HouseholdWorkspaceAccess(
          inventoryRead: true,
          inventoryWrite: false,
          purchasesRead: true,
          purchasesWrite: false,
          shoppingRead: true,
          shoppingWrite: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    viewerApp.selectSection(AppSection.stock);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('read-only-inventory-workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('start-stock-count')), findsNothing);

    viewerApp.selectSection(AppSection.purchases);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('read-only-purchasing-workspace')),
      findsOneWidget,
    );

    viewerApp.selectSection(AppSection.lists);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('read-only-shopping-workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('manual-list-add')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final deniedFixture = _FeatureFixture();
    final deniedApp = AppController.preview();
    await tester.pumpWidget(
      ProvidentiaApp(controller: deniedApp, features: deniedFixture.features),
    );
    await tester.pumpAndSettle();

    expect(deniedFixture.inventory.watchCalls, 0);
    expect(deniedFixture.purchases.watchCalls, 0);
    expect(deniedFixture.shopping.watchCalls, 0);

    deniedApp.selectSection(AppSection.stock);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('household-access-denied')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    final writerFixture = _FeatureFixture();
    final writerApp = AppController.preview();
    await tester.pumpWidget(
      ProvidentiaApp(
        controller: writerApp,
        features: writerFixture.features,
        access: const HouseholdWorkspaceAccess(
          inventoryRead: true,
          inventoryWrite: true,
          purchasesRead: true,
          purchasesWrite: true,
          shoppingRead: true,
          shoppingWrite: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    writerApp.selectSection(AppSection.stock);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('start-stock-count')), findsOneWidget);

    writerApp.selectSection(AppSection.lists);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manual-list-add')), findsOneWidget);
  });
}

const String _homeId = 'home-a';

final class _FeatureFixture {
  _FeatureFixture()
    : inventory = _InventoryRepository(),
      purchases = _PurchaseRepository(),
      shopping = _ShoppingRepository() {
    features = HouseholdFeatures(
      inventory: InventoryController(repository: inventory, homeId: _homeId),
      purchasing: PurchasingController(repository: purchases, homeId: _homeId),
      shopping: ShoppingController(repository: shopping, homeId: _homeId),
    );
  }

  final _InventoryRepository inventory;
  final _PurchaseRepository purchases;
  final _ShoppingRepository shopping;
  late final HouseholdFeatures features;
}

final class _InventoryRepository implements InventoryRepository {
  int watchCalls = 0;

  @override
  Stream<StockCountSession?> watchActiveCountSession({required String homeId}) {
    watchCalls++;
    return Stream<StockCountSession?>.value(null);
  }

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) {
    watchCalls++;
    return Stream<List<InventoryItem>>.value(const <InventoryItem>[]);
  }

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) async {}

  @override
  Future<void> saveCountSession(StockCountSession session) async {}
}

final class _PurchaseRepository implements PurchaseRepository {
  int watchCalls = 0;

  @override
  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  }) => Stream<List<PriceObservation>>.value(const <PriceObservation>[]);

  @override
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId}) {
    watchCalls++;
    return Stream<List<PurchaseLine>>.value(const <PurchaseLine>[]);
  }
}

final class _ShoppingRepository implements ShoppingRepository {
  int watchCalls = 0;

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) {
    watchCalls++;
    return Stream<ShoppingList>.value(
      ShoppingList(
        id: 'list-a',
        homeId: homeId,
        name: 'Shopping list',
        createdAt: DateTime.utc(2026, 8, 9),
      ),
    );
  }

  @override
  Future<void> recordFeedback(SuggestionFeedback feedback) async {}

  @override
  Future<void> saveList(ShoppingList list) async {}
}
