import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/inventory/presentation/inventory_metadata_dialogs.dart';

void main() {
  testWidgets(
    'private product editor saves every editable field and safely exits',
    (tester) async {
      final repository = _Repository();
      final controller = InventoryController(
        repository: repository,
        homeId: 'home',
      )..start();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showInventoryProductEditor(context, controller, _product),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Product name'), 'Brown rice');
      await tester.enterText(_field('Pack and measure'), '500 g');
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();
      expect(repository.edits.single, {
        'name': 'Brown rice',
        'pack': '500 g',
        'category': null,
        'archived': false,
      });
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove product'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(repository.edits.last['archived'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removed product can be restored without exposing another remove action',
    (tester) async {
      final repository = _Repository();
      final controller = InventoryController(
        repository: repository,
        homeId: 'home',
      )..start();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showArchivedInventoryProducts(context, controller),
                child: const Text('Removed'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Removed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rice'));
      await tester.pumpAndSettle();
      expect(find.text('Remove product'), findsNothing);
      await tester.tap(find.text('Restore product'));
      await tester.pumpAndSettle();
      expect(repository.edits.single['archived'], isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category dialog validates names and retains controllers through closing',
    (tester) async {
      final repository = _Repository();
      final controller = InventoryController(
        repository: repository,
        homeId: 'home',
      )..start();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showInventoryCategories(context, controller),
                child: const Text('Categories'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a category name.'), findsOneWidget);
      await tester.enterText(_field('Category name'), 'Pantry');
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();
      expect(repository.categoryNames, ['Pantry']);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

final _product = InventoryItem(
  id: 'rice',
  homeId: 'home',
  canonicalName: 'Rice',
  packSize: '1 kg',
  category: 'Food',
  isHomeProduct: true,
);

class _Repository implements InventoryRepository, InventoryMetadataRepository {
  final edits = <Map<String, Object?>>[];
  final categoryNames = <String>[];
  @override
  bool get supportsInventoryMetadata => true;
  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
      Stream.value([]);
  @override
  Stream<List<InventoryItem>> watchArchivedHomeProducts(String homeId) =>
      Stream.value([_product]);
  @override
  Stream<List<HomeInventoryCategory>> watchHomeCategories(String homeId) =>
      Stream.value([]);
  @override
  Stream<StockCountSession?> watchActiveCountSession({
    required String homeId,
  }) => Stream.value(null);
  @override
  Future<void> saveCountSession(StockCountSession session) async {}
  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) async {}
  @override
  Future<void> saveHomeCategory({
    required String homeId,
    String? categoryId,
    required String name,
    required bool archived,
    int? expectedRevision,
  }) async {
    categoryNames.add(name);
  }

  @override
  Future<void> updateHomeProduct({
    required String homeId,
    required String productId,
    required String privateName,
    String? originalPackText,
    String? homeCategoryId,
    required bool archived,
    int? expectedRevision,
  }) async {
    edits.add({
      'name': privateName,
      'pack': originalPackText,
      'category': homeCategoryId,
      'archived': archived,
    });
  }
}
