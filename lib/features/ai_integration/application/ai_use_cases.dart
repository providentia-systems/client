import 'dart:async';

import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';
import 'package:providentia/features/ai_integration/domain/proposal_validation.dart';

final class ConfigureAiProvider {
  const ConfigureAiProvider({
    required AiPrivacyPolicy policy,
    required AiProviderRepository providers,
    required AiGatewayResolver gateways,
    required ServerCredentialProvisioningPort serverCredentials,
    required CredentialVault credentialVault,
  }) : _policy = policy,
       _providers = providers,
       _gateways = gateways,
       _serverCredentials = serverCredentials,
       _credentialVault = credentialVault;

  final AiPrivacyPolicy _policy;
  final AiProviderRepository _providers;
  final AiGatewayResolver _gateways;
  final ServerCredentialProvisioningPort _serverCredentials;
  final CredentialVault _credentialVault;

  Future<AiProviderProfile> execute({
    required AiProviderProfile profile,
    String? replacementSecret,
  }) async {
    var configured = profile;
    final secret = replacementSecret?.trim();
    if (profile.transport == AiTransport.serverProxy &&
        secret != null &&
        secret.isNotEmpty) {
      await _serverCredentials.replaceCredential(
        homeId: profile.homeId,
        profileId: profile.id,
        secret: secret,
      );
      configured = profile.copyWith(credentialConfigured: true);
    } else if (profile.transport == AiTransport.directNative &&
        secret != null &&
        secret.isNotEmpty) {
      if (!_credentialVault.supportsNativeSecrets) {
        throw const AiPolicyViolation(
          code: 'native_vault_unavailable',
          safeMessage:
              'Secure local credential storage is unavailable on this platform.',
        );
      }
      await _credentialVault.write(profileId: profile.id, secret: secret);
      configured = profile.copyWith(credentialConfigured: true);
    }

    _policy.validateProfile(configured);
    final route = _routeFor(configured.transport);
    final gateway = _gateways.forRoute(route);
    if (gateway == null || gateway.route != route) {
      throw const AiPolicyViolation(
        code: 'gateway_contract_unavailable',
        safeMessage: 'The required secure AI connection is not available.',
      );
    }
    final readiness = await gateway.readiness(configured);
    if (!readiness.isReady) {
      throw AiPolicyViolation(
        code: switch (readiness.state) {
          AiGatewayReadinessState.missingBackendContract =>
            'provider_contract_unavailable',
          AiGatewayReadinessState.missingCapability =>
            'required_capability_missing',
          AiGatewayReadinessState.unavailable => 'provider_unavailable',
          AiGatewayReadinessState.ready => 'provider_unavailable',
        },
        safeMessage:
            readiness.safeMessage ??
            'The provider could not be verified safely.',
      );
    }
    await _providers.save(configured);
    return configured;
  }

  Future<void> delete(AiProviderProfile profile) async {
    if (profile.transport == AiTransport.serverProxy) {
      await _serverCredentials.deleteCredential(
        homeId: profile.homeId,
        profileId: profile.id,
      );
    } else if (_credentialVault.supportsNativeSecrets) {
      await _credentialVault.delete(profile.id);
    }
    await _providers.delete(homeId: profile.homeId, providerId: profile.id);
  }
}

final class PrepareAiMedia {
  const PrepareAiMedia(this._media);

  final AiMediaPreparationPort _media;

  Future<PreparedMediaBatch> execute({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) {
    if (homeId.trim().isEmpty || assets.isEmpty) {
      throw const AiPolicyViolation(
        code: 'media_required',
        safeMessage: 'Add at least one image or receipt page.',
      );
    }
    if (assets.any(
      (asset) => asset.homeId != homeId || asset.purpose != purpose,
    )) {
      throw const AiPolicyViolation(
        code: 'media_scope_mismatch',
        safeMessage:
            'All selected media must belong to this home and workflow.',
      );
    }
    return _media.prepare(homeId: homeId, purpose: purpose, assets: assets);
  }
}

final class ExtractReceiptProposal {
  const ExtractReceiptProposal({
    required AiPrivacyPolicy policy,
    required AiGatewayResolver gateways,
    required AiMediaPreparationPort media,
    required AiRunRepository runs,
    required AiProposalRepository proposals,
    required AiIdentifierFactory identifiers,
    DateTime Function()? clock,
  }) : _policy = policy,
       _gateways = gateways,
       _media = media,
       _runs = runs,
       _proposals = proposals,
       _identifiers = identifiers,
       _clock = clock ?? DateTime.now;

