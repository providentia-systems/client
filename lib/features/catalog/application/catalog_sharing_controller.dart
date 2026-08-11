import 'package:flutter/foundation.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';

enum CatalogSharingStatus {
  idle,
  loading,
  ready,
  saving,
  authenticationRequired,
  forbidden,
  conflict,
  offline,
  failure,
}

/// Home-scoped, revision-bound catalog-sharing consent state.
///
/// This controller cannot submit catalog items: it depends only on the consent
/// port. Changing a category therefore never causes an implicit contribution.
final class CatalogSharingController extends ChangeNotifier {
  factory CatalogSharingController({
    required CatalogSharingConsentRepository repository,
    required String homeId,
    required bool canManageConsent,
    required bool canContribute,
    Future<void> Function()? onAuthorizationLost,
  }) => CatalogSharingController._(
    repository,
    homeId,
    canManageConsent,
    canContribute,
    onAuthorizationLost,
  );

  CatalogSharingController._(
    this._repository,
    this.homeId,
    this.canManageConsent,
    this.canContribute,
    this._onAuthorizationLost,
  );

  final CatalogSharingConsentRepository _repository;
  final String homeId;
  final bool canManageConsent;
  final bool canContribute;
  final Future<void> Function()? _onAuthorizationLost;

  CatalogSharingStatus _status = CatalogSharingStatus.idle;
  CatalogSharingConsent? _consent;
  int _generation = 0;
  bool _disposed = false;

  CatalogSharingStatus get status => _status;
  CatalogSharingConsent? get consent => _consent;
  bool get mayOpen => canManageConsent || canContribute;
  bool get mayEdit => canManageConsent;

  Future<void> load() async {
    if (!mayOpen) {
      _setStatus(CatalogSharingStatus.forbidden);
      return;
    }
    final generation = ++_generation;
    _setStatus(CatalogSharingStatus.loading);
    try {
      final consent = await _repository.loadConsent(homeId: homeId);
      if (!_isCurrent(generation)) return;
      _consent = consent;
      _setStatus(CatalogSharingStatus.ready);
    } on CatalogContributionAuthenticationRequiredException {
      await _handleAuthorizationLoss(
        generation,
        CatalogSharingStatus.authenticationRequired,
      );
    } on CatalogContributionForbiddenException {
      await _handleAuthorizationLoss(
        generation,
        CatalogSharingStatus.forbidden,
      );
    } on CatalogContributionConflictException {
      if (_isCurrent(generation)) _setStatus(CatalogSharingStatus.conflict);
    } on CatalogContributionUnavailableException {
      if (_isCurrent(generation)) _setStatus(CatalogSharingStatus.offline);
    } on Exception {
      if (_isCurrent(generation)) _setStatus(CatalogSharingStatus.failure);
    }
  }

  Future<void> setProductIdentity(bool value) => _save(productIdentity: value);

  Future<void> setProductImages(bool value) => _save(productImages: value);

  Future<void> setStorePrices(bool value) => _save(storePrices: value);

  Future<void> _save({
    bool? productIdentity,
    bool? productImages,
    bool? storePrices,
  }) async {
    final current = _consent;
    if (!mayEdit || current == null || _status == CatalogSharingStatus.saving) {
      return;
    }
    final generation = ++_generation;
    _setStatus(CatalogSharingStatus.saving);
    try {
      final updated = await _repository.updateConsent(
        homeId: homeId,
        update: CatalogSharingConsentUpdate(
          shareProductIdentity: productIdentity ?? current.shareProductIdentity,
          shareProductImages: productImages ?? current.shareProductImages,
          shareStorePrices: storePrices ?? current.shareStorePrices,
          expectedRevision: current.revision,
        ),
      );
      if (!_isCurrent(generation)) return;
      _consent = updated;
      _setStatus(CatalogSharingStatus.ready);
    } on CatalogContributionAuthenticationRequiredException {
      await _handleAuthorizationLoss(
        generation,
        CatalogSharingStatus.authenticationRequired,
      );
    } on CatalogContributionForbiddenException {
      await _handleAuthorizationLoss(
        generation,
        CatalogSharingStatus.forbidden,
      );
    } on CatalogContributionConflictException {
      _failUpdate(generation, CatalogSharingStatus.conflict);
    } on CatalogContributionUnavailableException {
      _failUpdate(generation, CatalogSharingStatus.offline);
    } on CatalogContributionValidationException {
      _failUpdate(generation, CatalogSharingStatus.failure);
    } on Exception {
      _failUpdate(generation, CatalogSharingStatus.failure);
    }
  }

  void _failUpdate(int generation, CatalogSharingStatus status) {
    if (!_isCurrent(generation)) return;
    _consent = null;
    _setStatus(status);
  }

  Future<void> _handleAuthorizationLoss(
    int generation,
    CatalogSharingStatus status,
  ) async {
    if (!_isCurrent(generation)) return;
    _consent = null;
    _setStatus(status);
    await _onAuthorizationLost?.call();
  }

  void clearSensitiveState() {
    _generation += 1;
    _consent = null;
    _setStatus(CatalogSharingStatus.idle);
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setStatus(CatalogSharingStatus value) {
    _status = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
