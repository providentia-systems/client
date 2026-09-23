import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/inventory/presentation/inventory_metadata_dialogs.dart';
import 'package:providentia/features/inventory/presentation/inventory_workspace.dart';

void main() {
  testWidgets(
    'create a private product with a global category and unit without local categories',
    (tester) async {
      final repository = _Repository();
      await _workspace(tester, repository);
      await tester.tap(find.byKey(const Key('inventory-add-private-product')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('inventory-private-product-name')),
        'Apple',
      );
      await _choose(
        tester,
        find.byKey(const Key('inventory-private-product-unit')),
        'kg',
      );
      await _choose(tester, _categoryField(), 'Produce · Global');
      await tester.tap(find.byKey(const Key('inventory-save-private-product')));
      await tester.pumpAndSettle();
      final draft = repository.created.single;
      expect(draft.privateName, 'Apple');
      expect(draft.unit, 'kg');
      expect(draft.globalCategoryId, 'global');
      expect(draft.homeCategoryId, isNull);
      expect(repository.categories, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final linked in [false, true]) {
    testWidgets(
      '${linked ? 'linked' : 'private'} product name, pack, stock unit and category remain editable',
      (tester) async {
        final repository = _Repository(localCategories: true, linked: linked);
        await _workspace(tester, repository);
        await tester.ensureVisible(find.byTooltip('Edit product'));
        await tester.tap(find.byTooltip('Edit product'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.byKey(const Key('inventory-product-name')),
              )
              .enabled,
          isTrue,
        );
        await tester.enterText(
          find.byKey(const Key('inventory-product-name')),
          'My apple',
        );
        await tester.enterText(
          find.byKey(const Key('inventory-product-pack')),
          'Fruit crate',
        );
        await _choose(
          tester,
          find.byKey(const Key('inventory-product-unit')),
          'kg',
        );
        await _choose(tester, _categoryField(), 'Pantry · Local');
        await _choose(tester, _categoryField(), 'Produce · Global');
        await tester.tap(find.text('Save locally'));
        await tester.pumpAndSettle();
        expect(repository.edits.single, {
          'id': 'apple',
          'name': 'My apple',
          'pack': 'Fruit crate',
          'unit': 'kg',
          'global': 'global',
          'local': null,
          'revision': 5,
          'archived': false,
        });
        expect(repository.adjustments, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final quantity in <double?>[null, 3]) {
    testWidgets(
      'quantity entry from $quantity has no reason controls and keeps the stock audit',
      (tester) async {
        final repository = _Repository(quantity: quantity);
        await _workspace(tester, repository);
        if (quantity == null) {
          await tester.tap(find.text('Item master'));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.text('Apple'));
        await tester.tap(find.text('Apple'));
        await tester.pumpAndSettle();
        expect(find.text('Reason for adjustment'), findsNothing);
        expect(find.text('Stock count correction'), findsNothing);
        expect(
          find.byKey(const Key('inventory-adjustment-reason')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('inventory-adjustment-explanation')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('inventory-quantity-input')),
          '4.5',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(repository.adjustments.single.observedQuantity, 4.5);
        expect(repository.adjustments.single.reason, 'Stock count correction');
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'quantity validation and cancellation do not write stock; zero is accepted',
    (tester) async {
      final repository = _Repository();
      await _workspace(tester, repository);
      await tester.ensureVisible(find.text('Apple'));
      await tester.tap(find.text('Apple'));
      await tester.pumpAndSettle();
      for (final invalid in ['', 'no quantity', '-1', 'NaN', 'Infinity']) {
        await tester.enterText(
          find.byKey(const Key('inventory-quantity-input')),
          invalid,
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(repository.adjustments, isEmpty);
        expect(
          find.text('Enter a finite quantity of zero or more.'),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.adjustments, isEmpty);
      await tester.tap(find.text('Apple'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('inventory-quantity-input')),
        '0',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.adjustments.single.observedQuantity, 0);
      expect(repository.adjustments.single.reason, 'Stock count correction');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'global category management remains visible with zero local categories',
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
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Produce'), findsOneWidget);
      expect(find.text('Global categories'), findsOneWidget);
      expect(find.text('Create category'), findsOneWidget);
      expect(repository.categories, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '320px layout at text scale $scale keeps adjustment controls reachable with keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _Repository();
        await _workspace(tester, repository, scale: scale);
        await tester.scrollUntilVisible(
          find.text('Apple'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Apple'));
        await tester.tap(find.text('Apple'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('inventory-quantity-input')),
        );
        await tester.enterText(
          find.byKey(const Key('inventory-quantity-input')),
          '4',
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(repository.adjustments.single.observedQuantity, 4);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _categoryField() => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<String> &&
      widget.key.toString().contains('inventory-category-selection-'),
);
Future<void> _choose(WidgetTester tester, Finder field, String label) async {
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  final option = find.text(label).last;
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _workspace(
  WidgetTester tester,
  _Repository repository, {
  double scale = 1,
}) async {
  final controller = InventoryController(
    repository: repository,
    homeId: 'home',
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: InventoryWorkspace(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

class _Repository
    implements InventoryProductCreationRepository, InventoryMetadataRepository {
  _Repository({
    bool localCategories = false,
    bool linked = false,
    double? quantity = 3,
  }) : categories = localCategories
           ? [
               HomeInventoryCategory(
                 id: 'local',
                 name: 'Pantry',
                 revision: 1,
                 archived: false,
               ),
             ]
           : [],
       item = InventoryItem(
         id: 'apple',
         homeId: 'home',
         canonicalName: 'Apple',
         packSize: '1 kg',
         category: 'Produce',
         currentQuantity: quantity,
         isHomeProduct: true,
         revision: 5,
         productId: linked ? 'catalog-apple' : null,
         packId: linked ? 'catalog-pack' : null,
         catalogName: linked ? 'Apple' : null,
         catalogPackText: linked ? '1 kg' : null,
         catalogCategoryId: linked ? 'global' : null,
         catalogCategoryName: linked ? 'Produce' : null,
       );
  final List<HomeInventoryCategory> categories;
  final InventoryItem item;
  final created = <PrivateHomeProductDraft>[];
  final edits = <Map<String, Object?>>[];
  final adjustments = <ManualAdjustmentIntent>[];
  @override
  bool get supportsInventoryMetadata => true;
  @override
  bool get supportsPrivateHomeProductCreation => true;
  @override
  bool get supportsCatalogHomeProductCreation => true;
  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
      Stream.value([item]);
  @override
  Stream<List<InventoryItem>> watchArchivedHomeProducts(String homeId) =>
      Stream.value([]);
  @override
  Stream<List<HomeInventoryCategory>> watchHomeCategories(String homeId) =>
      Stream.value(categories);
  @override
  Stream<List<PublishedInventoryCategory>> watchPublishedCategories(
    String homeId,
  ) => Stream.value([
    PublishedInventoryCategory(id: 'global', name: 'Produce', revision: 1),
  ]);
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
  }) async {
    adjustments.add(intent);
  }

  @override
  Future<InventoryProductCreationResult> createPrivateHomeProduct(
    PrivateHomeProductDraft draft,
  ) async {
    created.add(draft);
    return const InventoryProductCreationResult(
      homeProductId: 'created',
      revision: 1,
      disposition: InventoryProductCreationDisposition.queued,
    );
  }

  @override
  Future<InventoryProductCreationResult> createCatalogHomeProduct(
    CatalogHomeProductDraft draft,
  ) async => const InventoryProductCreationResult(
    homeProductId: 'created',
    revision: 1,
    disposition: InventoryProductCreationDisposition.queued,
  );
  @override
  Future<void> updateHomeProduct({
    required String homeId,
    required String productId,
    required String? privateName,
    String? originalPackText,
    String? homeCategoryId,
    String? globalCategoryId,
    String? unit,
    required bool archived,
    int? expectedRevision,
  }) async {
    edits.add({
      'id': productId,
      'name': privateName,
      'pack': originalPackText,
      'local': homeCategoryId,
      'global': globalCategoryId,
      'unit': unit,
      'revision': expectedRevision,
      'archived': archived,
    });
  }

  @override
  Future<void> saveHomeCategory({
    required String homeId,
    String? categoryId,
    required String name,
    required bool archived,
    int? expectedRevision,
  }) async {}
}
