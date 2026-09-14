import 'package:providentia/features/ai_integration/application/ai_review_resume_store.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/ai_use_cases.dart';
import 'package:providentia/features/ai_integration/application/server_ai_repository.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';
import 'package:providentia/features/ai_integration/domain/proposal_validation.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';

enum ServerAiWorkspaceStatus {
  accessDenied,
  idle,
  loading,
  ready,
  preparing,
  awaitingConsent,
  processing,
  reviewRequired,
  quarantined,
  failed,
}

/// Application-owned AI workspace. It may produce a typed review handoff, but
/// it has no inventory or purchasing mutation dependency by design.
final class ServerAiWorkspaceController extends ChangeNotifier {
  factory ServerAiWorkspaceController({
    required ServerAiRepository repository,
    required AiMediaPreparationPort media,
    required AiProviderGateway gateway,
    required AiIdentifierFactory identifiers,
    required AiHomeCapabilities capabilities,
    AiPrivacyPolicy policy = const AiPrivacyPolicy(),
    DateTime Function()? clock,
    String? Function()? stockCountTarget,
    AiReviewResumeStore? resumeStore,
  }) => ServerAiWorkspaceController._(
    repository,
    media,
    gateway,
    identifiers,
    capabilities,
    policy,
    clock ?? DateTime.now,
    stockCountTarget,
    resumeStore,
  );

  ServerAiWorkspaceController._(
    this._repository,
    this._media,
    this._gateway,
    this._identifiers,
    this._capabilities,
    this._policy,
    this._clock,
    this._stockCountTarget,
    this._resumeStore,
  ) : _status = _capabilities.mayRead
          ? ServerAiWorkspaceStatus.idle
          : ServerAiWorkspaceStatus.accessDenied;

  final ServerAiRepository _repository;
  final AiMediaPreparationPort _media;
  final AiProviderGateway _gateway;
  final AiIdentifierFactory _identifiers;
  final AiPrivacyPolicy _policy;
  final DateTime Function() _clock;
  final String? Function()? _stockCountTarget;
  final AiReviewResumeStore? _resumeStore;
  List<AiReviewResumeReference> _recentReviews =
      const <AiReviewResumeReference>[];
  List<AiReviewResumeReference> get recentReviews => _recentReviews;
  String? _preparedStockTarget;

  AiHomeCapabilities _capabilities;
  ServerAiWorkspaceStatus _status;
  AiServerWorkspace? _workspace;
  AiProviderProfile? _selectedProvider;
  PreparedMediaBatch? _prepared;
  AiConsent? _consent;
  ReceiptProposal? _receiptProposal;
  StockPhotoProposal? _stockProposal;
  AiExtractionReview? _review;
  String? _safeMessage;
  int _accessEpoch = 0;
  bool _disposed = false;

  AiHomeCapabilities get capabilities => _capabilities;
  ServerAiWorkspaceStatus get status => _status;
  AiServerWorkspace? get workspace => _workspace;
  AiProviderProfile? get selectedProvider => _selectedProvider;
  PreparedMediaBatch? get prepared => _prepared;
  AiConsent? get consent => _consent;
  ReceiptProposal? get receiptProposal => _receiptProposal;
  StockPhotoProposal? get stockProposal => _stockProposal;
  AiExtractionReview? get review => _review;
  String? get safeMessage => _safeMessage;
  bool get transmissionConfirmed => _consent != null;
  bool get isBusy => const <ServerAiWorkspaceStatus>{
    ServerAiWorkspaceStatus.loading,
    ServerAiWorkspaceStatus.preparing,
    ServerAiWorkspaceStatus.processing,
  }.contains(_status);

