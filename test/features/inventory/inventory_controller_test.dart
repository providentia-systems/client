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

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: Scaffold(body: child));
}
