import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/app/household_features.dart';
import 'package:providentia/app/providentia_app.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
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
  testWidgets('shell identifies the product and contract boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview()),
    );

    expect(find.text('Providentia'), findsOneWidget);
    expect(find.text('Your pantry, ready'), findsOneWidget);
    expect(find.textContaining('saved locally first'), findsOneWidget);
    expect(find.textContaining('generated backend contract'), findsOneWidget);
  });

  for (final viewport in <(String, Size, Key)>[
    ('phone', const Size(390, 844), const Key('phone-shell')),
    ('tablet', const Size(900, 1000), const Key('tablet-shell')),
    ('desktop', const Size(1440, 1000), const Key('desktop-shell')),
  ]) {
    testWidgets('${viewport.$1} uses its adaptive navigation', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport.$2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProvidentiaApp(controller: AppController.preview()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(viewport.$3), findsOneWidget);
      switch (viewport.$1) {
        case 'phone':
          expect(find.byKey(const Key('bottom-navigation')), findsOneWidget);
          break;
        case 'tablet':
          expect(find.byKey(const Key('navigation-rail')), findsOneWidget);
          break;
        case 'desktop':
          expect(find.byKey(const Key('navigation-sidebar')), findsOneWidget);
          break;
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('offline pending state is explicit and has manual retry', (
    tester,
  ) async {
    const summary = SyncSummary(
      pending: 2,
      syncing: 0,
      retryWaiting: 1,
      blockedConflicts: 0,
      blockedValidation: 0,
      blockedAuthorization: 0,
      acknowledged: 4,
      availability: SyncAvailability.offline,
      isSynchronizing: false,
    );

    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview(summary: summary)),
    );

    expect(find.text('Saved on this device — waiting to sync'), findsOneWidget);
    expect(find.text('3 local changes waiting.'), findsOneWidget);
    expect(find.byKey(const Key('manual-sync')), findsOneWidget);
  });

  testWidgets('membership loss is distinct from expired authentication', (
    tester,
  ) async {
    const summary = SyncSummary(
      pending: 0,
      syncing: 0,
      retryWaiting: 0,
      blockedConflicts: 0,
      blockedValidation: 0,
      blockedAuthorization: 0,
      acknowledged: 0,
      availability: SyncAvailability.authorizationDenied,
      isSynchronizing: false,
      lastSafeError: 'Home membership no longer permits synchronization.',
    );

    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview(summary: summary)),
    );

    expect(find.text('Access to this home changed'), findsOneWidget);
    expect(find.textContaining('membership'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsNothing);
  });

  testWidgets('a pull failure never presents the client as up to date', (
    tester,
  ) async {
    const summary = SyncSummary(
      pending: 0,
      syncing: 0,
      retryWaiting: 0,
      blockedConflicts: 0,
      blockedValidation: 0,
      blockedAuthorization: 0,
      acknowledged: 0,
      availability: SyncAvailability.temporarilyUnavailable,
      isSynchronizing: false,
      lastSafeError: 'Synchronization was interrupted. Try again safely.',
    );

    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview(summary: summary)),
    );

    expect(find.text('Sync paused'), findsOneWidget);
    expect(find.text('Up to date'), findsNothing);
  });

  testWidgets('blocked validation never presents the client as up to date', (
    tester,
  ) async {
    const summary = SyncSummary(
      pending: 0,
      syncing: 0,
      retryWaiting: 0,
      blockedConflicts: 0,
      blockedValidation: 1,
      blockedAuthorization: 0,
      acknowledged: 0,
      availability: SyncAvailability.online,
      isSynchronizing: false,
      lastSafeError: 'Correct the value before retrying.',
    );

    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview(summary: summary)),
    );

    expect(find.text('Review a change before syncing'), findsOneWidget);
    expect(find.text('Up to date'), findsNothing);
  });

  testWidgets('large text and reduced motion remain usable', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(1.8),
          disableAnimations: true,
        ),
        child: ProvidentiaApp(controller: AppController.preview()),
      ),
    );
    await tester.pump();

    expect(find.text('Your pantry, ready'), findsOneWidget);
    final brandMark = find.byKey(const Key('brand-mark-semantics'));
    expect(brandMark, findsOneWidget);
    expect(tester.getSemantics(brandMark).label, 'Providentia');
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('keyboard traversal reaches primary interactive controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview()),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  testWidgets('composed workspace exposes change-home and sign-out actions', (
    tester,
  ) async {
    var changeHomeCalls = 0;
    var signOutCalls = 0;
    await tester.pumpWidget(
      ProvidentiaApp(
        controller: AppController.preview(),
        onChangeHome: () async {
          changeHomeCalls++;
        },
        onSignOut: () async {
          signOutCalls++;
        },
      ),
    );

    await tester.tap(find.byKey(const Key('account-actions')));
    await tester.pumpAndSettle();
    expect(find.text('Change home'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Change home'));
    await tester.pumpAndSettle();
    expect(changeHomeCalls, 1);

    await tester.tap(find.byKey(const Key('account-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(signOutCalls, 1);
  });

  testWidgets(
    'overview baseline reports 292 catalog packs while preserving private counted products',
    (tester) async {
      const homeId = 'home-baseline';
      final catalogItems = List<InventoryItem>.generate(292, (index) {
        final selected = index < 32;
        return InventoryItem(
          id: selected ? 'home-product-$index' : 'pack-$index',
          homeId: homeId,
          canonicalName: 'Product $index',
          packSize: '${index + 1} units',
          category: 'Baseline',
          currentQuantity: selected ? 2 : null,
          isHomeProduct: selected,
          productId: 'product-$index',
          packId: 'pack-$index',
        );
      });
      final privateItems = List<InventoryItem>.generate(28, (index) {
        return InventoryItem(
          id: 'private-home-product-$index',
          homeId: homeId,
          canonicalName: 'Private product $index',
          packSize: 'Source description',
          category: 'Private',
          currentQuantity: index == 27 ? 41 : 2,
          isHomeProduct: true,
        );
      });
      final items = [...catalogItems, ...privateItems];
      final purchaseLines = <PurchaseLine>[
        for (var index = 0; index < 16; index++)
          _purchaseLine(
            homeId: homeId,
            index: index,
            source: PurchaseSource.recentReceipt,
            lineTotal: Money(minorUnits: 100 + index, currency: 'NAD'),
          ),
        for (var index = 16; index < 20; index++)
          _purchaseLine(
            homeId: homeId,
            index: index,
            source: PurchaseSource.historicalImport,
            lineTotal: Money(minorUnits: 100 + index, currency: 'NAD'),
          ),
        for (var index = 20; index < 23; index++)
          _purchaseLine(
            homeId: homeId,
            index: index,
            source: PurchaseSource.recentReceipt,
          ),
      ];
      final inventory = InventoryController(
        repository: _BaselineInventoryRepository(items),
        homeId: homeId,
      );
      final purchasing = PurchasingController(
        repository: _BaselinePurchaseRepository(purchaseLines),
        homeId: homeId,
      );
      final shopping = ShoppingController(
        repository: _BaselineShoppingRepository(
          ShoppingList(
            id: 'shopping-list',
            homeId: homeId,
            name: 'Baseline',
            createdAt: DateTime.utc(2026, 8, 11),
          ),
        ),
        homeId: homeId,
      );

      await tester.pumpWidget(
        ProvidentiaApp(
          controller: AppController.preview(),
          features: HouseholdFeatures(
            inventory: inventory,
            purchasing: purchasing,
            shopping: shopping,
          ),
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

      expect(inventory.state.items, hasLength(320));
      expect(
        inventory.state.items
            .map((item) => item.packId)
            .whereType<String>()
            .toSet(),
        hasLength(292),
      );
      expect(
        inventory.state.items.where((item) => item.isCounted),
        hasLength(60),
      );
      expect(
        inventory.state.items.fold<double>(
          0,
          (total, item) => total + (item.currentQuantity ?? 0),
        ),
        159,
      );
      expect(
        purchasing.state.lines.where(
          (line) =>
              line.source == PurchaseSource.recentReceipt &&
              line.lineTotal != null,
        ),
        hasLength(16),
      );
      expect(find.text('292'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
    },
  );
}

PurchaseLine _purchaseLine({
  required String homeId,
  required int index,
  required PurchaseSource source,
  Money? lineTotal,
}) => PurchaseLine(
  id: 'purchase-$index',
  homeId: homeId,
  purchasedAt: DateTime.utc(2026, 8, 11).subtract(Duration(days: index)),
  datePrecision: source == PurchaseSource.recentReceipt
      ? PurchaseDatePrecision.exactDay
      : PurchaseDatePrecision.monthOnly,
  storeName: 'Store',
  rawDescription: 'Item $index',
  packSize: '1 unit',
  quantity: 1,
  source: source,
  receiptId: source == PurchaseSource.recentReceipt ? 'receipt-$index' : null,
  lineTotal: lineTotal,
);

final class _BaselineInventoryRepository implements InventoryRepository {
  const _BaselineInventoryRepository(this.items);

  final List<InventoryItem> items;

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
      Stream<List<InventoryItem>>.value(items);

  @override
  Stream<StockCountSession?> watchActiveCountSession({
    required String homeId,
  }) => Stream<StockCountSession?>.value(null);

  @override
  Future<void> saveCountSession(StockCountSession session) =>
      throw UnsupportedError('read-only baseline');

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) => throw UnsupportedError('read-only baseline');
}

final class _BaselinePurchaseRepository implements PurchaseRepository {
  const _BaselinePurchaseRepository(this.lines);

  final List<PurchaseLine> lines;

  @override
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId}) =>
      Stream<List<PurchaseLine>>.value(lines);

  @override
  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  }) => const Stream<List<PriceObservation>>.empty();
}

final class _BaselineShoppingRepository implements ShoppingRepository {
  const _BaselineShoppingRepository(this.list);

  final ShoppingList list;

  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) =>
      Stream<ShoppingList>.value(list);

  @override
  Future<void> saveList(ShoppingList list) =>
      throw UnsupportedError('read-only baseline');

  @override
  Future<void> recordFeedback(SuggestionFeedback feedback) =>
      throw UnsupportedError('read-only baseline');
}
