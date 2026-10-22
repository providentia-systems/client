import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';
import 'package:providentia/features/shopping/presentation/shopping_workspace.dart';

void main() {
  testWidgets('offline alias lookup selects a zero-stock household product', (
    tester,
  ) async {
    final repository = _Repository();
    final controller = _controller(repository);
    await _show(tester, controller);
    await tester.tap(find.byKey(const Key('manual-list-input')));
    await tester.enterText(
      find.byKey(const Key('manual-list-input')),
      'basmati',
    );
    await tester.pumpAndSettle();
    expect(find.text('Rice · Tastic · 1 kg (kg)'), findsWidgets);
    await tester.tap(find.text('Rice · Tastic · 1 kg (kg)').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shopping-selected-product')), findsOneWidget);
    await tester.tap(find.byKey(const Key('manual-list-add')));
    await tester.pumpAndSettle();
    final line = controller.state.list!.lines.single;
    expect(line.homeProductId, 'rice');
    expect(line.name, 'Rice');
    expect(line.origin, ShoppingLineOrigin.manual);
    expect(line.suggestionId, isNull);
    expect(line.quantity, 1);
    expect(repository.items.first.currentQuantity, 0);
    await _close(tester, controller, repository);
  });

  testWidgets('edited product text becomes an explicit unlinked custom item', (
    tester,
  ) async {
    final repository = _Repository();
    final controller = _controller(repository);
    await _show(tester, controller);
    await tester.tap(find.byKey(const Key('manual-list-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rice · Tastic · 1 kg (kg)').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manual-list-input')),
      'fruit for visitors',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shopping-selected-product')), findsNothing);
    await tester.tap(find.byKey(const Key('shopping-add-custom')));
    await tester.pumpAndSettle();
    expect(controller.state.list!.lines.single.homeProductId, isNull);
    expect(controller.state.list!.lines.single.name, 'fruit for visitors');
    expect(repository.items, hasLength(2));
    await _close(tester, controller, repository);
  });

  testWidgets(
    'duplicate prompt can adjust or intentionally keep a separate line',
    (tester) async {
      final repository = _Repository();
      final controller = _controller(repository);
      await _show(tester, controller);
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.tap(find.byKey(const Key('manual-list-input')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rice · Tastic · 1 kg (kg)').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('manual-list-add')));
        await tester.pumpAndSettle();
        if (attempt > 0) {
          expect(find.text('Product already on this list'), findsOneWidget);
          await tester.tap(
            find.text(
              attempt == 1 ? 'Add to existing quantity' : 'Keep separate line',
            ),
          );
          await tester.pumpAndSettle();
        }
      }
      expect(controller.state.list!.lines, hasLength(2));
      expect(controller.state.list!.lines.first.quantity, 2);
      expect(controller.state.list!.lines.last.quantity, 1);
      await _close(tester, controller, repository);
    },
  );

  testWidgets('failed save and invalid empty quantity retain the entry', (
    tester,
  ) async {
    final repository = _Repository()..failSave = true;
    final controller = _controller(repository);
    await _show(tester, controller);
    await tester.enterText(find.byKey(const Key('manual-list-input')), 'Milk');
    await tester.enterText(
      find.byKey(const Key('manual-list-quantity')),
      '2.75',
    );
    await tester.tap(find.byKey(const Key('manual-list-add')));
    await tester.pumpAndSettle();
    expect(controller.state.list!.lines, isEmpty);
    expect(find.textContaining('Your entry is retained'), findsOneWidget);
    final quantity = tester.widget<TextFormField>(
      find.descendant(
        of: find.byKey(const Key('manual-list-quantity')),
        matching: find.byType(TextFormField),
      ),
    );
    expect(quantity.controller!.text, '2.75');
    await tester.enterText(find.byKey(const Key('manual-list-quantity')), '');
    await tester.tap(find.byKey(const Key('manual-list-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shopping-entry-error')), findsOneWidget);
    expect(controller.state.list!.lines, isEmpty);
    repository.failSave = false;
    await tester.enterText(
      find.byKey(const Key('manual-list-quantity')),
      '2.75',
    );
    await tester.tap(find.byKey(const Key('manual-list-add')));
    await tester.pumpAndSettle();
    expect(controller.state.list!.lines.single.quantity, 2.75);
    expect(quantity.controller!.text, '1');
    await _close(tester, controller, repository);
  });

  test(
    'item-master isolation rejects foreign rows and stale selections',
    () async {
      final repository = _Repository();
      final controller = _controller(repository)..start();
      await Future<void>.delayed(Duration.zero);
      repository.itemUpdates.add([_item('foreign', homeId: 'other')]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.items, isEmpty);
      expect(controller.state.safeError, contains('rejected'));
      expect(
        await controller.addManual('Rice', homeProductId: 'rice'),
        isFalse,
      );
      expect(repository.current.lines, isEmpty);
      controller.dispose();
      await repository.close();
    },
  );

  test(
    'duplicates in an old list do not block the selected new list',
    () async {
      final repository = _Repository();
      repository.other = _list('old').add(
        ShoppingListLine(
          id: 'old-rice',
          homeId: 'home',
          name: 'Rice',
          quantity: 2,
          origin: ShoppingLineOrigin.manual,
          createdAt: DateTime.utc(2026),
          homeProductId: 'rice',
        ),
      );
      final controller = _controller(repository)..start();
      await Future<void>.delayed(Duration.zero);
      expect(controller.duplicateForProduct('rice'), isNull);
      expect(await controller.addManual('Rice', homeProductId: 'rice'), isTrue);
      controller.dispose();
      await repository.close();
    },
  );
}

ShoppingController _controller(_Repository repository) {
  var sequence = 0;
  return ShoppingController(
    repository: repository,
    itemMasterRepository: repository,
    homeId: 'home',
    idGenerator: () => 'line-${++sequence}',
  );
}

Future<void> _show(WidgetTester tester, ShoppingController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ShoppingWorkspace(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _close(
  WidgetTester tester,
  ShoppingController controller,
  _Repository repository,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await repository.close();
}

InventoryItem _item(String id, {String homeId = 'home'}) => InventoryItem(
  id: id,
  homeId: homeId,
  canonicalName: id == 'rice' ? 'Rice' : 'Milk',
  packSize: id == 'rice' ? '1 kg' : '1 l',
  brand: id == 'rice' ? 'Tastic' : 'NamMilk',
  aliases: id == 'rice' ? ['basmati'] : [],
  category: 'Groceries',
  unit: id == 'rice' ? 'kg' : 'l',
  currentQuantity: 0,
  isHomeProduct: true,
);

ShoppingList _list(String id) => ShoppingList(
  id: id,
  homeId: 'home',
  name: id,
  createdAt: DateTime.utc(2026),
);

class _Repository
    implements
        ShoppingRepository,
        ShoppingListLifecycleRepository,
        InventoryRepository {
  ShoppingList current = _list('new');
  ShoppingList? other;
  bool failSave = false;
  final items = [_item('rice'), _item('milk')];
  final itemUpdates = StreamController<List<InventoryItem>>.broadcast(
    sync: true,
  );
  final updates = StreamController<List<ShoppingList>>.broadcast(sync: true);

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) async* {
    yield List.of(items);
    yield* itemUpdates.stream;
  }

  @override
  Stream<List<ShoppingList>> watchLists({required String homeId}) async* {
    yield [current, ?other];
    yield* updates.stream;
  }

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) async* {
    yield current;
    yield* updates.stream.map((lists) => lists.first);
  }

  @override
  Future<void> saveList(ShoppingList list) async {
    if (failSave) throw StateError('Save failed');
    current = list;
    updates.add([current, ?other]);
  }

  @override
  Future<void> recordFeedback(SuggestionFeedback feedback) async {}
  @override
  Stream<StockCountSession?> watchActiveCountSession({
    required String homeId,
  }) => const Stream.empty();
  @override
  Future<void> saveCountSession(StockCountSession session) async =>
      throw UnimplementedError();
  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) async => throw UnimplementedError();
  Future<void> close() async {
    await itemUpdates.close();
    await updates.close();
  }
}
