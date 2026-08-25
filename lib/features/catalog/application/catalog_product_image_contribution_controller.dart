import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/catalog/application/catalog_product_image_service.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/application/catalog_submission_intent.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/domain/catalog_product_image_models.dart';

enum CatalogProductImageContributionStatus {
  idle,
  loading,
  ready,
  acquiring,
  submitting,
  submitted,
  consentRequired,
  authenticationRequired,
  forbidden,
  sourceUnavailable,
  conflict,
  imageTooLarge,
  imageUnsupported,
  imageInvalid,
  serviceUnavailable,
  offline,
  failure,
}

typedef CatalogProductImageAcquisition =
    Future<CatalogProductImageDraft?> Function();

/// Owns one exact, explicit product-image submission intent.
///
/// Image bytes are transient and zeroized on replacement, success,
/// authorization loss, route purge, and disposal. A persisted UUID contains no
/// image or household data and can only replay the same hashed request intent.
final class CatalogProductImageContributionController extends ChangeNotifier {
  factory CatalogProductImageContributionController({
    required CatalogSharingConsentRepository consentRepository,
    required CatalogProductImageService service,
    required String homeId,
    required bool canContribute,
    CatalogSubmissionIntentCoordinator? submissionIntents,
    String Function()? submissionIdGenerator,
    Future<void> Function()? onAuthorizationLost,
  }) => CatalogProductImageContributionController._(
    consentRepository,
    service,
    homeId,
    canContribute,
    submissionIntents ??
        CatalogSubmissionIntentCoordinator(
          store: MemoryCatalogSubmissionIntentStore(),
          idGenerator: submissionIdGenerator,
        ),
    onAuthorizationLost,
  );

  CatalogProductImageContributionController._(
    this._consentRepository,
    this._service,
    this.homeId,
    this.canContribute,
    this._submissionIntents,
    this._onAuthorizationLost,
  );

  final CatalogSharingConsentRepository _consentRepository;
  final CatalogProductImageService _service;
  final String homeId;
  final bool canContribute;
  final CatalogSubmissionIntentCoordinator _submissionIntents;
  final Future<void> Function()? _onAuthorizationLost;

  CatalogProductImageContributionStatus _status =
      CatalogProductImageContributionStatus.idle;
  CatalogSharingConsent? _serverConsent;
  CatalogProductImageSource? _source;
  CatalogProductImageDraft? _image;
  CatalogProductImageSubmission? _submission;
  CatalogSubmissionIntent? _pendingIntent;
  String _altText = '';
  String? _safeMediaError;
  bool _rightsConfirmed = false;
  bool _submissionConfirmed = false;
  int _generation = 0;
  bool _disposed = false;

  CatalogProductImageContributionStatus get status => _status;
  CatalogSharingConsent? get serverConsent => _serverConsent;
  CatalogProductImageSource? get source => _source;
  CatalogProductImageDraft? get image => _image;
  CatalogProductImageSubmission? get submission => _submission;
  String? get pendingSubmissionId => _pendingIntent?.submissionId;
  String get altText => _altText;
  String? get safeMediaError => _safeMediaError;
  bool get rightsConfirmed => _rightsConfirmed;
  bool get submissionConfirmed => _submissionConfirmed;
  bool get maySubmit =>
      const <CatalogProductImageContributionStatus>{
        CatalogProductImageContributionStatus.ready,
        CatalogProductImageContributionStatus.offline,
        CatalogProductImageContributionStatus.serviceUnavailable,
        CatalogProductImageContributionStatus.failure,
      }.contains(_status) &&
      _source != null &&
      _image != null &&
      _altText.trim().isNotEmpty &&
      _rightsConfirmed &&
      _submissionConfirmed;

