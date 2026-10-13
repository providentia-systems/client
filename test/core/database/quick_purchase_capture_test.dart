import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_workspace.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/purchase_quantity.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';

const _home = '10000000-0000-4000-8000-000000000001';
const _device = '10000000-0000-4000-8000-000000000002';
const _product = '10000000-0000-4000-8000-000000000003';
const _canonical = '10000000-0000-4000-8000-000000000004';
const _packOne = '10000000-0000-4000-8000-000000000005';
const _packFour = '10000000-0000-4000-8000-000000000006';
const _line = '10000000-0000-4000-8000-000000000007';

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(database, deviceId: _device);
    await _seed(database, 'inventory-home-product', _product, {
      'productId': _canonical,
      'packId': _packOne,
      'productName': 'Apples',
      'status': 'active',
      'unit': 'kg',
    });
    await _seed(database, 'inventory-balance', _product, {
      'homeProductId': _product,
      'quantity': '2',
    });
    for (final pack in [
      (_packOne, '1 kg', '1000'),
      (_packFour, '4 kg', '4000'),
    ]) {
      await _seed(database, 'inventory-item-master-product', pack.$1, {
        'id': pack.$1,
        'homeId': _home,
        'canonicalName': 'Apples',
        'packSize': pack.$2,
        'category': 'Fruit',
        'brand': '',
        'unit': 'units',
        'aliases': <String>[],
        'isHomeProduct': false,
        'productId': _canonical,
        'packId': pack.$1,
        'normalizedBaseAmount': pack.$3,
        'normalizedBaseUnit': 'g',
        'packStatus': 'published',
      });
    }
  });
  tearDown(() async => database.close());

  test(
    'selected purchases add exact stock, preserve packs, and commit once',
    () async {
      final receipt = await _draft(repository);
      final first = await repository.addPurchasedReceiptLine(
        homeProductId: _product,
        packId: _packOne,
        line: _request(receipt.entityId, '4', clientId: _line, pack: '1 kg'),
      );
      expect(await _stock(database), '6');
      final retry = await repository.addPurchasedReceiptLine(
        homeProductId: _product,
        packId: _packOne,
        line: _request(receipt.entityId, '4', clientId: _line, pack: '1 kg'),
      );
      expect(retry.disposition, PurchaseMutationDisposition.alreadyQueued);
      expect(await _stock(database), '6');
      await repository.addPurchasedReceiptLine(
        homeProductId: _product,
        packId: _packFour,
        line: _request(receipt.entityId, '1', pack: '4 kg'),
      );
      expect(await _stock(database), '10');
      final captures = await repository
          .watchReceiptCaptures(homeId: _home)
          .first;
      expect(
        captures.single.lines.every(
          (line) => line.approved && line.stockApplied,
        ),
        isTrue,
      );
      expect(
        captures.single.lines.map((line) => line.quantity),
        unorderedEquals([4, 1]),
      );
      expect(captures.single.lines.map((line) => line.stockQuantity), [
        '4',
        '4',
      ]);
      final history = await repository.watchPurchaseLines(homeId: _home).first;
      expect(history, hasLength(2));
      expect(history.every((line) => line.pendingSynchronization), isTrue);
      await repository.commitReceipt(
        homeId: _home,
        receiptId: receipt.entityId,
      );
      await repository.commitReceipt(
        homeId: _home,
        receiptId: receipt.entityId,
      );
      expect(await _stock(database), '10');
      final operations = await database.select(database.clientOperations).get();
      expect(
        operations.where(
          (op) => op.operationType == 'purchasing.receipt-line.purchase',
        ),
        hasLength(2),
      );
      expect(
        operations.where(
          (op) => op.operationType == 'purchasing.receipt.commit',
        ),
        hasLength(1),
      );
      expect(first.revision, 1);
    },
  );

  test(
    'alternative packs convert into the selected home base pack unit',
    () async {
      await _seed(database, 'inventory-home-product', _product, {
        'productId': _canonical,
        'packId': _packOne,
        'productName': 'Apples',
        'status': 'active',
        'unit': 'units',
      });
      final receipt = await _draft(repository);
      await repository.addPurchasedReceiptLine(
        homeProductId: _product,
        packId: _packFour,
        line: _request(receipt.entityId, '1', pack: '4 kg'),
      );
      expect(await _stock(database), '6');
      final operations = await database.select(database.clientOperations).get();
      final command = jsonDecode(operations.last.payload) as Map;
      expect(command['unit'], 'units');
      expect(command['stockQuantityPerPack'], '4');
      expect(command['quantity'], '1');
    },
  );

  test(
    'quantity corrections and removal reverse only this line stock',
    () async {
      final receipt = await _draft(repository);
      final purchase = await repository.addPurchasedReceiptLine(
        homeProductId: _product,
        packId: _packFour,
        line: _request(receipt.entityId, '2', pack: '4 kg'),
      );
      expect(await _stock(database), '10');
      await repository.updateReceiptDraftLine(
        lineId: purchase.entityId,
        expectedRevision: 1,
        line: _request(receipt.entityId, '1.25', pack: '4 kg'),
      );
      expect(await _stock(database), '7');
      final capture =
          (await repository.watchReceiptCaptures(homeId: _home).first).single;
      expect(capture.lines.single.approved, isTrue);
      expect(capture.lines.single.stockQuantity, '5');
      await repository.removeReceiptDraftLine(
        homeId: _home,
        receiptId: receipt.entityId,
        lineId: purchase.entityId,
        expectedRevision: 2,
      );
      expect(await _stock(database), '2');
      final line = await _payload(
        database,
        'purchasing-receipt-line',
        purchase.entityId,
      );
      expect(line['approvalStatus'], 'removed');
      expect(line['homeProductId'], _product);
      expect(line['stockQuantity'], '0');
    },
  );

  test(
    'separate receipts remain editable and cancellation reverses applied quantities',
    () async {
      final first = await _draft(repository);
      final second = await _draft(repository);
      await repository.addPurchasedReceiptLine(
        homeProductId: _product,
        line: _request(first.entityId, '0.1'),
      );
      await repository.addPurchasedReceiptLine(
        homeProductId: _product,
        line: _request(second.entityId, '0.2'),
      );
      expect(await _stock(database), '2.3');
      final receipts = await repository
          .watchReceiptCaptures(homeId: _home)
          .first;
      expect(receipts, hasLength(2));
      final original = receipts.firstWhere(
        (receipt) => receipt.id == first.entityId,
      );
      await repository.cancelReceiptDraft(
        homeId: _home,
        receiptId: original.id,
        expectedRevision: original.revision,
      );
      expect(await _stock(database), '2.2');
      expect(
        (await repository.watchReceiptCaptures(homeId: _home).first).single.id,
        second.entityId,
      );
      expect(
        (await repository.watchPurchaseLines(homeId: _home).first)
            .single
            .quantity,
        0.2,
      );
    },
  );

  test(
    'incompatible pack rejects atomically and preserves all pending work',
    () async {
      final receipt = await _draft(repository);
      await _seed(database, 'inventory-item-master-product', _packFour, {
        'id': _packFour,
        'homeId': _home,
        'canonicalName': 'Apples',
        'packSize': '1 litre',
        'category': 'Fruit',
        'brand': '',
        'unit': 'units',
        'aliases': <String>[],
        'productId': _canonical,
        'packId': _packFour,
        'normalizedBaseAmount': '1000',
        'normalizedBaseUnit': 'ml',
        'packStatus': 'published',
      });
      await expectLater(
        repository.addPurchasedReceiptLine(
          homeProductId: _product,
          packId: _packFour,
          line: _request(receipt.entityId, '1'),
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect(await _stock(database), '2');
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(1),
      );
      expect(
        (await repository.watchReceiptCaptures(homeId: _home).first)
            .single
            .lines,
        isEmpty,
      );
    },
  );

  test(
    'committed store/header corrections preserve stock and frozen dates',
    () async {
      final receipt = await _draft(repository);
      await repository.addPurchasedReceiptLine(
        homeProductId: _product,
        line: _request(receipt.entityId, '5'),
      );
      final committed = await repository.commitReceipt(
        homeId: _home,
        receiptId: receipt.entityId,
      );
      await repository.updateReceiptDraft(
        receiptId: receipt.entityId,
        expectedRevision: committed.revision,
        draft: PurchaseReceiptDraftRequest(
          homeId: _home,
          purchaseDate: DateTime.utc(2026, 10, 13),
          currency: 'NAD',
          notes: 'Corrected note',
        ),
      );
      expect(await _stock(database), '7');
      await expectLater(
        repository.updateReceiptDraft(
          receiptId: receipt.entityId,
          expectedRevision: committed.revision + 1,
          draft: PurchaseReceiptDraftRequest(
            homeId: _home,
            purchaseDate: DateTime.utc(2026, 10, 14),
            currency: 'NAD',
          ),
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect(await _stock(database), '7');
    },
  );

  test(
    'controller switches drafts while another receipt synchronization is pending',
    () async {
      final first = await _draft(repository);
      final second = await _draft(repository);
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
        productCreationRepository: repository,
      )..start();
      await pumpEventQueue();
      expect(controller.receipts, hasLength(2));
      controller.selectReceipt(first.entityId);
      expect(controller.state.capture?.id, first.entityId);
      controller.selectReceipt(second.entityId);
      expect(controller.state.capture?.id, second.entityId);
      controller.startAnotherReceipt();
      expect(controller.state.capture, isNull);
      expect(
        await controller.createDraft(
          purchaseDate: DateTime.utc(2026, 10, 13),
          currency: 'NAD',
        ),
        isTrue,
      );
      await pumpEventQueue();
      expect(controller.receipts, hasLength(3));
      expect(controller.state.capture?.id, isNot(first.entityId));
      expect(controller.state.capture?.id, isNot(second.entityId));
      controller.dispose();
    },
  );

  testWidgets('manual Add increases stock and resets the next product entry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _draft(repository);
    final controller = PurchasingController(
      repository: repository,
      homeId: _home,
      mayWrite: true,
      productCreationRepository: repository,
    );
    addTearDown(controller.dispose);
    var imports = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PurchasingWorkspace(
            controller: controller,
            onImportReceipt: () => imports++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byKey(const Key('purchase-product-search')),
      matching: find.byType(TextField),
    );
    await tester.tap(search);
    await tester.enterText(search, 'Apples');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apples · 1 kg').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('purchase-line-quantity')),
      '5',
    );
    await tester.enterText(
      find.byKey(const Key('purchase-line-total')),
      '100.00',
    );
    await tester.ensureVisible(find.byKey(const Key('purchase-add-line')));
    await tester.tap(find.byKey(const Key('purchase-add-line')));
    await tester.pumpAndSettle();
    expect(await _stock(database), '7');
    expect(find.text('Match product'), findsNothing);
    expect(tester.widget<TextField>(search).controller!.text, '');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('purchase-line-quantity')))
          .controller!
          .text,
      '1',
    );
    expect(
      find.text(
        'Purchase saved. Stock is updated locally; synchronization is pending.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('purchase-import-receipt')),
    );
    await tester.tap(find.byKey(const Key('purchase-import-receipt')));
    expect(imports, 1);
  });

  test('decimal arithmetic rejects precision loss and adds tenths exactly', () {
    expect(
      (PurchaseQuantity.parse('0.1') + PurchaseQuantity.parse('0.2'))
          .toString(),
      '0.3',
    );
    expect(
      (PurchaseQuantity.parse('1.25') * PurchaseQuantity.parse('4')).toString(),
      '5',
    );
    expect(() => PurchaseQuantity.parse('0.000000001'), throwsArgumentError);
    expect(
      () =>
          PurchaseQuantity.parse('0.00000001') * PurchaseQuantity.parse('0.1'),
      throwsArgumentError,
    );
  });
}