  final AiPrivacyPolicy _policy;
  final AiGatewayResolver _gateways;
  final AiMediaPreparationPort _media;
  final AiRunRepository _runs;
  final AiProposalRepository _proposals;
  final AiIdentifierFactory _identifiers;
  final DateTime Function() _clock;

  Future<AiExtractionResult<ReceiptProposal>> execute({
    required AiProviderProfile provider,
    required AiPrivacyMode privacyMode,
    required PreparedMediaBatch media,
    required AiConsent consent,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    _policy.authorizeExtraction(
      profile: provider,
      privacyMode: privacyMode,
      media: media,
      consent: consent,
    );
    if (media.purpose != AiExtractionKind.receipt) {
      throw const AiPolicyViolation(
        code: 'wrong_media_purpose',
        safeMessage: 'These images were not prepared for receipt extraction.',
      );
    }
    final run = AiRunRecord(
      id: _identifiers.nextId(),
      homeId: provider.homeId,
      kind: AiExtractionKind.receipt,
      providerId: provider.id,
      state: AiRunState.processing,
      createdAt: _clock().toUtc(),
    );
    await _runs.save(run);
    try {
      final gateway = await _readyGateway(provider, privacyMode);
      final request = AiExtractionRequest(
        runId: run.id,
        homeId: provider.homeId,
        kind: AiExtractionKind.receipt,
        provider: provider,
        privacyMode: privacyMode,
        media: media,
        schemaVersion: AiProposalSchemas.receiptVersion,
        promptVersion: 'receipt-extraction-v1',
        timeout: timeout,
      );
      final result = await gateway.extractReceipt(request);
      return switch (result) {
        AiExtractionSuccess<ReceiptProposal>() => _acceptReceipt(run, result),
        AiExtractionRefused<ReceiptProposal>() => _recordReceiptFailure(
          run,
          result,
          'provider_refused',
        ),
        AiExtractionIncomplete<ReceiptProposal>() => _recordReceiptFailure(
          run,
          result,
          'provider_incomplete',
        ),
        AiExtractionFailure<ReceiptProposal>() => _recordReceiptFailure(
          run,
          result,
          result.code,
        ),
        AiExtractionQuarantined<ReceiptProposal>() => _recordReceiptQuarantine(
          run,
          result.classification,
        ),
      };
    } on AiPolicyViolation {
      await _runs.save(run.withState(AiRunState.failed));
      rethrow;
    } on ProposalValidationException {
      await _runs.save(
        run.withState(
          AiRunState.failed,
          safeFailureCode: 'invalid_structured_output',
        ),
      );
      rethrow;
    } finally {
      await _media.discard(media);
    }
  }

  Future<AiExtractionResult<ReceiptProposal>> _acceptReceipt(
    AiRunRecord run,
    AiExtractionSuccess<ReceiptProposal> success,
  ) async {
    final proposal = success.proposal;
    if (proposal.runId != run.id ||
        proposal.schemaVersion != AiProposalSchemas.receiptVersion) {
      throw ProposalValidationException(<String>[
        'The proposal does not match its extraction run or schema.',
      ]);
    }
    if (proposal.requiresQuarantine ||
        proposal.classification == ReceiptDocumentClassification.unknown) {
      return _recordReceiptQuarantine(
        run,
        proposal.classification.name,
        metadata: success.metadata,
      );
    }
    await _proposals.saveReceipt(homeId: run.homeId, proposal: proposal);
    await _runs.save(
      run.withState(AiRunState.reviewRequired, metadata: success.metadata),
    );
    return success;
  }

  Future<AiExtractionResult<ReceiptProposal>> _recordReceiptFailure(
    AiRunRecord run,
    AiExtractionResult<ReceiptProposal> result,
    String code,
  ) async {
    await _runs.save(run.withState(AiRunState.failed, safeFailureCode: code));
    return result;
  }

  Future<AiExtractionResult<ReceiptProposal>> _recordReceiptQuarantine(
    AiRunRecord run,
    String classification, {
    AiRunMetadata? metadata,
  }) async {
    await _runs.save(run.withState(AiRunState.quarantined, metadata: metadata));
    return AiExtractionQuarantined<ReceiptProposal>(
      classification: classification,
    );
  }

  Future<AiProviderGateway> _readyGateway(
    AiProviderProfile provider,
    AiPrivacyMode privacyMode,
  ) async {
    final route = _routeForMode(privacyMode);
    final gateway = _gateways.forRoute(route);
    if (gateway == null || gateway.route != route) {
      throw const AiPolicyViolation(
        code: 'gateway_contract_unavailable',
        safeMessage: 'The required secure AI connection is not available.',
      );
    }
    final readiness = await gateway.readiness(provider);
    if (!readiness.isReady) {
      throw AiPolicyViolation(
        code: readiness.state == AiGatewayReadinessState.missingBackendContract
            ? 'provider_contract_unavailable'
            : 'provider_unavailable',
        safeMessage:
            readiness.safeMessage ?? 'The provider connection is not ready.',
      );
    }
    return gateway;
  }
}

final class ExtractStockPhotoProposal {
  const ExtractStockPhotoProposal({
    required AiPrivacyPolicy policy,
    required AiGatewayResolver gateways,
    required AiMediaPreparationPort media,
    required AiRunRepository runs,
    required AiProposalRepository proposals,
    required AiIdentifierFactory identifiers,
    DateTime Function()? clock,
  }) : _policy = policy,
       _gateways = gateways,
       _media = media,
       _runs = runs,
       _proposals = proposals,
       _identifiers = identifiers,
       _clock = clock ?? DateTime.now;