  Future<void> updateCapabilities(AiHomeCapabilities capabilities) async {
    final scopeChanged = capabilities.homeId != _capabilities.homeId;
    final lostRead = _capabilities.mayRead && !capabilities.mayRead;
    final lostUse = _capabilities.mayUse && !capabilities.mayUse;
    _capabilities = capabilities;
    if (scopeChanged || lostRead || lostUse) {
      _accessEpoch++;
      _recentReviews = const <AiReviewResumeReference>[];
      await _discardPrepared();
      _clearExtractionState();
    }
    if (!capabilities.mayRead) {
      _workspace = null;
      _status = ServerAiWorkspaceStatus.accessDenied;
      _safeMessage = 'Your current household role does not allow access to AI.';
    } else if (scopeChanged || lostRead) {
      _workspace = null;
      _status = ServerAiWorkspaceStatus.idle;
      _safeMessage = null;
    } else if (lostUse &&
        _status != ServerAiWorkspaceStatus.loading &&
        _status != ServerAiWorkspaceStatus.failed) {
      _status = ServerAiWorkspaceStatus.ready;
      _safeMessage = null;
    }
    _notify();
  }

  Future<void> load() async {
    if (!_requireRead()) return;
    final epoch = _accessEpoch;
    final homeId = _capabilities.homeId;
    _status = ServerAiWorkspaceStatus.loading;
    _safeMessage = null;
    _notify();
    try {
      final loaded = await _repository.loadWorkspace(homeId: homeId);
      if (!_stillAuthorized(epoch, homeId, read: true)) return;
      if (loaded.homeId != homeId) {
        throw const AiServerException(AiServerFailureKind.invalidResponse);
      }
      final recent =
          await _resumeStore?.list() ?? const <AiReviewResumeReference>[];
      if (!_stillAuthorized(epoch, homeId)) return;
      _recentReviews = recent;
      _workspace = loaded;
      _status = ServerAiWorkspaceStatus.ready;
    } on AiServerException catch (error) {
      await _handleServerExceptionIfCurrent(epoch, homeId, error);
    } catch (_) {
      _failIfCurrent(epoch, homeId, 'Household AI could not be loaded safely.');
    }
    _notify();
  }

  Future<void> updateSettings(AiSettingsUpdate update) async {
    if (!_requireManage()) return;
    final current = _workspace;
    if (current == null ||
        update.expectedRevision != current.settings.revision) {
      _setFailure('Refresh AI settings before saving changes.');
      return;
    }
    final epoch = _accessEpoch;
    final homeId = _capabilities.homeId;
    _status = ServerAiWorkspaceStatus.loading;
    _safeMessage = null;
    _notify();
    try {
      await _repository.updateSettings(homeId: homeId, update: update);
      if (!_stillAuthorized(epoch, homeId, manage: true)) return;
      await _reloadAfterManagement(epoch, homeId);
    } on AiServerException catch (error) {
      await _handleServerExceptionIfCurrent(epoch, homeId, error);
    } catch (_) {
      _failIfCurrent(epoch, homeId, 'AI settings could not be saved safely.');
    }
    _notify();
  }

  Future<void> saveProviderProfile({
    required AiProviderProfileDraft draft,
    String? credential,
  }) async {
    if (!_requireManage()) return;
    if (draft.ownerScope == AiProfileOwnerScope.home &&
        !_capabilities.mayShareHomeProfiles) {
      _setFailure(
        'Only the home owner can share an AI provider profile with this home.',
      );
      return;
    }
    final current = draft.id == null ? null : _workspace?.profile(draft.id!);
    if ((draft.id == null && draft.expectedRevision != 0) ||
        (draft.id != null &&
            (current == null || current.revision != draft.expectedRevision))) {
      _setFailure('Refresh provider profiles before saving changes.');
      return;
    }
    final epoch = _accessEpoch;
    final homeId = _capabilities.homeId;
    _status = ServerAiWorkspaceStatus.loading;
    _safeMessage = null;
    _notify();
    try {
      await _repository.saveProviderProfile(
        homeId: homeId,
        draft: draft,
        credential: credential,
      );
      if (!_stillAuthorized(epoch, homeId, manage: true)) return;
      await _reloadAfterManagement(epoch, homeId);
    } on AiServerException catch (error) {
      await _handleServerExceptionIfCurrent(epoch, homeId, error);
    } catch (_) {
      _failIfCurrent(epoch, homeId, 'The provider could not be saved safely.');
    }
    _notify();
  }

