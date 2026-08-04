import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';

final class MediaAcquisitionException implements Exception {
  const MediaAcquisitionException(this.safeMessage);

  final String safeMessage;
}

typedef MediaFilePicker =
    Future<FilePickerResult?> Function({required bool allowMultiple});

/// Camera, gallery and file-system acquisition with bounded in-memory bytes.
/// Nothing is transmitted until preparation, disclosure and explicit consent.
final class MediaAcquisitionService {
  factory MediaAcquisitionService({
    required RegisteredMediaSourceReader registry,
    ImagePicker? imagePicker,
    MediaFilePicker? filePicker,
    int maximumSourceBytes = 25 * 1024 * 1024,
  }) => MediaAcquisitionService._(
    registry,
    imagePicker ?? ImagePicker(),
    filePicker ?? _pickPlatformFiles,
    maximumSourceBytes,
  );

  MediaAcquisitionService._(
    this._registry,
    this._imagePicker,
    this._filePicker,
    this.maximumSourceBytes,
  );

  final RegisteredMediaSourceReader _registry;
  final ImagePicker _imagePicker;
  final MediaFilePicker _filePicker;
  final int maximumSourceBytes;

  Future<AiMediaAsset?> takePhoto({
    required String homeId,
    required AiExtractionKind purpose,
  }) async {
    final selected = await _imagePicker.pickImage(source: ImageSource.camera);
    return selected == null
        ? null
        : _registerXFile(selected, homeId: homeId, purpose: purpose);
  }

  Future<List<AiMediaAsset>> choosePhotos({
    required String homeId,
    required AiExtractionKind purpose,
    int limit = 12,
  }) async {
    final selected = await _imagePicker.pickMultiImage(limit: limit);
    return Future.wait(
      selected.map(
        (file) => _registerXFile(file, homeId: homeId, purpose: purpose),
      ),
    );
  }

  Future<AiMediaAsset?> recordVideo({
    required String homeId,
    required AiExtractionKind purpose,
    Duration maximumDuration = const Duration(seconds: 45),
  }) async {
    final selected = await _imagePicker.pickVideo(
      source: ImageSource.camera,
      maxDuration: maximumDuration,
    );
    return selected == null
        ? null
        : _registerXFile(selected, homeId: homeId, purpose: purpose);
  }

  Future<List<AiMediaAsset>> chooseFiles({
    required String homeId,
    required AiExtractionKind purpose,
    bool allowMultiple = true,
  }) async {
    final result = await _filePicker(allowMultiple: allowMultiple);
    if (result == null) return const <AiMediaAsset>[];
    final assets = <AiMediaAsset>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        throw const MediaAcquisitionException(
          'The selected file could not be read on this device.',
        );
      }
      assets.add(
        _registerBytes(
          bytes,
          name: file.name,
          mimeType: _mimeType(file.extension),
          homeId: homeId,
          purpose: purpose,
        ),
      );
    }
    return assets;
  }

  Future<AiMediaAsset> _registerXFile(
    XFile file, {
    required String homeId,
    required AiExtractionKind purpose,
  }) async {
    final bytes = await file.readAsBytes();
    return _registerBytes(
      bytes,
      name: file.name,
      mimeType: file.mimeType ?? _mimeType(file.name.split('.').last),
      homeId: homeId,
      purpose: purpose,
    );
  }

  AiMediaAsset _registerBytes(
    Uint8List bytes, {
    required String name,
    required String mimeType,
    required String homeId,
    required AiExtractionKind purpose,
  }) {
    if (bytes.length < 16 || bytes.length > maximumSourceBytes) {
      throw const MediaAcquisitionException(
        'The selected file is empty or exceeds the 25 MB safety limit.',
      );
    }
    final digest = sha256.convert(bytes).toString();
    final asset = AiMediaAsset(
      id: 'source-${digest.substring(0, 24)}',
      homeId: homeId,
      localReference: 'registered://$name',
      purpose: purpose,
      mimeType: mimeType,
      byteLength: bytes.length,
      createdAt: DateTime.now().toUtc(),
    );
    _registry.register(asset, bytes);
    return asset;
  }
}

Future<FilePickerResult?> _pickPlatformFiles({required bool allowMultiple}) =>
    FilePicker.pickFiles(
      allowMultiple: allowMultiple,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>[
        'jpg',
        'jpeg',
        'png',
        'webp',
        'pdf',
        'mp4',
        'mov',
        'webm',
      ],
    );

String _mimeType(String? extension) => switch (extension?.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'webp' => 'image/webp',
  'pdf' => 'application/pdf',
  'mp4' => 'video/mp4',
  'mov' => 'video/quicktime',
  'webm' => 'video/webm',
  _ => 'application/octet-stream',
};
