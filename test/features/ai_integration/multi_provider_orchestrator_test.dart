import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/multi_provider_orchestrator.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/media_intake.dart';
import 'package:providentia/features/ai_integration/domain/media_transmission.dart';
import 'package:providentia/features/ai_integration/domain/multi_provider_consensus.dart';

void main() {
  group('deterministic field consensus', () {
    test('normalizes text and accepts numeric values within tolerance', () {
      const engine = DeterministicAiConsensusEngine();
      final primary = _snapshot(
        providerId: 'primary',
        fields: <ComparableAiField>[
          ComparableAiField.text(
            path: 'header.store',
            value: '  Providentia   Market ',
            confidence: 0.95,
          ),
          ComparableAiField.number(
            path: 'header.total',
            value: 20,
            confidence: 0.95,
            tolerance: 0.01,
            importance: AiFieldImportance.critical,
          ),
        ],
      );
      final validator = _snapshot(
        providerId: 'validator',
        fields: <ComparableAiField>[
          ComparableAiField.number(
            path: 'header.total',
            value: 20.005,
            confidence: 0.90,
            tolerance: 0.01,
            importance: AiFieldImportance.critical,
          ),
          ComparableAiField.text(
            path: 'header.store',
            value: 'providentia market',
            confidence: 0.90,
          ),
        ],
      );

      final report = engine.compare<_Proposal>(
        primary: primary,
        validator: validator,
      );

      expect(report.status, AiConsensusStatus.unanimous);
      expect(report.highestSeverity, AiDisagreementSeverity.none);
      expect(report.comparisons.map((comparison) => comparison.path), <String>[
        'header.store',
        'header.total',
      ]);
      expect(
        report.comparisons.every((comparison) => comparison.agreed),
        isTrue,
      );
    });

    test('marks a missing or different critical value as critical', () {
      const engine = DeterministicAiConsensusEngine();
      final report = engine.compare<_Proposal>(
        primary: _snapshot(
          providerId: 'primary',
          fields: <ComparableAiField>[
            ComparableAiField.number(
              path: 'header.total',
              value: 20,
              confidence: 0.98,
              importance: AiFieldImportance.critical,
            ),
            ComparableAiField.text(
              path: 'header.currency',
              value: 'NAD',
              confidence: 0.99,
              importance: AiFieldImportance.critical,
            ),
          ],
        ),
        validator: _snapshot(
          providerId: 'validator',
          fields: <ComparableAiField>[
            ComparableAiField.number(
              path: 'header.total',
              value: 200,
              confidence: 0.95,
              importance: AiFieldImportance.critical,
            ),
          ],
        ),
      );

      expect(report.status, AiConsensusStatus.disputed);
      expect(report.highestSeverity, AiDisagreementSeverity.critical);
      expect(report.hasMaterialDisagreement, isTrue);
      expect(
        report.comparisons
            .singleWhere((item) => item.path == 'header.currency')
            .reasonCode,
        'field_missing_from_one_provider',
      );
    });
  });

  group('primary and independent validator orchestration', () {
    test('returns mandatory review when no validator is configured', () async {
      final primary = _provider('primary');
      final request = _request(primary: primary);
      final port = _FakeExecutionPort((invocation) async {
        return AiProviderAttemptSuccess<_Proposal>(
          _snapshot(providerId: invocation.provider.id),
        );
      });

      final result =
          await ExtractAndValidateAiProposal<_Proposal>(
            executions: port,
          ).execute(
            primaryProvider: primary,
            manifest: request.manifest,
            consent: request.consent,
          );

      final review = result as AiReviewRequired<_Proposal>;
      expect(review.validationState, AiValidationState.notConfigured);
      expect(review.humanReviewRequired, isTrue);
      expect(review.automaticCommitAllowed, isFalse);
      expect(
        port.invocations.single.role,
        AiProviderExecutionRole.primaryExtractor,
      );
    });

    test(
      'compares independent results and still requires human review',
      () async {
        final primary = _provider('primary');
        final validator = _provider('validator');
        final request = _request(primary: primary, validator: validator);
        final port = _FakeExecutionPort((invocation) async {
          return AiProviderAttemptSuccess<_Proposal>(
            _snapshot(
              providerId: invocation.provider.id,
              cost: invocation.role == AiProviderExecutionRole.primaryExtractor
                  ? 10
                  : 5,
            ),
          );
        });

        final result =
            await ExtractAndValidateAiProposal<_Proposal>(
              executions: port,
            ).execute(
              primaryProvider: primary,
              validatorProvider: validator,
              manifest: request.manifest,
              consent: request.consent,
            );

        final review = result as AiReviewRequired<_Proposal>;
        expect(review.validationState, AiValidationState.agreed);
        expect(review.consensus?.status, AiConsensusStatus.unanimous);
        expect(review.totalEstimatedCostMinorUnits, 15);
        expect(review.humanReviewRequired, isTrue);
        expect(review.automaticCommitAllowed, isFalse);
        expect(port.invocations.length, 2);
        expect(
          port.invocations.last.primaryProposal,
          same(review.primary.proposal),
        );
      },
    );

    test('surfaces critical provider disagreement', () async {
      final primary = _provider('primary');
      final validator = _provider('validator');
      final request = _request(primary: primary, validator: validator);
      final port = _FakeExecutionPort((invocation) async {
        final value =
            invocation.role == AiProviderExecutionRole.primaryExtractor
            ? 20.0
            : 200.0;
        return AiProviderAttemptSuccess<_Proposal>(
          _snapshot(
            providerId: invocation.provider.id,
            fields: <ComparableAiField>[
              ComparableAiField.number(
                path: 'header.total',
                value: value,
                confidence: 0.98,
                importance: AiFieldImportance.critical,
              ),
            ],
          ),
        );
      });

      final result =
          await ExtractAndValidateAiProposal<_Proposal>(
            executions: port,
          ).execute(
            primaryProvider: primary,
            validatorProvider: validator,
            manifest: request.manifest,
            consent: request.consent,
          );

      final review = result as AiReviewRequired<_Proposal>;
      expect(review.validationState, AiValidationState.disagreed);
      expect(
        review.consensus?.highestSeverity,
        AiDisagreementSeverity.critical,
      );
      expect(review.warnings.single, contains('materially disagree'));
    });

    test('keeps the primary proposal when validation times out', () async {
      final primary = _provider('primary');
      final validator = _provider('validator');
      final request = _request(primary: primary, validator: validator);
      final never = Completer<AiProviderAttempt<_Proposal>>();
      final port = _FakeExecutionPort((invocation) {
        if (invocation.role == AiProviderExecutionRole.independentValidator) {
          return never.future;
        }
        return Future<AiProviderAttempt<_Proposal>>.value(
          AiProviderAttemptSuccess<_Proposal>(
            _snapshot(providerId: invocation.provider.id),
          ),
        );
      });

      final result =
          await ExtractAndValidateAiProposal<_Proposal>(
            executions: port,
          ).execute(
            primaryProvider: primary,
            validatorProvider: validator,
            manifest: request.manifest,
            consent: request.consent,
            budget: const AiOrchestrationBudget(
              totalTimeout: Duration(milliseconds: 100),
              primaryTimeout: Duration(milliseconds: 50),
              validatorTimeout: Duration(milliseconds: 5),
            ),
          );

      final review = result as AiReviewRequired<_Proposal>;
      expect(review.validationState, AiValidationState.timedOut);
      expect(review.primary.providerId, 'primary');
      expect(review.validator, isNull);
      expect(review.humanReviewRequired, isTrue);
    });

    test('fails closed when the primary exceeds its cost ceiling', () async {
      final primary = _provider('primary');
      final request = _request(primary: primary);
      final port = _FakeExecutionPort((invocation) async {
        return AiProviderAttemptSuccess<_Proposal>(
          _snapshot(providerId: invocation.provider.id, cost: 11),
        );
      });

      final result =
          await ExtractAndValidateAiProposal<_Proposal>(
            executions: port,
          ).execute(
            primaryProvider: primary,
            manifest: request.manifest,
            consent: request.consent,
            budget: const AiOrchestrationBudget(
              maxTotalCostMinorUnits: 20,
              maxPrimaryCostMinorUnits: 10,
              maxValidatorCostMinorUnits: 10,
            ),
          );

      final failure = result as AiPrimaryExtractionFailed<_Proposal>;
      expect(failure.code, 'primary_cost_budget_exceeded');
      expect(failure.automaticCommitAllowed, isFalse);
    });

    test(
      'does not trust validator output that exceeds the remaining budget',
      () async {
        final primary = _provider('primary');
        final validator = _provider('validator');
        final request = _request(primary: primary, validator: validator);
        final port = _FakeExecutionPort((invocation) async {
          return AiProviderAttemptSuccess<_Proposal>(
            _snapshot(
              providerId: invocation.provider.id,
              cost: invocation.role == AiProviderExecutionRole.primaryExtractor
                  ? 8
                  : 5,
            ),
          );
        });

        final result =
            await ExtractAndValidateAiProposal<_Proposal>(
              executions: port,
            ).execute(
              primaryProvider: primary,
              validatorProvider: validator,
              manifest: request.manifest,
              consent: request.consent,
              budget: const AiOrchestrationBudget(
                maxTotalCostMinorUnits: 12,
                maxPrimaryCostMinorUnits: 10,
                maxValidatorCostMinorUnits: 10,
              ),
            );

        final review = result as AiReviewRequired<_Proposal>;
        expect(review.validationState, AiValidationState.costLimitExceeded);
        expect(review.validator, isNull);
        expect(review.consensus, isNull);
      },
    );
  });
}

