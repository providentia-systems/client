import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/purchasing/application/purchase_receipt_history.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/receipt_spend.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_workspace.dart';

const _home = '10000000-0000-4000-8000-000000000001';
const _device = '10000000-0000-4000-8000-000000000002';
const _product = '10000000-0000-4000-8000-000000000003';
const _receipt = '10000000-0000-4000-8000-000000000004';
const _line = '10000000-0000-4000-8000-000000000005';
const _pending = '10000000-0000-4000-8000-000000000006';
const _audit = '10000000-0000-4000-8000-000000000007';

void main() {
  late AppDatabase db;
  late DriftHouseholdRepository repository;
  final at = DateTime.utc(2026, 10, 20, 12);
  Future<void> seed(
    String type,
    String id,
    Map<String, Object?> fields, {
    int revision = 1,
  }) async => db
      .into(db.localRecords)
      .insertOnConflictUpdate(
        LocalRecordsCompanion.insert(
          homeId: _home,
          entityType: type,
          entityId: id,
          payload: jsonEncode(fields),
          revision: Value(revision),
          updatedAt: at,
          synchronizedAt: Value(at),
        ),
      );
  Future<Map<String, Object?>> row(String type, String id) async =>
      jsonDecode(
            (await (db.select(db.localRecords)..where(
                      (r) =>
                          r.homeId.equals(_home) &
                          r.entityType.equals(type) &
                          r.entityId.equals(id),
                    ))
                    .getSingle())
                .payload,
          )
          as Map<String, Object?>;
  Future<PurchaseReceiptCapture> capture() async =>
      (await repository.watchReceiptCaptures(homeId: _home).first).single;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(
      db,
      deviceId: _device,
      clock: () => at,
    );
    await seed('inventory-home-product', _product, {
      'privateName': 'Rice',
      'originalPackText': '1 kg',
      'unit': 'kg',
      'status': 'active',
    });
    await seed('inventory-balance', _product, {
      'homeProductId': _product,
      'quantity': '7',
    });
    await seed('purchasing-receipt', _receipt, {
      'status': 'committed',
      'purchaseDate': '2026-10-01',
      'currency': 'NAD',
      'totalAmount': '50.00',
      'notes': '',
      'lineCorrectionState': 'available',
      'createdAt': '2026-10-02T08:00:00Z',
    }, revision: 8);
    await seed('purchasing-receipt-line', _line, {
      'receiptId': _receipt,
      'rawDescription': 'Recorded rice',
      'quantity': '5',
      'approvalStatus': 'approved',
      'homeProductId': _product,
      'stockQuantity': '5',
      'stockQuantityPerPack': '1',
      'stockUnit': 'kg',
      'lineTotal': '50.00',
    });
    await seed('purchasing-receipt-line', _pending, {
      'receiptId': _receipt,
      'rawDescription': 'Unpriced pending rice',
      'quantity': '3',
      'approvalStatus': 'unresolved',
      'homeProductId': null,
      'unitPrice': null,
      'lineTotal': null,
    }, revision: 2);
  });
  tearDown(() => db.close());

  test(
    'finished cancellation reverses only applied stock once and retains discoverable context',
    () async {
      await repository.cancelReceiptDraft(
        homeId: _home,
        receiptId: _receipt,
        expectedRevision: 8,
      );
      expect((await row('inventory-balance', _product))['quantity'], '2');
      var saved = await capture();
      expect(saved.status, PurchaseReceiptStatus.cancelled);
      expect(saved.cancellationConfirmed, isFalse);
      expect(saved.lines.single.id, _pending);
      expect(saved.removedLines.single.id, _line);
      expect(saved.removedLines.single.stockQuantity, '0');
      expect(saved.createdAt, DateTime.utc(2026, 10, 2, 8));
      expect(saved.auditEntries.single.kind, 'Receipt cancellation');
      expect(
        saved.auditEntries.single.state,
        PurchaseReceiptAuditState.pending,
      );
      expect(
        ReceiptSpendSummary.fromReceipts(
          homeId: _home,
          receipts: [saved],
        ).receiptCount,
        0,
      );
      expect(
        await repository.watchActiveReceiptCapture(homeId: _home).first,
        isNull,
      );
      final operation = await db.select(db.clientOperations).getSingle();
      expect(operation.operationType, 'purchasing.receipt.cancel');
      expect(jsonDecode(operation.payload), isEmpty);
      repository = DriftHouseholdRepository(db, deviceId: _device);
      final repeated = await repository.cancelReceiptDraft(
        homeId: _home,
        receiptId: _receipt,
        expectedRevision: 8,
      );
      expect(repeated.disposition, PurchaseMutationDisposition.alreadyQueued);
      expect((await row('inventory-balance', _product))['quantity'], '2');
      expect(
        (await db.select(db.clientOperations).getSingle()).operationId,
        operation.operationId,
      );
      final local = DriftLocalSyncRepository(db);
      await local.applyPushResults(
        results: [
          PushOperationResult(
            operationId: operation.operationId,
            kind: PushResultKind.acknowledged,
            acceptedRevision: 9,
          ),
        ],
        now: at,
        retryPolicy: RetryPolicy(),
      );
      saved = await capture();
      expect(saved.cancellationConfirmed, isTrue);
      expect(saved.synchronizationState, PurchaseSynchronizationState.pending);
      await local.applyPullPage(
        homeId: _home,
        page: PullPage(
          protocolVersion: 1,
          fromCursor: null,
          pageCursor: 'cancel-readback',
          highWaterCursor: 'cancel-readback',
          hasMore: false,
          requestId: _device,
          changes: [
            for (final value in [
              (
                'purchasing-receipt',
                _receipt,
                9,
                await row('purchasing-receipt', _receipt),
              ),
              (
                'purchasing-receipt-line',
                _line,
                2,
                await row('purchasing-receipt-line', _line),
              ),
              (
                'inventory-balance',
                _product,
                2,
                {'homeProductId': _product, 'quantity': '2'},
              ),
            ])
              RemoteChange(
                cursor: 'cancel-readback',
                homeId: _home,
                entityType: value.$1,
                entityId: value.$2,
                revision: value.$3,
                kind: RemoteChangeKind.upsert,
                serverTimestamp: at,
                payload: value.$4,
              ),
          ],
        ),
      );
      saved = await capture();
      expect(
        saved.synchronizationState,
        PurchaseSynchronizationState.synchronized,
      );
      expect(saved.removedLines.single.rawDescription, 'Recorded rice');
      expect((await row('inventory-balance', _product))['quantity'], '2');
    },
  );

  test(
    'cancellation conflict or unconfirmed stock cannot mutate receipt or stock',
    () async {
      final before = await row('purchasing-receipt', _receipt);
      await expectLater(
        repository.cancelReceiptDraft(
          homeId: _home,
          receiptId: _receipt,
          expectedRevision: 7,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      await seed('purchasing-receipt-line', _pending, {
        'receiptId': _receipt,
        'rawDescription': 'Unconfirmed rice',
        'quantity': '3',
        'approvalStatus': 'approved',
        'homeProductId': _product,
        'stockQuantityPerPack': '1',
        'stockUnit': 'kg',
      }, revision: 2);
      await expectLater(
        repository.cancelReceiptDraft(
          homeId: _home,
          receiptId: _receipt,
          expectedRevision: 8,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect(await row('purchasing-receipt', _receipt), before);
      expect((await row('inventory-balance', _product))['quantity'], '7');
      expect(await db.select(db.clientOperations).get(), isEmpty);
    },
  );

  test(
    'unpriced unresolved text edit and removal preserve no-stock semantics',
    () async {
      await repository.updateReceiptDraftLine(
        lineId: _pending,
        expectedRevision: 2,
        line: PurchaseReceiptLineRequest(
          homeId: _home,
          receiptId: _receipt,
          rawDescription: 'Clarified unpriced rice',
          quantity: 3,
          allowUnknownPrice: true,
        ),
      );
      var saved = await capture();
      expect(
        saved.lines.firstWhere((line) => line.id == _pending).unresolved,
        isTrue,
      );
      expect(
        saved.lines.firstWhere((line) => line.id == _pending).lineTotal,
        isNull,
      );
      expect((await row('inventory-balance', _product))['quantity'], '7');
      await repository.removeReceiptDraftLine(
        homeId: _home,
        receiptId: _receipt,
        lineId: _pending,
        expectedRevision: 3,
      );
      saved = await capture();
      expect(saved.removedLines.single.id, _pending);
      expect(saved.removedLines.single.stockApplied, isFalse);
      expect((await row('inventory-balance', _product))['quantity'], '7');
      expect(
        (await db.select(db.clientOperations).get()).map(
          (op) => op.operationType,
        ),
        ['purchasing.receipt-line.update', 'purchasing.receipt-line.remove'],
      );
    },
  );

  test(
    'unknown-price edit does not weaken ordinary draft or applied line validation',
    () async {
      expect(
        () => PurchaseReceiptLineRequest(
          homeId: _home,
          receiptId: _receipt,
          rawDescription: 'Unpriced ordinary entry',
          quantity: 1,
        ),
        throwsArgumentError,
      );
      final request = PurchaseReceiptLineRequest(
        homeId: _home,
        receiptId: _receipt,
        rawDescription: 'No price',
        quantity: 1,
        allowUnknownPrice: true,
      );
      await expectLater(
        repository.updateReceiptDraftLine(
          lineId: _line,
          expectedRevision: 1,
          line: request,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      await expectLater(
        repository.addReceiptLine(request),
        throwsA(isA<PurchaseCaptureException>()),
      );
      await expectLater(
        repository.addPurchasedReceiptLine(
          line: request,
          homeProductId: _product,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect((await row('inventory-balance', _product))['quantity'], '7');
      expect(await db.select(db.clientOperations).get(), isEmpty);
    },
  );

  test(
    'last line removal preserves header, historical lock and retained detail',
    () async {
      await repository.removeReceiptDraftLine(
        homeId: _home,
        receiptId: _receipt,
        lineId: _pending,
        expectedRevision: 2,
      );
      await repository.removeReceiptDraftLine(
        homeId: _home,
        receiptId: _receipt,
        lineId: _line,
        expectedRevision: 1,
      );
      final saved = await capture();
      expect(saved.status, PurchaseReceiptStatus.committed);
      expect(saved.lines, isEmpty);
      expect(saved.removedLines, hasLength(2));
      expect(saved.emptyAfterCorrection, isTrue);
      expect(saved.purchaseBasisFixed, isTrue);
      expect(saved.total!.minorUnits, 5000);
      expect((await row('inventory-balance', _product))['quantity'], '2');
      expect(
        ReceiptSpendSummary.fromReceipts(
          homeId: _home,
          receipts: [saved],
        ).singleCurrencyAmount!.minorUnits,
        5000,
      );
    },
  );

  test(
    'creation timestamp and correction audits survive mutable header readback',
    () async {
      final reader = _HistoryReader(createdAt: DateTime.utc(2026, 10, 2, 8));
      repository = DriftHouseholdRepository(
        db,
        deviceId: _device,
        receiptHistoryReader: reader,
      );
      await repository.refreshReceiptHistory(
        homeId: _home,
        receiptId: _receipt,
      );
      var saved = await capture();
      expect(saved.createdAt, reader.createdAt);
      expect(saved.auditEntries.single.id, _audit);
      final header = await row('purchasing-receipt', _receipt);
      header.remove('createdAt');
      await seed('purchasing-receipt', _receipt, header, revision: 8);
      repository = DriftHouseholdRepository(
        db,
        deviceId: _device,
        receiptHistoryReader: _HistoryReader(
          createdAt: DateTime.utc(2026, 10, 3, 8),
        ),
      );
      await expectLater(
        repository.refreshReceiptHistory(homeId: _home, receiptId: _receipt),
        throwsA(isA<PurchaseReceiptHistoryException>()),
      );
      saved = await capture();
      expect(saved.createdAt, DateTime.utc(2026, 10, 2, 8));
      expect(saved.auditEntries.single.reason, 'Correct purchase day');
      expect(await db.select(db.clientOperations).get(), isEmpty);
    },
  );

  testWidgets(
    'unpriced finished line editor saves text without fabricating price',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('purchase-edit-line-$_pending')),
      );
      await tester.tap(find.byKey(const Key('purchase-edit-line-$_pending')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('receipt-edit-description')),
        'Retained unknown-price description',
      );
      await tester.ensureVisible(find.byKey(const Key('receipt-edit-save')));
      await tester.tap(find.byKey(const Key('receipt-edit-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-edit-error')), findsNothing);
      expect(
        (await row('purchasing-receipt-line', _pending))['rawDescription'],
        'Retained unknown-price description',
      );
      expect(
        (await row('purchasing-receipt-line', _pending))['unitPrice'],
        isNull,
      );
      expect((await row('inventory-balance', _product))['quantity'], '7');
    },
  );

  testWidgets(
    'finished cancellation confirms consequences and remains visible as pending',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('purchase-cancel-receipt')),
      );
      await tester.tap(find.byKey(const Key('purchase-cancel-receipt')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Every remaining stock-applied line is reversed exactly once',
        ),
        findsOneWidget,
      );
      expect(await db.select(db.clientOperations).get(), isEmpty);
      await tester.tap(find.byKey(const Key('purchase-confirm-removal')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Cancellation queued; awaiting server confirmation',
        ),
        findsWidgets,
      );
      expect(find.byKey(const Key('purchase-add-omitted-line')), findsNothing);
      expect((await row('inventory-balance', _product))['quantity'], '2');
      expect(
        find.byKey(const Key('receipt-removed-line-$_line')),
        findsOneWidget,
      );
      expect(find.text('Unpriced pending rice'), findsOneWidget);
    },
  );
  testWidgets(
    'older purchase day is explicit at creation and survives repository restart',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('purchase-another-receipt')),
      );
      await tester.tap(find.byKey(const Key('purchase-another-receipt')));
      await tester.pumpAndSettle();
      final initialDay = tester
          .widget<TextField>(find.byKey(const Key('purchase-receipt-date')))
          .controller!
          .text;
      final today = DateTime.now();
      expect(
        initialDay,
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
      );
      await tester.enterText(
        find.byKey(const Key('purchase-receipt-date')),
        '2020-12-31',
      );
      await tester.ensureVisible(
        find.byKey(const Key('purchase-create-draft')),
      );
      await tester.tap(find.byKey(const Key('purchase-create-draft')));
      await tester.pumpAndSettle();
      final selected = controller.state.capture!;
      expect(selected.id, isNot(_receipt));
      expect(selected.purchaseDate, DateTime.utc(2020, 12, 31));
      expect(selected.recordedAt, at);
      repository = DriftHouseholdRepository(db, deviceId: _device);
      final restored = (await tester.runAsync(
        () => repository.watchReceiptCaptures(homeId: _home).first,
      ))!.firstWhere((receipt) => receipt.id == selected.id);
      expect(restored.purchaseDate, DateTime.utc(2020, 12, 31));
      expect(restored.recordedAt, at);
      expect((await row('inventory-balance', _product))['quantity'], '7');
    },
  );

  testWidgets(
    'audited date dialog requires reason and preserves immutable creation and stock',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('purchase-correct-date')),
      );
      await tester.tap(find.byKey(const Key('purchase-correct-date')));
      await tester.pumpAndSettle();
      expect(find.text('Existing purchase day: 2026-10-01'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('receipt-correction-date')),
        '2026-09-30',
      );
      await tester.tap(find.byKey(const Key('receipt-correction-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Give the reason for changing this purchase day.'),
        findsOneWidget,
      );
      expect(await db.select(db.clientOperations).get(), isEmpty);
      await tester.enterText(
        find.byKey(const Key('receipt-correction-reason')),
        'Correct original receipt day',
      );
      await tester.tap(find.byKey(const Key('receipt-correction-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-correction-error')), findsNothing);
      expect(controller.state.capture!.purchaseDate, DateTime.utc(2026, 9, 30));
      expect(controller.state.capture!.createdAt, DateTime.utc(2026, 10, 2, 8));
      expect(
        controller.state.capture!.auditEntries.single.state,
        PurchaseReceiptAuditState.pending,
      );
      expect((await row('inventory-balance', _product))['quantity'], '7');
      final op = await db.select(db.clientOperations).getSingle();
      expect(op.operationType, 'purchasing.receipt.correct-date');
      expect(op.baseRevision, 8);
    },
  );

  testWidgets(
    'date correction conflict retains typed day and reason without resubmitting',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('purchase-correct-date')),
      );
      await tester.tap(find.byKey(const Key('purchase-correct-date')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('receipt-correction-date')),
        '2026-09-29',
      );
      await tester.enterText(
        find.byKey(const Key('receipt-correction-reason')),
        'My retained reason',
      );
      await seed(
        'purchasing-receipt',
        _receipt,
        await row('purchasing-receipt', _receipt),
        revision: 9,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('receipt-correction-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('receipt-correction-error')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('receipt-correction-date')),
            )
            .controller!
            .text,
        '2026-09-29',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('receipt-correction-reason')),
            )
            .controller!
            .text,
        'My retained reason',
      );
      expect(await db.select(db.clientOperations).get(), isEmpty);
      expect((await row('inventory-balance', _product))['quantity'], '7');
    },
  );

  testWidgets(
    'removed applied history keeps ordinary date and currency locked with audited action available',
    (tester) async {
      await repository.removeReceiptDraftLine(
        homeId: _home,
        receiptId: _receipt,
        lineId: _line,
        expectedRevision: 1,
      );
      final header = await row('purchasing-receipt', _receipt);
      header['status'] = 'draft';
      await seed('purchasing-receipt', _receipt, header, revision: 9);
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        controller.state.capture!.lines.every((line) => !line.stockApplied),
        isTrue,
      );
      expect(controller.state.capture!.purchaseBasisFixed, isTrue);
      expect(find.byKey(const Key('purchase-correct-date')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('purchase-edit-receipt')),
      );
      await tester.tap(find.byKey(const Key('purchase-edit-receipt')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('receipt-edit-date')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('receipt-edit-currency')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
    },
  );
  test(
    'first history refresh cannot replace an existing immutable header creation time',
    () async {
      repository = DriftHouseholdRepository(
        db,
        deviceId: _device,
        receiptHistoryReader: _HistoryReader(
          createdAt: DateTime.utc(2026, 10, 3, 8),
        ),
      );
      await expectLater(
        repository.refreshReceiptHistory(homeId: _home, receiptId: _receipt),
        throwsA(isA<PurchaseReceiptHistoryException>()),
      );
      expect((await capture()).createdAt, DateTime.utc(2026, 10, 2, 8));
      expect((await capture()).auditEntries, isEmpty);
    },
  );

  test(
    'backend UTC SQL creation timestamp remains UTC in every host timezone',
    () async {
      final header = await row('purchasing-receipt', _receipt);
      header['createdAt'] = '2026-10-02 08:00:00.000000';
      await seed('purchasing-receipt', _receipt, header, revision: 8);
      expect((await capture()).createdAt, DateTime.utc(2026, 10, 2, 8));
      repository = DriftHouseholdRepository(
        db,
        deviceId: _device,
        receiptHistoryReader: _HistoryReader(
          createdAt: DateTime.utc(2026, 10, 2, 8),
        ),
      );
      await repository.refreshReceiptHistory(
        homeId: _home,
        receiptId: _receipt,
      );
      expect((await capture()).createdAt, DateTime.utc(2026, 10, 2, 8));
    },
  );

  test(
    'stale empty history merges accepted audits and changed immutable audit is rejected',
    () async {
      repository = DriftHouseholdRepository(
        db,
        deviceId: _device,
        receiptHistoryReader: _HistoryReader(
          createdAt: DateTime.utc(2026, 10, 2, 8),
        ),
      );
      await repository.refreshReceiptHistory(
        homeId: _home,
        receiptId: _receipt,
      );
      repository = DriftHouseholdRepository(
        db,
        deviceId: _device,
        receiptHistoryReader: _HistoryReader(
          createdAt: DateTime.utc(2026, 10, 2, 8),
          includeEntries: false,
        ),
      );
      await repository.refreshReceiptHistory(
        homeId: _home,
        receiptId: _receipt,
      );
      expect(
        (await capture()).auditEntries.single.reason,
        'Correct purchase day',
      );
      repository = DriftHouseholdRepository(
        db,
        deviceId: _device,
        receiptHistoryReader: _HistoryReader(
          createdAt: DateTime.utc(2026, 10, 2, 8),
          reason: 'Changed immutable reason',
        ),
      );
      await expectLater(
        repository.refreshReceiptHistory(homeId: _home, receiptId: _receipt),
        throwsA(isA<PurchaseReceiptHistoryException>()),
      );
      expect(
        (await capture()).auditEntries.single.reason,
        'Correct purchase day',
      );
    },
  );

  test(
    'binding change before final commit rolls cancellation and line removal back atomically',
    () async {
      final originalHeader = await row('purchasing-receipt', _receipt);
      final originalLine = await row('purchasing-receipt-line', _line);
      for (final cancel in [true, false]) {
        var checks = 0;
        repository = DriftHouseholdRepository(
          db,
          deviceId: _device,
          isCurrent: () => ++checks < 3,
        );
        await expectLater(
          cancel
              ? repository.cancelReceiptDraft(
                  homeId: _home,
                  receiptId: _receipt,
                  expectedRevision: 8,
                )
              : repository.removeReceiptDraftLine(
                  homeId: _home,
                  receiptId: _receipt,
                  lineId: _line,
                  expectedRevision: 1,
                ),
          throwsA(isA<AuthenticationSyncException>()),
        );
        expect(checks, 3);
        expect(await row('purchasing-receipt', _receipt), originalHeader);
        expect(await row('purchasing-receipt-line', _line), originalLine);
        expect((await row('inventory-balance', _product))['quantity'], '7');
        expect(await db.select(db.clientOperations).get(), isEmpty);
      }
    },
  );

  test(
    'removing consumed historical purchase preserves signed ledger without a physical count',
    () async {
      await seed('inventory-balance', _product, {
        'homeProductId': _product,
        'quantity': '0',
      });
      final original = await row('purchasing-receipt-line', _line);
      await seed('purchasing-receipt-line', _line, {
        ...original,
        'quantity': '3',
        'stockQuantity': '3',
      });
      await repository.removeReceiptDraftLine(
        homeId: _home,
        receiptId: _receipt,
        lineId: _line,
        expectedRevision: 1,
      );
      final balance = await row('inventory-balance', _product);
      expect(balance['quantity'], '-3');
      expect(balance['uncertain'], isTrue);
      expect((await capture()).removedLines.single.quantityText, '3');
      expect(
        (await db.select(db.clientOperations).getSingle()).operationType,
        'purchasing.receipt-line.remove',
      );
      expect(
        await (db.select(
          db.localRecords,
        )..where((r) => r.entityType.equals('inventory-count-line'))).get(),
        isEmpty,
      );
    },
  );

  test(
    'whole cancellation after consumption retains negative ledger and never reverses twice',
    () async {
      await seed('inventory-balance', _product, {
        'homeProductId': _product,
        'quantity': '2',
      });
      await repository.cancelReceiptDraft(
        homeId: _home,
        receiptId: _receipt,
        expectedRevision: 8,
      );
      expect((await row('inventory-balance', _product))['quantity'], '-3');
      await repository.cancelReceiptDraft(
        homeId: _home,
        receiptId: _receipt,
        expectedRevision: 8,
      );
      expect((await row('inventory-balance', _product))['quantity'], '-3');
      expect(await db.select(db.clientOperations).get(), hasLength(1));
    },
  );

  test(
    'rejected cancellation stays failed in retained history rather than completed',
    () async {
      await repository.cancelReceiptDraft(
        homeId: _home,
        receiptId: _receipt,
        expectedRevision: 8,
      );
      final operation = await db.select(db.clientOperations).getSingle();
      await DriftLocalSyncRepository(db).applyPushResults(
        results: [
          PushOperationResult(
            operationId: operation.operationId,
            kind: PushResultKind.authorizationFailure,
            safeMessage: 'Review purchase permission before retry',
          ),
        ],
        now: at,
        retryPolicy: RetryPolicy(),
      );
      final saved = await capture();
      expect(saved.cancellationConfirmed, isFalse);
      expect(saved.synchronizationState, PurchaseSynchronizationState.pending);
      expect(saved.auditEntries.single.state, PurchaseReceiptAuditState.failed);
      expect(
        saved.auditEntries.single.safeFailure,
        'Review purchase permission before retry',
      );
      await expectLater(
        repository.cancelReceiptDraft(
          homeId: _home,
          receiptId: _receipt,
          expectedRevision: 8,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect((await row('inventory-balance', _product))['quantity'], '2');
      expect(await db.select(db.clientOperations).get(), hasLength(1));
    },
  );
}

final class _HistoryReader implements PurchaseReceiptHistoryReader {
  const _HistoryReader({
    required this.createdAt,
    this.includeEntries = true,
    this.reason = 'Correct purchase day',
  });
  final DateTime createdAt;
  final bool includeEntries;
  final String reason;
  @override
  Future<PurchaseReceiptHistorySnapshot> load({
    required String homeId,
    required String receiptId,
  }) async => PurchaseReceiptHistorySnapshot(
    homeId: homeId,
    receiptId: receiptId,
    createdAt: createdAt,
    entries: [
      if (includeEntries)
        PurchaseReceiptAuditEntry(
          id: _audit,
          kind: 'Purchase day correction',
          reason: reason,
          at: DateTime.utc(2026, 10, 3),
          state: PurchaseReceiptAuditState.accepted,
          originalPurchaseDay: '2026-10-02',
          purchaseDay: '2026-10-01',
        ),
    ],
  );
}