Future<PurchaseMutationResult> _draft(DriftHouseholdRepository repository) =>
    repository.createReceiptDraft(
      PurchaseReceiptDraftRequest(
        homeId: _home,
        purchaseDate: DateTime.utc(2026, 10, 13),
        currency: 'NAD',
      ),
    );

PurchaseReceiptLineRequest _request(
  String receipt,
  String quantity, {
  String? clientId,
  String? pack,
}) => PurchaseReceiptLineRequest(
  homeId: _home,
  receiptId: receipt,
  rawDescription: 'Apples',
  quantity: double.parse(quantity),
  quantityText: quantity,
  clientLineId: clientId,
  originalPackText: pack,
  lineTotal: Money(minorUnits: 1200, currency: 'NAD'),
);

Future<void> _seed(
  AppDatabase database,
  String type,
  String id,
  Map<String, Object?> value,
) async {
  await database
      .into(database.localRecords)
      .insertOnConflictUpdate(
        LocalRecordsCompanion.insert(
          homeId: _home,
          entityType: type,
          entityId: id,
          revision: const Value(1),
          payload: jsonEncode(value),
          updatedAt: DateTime.utc(2026, 10, 13),
          synchronizedAt: Value(DateTime.utc(2026, 10, 13)),
        ),
      );
}

Future<Map<String, Object?>> _payload(
  AppDatabase database,
  String type,
  String id,
) async {
  final row =
      await (database.select(database.localRecords)..where(
            (row) =>
                row.homeId.equals(_home) &
                row.entityType.equals(type) &
                row.entityId.equals(id),
          ))
          .getSingle();
  return (jsonDecode(row.payload) as Map).cast<String, Object?>();
}

Future<String> _stock(AppDatabase database) async =>
    (await _payload(database, 'inventory-balance', _product))['quantity']
        as String;
