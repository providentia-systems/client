import 'dart:collection';

import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';

/// How every record in one staged import is applied by the backend.
enum CatalogImportRecordType {
  catalogProductReference('catalog_product_reference'),
  homeProduct('home_product');

  const CatalogImportRecordType(this.wireName);

  final String wireName;
}

/// The contract fields a spreadsheet column can be assigned to.
enum CatalogImportField {
  productId('productId', 'Catalog product ID', 36),
  packId('packId', 'Catalog pack ID', 36),
  barcode('barcode', 'Barcode', 64),
  name('name', 'Name', 191),
  brand('brand', 'Brand', 120),
  privateName('privateName', 'Private name', 191),
  packText('packText', 'Pack size', 191);

  const CatalogImportField(this.wireName, this.label, this.maxLength);

  final String wireName;
  final String label;
  final int maxLength;
}

/// Import limits fixed by the pinned API 1.19.0 contract.
abstract final class CatalogImportPolicy {
  static const int maxRecordsPerStage = 500;
  static const String confirmationWord = 'apply_catalog_records';

  /// Splits [records] into staged batches of at most [maxRecordsPerStage].
  static List<List<Map<String, Object?>>> partition(
    List<Map<String, Object?>> records,
  ) {
    final batches = <List<Map<String, Object?>>>[];
    for (var start = 0; start < records.length; start += maxRecordsPerStage) {
      final end = start + maxRecordsPerStage > records.length
          ? records.length
          : start + maxRecordsPerStage;
      batches.add(
        List<Map<String, Object?>>.unmodifiable(records.sublist(start, end)),
      );
    }
    return List<List<Map<String, Object?>>>.unmodifiable(batches);
  }
}

/// Assignment of spreadsheet columns to contract record fields.
final class CatalogImportColumnMapping {
  factory CatalogImportColumnMapping(Map<int, CatalogImportField> assignments) {
    final seen = <CatalogImportField>{};
    for (final entry in assignments.entries) {
      if (entry.key < 0) {
        throw ArgumentError.value(
          entry.key,
          'assignments',
          'column indexes must not be negative',
        );
      }
      if (!seen.add(entry.value)) {
        throw ArgumentError.value(
          entry.value,
          'assignments',
          'each field may be assigned to only one column',
        );
      }
    }
    return CatalogImportColumnMapping._(
      UnmodifiableMapView<int, CatalogImportField>(
        Map<int, CatalogImportField>.of(assignments),
      ),
    );
  }

  const CatalogImportColumnMapping._(this.assignments);

  static const CatalogImportColumnMapping empty = CatalogImportColumnMapping._(
    <int, CatalogImportField>{},
  );

  final Map<int, CatalogImportField> assignments;

  CatalogImportField? fieldForColumn(int column) => assignments[column];

  bool get isEmpty => assignments.isEmpty;

  /// Returns a mapping with [column] assigned to [field]; a `null` [field]
  /// clears the column and a field already held by another column moves.
  CatalogImportColumnMapping assign(int column, CatalogImportField? field) {
    final next = Map<int, CatalogImportField>.of(assignments)..remove(column);
    if (field != null) {
      next.removeWhere((_, assigned) => assigned == field);
      next[column] = field;
    }
    return CatalogImportColumnMapping(next);
  }

  /// Maps header texts to fields by normalized-name heuristics. Each field is
  /// assigned at most once; the leftmost matching column wins.
  static CatalogImportColumnMapping fromHeaders(List<String> headers) {
    final assignments = <int, CatalogImportField>{};
    final taken = <CatalogImportField>{};
    for (var column = 0; column < headers.length; column++) {
      final field = suggestField(headers[column]);
      if (field != null && taken.add(field)) {
        assignments[column] = field;
      }
    }
    return CatalogImportColumnMapping(assignments);
  }

