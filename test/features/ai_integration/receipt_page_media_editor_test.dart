import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/receipt_page_media_editor.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';

void main() {
  test(
    'rotate and crop replace local pixels before outbound preparation',
    () async {
      final sources = RegisteredMediaSourceReader();
      final editor = ReceiptPageMediaEditor(sources: sources);
      final original = image.Image(width: 40, height: 20);
      image.fill(original, color: image.ColorRgb8(220, 20, 20));
      final originalBytes = Uint8List.fromList(image.encodePng(original));
      final asset = _asset(
        'receipt-page-0',
        originalBytes.length,
        pageIndex: 0,
      );
      sources.register(asset, originalBytes);

      final rotated = await editor.rotateClockwise90(asset);
      final rotatedPixels = image.decodeJpg(await editor.readPreview(rotated));

      expect(rotated.mimeType, 'image/jpeg');
      expect(rotated.width, 20);
      expect(rotated.height, 40);
      expect(rotatedPixels?.width, 20);
      expect(rotatedPixels?.height, 40);
      expect(sources.registeredIds, isNot(contains(asset.id)));

      final cropped = await editor.crop(
        rotated,
        region: const NormalizedRegion(
          pageIndex: 0,
          x: 0.25,
          y: 0.25,
          width: 0.5,
          height: 0.5,
        ),
      );
      final croppedPixels = image.decodeJpg(await editor.readPreview(cropped));

      expect(cropped.width, 10);
      expect(cropped.height, 20);
      expect(croppedPixels?.width, 10);
      expect(croppedPixels?.height, 20);
      expect(sources.registeredIds, <String>{cropped.id});

      await editor.discard(<AiMediaAsset>[cropped]);
      expect(sources.registeredIds, isEmpty);
    },
  );

  test('crop is page-bound and never crosses receipt or home scope', () async {
    final sources = RegisteredMediaSourceReader();
    final editor = ReceiptPageMediaEditor(sources: sources);
    final bytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 20, height: 20)),
    );
    final asset = _asset('receipt-page-1', bytes.length, pageIndex: 1);
    sources.register(asset, bytes);

    await expectLater(
      editor.crop(
        asset,
        region: const NormalizedRegion(
          pageIndex: 0,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      editor.rotateClockwise90(
        _asset(
          'stock-page',
          bytes.length,
          pageIndex: 0,
          purpose: AiExtractionKind.stockPhoto,
        ),
      ),
      throwsStateError,
    );
    expect(sources.registeredIds, <String>{asset.id});
  });
}

AiMediaAsset _asset(
  String id,
  int byteLength, {
  required int pageIndex,
  AiExtractionKind purpose = AiExtractionKind.receipt,
}) => AiMediaAsset(
  id: id,
  homeId: 'home-1',
  localReference: 'registered://$id',
  purpose: purpose,
  mimeType: 'image/png',
  byteLength: byteLength,
  createdAt: DateTime.utc(2026, 8, 11),
  pageIndex: pageIndex,
);
