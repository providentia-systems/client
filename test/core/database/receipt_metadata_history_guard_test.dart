import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';

const _home = '10000000-0000-4000-8000-000000000011';
const _device = '10000000-0000-4000-8000-000000000012';
const _product = '10000000-0000-4000-8000-000000000013';
const _store = '10000000-0000-4000-8000-000000000014';

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;
  final purchaseDate = DateTime.utc(2026, 10, 13);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(database, deviceId: _device);
    for (final record in <(String, String, Map<String, Object?>)>[
      (
        'inventory-home-product',
        _product,
        <String, Object?>{
          'privateName': 'Apples',
          'status': 'active',
          'unit': 'kg',
        },
      ),
      (
        'inventory-balance',
        _product,
        <String, Object?>{'homeProductId': _product, 'quantity': '2'},
      ),
      (
        'purchasing-store',
        _store,
        <String, Object?>{
          'name': 'Local shop',
          'location': '',
          'status': 'active',
        },
      ),
    ]) {
      await database
          .into(database.localRecords)
          .insert(
            LocalRecordsCompanion.insert(
              homeId: _home,
              entityType: record.$1,
              entityId: record.$2,
              payload: jsonEncode(record.$3),
              revision: const Value(1),
              updatedAt: purchaseDate,
              synchronizedAt: Value(purchaseDate),
            ),
          );
    }
  });
  tearDown(() => database.close());

  Future<LocalRecord> receipt(String id) =>
      (database.select(database.localRecords)..where(
            (row) =>
                row.homeId.equals(_home) &
                row.entityType.equals('purchasing-receipt') &
                row.entityId.equals(id),
          ))
          .getSingle();

  for (final removedHistory in <bool>[true, false]) {
    test(
      removedHistory
          ? 'removed applied lines retain receipt date and currency guard'
          : 'finished unresolved-only receipt retains date and currency guard',
      () async {
        final draft = await repository.createReceiptDraft(
          PurchaseReceiptDraftRequest(
            homeId: _home,
            purchaseDate: purchaseDate,
            currency: 'NAD',
          ),
        );
        final line = PurchaseReceiptLineRequest(
          homeId: _home,
          receiptId: draft.entityId,
          rawDescription: 'Apples',
          quantity: 5,
          quantityText: '5',
          lineTotal: Money(minorUnits: 5000, currency: 'NAD'),
        );
        if (removedHistory) {
          final purchase = await repository.addPurchasedReceiptLine(
            line: line,
            homeProductId: _product,
          );
          await repository.removeReceiptDraftLine(
            homeId: _home,
            receiptId: draft.entityId,
            lineId: purchase.entityId,
            expectedRevision: purchase.revision,
          );
        } else {
          final imported = await repository.addReceiptLine(line);
          await repository.markReceiptLineUnresolved(
            homeId: _home,
            receiptId: draft.entityId,
            lineId: imported.entityId,
          );
          await repository.commitReceipt(
            homeId: _home,
            receiptId: draft.entityId,
          );
        }
        final before = await receipt(draft.entityId);
        final operationCount =
            (await database.select(database.clientOperations).get()).length;
        for (final change in <(DateTime, String)>[
          (purchaseDate.add(const Duration(days: 1)), 'NAD'),
          (purchaseDate, 'USD'),
        ]) {
          await expectLater(
            repository.updateReceiptDraft(
              receiptId: draft.entityId,
              expectedRevision: before.revision,
              draft: PurchaseReceiptDraftRequest(
                homeId: _home,
                purchaseDate: change.$1,
                currency: change.$2,
              ),
            ),
            throwsA(isA<PurchaseCaptureException>()),
          );
          expect((await receipt(draft.entityId)).payload, before.payload);
          expect((await receipt(draft.entityId)).revision, before.revision);
          expect(
            (await database.select(database.clientOperations).get()).length,
            operationCount,
          );
        }
        await repository.updateReceiptDraft(
          receiptId: draft.entityId,
          expectedRevision: before.revision,
          draft: PurchaseReceiptDraftRequest(
            homeId: _home,
            purchaseDate: purchaseDate,
            currency: 'NAD',
            storeId: _store,
            notes: 'Corrected receipt context',
            total: Money(minorUnits: 1234, currency: 'NAD'),
          ),
        );
        final updated =
            jsonDecode((await receipt(draft.entityId)).payload)
                as Map<String, Object?>;
        expect(updated['storeId'], _store);
        expect(updated['notes'], 'Corrected receipt context');
        expect(updated['totalAmount'], '12.34');
        expect(updated['purchaseDate'], '2026-10-13');
        expect(updated['currency'], 'NAD');
      },
    );
  }
}
