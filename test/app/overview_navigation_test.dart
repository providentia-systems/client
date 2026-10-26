import 'dart:async';

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

const _home = 'synthetic-home';
const _access = HouseholdWorkspaceAccess(
  inventoryRead: true,
  inventoryWrite: true,
  purchasesRead: true,
  purchasesWrite: false,
  shoppingRead: true,
  shoppingWrite: false,
);

void main() {
  testWidgets(
    'overview counts private products and repeated pack links, zero balances and unpriced receipts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture();
      await tester.pumpWidget(
        fixture.app(
          summary: const SyncSummary.initial().copyWith(
            availability: SyncAvailability.offline,
            pending: 2,
          ),
        ),
      );
      fixture.inventory.items.add([
        _item('private', quantity: 0),
        _item('linked-one', pack: 'same-pack', quantity: 2),
        _item('linked-two', pack: 'same-pack'),
        _item('catalog-browsing', pack: 'other-pack', selected: false),
      ]);
      fixture.purchasing.lines.add([]);
      fixture.purchasing.receipts.add([
        _receipt('missing-prices'),
        _receipt('header-only', total: 1000),
        _receipt('draft', draft: true),
      ]);
      await tester.pumpAndSettle();
      expect(_metricText(tester, 'Household products'), contains('3'));
      expect(_metricText(tester, 'Products with a balance'), contains('2'));
      expect(_metricText(tester, 'Finished receipts'), contains('2'));
      expect(find.textContaining('including zero'), findsOneWidget);
      expect(
        find.textContaining('not a physical-count certification'),
        findsOneWidget,
      );
      expect(find.textContaining('all saved purchase dates'), findsOneWidget);
      expect(find.textContaining('Saved offline data'), findsNWidgets(3));
      expect(
        find.textContaining('2 unresolved local operations'),
        findsNWidgets(3),
      );
      expect(tester.takeException(), isNull);
      await fixture.close(tester);
    },
  );

  testWidgets(
    'initial failures, last-known reads and a genuine empty result remain distinct independently',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture();
      await tester.pumpWidget(fixture.app());
      expect(_metricText(tester, 'Household products'), contains('Loading'));
      expect(_metricText(tester, 'Finished receipts'), contains('Loading'));
      fixture.inventory.items.addError(
        StateError('synthetic inventory failure'),
      );
      fixture.purchasing.lines.add([]);
      fixture.purchasing.receipts.add([_receipt('saved')]);
      await tester.pumpAndSettle();
      expect(
        _metricText(tester, 'Household products'),
        contains('Unavailable'),
      );
      expect(_metricText(tester, 'Finished receipts'), contains('1'));
      expect(find.textContaining('this is not a zero'), findsNWidgets(2));
      fixture.inventory.items.add([_item('one', quantity: 0)]);
      await tester.pumpAndSettle();
      fixture.inventory.items.addError(StateError('synthetic refresh failure'));
      fixture.purchasing.receipts.addError(
        StateError('synthetic receipt refresh failure'),
      );
      await tester.pumpAndSettle();
      expect(fixture.features.inventory.state.items.single.id, 'one');
      expect(_metricText(tester, 'Household products'), contains('1'));
      expect(_metricText(tester, 'Finished receipts'), contains('1'));
      expect(
        find.textContaining('Last known data; the latest read failed'),
        findsNWidgets(3),
      );
      fixture.inventory.items.add([]);
      fixture.purchasing.receipts.add([]);
      await tester.pumpAndSettle();
      expect(_metricText(tester, 'Household products'), contains('0'));
      expect(_metricText(tester, 'Finished receipts'), contains('0'));
      expect(
        find.textContaining('Last known data; the latest read failed'),
        findsNothing,
      );
      await fixture.close(tester);
    },
  );

  for (final size in [
    const Size(390, 844),
    const Size(900, 1000),
    const Size(1440, 1000),
  ]) {
    testWidgets(
      'named reports/account links retain workspace input at width ${size.width}',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = _Fixture();
        await tester.pumpWidget(
          fixture.app(
            reports: (_) => Scaffold(
              appBar: AppBar(title: const Text('Reports')),
              body: const Text('Existing protected report route'),
            ),
            account: (_) => Scaffold(
              appBar: AppBar(title: const Text('Account')),
              body: const Text('Existing account route'),
            ),
          ),
        );
        fixture.inventory.items.add([_item('private', quantity: 0)]);
        fixture.purchasing.lines.add([]);
        fixture.purchasing.receipts.add([]);
        fixture.controller.selectSection(AppSection.stock);
        await tester.pumpAndSettle();
        final search = find.byKey(const Key('inventory-search'));
        await tester.enterText(search, 'typed stock filter');
        await tester.pumpAndSettle();
        expect(find.text('Reports').hitTestable(), findsOneWidget);
        expect(find.text('Account/settings').hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(const Key('workspace-reports')));
        await tester.pumpAndSettle();
        expect(find.text('Existing protected report route'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(fixture.controller.section, AppSection.stock);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: search,
                  matching: find.byType(EditableText),
                ),
              )
              .controller
              .text,
          'typed stock filter',
        );
        await tester.tap(find.byKey(const Key('workspace-account-settings')));
        await tester.pumpAndSettle();
        expect(find.text('Existing account route'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          fixture.features.inventory.state.criteria.query,
          'typed stock filter',
        );
        expect(tester.takeException(), isNull);
        await fixture.close(tester);
      },
    );
  }

  testWidgets('report link has a screen-reader label and opens from keyboard', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProvidentiaApp(
        controller: AppController.preview(),
        householdReportsPageBuilder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Household reports')),
          body: const Text('Keyboard report route'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('workspace-reports'))).label,
      contains('Reports'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Keyboard report route'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'unavailable direct report route explains the state and returns safely',
    (tester) async {
      await tester.pumpWidget(
        ProvidentiaApp(controller: AppController.preview()),
      );
      await tester.tap(find.byKey(const Key('workspace-reports')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('unavailable in the current session'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Saved local work is preserved'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-workspace')), findsOneWidget);
    },
  );
}