  Future<void> updatePolicy(AiOrchestrationPolicyUpdate update) async {
    if (!_requireManage()) return;
    final current = _workspace;
    if (current == null || update.expectedRevision != current.policy.revision) {
      _setFailure('Refresh the AI policy before saving changes.');
      return;
    }
    final profileIds = current.profiles.map((profile) => profile.id).toSet();
    if (update.extractionProfileIds.any(
          (profileId) => !profileIds.contains(profileId),
        ) ||
        (update.validationProfileId != null &&
            !profileIds.contains(update.validationProfileId))) {
      _setFailure('Choose provider profiles from the active household.');
      return;
    }
    final epoch = _accessEpoch;
    final homeId = _capabilities.homeId;
    _status = ServerAiWorkspaceStatus.loading;
    _safeMessage = null;
    _notify();
    try {
      await _repository.updatePolicy(homeId: homeId, update: update);
      if (!_stillAuthorized(epoch, homeId, manage: true)) return;
      await _reloadAfterManagement(epoch, homeId);
    } on AiServerException catch (error) {
      await _handleServerExceptionIfCurrent(epoch, homeId, error);
    } catch (_) {
      _failIfCurrent(epoch, homeId, 'The AI policy could not be saved safely.');
    }
    _notify();
  }

  Future<void> prepareOne({
    required AiProviderProfile provider,
    required AiMediaAsset asset,
  }) => _prepareSelection(
    provider: provider,
    purpose: asset.purpose,
    assets: <AiMediaAsset>[asset],
  );

  Future<void> prepareReceiptPages({
    required AiProviderProfile provider,
    required List<AiMediaAsset> assets,
  }) => _prepareSelection(
    provider: provider,
    purpose: AiExtractionKind.receipt,
    assets: List<AiMediaAsset>.of(assets),
  );

