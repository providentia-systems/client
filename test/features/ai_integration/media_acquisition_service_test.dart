import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/media_acquisition_service.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';

void main() {
  test(
    'camera, gallery, and video bytes become registered local assets',
    () async {
      final registry = RegisteredMediaSourceReader();
      final picker = _FakeImagePicker(
        image: _file('receipt.jpeg', 32),
        images: <XFile>[_file('pantry.png', 40), _file('shelf.webp', 48)],
        video: _file('stock.mov', 64),
      );
      final service = MediaAcquisitionService(
        registry: registry,
        imagePicker: picker,
      );

      final photo = await service.takePhoto(
        homeId: 'home-1',
        purpose: AiExtractionKind.receipt,
      );
      final gallery = await service.choosePhotos(
        homeId: 'home-1',
        purpose: AiExtractionKind.stockPhoto,
        limit: 2,
      );
      final video = await service.recordVideo(
        homeId: 'home-1',
        purpose: AiExtractionKind.stockPhoto,
        maximumDuration: const Duration(seconds: 30),
      );

      expect(photo, isNotNull);
      expect(photo?.mimeType, 'image/jpeg');
      expect(gallery.map((asset) => asset.mimeType), <String>[
        'image/png',
        'image/webp',
      ]);
      expect(video?.mimeType, 'video/quicktime');
      expect(registry.registeredIds, hasLength(4));
      expect(picker.lastImageSource, ImageSource.camera);
      expect(picker.lastMultiImageLimit, 2);
      expect(picker.lastVideoSource, ImageSource.camera);
      expect(picker.lastVideoDuration, const Duration(seconds: 30));
    },
  );

  test(
    'picker cancellation returns empty results without registration',
    () async {
      final registry = RegisteredMediaSourceReader();
      final service = MediaAcquisitionService(
        registry: registry,
        imagePicker: _FakeImagePicker(),
      );

      expect(
        await service.takePhoto(
          homeId: 'home-1',
          purpose: AiExtractionKind.receipt,
        ),
        isNull,
      );
      expect(
        await service.choosePhotos(
          homeId: 'home-1',
          purpose: AiExtractionKind.stockPhoto,
        ),
        isEmpty,
      );
      expect(
        await service.recordVideo(
          homeId: 'home-1',
          purpose: AiExtractionKind.stockPhoto,
        ),
        isNull,
      );
      expect(registry.registeredIds, isEmpty);
    },
  );

  test('source byte limits fail closed before registration', () async {
    Future<void> expectRejected(int length) async {
      final registry = RegisteredMediaSourceReader();
      final service = MediaAcquisitionService(
        registry: registry,
        imagePicker: _FakeImagePicker(image: _file('receipt.jpg', length)),
        maximumSourceBytes: 40,
      );

      await expectLater(
        service.takePhoto(homeId: 'home-1', purpose: AiExtractionKind.receipt),
        throwsA(isA<MediaAcquisitionException>()),
      );
      expect(registry.registeredIds, isEmpty);
    }

    await expectRejected(8);
    await expectRejected(41);
  });

  test(
    'file picker imports supported media with explicit MIME types',
    () async {
      final registry = RegisteredMediaSourceReader();
      bool? requestedMultiple;
      final service = MediaAcquisitionService(
        registry: registry,
        imagePicker: _FakeImagePicker(),
        filePicker: ({required bool allowMultiple}) async {
          requestedMultiple = allowMultiple;
          return FilePickerResult(<PlatformFile>[
            PlatformFile(name: 'receipt.pdf', size: 32, bytes: _raw(32)),
            PlatformFile(name: 'stock.mp4', size: 33, bytes: _raw(33)),
            PlatformFile(name: 'stock.webm', size: 34, bytes: _raw(34)),
            PlatformFile(name: 'unknown.bin', size: 35, bytes: _raw(35)),
          ]);
        },
      );

      final assets = await service.chooseFiles(
        homeId: 'home-1',
        purpose: AiExtractionKind.stockPhoto,
        allowMultiple: false,
      );

      expect(requestedMultiple, isFalse);
      expect(assets.map((asset) => asset.mimeType), <String>[
        'application/pdf',
        'video/mp4',
        'video/webm',
        'application/octet-stream',
      ]);
      expect(registry.registeredIds, hasLength(4));
    },
  );

  test('file picker cancellation and missing bytes fail safely', () async {
    final cancelled = MediaAcquisitionService(
      registry: RegisteredMediaSourceReader(),
      imagePicker: _FakeImagePicker(),
      filePicker: ({required bool allowMultiple}) async => null,
    );
    expect(
      await cancelled.chooseFiles(
        homeId: 'home-1',
        purpose: AiExtractionKind.receipt,
      ),
      isEmpty,
    );

    final unreadable = MediaAcquisitionService(
      registry: RegisteredMediaSourceReader(),
      imagePicker: _FakeImagePicker(),
      filePicker: ({required bool allowMultiple}) async => FilePickerResult(
        <PlatformFile>[PlatformFile(name: 'receipt.pdf', size: 32)],
      ),
    );
    await expectLater(
      unreadable.chooseFiles(
        homeId: 'home-1',
        purpose: AiExtractionKind.receipt,
      ),
      throwsA(isA<MediaAcquisitionException>()),
    );
  });
}

XFile _file(String name, int length) => XFile.fromData(
  _raw(length),
  name: name,
  mimeType: switch (name.split('.').last) {
    'jpeg' || 'jpg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'mov' => 'video/quicktime',
    _ => 'application/octet-stream',
  },
);

Uint8List _raw(int length) =>
    Uint8List.fromList(List<int>.generate(length, (index) => index % 251));

final class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker({this.image, this.images = const <XFile>[], this.video});

  final XFile? image;
  final List<XFile> images;
  final XFile? video;

  ImageSource? lastImageSource;
  int? lastMultiImageLimit;
  ImageSource? lastVideoSource;
  Duration? lastVideoDuration;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    lastImageSource = source;
    return image;
  }

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    lastMultiImageLimit = limit;
    return images;
  }

  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    lastVideoSource = source;
    lastVideoDuration = maxDuration;
    return video;
  }
}
