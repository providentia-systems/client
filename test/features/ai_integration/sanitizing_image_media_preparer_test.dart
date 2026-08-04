import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';

void main() {
  test('registered source reader owns a defensive transient copy', () async {
    final reader = RegisteredMediaSourceReader();
    final bytes = Uint8List.fromList(List<int>.generate(32, (index) => index));
    final asset = _asset('source-1', bytes.length);

    reader.register(asset, bytes);
    bytes[0] = 255;

    expect(reader.registeredIds, <String>{'source-1'});
    expect((await reader.read(asset)).first, 0);
    expect(
      () => reader.register(_asset('bad', 31), bytes),
      throwsArgumentError,
    );

    reader.remove(asset.id);
    expect(() => reader.read(asset), throwsStateError);
  });

  test('memory prepared store copies bytes and deletes them', () async {
    final store = MemoryEphemeralPreparedMediaStore();
    final bytes = Uint8List.fromList(List<int>.generate(24, (index) => index));
    final reference = await store.write(id: 'prepared-1', bytes: bytes);
    final media = _prepared(reference, bytes.length);

    bytes[0] = 255;
    final firstRead = await store.read(media);
    expect(firstRead.first, 0);
    firstRead[1] = 255;
    expect((await store.read(media))[1], 1);

    await store.delete(reference);
    expect(() => store.read(media), throwsStateError);
  });

  test('preparer resizes, re-encodes, hashes, and discards images', () async {
    final source = RegisteredMediaSourceReader();
    final prepared = MemoryEphemeralPreparedMediaStore();
    final original = image.Image(width: 800, height: 400);
    image.fill(original, color: image.ColorRgb8(40, 120, 200));
    final bytes = Uint8List.fromList(image.encodePng(original));
    final asset = _asset('source-wide', bytes.length, pageIndex: 3);
    source.register(asset, bytes);
    final preparer = SanitizingImageMediaPreparer(
      sources: source,
      prepared: prepared,
      maximumDimension: 512,
      jpegQuality: 80,
    );

    final batch = await preparer.prepare(
      homeId: 'home-1',
      purpose: AiExtractionKind.stockPhoto,
      assets: <AiMediaAsset>[asset],
    );

    expect(batch.id, startsWith('prepared-'));
    expect(batch.homeId, 'home-1');
    expect(batch.media, hasLength(1));
    final media = batch.media.single;
    expect(media.sourceMediaId, asset.id);
    expect(media.mimeType, 'image/jpeg');
    expect(media.width, 512);
    expect(media.height, 256);
    expect(media.pageIndex, 3);
    expect(media.sha256, hasLength(64));
    final sanitized = await prepared.read(media);
    expect(image.decodeJpg(sanitized), isNotNull);

    await preparer.discard(batch);
    expect(() => prepared.read(media), throwsStateError);
  });

  test('preparer rejects invalid policy and cross-home media', () async {
    final source = RegisteredMediaSourceReader();
    final prepared = MemoryEphemeralPreparedMediaStore();
    final bytes = Uint8List.fromList(List<int>.filled(32, 1));
    final asset = _asset('source-1', bytes.length);
    source.register(asset, bytes);

    final invalidPolicy = SanitizingImageMediaPreparer(
      sources: source,
      prepared: prepared,
      maximumDimension: 256,
    );
    expect(
      () => invalidPolicy.prepare(
        homeId: 'home-1',
        purpose: AiExtractionKind.stockPhoto,
        assets: <AiMediaAsset>[asset],
      ),
      throwsStateError,
    );

    final preparer = SanitizingImageMediaPreparer(
      sources: source,
      prepared: prepared,
    );
    expect(
      () => preparer.prepare(
        homeId: 'home-2',
        purpose: AiExtractionKind.stockPhoto,
        assets: <AiMediaAsset>[asset],
      ),
      throwsStateError,
    );
    expect(
      () => preparer.prepare(
        homeId: 'home-1',
        purpose: AiExtractionKind.stockPhoto,
        assets: const <AiMediaAsset>[],
      ),
      throwsArgumentError,
    );
  });

  test(
    'preparer removes earlier output when a later image is invalid',
    () async {
      final source = RegisteredMediaSourceReader();
      final prepared = _RecordingPreparedStore();
      final validImage = image.Image(width: 16, height: 16);
      final validBytes = Uint8List.fromList(image.encodePng(validImage));
      final invalidBytes = Uint8List.fromList(List<int>.filled(32, 1));
      final valid = _asset('valid', validBytes.length);
      final invalid = _asset('invalid', invalidBytes.length);
      source.register(valid, validBytes);
      source.register(invalid, invalidBytes);
      final preparer = SanitizingImageMediaPreparer(
        sources: source,
        prepared: prepared,
      );

      await expectLater(
        preparer.prepare(
          homeId: 'home-1',
          purpose: AiExtractionKind.stockPhoto,
          assets: <AiMediaAsset>[valid, invalid],
        ),
        throwsFormatException,
      );

      expect(prepared.written, hasLength(1));
      expect(prepared.deleted, prepared.written);
    },
  );
}

AiMediaAsset _asset(String id, int byteLength, {int? pageIndex}) =>
    AiMediaAsset(
      id: id,
      homeId: 'home-1',
      localReference: 'registered://$id',
      purpose: AiExtractionKind.stockPhoto,
      mimeType: 'image/png',
      byteLength: byteLength,
      createdAt: DateTime.utc(2026, 8, 4),
      pageIndex: pageIndex,
    );

PreparedAiMedia _prepared(String reference, int byteLength) => PreparedAiMedia(
  sourceMediaId: 'source-1',
  ephemeralReference: reference,
  previewReference: reference,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  mimeType: 'image/jpeg',
  byteLength: byteLength,
  width: 10,
  height: 10,
  pageIndex: 0,
);

final class _RecordingPreparedStore implements EphemeralPreparedMediaStore {
  final List<String> written = <String>[];
  final List<String> deleted = <String>[];
  final Map<String, Uint8List> _bytes = <String, Uint8List>{};

  @override
  Future<String> write({required String id, required Uint8List bytes}) async {
    final reference = 'ephemeral://$id';
    written.add(reference);
    _bytes[reference] = bytes;
    return reference;
  }

  @override
  Future<Uint8List> read(PreparedAiMedia media) async =>
      _bytes[media.ephemeralReference]!;

  @override
  Future<void> delete(String reference) async {
    deleted.add(reference);
    _bytes.remove(reference);
  }
}