  Future<void> loadConsent() async {
    _submissionConfirmed = false;
    _submission = null;
    await _retirePendingIntent();
    if (!canContribute) {
      _serverConsent = null;
      _releasePrivateSelection();
      _setStatus(CatalogProductImageContributionStatus.forbidden);
      return;
    }
    final generation = ++_generation;
    _setStatus(CatalogProductImageContributionStatus.loading);
    try {
      final consent = await _consentRepository.loadConsent(homeId: homeId);
      if (!_isCurrent(generation)) return;
      _serverConsent = consent;
      if (!consent.shareProductImages || consent.revision < 1) {
        _releasePrivateSelection();
      }
      _setStatus(
        consent.shareProductImages && consent.revision > 0
            ? CatalogProductImageContributionStatus.ready
            : CatalogProductImageContributionStatus.consentRequired,
      );
    } on CatalogContributionAuthenticationRequiredException {
      await _handleAuthorizationLoss(
        generation,
        CatalogProductImageContributionStatus.authenticationRequired,
      );
    } on CatalogContributionForbiddenException {
      await _handleAuthorizationLoss(
        generation,
        CatalogProductImageContributionStatus.forbidden,
      );
    } on CatalogContributionConflictException {
      _fail(generation, CatalogProductImageContributionStatus.conflict);
    } on CatalogContributionUnavailableException {
      _fail(generation, CatalogProductImageContributionStatus.offline);
    } on Exception {
      _fail(generation, CatalogProductImageContributionStatus.failure);
    }
  }

  void selectSource(CatalogProductImageSource source) {
    if (!_canEdit) return;
    if (source.homeId != homeId) {
      throw StateError('Cannot share an image from another home.');
    }
    if (_source?.homeProductId == source.homeProductId) return;
    _releaseImage();
    _source = source;
    _clearReviewedFields();
    unawaited(_retirePendingIntent());
    _notify();
  }

  void reconcileAvailableSourceIds(Set<String> sourceIds) {
    final selected = _source;
    if (selected != null && !sourceIds.contains(selected.homeProductId)) {
      clearSelection();
    }
  }

  Future<void> acquire(CatalogProductImageAcquisition acquisition) async {
    if (!_canEdit || _source == null) return;
    final generation = ++_generation;
    _safeMediaError = null;
    _setStatus(CatalogProductImageContributionStatus.acquiring);
    CatalogProductImageDraft? selected;
    try {
      selected = await acquisition();
      if (!_isCurrent(generation)) {
        selected?.release();
        return;
      }
      if (selected == null) {
        _setStatus(CatalogProductImageContributionStatus.ready);
        return;
      }
      _releaseImage();
      _image = selected;
      selected = null;
      _altText = '';
      _clearReviewedFields();
      await _retirePendingIntent();
      if (_isCurrent(generation)) {
        _setStatus(CatalogProductImageContributionStatus.ready);
      }
    } on CatalogProductImageAcquisitionException catch (error) {
      selected?.release();
      if (!_isCurrent(generation)) return;
      _safeMediaError = error.safeMessage;
      _setStatus(switch (error.kind) {
        CatalogProductImageAcquisitionFailureKind.tooLarge =>
          CatalogProductImageContributionStatus.imageTooLarge,
        CatalogProductImageAcquisitionFailureKind.unsupported =>
          CatalogProductImageContributionStatus.imageUnsupported,
        CatalogProductImageAcquisitionFailureKind.invalidDimensions ||
        CatalogProductImageAcquisitionFailureKind.unreadable =>
          CatalogProductImageContributionStatus.imageInvalid,
      });
    } on Exception {
      selected?.release();
      if (_isCurrent(generation)) {
        _safeMediaError = 'The selected image could not be prepared safely.';
        _setStatus(CatalogProductImageContributionStatus.imageInvalid);
      }
    }
  }

  void dismissMediaError() {
    if (!const <CatalogProductImageContributionStatus>{
      CatalogProductImageContributionStatus.imageTooLarge,
      CatalogProductImageContributionStatus.imageUnsupported,
      CatalogProductImageContributionStatus.imageInvalid,
    }.contains(_status)) {
      return;
    }
    _safeMediaError = null;
    _setStatus(CatalogProductImageContributionStatus.ready);
  }

  void reviewAfterConflict() {
    if (_status != CatalogProductImageContributionStatus.conflict) return;
    _setStatus(CatalogProductImageContributionStatus.ready);
  }

  void setAltText(String value) {
    if (!_canEdit || _image == null || value == _altText) return;
    _altText = value;
    _submissionConfirmed = false;
    unawaited(_retirePendingIntent());
    _notify();
  }

