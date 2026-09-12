import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/receipt_draft_editor.dart';

const _home = '01912345-6789-7abc-8def-0123456789ab';
const _otherHome = '01912345-6789-7abc-8def-1123456789ab';
const _device = '01912345-6789-7abc-8def-2123456789ab';

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;
  final at = DateTime.utc(2026, 9, 12);
  setUp(() {
    var nextId = 1;
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(
      database,
      deviceId: _device,
      idGenerator: () =>
          '01912345-6789-7abc-8def-${(nextId++).toString().padLeft(12, '0')}',
      clock: () => at,
    );
  });
  tearDown(() => database.close());

  Future<PurchaseReceiptCapture> draftWithLine() async {
    final result = await repository.createReceiptDraft(
      PurchaseReceiptDraftRequest(
        homeId: _home,
        purchaseDate: at,
        currency: 'NAD',
        notes: 'Original',
        sourceReference: 'ai-review-1',
      ),
    );
    await repository.addReceiptLine(
      PurchaseReceiptLineRequest(
        homeId: _home,
        receiptId: result.entityId,
        rawDescription: 'Rice',
        quantity: 1,
        lineTotal: Money(minorUnits: 1000, currency: 'NAD'),
      ),
    );
    return (await repository.watchActiveReceiptCapture(homeId: _home).first)!;
  }

  test(
    'draft edits retain identity and source, reset review, and persist ordered revision-bound commands',
    () async {
      var capture = await draftWithLine();
      final original = capture.lines.single;
      await repository.markReceiptLineUnresolved(
        homeId: _home,
        receiptId: capture.id,
        lineId: original.id,
      );
      capture = (await repository
          .watchActiveReceiptCapture(homeId: _home)
          .first)!;
      await repository.updateReceiptDraftLine(
        lineId: original.id,
        expectedRevision: 2,
        line: PurchaseReceiptLineRequest(
          homeId: _home,
          receiptId: capture.id,
          rawDescription: 'Brown rice',
          quantity: 2,
          originalPackText: '500 g',
          unitPrice: Money(minorUnits: 800, currency: 'NAD'),
          lineTotal: Money(minorUnits: 1600, currency: 'NAD'),
        ),
      );
      capture = (await repository
          .watchActiveReceiptCapture(homeId: _home)
          .first)!;
      expect(
        capture.lines.single.approvalStatus,
        PurchaseLineApprovalStatus.unreviewed,
      );
      expect(capture.lines.single.homeProductId, isNull);
      expect(capture.reviewComplete, isFalse);
      await repository.updateReceiptDraft(
        receiptId: capture.id,
        expectedRevision: capture.revision,
        draft: PurchaseReceiptDraftRequest(
          homeId: _home,
          purchaseDate: DateTime.utc(2026, 9, 11),
          currency: 'NAD',
          total: Money(minorUnits: 1600, currency: 'NAD'),
          notes: 'Corrected',
        ),
      );
      final restarted = DriftHouseholdRepository(database, deviceId: _device);
      capture = (await restarted
          .watchActiveReceiptCapture(homeId: _home)
          .first)!;
      expect(capture.id, original.receiptId);
      expect(capture.sourceReference, 'ai-review-1');
      expect(capture.notes, 'Corrected');
      expect(capture.revision, 5);
      expect(capture.lines.single.rawDescription, 'Brown rice');
      expect(capture.lines.single.quantity, 2);
      expect(capture.lines.single.revision, 3);
      expect(capture.lines.single.lineTotal!.minorUnits, 1600);
      final operations = await database.select(database.clientOperations).get();
      expect(operations.map((row) => row.operationType), [
        'purchasing.receipt.create',
        'purchasing.receipt-line.create',
        'purchasing.receipt-line.unresolve',
        'purchasing.receipt-line.update',
        'purchasing.receipt.update',
      ]);
      expect(operations.map((row) => row.baseRevision), [null, 1, 1, 2, 4]);
      expect(jsonDecode(operations.last.payload), {
        'storeId': null,
        'purchaseDate': '2026-09-11',
        'currency': 'NAD',
        'totalAmount': '16',
        'notes': 'Corrected',
      });
    },
  );

  test(
    'removed lines remain durable but cannot be reviewed or committed; cancellation records no purchases',
    () async {
      final capture = await draftWithLine();
      final line = capture.lines.single;
      await repository.removeReceiptDraftLine(
        homeId: _home,
        receiptId: capture.id,
        lineId: line.id,
        expectedRevision: line.revision,
      );
      final removed = (await repository
          .watchActiveReceiptCapture(homeId: _home)
          .first)!;
      expect(removed.lines, isEmpty);
      expect(removed.revision, 3);
      final rows = await database.select(database.localRecords).get();
      expect(
        (jsonDecode(rows.singleWhere((row) => row.entityId == line.id).payload)
            as Map<String, Object?>)['approvalStatus'],
        'removed',
      );
      await expectLater(
        repository.commitReceipt(homeId: _home, receiptId: capture.id),
        throwsA(isA<PurchaseCaptureException>()),
      );
      await expectLater(
        repository.markReceiptLineUnresolved(
          homeId: _home,
          receiptId: capture.id,
          lineId: line.id,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      await repository.cancelReceiptDraft(
        homeId: _home,
        receiptId: capture.id,
        expectedRevision: removed.revision,
      );
      expect(
        await repository.watchActiveReceiptCapture(homeId: _home).first,
        isNull,
      );
      expect(await repository.watchPurchaseLines(homeId: _home).first, isEmpty);
      expect(
        await repository.watchPriceObservations(homeId: _home).first,
        isEmpty,
      );
      await expectLater(
        repository.updateReceiptDraft(
          receiptId: capture.id,
          expectedRevision: 4,
          draft: PurchaseReceiptDraftRequest(
            homeId: _home,
            purchaseDate: at,
            currency: 'NAD',
          ),
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      final operations = await database.select(database.clientOperations).get();
      expect(operations.last.operationType, 'purchasing.receipt.cancel');
      expect(operations.last.baseRevision, 3);
      expect(jsonDecode(operations.last.payload), isEmpty);
    },
  );

  test(
    'stale draft revisions and foreign-home edits leave projections and outbox unchanged',
    () async {
      final capture = await draftWithLine();
      final before =
          (await database.select(database.clientOperations).get()).length;
      for (final home in [_home, _otherHome]) {
        await expectLater(
          repository.updateReceiptDraft(
            receiptId: capture.id,
            expectedRevision: 1,
            draft: PurchaseReceiptDraftRequest(
              homeId: home,
              purchaseDate: at,
              currency: 'NAD',
              notes: 'Stale',
            ),
          ),
          throwsA(isA<PurchaseCaptureException>()),
        );
        await expectLater(
          repository.removeReceiptDraftLine(
            homeId: home,
            receiptId: capture.id,
            lineId: capture.lines.single.id,
            expectedRevision: 99,
          ),
          throwsA(isA<PurchaseCaptureException>()),
        );
      }
      expect(
        (await database.select(database.clientOperations).get()).length,
        before,
      );
      expect(
        (await repository.watchActiveReceiptCapture(homeId: _home).first)!
            .notes,
        'Original',
      );
    },
  );

  test(
    'commit excludes removed rows and then rejects draft maintenance',
    () async {
      var capture = await draftWithLine();
      final removedId = capture.lines.single.id;
      await repository.removeReceiptDraftLine(
        homeId: _home,
        receiptId: capture.id,
        lineId: removedId,
        expectedRevision: 1,
      );
      final kept = await repository.addReceiptLine(
        PurchaseReceiptLineRequest(
          homeId: _home,
          receiptId: capture.id,
          rawDescription: 'Kept line',
          quantity: 1,
          lineTotal: Money(minorUnits: 200, currency: 'NAD'),
        ),
      );
      await repository.markReceiptLineUnresolved(
        homeId: _home,
        receiptId: capture.id,
        lineId: kept.entityId,
      );
      await repository.commitReceipt(homeId: _home, receiptId: capture.id);
      capture = (await repository
          .watchActiveReceiptCapture(homeId: _home)
          .first)!;
      expect(capture.status, PurchaseReceiptStatus.committed);
      expect(
        (await repository.watchPurchaseLines(homeId: _home).first)
            .single
            .rawDescription,
        'Kept line',
      );
      await expectLater(
        repository.cancelReceiptDraft(
          homeId: _home,
          receiptId: capture.id,
          expectedRevision: capture.revision,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      await expectLater(
        repository.removeReceiptDraftLine(
          homeId: _home,
          receiptId: capture.id,
          lineId: kept.entityId,
          expectedRevision: 2,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
    },
  );

  testWidgets(
    'line edit form saves changed values through the durable repository',
    (tester) async {
      final capture = (await tester.runAsync(draftWithLine))!;
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptDraftEditor(
              controller: controller,
              receipt: capture,
              line: capture.lines.single,
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('receipt-edit-description')),
        'Edited rice',
      );
      await tester.enterText(
        find.byKey(const Key('receipt-edit-quantity')),
        '3',
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('receipt-edit-save')));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      final edited = (await tester.runAsync(
        () => repository.watchActiveReceiptCapture(homeId: _home).first,
      ))!.lines.single;
      expect(edited.rawDescription, 'Edited rice');
      expect(edited.quantity, 3);
      expect(edited.approvalStatus, PurchaseLineApprovalStatus.unreviewed);
    },
  );
}
