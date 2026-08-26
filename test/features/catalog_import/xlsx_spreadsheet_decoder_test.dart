import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';
import 'package:providentia/features/catalog_import/infrastructure/xlsx_spreadsheet_decoder.dart';

void main() {
  test('decodes an in-test workbook into display texts', () {
    final workbook = Excel.createExcel();
    final sheet = workbook[workbook.tables.keys.first];
    void put(String cell, CellValue value) =>
        sheet.updateCell(CellIndex.indexByString(cell), value);
    put('A1', TextCellValue('name'));
    put('B1', TextCellValue('barcode'));
    put('C1', TextCellValue('pack'));
    put('D1', TextCellValue('counted'));
    put('E1', TextCellValue('added'));
    put('A2', TextCellValue('Rolled oats'));
    put('B2', const IntCellValue(6001234567890));
    put('C2', const DoubleCellValue(1.5));
    put('D2', const BoolCellValue(true));
    put('E2', DateCellValue(year: 2026, month: 8, day: 5));
    put('A3', TextCellValue('Milk'));
    put('B3', const DoubleCellValue(7290000000001));

    final grid = decodeXlsxGrid(
      sourceName: 'products.xlsx',
      bytes: Uint8List.fromList(workbook.save()!),
    );

    expect(grid.sourceName, 'products.xlsx');
    expect(grid.columnCount, 5);
    expect(grid.rows, <List<String>>[
      <String>['name', 'barcode', 'pack', 'counted', 'added'],
      <String>['Rolled oats', '6001234567890', '1.5', 'true', '2026-08-05'],
      <String>['Milk', '7290000000001', '', '', ''],
    ]);
  });

  test('renders integral doubles without a trailing decimal', () {
    final workbook = Excel.createExcel();
    final sheet = workbook[workbook.tables.keys.first];
    sheet.updateCell(CellIndex.indexByString('A1'), const DoubleCellValue(8));
    final grid = decodeXlsxGrid(
      sourceName: 'numbers.xlsx',
      bytes: Uint8List.fromList(workbook.save()!),
    );
    expect(grid.rows.single.single, '8');
  });

  test('rejects bytes that are not a readable workbook', () {
    expect(
      () => decodeXlsxGrid(
        sourceName: 'broken.xlsx',
        bytes: Uint8List.fromList(List<int>.generate(64, (index) => index)),
      ),
      throwsA(isA<SpreadsheetParseException>()),
    );
  });

  test('rejects a workbook whose sheets contain no rows', () {
    final workbook = Excel.createExcel();
    expect(
      () => decodeXlsxGrid(
        sourceName: 'empty.xlsx',
        bytes: Uint8List.fromList(workbook.save()!),
      ),
      throwsA(isA<SpreadsheetParseException>()),
    );
  });
}
