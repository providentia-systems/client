import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/catalog_import/application/catalog_import_controller.dart';
import 'package:providentia/features/catalog_import/application/catalog_import_ports.dart';
import 'package:providentia/features/catalog_import/domain/catalog_import_models.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';
import 'package:providentia/features/catalog_import/presentation/catalog_import_page.dart';

const String _homeId = 'home-1';
const Size _desktopSurface = Size(1400, 1000);

void main() {
  testWidgets('maps columns, previews rows, and stages for review', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_desktopSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _PageFixture(
      csv: 'name,brand\nRolled oats,Acme\nMilk,Dairyco\n',
    );
    await tester.pumpWidget(fixture.app);

    expect(find.byKey(const Key('catalog-import-pick-file')), findsOneWidget);
    await tester.tap(find.byKey(const Key('catalog-import-pick-file')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-import-record-type')), findsOneWidget);
    expect(find.byKey(const Key('catalog-import-column-0')), findsOneWidget);
    expect(find.byKey(const Key('catalog-import-column-1')), findsOneWidget);
    expect(find.byKey(const Key('catalog-import-preview')), findsOneWidget);
    expect(find.text('Rolled oats'), findsOneWidget);
    expect(find.text('Dairyco'), findsOneWidget);
    expect(
      find.text('2 rows ready · 0 with problems · 0 empty skipped'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Stage 2 rows for review'),
              matching: find.byType(FilledButton),
            ),
          )
          .enabled,
      isTrue,
    );

    // Unmapping the only value-bearing columns blocks staging.
    await tester.tap(find.byKey(const Key('catalog-import-column-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignored').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-import-column-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignored').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Assign at least one column before staging.'),
      findsOneWidget,
    );

    // Remap the first column and change the record type to catalog links.
    await tester.tap(find.byKey(const Key('catalog-import-column-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Barcode').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link to catalog'));
    await tester.pumpAndSettle();
    expect(
      find.text('2 rows ready · 0 with problems · 0 empty skipped'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('catalog-import-stage')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-import-review')), findsOneWidget);
    expect(fixture.gateway.stageCalls.single.records.first, <String, Object?>{
      'recordType': 'catalog_product_reference',
      'barcode': 'Rolled oats',
    });
  });

  testWidgets('review renders per-resolution counts and row errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_desktopSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _PageFixture(csv: 'name\nOats\nMilk\nBread\nJam\n');
    await tester.pumpWidget(fixture.app);
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalog-import-count-already-present')),
      findsOneWidget,
    );
    expect(find.text('1 already present'), findsOneWidget);
    expect(find.text('1 link to catalog'), findsOneWidget);
    expect(find.text('1 new private'), findsOneWidget);
    expect(find.text('1 with errors'), findsOneWidget);
    expect(find.byKey(const Key('catalog-import-batch-0')), findsOneWidget);
    expect(find.textContaining('Jam — barcode is unknown'), findsOneWidget);
  });

  testWidgets('confirmation happens only through the summary dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_desktopSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _PageFixture(csv: 'name\nOats\nMilk\nBread\nJam\n');
    await tester.pumpWidget(fixture.app);
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('catalog-import-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('catalog-import-confirm-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('1 row with errors'), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-import-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(fixture.gateway.confirmCalls, isEmpty);
    expect(find.byKey(const Key('catalog-import-review')), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-import-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-import-confirm-apply')));
    await tester.pumpAndSettle();

    expect(fixture.gateway.confirmCalls.single.expectedRevision, 4);
    expect(
      find.byKey(const Key('catalog-import-reconciliation')),
      findsOneWidget,
    );
    expect(find.text('3 rows imported'), findsOneWidget);
    expect(find.text('1 rows skipped'), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-import-start-over')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catalog-import-pick-file')), findsOneWidget);
  });

  testWidgets('a revision conflict re-renders the refreshed review', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(_desktopSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _PageFixture(
      csv: 'name\nOats\nMilk\nBread\nJam\n',
      conflictOnFirstConfirm: true,
    );
    await tester.pumpWidget(fixture.app);
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('catalog-import-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-import-confirm-apply')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-import-review')), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-import-safe-message')),
      findsOneWidget,
    );
    expect(find.textContaining('changed elsewhere'), findsOneWidget);
    expect(fixture.gateway.fetchCalls, hasLength(1));
  });

  testWidgets('denied access renders the fail-closed state', (tester) async {
    await tester.binding.setSurfaceSize(_desktopSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _PageFixture(csv: 'name\nOats\n', forbidStage: true);
    await tester.pumpWidget(fixture.app);
    await fixture.controller.pickSpreadsheet();
    await fixture.controller.stage();
    await tester.pumpAndSettle();

    expect(find.text('Catalog-import permission required'), findsOneWidget);
    expect(find.byKey(const Key('catalog-import-confirm')), findsNothing);
  });
}