  /// Suggests the contract field for one header text, or `null`.
  static CatalogImportField? suggestField(String header) {
    final normalized = header.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (normalized.isEmpty) return null;
    for (final entry in _headerSynonyms.entries) {
      if (entry.value.contains(normalized)) return entry.key;
    }
    if (normalized.contains('barcode')) return CatalogImportField.barcode;
    if (normalized.contains('privatename') || normalized.contains('alias')) {
      return CatalogImportField.privateName;
    }
    if (normalized.contains('packid')) return CatalogImportField.packId;
    if (normalized.contains('productid')) return CatalogImportField.productId;
    if (normalized.contains('brand')) return CatalogImportField.brand;
    if (normalized.contains('pack') || normalized.contains('size')) {
      return CatalogImportField.packText;
    }
    if (normalized.contains('name')) return CatalogImportField.name;
    return null;
  }

  static const Map<CatalogImportField, Set<String>> _headerSynonyms =
      <CatalogImportField, Set<String>>{
        CatalogImportField.privateName: <String>{
          'privatename',
          'private',
          'alias',
          'nickname',
          'ownname',
          'customname',
        },
        CatalogImportField.productId: <String>{
          'productid',
          'catalogproductid',
          'catalogid',
        },
        CatalogImportField.packId: <String>{'packid', 'catalogpackid'},
        CatalogImportField.barcode: <String>{
          'barcode',
          'ean',
          'ean13',
          'gtin',
          'upc',
          'code',
        },
        CatalogImportField.brand: <String>{
          'brand',
          'brandname',
          'manufacturer',
          'make',
        },
        CatalogImportField.packText: <String>{
          'pack',
          'packsize',
          'packtext',
          'packaging',
          'size',
          'unitsize',
          'contents',
        },
        CatalogImportField.name: <String>{
          'name',
          'productname',
          'product',
          'canonicalname',
          'itemname',
          'item',
          'description',
          'title',
        },
      };
}

/// One spreadsheet row prepared as an exact contract record payload.
final class CatalogImportRecordDraft {
  CatalogImportRecordDraft({
    required this.sourceRowNumber,
    required Map<String, Object?> wireRecord,
  }) : wireRecord = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(wireRecord),
       ) {
    if (sourceRowNumber < 1) {
      throw ArgumentError.value(
        sourceRowNumber,
        'sourceRowNumber',
        'must be positive',
      );
    }
  }

  /// One-based row number in the source file, including any header row.
  final int sourceRowNumber;
  final Map<String, Object?> wireRecord;
}

/// One rejected spreadsheet row with a safe, displayable reason.
final class CatalogImportRowIssue {
  const CatalogImportRowIssue({
    required this.sourceRowNumber,
    required this.message,
  });

  final int sourceRowNumber;
  final String message;
}

/// Client-side validation of the mapped grid before anything is staged.
final class CatalogImportValidation {
  CatalogImportValidation({
    required List<CatalogImportRecordDraft> records,
    required List<CatalogImportRowIssue> issues,
    required this.emptyRowCount,
    this.blockingReason,
  }) : records = UnmodifiableListView<CatalogImportRecordDraft>(
         List<CatalogImportRecordDraft>.of(records),
       ),
       issues = UnmodifiableListView<CatalogImportRowIssue>(
         List<CatalogImportRowIssue>.of(issues),
       );

  final List<CatalogImportRecordDraft> records;
  final List<CatalogImportRowIssue> issues;
  final int emptyRowCount;
  final String? blockingReason;

  bool get mayStage => blockingReason == null && records.isNotEmpty;