String _metricText(WidgetTester tester, String label) {
  final card = find
      .ancestor(of: find.text(label), matching: find.byType(Card))
      .first;
  return tester
      .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
      .map((text) => text.data ?? '')
      .join(' ');
}

InventoryItem _item(
  String id, {
  String? pack,
  double? quantity,
  bool selected = true,
}) => InventoryItem(
  id: id,
  homeId: _home,
  canonicalName: id,
  packSize: '1 unit',
  category: 'Synthetic',
  isHomeProduct: selected,
  packId: pack,
  currentQuantity: quantity,
);
PurchaseReceiptCapture _receipt(String id, {bool draft = false, int? total}) =>
    PurchaseReceiptCapture(
      id: id,
      homeId: _home,
      purchaseDate: DateTime.utc(2026, 10, 26),
      currency: 'NAD',
      total: total == null ? null : Money(minorUnits: total, currency: 'NAD'),
      notes: '',
      revision: 1,
      status: draft
          ? PurchaseReceiptStatus.draft
          : PurchaseReceiptStatus.committed,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: const [],
    );

final class _Fixture {
  final inventory = _Inventory();
  final purchasing = _Purchasing();
  final controller = AppController.preview(activeHomeId: _home);
  late final features = HouseholdFeatures(
    inventory: InventoryController(repository: inventory, homeId: _home),
    purchasing: PurchasingController(repository: purchasing, homeId: _home),
    shopping: ShoppingController(repository: _Shopping(), homeId: _home),
  );

  Widget app({
    SyncSummary? summary,
    WidgetBuilder? reports,
    WidgetBuilder? account,
  }) => ProvidentiaApp(
    controller: summary == null
        ? controller
        : AppController.preview(activeHomeId: _home, summary: summary),
    features: features,
    access: _access,
    householdName: 'Synthetic household',
    householdReportsPageBuilder: reports,
    accountPageBuilder: account,
  );
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await inventory.items.close();
    await purchasing.lines.close();
    await purchasing.receipts.close();
  }
}

final class _Inventory implements InventoryRepository {
  final items = StreamController<List<InventoryItem>>.broadcast();
  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
      items.stream;
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
}

final class _Purchasing
    implements PurchaseRepository, PurchaseReceiptSelectionRepository {
  final lines = StreamController<List<PurchaseLine>>.broadcast();
  final receipts = StreamController<List<PurchaseReceiptCapture>>.broadcast();
  @override
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId}) =>
      lines.stream;
  @override
  Stream<List<PurchaseReceiptCapture>> watchReceiptCaptures({
    required String homeId,
  }) => receipts.stream;
  @override
  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  }) => Stream.value([]);
}

final class _Shopping implements ShoppingRepository {
  @override
  Stream<ShoppingList> watchActiveList({required String homeId}) =>
      Stream.value(
        ShoppingList(
          id: 'list',
          homeId: homeId,
          name: 'Synthetic',
          createdAt: DateTime.utc(2026),
        ),
      );
  @override
  Future<void> saveList(ShoppingList list) async {}
  @override
  Future<void> recordFeedback(SuggestionFeedback feedback) async {}
}