  final AiPrivacyPolicy _policy;
  final AiGatewayResolver _gateways;
  final AiMediaPreparationPort _media;
  final AiRunRepository _runs;
  final AiProposalRepository _proposals;
  final AiIdentifierFactory _identifiers;
  final DateTime Function() _clock;

  Future<AiExtractionResult<StockPhotoProposal>> execute({
    required AiProviderProfile provider,
    required AiPrivacyMode privacyMode,
    required PreparedMediaBatch media,
    required AiConsent consent,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    _policy.authorizeExtraction(
      profile: provider,
      privacyMode: privacyMode,
      media: media,
      consent: consent,
    );
    if (media.purpose != AiExtractionKind.stockPhoto) {
      throw const AiPolicyViolation(
        code: 'wrong_media_purpose',
        safeMessage: 'These images were not prepared for stock counting.',
      );
    }
    final run = AiRunRecord(
      id: _identifiers.nextId(),
      homeId: provider.homeId,
      kind: AiExtractionKind.stockPhoto,
      providerId: provider.id,
      state: AiRunState.processing,
      createdAt: _clock().toUtc(),
    );
    await _runs.save(run);
    try {
      final route = _routeForMode(privacyMode);
      final gateway = _gateways.forRoute(route);
      if (gateway == null || gateway.route != route) {
        throw const AiPolicyViolation(
          code: 'gateway_contract_unavailable',
          safeMessage: 'The required secure AI connection is not available.',
        );
      }
      final readiness = await gateway.readiness(provider);
      if (!readiness.isReady) {
        throw AiPolicyViolation(
          code:
              readiness.state == AiGatewayReadinessState.missingBackendContract
              ? 'provider_contract_unavailable'
              : 'provider_unavailable',
          safeMessage:
              readiness.safeMessage ?? 'The provider connection is not ready.',
        );
      }
      final result = await gateway.extractStockPhoto(
        AiExtractionRequest(
          runId: run.id,
          homeId: provider.homeId,
          kind: AiExtractionKind.stockPhoto,
          provider: provider,
          privacyMode: privacyMode,
          media: media,
          schemaVersion: AiProposalSchemas.stockPhotoVersion,
          promptVersion: 'stock-photo-extraction-v1',
          timeout: timeout,
        ),
      );
      if (result case AiExtractionSuccess<StockPhotoProposal> success) {
        final proposal = success.proposal;
        if (proposal.runId != run.id ||
            proposal.schemaVersion != AiProposalSchemas.stockPhotoVersion) {
          throw ProposalValidationException(<String>[
            'The proposal does not match its extraction run or schema.',
          ]);
        }
        if (proposal.requiresQuarantine ||
            proposal.classification == StockImageClassification.unknown) {
          await _runs.save(
            run.withState(AiRunState.quarantined, metadata: success.metadata),
          );
          return AiExtractionQuarantined<StockPhotoProposal>(
            classification: proposal.classification.name,
          );
        }
        await _proposals.saveStockPhoto(homeId: run.homeId, proposal: proposal);
        await _runs.save(
          run.withState(AiRunState.reviewRequired, metadata: success.metadata),
        );
      } else {
        final code = switch (result) {
          AiExtractionRefused<StockPhotoProposal>() => 'provider_refused',
          AiExtractionIncomplete<StockPhotoProposal>() => 'provider_incomplete',
          AiExtractionFailure<StockPhotoProposal>() => result.code,
          AiExtractionQuarantined<StockPhotoProposal>() => 'quarantined',
          AiExtractionSuccess<StockPhotoProposal>() => 'unknown',
        };
        await _runs.save(
          run.withState(
            code == 'quarantined' ? AiRunState.quarantined : AiRunState.failed,
            safeFailureCode: code,
          ),
        );
      }
      return result;
    } on AiPolicyViolation {
      await _runs.save(run.withState(AiRunState.failed));
      rethrow;
    } on ProposalValidationException {
      await _runs.save(
        run.withState(
          AiRunState.failed,
          safeFailureCode: 'invalid_structured_output',
        ),
      );
      rethrow;
    } finally {
      await _media.discard(media);
    }
  }
}

final class ApproveReceiptProposal {
  const ApproveReceiptProposal({
    required AiProposalRepository proposals,
    required ReceiptCommitPort commits,
  }) : _proposals = proposals,
       _commits = commits;

