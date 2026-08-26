import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/catalog_import/domain/csv_table_parser.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';

void main() {
  group('delimiter sniffing', () {
    test('prefers the semicolon when it dominates outside quotes', () {
      expect(
        CsvTableParser.sniffDelimiter('name;brand;barcode\noats;acme;123\n'),
        ';',
      );
    });

    test('prefers the comma when counts tie or nothing matches', () {
      expect(CsvTableParser.sniffDelimiter('a,b\nc;d\n'), ',');
      expect(CsvTableParser.sniffDelimiter('single column\nrows\n'), ',');
      expect(CsvTableParser.sniffDelimiter(''), ',');
    });

    test('ignores delimiters inside quoted fields', () {
      expect(CsvTableParser.sniffDelimiter('"a,a,a,a";b\n"c,c,c,c";d\n'), ';');
    });
  });

  group('parsing', () {
    test('splits unquoted fields on the sniffed delimiter', () {
      expect(CsvTableParser.parse('a,b,c\nd,e,f'), <List<String>>[
        <String>['a', 'b', 'c'],
        <String>['d', 'e', 'f'],
      ]);
      expect(CsvTableParser.parse('a;b\nc;d'), <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
      ]);
    });

    test('honors an explicit delimiter over sniffing', () {
      expect(CsvTableParser.parse('a;b;c', delimiter: ','), <List<String>>[
        <String>['a;b;c'],
      ]);
    });

    test('rejects an unsupported explicit delimiter', () {
      expect(
        () => CsvTableParser.parse('a\tb', delimiter: '\t'),
        throwsArgumentError,
      );
    });

    test('handles CRLF, bare CR, and a trailing newline without ghosts', () {
      expect(CsvTableParser.parse('a,b\r\nc,d\r\n'), <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
      ]);
      expect(CsvTableParser.parse('a,b\rc,d'), <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
      ]);
      expect(CsvTableParser.parse('a,b\n'), <List<String>>[
        <String>['a', 'b'],
      ]);
    });

    test('strips a UTF-8 byte-order mark before the first header', () {
      expect(CsvTableParser.parse('\uFEFFname,brand\na,b'), <List<String>>[
        <String>['name', 'brand'],
        <String>['a', 'b'],
      ]);
    });

    test('keeps delimiters, quotes, and line breaks inside quoted fields', () {
      expect(CsvTableParser.parse('"a,1",b\n"say ""hi""",d'), <List<String>>[
        <String>['a,1', 'b'],
        <String>['say "hi"', 'd'],
      ]);
      expect(CsvTableParser.parse('"line1\nline2",b'), <List<String>>[
        <String>['line1\nline2', 'b'],
      ]);
      expect(CsvTableParser.parse('"line1\r\nline2",b'), <List<String>>[
        <String>['line1\r\nline2', 'b'],
      ]);
    });

    test('treats a quote after field content as a literal character', () {
      expect(CsvTableParser.parse('5" screw,b'), <List<String>>[
        <String>['5" screw', 'b'],
      ]);
    });

    test('keeps text after a closing quote in the same field', () {
      expect(CsvTableParser.parse('"a"x,b'), <List<String>>[
        <String>['ax', 'b'],
      ]);
    });

    test('keeps the collected text when a final quote never closes', () {
      expect(CsvTableParser.parse('a,"unterminated'), <List<String>>[
        <String>['a', 'unterminated'],
      ]);
    });

    test('preserves empty fields, empty quoted fields, and ragged rows', () {
      expect(CsvTableParser.parse('a,,c\n"",""\nonly'), <List<String>>[
        <String>['a', '', 'c'],
        <String>['', ''],
        <String>['only'],
      ]);
    });

    test('returns no rows for empty input', () {
      expect(CsvTableParser.parse(''), isEmpty);
    });
  });

  group('grid building', () {
    test('pads ragged rows and drops trailing empty rows', () {
      final grid = CsvTableParser.parseGrid(
        sourceName: 'products.csv',
        text: 'name,brand,barcode\noats\n , , \n,,\n',
      );
      expect(grid.sourceName, 'products.csv');
      expect(grid.columnCount, 3);
      expect(grid.rows, <List<String>>[
        <String>['name', 'brand', 'barcode'],
        <String>['oats', '', ''],
      ]);
    });

    test('rejects input without any usable rows', () {
      expect(
        () => CsvTableParser.parseGrid(sourceName: 'empty.csv', text: ''),
        throwsA(isA<SpreadsheetParseException>()),
      );
      expect(
        () => CsvTableParser.parseGrid(sourceName: 'blank.csv', text: '\n\n'),
        throwsA(isA<SpreadsheetParseException>()),
      );
    });
  });
}
