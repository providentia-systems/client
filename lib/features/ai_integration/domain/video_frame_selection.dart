import 'dart:collection';

import 'package:providentia/features/ai_integration/domain/media_intake.dart';

enum VideoFrameRejectionReason {
  lowSharpness,
  underexposed,
  overexposed,
  nearDuplicate,
  tooCloseInTime,
  selectionCapacity,
}

final class VideoFrameCandidate {
  const VideoFrameCandidate({
    required this.id,
    required this.sourceId,
    required this.offset,
    required this.ephemeralReference,
    required this.previewReference,
    required this.sha256,
    required this.perceptualHash,
    required this.mimeType,
    required this.byteLength,
    required this.width,
    required this.height,
    required this.sharpness,
    required this.exposure,
    required this.metadataStripped,
    required this.orientationNormalized,
  });

  final String id;
  final String sourceId;
  final Duration offset;
  final String ephemeralReference;
  final String previewReference;
  final String sha256;
  final String perceptualHash;
  final String mimeType;
  final int byteLength;
  final int width;
  final int height;
  final double sharpness;
  final double exposure;
  final bool metadataStripped;
  final bool orientationNormalized;

  double get exposureQuality => 1 - ((exposure - 0.5).abs() / 0.5);

  double get qualityScore => (sharpness * 0.7) + (exposureQuality * 0.3);

  PreparedMediaUnit toPreparedMediaUnit(int orderIndex) => PreparedMediaUnit(
    id: id,
    sourceId: sourceId,
    kind: PreparedMediaKind.videoFrame,
    orderIndex: orderIndex,
    ephemeralReference: ephemeralReference,
    previewReference: previewReference,
    sha256: sha256,
    mimeType: mimeType,
    byteLength: byteLength,
    width: width,
    height: height,
    metadataStripped: metadataStripped,
    orientationNormalized: orientationNormalized,
    frameOffset: offset,
  );
}

final class RejectedVideoFrame {
  const RejectedVideoFrame({required this.frame, required this.reason});

  final VideoFrameCandidate frame;
  final VideoFrameRejectionReason reason;
}

final class VideoFrameSelection {
  VideoFrameSelection({
    required List<VideoFrameCandidate> selected,
    required List<RejectedVideoFrame> rejected,
  }) : selected = UnmodifiableListView<VideoFrameCandidate>(selected),
       rejected = UnmodifiableListView<RejectedVideoFrame>(rejected);

  final List<VideoFrameCandidate> selected;
  final List<RejectedVideoFrame> rejected;

  List<PreparedMediaUnit> toPreparedMediaUnits({int startingOrder = 0}) =>
      selected
          .asMap()
          .entries
          .map(
            (entry) =>
                entry.value.toPreparedMediaUnit(startingOrder + entry.key),
          )
          .toList(growable: false);
}

final class DeterministicVideoFrameSelector {
  const DeterministicVideoFrameSelector({
    this.bounds = const MediaWorkflowBounds(),
  });

  final MediaWorkflowBounds bounds;

  VideoFrameSelection select({
    required String sourceId,
    required Duration videoDuration,
    required List<VideoFrameCandidate> candidates,
  }) {
    bounds.validate();
    if (sourceId.trim().isEmpty ||
        videoDuration <= Duration.zero ||
        videoDuration > bounds.maxVideoDuration) {
      throw const MediaPolicyViolation(
        code: 'invalid_video_selection_scope',
        safeMessage: 'The video selection scope is invalid.',
      );
    }
    if (candidates.isEmpty ||
        candidates.length > bounds.maxVideoFrameCandidates) {
      throw const MediaPolicyViolation(
        code: 'video_candidate_limit',
        safeMessage: 'The number of video frame candidates is invalid.',
      );
    }

    final ids = <String>{};
    for (final candidate in candidates) {
      _validateCandidate(candidate, sourceId, videoDuration);
      if (!ids.add(candidate.id)) {
        throw const MediaPolicyViolation(
          code: 'duplicate_video_frame_id',
          safeMessage: 'Video frame candidate identifiers must be unique.',
        );
      }
    }

    final ranked = List<VideoFrameCandidate>.of(candidates)
      ..sort(_compareQuality);
    final selected = <VideoFrameCandidate>[];
    final rejected = <RejectedVideoFrame>[];

    for (final candidate in ranked) {
      final basicRejection = _basicRejection(candidate);
      if (basicRejection != null) {
        rejected.add(
          RejectedVideoFrame(frame: candidate, reason: basicRejection),
        );
        continue;
      }
      if (selected.any(
        (existing) =>
            normalizedPerceptualDistance(
              existing.perceptualHash,
              candidate.perceptualHash,
            ) <=
            bounds.nearDuplicateDistance,
      )) {
        rejected.add(
          RejectedVideoFrame(
            frame: candidate,
            reason: VideoFrameRejectionReason.nearDuplicate,
          ),
        );
        continue;
      }
      if (selected.any(
        (existing) =>
            (existing.offset - candidate.offset).abs() < bounds.minFrameSpacing,
      )) {
        rejected.add(
          RejectedVideoFrame(
            frame: candidate,
            reason: VideoFrameRejectionReason.tooCloseInTime,
          ),
        );
        continue;
      }
      if (selected.length >= bounds.maxSelectedVideoFrames) {
        rejected.add(
          RejectedVideoFrame(
            frame: candidate,
            reason: VideoFrameRejectionReason.selectionCapacity,
          ),
        );
        continue;
      }
      selected.add(candidate);
    }

    if (selected.isEmpty) {
      throw const MediaPolicyViolation(
        code: 'no_usable_video_frames',
        safeMessage:
            'No sufficiently clear, well-exposed video frames were found.',
      );
    }
    selected.sort(_compareChronological);
    rejected.sort(
      (left, right) => _compareChronological(left.frame, right.frame),
    );
    return VideoFrameSelection(selected: selected, rejected: rejected);
  }