final class _Proposal {
  const _Proposal(this.id);

  final String id;
}

AiProposalSnapshot<_Proposal> _snapshot({
  required String providerId,
  List<ComparableAiField>? fields,
  int cost = 1,
}) => AiProposalSnapshot<_Proposal>(
  providerId: providerId,
  providerRevision: 1,
  proposal: _Proposal('proposal-$providerId'),
  fields:
      fields ??
      <ComparableAiField>[
        ComparableAiField.text(
          path: 'header.store',
          value: 'Providentia Market',
          confidence: 0.95,
        ),
      ],
  estimatedCostMinorUnits: cost,
  processingTime: const Duration(milliseconds: 10),
);

AiProviderProfile _provider(String id) => AiProviderProfile(
  id: id,
  homeId: 'home-1',
  displayName: id,
  kind: AiProviderKind.openAi,
  transport: AiTransport.serverProxy,
  protocol: AiEndpointProtocol.openAiResponses,
  model: 'vision-model',
  capabilities: <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
  },
  availability: AiProviderAvailability.available,
  credentialConfigured: true,
);

({AiTransmissionManifest manifest, AiTransmissionConsent consent}) _request({
  required AiProviderProfile primary,
  AiProviderProfile? validator,
}) {
  final source = AcquiredMediaSource(
    id: 'source-1',
    homeId: 'home-1',
    purpose: AiExtractionKind.receipt,
    kind: MediaSourceKind.cameraImage,
    localReference: 'local://receipt.jpg',
    mimeType: 'image/jpeg',
    byteLength: 1000,
    acquiredAt: DateTime.utc(2026, 8, 4),
    width: 1200,
    height: 1600,
  );
  final batch = const BoundedMediaPlanner().create(
    batchId: 'batch-1',
    homeId: 'home-1',
    purpose: AiExtractionKind.receipt,
    sources: <AcquiredMediaSource>[source],
    media: <PreparedMediaUnit>[
      PreparedMediaUnit(
        id: 'media-1',
        sourceId: 'source-1',
        kind: PreparedMediaKind.image,
        orderIndex: 0,
        ephemeralReference: 'ephemeral://media-1',
        previewReference: 'preview://media-1',
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        mimeType: 'image/jpeg',
        byteLength: 500,
        width: 1200,
        height: 1600,
        metadataStripped: true,
        orientationNormalized: true,
      ),
    ],
    preparedAt: DateTime.utc(2026, 8, 4, 10),
  );
  final manifest = AiTransmissionManifest.create(
    id: 'manifest-1',
    batch: batch,
    privacyMode: AiPrivacyMode.serverProxyCloud,
    primaryProvider: primary,
    validatorProvider: validator,
    disclosureVersion: 'privacy-v2',
    createdAt: DateTime.utc(2026, 8, 4, 10),
  );
  return (
    manifest: manifest,
    consent: AiTransmissionConsent(
      manifestId: manifest.id,
      canonicalBinding: manifest.canonicalConsentBinding,
      disclosureVersion: manifest.disclosureVersion,
      confirmedBy: 'user-1',
      confirmedAt: DateTime.utc(2026, 8, 4, 10, 1),
      explicitlyConfirmed: true,
    ),
  );
}

final class _FakeExecutionPort implements AiProposalExecutionPort<_Proposal> {
  _FakeExecutionPort(this.handler);

  final Future<AiProviderAttempt<_Proposal>> Function(
    AiProviderInvocation<_Proposal> invocation,
  )
  handler;
  final List<AiProviderInvocation<_Proposal>> invocations =
      <AiProviderInvocation<_Proposal>>[];

  @override
  Future<AiProviderAttempt<_Proposal>> execute(
    AiProviderInvocation<_Proposal> invocation,
  ) {
    invocations.add(invocation);
    return handler(invocation);
  }
}
