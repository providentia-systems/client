import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/application/stock_preference_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/domain/stock_preference.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/inventory/presentation/stock_preference_editor.dart';

const _home = '00000000-0000-4000-8000-000000000001';
const _product = '00000000-0000-4000-8000-000000000002';

void main() {
  testWidgets(
    'editor loads current values, rejects invalid input and preserves revision on save',
    (tester) async {
      final repository = _Repository();
      final controller = InventoryController(
        repository: repository,
        homeId: _home,
        mayManageStockPreferences: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showStockPreferenceEditor(
                  context,
                  controller,
                  InventoryItem(
                    id: _product,
                    homeId: _home,
                    canonicalName: 'Rice',
                    packSize: '1 kg',
                    category: 'Pantry',
                  ),
                ),
                child: const Text('Open preferences'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open preferences'));
      await tester.pumpAndSettle();
      expect(find.text('6.5'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('stock-preference-minimum')),
        '-1',
      );
      await tester.tap(find.text('Save preferences'));
      await tester.pumpAndSettle();
      expect(repository.saved, isNull);
      expect(
        find.textContaining('Minimum must be non-negative'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('stock-preference-minimum')),
        '4.25',
      );
      await tester.tap(find.text('Save preferences'));
      await tester.pumpAndSettle();
      expect(repository.saved!.minimumQuantity, '4.25');
      expect(repository.saved!.revision, 9);
      expect(find.text('Save preferences'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Repository
    implements InventoryRepository, StockPreferenceRepository {
  StockPreference? saved;
  @override
  bool get supportsStockPreferences => true;
  @override
  Future<StockPreference> loadStockPreference({
    required String homeId,
    required String productId,
  }) async => StockPreference(
    homeId: homeId,
    homeProductId: productId,
    revision: 9,
    minimumQuantity: '6.5',
    leadTimeDays: 2,
  );
  @override
  Future<void> saveStockPreference(StockPreference preference) async {
    saved = preference;
  }

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
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
}
