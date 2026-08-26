import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';

/// Minimal, dependency-free CSV parsing for the spreadsheet import workflow.
///
/// The parser accepts RFC 4180 material plus the deviations common in
/// household exports: LF, CRLF, and bare-CR row endings, a UTF-8 byte-order
/// mark, semicolon-delimited locales, ragged rows, and unterminated trailing
/// quotes. Quoted fields may contain the delimiter, doubled quotes (`""`) and
/// line breaks; quote characters inside an unquoted field are kept literally.
abstract final class CsvTableParser {
  static const String comma = ',';
  static const String semicolon = ';';

  /// Chooses between comma and semicolon by counting candidate delimiters
  /// outside quoted regions across the first sniffed lines. Ties and
  /// delimiter-free input fall back to the comma.
  static String sniffDelimiter(String text, {int sniffedLines = 10}) {
    var commas = 0;
    var semicolons = 0;
    var inQuotes = false;
    var lines = 0;
    for (var i = 0; i < text.length && lines < sniffedLines; i++) {
      final character = text[i];
      if (character == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && character == comma) {
        commas++;
      } else if (!inQuotes && character == semicolon) {
        semicolons++;
      } else if (!inQuotes && (character == '\n' || character == '\r')) {
        lines++;
      }
    }
    return semicolons > commas ? semicolon : comma;
  }

  /// Parses [text] into rows of fields. When [delimiter] is omitted it is
  /// sniffed with [sniffDelimiter].
  static List<List<String>> parse(String text, {String? delimiter}) {
    var source = text;
    if (source.startsWith('\uFEFF')) {
      source = source.substring(1);
    }
    final separator = delimiter ?? sniffDelimiter(source);
    if (separator != comma && separator != semicolon) {
      throw ArgumentError.value(
        delimiter,
        'delimiter',
        'must be a comma or a semicolon',
      );
    }

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var rowHasContent = false;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      rows.add(List<String>.unmodifiable(row));
      row = <String>[];
      rowHasContent = false;
    }

    for (var i = 0; i < source.length; i++) {
      final character = source[i];
      if (inQuotes) {
        if (character == '"') {
          final isEscapedQuote = i + 1 < source.length && source[i + 1] == '"';
          if (isEscapedQuote) {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(character);
        }
        continue;
      }
      if (character == '"' && field.isEmpty) {
        inQuotes = true;
        rowHasContent = true;
      } else if (character == separator) {
        endField();
        rowHasContent = true;
      } else if (character == '\r') {
        if (i + 1 < source.length && source[i + 1] == '\n') {
          i++;
        }
        endRow();
      } else if (character == '\n') {
        endRow();
      } else {
        field.write(character);
        rowHasContent = true;
      }
    }
    if (inQuotes) {
      // An unterminated quote keeps the collected text as the final field.
      inQuotes = false;
    }
    if (rowHasContent || field.isNotEmpty || row.isNotEmpty) {
      endRow();
    }
    return List<List<String>>.unmodifiable(rows);
  }

  /// Parses CSV [text] into a normalized [SpreadsheetGrid].
  static SpreadsheetGrid parseGrid({
    required String sourceName,
    required String text,
    String? delimiter,
  }) {
    final rows = parse(text, delimiter: delimiter);
    if (rows.isEmpty) {
      throw const SpreadsheetParseException(
        'The selected spreadsheet contains no rows.',
      );
    }
    return SpreadsheetGrid(sourceName: sourceName, rows: rows);
  }
}
