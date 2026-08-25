import 'package:flutter/foundation.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/application/catalog_store_price_service.dart';
import 'package:providentia/features/catalog/application/catalog_submission_intent.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/domain/catalog_store_price_models.dart';

enum CatalogStorePriceContributionStatus {
  idle,
  loading,
  ready,
  submitting,
  submitted,
  consentRequired,
  authenticationRequired,
  forbidden,
  sourceUnavailable,
  conflict,
  offline,
  failure,
}

/// Coordinates one explicitly reviewed store-price observation.
///
/// The stable submission UUID is persisted before transport and survives an
/// ambiguous failure or app restart. Its fingerprint binds the consent CAS
/// revision and exact payload; terminal outcomes retire it.
final class CatalogStorePriceContributionController extends ChangeNotifier {
  factory CatalogStorePriceContributionController({
    required CatalogSharingConsentRepository consentRepository,
    required CatalogStorePriceService service,
    required String homeId,
    required bool canContribute,
    CatalogSubmissionIntentCoordinator? submissionIntents,
    String Function()? submissionIdGenerator,
    Future<void> Function()? onAuthorizationLost,
  }) => CatalogStorePriceContributionController._(
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

  CatalogStorePriceContributionController._(
    this._consentRepository,
    this._service,
    this.homeId,
    this.canContribute,
    this._submissionIntents,
    this._onAuthorizationLost,
  );

  final CatalogSharingConsentRepository _consentRepository;
  final CatalogStorePriceService _service;
  final String homeId;
  final bool canContribute;
  final CatalogSubmissionIntentCoordinator _submissionIntents;
  final Future<void> Function()? _onAuthorizationLost;

  CatalogStorePriceContributionStatus _status =
      CatalogStorePriceContributionStatus.idle;
  CatalogSharingConsent? _serverConsent;
  CatalogStorePriceSource? _source;
  CatalogStorePriceObservation? _observation;
  CatalogContributionReceipt? _submission;
  CatalogSubmissionIntent? _pendingIntent;
  bool _explicitlyConsented = false;
  int _generation = 0;
  bool _disposed = false;

  CatalogStorePriceContributionStatus get status => _status;
  CatalogSharingConsent? get serverConsent => _serverConsent;
  CatalogStorePriceSource? get source => _source;
  CatalogStorePriceObservation? get observation => _observation;
  CatalogContributionReceipt? get submission => _submission;
  String? get pendingSubmissionId => _pendingIntent?.submissionId;
  bool get explicitlyConsented => _explicitlyConsented;
  bool get maySubmit =>
      _status == CatalogStorePriceContributionStatus.ready &&
      _observation != null &&
      _explicitlyConsented;

  Future<void> loadConsent() async {
    _explicitlyConsented = false;
    _submission = null;
    if (!canContribute) {
      _serverConsent = null;
      _setStatus(CatalogStorePriceContributionStatus.forbidden);
      return;
    }
    final generation = ++_generation;
    _setStatus(CatalogStorePriceContributionStatus.loading);
    try {
      final consent = await _consentRepository.loadConsent(homeId: homeId);
      if (!_isCurrent(generation)) return;
      _serverConsent = consent;
      _setStatus(
        consent.shareStorePrices && consent.revision > 0
            ? CatalogStorePriceContributionStatus.ready
            : CatalogStorePriceContributionStatus.consentRequired,
      );
    } on CatalogContributionAuthenticationRequiredException {
      await _handleAuthorizationLoss(
        generation,
        CatalogStorePriceContributionStatus.authenticationRequired,
      );
    } on CatalogContributionForbiddenException {
      await _handleAuthorizationLoss(
        generation,
        CatalogStorePriceContributionStatus.forbidden,
      );
    } on CatalogContributionConflictException {
      _fail(generation, CatalogStorePriceContributionStatus.conflict);
    } on CatalogContributionUnavailableException {
      _fail(generation, CatalogStorePriceContributionStatus.offline);
    } on Exception {
      _fail(generation, CatalogStorePriceContributionStatus.failure);
    }
  }

  void selectSource(CatalogStorePriceSource source) {
    if (_status != CatalogStorePriceContributionStatus.ready) return;
    if (source.homeId != homeId) {
      throw StateError('Cannot share a price from another home.');
    }
    _source = source;
    discardPreview();
  }

  void reconcileAvailableSourceIds(Set<String> sourceIds) {
    final selected = _source;
    if (selected != null && !sourceIds.contains(selected.homeProductId)) {
      clearSelection();
    }
  }

  void preview({
    required String storeName,
    String? storeLocation,
    required String price,
    required String currency,
    required DateTime observedOn,
  }) {
    if (_status != CatalogStorePriceContributionStatus.ready) return;
    final source = _source;
    if (source == null) {
      throw StateError('Choose a catalog-linked home product first.');
    }
    _observation = _service.preview(
      source: source,
      storeName: storeName,
      storeLocation: storeLocation,
      price: price,
      currency: currency,
      observedOn: observedOn,
    );
    _pendingIntent = null;
    _explicitlyConsented = false;
    _submission = null;
    _notify();
  }

  void discardPreview() {
    _observation = null;
    _pendingIntent = null;
    _explicitlyConsented = false;
    _submission = null;
    _notify();
  }

  void setExplicitConsent(bool value) {
    if (_status != CatalogStorePriceContributionStatus.ready ||
        _observation == null) {
      return;
    }
    _explicitlyConsented = value;
    _notify();
  }

  Future<void> submit() async {
    final observation = _observation;
    final consentRevision = _serverConsent?.revision;
    if (!maySubmit ||
        observation == null ||
        consentRevision == null ||
        consentRevision < 1) {
      return;
    }
    final generation = ++_generation;
    _setStatus(CatalogStorePriceContributionStatus.submitting);
    try {
      var intent = _pendingIntent;
      intent ??= await _submissionIntents.obtain(
        CatalogSubmissionIntentKey.forPayload(
          type: CatalogContributionIntentType.storePrice,
          homeId: observation.source.homeId,
          sourceEntityId: observation.source.homeProductId,
          expectedConsentRevision: consentRevision,
          payload: observation.toPayloadJson(),
        ),
      );
      if (!_isCurrent(generation)) return;
      _pendingIntent = intent;
      final link = await _service.submit(
        submissionId: intent.submissionId,
        expectedConsentRevision: consentRevision,
        observation: observation,
        explicitlyConsented: true,
      );
      if (!_isCurrent(generation)) return;
      await _submissionIntents.retire(intent);
      if (!_isCurrent(generation)) return;
      _submission = link;
      _source = null;
      _observation = null;
      _pendingIntent = null;
      _explicitlyConsented = false;
      _setStatus(CatalogStorePriceContributionStatus.submitted);
    } on CatalogServerConsentRequiredException {
      if (!_isCurrent(generation)) return;
      _serverConsent = null;
      await _retirePendingIntent();
      _explicitlyConsented = false;
      _setStatus(CatalogStorePriceContributionStatus.consentRequired);
    } on CatalogContributionAuthenticationRequiredException {
      await _handleAuthorizationLoss(
        generation,
        CatalogStorePriceContributionStatus.authenticationRequired,
      );
    } on CatalogContributionForbiddenException {
      await _handleAuthorizationLoss(
        generation,
        CatalogStorePriceContributionStatus.forbidden,
      );
    } on CatalogContributionConflictException {
      await _retirePendingIntent();
      _fail(generation, CatalogStorePriceContributionStatus.conflict);
    } on CatalogContributionSourceUnavailableException {
      await _retirePendingIntent();
      if (_isCurrent(generation)) {
        _source = null;
        _observation = null;
      }
      _fail(generation, CatalogStorePriceContributionStatus.sourceUnavailable);
    } on CatalogContributionUnavailableException {
      _fail(generation, CatalogStorePriceContributionStatus.offline);
    } on CatalogContributionValidationException {
      await _retirePendingIntent();
      _fail(generation, CatalogStorePriceContributionStatus.failure);
    } on ArgumentError {
      await _retirePendingIntent();
      _fail(generation, CatalogStorePriceContributionStatus.failure);
    } on Exception {
      _fail(generation, CatalogStorePriceContributionStatus.failure);
    }
  }

  void contributeAnother() {
    if (_status != CatalogStorePriceContributionStatus.submitted) return;
    final consent = _serverConsent;
    clearSelection();
    _setStatus(
      consent != null && consent.shareStorePrices && consent.revision > 0
          ? CatalogStorePriceContributionStatus.ready
          : CatalogStorePriceContributionStatus.consentRequired,
    );
  }

  void clearSelection() {
    _source = null;
    discardPreview();
  }

  void clearSensitiveState() {
    _generation += 1;
    _serverConsent = null;
    _source = null;
    _observation = null;
    _submission = null;
    _pendingIntent = null;
    _explicitlyConsented = false;
    _setStatus(CatalogStorePriceContributionStatus.idle);
  }

  void _fail(int generation, CatalogStorePriceContributionStatus status) {
    if (!_isCurrent(generation)) return;
    _explicitlyConsented = false;
    _setStatus(status);
  }

  Future<void> _handleAuthorizationLoss(
    int generation,
    CatalogStorePriceContributionStatus status,
  ) async {
    if (!_isCurrent(generation)) return;
    _serverConsent = null;
    _source = null;
    _observation = null;
    _submission = null;
    await _retirePendingIntent();
    _explicitlyConsented = false;
    _setStatus(status);
    await _onAuthorizationLost?.call();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _retirePendingIntent() async {
    final intent = _pendingIntent;
    _pendingIntent = null;
    if (intent == null) return;
    try {
      await _submissionIntents.retire(intent);
    } on CatalogContributionUnavailableException {
      // A delayed secure-store cleanup cannot attach this UUID to changed
      // data because the storage slot is an exact payload fingerprint.
    }
  }

  void _setStatus(CatalogStorePriceContributionStatus value) {
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
    _source = null;
    _observation = null;
    _submission = null;
    _pendingIntent = null;
    super.dispose();
  }
}
