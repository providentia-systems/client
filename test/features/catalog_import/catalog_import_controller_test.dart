import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/catalog_import/application/catalog_import_controller.dart';
import 'package:providentia/features/catalog_import/application/catalog_import_ports.dart';
import 'package:providentia/features/catalog_import/domain/catalog_import_models.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';

const String _homeId = 'home-1';

void main() {
  test('parser enforces the 10 MB selection bound', () {
    final parser = SpreadsheetTableParser(
      decodeXlsx: ({required sourceName, required bytes}) =>
          throw StateError('unused'),
    );
    expect(
      () => parser.parse(
        PickedSpreadsheetFile(
          name: 'big.csv',
          kind: SpreadsheetFileKind.csv,
          bytes: Uint8List(SpreadsheetImportPolicy.maxFileBytes + 1),
        ),
      ),
      throwsA(isA<SpreadsheetSelectionException>()),
    );
  });

  test('a planned batch rejects an out-of-contract idempotency key', () {
    expect(
      () => CatalogImportBatchSlot(
        index: 0,
        records: const <Map<String, Object?>>[
          <String, Object?>{'recordType': 'home_product'},
        ],
        idempotencyKey: 'short',
      ),
      throwsArgumentError,
    );
  });

  test('cancelling the picker keeps the idle state untouched', () async {
    final fixture = _Fixture(pickResults: <PickedSpreadsheetFile?>[null]);
    await fixture.controller.pickSpreadsheet();
    expect(fixture.controller.state.phase, CatalogImportPhase.idle);
    expect(fixture.controller.state.safeMessage, isNull);
  });

  test('picking parses, auto-maps by headers, and validates', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[
        _csvFile('name,brand\nRolled oats,Acme\nMilk,\n'),
      ],
    );
    await fixture.controller.pickSpreadsheet();
    final state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.mapping);
    expect(state.grid?.sourceName, 'products.csv');
    expect(state.mapping.assignments, <int, CatalogImportField>{
      0: CatalogImportField.name,
      1: CatalogImportField.brand,
    });
    expect(state.recordType, CatalogImportRecordType.homeProduct);
    expect(state.validation?.records, hasLength(2));
    expect(state.validation?.mayStage, isTrue);
  });

  test(
    'a rejected selection restores the previous state with a message',
    () async {
      final fixture = _Fixture(
        pickThrows: const SpreadsheetSelectionException(
          'Choose a spreadsheet of 10 MB or less.',
        ),
      );
      await fixture.controller.pickSpreadsheet();
      final state = fixture.controller.state;
      expect(state.phase, CatalogImportPhase.idle);
      expect(state.safeMessage, contains('10 MB'));
    },
  );

  test('mapping edits and record type both recompute validation', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[
        _csvFile('name,code\nRolled oats,6001\n'),
      ],
    );
    await fixture.controller.pickSpreadsheet();
    fixture.controller.selectRecordType(
      CatalogImportRecordType.catalogProductReference,
    );
    var state = fixture.controller.state;
    expect(state.validation?.records, hasLength(1));
    expect(
      state.validation?.records.single.wireRecord['recordType'],
      'catalog_product_reference',
    );

    fixture.controller.assignColumn(1, null);
    state = fixture.controller.state;
    expect(state.validation?.records, isEmpty);
    expect(state.validation?.issues.single.message, contains('barcode'));

    fixture.controller.setHasHeaderRow(false);
    state = fixture.controller.state;
    expect(state.validation?.issues, hasLength(2));
  });

  test('staging sends one batch with a persisted fresh key', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[
        _csvFile('name\nRolled oats\nMilk\n'),
      ],
    );
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();

    final state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.review);
    expect(fixture.gateway.stageCalls, hasLength(1));
    final call = fixture.gateway.stageCalls.single;
    expect(call.homeId, _homeId);
    expect(call.idempotencyKey, 'generated-idempotency-key-1');
    expect(call.records, <Map<String, Object?>>[
      <String, Object?>{'recordType': 'home_product', 'name': 'Rolled oats'},
      <String, Object?>{'recordType': 'home_product', 'name': 'Milk'},
    ]);
    expect(state.batches.single.batch?.id, 'import-1');
  });

  test('a large import stages sequential 500-record batches', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[_csvFile(_manyRows(750))],
    );
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();

    expect(fixture.gateway.stageCalls, hasLength(2));
    expect(fixture.gateway.stageCalls.first.records, hasLength(500));
    expect(fixture.gateway.stageCalls.last.records, hasLength(250));
    expect(
      fixture.gateway.stageCalls.first.idempotencyKey,
      isNot(fixture.gateway.stageCalls.last.idempotencyKey),
    );
    expect(fixture.controller.state.phase, CatalogImportPhase.review);
    expect(fixture.controller.state.stagedBatchCount, 2);
  });

  test('a staging retry resumes and replays the exact same key', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[_csvFile(_manyRows(750))],
    );
    fixture.gateway.stageFailures.add(1);
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();

    var state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.staging);
    expect(state.busy, isFalse);
    expect(state.safeMessage, contains('batch 2 of 2'));
    expect(state.stagedBatchCount, 1);
    final failedKey = fixture.gateway.stageCalls.last.idempotencyKey;

    await fixture.controller.stage();
    state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.review);
    expect(fixture.gateway.stageCalls, hasLength(3));
    expect(fixture.gateway.stageCalls.last.idempotencyKey, failedKey);
    expect(
      fixture.gateway.stageCalls.map((call) => call.records.length).toList(),
      <int>[500, 250, 250],
    );
  });

  test('a server-side validation rejection returns to mapping', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[_csvFile('name\nRolled oats\n')],
    );
    fixture.gateway.stageErrors.add(const CatalogImportValidationException());
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();

    final state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.mapping);
    expect(state.batches, isEmpty);
    expect(state.safeMessage, contains('rejected'));
  });

  test('lost authorization fails closed from staging', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[_csvFile('name\nRolled oats\n')],
    );
    fixture.gateway.stageErrors.add(const CatalogImportForbiddenException());
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();

    expect(fixture.controller.state.phase, CatalogImportPhase.accessDenied);
    expect(fixture.authorizationLostCalls, 1);
  });

  test('confirmation applies each staged batch at its revision', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[_csvFile(_manyRows(750))],
    );
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();
    await fixture.controller.confirmStagedBatches();

    final state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.completed);
    expect(fixture.gateway.confirmCalls, hasLength(2));
    expect(fixture.gateway.confirmCalls.first.importId, 'import-1');
    expect(fixture.gateway.confirmCalls.first.expectedRevision, 1);
    expect(state.confirmedBatchCount, 2);
    expect(state.reconciliation.createPrivate, 750);
    expect(state.reconciliation.imported, 750);
  });

  test('a 409 refetches the batch and requires a fresh confirmation', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[_csvFile('name\nRolled oats\n')],
    );
    fixture.gateway.confirmConflicts.add(0);
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();
    await fixture.controller.confirmStagedBatches();

    var state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.review);
    expect(state.safeMessage, contains('changed elsewhere'));
    expect(fixture.gateway.fetchCalls, hasLength(1));
    expect(fixture.gateway.fetchCalls.single.importId, 'import-1');
    expect(state.batches.single.batch?.revision, 7);

    await fixture.controller.confirmStagedBatches();
    state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.completed);
    expect(fixture.gateway.confirmCalls, hasLength(2));
    expect(fixture.gateway.confirmCalls.last.expectedRevision, 7);
  });

  test('a mid-import conflict keeps earlier batches applied', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[_csvFile(_manyRows(750))],
    );
    fixture.gateway.confirmConflicts.add(1);
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();
    await fixture.controller.confirmStagedBatches();

    var state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.review);
    expect(state.confirmedBatchCount, 1);

    await fixture.controller.confirmStagedBatches();
    state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.completed);
    // Batch one was confirmed exactly once; batch two twice.
    expect(
      fixture.gateway.confirmCalls
          .where((call) => call.importId == 'import-1')
          .length,
      1,
    );
    expect(
      fixture.gateway.confirmCalls
          .where((call) => call.importId == 'import-2')
          .length,
      2,
    );
  });

  test('a transport failure during confirmation returns to review', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[_csvFile('name\nRolled oats\n')],
    );
    fixture.gateway.confirmErrors.add(
      const CatalogImportUnavailableException(),
    );
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();
    await fixture.controller.confirmStagedBatches();

    final state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.review);
    expect(state.safeMessage, contains('Confirmation paused'));

    await fixture.controller.confirmStagedBatches();
    expect(fixture.controller.state.phase, CatalogImportPhase.completed);
  });

  test(
    'clearing sensitive state resets and invalidates in-flight work',
    () async {
      final gate = Completer<void>();
      final fixture = _Fixture(
        pickResults: <PickedSpreadsheetFile?>[_csvFile('name\nRolled oats\n')],
      );
      fixture.gateway.stageGate = gate.future;
      await fixture.controller.pickSpreadsheet();
      final staging = fixture.controller.stage();
      expect(fixture.controller.state.phase, CatalogImportPhase.staging);

      fixture.controller.clearSensitiveState();
      expect(fixture.controller.state.phase, CatalogImportPhase.idle);
      gate.complete();
      await staging;
      expect(fixture.controller.state.phase, CatalogImportPhase.idle);
      expect(fixture.controller.state.batches, isEmpty);
    },
  );

  test('completed imports can start over from a clean pick step', () async {
    final fixture = _Fixture(
      pickResults: <PickedSpreadsheetFile?>[_csvFile('name\nRolled oats\n')],
    );
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();
    await fixture.controller.confirmStagedBatches();
    expect(fixture.controller.state.phase, CatalogImportPhase.completed);

    fixture.controller.reset();
    final state = fixture.controller.state;
    expect(state.phase, CatalogImportPhase.idle);
    expect(state.grid, isNull);
    expect(state.batches, isEmpty);
  });
}