  /// Validates every data row of [grid] under [mapping] and [recordType].
  ///
  /// Rows whose mapped cells are all empty are skipped and counted, mirroring
  /// padding rows in real exports. Rows with problems become issues and are
  /// excluded from [records]; validation never mutates the grid.
  static CatalogImportValidation of({
    required SpreadsheetGrid grid,
    required CatalogImportColumnMapping mapping,
    required CatalogImportRecordType recordType,
    required bool hasHeaderRow,
  }) {
    if (mapping.isEmpty) {
      return CatalogImportValidation(
        records: const <CatalogImportRecordDraft>[],
        issues: const <CatalogImportRowIssue>[],
        emptyRowCount: 0,
        blockingReason: 'Assign at least one column before staging.',
      );
    }
    final firstDataRow = hasHeaderRow ? 1 : 0;
    final dataRowCount = grid.rows.length - firstDataRow;
    if (dataRowCount > SpreadsheetImportPolicy.maxDataRows) {
      return CatalogImportValidation(
        records: const <CatalogImportRecordDraft>[],
        issues: const <CatalogImportRowIssue>[],
        emptyRowCount: 0,
        blockingReason:
            'This file has $dataRowCount data rows; one import accepts at '
            'most ${SpreadsheetImportPolicy.maxDataRows}.',
      );
    }
    final records = <CatalogImportRecordDraft>[];
    final issues = <CatalogImportRowIssue>[];
    var emptyRows = 0;
    for (var index = firstDataRow; index < grid.rows.length; index++) {
      final row = grid.rows[index];
      final sourceRowNumber = index + 1;
      final values = <CatalogImportField, String>{};
      for (final entry in mapping.assignments.entries) {
        final cell = entry.key < row.length ? row[entry.key].trim() : '';
        if (cell.isNotEmpty) values[entry.value] = cell;
      }
      if (values.isEmpty) {
        emptyRows++;
        continue;
      }
      final problem = _rowProblem(values, recordType);
      if (problem != null) {
        issues.add(
          CatalogImportRowIssue(
            sourceRowNumber: sourceRowNumber,
            message: problem,
          ),
        );
        continue;
      }
      records.add(
        CatalogImportRecordDraft(
          sourceRowNumber: sourceRowNumber,
          wireRecord: <String, Object?>{
            'recordType': recordType.wireName,
            for (final entry in values.entries) entry.key.wireName: entry.value,
          },
        ),
      );
    }
    if (records.isEmpty && issues.isEmpty) {
      return CatalogImportValidation(
        records: records,
        issues: issues,
        emptyRowCount: emptyRows,
        blockingReason: 'No mapped row contains a value to import.',
      );
    }
    return CatalogImportValidation(
      records: records,
      issues: issues,
      emptyRowCount: emptyRows,
    );
  }

  static String? _rowProblem(
    Map<CatalogImportField, String> values,
    CatalogImportRecordType recordType,
  ) {
    for (final entry in values.entries) {
      if (entry.value.length > entry.key.maxLength) {
        return '${entry.key.label} exceeds ${entry.key.maxLength} characters.';
      }
    }
    for (final identifier in <CatalogImportField>[
      CatalogImportField.productId,
      CatalogImportField.packId,
    ]) {
      final value = values[identifier];
      if (value != null && !isUuid(value)) {
        return '${identifier.label} is not a valid UUID.';
      }
    }
    return switch (recordType) {
      CatalogImportRecordType.catalogProductReference
          when !values.containsKey(CatalogImportField.productId) &&
              !values.containsKey(CatalogImportField.packId) &&
              !values.containsKey(CatalogImportField.barcode) =>
        'A catalog reference needs a product ID, pack ID, or barcode.',
      CatalogImportRecordType.homeProduct
          when !values.containsKey(CatalogImportField.name) &&
              !values.containsKey(CatalogImportField.privateName) =>
        'A private product needs a name or a private name.',
      _ => null,
    };
  }
}

/// Server states of one staged import batch.
enum CatalogImportBatchStatus {
  staged('staged'),
  confirming('confirming'),
  confirmed('confirmed');

  const CatalogImportBatchStatus(this.wireName);

  final String wireName;

  static CatalogImportBatchStatus parse(String value) => values.firstWhere(
    (status) => status.wireName == value,
    orElse: () => throw const FormatException('Unknown catalog-import status.'),
  );
}

/// Server resolution of one reviewed import row.
enum CatalogImportRowResolution {
  alreadyPresent('already_present'),
  linkCatalog('link_catalog'),
  createPrivate('create_private'),
  error('error');

