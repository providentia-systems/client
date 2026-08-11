import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';

enum ReceiptPageTransform { rotateClockwise90, crop }

/// Performs receipt-page edits entirely in the transient local source store.
/// Every edit re-encodes pixels, so metadata is removed before the ordinary
/// sanitizer prepares the exact outbound bytes.
final class ReceiptPageMediaEditor {
  factory ReceiptPageMediaEditor({
    required RegisteredMediaSourceReader sources,
  }) => ReceiptPageMediaEditor._(sources);

  const ReceiptPageMediaEditor._(this._sources);

  final RegisteredMediaSourceReader _sources;

  Future<Uint8List> readPreview(AiMediaAsset asset) {
    _requireReceipt(asset);
    return _sources.read(asset);
  }

  Future<AiMediaAsset> transform({
    required AiMediaAsset asset,
    required ReceiptPageTransform transform,
    NormalizedRegion? crop,
  }) => switch (transform) {
    ReceiptPageTransform.rotateClockwise90 => rotateClockwise90(asset),
    ReceiptPageTransform.crop when crop != null => this.crop(
      asset,
      region: crop,
    ),
    ReceiptPageTransform.crop => throw ArgumentError(
      'A bounded crop region is required.',
    ),
  };

  Future<AiMediaAsset> rotateClockwise90(AiMediaAsset asset) async {
    _requireReceipt(asset);
    final source = await _sources.read(asset);
    final transformed = await Isolate.run(
      () => _rotateAndEncode(source, clockwiseDegrees: 90),
    );
    return _replace(asset, transformed);
  }

  Future<AiMediaAsset> crop(
    AiMediaAsset asset, {
    required NormalizedRegion region,
  }) async {
    _requireReceipt(asset);
    if (region.pageIndex != (asset.pageIndex ?? 0) ||
        !region.x.isFinite ||
        !region.y.isFinite ||
        !region.width.isFinite ||
        !region.height.isFinite ||
        region.x < 0 ||
        region.y < 0 ||
        region.width <= 0 ||
        region.height <= 0 ||
        region.x + region.width > 1 ||
        region.y + region.height > 1) {
      throw ArgumentError('The receipt crop must fit within its page.');
    }
    final source = await _sources.read(asset);
    final transformed = await Isolate.run(
      () => _cropAndEncode(
        source,
        x: region.x,
        y: region.y,
        width: region.width,
        height: region.height,
      ),
    );
    return _replace(asset, transformed);
  }

  Future<void> discard(Iterable<AiMediaAsset> assets) async {
    for (final asset in assets) {
      _sources.remove(asset.id);
    }
  }

  void _requireReceipt(AiMediaAsset asset) {
    if (asset.purpose != AiExtractionKind.receipt ||
        asset.homeId.trim().isEmpty) {
      throw StateError('Only a home-scoped receipt page can be edited.');
    }
  }

  AiMediaAsset _replace(AiMediaAsset original, _EditedImage transformed) {
    final digest = sha256.convert(transformed.bytes).toString();
    final replacement = AiMediaAsset(
      id: 'receipt-edit-${digest.substring(0, 20)}-page-${original.pageIndex ?? 0}',
      homeId: original.homeId,
      localReference: 'registered://receipt-edited',
      purpose: AiExtractionKind.receipt,
      mimeType: 'image/jpeg',
      byteLength: transformed.bytes.length,
      createdAt: original.createdAt,
      pageIndex: original.pageIndex,
      width: transformed.width,
      height: transformed.height,
    );
    _sources.register(replacement, transformed.bytes);
    if (replacement.id != original.id) {
      _sources.remove(original.id);
    }
    return replacement;
  }
}

final class _EditedImage {
  const _EditedImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

_EditedImage _rotateAndEncode(
  Uint8List bytes, {
  required num clockwiseDegrees,
}) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image.');
  final oriented = image.bakeOrientation(decoded);
  final rotated = image.copyRotate(oriented, angle: clockwiseDegrees);
  return _encode(rotated);
}

_EditedImage _cropAndEncode(
  Uint8List bytes, {
  required double x,
  required double y,
  required double width,
  required double height,
}) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image.');
  final oriented = image.bakeOrientation(decoded);
  final left = math.min(oriented.width - 1, (oriented.width * x).floor());
  final top = math.min(oriented.height - 1, (oriented.height * y).floor());
  final cropWidth = math.max(
    1,
    math.min(oriented.width - left, (oriented.width * width).round()),
  );
  final cropHeight = math.max(
    1,
    math.min(oriented.height - top, (oriented.height * height).round()),
  );
  final cropped = image.copyCrop(
    oriented,
    x: left,
    y: top,
    width: cropWidth,
    height: cropHeight,
  );
  return _encode(cropped);
}

_EditedImage _encode(image.Image value) {
  final bytes = Uint8List.fromList(image.encodeJpg(value, quality: 92));
  return _EditedImage(bytes, value.width, value.height);
}
