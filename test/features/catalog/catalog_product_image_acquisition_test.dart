import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:providentia/features/catalog/application/catalog_product_image_service.dart';
import 'package:providentia/features/catalog/domain/catalog_product_image_models.dart';
import 'package:providentia/features/catalog/infrastructure/catalog_product_image_acquisition.dart';

void main() {
  test(
    'format, dimensions and digest come from bytes rather than filename',
    () async {
      final bytes = _png(32, 24);
      final expected = Uint8List.fromList(bytes);
      final acquirer = CatalogProductImageAcquirer(
        imagePicker: _ImagePicker(
          image: XFile.fromData(
            bytes,
            name: 'misleading.pdf',
            mimeType: 'application/pdf',
          ),
        ),
      );

      final draft = await acquirer.chooseGallery();

      expect(draft, isNotNull);
      expect(draft?.mediaType, CatalogProductImageMediaType.png);
      expect(draft?.width, 32);
      expect(draft?.height, 24);
      expect(draft?.byteLength, expected.length);
      expect(draft?.sourceDigest, hasLength(64));
      expect(bytes, everyElement(0), reason: 'picker buffer is wiped');
      expect(draft?.previewBytes, expected);
      draft?.release();
    },
  );

  test('file upload derives WebP despite a misleading extension', () async {
    final bytes = Uint8List.fromList(
      image.encodeWebP(image.Image(width: 20, height: 30)),
    );
    final acquirer = CatalogProductImageAcquirer(
      filePicker: () async => FilePickerResult(<PlatformFile>[
        PlatformFile(name: 'photo.jpg', size: bytes.length, bytes: bytes),
      ]),
    );

    final draft = await acquirer.chooseFile();

    expect(draft?.mediaType, CatalogProductImageMediaType.webp);
    expect(draft?.width, 20);
    expect(draft?.height, 30);
    expect(bytes, everyElement(0));
    draft?.release();
  });

  test(
    'desktop file path works when the picker omits in-memory bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'providentia-catalog-image-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/misleading.txt');
      final bytes = _png(18, 22);
      await file.writeAsBytes(bytes, flush: true);
      final acquirer = CatalogProductImageAcquirer(
        filePicker: () async => FilePickerResult(<PlatformFile>[
          PlatformFile(
            name: 'misleading.txt',
            path: file.path,
            size: bytes.length,
          ),
        ]),
      );

      final draft = await acquirer.chooseFile();

      expect(draft?.mediaType, CatalogProductImageMediaType.png);
      expect(draft?.width, 18);
      expect(draft?.height, 22);
      expect(await file.exists(), isTrue);
      draft?.release();
    },
  );

  test('size, format, dimension and read failures are distinct', () async {
    Future<void> expectKind(
      CatalogProductImageAcquirer acquirer,
      CatalogProductImageAcquisitionFailureKind kind,
    ) async {
      await expectLater(
        acquirer.chooseFile(),
        throwsA(
          isA<CatalogProductImageAcquisitionException>().having(
            (error) => error.kind,
            'kind',
            kind,
          ),
        ),
      );
    }

    await expectKind(
      CatalogProductImageAcquirer(
        filePicker: () async => FilePickerResult(<PlatformFile>[
          PlatformFile(
            name: 'huge.png',
            size: CatalogProductImageDraft.maximumBytes + 1,
          ),
        ]),
      ),
      CatalogProductImageAcquisitionFailureKind.tooLarge,
    );
    await expectKind(
      CatalogProductImageAcquirer(
        filePicker: () async => FilePickerResult(<PlatformFile>[
          PlatformFile(name: 'fake.jpg', size: 32, bytes: Uint8List(32)),
        ]),
      ),
      CatalogProductImageAcquisitionFailureKind.unsupported,
    );
    final tiny = _png(8, 8);
    await expectKind(
      CatalogProductImageAcquirer(
        filePicker: () async => FilePickerResult(<PlatformFile>[
          PlatformFile(name: 'tiny.png', size: tiny.length, bytes: tiny),
        ]),
      ),
      CatalogProductImageAcquisitionFailureKind.invalidDimensions,
    );
    await expectKind(
      CatalogProductImageAcquirer(
        filePicker: () async => FilePickerResult(<PlatformFile>[
          PlatformFile(name: 'missing.png', size: 128),
        ]),
      ),
      CatalogProductImageAcquisitionFailureKind.unreadable,
    );
  });

  test('released image overwrites bytes and cannot be read again', () {
    final source = _png(16, 16);
    final draft = CatalogProductImageDraft(
      bytes: source,
      mediaType: CatalogProductImageMediaType.png,
      width: 16,
      height: 16,
    );
    final view = draft.previewBytes;

    draft.release();

    expect(draft.isReleased, isTrue);
    expect(view, everyElement(0));
    expect(draft.copyBytes, throwsStateError);
    expect(() => draft.previewBytes, throwsStateError);
  });
}

Uint8List _png(int width, int height) => Uint8List.fromList(
  image.encodePng(image.Image(width: width, height: height)),
);

final class _ImagePicker extends ImagePicker {
  _ImagePicker({this.image});

  final XFile? image;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => image;
}
