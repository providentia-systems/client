import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum CatalogProductImageMediaType {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp');

  const CatalogProductImageMediaType(this.wireName, this.fileExtension);

  final String wireName;
  final String fileExtension;
}

/// The only private inventory identity needed to bind an image contribution.
///
/// This value stays in the authenticated home endpoint. It is never part of
/// the moderator or public image projection.
final class CatalogProductImageSource {
  CatalogProductImageSource({
    required this.homeId,
    required this.homeProductId,
    required this.displayName,
  }) {
    _requireUuid(homeId, 'homeId');
    _requireUuid(homeProductId, 'homeProductId');
    _requireText(displayName, 'displayName', maximumLength: 191);
  }

  final String homeId;
  final String homeProductId;
  final String displayName;
}

/// One bounded, transient image selected for public-catalog moderation.
///
/// Bytes are copied on construction, never persisted by this type, and are
/// overwritten when ownership is released. The server remains authoritative:
/// it verifies this digest and re-encodes the image as metadata-free WebP.
final class CatalogProductImageDraft {
  CatalogProductImageDraft({
    required Uint8List bytes,
    required this.mediaType,
    required this.width,
    required this.height,
  }) : _bytes = Uint8List.fromList(bytes),
       sourceDigest = sha256.convert(bytes).toString() {
    if (bytes.length < minimumBytes || bytes.length > maximumBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'must be between $minimumBytes and $maximumBytes bytes',
      );
    }
    if (width < minimumDimension ||
        height < minimumDimension ||
        width > maximumDimension ||
        height > maximumDimension ||
        width * height > maximumPixels) {
      throw ArgumentError('Image dimensions are outside the accepted limits.');
    }
  }

  static const int minimumBytes = 16;
  static const int maximumBytes = 5 * 1024 * 1024;
  static const int minimumDimension = 16;
  static const int maximumDimension = 4096;
  static const int maximumPixels = 16777216;
  static const String rightsDeclarationVersion =
      'homeowner_original_public_catalog_v1';
  static const String reuseNoticeVersion = 'catalog-image-public-reuse-v1';

  Uint8List _bytes;
  bool _released = false;

  final CatalogProductImageMediaType mediaType;
  final int width;
  final int height;
  final String sourceDigest;

  int get byteLength => _bytes.length;
  bool get isReleased => _released;

  /// Read-only view used only by the local preview surface.
  Uint8List get previewBytes {
    _requireAvailable();
    return _bytes.asUnmodifiableView();
  }

  /// Short-lived transport copy. The repository overwrites it after upload.
  Uint8List copyBytes() {
    _requireAvailable();
    return Uint8List.fromList(_bytes);
  }

  void release() {
    if (_released) return;
    _bytes.fillRange(0, _bytes.length, 0);
    _bytes = Uint8List(0);
    _released = true;
  }

  void _requireAvailable() {
    if (_released) throw StateError('The selected image has been released.');
  }
}

final class CatalogProductImageSubmission {
  CatalogProductImageSubmission({
    required this.contributionId,
    required this.status,
    required this.revision,
    required this.assetDigest,
  }) {
    _requireUuid(contributionId, 'contributionId');
    if (!_digestPattern.hasMatch(assetDigest)) {
      throw ArgumentError.value(assetDigest, 'assetDigest', 'must be SHA-256');
    }
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  final String contributionId;
  final CatalogProductImageSubmissionStatus status;
  final int revision;
  final String assetDigest;
}

enum CatalogProductImageSubmissionStatus {
  pending,
  approved,
  rejected,
  withdrawn,
}

void _requireText(String value, String name, {int? maximumLength}) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      (maximumLength != null && normalized.length > maximumLength)) {
    throw ArgumentError.value(value, name, 'has an invalid length');
  }
}

void _requireUuid(String value, String name) {
  if (!_uuidPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a UUID');
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _digestPattern = RegExp(r'^[a-f0-9]{64}$');
