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
  testWidgets(
    'independent published pack and instructions are distinct from stock',
    (tester) async {
      final repository = _Repository();
      repository.items.clear();
      repository.items.addAll([
        InventoryItem(
          id: 'rice',
          homeId: 'home',
          canonicalName: 'Rice',
          packSize: '1 kg',
          category: 'Groceries',
          unit: 'kg',
          isHomeProduct: true,
          productId: 'family',
          packId: 'base',
          normalizedBaseAmount: '1000',
          normalizedBaseUnit: 'g',
          packStatus: 'published',
        ),
        InventoryItem(
          id: 'small',
          homeId: 'home',
          canonicalName: 'Rice',
          packSize: '500 g',
          category: 'Groceries',
          productId: 'family',
          packId: 'small',
          normalizedBaseAmount: '500',
          normalizedBaseUnit: 'g',
          packStatus: 'published',
        ),
        InventoryItem(
          id: 'bad',
          homeId: 'home',
          canonicalName: 'Rice',
          packSize: '1 l',
          category: 'Groceries',
          productId: 'family',
          packId: 'bad',
          normalizedBaseAmount: '1000',
          normalizedBaseUnit: 'ml',
          packStatus: 'published',
        ),
      ]);
      final controller = _controller(repository);
      await _show(tester, controller);
      expect(controller.packChoices('rice').map((pack) => pack.id), [
        'base',
        'small',
      ]);
      await tester.tap(find.byKey(const Key('manual-list-input')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rice · 1 kg (kg)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shopping-manual-pack-rice')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Packs: 500 g').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('shopping-manual-instructions')),
        'Sealed bags only',
      );
      await tester.enterText(
        find.byKey(const Key('manual-list-quantity')),
        '2',
      );
      await tester.tap(find.byKey(const Key('manual-list-add')));
      await tester.pumpAndSettle();
      final line = controller.state.list!.lines.single;
      expect(line.selectedPackId, 'small');
      expect(line.quantityBasis, 'pack-count');
      expect(line.name, 'Sealed bags only');
      expect(line.quantity, 2);
      expect(line.stockUnit, 'kg');
      await _close(tester, controller, repository);
    },
  );

  testWidgets(
    'failed explicit relink retains typed selection and original revision',
    (tester) async {
      final repository = _Repository()..failSave = true;
      repository.current = _list('new').copyWith(
        lines: [
          ShoppingListLine(
            id: 'existing',
            homeId: 'home',
            name: 'For visitors',
            quantity: 3,
            origin: ShoppingLineOrigin.manual,
            createdAt: DateTime.utc(2026),
            homeProductId: 'rice',
            revision: 7,
          ),
        ],
      );
      final controller = _controller(repository);
      await _show(tester, controller);
      await tester.ensureVisible(
        find.byKey(const Key('relink-shopping-line-existing')),
      );
      await tester.tap(find.byKey(const Key('relink-shopping-line-existing')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shopping-relink-product')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milk · 1 l').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('shopping-relink-reason')),
        'Buy milk instead',
      );
      await tester.tap(find.byKey(const Key('shopping-relink-save')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('selection is retained'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('shopping-relink-reason')))
            .controller!
            .text,
        'Buy milk instead',
      );
      expect(repository.lastRelinkRevision, 7);
      expect(repository.lastRelinkProduct, 'milk');
      expect(controller.state.list!.lines.single.homeProductId, 'rice');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await _close(tester, controller, repository);
    },
  );

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

  testWidgets('a late save from the previous home cannot clear the new draft', (
    tester,
  ) async {
    final previous = _Repository();
    final oldController = _controller(previous);
    await _show(tester, oldController);
    previous.saveGate = Completer<void>();
    await tester.enterText(
      find.byKey(const Key('manual-list-input')),
      'Old home item',
    );
    await tester.tap(find.byKey(const Key('manual-list-add')));
    await tester.pump();
    final next = _Repository(homeId: 'other-home');
    final newController = _controller(next);
    await _show(tester, newController);
    expect(newController.manualBusy, false);
    expect(
      tester
          .widget<DropdownMenu<String>>(
            find.byKey(const Key('manual-list-input')),
          )
          .enabled,
      true,
    );
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('manual-list-input')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.readOnly, false);
    expect(
      identical(
        editable.controller,
        tester
            .widget<DropdownMenu<String>>(
              find.byKey(const Key('manual-list-input')),
            )
            .controller,
      ),
      true,
    );
    await tester.tap(find.byKey(const Key('manual-list-input')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manual-list-input')),
      'New home draft',
    );
    await tester.pump();
    expect(
      tester
          .widget<DropdownMenu<String>>(
            find.byKey(const Key('manual-list-input')),
          )
          .controller!
          .text,
      'New home draft',
      reason: 'before prior save completion',
    );
    previous.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownMenu<String>>(
            find.byKey(const Key('manual-list-input')),
          )
          .controller!
          .text,
      'New home draft',
    );
    expect(newController.state.list!.lines, isEmpty);
    expect(previous.current.lines.single.homeId, 'home');
    oldController.dispose();
    await previous.close();
    await _close(tester, newController, next);
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
    homeId: repository.homeId,
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

ShoppingList _list(String id, {String homeId = 'home'}) => ShoppingList(
  id: id,
  homeId: homeId,
  name: id,
  createdAt: DateTime.utc(2026),
);

class _Repository
    implements
        ShoppingRepository,
        ShoppingListLifecycleRepository,
        ShoppingLineRelinkRepository,
        InventoryRepository {
  _Repository({this.homeId = 'home'})
    : current = _list('new', homeId: homeId),
      items = [_item('rice', homeId: homeId), _item('milk', homeId: homeId)];

  final String homeId;
  ShoppingList current;
  Completer<void>? saveGate;
  ShoppingList? other;
  bool failSave = false;
  int? lastRelinkRevision;
  String? lastRelinkProduct;
  final List<InventoryItem> items;
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
    await saveGate?.future;
    if (failSave) throw StateError('Save failed');
    current = list;
    updates.add([current, ?other]);
  }

  @override
  Future<void> relinkShoppingLine({
    required String homeId,
    required String listId,
    required String lineId,
    required int expectedRevision,
    required String? homeProductId,
    required String? selectedPackId,
    required String reason,
  }) async {
    lastRelinkRevision = expectedRevision;
    lastRelinkProduct = homeProductId;
    if (failSave) throw StateError('Synthetic stale revision');
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