  final AiProposalRepository _proposals;
  final ReceiptCommitPort _commits;

  Future<CommitOutcome> execute({
    required ReviewedReceipt review,
    required String idempotencyKey,
  }) async {
    _requireIdempotencyKey(idempotencyKey);
    final existing = await _proposals.findReceiptCommitOutcome(
      homeId: review.homeId,
      idempotencyKey: idempotencyKey,
    );
    if (existing != null) {
      return existing;
    }
    if (!review.humanConfirmed || review.lines.isEmpty) {
      throw const AiPolicyViolation(
        code: 'human_approval_required',
        safeMessage: 'Review and explicitly approve at least one receipt line.',
      );
    }
    final proposal = await _proposals.findReceipt(
      homeId: review.homeId,
      proposalId: review.proposalId,
    );
    if (proposal == null ||
        proposal.runId != review.runId ||
        proposal.requiresQuarantine ||
        proposal.classification == ReceiptDocumentClassification.unknown) {
      throw const AiPolicyViolation(
        code: 'proposal_not_approvable',
        safeMessage: 'This receipt proposal cannot be approved.',
      );
    }
    final availableIds = proposal.lines.map((line) => line.lineId).toSet();
    final reviewedIds = <String>{};
    for (final line in review.lines) {
      if (!availableIds.contains(line.proposalLineId) ||
          !reviewedIds.add(line.proposalLineId) ||
          line.resolution.kind == CatalogResolutionKind.unresolved ||
          line.quantity <= 0 ||
          !line.quantity.isFinite) {
        throw const AiPolicyViolation(
          code: 'invalid_receipt_review',
          safeMessage:
              'Resolve each selected line and enter a valid quantity before approval.',
        );
      }
    }
    await _proposals.markReceiptApproved(
      homeId: review.homeId,
      proposalId: review.proposalId,
    );
    final outcome = await _commits.commitApprovedReceipt(
      receipt: review,
      idempotencyKey: idempotencyKey,
    );
    await _proposals.saveReceiptCommitOutcome(
      homeId: review.homeId,
      idempotencyKey: idempotencyKey,
      outcome: outcome,
    );
    return outcome;
  }
}

final class CloseStockPhotoCount {
  const CloseStockPhotoCount({
    required AiProposalRepository proposals,
    required StockCountCommitPort commits,
  }) : _proposals = proposals,
       _commits = commits;

