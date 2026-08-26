import 'package:file_picker/file_picker.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';

/// Platform file selection for spreadsheet imports.
///
/// Bytes are loaded directly into memory (`withData: true`) and handed to the
/// parser only. This path is intentionally separate from the AI media
/// acquisition registry: tabular household data never enters any media,
/// sanitization, or consent pipeline.
final class SpreadsheetFileSource {
  const SpreadsheetFileSource({
    this.pickPlatformFiles = _pickPlatformSpreadsheet,
  });

  final Future<FilePickerResult?> Function() pickPlatformFiles;

  /// Returns the selected spreadsheet, or `null` when the person cancels.
  Future<PickedSpreadsheetFile?> pick() async {
    final result = await pickPlatformFiles();
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final kind = SpreadsheetImportPolicy.kindForName(file.name);
    if (kind == null) {
      throw const SpreadsheetSelectionException(
        'Choose a .csv or .xlsx spreadsheet.',
      );
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const SpreadsheetSelectionException(
        'The selected file could not be read on this device.',
      );
    }
    if (bytes.length > SpreadsheetImportPolicy.maxFileBytes) {
      throw const SpreadsheetSelectionException(
        'Choose a spreadsheet of 10 MB or less.',
      );
    }
    return PickedSpreadsheetFile(name: file.name, kind: kind, bytes: bytes);
  }
}

Future<FilePickerResult?> _pickPlatformSpreadsheet() => FilePicker.pickFiles(
  withData: true,
  type: FileType.custom,
  allowedExtensions: const <String>['csv', 'xlsx'],
);
