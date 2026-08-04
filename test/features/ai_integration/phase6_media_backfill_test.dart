import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/prepared_media_lifecycle.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/media_intake.dart';
import 'package:providentia/features/ai_integration/domain/media_transmission.dart';
import 'package:providentia/features/ai_integration/domain/video_frame_selection.dart';

void main() {
  group('bounded media planning', () {
    test('preserves stable ordering for a multi-page receipt PDF', () {
      final source = _pdfSource(pageCount: 2);
      final planner = const BoundedMediaPlanner();

      final batch = planner.create(
        batchId: 'receipt-batch-1',
        homeId: 'home-1',
        purpose: AiExtractionKind.receipt,
        sources: <AcquiredMediaSource>[source],
        media: <PreparedMediaUnit>[
          _preparedUnit(
            id: 'page-2',
            sourceId: source.id,
            kind: PreparedMediaKind.pdfPage,
            orderIndex: 1,
            pageIndex: 1,
            hashCharacter: 'b',
          ),
          _preparedUnit(
            id: 'page-1',
            sourceId: source.id,
            kind: PreparedMediaKind.pdfPage,
            orderIndex: 0,
            pageIndex: 0,
            hashCharacter: 'a',
          ),
        ],
        preparedAt: DateTime.utc(2026, 8, 4),
      );

      expect(batch.media.map((item) => item.id), <String>['page-1', 'page-2']);
      expect(batch.orderedHashes, <String>[_hash('a'), _hash('b')]);
      expect(batch.audioPolicy, MediaAudioPolicy.excluded);
      expect(batch.retention.original, OriginalMediaRetention.localOnly);
      expect(batch.toPreparedMediaBatch().media.length, 2);
      expect(batch.toPreparedMediaBatch().media.last.pageIndex, 1);
    });

    test('rejects video input in the receipt workflow', () {
      final source = _videoSource();

      expect(
        () => const BoundedMediaPlanner().create(
          batchId: 'receipt-batch-1',
          homeId: 'home-1',
          purpose: AiExtractionKind.receipt,
          sources: <AcquiredMediaSource>[source],
          media: <PreparedMediaUnit>[
            _preparedUnit(
              id: 'frame-1',
              sourceId: source.id,
              kind: PreparedMediaKind.videoFrame,
              orderIndex: 0,
              frameOffset: const Duration(seconds: 1),
            ),
          ],
          preparedAt: DateTime.utc(2026, 8, 4),
        ),
        throwsA(
          isA<MediaPolicyViolation>().having(
            (error) => error.code,
            'code',
            'invalid_receipt_media',
          ),
        ),
      );
    });

    test('rejects unsanitized and oversized prepared media', () {
      final source = _imageSource();
      final planner = BoundedMediaPlanner(
        bounds: const MediaWorkflowBounds(maxPreparedBytesPerUnit: 100),
      );

      expect(
        () => planner.create(
          batchId: 'stock-batch-1',
          homeId: 'home-1',
          purpose: AiExtractionKind.stockPhoto,
          sources: <AcquiredMediaSource>[source],
          media: <PreparedMediaUnit>[
            _preparedUnit(
              id: 'image-1',
              sourceId: source.id,
              kind: PreparedMediaKind.image,
              orderIndex: 0,
              byteLength: 101,
              metadataStripped: false,
            ),
          ],
          preparedAt: DateTime.utc(2026, 8, 4),
        ),
        throwsA(isA<MediaPolicyViolation>()),
      );
    });
  });

  group('deterministic video frame selection', () {
    test('selects clear frames, removes duplicates, and orders by time', () {
      const selector = DeterministicVideoFrameSelector(
        bounds: MediaWorkflowBounds(
          maxSelectedVideoFrames: 3,
          minFrameSpacing: Duration(milliseconds: 500),
          nearDuplicateDistance: 0.08,
        ),
      );
      final candidates = <VideoFrameCandidate>[
        _frame(
          id: 'late',
          second: 8,
          sharpness: 0.80,
          exposure: 0.50,
          perceptualHash: 'ffffffffffffffff',
        ),
        _frame(
          id: 'best',
          second: 2,
          sharpness: 0.95,
          exposure: 0.50,
          perceptualHash: '0000000000000000',
        ),
        _frame(
          id: 'duplicate',
          second: 4,
          sharpness: 0.90,
          exposure: 0.50,
          perceptualHash: '0000000000000001',
        ),
        _frame(
          id: 'dark',
          second: 6,
          sharpness: 0.90,
          exposure: 0.05,
          perceptualHash: 'aaaaaaaaaaaaaaaa',
        ),
        _frame(
          id: 'middle',
          second: 5,
          sharpness: 0.75,
          exposure: 0.55,
          perceptualHash: '5555555555555555',
        ),
      ];

      final result = selector.select(
        sourceId: 'video-1',
        videoDuration: const Duration(seconds: 10),
        candidates: candidates,
      );

      expect(result.selected.map((frame) => frame.id), <String>[
        'best',
        'middle',
        'late',
      ]);
      expect(
        result.rejected
            .singleWhere((item) => item.frame.id == 'duplicate')
            .reason,
        VideoFrameRejectionReason.nearDuplicate,
      );
      expect(
        result.rejected.singleWhere((item) => item.frame.id == 'dark').reason,
        VideoFrameRejectionReason.underexposed,
      );
      expect(
        result.toPreparedMediaUnits().every((item) => !item.containsAudio),
        isTrue,
      );
      expect(normalizedPerceptualDistance('00', '01'), closeTo(0.125, 0.0001));
    });

    test('fails closed when every frame is unusable', () {
      expect(
        () => const DeterministicVideoFrameSelector().select(
          sourceId: 'video-1',
          videoDuration: const Duration(seconds: 10),
          candidates: <VideoFrameCandidate>[
            _frame(
              id: 'blurred',
              second: 1,
              sharpness: 0.1,
              exposure: 0.5,
              perceptualHash: '0000000000000000',
            ),
          ],
        ),
        throwsA(
          isA<MediaPolicyViolation>().having(
            (error) => error.code,
            'code',
            'no_usable_video_frames',
          ),
        ),
      );
    });
  });

  group('transmission consent and cleanup', () {
    test('binds consent to both providers and the exact media hashes', () {
      final batch = _stockBatch();
      final primary = _provider(id: 'primary');
      final validator = _provider(id: 'validator');
      final manifest = AiTransmissionManifest.create(
        id: 'manifest-1',
        batch: batch,
        privacyMode: AiPrivacyMode.serverProxyCloud,
        primaryProvider: primary,
        validatorProvider: validator,
        disclosureVersion: 'privacy-v2',
        createdAt: DateTime.utc(2026, 8, 4, 10),
      );
      final consent = AiTransmissionConsent(
        manifestId: manifest.id,
        canonicalBinding: manifest.canonicalConsentBinding,
        disclosureVersion: manifest.disclosureVersion,
        confirmedBy: 'user-1',
        confirmedAt: DateTime.utc(2026, 8, 4, 10, 1),
        explicitlyConfirmed: true,
      );

      manifest.authorize(consent);
      final validatorConsent = manifest.consentForProvider(
        provider: validator,
        consent: consent,
      );

      expect(validatorConsent.providerId, 'validator');
      expect(validatorConsent.orderedMediaHashes, batch.orderedHashes);
      expect(manifest.applicationServerPersistsMedia, isFalse);
      expect(manifest.originalsRemainLocal, isTrue);
      expect(manifest.audioPolicy, MediaAudioPolicy.excluded);
    });

    test('rejects stale or altered consent', () {
      final batch = _stockBatch();
      final primary = _provider(id: 'primary');
      final manifest = AiTransmissionManifest.create(
        id: 'manifest-1',
        batch: batch,
        privacyMode: AiPrivacyMode.serverProxyCloud,
        primaryProvider: primary,
        disclosureVersion: 'privacy-v2',
        createdAt: DateTime.utc(2026, 8, 4, 10),
      );

      expect(
        () => manifest.authorize(
          AiTransmissionConsent(
            manifestId: manifest.id,
            canonicalBinding: '${manifest.canonicalConsentBinding}-altered',
            disclosureVersion: manifest.disclosureVersion,
            confirmedBy: 'user-1',
            confirmedAt: DateTime.utc(2026, 8, 4, 10, 1),
            explicitlyConfirmed: true,
          ),
        ),
        throwsA(
          isA<MediaPolicyViolation>().having(
            (error) => error.code,
            'code',
            'transmission_consent_mismatch',
          ),
        ),
      );
    });

    test(
      'cleans temporary media after success, timeout, and cancellation',
      () async {
        final cleanup = _CleanupSpy();
        final lifecycle = ExecuteWithPreparedMediaCleanup(cleanup);
        final batch = _stockBatch();

        expect(
          await lifecycle.execute<int>(batch: batch, operation: () async => 7),
          7,
        );
        await expectLater(
          lifecycle.execute<void>(
            batch: batch,
            operation: () async => throw TimeoutException('private detail'),
          ),
          throwsA(isA<TimeoutException>()),
        );
        await expectLater(
          lifecycle.execute<void>(
            batch: batch,
            operation: () async => throw const MediaOperationCancelled(),
          ),
          throwsA(isA<MediaOperationCancelled>()),
        );

        expect(cleanup.triggers, <MediaCleanupTrigger>[
          MediaCleanupTrigger.success,
          MediaCleanupTrigger.timeout,
          MediaCleanupTrigger.cancellation,
        ]);
      },
    );
  });
}

