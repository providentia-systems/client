import 'dart:collection';

import 'package:providentia/features/ai_integration/domain/ai_models.dart';

enum MediaSourceKind {
  cameraImage,
  galleryImage,
  fileImage,
  pdfDocument,
  video,
}

enum PreparedMediaKind { image, pdfPage, videoFrame }

enum OriginalMediaRetention { localOnly, encryptedBackupOptIn }

enum PreparedMediaRetention { untilExtractionFinishes }

enum MediaAudioPolicy { excluded }

enum MediaCleanupTrigger { success, failure, timeout, cancellation }

final class MediaPolicyViolation implements Exception {
  const MediaPolicyViolation({required this.code, required this.safeMessage});

  final String code;
  final String safeMessage;

  @override
  String toString() => 'MediaPolicyViolation($code): $safeMessage';
}

final class MediaWorkflowBounds {
  const MediaWorkflowBounds({
    this.maxSourceCount = 12,
    this.maxBatchUnits = 16,
    this.maxBytesPerSource = 25 * 1024 * 1024,
    this.maxPreparedBytesPerUnit = 8 * 1024 * 1024,
    this.maxTotalPreparedBytes = 40 * 1024 * 1024,
    this.maxPreparedDimension = 4096,
    this.maxReceiptPages = 12,
    this.maxStockPhotos = 12,
    this.maxVideoDuration = const Duration(seconds: 45),
    this.maxVideoFrameCandidates = 120,
    this.maxSelectedVideoFrames = 8,
    this.minFrameSpacing = const Duration(milliseconds: 500),
    this.minFrameSharpness = 0.45,
    this.minFrameExposure = 0.15,
    this.maxFrameExposure = 0.90,
    this.nearDuplicateDistance = 0.08,
  });

  final int maxSourceCount;
  final int maxBatchUnits;
  final int maxBytesPerSource;
  final int maxPreparedBytesPerUnit;
  final int maxTotalPreparedBytes;
  final int maxPreparedDimension;
  final int maxReceiptPages;
  final int maxStockPhotos;
  final Duration maxVideoDuration;
  final int maxVideoFrameCandidates;
  final int maxSelectedVideoFrames;
  final Duration minFrameSpacing;
  final double minFrameSharpness;
  final double minFrameExposure;
  final double maxFrameExposure;
  final double nearDuplicateDistance;

  void validate() {
    final positiveIntegers = <int>[
      maxSourceCount,
      maxBatchUnits,
      maxBytesPerSource,
      maxPreparedBytesPerUnit,
      maxTotalPreparedBytes,
      maxPreparedDimension,
      maxReceiptPages,
      maxStockPhotos,
      maxVideoFrameCandidates,
      maxSelectedVideoFrames,
    ];
    if (positiveIntegers.any((value) => value <= 0) ||
        maxVideoDuration <= Duration.zero ||
        minFrameSpacing < Duration.zero ||
        !_isUnitInterval(minFrameSharpness) ||
        !_isUnitInterval(minFrameExposure) ||
        !_isUnitInterval(maxFrameExposure) ||
        !_isUnitInterval(nearDuplicateDistance) ||
        minFrameExposure >= maxFrameExposure ||
        maxSelectedVideoFrames > maxVideoFrameCandidates) {
      throw const MediaPolicyViolation(
        code: 'invalid_media_bounds',
        safeMessage: 'The media safety limits are invalid.',
      );
    }
  }
}

final class MediaRetentionPolicy {
  const MediaRetentionPolicy({
    required this.original,
    required this.prepared,
    required this.maximumPreparedLifetime,
    required this.cleanupOnSuccess,
    required this.cleanupOnFailure,
    required this.cleanupOnTimeout,
    required this.cleanupOnCancellation,
  });

  static const MediaRetentionPolicy productionDefault = MediaRetentionPolicy(
    original: OriginalMediaRetention.localOnly,
    prepared: PreparedMediaRetention.untilExtractionFinishes,
    maximumPreparedLifetime: Duration(hours: 1),
    cleanupOnSuccess: true,
    cleanupOnFailure: true,
    cleanupOnTimeout: true,
    cleanupOnCancellation: true,
  );