  void setRightsConfirmed(bool value) {
    if (!_canEdit || _image == null || value == _rightsConfirmed) return;
    _rightsConfirmed = value;
    _submissionConfirmed = false;
    unawaited(_retirePendingIntent());
    _notify();
  }

  void setSubmissionConfirmed(bool value) {
    if (!_canEdit ||
        _image == null ||
        !_rightsConfirmed ||
        _altText.trim().isEmpty) {
      return;
    }
    _submissionConfirmed = value;
    if (!value) unawaited(_retirePendingIntent());
    _notify();
  }

  Future<void> submit() async {
    final source = _source;
    final image = _image;
    final consentRevision = _serverConsent?.revision;
    if (!maySubmit ||
        source == null ||
        image == null ||
        consentRevision == null ||
        consentRevision < 1) {
      return;
    }
    final generation = ++_generation;
    _setStatus(CatalogProductImageContributionStatus.submitting);
    try {
      final normalizedAltText = _service.normalizeAltText(_altText);
      var intent = _pendingIntent;
      intent ??= await _submissionIntents.obtain(
        CatalogSubmissionIntentKey.forPayload(
          type: CatalogContributionIntentType.productImage,
          homeId: source.homeId,
          sourceEntityId: source.homeProductId,
          expectedConsentRevision: consentRevision,
          payload: <String, Object?>{
            'altText': normalizedAltText,
            'sourceDigest': image.sourceDigest,
            'mediaType': image.mediaType.wireName,
            'rightsDeclarationVersion':
                CatalogProductImageDraft.rightsDeclarationVersion,
            'submissionConfirmed': true,
          },
        ),
      );
      if (!_isCurrent(generation)) {
        await _retireDetachedIntent(intent);
        return;
      }
      _pendingIntent = intent;
      final submission = await _service.submit(
        submissionId: intent.submissionId,
        expectedConsentRevision: consentRevision,
        source: source,
        image: image,
        altText: normalizedAltText,
        rightsConfirmed: true,
        submissionConfirmed: true,
      );
      if (!_isCurrent(generation)) return;
      await _submissionIntents.retire(intent);
      if (!_isCurrent(generation)) return;
      _submission = submission;
      _pendingIntent = null;
      _source = null;
      _releaseImage();
      _altText = '';
      _rightsConfirmed = false;
      _submissionConfirmed = false;
      _setStatus(CatalogProductImageContributionStatus.submitted);
    } on CatalogServerConsentRequiredException {
      if (!_isCurrent(generation)) return;
      _serverConsent = null;
      await _retirePendingIntent();
      _submissionConfirmed = false;
      _setStatus(CatalogProductImageContributionStatus.consentRequired);
    } on CatalogContributionAuthenticationRequiredException {
      await _handleAuthorizationLoss(
        generation,
        CatalogProductImageContributionStatus.authenticationRequired,
      );
    } on CatalogContributionForbiddenException {
      await _handleAuthorizationLoss(
        generation,
        CatalogProductImageContributionStatus.forbidden,
      );
    } on CatalogContributionSourceUnavailableException {
      await _retirePendingIntent();
      if (_isCurrent(generation)) _releasePrivateSelection();
      _fail(
        generation,
        CatalogProductImageContributionStatus.sourceUnavailable,
      );
    } on CatalogContributionConflictException {
      await _retirePendingIntent();
      _submissionConfirmed = false;
      _fail(generation, CatalogProductImageContributionStatus.conflict);
    } on CatalogProductImageTooLargeException {
      await _retirePendingIntent();
      if (_isCurrent(generation)) {
        _safeMediaError = 'The server rejected this image as too large.';
        _releaseImage();
      }
      _fail(generation, CatalogProductImageContributionStatus.imageTooLarge);
    } on CatalogProductImageUnsupportedException {
      await _retirePendingIntent();
      if (_isCurrent(generation)) {
        _safeMediaError = 'The server could not accept this image format.';
        _releaseImage();
      }
      _fail(generation, CatalogProductImageContributionStatus.imageUnsupported);
    } on CatalogContributionValidationException {
      await _retirePendingIntent();
      if (_isCurrent(generation)) {
        _safeMediaError =
            'The image or description did not pass server validation.';
        _submissionConfirmed = false;
      }
      _fail(generation, CatalogProductImageContributionStatus.imageInvalid);
    } on ArgumentError {
      await _retirePendingIntent();
      _submissionConfirmed = false;
      _fail(generation, CatalogProductImageContributionStatus.imageInvalid);
    } on CatalogProductImageServiceUnavailableException {
      _fail(
        generation,
        CatalogProductImageContributionStatus.serviceUnavailable,
        preserveConfirmation: true,
      );
    } on CatalogContributionUnavailableException {
      _fail(
        generation,
        CatalogProductImageContributionStatus.offline,
        preserveConfirmation: true,
      );
    } on Exception {
      _fail(
        generation,
        CatalogProductImageContributionStatus.failure,
        preserveConfirmation: true,
      );
    }
  }