final class _PageFixture {
  _PageFixture({
    required String csv,
    bool conflictOnFirstConfirm = false,
    bool forbidStage = false,
  }) : gateway = _ReviewGateway(
         conflictOnFirstConfirm: conflictOnFirstConfirm,
         forbidStage: forbidStage,
       ) {
    controller = CatalogImportController(
      homeId: _homeId,
      gateway: gateway,
      pickFile: () async => PickedSpreadsheetFile(
        name: 'products.csv',
        kind: SpreadsheetFileKind.csv,
        bytes: Uint8List.fromList(utf8.encode(csv)),
      ),
      parser: SpreadsheetTableParser(
        decodeXlsx: ({required sourceName, required bytes}) =>
            throw StateError('XLSX decoding is not scripted in this test'),
      ),
      idGenerator: () => 'widget-test-idempotency-key-${++_keys}',
      onAuthorizationLost: () async {},
    );
    addTearDown(controller.dispose);
    app = MaterialApp(home: CatalogImportPage(controller: controller));
  }

  final _ReviewGateway gateway;
  late final CatalogImportController controller;
  late final MaterialApp app;
  int _keys = 0;
}

final class _StagePayload {
  const _StagePayload({required this.records});

  final List<Map<String, Object?>> records;
}

final class _ConfirmPayload {
  const _ConfirmPayload({required this.expectedRevision});

  final int expectedRevision;
}

final class _FetchPayload {
  const _FetchPayload();
}

/// Gateway whose staged review cycles resolutions per row: already present,
/// link catalog, create private, then an unknown-barcode error.
final class _ReviewGateway implements CatalogImportGateway {
  _ReviewGateway({
    required this.conflictOnFirstConfirm,
    required this.forbidStage,
  });

  final bool conflictOnFirstConfirm;
  final bool forbidStage;
  final List<_StagePayload> stageCalls = <_StagePayload>[];
  final List<_ConfirmPayload> confirmCalls = <_ConfirmPayload>[];
  final List<_FetchPayload> fetchCalls = <_FetchPayload>[];
  var _conflicted = false;

  static const List<CatalogImportRowResolution> _cycle =
      <CatalogImportRowResolution>[
        CatalogImportRowResolution.alreadyPresent,
        CatalogImportRowResolution.linkCatalog,
        CatalogImportRowResolution.createPrivate,
        CatalogImportRowResolution.error,
      ];

  @override
  Future<CatalogImportBatchView> stage({
    required String homeId,
    required String idempotencyKey,
    required List<Map<String, Object?>> records,
  }) async {
    if (forbidStage) throw const CatalogImportForbiddenException();
    stageCalls.add(_StagePayload(records: records));
    return _view(records.length, revision: 4, confirmed: false);
  }

  @override
  Future<CatalogImportBatchView> fetch({
    required String homeId,
    required String importId,
  }) async {
    fetchCalls.add(const _FetchPayload());
    return _view(
      stageCalls.single.records.length,
      revision: 9,
      confirmed: false,
    );
  }

  @override
  Future<CatalogImportBatchView> confirm({
    required String homeId,
    required String importId,
    required int expectedRevision,
  }) async {
    if (conflictOnFirstConfirm && !_conflicted) {
      _conflicted = true;
      throw const CatalogImportConflictException();
    }
    confirmCalls.add(_ConfirmPayload(expectedRevision: expectedRevision));
    return _view(
      stageCalls.single.records.length,
      revision: expectedRevision + 1,
      confirmed: true,
    );
  }

  CatalogImportBatchView _view(
    int rowCount, {
    required int revision,
    required bool confirmed,
  }) {
    const names = <String>['Oats', 'Milk', 'Bread', 'Jam'];
    final errorCount = rowCount >= _cycle.length ? 1 : 0;
    return CatalogImportBatchView(
      id: 'import-1',
      homeId: _homeId,
      status: confirmed
          ? CatalogImportBatchStatus.confirmed
          : CatalogImportBatchStatus.staged,
      rowCount: rowCount,
      validCount: rowCount - errorCount,
      errorCount: errorCount,
      importedCount: confirmed ? rowCount - errorCount : 0,
      skippedCount: confirmed ? errorCount : 0,
      revision: revision,
      rows: <CatalogImportRowView>[
        for (var position = 0; position < rowCount; position++)
          CatalogImportRowView(
            position: position,
            recordType: 'home_product',
            resolution: _cycle[position % _cycle.length],
            record: <String, Object?>{'name': names[position % names.length]},
            errorDetail:
                _cycle[position % _cycle.length] ==
                    CatalogImportRowResolution.error
                ? 'barcode is unknown'
                : null,
          ),
      ],
    );
  }
}
