import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';
import 'package:providentia/features/shopping/presentation/shopping_workspace.dart';

void main() {
  testWidgets(
    'list and item edits, removal, and restore retain the same record',
    (tester) async {
      final repository = _MemoryLists();
      final controller = ShoppingController(
        repository: repository,
        homeId: 'home',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShoppingWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New list'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Month end');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.lists, hasLength(2));
      final listId = controller.state.list!.id;
      await tester.enterText(
        find.byKey(const Key('manual-list-input')),
        'Rice',
      );
      await tester.tap(find.byKey(const Key('manual-list-add')));
      await tester.pumpAndSettle();
      final lineId = controller.state.list!.lines.single.id;
      await tester.ensureVisible(find.byTooltip('Edit item'));
      await tester.tap(find.byTooltip('Edit item'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Brown rice');
      await tester.enterText(find.byType(TextFormField).at(1), '3.5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(controller.state.list!.lines.single.name, 'Brown rice');
      expect(controller.state.list!.lines.single.quantity, 3.5);
      await tester.ensureVisible(find.byTooltip('Remove item'));
      await tester.tap(find.byTooltip('Remove item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(controller.state.list!.activeLines, isEmpty);
      await tester.ensureVisible(find.text('Show removed items'));
      await tester.tap(find.text('Show removed items'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Restore item'));
      await tester.tap(find.byTooltip('Restore item'));
      await tester.pumpAndSettle();
      expect(controller.state.list!.activeLines.single.id, lineId);
      await tester.ensureVisible(find.text('Remove list'));
      await tester.tap(find.text('Remove list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(controller.state.list!.archived, isTrue);
      await tester.tap(find.text('Restore list'));
      await tester.pumpAndSettle();
      expect(controller.state.list!.archived, isFalse);
      expect(controller.state.list!.id, listId);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await repository.close();
    },
  );
}

final class _MemoryLists
    implements ShoppingRepository, ShoppingListLifecycleRepository {
  final _updates = StreamController<List<ShoppingList>>.broadcast(sync: true);
  final _lists = <ShoppingList>[
    ShoppingList(
      id: 'initial',
      homeId: 'home',
      name: 'Weekly shop',
      createdAt: DateTime.utc(2026),
    ),
  ];

  @override
  Stream<List<ShoppingList>> watchLists({required String homeId}) async* {
    yield List<ShoppingList>.of(_lists);
    yield* _updates.stream;
  }

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) =>
      watchLists(homeId: homeId).map((lists) => lists.first);

  @override
  Future<void> saveList(ShoppingList list) async {
    final index = _lists.indexWhere((entry) => entry.id == list.id);
    if (index < 0) {
      _lists.add(list);
    } else {
      _lists[index] = list;
    }
    _updates.add(List<ShoppingList>.of(_lists));
  }

  @override
  Future<void> recordFeedback(SuggestionFeedback feedback) async {}

  Future<void> close() => _updates.close();
}
