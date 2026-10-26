import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/receipt_spend.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';

const _home = '01912345-6789-7abc-8def-0123456789ab';
const _receipt = '01912345-6789-7abc-8def-1123456789ab';
const _line = '01912345-6789-7abc-8def-2123456789ab';
const _device = '01912345-6789-7abc-8def-3123456789ab';
final _at = DateTime.utc(2026, 10, 26);

void main() {
  test(
    'local header edit, restart and authoritative refresh retain one receipt spend',
    () async {
      final directory = await Directory.systemTemp.createTemp('receipt-spend-');
      final file = File('${directory.path}/saved.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      try {
        var sync = DriftLocalSyncRepository(database, clock: () => _at);
        await sync.applyPullPage(
          homeId: _home,
          page: _page('initial', null, revision: 1, total: '10'),
        );
        var repository = DriftHouseholdRepository(
          database,
          deviceId: _device,
          clock: () => _at,
        );
        var receipt =
            (await repository.watchReceiptCaptures(homeId: _home).first).single;
        expect(
          ReceiptSpendAmount.fromReceipt(receipt).amount!.minorUnits,
          1000,
        );
        expect(
          ReceiptSpendAmount.fromReceipt(receipt).products.isComplete,
          isFalse,
        );
        await repository.updateReceiptDraft(
          receiptId: _receipt,
          expectedRevision: receipt.revision,
          draft: PurchaseReceiptDraftRequest(
            homeId: _home,
            purchaseDate: _at,
            currency: 'NAD',
            total: Money(minorUnits: 850, currency: 'NAD'),
          ),
        );
        receipt =
            (await repository.watchReceiptCaptures(homeId: _home).first).single;
        expect(ReceiptSpendAmount.fromReceipt(receipt).amount!.minorUnits, 850);
        final operation =
            (await database.select(database.clientOperations).get()).single;
        expect(operation.operationType, 'purchasing.receipt.update');
        final originalId = operation.operationId;
        final originalPayload = operation.payload;
        await database.close();
        database = AppDatabase(NativeDatabase(file));
        repository = DriftHouseholdRepository(
          database,
          deviceId: _device,
          clock: () => _at,
        );
        receipt =
            (await repository.watchReceiptCaptures(homeId: _home).first).single;
        expect(ReceiptSpendAmount.fromReceipt(receipt).amount!.minorUnits, 850);
        expect(
          receipt.synchronizationState,
          PurchaseSynchronizationState.pending,
        );
        final restored =
            (await database.select(database.clientOperations).get()).single;
        expect(restored.operationId, originalId);
        expect(restored.payload, originalPayload);
        sync = DriftLocalSyncRepository(database, clock: () => _at);
        await sync.applyPushResults(
          results: [
            PushOperationResult(
              operationId: originalId,
              kind: PushResultKind.acknowledged,
              acceptedRevision: 2,
            ),
          ],
          now: _at,
          retryPolicy: RetryPolicy(),
        );
        await sync.applyPullPage(
          homeId: _home,
          page: _page('readback', 'initial', revision: 2, total: '8.5'),
        );
        receipt =
            (await repository.watchReceiptCaptures(homeId: _home).first).single;
        expect(
          receipt.synchronizationState,
          PurchaseSynchronizationState.synchronized,
        );
        expect(
          ReceiptSpendSummary.fromReceipts(
            homeId: _home,
            receipts: [receipt],
          ).singleCurrencyAmount!.minorUnits,
          850,
        );
        expect(
          await database.select(database.clientOperations).get(),
          hasLength(1),
        );
        expect(
          (await database.select(database.localRecords).get()).where(
            (row) => row.entityType == 'inventory-balance',
          ),
          isEmpty,
        );
        await sync.applyPullPage(
          homeId: _home,
          page: _page(
            'cancelled',
            'readback',
            revision: 3,
            total: '8.5',
            cancelled: true,
          ),
        );
        final remaining = await repository
            .watchReceiptCaptures(homeId: _home)
            .first;
        expect(
          ReceiptSpendSummary.fromReceipts(
            homeId: _home,
            receipts: remaining,
          ).receiptCount,
          0,
        );
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('read-only controller receives header-only finished receipts', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final sync = DriftLocalSyncRepository(database, clock: () => _at);
    await sync.applyPullPage(
      homeId: _home,
      page: _page(
        'header-only',
        null,
        revision: 1,
        total: '7.5',
        withLine: false,
      ),
    );
    final repository = DriftHouseholdRepository(database);
    final controller = PurchasingController(
      repository: repository,
      homeId: _home,
    );
    final loaded = Completer<void>();
    controller.addListener(() {
      if (controller.receipts.isNotEmpty && !loaded.isCompleted) {
        loaded.complete();
      }
    });
    controller.start();
    try {
      await loaded.future.timeout(const Duration(seconds: 5));
      expect(controller.captureEnabled, isFalse);
      expect(controller.receipts, hasLength(1));
      expect(controller.recentGroups.single.lines, isEmpty);
      expect(controller.recentSpend!.minorUnits, 750);
    } finally {
      controller.dispose();
      await database.close();
    }
  });
}

PullPage _page(
  String cursor,
  String? from, {
  required int revision,
  required String total,
  bool cancelled = false,
  bool withLine = true,
}) => PullPage(
  protocolVersion: 1,
  fromCursor: from,
  pageCursor: cursor,
  highWaterCursor: cursor,
  hasMore: false,
  requestId: 'synthetic-spend-$cursor',
  changes: [
    RemoteChange(
      cursor: cursor,
      homeId: _home,
      entityType: 'purchasing-receipt',
      entityId: _receipt,
      kind: RemoteChangeKind.upsert,
      revision: revision,
      serverTimestamp: _at,
      payload: {
        'status': cancelled ? 'cancelled' : 'committed',
        'purchaseDate': '2026-10-26',
        'currency': 'NAD',
        'totalAmount': total,
        'storeId': null,
        'notes': '',
      },
    ),
    if (withLine)
      RemoteChange(
        cursor: cursor,
        homeId: _home,
        entityType: 'purchasing-receipt-line',
        entityId: _line,
        kind: RemoteChangeKind.upsert,
        revision: 1,
        serverTimestamp: _at,
        payload: const {
          'receiptId': _receipt,
          'rawDescription': 'Synthetic unresolved product',
          'quantity': '1',
          'unitPrice': null,
          'lineTotal': null,
          'approvalStatus': 'unresolved',
          'homeProductId': null,
        },
      ),
  ],
);
