import 'dart:collection';
import 'dart:typed_data';

/// Spreadsheet file kinds the import workflow accepts.
enum SpreadsheetFileKind { csv, xlsx }

/// Bounded selection and parsing policy for household spreadsheet imports.
///
/// The selection path is deliberately independent from the AI media
/// acquisition registry: spreadsheet bytes are tabular household data, never
/// media, and must not enter any consent-gated media pipeline.
abstract final class SpreadsheetImportPolicy {
  /// Upper bound on the selected file size.
  static const int maxFileBytes = 10 * 1024 * 1024;

  /// Upper bound on data rows in one import (ten staged batches of 500).
  static const int maxDataRows = 5000;

  static SpreadsheetFileKind? kindForName(String name) {
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return switch (extension) {
      'csv' => SpreadsheetFileKind.csv,
      'xlsx' => SpreadsheetFileKind.xlsx,
      _ => null,
    };
  }
}

/// One user-selected spreadsheet held fully in memory.
final class PickedSpreadsheetFile {
  PickedSpreadsheetFile({
    required this.name,
    required this.kind,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }

  final String name;
  final SpreadsheetFileKind kind;
  final Uint8List bytes;
}

/// The selected file could not be accepted. [safeMessage] never contains
/// filesystem paths or file contents.
final class SpreadsheetSelectionException implements Exception {
  const SpreadsheetSelectionException(this.safeMessage);

  final String safeMessage;
}

/// The selected file could not be parsed into rows. [safeMessage] never
/// contains filesystem paths or file contents.
final class SpreadsheetParseException implements Exception {
  const SpreadsheetParseException(this.safeMessage);

  final String safeMessage;
}

/// A rectangular grid of cell texts parsed from one sheet.
///
/// Rows are padded to a uniform column count and rows that are entirely empty
/// at the end of the sheet are dropped, so presentation and mapping logic can
/// index cells safely.
final class SpreadsheetGrid {
  factory SpreadsheetGrid({
    required String sourceName,
    required List<List<String>> rows,
  }) {
    final trimmed = List<List<String>>.of(rows);
    while (trimmed.isNotEmpty &&
        trimmed.last.every((cell) => cell.trim().isEmpty)) {
      trimmed.removeLast();
    }
    if (trimmed.isEmpty) {
      throw const SpreadsheetParseException(
        'The selected spreadsheet contains no rows.',
      );
    }
    var columnCount = 0;
    for (final row in trimmed) {
      if (row.length > columnCount) columnCount = row.length;
    }
    if (columnCount == 0) {
      throw const SpreadsheetParseException(
        'The selected spreadsheet contains no columns.',
      );
    }
    final padded = <List<String>>[
      for (final row in trimmed)
        List<String>.unmodifiable(<String>[
          ...row,
          for (var i = row.length; i < columnCount; i++) '',
        ]),
    ];
    return SpreadsheetGrid._(
      sourceName: sourceName,
      columnCount: columnCount,
      rows: UnmodifiableListView<List<String>>(padded),
    );
  }

  const SpreadsheetGrid._({
    required this.sourceName,
    required this.columnCount,
    required this.rows,
  });

  final String sourceName;
  final int columnCount;
  final List<List<String>> rows;
}
