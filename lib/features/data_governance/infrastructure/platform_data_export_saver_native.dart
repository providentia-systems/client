import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../application/data_export_ports.dart';
import '../domain/data_export_artifact.dart';

final class PlatformDataExportSaver implements DataExportSaver {
  static const _channel = MethodChannel('providentia/data-export');
  var _generation = 0;

  @override
  Future<DataExportSaveResult> save(DataExportArtifact artifact) async {
    final generation = ++_generation;
    if (Platform.isIOS) {
      // file_picker 11.0.3 leaves a plaintext Documents copy on iOS. The owned
      // bridge instead uses excluded-from-backup, file-protected temporary
      // storage and removes it on success, cancellation, and the next launch.
      final saved = await _channel.invokeMethod<bool>('save', <String, Object?>{
        'filename': artifact.filename,
        'bytes': artifact.bytes,
      });
      return saved == true
          ? DataExportSaveResult.saved
          : DataExportSaveResult.cancelled;
    }
    if (Platform.isAndroid) {
      final destination = await FilePicker.saveFile(
        fileName: artifact.filename,
        bytes: artifact.bytes,
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
      );
      return destination == null
          ? DataExportSaveResult.cancelled
          : DataExportSaveResult.saved;
    }
    final destination = await FilePicker.saveFile(
      dialogTitle: 'Save a private Providentia export copy',
      fileName: artifact.filename,
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      lockParentWindow: true,
    );
    if (destination == null || generation != _generation || artifact.disposed) {
      return DataExportSaveResult.cancelled;
    }
    // Only a user-selected destination is written; no application cache file.
    await File(destination).writeAsBytes(artifact.bytes, flush: true);
    return DataExportSaveResult.saved;
  }

  @override
  Future<void> clearTemporaryState() async {
    _generation++;
    if (Platform.isIOS) await _channel.invokeMethod<void>('discard');
  }
}
