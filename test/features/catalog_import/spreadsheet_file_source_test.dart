import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';
import 'package:providentia/features/catalog_import/infrastructure/spreadsheet_file_source.dart';

void main() {
  test('returns the selected spreadsheet with its bytes and kind', () async {
    final bytes = Uint8List.fromList('name\nRolled oats\n'.codeUnits);
    final source = SpreadsheetFileSource(
      pickPlatformFiles: () async => FilePickerResult(<PlatformFile>[
        PlatformFile(name: 'products.CSV', size: bytes.length, bytes: bytes),
      ]),
    );

    final picked = await source.pick();

    expect(picked, isNotNull);
    expect(picked!.name, 'products.CSV');
    expect(picked.kind, SpreadsheetFileKind.csv);
    expect(picked.bytes, bytes);
  });

  test('recognizes the xlsx extension case-insensitively', () {
    expect(
      SpreadsheetImportPolicy.kindForName('Products.XLSX'),
      SpreadsheetFileKind.xlsx,
    );
    expect(SpreadsheetImportPolicy.kindForName('products.xls'), isNull);
    expect(SpreadsheetImportPolicy.kindForName('products'), isNull);
  });

  test('cancelling returns null', () async {
    final source = SpreadsheetFileSource(pickPlatformFiles: () async => null);
    expect(await source.pick(), isNull);
  });

  test('rejects unsupported extensions before reading bytes', () async {
    final source = SpreadsheetFileSource(
      pickPlatformFiles: () async => FilePickerResult(<PlatformFile>[
        PlatformFile(
          name: 'products.ods',
          size: 4,
          bytes: Uint8List.fromList(const <int>[1, 2, 3, 4]),
        ),
      ]),
    );
    await expectLater(
      source.pick(),
      throwsA(
        isA<SpreadsheetSelectionException>().having(
          (error) => error.safeMessage,
          'safeMessage',
          contains('.csv or .xlsx'),
        ),
      ),
    );
  });

  test('rejects selections without in-memory bytes', () async {
    final source = SpreadsheetFileSource(
      pickPlatformFiles: () async => FilePickerResult(<PlatformFile>[
        PlatformFile(name: 'products.csv', size: 10),
      ]),
    );
    await expectLater(
      source.pick(),
      throwsA(isA<SpreadsheetSelectionException>()),
    );
  });

  test('rejects files above the 10 MB bound', () async {
    final oversized = Uint8List(SpreadsheetImportPolicy.maxFileBytes + 1);
    final source = SpreadsheetFileSource(
      pickPlatformFiles: () async => FilePickerResult(<PlatformFile>[
        PlatformFile(
          name: 'products.xlsx',
          size: oversized.length,
          bytes: oversized,
        ),
      ]),
    );
    await expectLater(
      source.pick(),
      throwsA(
        isA<SpreadsheetSelectionException>().having(
          (error) => error.safeMessage,
          'safeMessage',
          contains('10 MB'),
        ),
      ),
    );
  });
}
