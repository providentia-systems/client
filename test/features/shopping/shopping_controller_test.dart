import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';
import 'package:providentia/features/shopping/presentation/shopping_workspace.dart';

void main() {
  testWidgets('manual item is trimmed, saved, and check-off updates progress', (
    tester,
  ) async {
    final repository = _ShoppingRepository(_list());
    final controller = ShoppingController(
      repository: repository,
      homeId: 'home-a',
      idGenerator: () => 'manual-1',
      clock: () => DateTime.utc(2026, 7, 30),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShoppingWorkspace(controller: controller)),
      ),
    );
    repository.emit();
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('manual-list-input')),
      '  Tea  ',
    );
    await tester.tap(find.byKey(const Key('manual-list-add')));
    await tester.pump();
    expect(repository.current.lines.single.name, 'Tea');
    repository.emit();
    await tester.pump();
    expect(find.text('Tea'), findsOneWidget);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    repository.emit();
    await tester.pump();
    expect(find.text('1/1 complete'), findsOneWidget);

    controller.dispose();
    await repository.close();
  });

  test('controller rejects a repository stream from another home', () async {
    final repository = _ShoppingRepository(
      ShoppingList(
        id: 'foreign',
        homeId: 'home-b',
        name: 'Foreign',
        createdAt: DateTime.utc(2026),
      ),
    );
    final controller = ShoppingController(
      repository: repository,
      homeId: 'home-a',
    );
    controller.start();
    repository.emit();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.safeError, contains('rejected'));
    controller.dispose();
    await repository.close();
  });
}

ShoppingList _list() => ShoppingList(
  id: 'list',
  homeId: 'home-a',
  name: 'Weekly',
  createdAt: DateTime.utc(2026),
);

class _ShoppingRepository implements ShoppingRepository {
  _ShoppingRepository(this.current);

  final controller = StreamController<ShoppingList>.broadcast();
  ShoppingList current;

  void emit() => controller.add(current);

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) =>
      controller.stream;

  @override
  Future<void> saveList(ShoppingList list) async {
    current = list;
  }

  @override
  Future<void> recordFeedback(SuggestionFeedback feedback) async {}

  Future<void> close() => controller.close();
}
