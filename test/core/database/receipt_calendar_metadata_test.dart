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
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/receipt_draft_editor.dart';

const _home = '10000000-0000-4000-8000-000000000011';
const _device = '10000000-0000-4000-8000-000000000012';
const _receipt = '10000000-0000-4000-8000-000000000013';
const _product = '10000000-0000-4000-8000-000000000014';
const _line = '10000000-0000-4000-8000-000000000015';
const _store = '10000000-0000-4000-8000-000000000016';
const _otherStore = '10000000-0000-4000-8000-000000000017';

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;
  final at = DateTime.utc(2026, 10, 26);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(database, deviceId: _device);
  });
  tearDown(() => database.close());

  Future<void> seed(
    String type,
    String id,
    Map<String, Object?> fields, {
    int revision = 1,
  }) async {
    await database
        .into(database.localRecords)
        .insertOnConflictUpdate(
          LocalRecordsCompanion.insert(
            homeId: _home,
            entityType: type,
            entityId: id,
            revision: Value(revision),
            payload: jsonEncode(fields),
            updatedAt: at,
            synchronizedAt: Value(at),
          ),
        );
  }

  Future<Map<String, Object?>> row(String type, String id) async {
    final record =
        await (database.select(database.localRecords)..where(
              (r) =>
                  r.homeId.equals(_home) &
                  r.entityType.equals(type) &
                  r.entityId.equals(id),
            ))
            .getSingle();
    return jsonDecode(record.payload) as Map<String, Object?>;
  }

  Future<void> seedReceipt(String state, String day) async {
    for (final store in [
      (_store, 'Original shop'),
      (_otherStore, 'Other shop'),
    ]) {
      await seed('purchasing-store', store.$1, {
        'name': store.$2,
        'location': '',
        'status': 'active',
      });
    }
    await seed('inventory-home-product', _product, {
      'privateName': 'Rice',
      'status': 'active',
      'unit': 'kg',
    });
    await seed('inventory-balance', _product, {
      'homeProductId': _product,
      'quantity': '4',
    });
    await seed('purchasing-receipt', _receipt, {
      'status': state == 'committed' ? 'committed' : 'draft',
      'purchaseDate': day,
      'currency': 'NAD',
      'storeId': _store,
      'totalAmount': '10.00',
      'notes': 'Original notes',
      'lineCorrectionState': state == 'committed' ? 'available' : 'draft',
    }, revision: 4);
    if (state != 'draft') {
      await seed('purchasing-receipt-line', _line, {
        'receiptId': _receipt,
        'rawDescription': 'Rice',
        'quantity': '2',
        'approvalStatus': 'approved',
        'homeProductId': _product,
        'stockQuantity': '2',
        'stockQuantityPerPack': '1',
        'stockUnit': 'kg',
        'lineTotal': '10.00',
      });
    }
  }

  for (final scenario in [
    ('draft', '2026-01-01'),
    ('applied', '2026-03-01'),
    ('committed', '2026-12-31'),
  ]) {
    for (final change in ['total', 'store', 'notes', 'combined']) {
      testWidgets(
        '${scenario.$1} $change metadata retains calendar ${scenario.$2} at local UTC offset ${DateTime(2026, 1, 1).timeZoneOffset.inMinutes} minutes',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(900, 1400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.runAsync(() => seedReceipt(scenario.$1, scenario.$2));
          final beforeBalance = await row('inventory-balance', _product);
          final beforeLine = scenario.$1 == 'draft'
              ? null
              : await row('purchasing-receipt-line', _line);
          final controller = PurchasingController(
            repository: repository,
            homeId: _home,
            mayWrite: true,
          );
          addTearDown(controller.dispose);
          controller.start();
          await tester.pumpAndSettle();
          final opened = (await tester.runAsync(
            () => repository.watchReceiptCaptures(homeId: _home).first,
          ))!.single;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ReceiptDraftEditor(
                  controller: controller,
                  receipt: opened,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (change == 'total' || change == 'combined') {
            await tester.enterText(
              find.byKey(const Key('receipt-edit-total')),
              '12.34',
            );
          }
          if (change == 'notes' || change == 'combined') {
            await tester.enterText(
              find.byKey(const Key('receipt-edit-notes')),
              'Changed notes',
            );
          }
          if (change == 'store' || change == 'combined') {
            await tester.tap(find.byKey(const Key('receipt-edit-store')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Other shop').last);
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(
            find.byKey(const Key('receipt-edit-save')),
          );
          await tester.tap(find.byKey(const Key('receipt-edit-save')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('receipt-edit-error')), findsNothing);
          final saved = await row('purchasing-receipt', _receipt);
          expect(saved['purchaseDate'], scenario.$2);
          expect(saved['currency'], 'NAD');
          expect(
            saved['totalAmount'],
            change == 'total' || change == 'combined' ? '12.34' : '10',
          );
          expect(
            saved['notes'],
            change == 'notes' || change == 'combined'
                ? 'Changed notes'
                : 'Original notes',
          );
          expect(
            saved['storeId'],
            change == 'store' || change == 'combined' ? _otherStore : _store,
          );
          expect(await row('inventory-balance', _product), beforeBalance);
          if (beforeLine != null) {
            expect(await row('purchasing-receipt-line', _line), beforeLine);
          }
          final operations = await database
              .select(database.clientOperations)
              .get();
          expect(operations, hasLength(1));
          expect(operations.single.operationType, 'purchasing.receipt.update');
          expect(operations.single.baseRevision, 4);
          expect(
            jsonDecode(operations.single.payload),
            containsPair('purchaseDate', scenario.$2),
          );
        },
      );
    }
  }

  test(
    'local midnight creation and repeated unlocked saves retain year boundary',
    () async {
      final created = await repository.createReceiptDraft(
        PurchaseReceiptDraftRequest(
          homeId: _home,
          purchaseDate: DateTime(2026, 1, 1),
          currency: 'NAD',
        ),
      );
      for (var revision = 1; revision <= 3; revision++) {
        final reopened =
            (await repository.watchReceiptCaptures(homeId: _home).first).single;
        expect(reopened.purchaseDate, DateTime.utc(2026, 1, 1));
        await repository.updateReceiptDraft(
          receiptId: created.entityId,
          expectedRevision: revision,
          draft: PurchaseReceiptDraftRequest(
            homeId: _home,
            purchaseDate: DateTime(2026, 1, 1),
            currency: 'NAD',
            notes: 'Save $revision',
          ),
        );
        expect(
          (await row('purchasing-receipt', created.entityId))['purchaseDate'],
          '2026-01-01',
        );
      }
      final operations = await database.select(database.clientOperations).get();
      expect(
        operations.every(
          (op) =>
              (jsonDecode(op.payload) as Map)['purchaseDate'] == '2026-01-01',
        ),
        isTrue,
      );
    },
  );

  test(
    'legacy cached ISO day normalizes without UTC conversion or guard bypass',
    () async {
      await seedReceipt('committed', '2026-12-31T00:00:00.000+02:00');
      final reopened =
          (await repository.watchReceiptCaptures(homeId: _home).first).single;
      expect(reopened.purchaseDate, DateTime.utc(2026, 12, 31));
      await repository.updateReceiptDraft(
        receiptId: _receipt,
        expectedRevision: 4,
        draft: PurchaseReceiptDraftRequest(
          homeId: _home,
          purchaseDate: DateTime(2026, 12, 31),
          currency: 'NAD',
          storeId: _store,
          notes: 'Metadata only',
        ),
      );
      expect(
        (await row('purchasing-receipt', _receipt))['purchaseDate'],
        '2026-12-31',
      );
      final before = await row('purchasing-receipt', _receipt);
      await expectLater(
        repository.updateReceiptDraft(
          receiptId: _receipt,
          expectedRevision: 5,
          draft: PurchaseReceiptDraftRequest(
            homeId: _home,
            purchaseDate: DateTime(2027, 1, 1),
            currency: 'NAD',
            storeId: _store,
          ),
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect(await row('purchasing-receipt', _receipt), before);
      expect(
        await database.select(database.clientOperations).get(),
        hasLength(1),
      );
    },
  );

  test(
    'audited purchase-day correction queues exact intent without replaying stock',
    () async {
      await seedReceipt('committed', '2026-01-01');
      final originalLine = await row('purchasing-receipt-line', _line);
      await repository.correctReceiptPurchaseDate(
        homeId: _home,
        receiptId: _receipt,
        expectedRevision: 4,
        purchaseDate: DateTime(2025, 12, 31),
        reason: 'Correct receipt day',
      );
      final saved = await row('purchasing-receipt', _receipt);
      expect(saved['purchaseDate'], '2025-12-31');
      expect(saved['status'], 'committed');
      expect(saved['currency'], 'NAD');
      expect(await row('purchasing-receipt-line', _line), originalLine);
      final balance = await row('inventory-balance', _product);
      expect(balance['quantity'], '4');
      expect(balance['uncertain'], isTrue);
      expect(
        balance['limitations'],
        contains('Purchase day correction awaits authoritative stock readback'),
      );
      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(operation.operationType, 'purchasing.receipt.correct-date');
      expect(operation.entityId, _receipt);
      expect(operation.deviceId, _device);
      expect(operation.baseRevision, 4);
      expect(jsonDecode(operation.payload), {
        'purchaseDate': '2025-12-31',
        'reason': 'Correct receipt day',
      });
      final restarted = DriftHouseholdRepository(database, deviceId: _device);
      await expectLater(
        restarted.correctReceiptPurchaseDate(
          homeId: _home,
          receiptId: _receipt,
          expectedRevision: 4,
          purchaseDate: DateTime(2025, 12, 31),
          reason: 'Correct receipt day',
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      final preserved = await database
          .select(database.clientOperations)
          .getSingle();
      expect(preserved.operationId, operation.operationId);
      expect(preserved.payload, operation.payload);
      expect((await row('inventory-balance', _product))['quantity'], '4');
      final local = DriftLocalSyncRepository(database);
      await local.applyPushResults(
        results: [
          PushOperationResult(
            operationId: operation.operationId,
            kind: PushResultKind.acknowledged,
            acceptedRevision: 5,
          ),
        ],
        now: at,
        retryPolicy: RetryPolicy(),
      );
      await local.applyPullPage(
        homeId: _home,
        page: PullPage(
          protocolVersion: 1,
          fromCursor: null,
          pageCursor: 'date-readback',
          highWaterCursor: 'date-readback',
          hasMore: false,
          requestId: _device,
          changes: [
            RemoteChange(
              cursor: 'date-readback',
              homeId: _home,
              entityType: 'purchasing-receipt',
              entityId: _receipt,
              kind: RemoteChangeKind.upsert,
              revision: 5,
              serverTimestamp: at,
              payload: {...saved, 'purchaseDate': '2025-12-31'},
            ),
            RemoteChange(
              cursor: 'date-readback',
              homeId: _home,
              entityType: 'inventory-balance',
              entityId: _product,
              kind: RemoteChangeKind.upsert,
              revision: 1,
              serverTimestamp: at,
              payload: {
                'homeProductId': _product,
                'quantity': '4',
                'uncertain': false,
                'limitations': <String>[],
              },
            ),
          ],
        ),
      );
      expect((await row('inventory-balance', _product))['quantity'], '4');
      expect((await row('inventory-balance', _product))['uncertain'], isFalse);
      expect(
        (await repository.watchReceiptCaptures(homeId: _home).first)
            .single
            .synchronizationState,
        PurchaseSynchronizationState.synchronized,
      );
      expect(
        (await database.select(database.clientOperations).getSingle()).payload,
        operation.payload,
      );
    },
  );
}