  Future<void> _prepareSelection({
    required AiProviderProfile provider,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) async {
    if (!_requireUse()) return;
    final current = _workspace?.profile(provider.id);
    if (current == null ||
        current.revision != provider.revision ||
        provider.homeId != _capabilities.homeId ||
        assets.any(
          (asset) =>
              asset.homeId != _capabilities.homeId || asset.purpose != purpose,
        ) ||
        purpose != AiExtractionKind.receipt &&
            purpose != AiExtractionKind.stockPhoto) {
      _setFailure('Refresh the provider and choose media for the active home.');
      return;
    }
    final plan = _workspace?.settings.transmissionPlan;
    if (plan == null ||
        plan.primary.profileId != provider.id ||
        plan.primary.revision != provider.revision) {
      _setFailure(
        'Choose the active primary provider, refresh its plan, and review every recipient before sending.',
      );
      return;
    }
    if ((purpose == AiExtractionKind.receipt &&
            (assets.isEmpty || assets.length > 8)) ||
        (purpose == AiExtractionKind.stockPhoto &&
            (assets.isEmpty || assets.length > 8))) {
      _setFailure(
        purpose == AiExtractionKind.receipt
            ? 'Select between 1 and 8 receipt images.'
            : 'Select between 1 and 8 stock images.',
      );
      return;
    }
    if (assets.length > 1 &&
        !current.capabilities.contains(AiCapability.multiImage)) {
      _setFailure('This provider cannot safely process multiple images.');
      return;
    }
    final stockTarget = purpose == AiExtractionKind.stockPhoto
        ? _stockCountTarget?.call()
        : null;
    if (purpose == AiExtractionKind.stockPhoto && stockTarget == null) {
      _setFailure(
        'Start an ordinary stock count in Inventory before selecting stock images.',
      );
      return;
    }
    final epoch = _accessEpoch;
    final homeId = _capabilities.homeId;
    _status = ServerAiWorkspaceStatus.preparing;
    _safeMessage = null;
    await _discardPrepared();
    _clearExtractionState();
    _preparedStockTarget = stockTarget;
    _notify();
    try {
      final prepared = await PrepareAiMedia(
        _media,
      ).execute(homeId: homeId, purpose: purpose, assets: assets);
      if (!_stillAuthorized(epoch, homeId, use: true)) {
        await _media.discard(prepared);
        return;
      }
      final orderIsStable =
          prepared.media.length == assets.length &&
          (assets.length == 1 ||
              Iterable<int>.generate(assets.length).every(
                (index) =>
                    prepared.media[index].sourceMediaId == assets[index].id &&
                    prepared.media[index].pageIndex ==
                        (assets[index].pageIndex ?? index),
              ));
      if (!orderIsStable ||
          prepared.homeId != homeId ||
          prepared.purpose != purpose) {
        await _media.discard(prepared);
        throw AiPolicyViolation(
          code: 'unsafe_prepared_media',
          safeMessage: assets.length == 1
              ? 'The selected image could not be prepared safely.'
              : 'The selected images could not be prepared safely.',
        );
      }
      _selectedProvider = current;
      _prepared = prepared;
      _status = ServerAiWorkspaceStatus.awaitingConsent;
    } on AiPolicyViolation catch (error) {
      _failIfCurrent(epoch, homeId, error.safeMessage);
    } catch (_) {
      _failIfCurrent(
        epoch,
        homeId,
        assets.length == 1
            ? 'The selected image could not be prepared safely.'
            : 'The selected images could not be prepared safely.',
      );
    }
    _notify();
  }

  void confirmTransmission() {
    if (!_requireUse()) return;
    final provider = _selectedProvider;
    final prepared = _prepared;
    if (_status != ServerAiWorkspaceStatus.awaitingConsent ||
        provider == null ||
        prepared == null) {
      _setFailure('Prepare one image before confirming transmission.');
      return;
    }
    _consent = AiConsent(
      providerId: provider.id,
      providerRevision: provider.revision,
      privacyMode: AiPrivacyMode.serverProxyCloud,
      purpose: prepared.purpose,
      orderedMediaHashes: prepared.orderedHashes,
      disclosureVersion: AiPrivacyPolicy.disclosureVersion,
      confirmedAt: _clock().toUtc(),
      transmissionPlanHash: _workspace?.settings.transmissionPlan?.sha256,
    );
    _safeMessage = null;
    _notify();
  }

  void revokeTransmission() {
    if (_consent == null) return;
    _consent = null;
    _notify();
  }

  Future<void> extract() async {
    if (!_requireUse()) return;
    final provider = _selectedProvider;
    final prepared = _prepared;
    final consent = _consent;
    final current = provider == null ? null : _workspace?.profile(provider.id);
    if (provider == null ||
        prepared == null ||
        consent == null ||
        current == null ||
        current.revision != provider.revision ||
        consent.transmissionPlanHash == null ||
        consent.transmissionPlanHash !=
            _workspace?.settings.transmissionPlan?.sha256) {
      _setFailure('Review the provider and image, then confirm transmission.');
      return;
    }
    final epoch = _accessEpoch;
    final homeId = _capabilities.homeId;
    _status = ServerAiWorkspaceStatus.processing;
    _safeMessage = null;
    _notify();
    try {
      _policy.authorizeExtraction(
        profile: provider,
        privacyMode: AiPrivacyMode.serverProxyCloud,
        media: prepared,
        consent: consent,
      );
      if (_gateway.route != AiGatewayRoute.serverProxyCloud) {
        throw const AiPolicyViolation(
          code: 'gateway_contract_unavailable',
          safeMessage: 'The secure AI connection is not available.',
        );
      }
      final readiness = await _gateway.readiness(provider);
      if (!readiness.isReady) {
        throw AiPolicyViolation(
          code: 'provider_unavailable',
          safeMessage: readiness.safeMessage ?? 'The AI provider is not ready.',
        );
      }
      if (!_stillAuthorized(epoch, homeId, use: true)) return;
      if (prepared.purpose == AiExtractionKind.stockPhoto &&
          (_preparedStockTarget == null ||
              _stockCountTarget?.call() != _preparedStockTarget)) {
        throw const AiPolicyViolation(
          code: 'count_changed',
          safeMessage:
              'The stock count changed. Select images again for the current open count.',
        );
      }
      final request = AiExtractionRequest(
        runId: _identifiers.nextId(),
        homeId: homeId,
        kind: prepared.purpose,
        provider: provider,
        privacyMode: AiPrivacyMode.serverProxyCloud,
        media: prepared,
        schemaVersion: prepared.purpose == AiExtractionKind.receipt
            ? AiProposalSchemas.receiptVersion
            : AiProposalSchemas.stockPhotoVersion,
        promptVersion: prepared.purpose == AiExtractionKind.receipt
            ? 'receipt-extraction-v1'
            : 'stock-photo-extraction-v1',
        timeout: const Duration(seconds: 45),
        targetId: _preparedStockTarget,
        transmissionPlan: _workspace?.settings.transmissionPlan,
      );
      if (prepared.purpose == AiExtractionKind.receipt) {
        final result = await _gateway.extractReceipt(request);
        if (!_stillAuthorized(epoch, homeId, use: true)) return;
        await _handleReceiptResult(result, epoch: epoch, homeId: homeId);
      } else {
        final result = await _gateway.extractStockPhoto(request);
        if (!_stillAuthorized(epoch, homeId, use: true)) return;
        await _handleStockResult(result, epoch: epoch, homeId: homeId);
      }
    } on AiGatewayAuthorizationDeniedException catch (error) {
      await _denyAccessIfCurrent(epoch, homeId, error.safeMessage);
    } on AiPolicyViolation catch (error) {
      _failIfCurrent(epoch, homeId, error.safeMessage);
    } on AiServerException catch (error) {
      await _handleServerExceptionIfCurrent(epoch, homeId, error);
    } catch (_) {
      _failIfCurrent(
        epoch,
        homeId,
        'AI extraction could not be completed safely.',
      );
    } finally {
      _consent = null;
      if (_status != ServerAiWorkspaceStatus.reviewRequired) {
        await _discardPrepared();
        _selectedProvider = null;
      }
    }
    _notify();
  }

  Future<void> _handleReceiptResult(
    AiExtractionResult<ReceiptProposal> result, {
    required int epoch,
    required String homeId,
  }) async {
    switch (result) {
      case AiExtractionSuccess<ReceiptProposal>():
        _receiptProposal = result.proposal;
        await _loadReviewForProposal(
          epoch: epoch,
          homeId: homeId,
          extractionId: result.proposal.id,
          kind: AiExtractionKind.receipt,
        );
      case AiExtractionQuarantined<ReceiptProposal>():
        _markQuarantined();
      case AiExtractionRefused<ReceiptProposal>():
        _setFailure(result.safeReason);
      case AiExtractionIncomplete<ReceiptProposal>():
        _setFailure(result.safeReason);
      case AiExtractionFailure<ReceiptProposal>():
        _setFailure(result.safeMessage);
    }
  }

  Future<void> _handleStockResult(
    AiExtractionResult<StockPhotoProposal> result, {
    required int epoch,
    required String homeId,
  }) async {
    switch (result) {
      case AiExtractionSuccess<StockPhotoProposal>():
        _stockProposal = result.proposal;
        await _loadReviewForProposal(
          epoch: epoch,
          homeId: homeId,
          extractionId: result.proposal.id,
          kind: AiExtractionKind.stockPhoto,
        );
      case AiExtractionQuarantined<StockPhotoProposal>():
        _markQuarantined();
      case AiExtractionRefused<StockPhotoProposal>():
        _setFailure(result.safeReason);
      case AiExtractionIncomplete<StockPhotoProposal>():
        _setFailure(result.safeReason);
      case AiExtractionFailure<StockPhotoProposal>():
        _setFailure(result.safeMessage);
    }
  }

  void _markQuarantined() {
    _status = ServerAiWorkspaceStatus.quarantined;
    _safeMessage =
        'The image was quarantined and cannot change household data.';
  }

  Future<void> reviewCandidate({
    required int position,
    required AiCandidateDecision decision,
  }) async {
    if (isBusy ||
        _status != ServerAiWorkspaceStatus.reviewRequired ||
        !_requireUse())
      return;
    final review = _review;
    final candidate = review?.candidates
        .where((item) => item.position == position)
        .firstOrNull;
    if (review == null ||
        candidate == null ||
        candidate.status == AiCandidateReviewStatus.rejected ||
        (decision == AiCandidateDecision.accept &&
            (candidate.status != AiCandidateReviewStatus.pending ||
                !review.canAccept(position)))) {
      _safeMessage =
          'Resolve all evidence first. Confirmed duplicate candidates must be rejected.';
      _notify();
      return;
    }
    await _changeReview(
      review,
      () =>
          _repository.reviewCandidate(candidate: candidate, decision: decision),
    );
  }

  Future<void> reviewObservation(
    String id,
    AiObservationDecision decision,
  ) async {
    if (isBusy ||
        _status != ServerAiWorkspaceStatus.reviewRequired ||
        !_requireUse())
      return;
    final review = _review;
    final repository = _repository;
    final observation = review?.observations
        .where((item) => item.id == id)
        .firstOrNull;
    if (review == null ||
        observation == null ||
        repository is! AiEvidenceReviewRepository ||
        observation.exactDigest ||
        decision == AiObservationDecision.pending)
      return;
    await _changeReview(
      review,
      () => repository.reviewObservation(
        review: review,
        observation: observation,
        decision: decision,
      ),
    );
  }

  Future<void> reviewDiscrepancy(
    int position,
    AiDiscrepancyDecision decision,
  ) async {
    if (isBusy ||
        _status != ServerAiWorkspaceStatus.reviewRequired ||
        !_requireUse())
      return;
    final review = _review;
    final repository = _repository;
    final discrepancy = review?.discrepancies
        .where((item) => item.position == position)
        .firstOrNull;
    if (review == null ||
        discrepancy == null ||
        repository is! AiEvidenceReviewRepository ||
        decision == AiDiscrepancyDecision.pending)
      return;
    await _changeReview(
      review,
      () => repository.reviewDiscrepancy(
        review: review,
        discrepancy: discrepancy,
        decision: decision,
      ),
    );
  }

  /// A lost mutation response is never retried blindly. Read the same extraction
  /// again, preserving unresolved evidence and its current revisions.
  Future<void> _changeReview(
    AiExtractionReview original,
    Future<AiExtractionReview> Function() change,
  ) async {
    final epoch = _accessEpoch;
    final homeId = _capabilities.homeId;
    if (original.homeId != homeId) return;
    _status = ServerAiWorkspaceStatus.processing;
    _safeMessage = null;
    _notify();
    try {
      final updated = await change();
      if (!_stillAuthorized(epoch, homeId, use: true)) return;
      _installReview(updated, original.extractionId);
    } on AiServerException catch (error) {
      if (!_stillAuthorized(epoch, homeId, use: true)) return;
      if (error.kind == AiServerFailureKind.authenticationRequired ||
          error.kind == AiServerFailureKind.authorizationDenied) {
        await _handleServerExceptionIfCurrent(epoch, homeId, error);
      } else {
        await _recoverReview(epoch, homeId, original.extractionId);
      }
    } catch (_) {
      if (_stillAuthorized(epoch, homeId, use: true)) {
        await _recoverReview(epoch, homeId, original.extractionId);
      }
    }
    _notify();
  }

  void _installReview(AiExtractionReview updated, String extractionId) {
    if (updated.homeId != _capabilities.homeId ||
        updated.extractionId != extractionId) {
      throw const AiServerException(AiServerFailureKind.invalidResponse);
    }
    _review = updated;
    _status = ServerAiWorkspaceStatus.reviewRequired;
  }

  Future<void> _recoverReview(
    int epoch,
    String homeId,
    String extractionId,
  ) async {
    try {
      final current = await _repository.loadExtractionReview(
        homeId: homeId,
        extractionId: extractionId,
      );
      if (!_stillAuthorized(epoch, homeId, use: true)) return;
      _installReview(current, extractionId);
      _safeMessage =
          'The review changed or its response was lost. Current evidence has been reloaded; review it before continuing.';
    } on AiServerException catch (error) {
      if (!_stillAuthorized(epoch, homeId, use: true)) return;
      if (error.kind == AiServerFailureKind.authenticationRequired ||
          error.kind == AiServerFailureKind.authorizationDenied) {
        await _handleServerExceptionIfCurrent(epoch, homeId, error);
      } else {
        _status = ServerAiWorkspaceStatus.failed;
        _safeMessage =
            'The current review could not be reloaded. Refresh this extraction before continuing.';
      }
    } catch (_) {
      if (!_stillAuthorized(epoch, homeId, use: true)) return;
      _status = ServerAiWorkspaceStatus.failed;
      _safeMessage =
          'The current review could not be reloaded. Refresh this extraction before continuing.';
    }
  }

  Future<void> resumeReview(String extractionId) async {
    if (isBusy || !_requireUse()) return;
    final epoch = ++_accessEpoch;
    final homeId = _capabilities.homeId;
    await _discardPrepared();
    _clearExtractionState();
    _status = ServerAiWorkspaceStatus.processing;
    _safeMessage = null;
    _notify();
    try {
      final loaded = await _repository.loadExtractionReview(
        homeId: homeId,
        extractionId: extractionId,
      );
      if (!_stillAuthorized(epoch, homeId, use: true)) return;
      _installReview(loaded, extractionId);
      await _rememberReview(loaded, epoch);
      if (!_stillAuthorized(epoch, homeId, use: true)) return;
      _safeMessage =
          'Current structured review restored. Images are not downloaded or sent to a provider.';
    } on AiServerException catch (error) {
      await _handleServerExceptionIfCurrent(epoch, homeId, error);
    } catch (_) {
      _failIfCurrent(
        epoch,
        homeId,
        'This extraction could not be restored safely.',
      );
    }
    _notify();
  }

  Future<void> _rememberReview(AiExtractionReview review, int epoch) async {
    final store = _resumeStore;
    if (store == null) return;
    final reference = AiReviewResumeReference(
      extractionId: review.extractionId,
      kind: review.kind,
    );
    await store.remember(reference);
    if (!_stillAuthorized(epoch, review.homeId, use: true)) return;
    _recentReviews =
        List<AiReviewResumeReference>.unmodifiable(<AiReviewResumeReference>[
          reference,
          ..._recentReviews
              .where((item) => item.extractionId != reference.extractionId)
              .take(19),
        ]);
  }

  Future<void> refreshReview() async {
    final review = _review;
    if (review == null || isBusy || !_requireUse()) return;
    await _changeReview(
      review,
      () => _repository.loadExtractionReview(
        homeId: review.homeId,
        extractionId: review.extractionId,
      ),
    );
  }

  AiReviewHandoff? buildReviewHandoff() {
    if (isBusy ||
        _status != ServerAiWorkspaceStatus.reviewRequired ||
        !_requireUse())
      return null;
    final review = _review;
    if (review == null || review.homeId != _capabilities.homeId) {
      _setFailure('Complete the AI candidate review first.');
      return null;
    }
    try {
      if (review.kind == AiExtractionKind.stockPhoto &&
          (review.targetId == null ||
              review.targetId != _stockCountTarget?.call())) {
        _safeMessage =
            'Reopen the original stock count before preparing its reviewed handoff.';
        _notify();
        return null;
      }
      final handoff = const AiReviewHandoffBuilder().build(review);
      _safeMessage = null;
      _notify();
      return handoff;
    } on AiServerException catch (error) {
      _setFailure(error.safeMessage);
      return null;
    }
  }

  Future<void> clearExtraction() async {
    _accessEpoch++;
    await _discardPrepared();
    _clearExtractionState();
    _status = _capabilities.mayRead
        ? ServerAiWorkspaceStatus.ready
        : ServerAiWorkspaceStatus.accessDenied;
    _safeMessage = null;
    _notify();
  }

  Future<void> _reloadAfterManagement(int epoch, String homeId) async {
    final loaded = await _repository.loadWorkspace(homeId: homeId);
    if (!_stillAuthorized(epoch, homeId, manage: true)) return;
    if (loaded.homeId != homeId) {
      throw const AiServerException(AiServerFailureKind.invalidResponse);
    }
    _workspace = loaded;
    _status = ServerAiWorkspaceStatus.ready;
  }

  Future<void> _loadReviewForProposal({
    required int epoch,
    required String homeId,
    required String extractionId,
    required AiExtractionKind kind,
  }) async {
    final review = await _repository.loadExtractionReview(
      homeId: homeId,
      extractionId: extractionId,
    );
    if (!_stillAuthorized(epoch, homeId, use: true)) return;
    if (review.homeId != homeId ||
        review.extractionId != extractionId ||
        review.kind != kind) {
      throw const AiServerException(AiServerFailureKind.invalidResponse);
    }
    await _rememberReview(review, epoch);
    if (!_stillAuthorized(epoch, homeId, use: true)) return;
    _review = review;
    _status = ServerAiWorkspaceStatus.reviewRequired;
  }

  bool _requireRead() {
    if (_capabilities.mayRead && _capabilities.homeId.isNotEmpty) return true;
    _setAccessDenied();
    return false;
  }

  bool _requireUse() {
    if (_capabilities.mayRead &&
        _capabilities.mayUse &&
        _capabilities.homeId.isNotEmpty) {
      return true;
    }
    _setAccessDenied();
    return false;
  }

  bool _requireManage() {
    if (_capabilities.mayRead &&
        _capabilities.mayManage &&
        _capabilities.homeId.isNotEmpty) {
      return true;
    }
    _setAccessDenied();
    return false;
  }

  bool _stillAuthorized(
    int epoch,
    String homeId, {
    bool read = false,
    bool use = false,
    bool manage = false,
  }) {
    return !_disposed &&
        epoch == _accessEpoch &&
        homeId == _capabilities.homeId &&
        (!read || _capabilities.mayRead) &&
        (!use || (_capabilities.mayRead && _capabilities.mayUse)) &&
        (!manage || (_capabilities.mayRead && _capabilities.mayManage));
  }

  void _failIfCurrent(int epoch, String homeId, String message) {
    if (_stillAuthorized(epoch, homeId)) _setFailure(message);
  }

  Future<void> _handleServerExceptionIfCurrent(
    int epoch,
    String homeId,
    AiServerException error,
  ) async {
    if (error.kind == AiServerFailureKind.authorizationDenied) {
      await _denyAccessIfCurrent(epoch, homeId, error.safeMessage);
      return;
    }
    _failIfCurrent(epoch, homeId, error.safeMessage);
  }

  Future<void> _denyAccessIfCurrent(
    int epoch,
    String homeId,
    String safeMessage,
  ) async {
    if (!_stillAuthorized(epoch, homeId)) return;
    _accessEpoch++;
    final discard = _discardPrepared();
    _clearExtractionState();
    _workspace = null;
    _status = ServerAiWorkspaceStatus.accessDenied;
    _safeMessage = safeMessage;
    _notify();
    await discard;
  }

  void _setAccessDenied() {
    _status = ServerAiWorkspaceStatus.accessDenied;
    _safeMessage = 'Your current household role does not allow this AI action.';
    _notify();
  }

  void _setFailure(String message) {
    _status = ServerAiWorkspaceStatus.failed;
    _safeMessage = message;
    _notify();
  }

  void _clearExtractionState() {
    _preparedStockTarget = null;
    _selectedProvider = null;
    _prepared = null;
    _consent = null;
    _receiptProposal = null;
    _stockProposal = null;
    _review = null;
  }

  Future<void> _discardPrepared() async {
    final prepared = _prepared;
    _prepared = null;
    if (prepared != null) {
      try {
        await _media.discard(prepared);
      } catch (_) {
        // Prepared media cleanup is best-effort and never exposes a path.
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _accessEpoch++;
    _workspace = null;
    final discard = _discardPrepared();
    _clearExtractionState();
    unawaited(discard);
    super.dispose();
  }
}
