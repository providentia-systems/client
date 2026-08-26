import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';

/// Decodes XLSX workbook bytes into the import grid with `excel_plus`.
///
/// The first sheet containing any row is used. Cell values are rendered as
/// display text: integral numbers lose the trailing `.0`, dates become
/// `yyyy-mm-dd`, and formula cells are kept as their literal formula text for
/// the person to review in the preview.
SpreadsheetGrid decodeXlsxGrid({
  required String sourceName,
  required Uint8List bytes,
}) {
  final Excel workbook;
  try {
    workbook = Excel.decodeBytes(bytes);
  } on ExcelException {
    throw const SpreadsheetParseException(
      'The selected file is not a readable Excel workbook.',
    );
  } on Exception {
    throw const SpreadsheetParseException(
      'The selected file is not a readable Excel workbook.',
    );
  }
  for (final sheet in workbook.tables.values) {
    if (sheet.rows.isEmpty) continue;
    return SpreadsheetGrid(
      sourceName: sourceName,
      rows: <List<String>>[
        for (final row in sheet.rows)
          <String>[for (final cell in row) _cellText(cell?.value)],
      ],
    );
  }
  throw const SpreadsheetParseException(
    'The selected spreadsheet contains no rows.',
  );
}

String _cellText(CellValue? value) => switch (value) {
  null => '',
  TextCellValue() => value.value.toString(),
  IntCellValue() => value.value.toString(),
  DoubleCellValue() =>
    value.value == value.value.roundToDouble() &&
            value.value.isFinite &&
            value.value.abs() < 1e15
        ? value.value.toInt().toString()
        : value.value.toString(),
  BoolCellValue() => value.value ? 'true' : 'false',
  DateCellValue() =>
    '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}',
  _ => value.toString(),
};