PickedSpreadsheetFile _csvFile(String text) => PickedSpreadsheetFile(
  name: 'products.csv',
  kind: SpreadsheetFileKind.csv,
  bytes: Uint8List.fromList(utf8.encode(text)),
);

String _manyRows(int count) {
  final buffer = StringBuffer('name\n');
  for (var row = 0; row < count; row++) {
    buffer.writeln('Item $row');
  }
  return buffer.toString();
}

final class _StageCall {
  const _StageCall({
    required this.homeId,
    required this.idempotencyKey,
    required this.records,
  });

  final String homeId;
  final String idempotencyKey;
  final List<Map<String, Object?>> records;
}

final class _ConfirmCall {
  const _ConfirmCall({
    required this.homeId,
    required this.importId,
    required this.expectedRevision,
  });

  final String homeId;
  final String importId;
  final int expectedRevision;
}

final class _FetchCall {
  const _FetchCall({required this.homeId, required this.importId});

  final String homeId;
  final String importId;
}

final class _ScriptedGateway implements CatalogImportGateway {
  final List<_StageCall> stageCalls = <_StageCall>[];
  final List<_ConfirmCall> confirmCalls = <_ConfirmCall>[];
  final List<_FetchCall> fetchCalls = <_FetchCall>[];

  /// Zero-based indexes of stage attempts that fail with an unavailable
  /// transport before succeeding on the next attempt.
  final Set<int> stageFailures = <int>{};