  final AiProposalRepository _proposals;
  final StockCountCommitPort _commits;

  Future<CommitOutcome> execute({
    required ReviewedStockCount review,
    required String idempotencyKey,
  }) async {
    _requireIdempotencyKey(idempotencyKey);
    final existing = await _proposals.findCountCommitOutcome(
      homeId: review.homeId,
      idempotencyKey: idempotencyKey,
    );
    if (existing != null) {
      return existing;
    }
    if (!review.explicitlyClosed) {
      throw const AiPolicyViolation(
        code: 'explicit_close_required',
        safeMessage: 'Review the count and explicitly close the session.',
      );
    }
    final proposal = await _proposals.findStockPhoto(
      homeId: review.homeId,
      proposalId: review.proposalId,
    );
    if (proposal == null ||
        proposal.runId != review.runId ||
        proposal.requiresQuarantine ||
        proposal.classification == StockImageClassification.unknown) {
      throw const AiPolicyViolation(
        code: 'proposal_not_approvable',
        safeMessage: 'This stock proposal cannot be closed.',
      );
    }
    final candidateIds = proposal.candidates
        .map((candidate) => candidate.candidateId)
        .toSet();
    final confirmedIds = <String>{};
    for (final item in review.items) {
      if (!candidateIds.contains(item.proposalCandidateId) ||
          !confirmedIds.add(item.proposalCandidateId) ||
          item.resolution.kind == CatalogResolutionKind.unresolved ||
          item.quantity < 0 ||
          !item.quantity.isFinite) {
        throw const AiPolicyViolation(
          code: 'invalid_stock_review',
          safeMessage:
              'Resolve each confirmed item and enter a valid quantity.',
        );
      }
    }
    await _proposals.markStockCountApproved(
      homeId: review.homeId,
      proposalId: review.proposalId,
    );
    final outcome = await _commits.closeApprovedCount(
      count: review,
      idempotencyKey: idempotencyKey,
    );
    await _proposals.saveCountCommitOutcome(
      homeId: review.homeId,
      idempotencyKey: idempotencyKey,
      outcome: outcome,
    );
    return outcome;
  }
}

AiGatewayRoute _routeFor(AiTransport transport) => switch (transport) {
  AiTransport.serverProxy => AiGatewayRoute.serverProxyCloud,
  AiTransport.directNative => AiGatewayRoute.directStrictLocal,
};

AiGatewayRoute _routeForMode(AiPrivacyMode mode) => switch (mode) {
  AiPrivacyMode.serverProxyCloud => AiGatewayRoute.serverProxyCloud,
  AiPrivacyMode.strictLocal => AiGatewayRoute.directStrictLocal,
  AiPrivacyMode.directCloudAdvanced => throw const AiPolicyViolation(
    code: 'direct_cloud_disabled',
    safeMessage:
        'Direct cloud credentials are disabled. Use the secure server connection.',
  ),
};

void _requireIdempotencyKey(String value) {
  if (value.trim().length < 12 || value.length > 200) {
    throw const AiPolicyViolation(
      code: 'invalid_idempotency_key',
      safeMessage: 'A stable approval reference is required.',
    );
  }
}