  void _validateCandidate(
    VideoFrameCandidate candidate,
    String sourceId,
    Duration videoDuration,
  ) {
    if (candidate.id.trim().isEmpty ||
        candidate.sourceId != sourceId ||
        candidate.offset < Duration.zero ||
        candidate.offset > videoDuration ||
        candidate.ephemeralReference.trim().isEmpty ||
        candidate.previewReference.trim().isEmpty ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(candidate.sha256) ||
        !RegExp(r'^[a-fA-F0-9]+$').hasMatch(candidate.perceptualHash) ||
        candidate.perceptualHash.length.isOdd ||
        candidate.mimeType != 'image/jpeg' ||
        candidate.byteLength <= 0 ||
        candidate.byteLength > bounds.maxPreparedBytesPerUnit ||
        candidate.width <= 0 ||
        candidate.height <= 0 ||
        candidate.width > bounds.maxPreparedDimension ||
        candidate.height > bounds.maxPreparedDimension ||
        !_unitInterval(candidate.sharpness) ||
        !_unitInterval(candidate.exposure) ||
        !candidate.metadataStripped ||
        !candidate.orientationNormalized) {
      throw const MediaPolicyViolation(
        code: 'invalid_video_frame_candidate',
        safeMessage: 'A video frame candidate is invalid or unsafe.',
      );
    }
  }

  VideoFrameRejectionReason? _basicRejection(VideoFrameCandidate candidate) {
    if (candidate.sharpness < bounds.minFrameSharpness) {
      return VideoFrameRejectionReason.lowSharpness;
    }
    if (candidate.exposure < bounds.minFrameExposure) {
      return VideoFrameRejectionReason.underexposed;
    }
    if (candidate.exposure > bounds.maxFrameExposure) {
      return VideoFrameRejectionReason.overexposed;
    }
    return null;
  }
}

double normalizedPerceptualDistance(String left, String right) {
  if (left.length != right.length ||
      left.isEmpty ||
      left.length.isOdd ||
      !RegExp(r'^[a-fA-F0-9]+$').hasMatch(left) ||
      !RegExp(r'^[a-fA-F0-9]+$').hasMatch(right)) {
    throw const MediaPolicyViolation(
      code: 'invalid_perceptual_hash',
      safeMessage: 'Frame comparison metadata is invalid.',
    );
  }
  var differentBits = 0;
  for (var index = 0; index < left.length; index++) {
    final difference =
        int.parse(left[index], radix: 16) ^ int.parse(right[index], radix: 16);
    differentBits += _nibbleBitCounts[difference];
  }
  return differentBits / (left.length * 4);
}

int _compareQuality(VideoFrameCandidate left, VideoFrameCandidate right) {
  final score = right.qualityScore.compareTo(left.qualityScore);
  if (score != 0) {
    return score;
  }
  final sharpness = right.sharpness.compareTo(left.sharpness);
  if (sharpness != 0) {
    return sharpness;
  }
  final offset = left.offset.compareTo(right.offset);
  return offset != 0 ? offset : left.id.compareTo(right.id);
}

int _compareChronological(VideoFrameCandidate left, VideoFrameCandidate right) {
  final offset = left.offset.compareTo(right.offset);
  return offset != 0 ? offset : left.id.compareTo(right.id);
}

bool _unitInterval(double value) => value.isFinite && value >= 0 && value <= 1;

const List<int> _nibbleBitCounts = <int>[
  0,
  1,
  1,
  2,
  1,
  2,
  2,
  3,
  1,
  2,
  2,
  3,
  2,
  3,
  3,
  4,
];