AcquiredMediaSource _pdfSource({required int pageCount}) => AcquiredMediaSource(
  id: 'pdf-1',
  homeId: 'home-1',
  purpose: AiExtractionKind.receipt,
  kind: MediaSourceKind.pdfDocument,
  localReference: 'local://receipt.pdf',
  mimeType: 'application/pdf',
  byteLength: 12000,
  acquiredAt: DateTime.utc(2026, 8, 4),
  pageCount: pageCount,
);

AcquiredMediaSource _imageSource() => AcquiredMediaSource(
  id: 'image-source-1',
  homeId: 'home-1',
  purpose: AiExtractionKind.stockPhoto,
  kind: MediaSourceKind.cameraImage,
  localReference: 'local://stock.jpg',
  mimeType: 'image/jpeg',
  byteLength: 12000,
  acquiredAt: DateTime.utc(2026, 8, 4),
  width: 1600,
  height: 1200,
);

AcquiredMediaSource _videoSource() => AcquiredMediaSource(
  id: 'video-1',
  homeId: 'home-1',
  purpose: AiExtractionKind.receipt,
  kind: MediaSourceKind.video,
  localReference: 'local://stock.mp4',
  mimeType: 'video/mp4',
  byteLength: 12000,
  acquiredAt: DateTime.utc(2026, 8, 4),
  duration: const Duration(seconds: 10),
  containsAudio: true,
);

