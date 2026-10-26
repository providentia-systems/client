import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/receipt_draft_editor.dart';

const _home = '10000000-0000-4000-8000-000000000021';
const _otherHome = '10000000-0000-4000-8000-000000000022';
const _receipt = '10000000-0000-4000-8000-000000000023';
const _line = '10000000-0000-4000-8000-000000000024';
const _product = '10000000-0000-4000-8000-000000000025';
const _store = '10000000-0000-4000-8000-000000000026';
const _replacement = '10000000-0000-4000-8000-000000000027';
const _device = '10000000-0000-4000-8000-000000000028';
final _at = DateTime.utc(2026, 10, 26);

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(database, deviceId: _device);
  });
  tearDown(() => database.close());

  Future<void> seed(
    String type,
    String id,
    Map<String, Object?> fields, {
    String home = _home,
    int revision = 1,
  }) => database
      .into(database.localRecords)
      .insertOnConflictUpdate(
        LocalRecordsCompanion.insert(
          homeId: home,
          entityType: type,
          entityId: id,
          revision: Value(revision),
          payload: jsonEncode(fields),
          updatedAt: _at,
          synchronizedAt: Value(_at),
        ),
      );

  Future<Map<String, Object?>> row(String type, String id) async {
    final saved =
        await (database.select(database.localRecords)..where(
              (r) =>
                  r.homeId.equals(_home) &
                  r.entityType.equals(type) &
                  r.entityId.equals(id),
            ))
            .getSingle();
    return jsonDecode(saved.payload) as Map<String, Object?>;
  }

  Future<void> seedStore(
    String id, {
    bool archived = false,
    String home = _home,
  }) => seed('purchasing-store', id, {
    'name': id == _store ? 'Original shop' : 'Replacement shop',
    'status': archived ? 'archived' : 'active',
    'location': '',
  }, home: home);

  Future<void> seedReceipt({String? storeId = _store, int revision = 4}) async {
    await seed('purchasing-receipt', _receipt, {
      'storeId': storeId,
      'purchaseDate': '2026-01-01',
      'currency': 'NAD',
      'status': 'committed',
      'lineCorrectionState': 'available',
      'totalAmount': '12.50',
      'notes': 'Original notes',
    }, revision: revision);
    await seed('purchasing-receipt-line', _line, {
      'receiptId': _receipt,
      'rawDescription': 'Synthetic rice',
      'quantity': '2',
      'approvalStatus': 'approved',
      'homeProductId': _product,
      'stockQuantity': '2',
      'stockQuantityPerPack': '1',
      'stockUnit': 'kg',
      'lineTotal': '12.50',
    });
    await seed('inventory-balance', _product, {
      'homeProductId': _product,
      'quantity': '-1.5',
      'uncertain': true,
      'limitations': ['Synthetic chronology limitation'],
    });
  }

  Future<void> update(String? storeId) => repository.updateReceiptDraft(
    receiptId: _receipt,
    expectedRevision: 4,
    draft: PurchaseReceiptDraftRequest(
      homeId: _home,
      purchaseDate: DateTime.utc(2026, 1, 1),
      currency: 'NAD',
      storeId: storeId,
      total: Money(currency: 'NAD', minorUnits: 1500),
      notes: 'Changed notes',
    ),
  );

  for (final missing in [false, true]) {
    test(
      'retains ${missing ? 'missing' : 'archived'} saved store without changing stock',
      () async {
        await seedReceipt();
        if (!missing) await seedStore(_store, archived: true);
        final stock = await row('inventory-balance', _product);
        final line = await row('purchasing-receipt-line', _line);
        final capture =
            (await repository.watchReceiptCaptures(homeId: _home).first).single;
        expect(capture.storeId, _store);
        expect(
          capture.storeName,
          missing ? 'Unavailable store' : 'Original shop',
        );
        await update(_store);
        final saved = await row('purchasing-receipt', _receipt);
        expect(saved['storeId'], _store);
        expect(saved['purchaseDate'], '2026-01-01');
        expect(saved['currency'], 'NAD');
        expect(saved['notes'], 'Changed notes');
        expect(saved['totalAmount'], '15');
        expect(await row('inventory-balance', _product), stock);
        expect(await row('purchasing-receipt-line', _line), line);
        final command = await database
            .select(database.clientOperations)
            .getSingle();
        expect(command.operationType, 'purchasing.receipt.update');
        expect((jsonDecode(command.payload) as Map)['storeId'], _store);
      },
    );
  }

  for (final clear in [false, true]) {
    test(
      'can explicitly ${clear ? 'clear' : 'replace'} an archived historical store',
      () async {
        await seedReceipt();
        await seedStore(_store, archived: true);
        await seedStore(_replacement);
        await update(clear ? null : _replacement);
        expect(
          (await row('purchasing-receipt', _receipt))['storeId'],
          clear ? null : _replacement,
        );
        expect((await row('purchasing-store', _store))['status'], 'archived');
      },
    );
  }

  for (final kind in ['archived', 'foreign', 'missing']) {
    test(
      'rejects a newly selected $kind store without changing a receipt',
      () async {
        await seedReceipt();
        if (kind != 'missing') {
          await seedStore(
            _replacement,
            archived: kind == 'archived',
            home: kind == 'foreign' ? _otherHome : _home,
          );
        }
        final before = await row('purchasing-receipt', _receipt);
        await expectLater(
          update(_replacement),
          throwsA(
            isA<PurchaseCaptureException>().having(
              (error) => error.safeMessage,
              'safeMessage',
              contains('active store from this home'),
            ),
          ),
        );
        expect(await row('purchasing-receipt', _receipt), before);
        expect(await database.select(database.clientOperations).get(), isEmpty);
      },
    );
  }

  test(
    'retention does not authorize assigning that archived store to another receipt',
    () async {
      await seedReceipt(storeId: null);
      await seedStore(_store, archived: true);
      await expectLater(
        update(_store),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect((await row('purchasing-receipt', _receipt))['storeId'], isNull);
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );

  Future<PurchasingController> openEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = PurchasingController(
      repository: repository,
      homeId: _home,
      mayWrite: true,
    );
    addTearDown(controller.dispose);
    controller.start();
    final capture = (await tester.runAsync(
      () => repository.watchReceiptCaptures(homeId: _home).first,
    ))!.single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ReceiptDraftEditor(
                  controller: controller,
                  receipt: capture,
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> saveEditor(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('receipt-edit-save')));
    final controller = tester
        .widget<ReceiptDraftEditor>(find.byType(ReceiptDraftEditor))
        .controller;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('receipt-edit-save')));
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (controller.state.captureBusy &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
  }

  for (final missing in [false, true]) {
    testWidgets(
      'editor displays and retains ${missing ? 'missing' : 'archived'} historical association',
      (tester) async {
        await tester.runAsync(() async {
          await seedReceipt();
          if (!missing) await seedStore(_store, archived: true);
        });
        await openEditor(tester);
        expect(
          find.textContaining(
            missing
                ? 'unavailable · current store'
                : 'Original shop (archived · current store)',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('receipt-edit-historical-store')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('receipt-edit-notes')),
          'Retained history',
        );
        await tester.enterText(
          find.byKey(const Key('receipt-edit-total')),
          '15.00',
        );
        await saveEditor(tester);
        expect(find.byKey(const Key('receipt-edit-error')), findsNothing);
        final saved = await tester.runAsync(
          () => row('purchasing-receipt', _receipt),
        );
        expect(saved!['storeId'], _store);
        expect(saved['notes'], 'Retained history');
        expect(saved['totalAmount'], '15');
        expect(saved['purchaseDate'], '2026-01-01');
      },
    );
  }

  for (final clear in [false, true]) {
    testWidgets(
      'editor explicitly ${clear ? 'clears' : 'replaces'} historical store',
      (tester) async {
        await tester.runAsync(() async {
          await seedReceipt();
          await seedStore(_store, archived: true);
          await seedStore(_replacement);
        });
        await openEditor(tester);
        await tester.tap(find.byKey(const Key('receipt-edit-store')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(clear ? 'No store' : 'Replacement shop').last,
        );
        await tester.pumpAndSettle();
        await saveEditor(tester);
        expect(find.byKey(const Key('receipt-edit-error')), findsNothing);
        final saved = await tester.runAsync(
          () => row('purchasing-receipt', _receipt),
        );
        expect(saved!['storeId'], clear ? null : _replacement);
        expect(
          (await tester.runAsync(
            () => row('purchasing-store', _store),
          ))!['status'],
          'archived',
        );
      },
    );
  }

  testWidgets(
    'store archived while editor is open stays selected and preserves typed input',
    (tester) async {
      await tester.runAsync(() async {
        await seedReceipt();
        await seedStore(_store);
      });
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('receipt-edit-notes')),
        'Typed before archive',
      );
      await tester.runAsync(() => seedStore(_store, archived: true));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Original shop (archived · current store)'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('receipt-edit-notes')))
            .controller!
            .text,
        'Typed before archive',
      );
      await saveEditor(tester);
      final saved = await tester.runAsync(
        () => row('purchasing-receipt', _receipt),
      );
      expect(saved!['storeId'], _store);
      expect(saved['notes'], 'Typed before archive');
    },
  );

  testWidgets(
    'replacement archived while editor is open gets a store field error and retains entries',
    (tester) async {
      await tester.runAsync(() async {
        await seedReceipt();
        await seedStore(_store);
        await seedStore(_replacement);
      });
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('receipt-edit-store')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replacement shop').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('receipt-edit-notes')),
        'Keep typed replacement',
      );
      await tester.runAsync(() => seedStore(_replacement, archived: true));
      await tester.pumpAndSettle();
      await saveEditor(tester);
      expect(
        find.text(
          'Choose an active store from this home, or keep the current historical store.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('receipt-edit-notes')))
            .controller!
            .text,
        'Keep typed replacement',
      );
      expect(
        (await tester.runAsync(
          () => row('purchasing-receipt', _receipt),
        ))!['storeId'],
        _store,
      );
      expect(
        await tester.runAsync(
          () => database.select(database.clientOperations).get(),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'receipt revision conflict preserves typed metadata and historical selection',
    (tester) async {
      await tester.runAsync(() async {
        await seedReceipt();
        await seedStore(_store, archived: true);
      });
      await openEditor(tester);
      await tester.enterText(
        find.byKey(const Key('receipt-edit-notes')),
        'Retain on revision conflict',
      );
      await tester.enterText(
        find.byKey(const Key('receipt-edit-total')),
        '16.00',
      );
      await tester.runAsync(
        () =>
            (database.update(database.localRecords)..where(
                  (record) =>
                      record.homeId.equals(_home) &
                      record.entityType.equals('purchasing-receipt') &
                      record.entityId.equals(_receipt),
                ))
                .write(const LocalRecordsCompanion(revision: Value(5))),
      );
      await tester.pumpAndSettle();
      await saveEditor(tester);
      expect(
        find.text('This draft changed. Reopen it before saving.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('receipt-edit-notes')))
            .controller!
            .text,
        'Retain on revision conflict',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('receipt-edit-total')))
            .controller!
            .text,
        '16.00',
      );
      expect(
        find.textContaining('Original shop (archived · current store)'),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(
          () => database.select(database.clientOperations).get(),
        ),
        isEmpty,
      );
    },
  );
}