  /// Exceptions consumed one per stage call, before any success.
  final List<Exception> stageErrors = <Exception>[];

  /// Zero-based batch indexes whose first confirmation raises a conflict.
  final Set<int> confirmConflicts = <int>{};

  /// Exceptions consumed one per confirm call, before any success.
  final List<Exception> confirmErrors = <Exception>[];

  Future<void>? stageGate;

  final Map<String, int> _rowCounts = <String, int>{};
  var _stageAttempts = 0;
  var _stagedBatches = 0;

  @override
  Future<CatalogImportBatchView> stage({
    required String homeId,
    required String idempotencyKey,
    required List<Map<String, Object?>> records,
  }) async {
    await (stageGate ?? Future<void>.value());
    stageCalls.add(
      _StageCall(
        homeId: homeId,
        idempotencyKey: idempotencyKey,
        records: records,
      ),
    );
    if (stageErrors.isNotEmpty) {
      throw stageErrors.removeAt(0);
    }
    if (stageFailures.remove(_stageAttempts++)) {
      throw const CatalogImportUnavailableException();
    }
    final importId = 'import-${++_stagedBatches}';
    _rowCounts[importId] = records.length;
    return _batch(
      importId: importId,
      rowCount: records.length,
      revision: 1,
      status: CatalogImportBatchStatus.staged,
    );
  }