PreparedMediaUnit _preparedUnit({
  required String id,
  required String sourceId,
  required PreparedMediaKind kind,
  required int orderIndex,
  int? pageIndex,
  Duration? frameOffset,
  String hashCharacter = 'a',
  int byteLength = 100,
  bool metadataStripped = true,
}) => PreparedMediaUnit(
  id: id,
  sourceId: sourceId,
  kind: kind,
  orderIndex: orderIndex,
  ephemeralReference: 'ephemeral://$id',
  previewReference: 'preview://$id',
  sha256: _hash(hashCharacter),
  mimeType: 'image/jpeg',
  byteLength: byteLength,
  width: 1200,
  height: 1600,
  metadataStripped: metadataStripped,
  orientationNormalized: true,
  pageIndex: pageIndex,
  frameOffset: frameOffset,
);

VideoFrameCandidate _frame({
  required String id,
  required int second,
  required double sharpness,
  required double exposure,
  required String perceptualHash,
}) => VideoFrameCandidate(
  id: id,
  sourceId: 'video-1',
  offset: Duration(seconds: second),
  ephemeralReference: 'ephemeral://$id',
  previewReference: 'preview://$id',
  sha256: _hash('a'),
  perceptualHash: perceptualHash,
  mimeType: 'image/jpeg',
  byteLength: 100,
  width: 1200,
  height: 800,
  sharpness: sharpness,
  exposure: exposure,
  metadataStripped: true,
  orientationNormalized: true,
);

PreparedMediaEnvelope _stockBatch() {
  final source = _imageSource();
  return const BoundedMediaPlanner().create(
    batchId: 'stock-batch-1',
    homeId: 'home-1',
    purpose: AiExtractionKind.stockPhoto,
    sources: <AcquiredMediaSource>[source],
    media: <PreparedMediaUnit>[
      _preparedUnit(
        id: 'stock-image-1',
        sourceId: source.id,
        kind: PreparedMediaKind.image,
        orderIndex: 0,
      ),
    ],
    preparedAt: DateTime.utc(2026, 8, 4),
  );
}

AiProviderProfile _provider({required String id}) => AiProviderProfile(
  id: id,
  homeId: 'home-1',
  displayName: id,
  kind: AiProviderKind.openAi,
  transport: AiTransport.serverProxy,
  protocol: AiEndpointProtocol.openAiResponses,
  model: 'vision-model',
  capabilities: <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
  },
  availability: AiProviderAvailability.available,
  credentialConfigured: true,
);

final class _CleanupSpy implements PreparedMediaCleanupPort {
  final List<MediaCleanupTrigger> triggers = <MediaCleanupTrigger>[];

  @override
  Future<void> discardPreparedMedia({
    required PreparedMediaEnvelope batch,
    required MediaCleanupTrigger trigger,
  }) async {
    triggers.add(trigger);
  }
}

String _hash(String character) => List<String>.filled(64, character).join();