  final OriginalMediaRetention original;
  final PreparedMediaRetention prepared;
  final Duration maximumPreparedLifetime;
  final bool cleanupOnSuccess;
  final bool cleanupOnFailure;
  final bool cleanupOnTimeout;
  final bool cleanupOnCancellation;

  bool requiresCleanup(MediaCleanupTrigger trigger) => switch (trigger) {
    MediaCleanupTrigger.success => cleanupOnSuccess,
    MediaCleanupTrigger.failure => cleanupOnFailure,
    MediaCleanupTrigger.timeout => cleanupOnTimeout,
    MediaCleanupTrigger.cancellation => cleanupOnCancellation,
  };

  void validate() {
    if (maximumPreparedLifetime <= Duration.zero ||
        !cleanupOnSuccess ||
        !cleanupOnFailure ||
        !cleanupOnTimeout ||
        !cleanupOnCancellation) {
      throw const MediaPolicyViolation(
        code: 'unsafe_retention_policy',
        safeMessage:
            'Prepared media must be temporary and cleaned up in every outcome.',
      );
    }
  }
}

final class AcquiredMediaSource {
  const AcquiredMediaSource({
    required this.id,
    required this.homeId,
    required this.purpose,
    required this.kind,
    required this.localReference,
    required this.mimeType,
    required this.byteLength,
    required this.acquiredAt,
    this.width,
    this.height,
    this.pageCount,
    this.duration,
    this.containsAudio = false,
  });

  final String id;
  final String homeId;
  final AiExtractionKind purpose;
  final MediaSourceKind kind;
  final String localReference;
  final String mimeType;
  final int byteLength;
  final DateTime acquiredAt;
  final int? width;
  final int? height;
  final int? pageCount;
  final Duration? duration;
  final bool containsAudio;
}

final class PreparedMediaUnit {
  const PreparedMediaUnit({
    required this.id,
    required this.sourceId,
    required this.kind,
    required this.orderIndex,
    required this.ephemeralReference,
    required this.previewReference,
    required this.sha256,
    required this.mimeType,
    required this.byteLength,
    required this.width,
    required this.height,
    required this.metadataStripped,
    required this.orientationNormalized,
    this.pageIndex,
    this.frameOffset,
  });

  final String id;
  final String sourceId;
  final PreparedMediaKind kind;
  final int orderIndex;
  final String ephemeralReference;
  final String previewReference;
  final String sha256;
  final String mimeType;
  final int byteLength;
  final int width;
  final int height;
  final bool metadataStripped;
  final bool orientationNormalized;
  final int? pageIndex;
  final Duration? frameOffset;

  bool get containsAudio => false;
}

final class PreparedMediaEnvelope {
  PreparedMediaEnvelope._({
    required this.id,
    required this.homeId,
    required this.purpose,
    required List<AcquiredMediaSource> sources,
    required List<PreparedMediaUnit> media,
    required this.retention,
    required this.audioPolicy,
    required this.preparedAt,
  }) : sources = UnmodifiableListView<AcquiredMediaSource>(sources),
       media = UnmodifiableListView<PreparedMediaUnit>(media);

  final String id;
  final String homeId;
  final AiExtractionKind purpose;
  final List<AcquiredMediaSource> sources;
  final List<PreparedMediaUnit> media;
  final MediaRetentionPolicy retention;
  final MediaAudioPolicy audioPolicy;
  final DateTime preparedAt;

  int get totalPreparedBytes =>
      media.fold<int>(0, (total, item) => total + item.byteLength);

  List<String> get orderedHashes =>
      media.map((item) => item.sha256).toList(growable: false);

