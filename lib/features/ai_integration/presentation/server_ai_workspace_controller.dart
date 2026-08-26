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
  }) => ServerAiWorkspaceController._(
    repository,
    media,
    gateway,
    identifiers,
    capabilities,
    policy,
    clock ?? DateTime.now,
  );

  ServerAiWorkspaceController._(
    this._repository,
    this._media,
    this._gateway,
    this._identifiers,
    this._capabilities,
    this._policy,
    this._clock,
  ) : _status = _capabilities.mayRead
          ? ServerAiWorkspaceStatus.idle
          : ServerAiWorkspaceStatus.accessDenied;

  final ServerAiRepository _repository;
  final AiMediaPreparationPort _media;
  final AiProviderGateway _gateway;
  final AiIdentifierFactory _identifiers;
  final AiPrivacyPolicy _policy;
  final DateTime Function() _clock;

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
    if ((purpose == AiExtractionKind.receipt &&
            (assets.isEmpty || assets.length > 8)) ||
        (purpose == AiExtractionKind.stockPhoto && assets.length != 1)) {
      _setFailure(
        purpose == AiExtractionKind.receipt
            ? 'Select between 1 and 8 receipt images.'
            : 'Select one stock image.',
      );
      return;
    }
    if (assets.length > 1 &&
        !current.capabilities.contains(AiCapability.multiImage)) {
      _setFailure('This provider cannot safely process multiple images.');
      return;
    }
    final epoch = _accessEpoch;
    final homeId = _capabilities.homeId;
    _status = ServerAiWorkspaceStatus.preparing;
    _safeMessage = null;
    await _discardPrepared();
    _clearExtractionState();
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
        current.revision != provider.revision) {
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
    if (!_requireUse()) return;
    final review = _review;
    if (review == null || review.homeId != _capabilities.homeId) {
      _setFailure('Reload the AI extraction before reviewing candidates.');
      return;
    }
    AiReviewCandidate? candidate;
    for (final item in review.candidates) {
      if (item.position == position) {
        candidate = item;
        break;
      }
    }
    if (candidate == null ||
        candidate.status != AiCandidateReviewStatus.pending) {
      _setFailure('This AI candidate has already been reviewed.');
      return;
    }
    final epoch = _accessEpoch;
    final homeId = _capabilities.homeId;
    _status = ServerAiWorkspaceStatus.processing;
    _safeMessage = null;
    _notify();
    try {
      final updated = await _repository.reviewCandidate(
        candidate: candidate,
        decision: decision,
      );
      if (!_stillAuthorized(epoch, homeId, use: true)) return;
      if (updated.homeId != homeId ||
          updated.extractionId != review.extractionId) {
        throw const AiServerException(AiServerFailureKind.invalidResponse);
      }
      _review = updated;
      _status = ServerAiWorkspaceStatus.reviewRequired;
    } on AiServerException catch (error) {
      await _handleServerExceptionIfCurrent(epoch, homeId, error);
    } catch (_) {
      _failIfCurrent(
        epoch,
        homeId,
        'The review decision was not saved safely.',
      );
    }
    _notify();
  }

  AiReviewHandoff? buildReviewHandoff() {
    if (!_requireUse()) return null;
    final review = _review;
    if (review == null || review.homeId != _capabilities.homeId) {
      _setFailure('Complete the AI candidate review first.');
      return null;
    }
    try {
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
