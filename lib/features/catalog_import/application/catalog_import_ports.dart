import 'dart:convert';
import 'dart:typed_data';

import 'package:providentia/features/catalog_import/domain/catalog_import_models.dart';
import 'package:providentia/features/catalog_import/domain/csv_table_parser.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';

/// Presents the platform file chooser and returns the selected spreadsheet,
/// or `null` when the person cancels. Implementations enforce the extension
/// and size policy and never route bytes through the AI media registry.
typedef SpreadsheetFilePick = Future<PickedSpreadsheetFile?> Function();

/// Decodes XLSX workbook bytes into a normalized grid.
typedef XlsxGridDecoder =
    SpreadsheetGrid Function({
      required String sourceName,
      required Uint8List bytes,
    });

/// The session ended before the import call completed.
final class CatalogImportAuthenticationRequiredException implements Exception {
  const CatalogImportAuthenticationRequiredException();
}

/// The active home no longer grants the catalog-import permission.
final class CatalogImportForbiddenException implements Exception {
  const CatalogImportForbiddenException();
}

/// The staged batch changed on the server since it was last read.
final class CatalogImportConflictException implements Exception {
  const CatalogImportConflictException();
}

/// The server rejected the staged records as invalid.
final class CatalogImportValidationException implements Exception {
  const CatalogImportValidationException();
}

/// The staged payload exceeded the server's size bound.
final class CatalogImportTooLargeException implements Exception {
  const CatalogImportTooLargeException();
}

/// The import service could not be reached or answered unexpectedly.
final class CatalogImportUnavailableException implements Exception {
  const CatalogImportUnavailableException();
}

/// Contract-shaped transport port for the three catalog-import operations.
abstract interface class CatalogImportGateway {
  /// Stages up to 500 records for review. Replaying the same
  /// [idempotencyKey] returns the already-staged batch unchanged.
  Future<CatalogImportBatchView> stage({
    required String homeId,
    required String idempotencyKey,
    required List<Map<String, Object?>> records,
  });

  /// Reads the current review state of one staged batch.
  Future<CatalogImportBatchView> fetch({
    required String homeId,
    required String importId,
  });

  /// Applies the reviewed batch at exactly [expectedRevision].
  Future<CatalogImportBatchView> confirm({
    required String homeId,
    required String importId,
    required int expectedRevision,
  });
}

/// Parses a picked file into a grid: CSV through the internal parser and
/// XLSX through the injected decoder.
final class SpreadsheetTableParser {
  const SpreadsheetTableParser({required this.decodeXlsx});

  final XlsxGridDecoder decodeXlsx;

  SpreadsheetGrid parse(PickedSpreadsheetFile file) {
    if (file.bytes.isEmpty) {
      throw const SpreadsheetParseException('The selected file is empty.');
    }
    if (file.bytes.length > SpreadsheetImportPolicy.maxFileBytes) {
      throw const SpreadsheetSelectionException(
        'Choose a spreadsheet of 10 MB or less.',
      );
    }
    return switch (file.kind) {
      SpreadsheetFileKind.csv => CsvTableParser.parseGrid(
        sourceName: file.name,
        text: _decodeText(file.bytes),
      ),
      SpreadsheetFileKind.xlsx => decodeXlsx(
        sourceName: file.name,
        bytes: file.bytes,
      ),
    };
  }

  static String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }
}
