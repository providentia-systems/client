import 'package:flutter/foundation.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';

enum CatalogProductContributionStatus {
  idle,
  loading,
  ready,
  submitting,
  submitted,
  consentRequired,
  authenticationRequired,
  forbidden,
  conflict,
  offline,
  failure,
}

/// Explicit, per-item product-identity contribution state.
///
/// Server consent and the local per-item checkbox are independent gates. This
/// controller has no inventory mutation port and cannot submit in response to
/// selection or consent changes.
final class CatalogProductContributionController extends ChangeNotifier {
  factory CatalogProductContributionController({
    required CatalogSharingConsentRepository consentRepository,
    required CatalogProposalService proposalService,
    required String homeId,
    required String locale,
    required bool canContribute,
    Future<void> Function()? onAuthorizationLost,
  }) => CatalogProductContributionController._(
    consentRepository,
    proposalService,
    homeId,
    locale,
    canContribute,
    onAuthorizationLost,
  );

  CatalogProductContributionController._(
    this._consentRepository,
    this._proposalService,
    this.homeId,
    this.locale,
    this.canContribute,
    this._onAuthorizationLost,
  );

  final CatalogSharingConsentRepository _consentRepository;
  final CatalogProposalService _proposalService;
  final String homeId;
  final String locale;
  final bool canContribute;
  final Future<void> Function()? _onAuthorizationLost;

  CatalogProductContributionStatus _status =
      CatalogProductContributionStatus.idle;
  CatalogSharingConsent? _serverConsent;
  PrivateProduct? _product;
  SanitizedCatalogProposal? _proposal;
  CatalogSubmissionLink? _submission;
  bool _explicitlyConsented = false;
  int _generation = 0;
  bool _disposed = false;

  CatalogProductContributionStatus get status => _status;
  CatalogSharingConsent? get serverConsent => _serverConsent;
  PrivateProduct? get product => _product;
  SanitizedCatalogProposal? get proposal => _proposal;
  CatalogSubmissionLink? get submission => _submission;
  bool get explicitlyConsented => _explicitlyConsented;
  bool get maySubmit =>
      _status == CatalogProductContributionStatus.ready &&
      _proposal != null &&
      _explicitlyConsented;

  Future<void> loadConsent() async {
    _explicitlyConsented = false;
    _submission = null;
    if (!canContribute) {
      _serverConsent = null;
      _setStatus(CatalogProductContributionStatus.forbidden);
      return;
    }
    final generation = ++_generation;
    _setStatus(CatalogProductContributionStatus.loading);
    try {
      final consent = await _consentRepository.loadConsent(homeId: homeId);
      if (!_isCurrent(generation)) return;
      _serverConsent = consent;
      _setStatus(
        consent.shareProductIdentity && consent.revision > 0
            ? CatalogProductContributionStatus.ready
            : CatalogProductContributionStatus.consentRequired,
      );
    } on CatalogContributionAuthenticationRequiredException {
      await _handleAuthorizationLoss(
        generation,
        CatalogProductContributionStatus.authenticationRequired,
      );
    } on CatalogContributionForbiddenException {
      await _handleAuthorizationLoss(
        generation,
        CatalogProductContributionStatus.forbidden,
      );
    } on CatalogContributionConflictException {
      _fail(generation, CatalogProductContributionStatus.conflict);
    } on CatalogContributionUnavailableException {
      _fail(generation, CatalogProductContributionStatus.offline);
    } on Exception {
      _fail(generation, CatalogProductContributionStatus.failure);
    }
  }

  void selectProduct(PrivateProduct product) {
    if (_status != CatalogProductContributionStatus.ready) return;
    if (product.homeId != homeId) {
      throw StateError('Cannot contribute a product from another home.');
    }
    _product = product;
    _proposal = _proposalService.preview(product: product, locale: locale);
    _explicitlyConsented = false;
    _submission = null;
    _notify();
  }

  void reconcileAvailableProductIds(Set<String> productIds) {
    final selected = _product;
    if (selected != null && !productIds.contains(selected.homeProductId)) {
      clearSelection();
    }
  }

  void setExplicitConsent(bool value) {
    if (_status != CatalogProductContributionStatus.ready ||
        _proposal == null) {
      return;
    }
    _explicitlyConsented = value;
    _notify();
  }

  Future<void> submit() async {
    final product = _product;
    final proposal = _proposal;
    if (!maySubmit || product == null || proposal == null) return;
    final generation = ++_generation;
    _setStatus(CatalogProductContributionStatus.submitting);
    try {
      final link = await _proposalService.submit(
        product: product,
        preview: proposal,
        explicitlyConsented: true,
      );
      if (!_isCurrent(generation)) return;
      _submission = link;
      _explicitlyConsented = false;
      _setStatus(CatalogProductContributionStatus.submitted);
    } on CatalogServerConsentRequiredException {
      if (!_isCurrent(generation)) return;
      _serverConsent = null;
      _explicitlyConsented = false;
      _setStatus(CatalogProductContributionStatus.consentRequired);
    } on CatalogContributionAuthenticationRequiredException {
      await _handleAuthorizationLoss(
        generation,
        CatalogProductContributionStatus.authenticationRequired,
      );
    } on CatalogContributionForbiddenException {
      await _handleAuthorizationLoss(
        generation,
        CatalogProductContributionStatus.forbidden,
      );
    } on CatalogContributionConflictException {
      _fail(generation, CatalogProductContributionStatus.conflict);
    } on CatalogContributionUnavailableException {
      _fail(generation, CatalogProductContributionStatus.offline);
    } on CatalogContributionValidationException {
      _fail(generation, CatalogProductContributionStatus.failure);
    } on Exception {
      _fail(generation, CatalogProductContributionStatus.failure);
    }
  }

  void contributeAnother() {
    if (_status != CatalogProductContributionStatus.submitted) return;
    final consent = _serverConsent;
    clearSelection();
    _setStatus(
      consent != null && consent.shareProductIdentity && consent.revision > 0
          ? CatalogProductContributionStatus.ready
          : CatalogProductContributionStatus.consentRequired,
    );
  }

  void clearSelection() {
    _product = null;
    _proposal = null;
    _submission = null;
    _explicitlyConsented = false;
    _notify();
  }

  void clearSensitiveState() {
    _generation += 1;
    _serverConsent = null;
    _product = null;
    _proposal = null;
    _submission = null;
    _explicitlyConsented = false;
    _setStatus(CatalogProductContributionStatus.idle);
  }

  void _fail(int generation, CatalogProductContributionStatus status) {
    if (!_isCurrent(generation)) return;
    _explicitlyConsented = false;
    _setStatus(status);
  }

  Future<void> _handleAuthorizationLoss(
    int generation,
    CatalogProductContributionStatus status,
  ) async {
    if (!_isCurrent(generation)) return;
    _serverConsent = null;
    _product = null;
    _proposal = null;
    _submission = null;
    _explicitlyConsented = false;
    _setStatus(status);
    await _onAuthorizationLost?.call();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setStatus(CatalogProductContributionStatus value) {
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
    super.dispose();
  }
}