  void contributeAnother() {
    if (_status != CatalogProductImageContributionStatus.submitted) return;
    _submission = null;
    final consent = _serverConsent;
    _setStatus(
      consent != null && consent.shareProductImages && consent.revision > 0
          ? CatalogProductImageContributionStatus.ready
          : CatalogProductImageContributionStatus.consentRequired,
    );
  }

  void clearSelection() {
    _releasePrivateSelection();
    _submission = null;
    unawaited(_retirePendingIntent());
    _notify();
  }

  void clearSensitiveState() {
    _generation += 1;
    _serverConsent = null;
    _releasePrivateSelection();
    _submission = null;
    final intent = _pendingIntent;
    _pendingIntent = null;
    if (intent != null) unawaited(_retireDetachedIntent(intent));
    _safeMediaError = null;
    _setStatus(CatalogProductImageContributionStatus.idle);
  }

  bool get _canEdit =>
      !_disposed &&
      const <CatalogProductImageContributionStatus>{
        CatalogProductImageContributionStatus.ready,
        CatalogProductImageContributionStatus.offline,
        CatalogProductImageContributionStatus.serviceUnavailable,
        CatalogProductImageContributionStatus.failure,
        CatalogProductImageContributionStatus.imageTooLarge,
        CatalogProductImageContributionStatus.imageUnsupported,
        CatalogProductImageContributionStatus.imageInvalid,
        CatalogProductImageContributionStatus.conflict,
      }.contains(_status);

  void _clearReviewedFields() {
    _altText = '';
    _rightsConfirmed = false;
    _submissionConfirmed = false;
    _submission = null;
    _safeMediaError = null;
  }

  void _releaseImage() {
    _image?.release();
    _image = null;
  }

  void _releasePrivateSelection() {
    _source = null;
    _releaseImage();
    _clearReviewedFields();
  }

  void _fail(
    int generation,
    CatalogProductImageContributionStatus status, {
    bool preserveConfirmation = false,
  }) {
    if (!_isCurrent(generation)) return;
    if (!preserveConfirmation) _submissionConfirmed = false;
    _setStatus(status);
  }

  Future<void> _handleAuthorizationLoss(
    int generation,
    CatalogProductImageContributionStatus status,
  ) async {
    if (!_isCurrent(generation)) return;
    _serverConsent = null;
    _releasePrivateSelection();
    _submission = null;
    await _retirePendingIntent();
    _setStatus(status);
    await _onAuthorizationLost?.call();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _retirePendingIntent() async {
    final intent = _pendingIntent;
    _pendingIntent = null;
    if (intent != null) await _retireDetachedIntent(intent);
  }

  Future<void> _retireDetachedIntent(CatalogSubmissionIntent intent) async {
    try {
      await _submissionIntents.retire(intent);
    } on CatalogContributionUnavailableException {
      // The slot is an exact one-way fingerprint. A delayed cleanup cannot
      // attach this UUID to different image bytes or household data.
    }
  }

  void _setStatus(CatalogProductImageContributionStatus value) {
    _status = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _serverConsent = null;
    _releasePrivateSelection();
    _submission = null;
    final intent = _pendingIntent;
    _pendingIntent = null;
    if (intent != null) unawaited(_retireDetachedIntent(intent));
    super.dispose();
  }
}
