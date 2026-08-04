import 'dart:async';
import 'dart:collection';

import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/media_transmission.dart';
import 'package:providentia/features/ai_integration/domain/multi_provider_consensus.dart';

enum AiProviderExecutionRole { primaryExtractor, independentValidator }

enum AiValidationState {
  notConfigured,
  agreed,
  disagreed,
  failed,
  timedOut,
  costLimitExceeded,
}

final class AiOrchestrationBudget {
  const AiOrchestrationBudget({
    this.totalTimeout = const Duration(seconds: 75),
    this.primaryTimeout = const Duration(seconds: 45),
    this.validatorTimeout = const Duration(seconds: 30),
    this.maxTotalCostMinorUnits = 100,
    this.maxPrimaryCostMinorUnits = 70,
    this.maxValidatorCostMinorUnits = 30,
  });

  final Duration totalTimeout;
  final Duration primaryTimeout;
  final Duration validatorTimeout;
  final int maxTotalCostMinorUnits;
  final int maxPrimaryCostMinorUnits;
  final int maxValidatorCostMinorUnits;

  void validate() {
    if (totalTimeout <= Duration.zero ||
        primaryTimeout <= Duration.zero ||
        validatorTimeout <= Duration.zero ||
        maxTotalCostMinorUnits <= 0 ||
        maxPrimaryCostMinorUnits <= 0 ||
        maxValidatorCostMinorUnits <= 0) {
      throw const AiOrchestrationViolation(
        code: 'invalid_orchestration_budget',
        safeMessage: 'The AI timeout or cost budget is invalid.',
      );
    }
  }
}

final class AiProviderInvocation<T> {
  const AiProviderInvocation({
    required this.role,
    required this.provider,
    required this.manifest,
    required this.providerConsent,
    required this.timeout,
    required this.maximumCostMinorUnits,
    this.primaryProposal,
  });

  final AiProviderExecutionRole role;
  final AiProviderProfile provider;
  final AiTransmissionManifest manifest;
  final AiConsent providerConsent;
  final Duration timeout;
  final int maximumCostMinorUnits;
  final T? primaryProposal;
}

abstract interface class AiProposalExecutionPort<T> {
  Future<AiProviderAttempt<T>> execute(AiProviderInvocation<T> invocation);
}

sealed class AiProviderAttempt<T> {
  const AiProviderAttempt();
}

final class AiProviderAttemptSuccess<T> extends AiProviderAttempt<T> {
  const AiProviderAttemptSuccess(this.snapshot);

  final AiProposalSnapshot<T> snapshot;
}

final class AiProviderAttemptFailure<T> extends AiProviderAttempt<T> {
  const AiProviderAttemptFailure({
    required this.code,
    required this.safeMessage,
    required this.retryable,
  });

  final String code;
  final String safeMessage;
  final bool retryable;
}

sealed class AiOrchestrationOutcome<T> {
  const AiOrchestrationOutcome();
}

final class AiReviewRequired<T> extends AiOrchestrationOutcome<T> {
  AiReviewRequired({
    required this.primary,
    required this.validator,
    required this.validationState,
    required this.consensus,
    required this.totalEstimatedCostMinorUnits,
    required List<String> warnings,
  }) : warnings = UnmodifiableListView<String>(warnings);

  final AiProposalSnapshot<T> primary;
  final AiProposalSnapshot<T>? validator;
  final AiValidationState validationState;
  final AiConsensusReport? consensus;
  final int totalEstimatedCostMinorUnits;
  final List<String> warnings;

  bool get humanReviewRequired => true;

  bool get automaticCommitAllowed => false;
}

final class AiPrimaryExtractionFailed<T> extends AiOrchestrationOutcome<T> {
  const AiPrimaryExtractionFailed({
    required this.code,
    required this.safeMessage,
    required this.retryable,
  });

  final String code;
  final String safeMessage;
  final bool retryable;

  bool get automaticCommitAllowed => false;
}

final class AiOrchestrationViolation implements Exception {
  const AiOrchestrationViolation({
    required this.code,
    required this.safeMessage,
  });

  final String code;
  final String safeMessage;

  @override
  String toString() => 'AiOrchestrationViolation($code): $safeMessage';
}

final class ExtractAndValidateAiProposal<T> {
  factory ExtractAndValidateAiProposal({
    required AiProposalExecutionPort<T> executions,
    DeterministicAiConsensusEngine consensusEngine =
        const DeterministicAiConsensusEngine(),
  }) => ExtractAndValidateAiProposal._(executions, consensusEngine);