  @override
  Future<CatalogImportBatchView> fetch({
    required String homeId,
    required String importId,
  }) async {
    fetchCalls.add(_FetchCall(homeId: homeId, importId: importId));
    return _batch(
      importId: importId,
      rowCount: _rowCounts[importId] ?? 1,
      revision: 7,
      status: CatalogImportBatchStatus.staged,
    );
  }

  @override
  Future<CatalogImportBatchView> confirm({
    required String homeId,
    required String importId,
    required int expectedRevision,
  }) async {
    confirmCalls.add(
      _ConfirmCall(
        homeId: homeId,
        importId: importId,
        expectedRevision: expectedRevision,
      ),
    );
    if (confirmErrors.isNotEmpty) {
      throw confirmErrors.removeAt(0);
    }
    final index = int.parse(importId.split('-').last) - 1;
    if (confirmConflicts.remove(index)) {
      throw const CatalogImportConflictException();
    }
    final rowCount = _rowCounts[importId] ?? 1;
    return _batch(
      importId: importId,
      rowCount: rowCount,
      revision: expectedRevision + 1,
      status: CatalogImportBatchStatus.confirmed,
      imported: rowCount,
    );
  }
}

CatalogImportBatchView _batch({
  required String importId,
  required int rowCount,
  required int revision,
  required CatalogImportBatchStatus status,
  int imported = 0,
}) => CatalogImportBatchView(
  id: importId,
  homeId: _homeId,
  status: status,
  rowCount: rowCount,
  validCount: rowCount,
  errorCount: 0,
  importedCount: imported,
  skippedCount: 0,
  revision: revision,
  rows: <CatalogImportRowView>[
    for (var position = 0; position < rowCount; position++)
      CatalogImportRowView(
        position: position,
        recordType: 'home_product',
        resolution: CatalogImportRowResolution.createPrivate,
        record: const <String, Object?>{'name': 'Item'},
      ),
  ],
);

final class _Fixture {
  _Fixture({
    List<PickedSpreadsheetFile?> pickResults = const <PickedSpreadsheetFile?>[],
    this.pickThrows,
  }) : _pickResults = List<PickedSpreadsheetFile?>.of(pickResults) {
    controller = CatalogImportController(
      homeId: _homeId,
      gateway: gateway,
      pickFile: _pick,
      parser: SpreadsheetTableParser(
        decodeXlsx: ({required sourceName, required bytes}) =>
            throw StateError('XLSX decoding is not scripted in this test'),
      ),
      idGenerator: () => 'generated-idempotency-key-${++_generatedKeys}',
      onAuthorizationLost: () async => authorizationLostCalls++,
    );
    addTearDown(controller.dispose);
  }

  final _ScriptedGateway gateway = _ScriptedGateway();
  final List<PickedSpreadsheetFile?> _pickResults;
  final Exception? pickThrows;
  late final CatalogImportController controller;
  int authorizationLostCalls = 0;
  int _generatedKeys = 0;

  Future<PickedSpreadsheetFile?> _pick() async {
    final failure = pickThrows;
    if (failure != null) throw failure;
    if (_pickResults.isEmpty) return null;
    return _pickResults.removeAt(0);
  }
}