  PreparedMediaBatch toPreparedMediaBatch() => PreparedMediaBatch(
    id: id,
    homeId: homeId,
    purpose: purpose,
    media: media
        .map(
          (item) => PreparedAiMedia(
            sourceMediaId: item.sourceId,
            ephemeralReference: item.ephemeralReference,
            previewReference: item.previewReference,
            sha256: item.sha256,
            mimeType: item.mimeType,
            byteLength: item.byteLength,
            width: item.width,
            height: item.height,
            pageIndex: item.orderIndex,
          ),
        )
        .toList(growable: false),
  );
}

final class BoundedMediaPlanner {
  const BoundedMediaPlanner({this.bounds = const MediaWorkflowBounds()});

  final MediaWorkflowBounds bounds;

  PreparedMediaEnvelope create({
    required String batchId,
    required String homeId,
    required AiExtractionKind purpose,
    required List<AcquiredMediaSource> sources,
    required List<PreparedMediaUnit> media,
    required DateTime preparedAt,
    MediaRetentionPolicy retention = MediaRetentionPolicy.productionDefault,
  }) {
    bounds.validate();
    retention.validate();
    _requireIdentifier(batchId, 'batch_id_required');
    _requireIdentifier(homeId, 'home_id_required');
    if (sources.isEmpty || media.isEmpty) {
      throw const MediaPolicyViolation(
        code: 'media_required',
        safeMessage: 'Select at least one image, receipt page, or video.',
      );
    }
    if (sources.length > bounds.maxSourceCount ||
        media.length > bounds.maxBatchUnits) {
      throw const MediaPolicyViolation(
        code: 'media_count_limit',
        safeMessage: 'The selected media exceeds the safe batch limit.',
      );
    }

    final sourceIds = <String>{};
    for (final source in sources) {
      _validateSource(source, homeId, purpose);
      if (!sourceIds.add(source.id)) {
        throw const MediaPolicyViolation(
          code: 'duplicate_source_id',
          safeMessage: 'The same media source was selected more than once.',
        );
      }
    }

    final mediaIds = <String>{};
    final orderIndexes = <int>{};
    var totalPreparedBytes = 0;
    for (final item in media) {
      _validatePreparedUnit(item, sourceIds);
      if (!mediaIds.add(item.id) || !orderIndexes.add(item.orderIndex)) {
        throw const MediaPolicyViolation(
          code: 'duplicate_prepared_media',
          safeMessage:
              'Prepared media identifiers and ordering must be unique.',
        );
      }
      totalPreparedBytes += item.byteLength;
    }
    final expectedOrder = List<int>.generate(media.length, (index) => index);
    final actualOrder = orderIndexes.toList()..sort();
    if (!_sameIntegers(expectedOrder, actualOrder)) {
      throw const MediaPolicyViolation(
        code: 'non_contiguous_media_order',
        safeMessage: 'Prepared media must have a stable, contiguous order.',
      );
    }
    if (totalPreparedBytes > bounds.maxTotalPreparedBytes) {
      throw const MediaPolicyViolation(
        code: 'prepared_batch_too_large',
        safeMessage:
            'The prepared media batch is too large to transmit safely.',
      );
    }

    _validatePurpose(purpose, sources, media);
    _validateSourceUnitMappings(sources, media);
    return PreparedMediaEnvelope._(
      id: batchId,
      homeId: homeId,
      purpose: purpose,
      sources: List<AcquiredMediaSource>.of(sources),
      media: (List<PreparedMediaUnit>.of(media)
        ..sort((left, right) => left.orderIndex.compareTo(right.orderIndex))),
      retention: retention,
      audioPolicy: MediaAudioPolicy.excluded,
      preparedAt: preparedAt.toUtc(),
    );
  }

