import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';

abstract interface class AiMediaSourceByteReader {
  Future<Uint8List> read(AiMediaAsset asset);
}

abstract interface class EphemeralPreparedMediaStore
    implements PreparedMediaByteReader {
  Future<String> write({required String id, required Uint8List bytes});

  Future<void> delete(String reference);
}

/// Testable memory store. Platform composition may replace it with an
/// encrypted temporary-file implementation without changing the workflow.
final class MemoryEphemeralPreparedMediaStore
    implements EphemeralPreparedMediaStore {
  final Map<String, Uint8List> _bytes = <String, Uint8List>{};

  @override
  Future<String> write({required String id, required Uint8List bytes}) async {
    final reference = 'ephemeral://$id';
    _bytes[reference] = Uint8List.fromList(bytes);
    return reference;
  }

  @override
  Future<Uint8List> read(PreparedAiMedia media) async {
    final bytes = _bytes[media.ephemeralReference];
    if (bytes == null) {
      throw StateError('Prepared media has already been removed.');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String reference) async {
    _bytes.remove(reference);
  }
}

/// Decodes and re-encodes selected images so EXIF/GPS metadata is removed,
/// orientation is baked into pixels, dimensions are bounded, and consent can
/// be tied to the exact SHA-256 bytes sent to a provider.
final class SanitizingImageMediaPreparer implements AiMediaPreparationPort {
  const SanitizingImageMediaPreparer({
    required AiMediaSourceByteReader sources,
    required EphemeralPreparedMediaStore prepared,
    this.maximumDimension = 4096,
    this.jpegQuality = 88,
  }) : _sources = sources,
       _prepared = prepared;

  final AiMediaSourceByteReader _sources;
  final EphemeralPreparedMediaStore _prepared;
  final int maximumDimension;
  final int jpegQuality;

  @override
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) async {
    if (homeId.trim().isEmpty || assets.isEmpty || assets.length > 16) {
      throw ArgumentError('A bounded, non-empty media selection is required.');
    }
    if (maximumDimension < 512 || jpegQuality < 60 || jpegQuality > 100) {
      throw StateError('The media preparation policy is invalid.');
    }
    if (assets.any(
      (asset) => asset.homeId != homeId || asset.purpose != purpose,
    )) {
      throw StateError('Media cannot cross home or workflow boundaries.');
    }

    final prepared = <PreparedAiMedia>[];
    try {
      for (var index = 0; index < assets.length; index++) {
        final asset = assets[index];
        final sourceBytes = await _sources.read(asset);
        if (sourceBytes.length != asset.byteLength) {
          throw StateError('Selected media changed before preparation.');
        }
        final encoded = await Isolate.run(
          () => _sanitize(sourceBytes, maximumDimension, jpegQuality),
        );
        final hash = sha256.convert(encoded.bytes).toString();
        final id = '${asset.id}-${hash.substring(0, 16)}';
        final reference = await _prepared.write(id: id, bytes: encoded.bytes);
        prepared.add(
          PreparedAiMedia(
            sourceMediaId: asset.id,
            ephemeralReference: reference,
            previewReference: reference,
            sha256: hash,
            mimeType: 'image/jpeg',
            byteLength: encoded.bytes.length,
            width: encoded.width,
            height: encoded.height,
            pageIndex: asset.pageIndex ?? index,
          ),
        );
      }
      final batchHash = sha256
          .convert(prepared.expand((item) => item.sha256.codeUnits).toList())
          .toString();
      return PreparedMediaBatch(
        id: 'prepared-${batchHash.substring(0, 24)}',
        homeId: homeId,
        purpose: purpose,
        media: prepared,
      );
    } on Object {
      for (final item in prepared) {
        await _prepared.delete(item.ephemeralReference);
      }
      rethrow;
    }
  }

  @override
  Future<void> discard(PreparedMediaBatch batch) async {
    for (final item in batch.media) {
      await _prepared.delete(item.ephemeralReference);
    }
  }
}

final class _EncodedImage {
  const _EncodedImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

_EncodedImage _sanitize(
  Uint8List bytes,
  int maximumDimension,
  int jpegQuality,
) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image.');
  var normalized = image.bakeOrientation(decoded);
  final largest = normalized.width > normalized.height
      ? normalized.width
      : normalized.height;
  if (largest > maximumDimension) {
    final scale = maximumDimension / largest;
    normalized = image.copyResize(
      normalized,
      width: (normalized.width * scale).round(),
      height: (normalized.height * scale).round(),
      interpolation: image.Interpolation.average,
    );
  }
  final encoded = Uint8List.fromList(
    image.encodeJpg(normalized, quality: jpegQuality),
  );
  return _EncodedImage(encoded, normalized.width, normalized.height);
}

/// Acquisition adapters can register transient picker bytes here without
/// exposing filesystem paths to the domain or logging them.
final class RegisteredMediaSourceReader implements AiMediaSourceByteReader {
  final Map<String, Uint8List> _sources = <String, Uint8List>{};

  UnmodifiableSetView<String> get registeredIds =>
      UnmodifiableSetView<String>(_sources.keys.toSet());

  void register(AiMediaAsset asset, Uint8List bytes) {
    if (bytes.length != asset.byteLength) {
      throw ArgumentError('Registered media length does not match metadata.');
    }
    _sources[asset.id] = Uint8List.fromList(bytes);
  }

  void remove(String assetId) => _sources.remove(assetId);

  @override
  Future<Uint8List> read(AiMediaAsset asset) async {
    final bytes = _sources[asset.id];
    if (bytes == null)
      throw StateError('Selected media is no longer available.');
    return Uint8List.fromList(bytes);
  }
}
