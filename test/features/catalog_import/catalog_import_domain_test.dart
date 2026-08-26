import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/catalog_import/domain/catalog_import_models.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';

void main() {
  group('header mapping heuristics', () {
    test('maps common export headers to contract fields', () {
      final mapping = CatalogImportColumnMapping.fromHeaders(const <String>[
        'Product Name',
        'Brand',
        'EAN',
        'Pack size',
        'Private name',
        'Catalog product id',
        'Pack ID',
      ]);
      expect(mapping.assignments, <int, CatalogImportField>{
        0: CatalogImportField.name,
        1: CatalogImportField.brand,
        2: CatalogImportField.barcode,
        3: CatalogImportField.packText,
        4: CatalogImportField.privateName,
        5: CatalogImportField.productId,
        6: CatalogImportField.packId,
      });
    });

    test('normalizes punctuation and case before matching', () {
      expect(
        CatalogImportColumnMapping.suggestField(' BAR-CODE '),
        CatalogImportField.barcode,
      );
      expect(
        CatalogImportColumnMapping.suggestField('item_name'),
        CatalogImportField.name,
      );
      expect(
        CatalogImportColumnMapping.suggestField('GTIN'),
        CatalogImportField.barcode,
      );
      expect(
        CatalogImportColumnMapping.suggestField('Manufacturer'),
        CatalogImportField.brand,
      );
      expect(
        CatalogImportColumnMapping.suggestField('Own name'),
        CatalogImportField.privateName,
      );
      expect(CatalogImportColumnMapping.suggestField('quantity'), isNull);
      expect(CatalogImportColumnMapping.suggestField(''), isNull);
    });

    test('never maps private-name headers to the public name field', () {
      expect(
        CatalogImportColumnMapping.suggestField('private name'),
        CatalogImportField.privateName,
      );
      expect(
        CatalogImportColumnMapping.suggestField('privateName'),
        CatalogImportField.privateName,
      );
    });

    test('assigns each field once with the leftmost column winning', () {
      final mapping = CatalogImportColumnMapping.fromHeaders(const <String>[
        'name',
        'product name',
        'barcode',
      ]);
      expect(mapping.assignments, <int, CatalogImportField>{
        0: CatalogImportField.name,
        2: CatalogImportField.barcode,
      });
    });
  });

  group('column mapping edits', () {
    test('reassigning a field moves it and clearing removes it', () {
      var mapping = CatalogImportColumnMapping.fromHeaders(const <String>[
        'name',
        'brand',
      ]);
      mapping = mapping.assign(1, CatalogImportField.name);
      expect(mapping.assignments, <int, CatalogImportField>{
        1: CatalogImportField.name,
      });
      mapping = mapping.assign(1, null);
      expect(mapping.isEmpty, isTrue);
    });

    test('rejects duplicate field assignments and negative columns', () {
      expect(
        () => CatalogImportColumnMapping(<int, CatalogImportField>{
          0: CatalogImportField.name,
          1: CatalogImportField.name,
        }),
        throwsArgumentError,
      );
      expect(
        () => CatalogImportColumnMapping(<int, CatalogImportField>{
          -1: CatalogImportField.name,
        }),
        throwsArgumentError,
      );
    });
  });

  group('row validation', () {
    SpreadsheetGrid grid(List<List<String>> rows) =>
        SpreadsheetGrid(sourceName: 'products.csv', rows: rows);

    test('builds exact wire records and skips empty rows', () {
      final validation = CatalogImportValidation.of(
        grid: grid(<List<String>>[
          <String>['name', 'brand', 'barcode'],
          <String>[' Rolled oats ', 'Acme', '6001234567890'],
          <String>['', '', ''],
          <String>['Milk', '', ''],
        ]),
        mapping: CatalogImportColumnMapping.fromHeaders(const <String>[
          'name',
          'brand',
          'barcode',
        ]),
        recordType: CatalogImportRecordType.homeProduct,
        hasHeaderRow: true,
      );
      expect(validation.mayStage, isTrue);
      expect(validation.emptyRowCount, 1);
      expect(validation.issues, isEmpty);
      expect(validation.records, hasLength(2));
      expect(validation.records.first.sourceRowNumber, 2);
      expect(validation.records.first.wireRecord, <String, Object?>{
        'recordType': 'home_product',
        'name': 'Rolled oats',
        'brand': 'Acme',
        'barcode': '6001234567890',
      });
      expect(validation.records.last.wireRecord, <String, Object?>{
        'recordType': 'home_product',
        'name': 'Milk',
      });
    });

    test('flags rows missing the required fields for their record type', () {
      final validation = CatalogImportValidation.of(
        grid: grid(<List<String>>[
          <String>['brand', 'barcode'],
          <String>['Acme', ''],
          <String>['Acme', '6001234567890'],
        ]),
        mapping: CatalogImportColumnMapping.fromHeaders(const <String>[
          'brand',
          'barcode',
        ]),
        recordType: CatalogImportRecordType.catalogProductReference,
        hasHeaderRow: true,
      );
      expect(validation.records, hasLength(1));
      expect(validation.issues, hasLength(1));
      expect(validation.issues.single.sourceRowNumber, 2);
      expect(validation.issues.single.message, contains('barcode'));

      final privateValidation = CatalogImportValidation.of(
        grid: grid(<List<String>>[
          <String>['brand'],
          <String>['Acme'],
        ]),
        mapping: CatalogImportColumnMapping.fromHeaders(const <String>[
          'brand',
        ]),
        recordType: CatalogImportRecordType.homeProduct,
        hasHeaderRow: true,
      );
      expect(privateValidation.records, isEmpty);
      expect(privateValidation.issues.single.message, contains('name'));
    });

    test('flags overlong values and malformed identifiers', () {
      final overlong = 'x' * 192;
      final validation = CatalogImportValidation.of(
        grid: grid(<List<String>>[
          <String>['name', 'product id'],
          <String>[overlong, ''],
          <String>['Milk', 'not-a-uuid'],
          <String>['Oats', '2b1f4f60-9d6a-4b86-9e34-3f6f3f0a9d21'],
        ]),
        mapping: CatalogImportColumnMapping.fromHeaders(const <String>[
          'name',
          'product id',
        ]),
        recordType: CatalogImportRecordType.homeProduct,
        hasHeaderRow: true,
      );
      expect(validation.records, hasLength(1));
      expect(validation.records.single.sourceRowNumber, 4);
      expect(validation.issues, hasLength(2));
      expect(validation.issues.first.message, contains('191'));
      expect(validation.issues.last.message, contains('UUID'));
    });

    test('respects the header toggle when numbering rows', () {
      final validation = CatalogImportValidation.of(
        grid: grid(<List<String>>[
          <String>['Rolled oats'],
          <String>['Milk'],
        ]),
        mapping: CatalogImportColumnMapping(const <int, CatalogImportField>{
          0: CatalogImportField.name,
        }),
        recordType: CatalogImportRecordType.homeProduct,
        hasHeaderRow: false,
      );
      expect(validation.records, hasLength(2));
      expect(validation.records.first.sourceRowNumber, 1);
    });

    test('blocks staging without a mapping, rows, or within-bounds size', () {
      final unmapped = CatalogImportValidation.of(
        grid: grid(<List<String>>[
          <String>['name'],
          <String>['Milk'],
        ]),
        mapping: CatalogImportColumnMapping.empty,
        recordType: CatalogImportRecordType.homeProduct,
        hasHeaderRow: true,
      );
      expect(unmapped.mayStage, isFalse);
      expect(unmapped.blockingReason, contains('at least one column'));

      final empty = CatalogImportValidation.of(
        grid: grid(<List<String>>[
          <String>['name'],
          <String>[''],
        ]),
        mapping: CatalogImportColumnMapping(const <int, CatalogImportField>{
          0: CatalogImportField.name,
        }),
        recordType: CatalogImportRecordType.homeProduct,
        hasHeaderRow: true,
      );
      expect(empty.mayStage, isFalse);
      expect(empty.blockingReason, contains('No mapped row'));

      final oversized = CatalogImportValidation.of(
        grid: grid(<List<String>>[
          <String>['name'],
          for (var row = 0; row <= SpreadsheetImportPolicy.maxDataRows; row++)
            <String>['Row $row'],
        ]),
        mapping: CatalogImportColumnMapping(const <int, CatalogImportField>{
          0: CatalogImportField.name,
        }),
        recordType: CatalogImportRecordType.homeProduct,
        hasHeaderRow: true,
      );
      expect(oversized.mayStage, isFalse);
      expect(oversized.blockingReason, contains('5000'));
    });
  });

  group('batch partitioning and reconciliation', () {
    test('partitions records into contract-sized stages', () {
      final records = List<Map<String, Object?>>.generate(
        1101,
        (index) => <String, Object?>{'recordType': 'home_product'},
      );
      final batches = CatalogImportPolicy.partition(records);
      expect(batches.map((batch) => batch.length), <int>[500, 500, 101]);
      expect(
        CatalogImportPolicy.partition(records.take(500).toList()),
        hasLength(1),
      );
    });

    test('aggregates counts by resolution across batches', () {
      final reconciliation = CatalogImportReconciliation.of(
        <CatalogImportBatchView>[
          _batch(
            resolutions: const <CatalogImportRowResolution>[
              CatalogImportRowResolution.alreadyPresent,
              CatalogImportRowResolution.linkCatalog,
              CatalogImportRowResolution.createPrivate,
            ],
            imported: 2,
            skipped: 1,
          ),
          _batch(
            resolutions: const <CatalogImportRowResolution>[
              CatalogImportRowResolution.error,
              CatalogImportRowResolution.createPrivate,
            ],
            imported: 1,
            skipped: 1,
          ),
        ],
      );
      expect(reconciliation.alreadyPresent, 1);
      expect(reconciliation.linkCatalog, 1);
      expect(reconciliation.createPrivate, 2);
      expect(reconciliation.errors, 1);
      expect(reconciliation.imported, 3);
      expect(reconciliation.skipped, 2);
    });

    test('row views surface a safe display name', () {
      final named = CatalogImportRowView(
        position: 0,
        recordType: 'home_product',
        resolution: CatalogImportRowResolution.createPrivate,
        record: const <String, Object?>{'name': 'Rolled oats'},
      );
      expect(named.displayName, 'Rolled oats');
      final anonymous = CatalogImportRowView(
        position: 4,
        recordType: 'home_product',
        resolution: CatalogImportRowResolution.error,
        record: const <String, Object?>{},
      );
      expect(anonymous.displayName, 'Row 5');
    });
  });
}

CatalogImportBatchView _batch({
  required List<CatalogImportRowResolution> resolutions,
  required int imported,
  required int skipped,
}) => CatalogImportBatchView(
  id: 'import-1',
  homeId: 'home-1',
  status: CatalogImportBatchStatus.confirmed,
  rowCount: resolutions.length,
  validCount: resolutions
      .where((resolution) => resolution != CatalogImportRowResolution.error)
      .length,
  errorCount: resolutions
      .where((resolution) => resolution == CatalogImportRowResolution.error)
      .length,
  importedCount: imported,
  skippedCount: skipped,
  revision: 2,
  rows: <CatalogImportRowView>[
    for (var index = 0; index < resolutions.length; index++)
      CatalogImportRowView(
        position: index,
        recordType: 'home_product',
        resolution: resolutions[index],
        record: const <String, Object?>{'name': 'Item'},
      ),
  ],
);