  const ExtractAndValidateAiProposal._(this._executions, this.consensusEngine);

  final AiProposalExecutionPort<T> _executions;
  final DeterministicAiConsensusEngine consensusEngine;

  Future<AiOrchestrationOutcome<T>> execute({
    required AiProviderProfile primaryProvider,
    AiProviderProfile? validatorProvider,
    required AiTransmissionManifest manifest,
    required AiTransmissionConsent consent,
    AiOrchestrationBudget budget = const AiOrchestrationBudget(),
  }) async {
    budget.validate();
    manifest.authorize(consent);
    _validateProviderBindings(
      manifest: manifest,
      primaryProvider: primaryProvider,
      validatorProvider: validatorProvider,
    );
    final timer = Stopwatch()..start();
    final primaryTimeout = _effectiveTimeout(
      budget.primaryTimeout,
      budget.totalTimeout,
      timer.elapsed,
    );
    final primaryAttempt = await _invoke(
      AiProviderInvocation<T>(
        role: AiProviderExecutionRole.primaryExtractor,
        provider: primaryProvider,
        manifest: manifest,
        providerConsent: manifest.consentForProvider(
          provider: primaryProvider,
          consent: consent,
        ),
        timeout: primaryTimeout,
        maximumCostMinorUnits: budget.maxPrimaryCostMinorUnits,
      ),
    );
    if (primaryAttempt case final AiProviderAttemptFailure<T> failure) {
      timer.stop();
      return AiPrimaryExtractionFailed<T>(
        code: failure.code,
        safeMessage: failure.safeMessage,
        retryable: failure.retryable,
      );
    }
    final primary = (primaryAttempt as AiProviderAttemptSuccess<T>).snapshot;
    _validateSnapshot(primary, primaryProvider);
    if (primary.estimatedCostMinorUnits > budget.maxPrimaryCostMinorUnits ||
        primary.estimatedCostMinorUnits > budget.maxTotalCostMinorUnits) {
      timer.stop();
      return AiPrimaryExtractionFailed<T>(
        code: 'primary_cost_budget_exceeded',
        safeMessage:
            'The primary extraction exceeded the configured cost limit.',
        retryable: false,
      );
    }

    if (validatorProvider == null) {
      timer.stop();
      return AiReviewRequired<T>(
        primary: primary,
        validator: null,
        validationState: AiValidationState.notConfigured,
        consensus: null,
        totalEstimatedCostMinorUnits: primary.estimatedCostMinorUnits,
        warnings: const <String>[
          'No independent validator was configured. Human review is required.',
        ],
      );
    }

    final remainingCost =
        budget.maxTotalCostMinorUnits - primary.estimatedCostMinorUnits;
    final validatorCostLimit = remainingCost < budget.maxValidatorCostMinorUnits
        ? remainingCost
        : budget.maxValidatorCostMinorUnits;
    if (validatorCostLimit <= 0) {
      timer.stop();
      return AiReviewRequired<T>(
        primary: primary,
        validator: null,
        validationState: AiValidationState.costLimitExceeded,
        consensus: null,
        totalEstimatedCostMinorUnits: primary.estimatedCostMinorUnits,
        warnings: const <String>[
          'The validator was not called because the total cost budget was exhausted.',
        ],
      );
    }

    final validatorTimeout = _effectiveTimeout(
      budget.validatorTimeout,
      budget.totalTimeout,
      timer.elapsed,
    );
    if (validatorTimeout <= Duration.zero) {
      timer.stop();
      return AiReviewRequired<T>(
        primary: primary,
        validator: null,
        validationState: AiValidationState.timedOut,
        consensus: null,
        totalEstimatedCostMinorUnits: primary.estimatedCostMinorUnits,
        warnings: const <String>[
          'The total timeout budget expired before independent validation.',
        ],
      );
    }
    final validatorAttempt = await _invoke(
      AiProviderInvocation<T>(
        role: AiProviderExecutionRole.independentValidator,
        provider: validatorProvider,
        manifest: manifest,
        providerConsent: manifest.consentForProvider(
          provider: validatorProvider,
          consent: consent,
        ),
        timeout: validatorTimeout,
        maximumCostMinorUnits: validatorCostLimit,
        primaryProposal: primary.proposal,
      ),
    );
    timer.stop();
    if (validatorAttempt case final AiProviderAttemptFailure<T> failure) {
      final timedOut = failure.code == 'provider_timeout';
      return AiReviewRequired<T>(
        primary: primary,
        validator: null,
        validationState: timedOut
            ? AiValidationState.timedOut
            : AiValidationState.failed,
        consensus: null,
        totalEstimatedCostMinorUnits: primary.estimatedCostMinorUnits,
        warnings: <String>[
          timedOut
              ? 'Independent validation timed out. Review every extracted field.'
              : 'Independent validation failed. Review every extracted field.',
        ],
      );
    }

    final validator =
        (validatorAttempt as AiProviderAttemptSuccess<T>).snapshot;
    _validateSnapshot(validator, validatorProvider);
    final totalCost =
        primary.estimatedCostMinorUnits + validator.estimatedCostMinorUnits;
    if (validator.estimatedCostMinorUnits > validatorCostLimit ||
        totalCost > budget.maxTotalCostMinorUnits) {
      return AiReviewRequired<T>(
        primary: primary,
        validator: null,
        validationState: AiValidationState.costLimitExceeded,
        consensus: null,
        totalEstimatedCostMinorUnits: totalCost,
        warnings: const <String>[
          'The validator exceeded the configured cost limit, so its result was not trusted.',
        ],
      );
    }
    final consensus = consensusEngine.compare<T>(
      primary: primary,
      validator: validator,
    );
    return AiReviewRequired<T>(
      primary: primary,
      validator: validator,
      validationState: consensus.hasMaterialDisagreement
          ? AiValidationState.disagreed
          : AiValidationState.agreed,
      consensus: consensus,
      totalEstimatedCostMinorUnits: totalCost,
      warnings: consensus.hasMaterialDisagreement
          ? const <String>[
              'The providers materially disagree. Resolve every disputed field.',
            ]
          : const <String>['Provider agreement does not replace human review.'],
    );
  }