  const CatalogImportRowResolution(this.wireName);

  final String wireName;

  static CatalogImportRowResolution parse(String value) => values.firstWhere(
    (resolution) => resolution.wireName == value,
    orElse: () =>
        throw const FormatException('Unknown catalog-import resolution.'),
  );
}

/// One reviewed row of a staged import batch as returned by the backend.
final class CatalogImportRowView {
  CatalogImportRowView({
    required this.position,
    required this.recordType,
    required this.resolution,
    required Map<String, Object?> record,
    this.errorCode,
    this.errorDetail,
  }) : record = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(record),
       ) {
    if (position < 0) {
      throw ArgumentError.value(position, 'position', 'must not be negative');
    }
  }

  final int position;
  final String recordType;
  final CatalogImportRowResolution resolution;
  final Map<String, Object?> record;
  final String? errorCode;
  final String? errorDetail;

  /// Best displayable label for the row without exposing raw payloads.
  String get displayName {
    for (final key in const <String>[
      'privateName',
      'name',
      'barcode',
      'productId',
      'packId',
    ]) {
      final value = record[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return 'Row ${position + 1}';
  }
}

/// One staged import batch with its per-row review resolutions.
final class CatalogImportBatchView {
  CatalogImportBatchView({
    required this.id,
    required this.homeId,
    required this.status,
    required this.rowCount,
    required this.validCount,
    required this.errorCount,
    required this.importedCount,
    required this.skippedCount,
    required this.revision,
    required List<CatalogImportRowView> rows,
    this.replayed = false,
  }) : rows = UnmodifiableListView<CatalogImportRowView>(
         List<CatalogImportRowView>.of(rows),
       ) {
    if (id.trim().isEmpty || homeId.trim().isEmpty) {
      throw ArgumentError('Batch identity must not be empty.');
    }
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
    for (final count in <int>[
      rowCount,
      validCount,
      errorCount,
      importedCount,
      skippedCount,
    ]) {
      if (count < 0) {
        throw ArgumentError.value(count, 'count', 'must not be negative');
      }
    }
  }

  final String id;
  final String homeId;
  final CatalogImportBatchStatus status;
  final int rowCount;
  final int validCount;
  final int errorCount;
  final int importedCount;
  final int skippedCount;
  final int revision;
  final bool replayed;
  final List<CatalogImportRowView> rows;

  bool get isConfirmed => status == CatalogImportBatchStatus.confirmed;

  int resolutionCount(CatalogImportRowResolution resolution) =>
      rows.where((row) => row.resolution == resolution).length;
}

/// Row-resolution totals across every batch of one import.
final class CatalogImportReconciliation {
  const CatalogImportReconciliation({
    required this.alreadyPresent,
    required this.linkCatalog,
    required this.createPrivate,
    required this.errors,
    required this.imported,
    required this.skipped,
  });

  factory CatalogImportReconciliation.of(List<CatalogImportBatchView> batches) {
    var alreadyPresent = 0;
    var linkCatalog = 0;
    var createPrivate = 0;
    var errors = 0;
    var imported = 0;
    var skipped = 0;
    for (final batch in batches) {
      alreadyPresent += batch.resolutionCount(
        CatalogImportRowResolution.alreadyPresent,
      );
      linkCatalog += batch.resolutionCount(
        CatalogImportRowResolution.linkCatalog,
      );
      createPrivate += batch.resolutionCount(
        CatalogImportRowResolution.createPrivate,
      );
      errors += batch.resolutionCount(CatalogImportRowResolution.error);
      imported += batch.importedCount;
      skipped += batch.skippedCount;
    }
    return CatalogImportReconciliation(
      alreadyPresent: alreadyPresent,
      linkCatalog: linkCatalog,
      createPrivate: createPrivate,
      errors: errors,
      imported: imported,
      skipped: skipped,
    );
  }

  final int alreadyPresent;
  final int linkCatalog;
  final int createPrivate;
  final int errors;
  final int imported;
  final int skipped;
}
