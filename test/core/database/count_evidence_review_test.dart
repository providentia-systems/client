import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;
  var nextId = 1;
  setUp(() async {
    nextId = 1;
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(
      database,
      deviceId: _deviceId,
      originatingAccountId: _accountId,
      clock: () => _now,
      idGenerator: () => _id(nextId++),
    );
    await _seedProducts(database);
  });
  tearDown(() => database.close());

  test(
    'ordinary new counts remain unassessed without an invented observation time',
    () async {
      await repository.saveCountSession(_openCount());
      final count =
          (await repository.watchCountSessions(homeId: _homeId).first).single;
      expect(count.scopeComplete, isFalse);
      expect(count.reliability, 'unassessed');
      expect(count.observedAt, isNull);
      expect(count.serverAccepted, isFalse);
      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(operation.operationType, 'inventory.count-session.create');
      final payload = _decode(operation.payload);
      expect(payload['scopeComplete'], isFalse);
      expect(payload['reliability'], 'unassessed');
      expect(payload.containsKey('observedAt'), isFalse);
    },
  );

  test(
    'finishing explicit count evidence preserves balances and omitted products until readback',
    () async {
      final balancesBefore = await _balances(database);
      final open = _openCount();
      await repository.saveCountSession(open);
      final counted = open.recordLine(
        StockCountLine(
          id: _countLineId,
          itemId: _productId,
          status: CountLineStatus.confirmed,
          source: CountSource.manual,
          unit: 'kg',
          observedQuantity: 2.5,
        ),
      );
      await repository.saveCountSession(counted);
      final reviewed = counted.withEvidence(_reliableEvidence()).close(_now);
      await repository.saveCountSession(reviewed);

      expect(await _balances(database), balancesBefore);
      expect(
        (await repository.watchItems(homeId: _homeId).first)
            .singleWhere((item) => item.id == _omittedProductId)
            .currentQuantity,
        7,
      );
      expect(
        (await repository.watchItems(homeId: _homeId).first)
            .singleWhere((item) => item.id == _uncountedProductId)
            .currentQuantity,
        isNull,
      );
      final count =
          (await repository.watchCountSessions(homeId: _homeId).first).single;
      expect(count.status, CountSessionStatus.closed);
      expect(count.serverAccepted, isFalse);
      expect(count.scopeComplete, isTrue);
      expect(count.reliability, 'reliable');
      expect(count.observedAt, _observedAt);
      final operations = await database.select(database.clientOperations).get();
      final close = operations.singleWhere(
        (operation) =>
            operation.operationType == 'inventory.count-session.close',
      );
      expect(_decode(close.payload), <String, Object?>{
        'scopeComplete': true,
        'reliability': 'reliable',
        'observedAt': _observedAt.toIso8601String(),
      });
      expect(
        operations.where(
          (operation) =>
              operation.operationType == 'inventory.count-session.close',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'accepted closed count readback carries exact revisions and physical evidence',
    () async {
      await _seedAcceptedCount(database);
      final count =
          (await repository.watchCountSessions(homeId: _homeId).first).single;
      expect(count.id, _sessionId);
      expect(count.homeId, _homeId);
      expect(count.status, CountSessionStatus.closed);
      expect(count.serverAccepted, isTrue);
      expect(count.reviewPending, isFalse);
      expect(count.revision, 3);
      expect(count.scopeComplete, isFalse);
      expect(count.reliability, 'unassessed');
      expect(count.observedAt, _observedAt);
      expect(count.observedTimezone, 'Africa/Windhoek');
      expect(count.observedAt, isNot(count.startedAt));
      expect(count.lines.single.id, _countLineId);
      expect(count.lines.single.revision, 2);
      expect(count.lines.single.unit, 'kg');
      expect(count.lines.single.observedQuantity, 2.5);
      expect(
        await repository.watchActiveCountSession(homeId: _homeId).first,
        isNull,
      );
    },
  );

  test(
    'audited review queues exact corrections while old evidence and stock survive restart',
    () async {
      await _seedAcceptedCount(database);
      final accepted =
          (await repository.watchCountSessions(homeId: _homeId).first).single;
      final balanceBefore = await _balances(database);
      final lineBefore = await _record(
        database,
        'inventory-count-line',
        _countLineId,
      );
      await repository.reviewCountSession(
        session: accepted,
        evidence: _reliableEvidence(observedAt: _reviewedObservedAt),
        reason: 'Synthetic whole-home observation review',
        corrections: <StockCountLineCorrection>[
          StockCountLineCorrection(
            id: _countLineId,
            expectedRevision: 2,
            quantity: '1.12500001',
          ),
        ],
      );

      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(operation.operationType, 'inventory.count-session.review');
      expect(operation.baseRevision, 3);
      expect(operation.homeId, _homeId);
      expect(operation.entityId, _sessionId);
      expect(operation.deviceId, _deviceId);
      expect(operation.originatingAccountId, _accountId);
      expect(_decode(operation.payload), <String, Object?>{
        'reason': 'Synthetic whole-home observation review',
        'scopeComplete': true,
        'reliability': 'reliable',
        'observedAt': _reviewedObservedAt.toIso8601String(),
        'lineCorrections': <Object?>[
          <String, Object?>{
            'id': _countLineId,
            'quantity': '1.12500001',
            'expectedRevision': 2,
          },
        ],
      });
      expect(
        await _record(database, 'inventory-count-line', _countLineId),
        lineBefore,
      );
      expect(await _balances(database), balanceBefore);
      final restarted = DriftHouseholdRepository(database, deviceId: _deviceId);
      final pending =
          (await restarted.watchCountSessions(homeId: _homeId).first).single;
      expect(pending.serverAccepted, isTrue);
      expect(pending.reviewPending, isTrue);
      expect(pending.revision, 3);
      expect(pending.scopeComplete, isFalse);
      expect(pending.reliability, 'unassessed');
      expect(pending.observedAt, _observedAt);
      expect(pending.lines.single.observedQuantity, 2.5);
      expect(pending.lines.single.revision, 2);

      final recordsBeforeRetry = await database
          .select(database.localRecords)
          .get();
      await expectLater(
        repository.reviewCountSession(
          session: accepted,
          evidence: _reliableEvidence(),
          reason: 'Retry the same pending review',
          corrections: const <StockCountLineCorrection>[],
        ),
        throwsStateError,
      );
      expect(
        await database.select(database.clientOperations).get(),
        <ClientOperation>[operation],
      );
      expect(
        await database.select(database.localRecords).get(),
        recordsBeforeRetry,
      );
    },
  );

  for (final invalid in <String>[
    'stale session',
    'other home',
    'stale line',
    'other-home line',
    'duplicate line',
    'future observation',
  ]) {
    test('$invalid evidence review is rejected atomically', () async {
      await _seedAcceptedCount(database);
      await _seed(
        database,
        'inventory-count-line',
        _otherCountLineId,
        <String, Object?>{
          'sessionId': _sessionId,
          'homeProductId': _productId,
          'quantity': '8',
          'unit': 'kg',
          'status': 'confirmed',
        },
        homeId: _otherHomeId,
        revision: 2,
      );
      final accepted =
          (await repository.watchCountSessions(homeId: _homeId).first).single;
      final session = invalid == 'stale session'
          ? _acceptedCopy(accepted, revision: 2)
          : invalid == 'other home'
          ? _acceptedCopy(accepted, homeId: _otherHomeId)
          : accepted;
      final correction = StockCountLineCorrection(
        id: invalid == 'other-home line' ? _otherCountLineId : _countLineId,
        expectedRevision: invalid == 'stale line' ? 1 : 2,
        quantity: '1.25',
      );
      final recordsBefore = await database.select(database.localRecords).get();
      await expectLater(
        repository.reviewCountSession(
          session: session,
          evidence: invalid == 'future observation'
              ? StockCountEvidence(
                  scopeComplete: true,
                  reliability: 'reliable',
                  observedAt: _now.add(const Duration(seconds: 1)),
                )
              : _reliableEvidence(),
          reason: 'Synthetic correction validation',
          corrections: <StockCountLineCorrection>[
            correction,
            if (invalid == 'duplicate line') correction,
          ],
        ),
        throwsStateError,
      );
      expect(await database.select(database.clientOperations).get(), isEmpty);
      expect(await database.select(database.localRecords).get(), recordsBefore);
    });
  }

  test(
    'reliability cannot certify incomplete scope or unsupported evidence',
    () {
      expect(
        () => StockCountEvidence(
          scopeComplete: false,
          reliability: 'reliable',
          observedAt: _observedAt,
        ),
        throwsArgumentError,
      );
      expect(
        () => StockCountEvidence(
          scopeComplete: true,
          reliability: 'trusted',
          observedAt: _observedAt,
        ),
        throwsArgumentError,
      );
      expect(
        () => StockCountLineCorrection(
          id: _countLineId,
          expectedRevision: 0,
          quantity: '2',
        ),
        throwsArgumentError,
      );
      expect(
        () => StockCountLineCorrection(
          id: _countLineId,
          expectedRevision: 2,
          quantity: '-1',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'late purchase remains pending beside a trusted checkpoint and is applied logically once',
    () async {
      await _seedAcceptedCount(
        database,
        scopeComplete: true,
        reliability: 'reliable',
        quantity: '9',
      );
      await _seed(database, 'inventory-balance', _productId, <String, Object?>{
        'homeProductId': _productId,
        'quantity': '9',
        'uncertain': false,
        'pendingQuantity': '0',
        'limitations': <String>[],
        'checkpointId': _sessionId,
      });
      final receipt = await repository.createReceiptDraft(
        PurchaseReceiptDraftRequest(
          homeId: _homeId,
          purchaseDate: DateTime.utc(2026, 10, 20),
          currency: 'NAD',
        ),
      );
      final request = PurchaseReceiptLineRequest(
        homeId: _homeId,
        receiptId: receipt.entityId,
        clientLineId: _purchaseLineId,
        rawDescription: 'Synthetic late purchase',
        quantity: 2.25,
        quantityText: '2.25',
        lineTotal: Money(minorUnits: 450, currency: 'NAD'),
      );
      await repository.addPurchasedReceiptLine(
        line: request,
        homeProductId: _productId,
      );
      final item = (await repository.watchItems(homeId: _homeId).first)
          .singleWhere((value) => value.id == _productId);
      expect(item.currentQuantity, 9);
      expect(item.localPendingStockQuantity, '2.25');
      expect(item.localStockPendingIsDeferred, isTrue);
      expect(item.stockCheckpointId, _sessionId);
      expect(item.stockUncertain, isFalse);
      final pendingBalance = await _record(
        database,
        'inventory-balance',
        _productId,
      );
      final retry = await repository.addPurchasedReceiptLine(
        line: request,
        homeProductId: _productId,
      );
      expect(retry.disposition, PurchaseMutationDisposition.alreadyQueued);
      expect(
        await _record(database, 'inventory-balance', _productId),
        pendingBalance,
      );
      await repository.commitReceipt(
        homeId: _homeId,
        receiptId: receipt.entityId,
      );
      await repository.commitReceipt(
        homeId: _homeId,
        receiptId: receipt.entityId,
      );
      final afterFinish = (await repository.watchItems(homeId: _homeId).first)
          .singleWhere((value) => value.id == _productId);
      expect(afterFinish.currentQuantity, 9);
      expect(afterFinish.localPendingStockQuantity, '2.25');
      expect(afterFinish.localStockPendingIsDeferred, isTrue);
      final operations = await database.select(database.clientOperations).get();
      expect(
        operations.where(
          (operation) =>
              operation.operationType == 'purchasing.receipt-line.purchase',
        ),
        hasLength(1),
      );
      expect(
        operations.where(
          (operation) => operation.operationType == 'purchasing.receipt.commit',
        ),
        hasLength(1),
      );
      final history =
          (await repository.watchPurchaseLines(homeId: _homeId).first).single;
      expect(history.id, _purchaseLineId);
      expect(history.purchasedAt, DateTime.utc(2026, 10, 20));
      expect(history.quantity, 2.25);
      expect(history.pendingSynchronization, isTrue);
    },
  );
}

Future<void> _seedProducts(AppDatabase database) async {
  for (final product in <(String, String)>[
    (_productId, 'Synthetic rice'),
    (_omittedProductId, 'Synthetic oats'),
    (_uncountedProductId, 'Synthetic flour'),
  ]) {
    await _seed(
      database,
      'inventory-home-product',
      product.$1,
      <String, Object?>{
        'privateName': product.$2,
        'productId': null,
        'packId': null,
        'status': 'active',
        'unit': 'kg',
      },
    );
  }
  await _seed(database, 'inventory-balance', _productId, <String, Object?>{
    'homeProductId': _productId,
    'quantity': '9',
  });
  await _seed(
    database,
    'inventory-balance',
    _omittedProductId,
    <String, Object?>{'homeProductId': _omittedProductId, 'quantity': '7'},
  );
}

Future<void> _seedAcceptedCount(
  AppDatabase database, {
  bool scopeComplete = false,
  String reliability = 'unassessed',
  String quantity = '2.5',
}) async {
  await _seed(
    database,
    'inventory-count-session',
    _sessionId,
    <String, Object?>{
      'status': 'closed',
      'locationId': null,
      'scopeComplete': scopeComplete,
      'reliability': reliability,
      'observedAt': _observedAt.toIso8601String(),
      'observedTimezone': 'Africa/Windhoek',
    },
    revision: 3,
  );
  await _seed(database, 'inventory-count-line', _countLineId, <String, Object?>{
    'sessionId': _sessionId,
    'homeProductId': _productId,
    'quantity': quantity,
    'unit': 'kg',
    'source': 'manual',
    'status': 'confirmed',
  }, revision: 2);
}

Future<void> _seed(
  AppDatabase database,
  String type,
  String id,
  Map<String, Object?> payload, {
  String homeId = _homeId,
  int revision = 1,
}) async {
  await database
      .into(database.localRecords)
      .insertOnConflictUpdate(
        LocalRecordsCompanion.insert(
          homeId: homeId,
          entityType: type,
          entityId: id,
          revision: Value(revision),
          payload: jsonEncode(<String, Object?>{
            'id': id,
            'homeId': homeId,
            'revision': revision,
            ...payload,
          }),
          updatedAt: _now,
          synchronizedAt: Value(_now),
        ),
      );
}

Future<LocalRecord> _record(AppDatabase database, String type, String id) =>
    (database.select(database.localRecords)..where(
          (row) =>
              row.homeId.equals(_homeId) &
              row.entityType.equals(type) &
              row.entityId.equals(id),
        ))
        .getSingle();

Future<List<LocalRecord>> _balances(AppDatabase database) => (database.select(
  database.localRecords,
)..where((row) => row.entityType.equals('inventory-balance'))).get();

StockCountSession _openCount() => StockCountSession(
  id: _sessionId,
  homeId: _homeId,
  locationId: 'primary',
  startedAt: _now,
);
StockCountEvidence _reliableEvidence({DateTime? observedAt}) =>
    StockCountEvidence(
      scopeComplete: true,
      reliability: 'reliable',
      observedAt: observedAt ?? _observedAt,
    );
StockCountSession _acceptedCopy(
  StockCountSession session, {
  int? revision,
  String? homeId,
}) => StockCountSession(
  id: session.id,
  homeId: homeId ?? session.homeId,
  locationId: session.locationId,
  startedAt: session.startedAt,
  status: session.status,
  closedAt: session.closedAt,
  revision: revision ?? session.revision,
  serverAccepted: session.serverAccepted,
  scopeComplete: session.scopeComplete,
  reliability: session.reliability,
  observedAt: session.observedAt,
  observedTimezone: session.observedTimezone,
  lines: session.lines,
);
Map<String, Object?> _decode(String value) =>
    (jsonDecode(value) as Map).cast<String, Object?>();
String _id(int value) =>
    '10000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
final _now = DateTime.utc(2026, 10, 26, 10);
final _observedAt = DateTime.utc(2026, 10, 24, 8);
final _reviewedObservedAt = DateTime.utc(2026, 10, 24, 7);
const _homeId = '20000000-0000-4000-8000-000000000001';
const _otherHomeId = '20000000-0000-4000-8000-000000000002';
const _deviceId = '20000000-0000-4000-8000-000000000003';
const _accountId = '20000000-0000-4000-8000-000000000004';
const _sessionId = '20000000-0000-4000-8000-000000000005';
const _countLineId = '20000000-0000-4000-8000-000000000006';
const _otherCountLineId = '20000000-0000-4000-8000-000000000007';
const _productId = '20000000-0000-4000-8000-000000000008';
const _omittedProductId = '20000000-0000-4000-8000-000000000009';
const _uncountedProductId = '20000000-0000-4000-8000-000000000010';
const _purchaseLineId = '20000000-0000-4000-8000-000000000011';
