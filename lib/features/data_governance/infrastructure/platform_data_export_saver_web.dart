import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../application/data_export_ports.dart';
import '../domain/data_export_artifact.dart';

final class PlatformDataExportSaver implements DataExportSaver {
  @override
  Future<DataExportSaveResult> save(DataExportArtifact artifact) async {
    // Called by an explicit Save button, preserving the browser user gesture.
    // This local Blob is not a public URL and contains no download credential.
    final blob = web.Blob(
      <JSAny>[artifact.bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = artifact.filename;
    try {
      web.document.body?.append(anchor);
      anchor.click();
    } finally {
      anchor.remove();
      web.URL.revokeObjectURL(url);
    }
    // Browsers do not report whether the user completed or cancelled saving.
    return DataExportSaveResult.handedToBrowser;
  }

  @override
  Future<void> clearTemporaryState() async {}
}