  Future<AiProviderAttempt<T>> _invoke(
    AiProviderInvocation<T> invocation,
  ) async {
    try {
      return await _executions.execute(invocation).timeout(invocation.timeout);
    } on TimeoutException {
      return AiProviderAttemptFailure<T>(
        code: 'provider_timeout',
        safeMessage: 'The AI provider did not respond within the time limit.',
        retryable: true,
      );
    } on Object {
      return AiProviderAttemptFailure<T>(
        code: 'provider_failure',
        safeMessage: 'The AI provider could not complete the request safely.',
        retryable: true,
      );
    }
  }

  void _validateProviderBindings({
    required AiTransmissionManifest manifest,
    required AiProviderProfile primaryProvider,
    required AiProviderProfile? validatorProvider,
  }) {
    final primaryBindings = manifest.providers.where(
      (binding) =>
          binding.role == TransmissionProviderRole.primaryExtractor &&
          binding.providerId == primaryProvider.id &&
          binding.providerRevision == primaryProvider.revision,
    );
    final validatorBindings = manifest.providers.where(
      (binding) =>
          binding.role == TransmissionProviderRole.independentValidator,
    );
    final validatorMatches = validatorProvider == null
        ? validatorBindings.isEmpty
        : validatorBindings.length == 1 &&
              validatorBindings.single.providerId == validatorProvider.id &&
              validatorBindings.single.providerRevision ==
                  validatorProvider.revision;
    if (primaryBindings.length != 1 ||
        !validatorMatches ||
        primaryProvider.homeId != manifest.batch.homeId ||
        (validatorProvider != null &&
            validatorProvider.homeId != manifest.batch.homeId)) {
      throw const AiOrchestrationViolation(
        code: 'provider_manifest_mismatch',
        safeMessage:
            'The selected providers do not match the confirmed request.',
      );
    }
  }

  void _validateSnapshot(
    AiProposalSnapshot<T> snapshot,
    AiProviderProfile provider,
  ) {
    if (snapshot.providerId != provider.id ||
        snapshot.providerRevision != provider.revision) {
      throw const AiOrchestrationViolation(
        code: 'provider_snapshot_mismatch',
        safeMessage: 'The provider result could not be verified.',
      );
    }
  }
}

Duration _effectiveTimeout(
  Duration phaseLimit,
  Duration totalLimit,
  Duration elapsed,
) {
  final remaining = totalLimit - elapsed;
  if (remaining <= Duration.zero) {
    return Duration.zero;
  }
  return phaseLimit < remaining ? phaseLimit : remaining;
}
