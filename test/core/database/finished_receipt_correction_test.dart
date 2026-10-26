import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_workspace.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

const _home = '10000000-0000-4000-8000-000000000001';
const _device = '10000000-0000-4000-8000-000000000002';
const _product = '10000000-0000-4000-8000-000000000003';
const _receipt = '10000000-0000-4000-8000-000000000004';
const _applied = '10000000-0000-4000-8000-000000000005';
const _unresolved = '10000000-0000-4000-8000-000000000006';
const _omitted = '10000000-0000-4000-8000-000000000007';

void main() {
  late AppDatabase database;
  late DriftHouseholdRepository repository;
  final at = DateTime.utc(2026, 10, 26);

  Future<void> seed(
    String type,
    String id,
    Map<String, Object?> value, {
    int revision = 1,
    bool synchronized = true,
  }) async {
    await database
        .into(database.localRecords)
        .insertOnConflictUpdate(
          LocalRecordsCompanion.insert(
            homeId: _home,
            entityType: type,
            entityId: id,
            payload: jsonEncode(value),
            revision: Value(revision),
            updatedAt: at,
            synchronizedAt: Value(synchronized ? at : null),
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

  PurchaseReceiptLineRequest request({String quantity = '2'}) =>
      PurchaseReceiptLineRequest(
        homeId: _home,
        receiptId: _receipt,
        rawDescription: 'Omitted rice',
        quantity: double.parse(quantity),
        quantityText: quantity,
        clientLineId: _omitted,
        allowUnknownPrice: true,
      );

  setUp(() async {
    var id = 20;
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftHouseholdRepository(
      database,
      deviceId: _device,
      clock: () => at,
      idGenerator: () =>
          '10000000-0000-4000-8000-${(id++).toString().padLeft(12, '0')}',
    );
    await seed('inventory-home-product', _product, {
      'privateName': 'Rice',
      'originalPackText': '1 kg',
      'status': 'active',
      'unit': 'kg',
    });
    await seed('inventory-balance', _product, {
      'homeProductId': _product,
      'quantity': '7',
    });
    await seed('purchasing-receipt', _receipt, {
      'purchaseDate': '2026-10-20',
      'currency': 'NAD',
      'notes': '',
      'status': 'committed',
      'lineCorrectionState': 'available',
    }, revision: 8);
    await seed('purchasing-receipt-line', _applied, {
      'receiptId': _receipt,
      'rawDescription': 'Original rice',
      'quantity': '5',
      'homeProductId': _product,
      'approvalStatus': 'approved',
      'stockQuantity': '5',
      'stockQuantityPerPack': '1',
      'stockUnit': 'kg',
      'lineTotal': '30.00',
    });
    await seed('purchasing-receipt-line', _unresolved, {
      'receiptId': _receipt,
      'rawDescription': 'Pending rice',
      'quantity': '3',
      'homeProductId': null,
      'approvalStatus': 'unresolved',
      'unitPrice': '5.00',
    }, revision: 2);
  });
  tearDown(() => database.close());

  test(
    'omitted and unresolved purchases queue once without replaying applied stock',
    () async {
      final original = await row('purchasing-receipt-line', _applied);
      await repository.completeFinishedReceiptLine(
        line: request(),
        expectedReceiptRevision: 8,
        homeProductId: _product,
        reason: 'Omitted from original entry',
      );
      expect((await row('inventory-balance', _product))['quantity'], '9');
      expect(await row('purchasing-receipt-line', _applied), original);
      var capture =
          (await repository.watchReceiptCaptures(homeId: _home).first).single;
      expect(capture.status, PurchaseReceiptStatus.committed);
      expect(capture.commitConfirmed, isTrue);
      expect(capture.revision, 9);
      expect(
        capture.lines.firstWhere((line) => line.id == _omitted).stockQuantity,
        '2',
      );
      final restarted = DriftHouseholdRepository(database, deviceId: _device);
      await restarted.completeFinishedReceiptLine(
        line: request(quantity: '3'),
        expectedReceiptRevision: 9,
        homeProductId: _product,
        reason: 'Resolved pending description',
        existingLineId: _unresolved,
        expectedLineRevision: 2,
      );
      expect((await row('inventory-balance', _product))['quantity'], '12');
      capture =
          (await restarted.watchReceiptCaptures(homeId: _home).first).single;
      expect(capture.revision, 10);
      expect(
        capture.lines.firstWhere((line) => line.id == _unresolved).revision,
        3,
      );
      final operations = await database.select(database.clientOperations).get();
      expect(operations.map((op) => op.operationType), [
        'purchasing.receipt-line.correct',
        'purchasing.receipt-line.correct',
      ]);
      expect(operations.map((op) => op.baseRevision), [8, 9]);
      final payloads = operations
          .map((op) => jsonDecode(op.payload) as Map)
          .toList();
      expect(payloads[0]['expectedLineRevision'], isNull);
      expect(payloads[1]['expectedLineRevision'], 2);
      expect(payloads.every((value) => value['receiptId'] == _receipt), isTrue);
      expect(payloads[0]['lineTotal'], isNull);
      expect(payloads[0]['unit'], 'kg');
      expect(payloads[0]['stockQuantityPerPack'], '1');
      expect(
        payloads.map((value) => value['correctionId']).toSet(),
        hasLength(2),
      );
      expect(
        operations.every((op) => op.deviceId == _device && op.homeId == _home),
        isTrue,
      );
      await expectLater(
        restarted.completeFinishedReceiptLine(
          line: request(quantity: '3'),
          expectedReceiptRevision: 9,
          homeProductId: _product,
          reason: 'Resolved pending description',
          existingLineId: _unresolved,
          expectedLineRevision: 2,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect((await row('inventory-balance', _product))['quantity'], '12');
      final unchanged = await database.select(database.clientOperations).get();
      expect(
        unchanged.map((op) => op.operationId),
        operations.map((op) => op.operationId),
      );
      expect(
        unchanged.map((op) => op.payload),
        operations.map((op) => op.payload),
      );
    },
  );

  test(
    'an omitted inbound purchase preserves a remaining signed ledger balance',
    () async {
      await seed('inventory-balance', _product, {
        'homeProductId': _product,
        'quantity': '-5',
        'uncertain': true,
        'pendingQuantity': '1.5',
        'limitations': ['No accepted physical checkpoint'],
      });
      await repository.completeFinishedReceiptLine(
        line: request(),
        expectedReceiptRevision: 8,
        homeProductId: _product,
        reason: 'Omitted inbound purchase',
      );
      final balance = await row('inventory-balance', _product);
      expect(balance['quantity'], '-3');
      expect(balance['uncertain'], isTrue);
      expect(balance['pendingQuantity'], '1.5');
      expect(balance['limitations'], ['No accepted physical checkpoint']);
    },
  );

  test(
    'lost correction response recovers immutable result and absolute stock readback',
    () async {
      final local = DriftLocalSyncRepository(database);
      await local.applyPullPage(
        homeId: _home,
        page: PullPage(
          protocolVersion: 1,
          fromCursor: null,
          pageCursor: 'cursor-0',
          highWaterCursor: 'cursor-0',
          hasMore: false,
          requestId: _device,
          changes: const [],
        ),
      );
      await repository.completeFinishedReceiptLine(
        line: request(),
        expectedReceiptRevision: 8,
        homeProductId: _product,
        reason: 'Omitted inbound purchase',
      );
      final original = await database
          .select(database.clientOperations)
          .getSingle();
      var effects = 0;
      var pushes = 0;
      var statusLookups = 0;
      Map<String, Object?>? accepted;
      final correctedLine = {
        'id': _omitted,
        'receiptId': _receipt,
        'revision': 1,
        'rawDescription': 'Omitted rice',
        'quantity': '2',
        'homeProductId': _product,
        'packId': null,
        'stockQuantity': '2',
        'stockQuantityPerPack': '1',
        'stockUnit': 'kg',
        'approvalStatus': 'approved',
        'unitPrice': null,
        'lineTotal': null,
        'originalPackText': null,
      };
      http.Response jsonResponse(Map<String, Object?> body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
      final gateway = GeneratedSyncGateway(
        generated.ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/sync/push')) {
              pushes++;
              final body = jsonDecode(request.body) as Map<String, Object?>;
              final command = (body['operations'] as List).single as Map;
              expect(command['operationId'], original.operationId);
              expect(command['commandType'], 'purchasing.receipt-line.correct');
              expect(command['baseRevision'], 8);
              expect(command['payload'], jsonDecode(original.payload));
              if (accepted == null) effects++;
              accepted ??= {
                'operationId': original.operationId,
                'status': 'accepted',
                'commandType': 'purchasing.receipt-line.correct',
                'entityId': _omitted,
                'result': {
                  ...correctedLine,
                  'receiptRevision': 9,
                  'correctionId':
                      (jsonDecode(original.payload) as Map)['correctionId'],
                },
              };
              return jsonResponse({
                'protocolVersion': 2,
                'batchId': body['batchId'],
                'requestId': _device,
                'serverTime': at.toIso8601String(),
                'highWaterCursor': 'cursor-1',
                'results': 'lost-response-bytes',
              });
            }
            if (request.url.path.endsWith('/sync/operation-status')) {
              statusLookups++;
              final body = jsonDecode(request.body) as Map;
              expect(body['deviceId'], _device);
              expect(body['operationIds'], [original.operationId]);
              return jsonResponse({
                'protocolVersion': 2,
                'operations': [
                  {
                    'operationId': original.operationId,
                    'known': true,
                    'result': accepted,
                  },
                ],
              });
            }
            expect(request.url.path, '/api/v1/homes/$_home/sync/pull');
            final from = request.url.queryParameters['cursor'];
            return jsonResponse({
              'protocolVersion': 1,
              'fromCursor': from,
              'pageCursor': 'cursor-1',
              'highWaterCursor': 'cursor-1',
              'hasMore': false,
              'requestId': _device,
              'changes': from == 'cursor-1'
                  ? []
                  : [
                      for (final entry in [
                        (
                          'purchasing-receipt',
                          _receipt,
                          9,
                          {
                            'status': 'committed',
                            'purchaseDate': '2026-10-20',
                            'currency': 'NAD',
                            'notes': '',
                            'lineCorrectionState': 'available',
                          },
                        ),
                        ('purchasing-receipt-line', _omitted, 1, correctedLine),
                        (
                          'inventory-balance',
                          _product,
                          2,
                          {'homeProductId': _product, 'quantity': '10'},
                        ),
                      ])
                        {
                          'cursor': 'cursor-1',
                          'entityType': entry.$1,
                          'entityId': entry.$2,
                          'revision': entry.$3,
                          'serverTimestamp': at.toIso8601String(),
                          'operation': 'upsert',
                          'representationSchemaVersion': 1,
                          'representation': entry.$4,
                        },
                    ],
            });
          }),
        ),
      );
      SyncCoordinator coordinator() => SyncCoordinator(
        local: local,
        remote: gateway,
        connectivity: const _Online(),
        clock: () => at,
      );
      expect(
        (await coordinator().synchronize(_home)).status,
        SyncRunStatus.completed,
      );
      expect(pushes, 1);
      expect(effects, 1);
      expect(statusLookups, 1);
      expect((await row('inventory-balance', _product))['quantity'], '10');
      final after = await database
          .select(database.clientOperations)
          .getSingle();
      expect(after.operationId, original.operationId);
      expect(after.payload, original.payload);
      expect(after.state, ClientOperationState.acknowledged.storageValue);
      final restarted = DriftHouseholdRepository(database, deviceId: _device);
      final capture =
          (await restarted.watchReceiptCaptures(homeId: _home).first).single;
      expect(
        capture.lines.firstWhere((line) => line.id == _omitted).stockQuantity,
        '2',
      );
      expect(
        capture.synchronizationState,
        PurchaseSynchronizationState.synchronized,
      );
      expect(
        (await coordinator().synchronize(_home)).status,
        SyncRunStatus.completed,
      );
      expect(pushes, 1);
      expect(effects, 1);
      expect((await row('inventory-balance', _product))['quantity'], '10');
    },
  );

  test(
    'unresolved detail edits and removal remain no-stock corrections',
    () async {
      await repository.updateReceiptDraftLine(
        lineId: _unresolved,
        expectedRevision: 2,
        line: PurchaseReceiptLineRequest(
          homeId: _home,
          receiptId: _receipt,
          rawDescription: 'Corrected pending text',
          quantity: 4,
          lineTotal: Money(minorUnits: 1700, currency: 'NAD'),
        ),
      );
      var pending = await row('purchasing-receipt-line', _unresolved);
      expect(pending['approvalStatus'], 'unresolved');
      expect(pending['stockQuantity'], isNull);
      expect(pending['homeProductId'], isNull);
      expect((await row('inventory-balance', _product))['quantity'], '7');
      await repository.removeReceiptDraftLine(
        homeId: _home,
        receiptId: _receipt,
        lineId: _unresolved,
        expectedRevision: 3,
      );
      pending = await row('purchasing-receipt-line', _unresolved);
      expect(pending['approvalStatus'], 'removed');
      expect((await row('inventory-balance', _product))['quantity'], '7');
      expect(
        (await row('purchasing-receipt', _receipt))['status'],
        'committed',
      );
    },
  );

  test(
    'stale line revision or absent capability cannot mutate stock or queue',
    () async {
      await expectLater(
        repository.completeFinishedReceiptLine(
          line: request(),
          expectedReceiptRevision: 8,
          homeProductId: _product,
          reason: 'Resolve',
          existingLineId: _unresolved,
          expectedLineRevision: 1,
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      final receipt = await row('purchasing-receipt', _receipt);
      receipt.remove('lineCorrectionState');
      await seed('purchasing-receipt', _receipt, receipt, revision: 8);
      await expectLater(
        repository.completeFinishedReceiptLine(
          line: request(),
          expectedReceiptRevision: 8,
          homeProductId: _product,
          reason: 'Resolve',
        ),
        throwsA(isA<PurchaseCaptureException>()),
      );
      expect((await row('inventory-balance', _product))['quantity'], '7');
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );

  test('unconfirmed finish and uncertain approved line stay blocked', () async {
    final receipt = await row('purchasing-receipt', _receipt);
    await seed(
      'purchasing-receipt',
      _receipt,
      receipt,
      revision: 8,
      synchronized: false,
    );
    await expectLater(
      repository.completeFinishedReceiptLine(
        line: request(),
        expectedReceiptRevision: 8,
        homeProductId: _product,
        reason: 'Resolve',
      ),
      throwsA(isA<PurchaseCaptureException>()),
    );
    await seed('purchasing-receipt', _receipt, receipt, revision: 8);
    await seed('purchasing-receipt-line', _unresolved, {
      'receiptId': _receipt,
      'rawDescription': 'Unconfirmed rice',
      'quantity': '3',
      'homeProductId': _product,
      'approvalStatus': 'approved',
      'stockQuantityPerPack': '1',
      'stockUnit': 'kg',
      'unitPrice': '5.00',
    }, revision: 2);
    await expectLater(
      repository.completeFinishedReceiptLine(
        line: request(),
        expectedReceiptRevision: 8,
        homeProductId: _product,
        reason: 'Resolve',
        existingLineId: _unresolved,
        expectedLineRevision: 2,
      ),
      throwsA(isA<PurchaseCaptureException>()),
    );
    expect((await row('inventory-balance', _product))['quantity'], '7');
    expect(await database.select(database.clientOperations).get(), isEmpty);
  });

  testWidgets(
    'finished receipt offers omitted and unresolved correction controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
        productCreationRepository: repository,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('purchase-add-omitted-line')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('purchase-resolve-line-$_unresolved')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('purchase-edit-line-$_unresolved')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('purchase-remove-line-$_unresolved')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('purchase-add-omitted-line')),
      );
      await tester.tap(find.byKey(const Key('purchase-add-omitted-line')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('finished-line-description')),
        'Retained omitted text',
      );
      await tester.ensureVisible(find.byKey(const Key('finished-line-save')));
      await tester.tap(find.byKey(const Key('finished-line-save')));
      await tester.pumpAndSettle();
      expect(find.text('Choose an existing home product.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('finished-line-description')),
            )
            .controller!
            .text,
        'Retained omitted text',
      );
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );
  testWidgets(
    'a remote receipt revision preserves the opened correction entries',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PurchasingController(
        repository: repository,
        homeId: _home,
        mayWrite: true,
        productCreationRepository: repository,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('purchase-add-omitted-line')),
      );
      await tester.tap(find.byKey(const Key('purchase-add-omitted-line')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('finished-line-product')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rice · 1 kg').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('finished-line-description')),
        'Retained stale correction',
      );
      await tester.ensureVisible(find.byKey(const Key('finished-line-reason')));
      await tester.enterText(
        find.byKey(const Key('finished-line-reason')),
        'Omitted purchase',
      );
      await seed(
        'purchasing-receipt',
        _receipt,
        await row('purchasing-receipt', _receipt),
        revision: 9,
      );
      await tester.pumpAndSettle();
      expect(controller.state.capture!.revision, 9);
      await tester.ensureVisible(find.byKey(const Key('finished-line-save')));
      await tester.tap(find.byKey(const Key('finished-line-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('finished-line-error')), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('finished-line-description')),
            )
            .controller!
            .text,
        'Retained stale correction',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('finished-line-reason')),
            )
            .controller!
            .text,
        'Omitted purchase',
      );
      expect((await row('inventory-balance', _product))['quantity'], '7');
      expect(await database.select(database.clientOperations).get(), isEmpty);
    },
  );
}

final class _Online implements ConnectivityProbe {
  const _Online();
  @override
  Future<ConnectivityResult> check() async => const ConnectivityResult.online();
}
