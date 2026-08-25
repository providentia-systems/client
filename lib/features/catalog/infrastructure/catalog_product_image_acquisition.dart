import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:providentia/features/catalog/application/catalog_product_image_service.dart';
import 'package:providentia/features/catalog/domain/catalog_product_image_models.dart';

typedef CatalogImageFilePicker = Future<FilePickerResult?> Function();

/// Camera/gallery/file acquisition for one transient catalog image.
///
/// Original names and filesystem paths are discarded. Format is detected from
/// bytes, dimensions are read before Flutter preview decoding, and only one
/// bounded in-memory copy crosses into the application controller.
final class CatalogProductImageAcquirer {
  factory CatalogProductImageAcquirer({
    ImagePicker? imagePicker,
    CatalogImageFilePicker? filePicker,
  }) => CatalogProductImageAcquirer._(
    imagePicker ?? ImagePicker(),
    filePicker ?? _pickImageFile,
  );

  const CatalogProductImageAcquirer._(this._imagePicker, this._filePicker);

  final ImagePicker _imagePicker;
  final CatalogImageFilePicker _filePicker;

  Future<CatalogProductImageDraft?> chooseGallery() async {
    final selected = await _imagePicker.pickImage(source: ImageSource.gallery);
    return selected == null ? null : fromXFile(selected);
  }

  Future<CatalogProductImageDraft?> chooseFile() async {
    final result = await _filePicker();
    if (result == null || result.files.isEmpty) return null;
    if (result.files.length != 1) {
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.unreadable,
        'Choose exactly one image.',
      );
    }
    final file = result.files.single;
    _validateEncodedLength(file.size);
    final bytes = file.bytes;
    if (bytes == null) {
      final path = file.path;
      if (path != null && path.trim().isNotEmpty) {
        return fromXFile(XFile(path, name: file.name, length: file.size));
      }
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.unreadable,
        'The selected image could not be read on this device.',
      );
    }
    if (bytes.length != file.size) {
      bytes.fillRange(0, bytes.length, 0);
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.unreadable,
        'The selected image changed while it was being read.',
      );
    }
    return _draftAndWipe(bytes);
  }

  Future<CatalogProductImageDraft> fromXFile(XFile file) async {
    int length;
    try {
      length = await file.length();
    } on Object {
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.unreadable,
        'The selected image could not be read on this device.',
      );
    }
    _validateEncodedLength(length);
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object {
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.unreadable,
        'The selected image could not be read on this device.',
      );
    }
    if (bytes.length != length) {
      bytes.fillRange(0, bytes.length, 0);
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.unreadable,
        'The selected image changed while it was being read.',
      );
    }
    return _draftAndWipe(bytes);
  }

  CatalogProductImageDraft _draftAndWipe(Uint8List bytes) {
    try {
      final detected = _inspect(bytes);
      return CatalogProductImageDraft(
        bytes: bytes,
        mediaType: detected.mediaType,
        width: detected.width,
        height: detected.height,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  ({CatalogProductImageMediaType mediaType, int width, int height}) _inspect(
    Uint8List bytes,
  ) {
    late final image.Decoder decoder;
    late final CatalogProductImageMediaType mediaType;
    if (_isJpeg(bytes)) {
      decoder = image.JpegDecoder();
      mediaType = CatalogProductImageMediaType.jpeg;
    } else if (_isPng(bytes)) {
      decoder = image.PngDecoder();
      mediaType = CatalogProductImageMediaType.png;
    } else if (_isWebp(bytes)) {
      decoder = image.WebPDecoder();
      mediaType = CatalogProductImageMediaType.webp;
    } else {
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.unsupported,
        'Choose a JPEG, PNG, or WebP image.',
      );
    }

    try {
      final information = decoder.startDecode(bytes);
      if (information == null) {
        throw const FormatException('Invalid image header.');
      }
      final width = information.width;
      final height = information.height;
      if (width < CatalogProductImageDraft.minimumDimension ||
          height < CatalogProductImageDraft.minimumDimension ||
          width > CatalogProductImageDraft.maximumDimension ||
          height > CatalogProductImageDraft.maximumDimension ||
          width * height > CatalogProductImageDraft.maximumPixels) {
        throw const CatalogProductImageAcquisitionException(
          CatalogProductImageAcquisitionFailureKind.invalidDimensions,
          'Choose an image between 16 and 4096 pixels per side.',
        );
      }
      return (mediaType: mediaType, width: width, height: height);
    } on CatalogProductImageAcquisitionException {
      rethrow;
    } on Object {
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.unsupported,
        'The selected image could not be decoded safely.',
      );
    }
  }

  void _validateEncodedLength(int length) {
    if (length > CatalogProductImageDraft.maximumBytes) {
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.tooLarge,
        'Choose an image no larger than 5 MiB.',
      );
    }
    if (length < CatalogProductImageDraft.minimumBytes) {
      throw const CatalogProductImageAcquisitionException(
        CatalogProductImageAcquisitionFailureKind.unsupported,
        'The selected image is empty or incomplete.',
      );
    }
  }
}

Future<FilePickerResult?> _pickImageFile() => FilePicker.pickFiles(
  allowMultiple: false,
  withData: true,
  type: FileType.custom,
  allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp'],
);

bool _isJpeg(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xff &&
    bytes[1] == 0xd8 &&
    bytes[2] == 0xff;

bool _isPng(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4e &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0d &&
    bytes[5] == 0x0a &&
    bytes[6] == 0x1a &&
    bytes[7] == 0x0a;

bool _isWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    bytes[0] == 0x52 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46 &&
    bytes[3] == 0x46 &&
    bytes[8] == 0x57 &&
    bytes[9] == 0x45 &&
    bytes[10] == 0x42 &&
    bytes[11] == 0x50;