  void _validateSource(
    AcquiredMediaSource source,
    String homeId,
    AiExtractionKind purpose,
  ) {
    _requireIdentifier(source.id, 'source_id_required');
    _requireIdentifier(source.localReference, 'local_reference_required');
    if (source.homeId != homeId || source.purpose != purpose) {
      throw const MediaPolicyViolation(
        code: 'media_scope_mismatch',
        safeMessage: 'All media must belong to this home and workflow.',
      );
    }
    if (source.byteLength <= 0 ||
        source.byteLength > bounds.maxBytesPerSource) {
      throw const MediaPolicyViolation(
        code: 'source_size_limit',
        safeMessage: 'A selected media source exceeds the safe size limit.',
      );
    }
    switch (source.kind) {
      case MediaSourceKind.cameraImage:
      case MediaSourceKind.galleryImage:
      case MediaSourceKind.fileImage:
        if (!_isSupportedImageMime(source.mimeType) ||
            !_validDimensions(source.width, source.height)) {
          throw const MediaPolicyViolation(
            code: 'invalid_image_source',
            safeMessage: 'A selected image is not in a supported safe format.',
          );
        }
      case MediaSourceKind.pdfDocument:
        if (source.mimeType != 'application/pdf' ||
            source.pageCount == null ||
            source.pageCount! <= 0 ||
            source.pageCount! > bounds.maxReceiptPages) {
          throw const MediaPolicyViolation(
            code: 'invalid_pdf_source',
            safeMessage: 'The receipt PDF is invalid or has too many pages.',
          );
        }
      case MediaSourceKind.video:
        if (!source.mimeType.startsWith('video/') ||
            source.duration == null ||
            source.duration! <= Duration.zero ||
            source.duration! > bounds.maxVideoDuration) {
          throw const MediaPolicyViolation(
            code: 'invalid_video_source',
            safeMessage: 'The video is invalid or exceeds the duration limit.',
          );
        }
    }
  }

  void _validatePreparedUnit(PreparedMediaUnit item, Set<String> sourceIds) {
    _requireIdentifier(item.id, 'prepared_media_id_required');
    _requireIdentifier(item.ephemeralReference, 'ephemeral_reference_required');
    _requireIdentifier(item.previewReference, 'preview_reference_required');
    if (!sourceIds.contains(item.sourceId)) {
      throw const MediaPolicyViolation(
        code: 'unknown_media_source',
        safeMessage: 'Prepared media does not match a selected source.',
      );
    }
    if (item.orderIndex < 0 ||
        item.byteLength <= 0 ||
        item.byteLength > bounds.maxPreparedBytesPerUnit ||
        item.width <= 0 ||
        item.height <= 0 ||
        item.width > bounds.maxPreparedDimension ||
        item.height > bounds.maxPreparedDimension ||
        !_isSupportedImageMime(item.mimeType) ||
        !_isSha256(item.sha256)) {
      throw const MediaPolicyViolation(
        code: 'invalid_prepared_media',
        safeMessage: 'Prepared media does not satisfy the safety limits.',
      );
    }
    if (!item.metadataStripped || !item.orientationNormalized) {
      throw const MediaPolicyViolation(
        code: 'media_not_sanitized',
        safeMessage:
            'Media metadata and orientation must be normalized before transmission.',
      );
    }
    switch (item.kind) {
      case PreparedMediaKind.image:
        if (item.pageIndex != null || item.frameOffset != null) {
          throw const MediaPolicyViolation(
            code: 'invalid_image_metadata',
            safeMessage:
                'The prepared image contains invalid page or video data.',
          );
        }
      case PreparedMediaKind.pdfPage:
        if (item.pageIndex == null ||
            item.pageIndex! < 0 ||
            item.frameOffset != null) {
          throw const MediaPolicyViolation(
            code: 'invalid_pdf_page',
            safeMessage:
                'A prepared PDF page has invalid ordering information.',
          );
        }
      case PreparedMediaKind.videoFrame:
        if (item.frameOffset == null ||
            item.frameOffset! < Duration.zero ||
            item.pageIndex != null ||
            item.containsAudio) {
          throw const MediaPolicyViolation(
            code: 'invalid_video_frame',
            safeMessage: 'A prepared video frame is invalid.',
          );
        }
    }
  }

  void _validatePurpose(
    AiExtractionKind purpose,
    List<AcquiredMediaSource> sources,
    List<PreparedMediaUnit> media,
  ) {
    switch (purpose) {
      case AiExtractionKind.receipt:
        if (sources.any((source) => source.kind == MediaSourceKind.video) ||
            media.any((item) => item.kind == PreparedMediaKind.videoFrame) ||
            media.length > bounds.maxReceiptPages) {
          throw const MediaPolicyViolation(
            code: 'invalid_receipt_media',
            safeMessage: 'Receipts accept bounded image or PDF pages only.',
          );
        }
        _validatePdfPageMappings(sources, media);
      case AiExtractionKind.stockPhoto:
        if (sources.any(
              (source) => source.kind == MediaSourceKind.pdfDocument,
            ) ||
            media.any((item) => item.kind == PreparedMediaKind.pdfPage)) {
          throw const MediaPolicyViolation(
            code: 'invalid_stock_media',
            safeMessage:
                'Stock counting accepts photos or selected video frames.',
          );
        }
        final stillCount = media
            .where((item) => item.kind == PreparedMediaKind.image)
            .length;
        final frameCount = media
            .where((item) => item.kind == PreparedMediaKind.videoFrame)
            .length;
        if (stillCount > bounds.maxStockPhotos ||
            frameCount > bounds.maxSelectedVideoFrames) {
          throw const MediaPolicyViolation(
            code: 'stock_media_count_limit',
            safeMessage: 'The stock media exceeds the safe selection limit.',
          );
        }
    }
  }

  void _validatePdfPageMappings(
    List<AcquiredMediaSource> sources,
    List<PreparedMediaUnit> media,
  ) {
    for (final source in sources.where(
      (item) => item.kind == MediaSourceKind.pdfDocument,
    )) {
      final pageIndexes = <int>{};
      for (final page in media.where((item) => item.sourceId == source.id)) {
        if (page.kind != PreparedMediaKind.pdfPage ||
            page.pageIndex == null ||
            page.pageIndex! >= source.pageCount! ||
            !pageIndexes.add(page.pageIndex!)) {
          throw const MediaPolicyViolation(
            code: 'invalid_pdf_page_mapping',
            safeMessage: 'Prepared PDF pages must be unique and within range.',
          );
        }
      }
    }
  }

  void _validateSourceUnitMappings(
    List<AcquiredMediaSource> sources,
    List<PreparedMediaUnit> media,
  ) {
    for (final source in sources) {
      final preparedForSource = media.where(
        (item) => item.sourceId == source.id,
      );
      if (preparedForSource.isEmpty) {
        throw const MediaPolicyViolation(
          code: 'source_without_prepared_media',
          safeMessage: 'Every selected source must produce prepared media.',
        );
      }
      final expectedKind = switch (source.kind) {
        MediaSourceKind.cameraImage ||
        MediaSourceKind.galleryImage ||
        MediaSourceKind.fileImage => PreparedMediaKind.image,
        MediaSourceKind.pdfDocument => PreparedMediaKind.pdfPage,
        MediaSourceKind.video => PreparedMediaKind.videoFrame,
      };
      if (preparedForSource.any((item) => item.kind != expectedKind)) {
        throw const MediaPolicyViolation(
          code: 'prepared_media_kind_mismatch',
          safeMessage: 'Prepared media does not match its original source.',
        );
      }
    }
  }
}

bool _isSupportedImageMime(String value) =>
    value == 'image/jpeg' || value == 'image/png' || value == 'image/webp';

bool _validDimensions(int? width, int? height) =>
    width != null && height != null && width > 0 && height > 0;

bool _isSha256(String value) => RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);

bool _isUnitInterval(double value) =>
    value.isFinite && value >= 0 && value <= 1;

bool _sameIntegers(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

void _requireIdentifier(String value, String code) {
  if (value.trim().isEmpty) {
    throw MediaPolicyViolation(
      code: code,
      safeMessage: 'Required media metadata is missing.',
    );
  }
}
