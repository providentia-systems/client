import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/ai_use_cases.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';
import 'package:providentia/features/ai_integration/domain/proposal_validation.dart';
import 'package:providentia/features/ai_integration/presentation/ai_controllers.dart';

import 'test_fixtures.dart';

void main() {
  group('provider configuration', () {
    test('provisions and deletes a server-proxy credential', () async {
      final providers = FakeProviderRepository();
      final credentials = FakeServerCredentials();
      final gateway = FakeGateway(route: AiGatewayRoute.serverProxyCloud);
      final useCase = ConfigureAiProvider(
        policy: const AiPrivacyPolicy(),
        providers: providers,
        gateways: FakeGatewayResolver(<AiGatewayRoute, AiProviderGateway>{
          AiGatewayRoute.serverProxyCloud: gateway,
        }),
        serverCredentials: credentials,
        credentialVault: FakeCredentialVault(),
      );
      final profile = serverProvider().copyWith(credentialConfigured: false);

      final configured = await useCase.execute(
        profile: profile,
        replacementSecret: '  cloud-secret  ',
      );

      expect(configured.credentialConfigured, isTrue);
      expect(credentials.replacements, 1);
      expect(providers.values[profile.id], same(configured));

      await useCase.delete(configured);

      expect(credentials.deletions, 1);
      expect(providers.values, isEmpty);
    });

    test('uses the native vault only for a direct local provider', () async {
      final providers = FakeProviderRepository();
      final vault = FakeCredentialVault();
      final gateway = FakeGateway(route: AiGatewayRoute.directStrictLocal);
      final useCase = ConfigureAiProvider(
        policy: const AiPrivacyPolicy(),
        providers: providers,
        gateways: FakeGatewayResolver(<AiGatewayRoute, AiProviderGateway>{
          AiGatewayRoute.directStrictLocal: gateway,
        }),
        serverCredentials: FakeServerCredentials(),
        credentialVault: vault,
      );

      final configured = await useCase.execute(
        profile: localProvider(),
        replacementSecret: ' local-token ',
      );

      expect(vault.values[configured.id], 'local-token');
      expect(configured.credentialConfigured, isTrue);

      await useCase.delete(configured);

      expect(vault.values, isEmpty);
      expect(providers.values, isEmpty);
    });

    test('fails closed when native secret storage is unavailable', () async {
      final useCase = ConfigureAiProvider(
        policy: const AiPrivacyPolicy(),
        providers: FakeProviderRepository(),
        gateways: FakeGatewayResolver(
          const <AiGatewayRoute, AiProviderGateway>{},
        ),
        serverCredentials: FakeServerCredentials(),
        credentialVault: FakeCredentialVault(supportsNativeSecrets: false),
      );

      await expectLater(
        useCase.execute(
          profile: localProvider(),
          replacementSecret: 'local-token',
        ),
        throwsA(
          isA<AiPolicyViolation>().having(
            (error) => error.code,
            'code',
            'native_vault_unavailable',
          ),
        ),
      );
    });

    test('does not persist a provider missing a required capability', () async {
      final providers = FakeProviderRepository();
      final gateway = FakeGateway(
        route: AiGatewayRoute.serverProxyCloud,
        gatewayReadiness: const AiGatewayReadiness(
          state: AiGatewayReadinessState.missingCapability,
          safeMessage: 'Vision schema support is unavailable.',
        ),
      );
      final useCase = ConfigureAiProvider(
        policy: const AiPrivacyPolicy(),
        providers: providers,
        gateways: FakeGatewayResolver(<AiGatewayRoute, AiProviderGateway>{
          AiGatewayRoute.serverProxyCloud: gateway,
        }),
        serverCredentials: FakeServerCredentials(),
        credentialVault: FakeCredentialVault(),
      );

      await expectLater(
        useCase.execute(profile: serverProvider()),
        throwsA(
          isA<AiPolicyViolation>()
              .having(
                (error) => error.code,
                'code',
                'required_capability_missing',
              )
              .having(
                (error) => error.safeMessage,
                'safeMessage',
                'Vision schema support is unavailable.',
              ),
        ),
      );
      expect(providers.values, isEmpty);
    });
  });

  group('media preparation', () {
    test('delegates only correctly scoped media', () async {
      final prepared = preparedBatch();
      final port = FakeMediaPreparation(prepared);
      final useCase = PrepareAiMedia(port);
      final asset = _mediaAsset();

      final result = await useCase.execute(
        homeId: 'home-1',
        purpose: AiExtractionKind.receipt,
        assets: <AiMediaAsset>[asset],
      );

      expect(result, same(prepared));
    });

    test('rejects empty and cross-home media before invoking the port', () {
      final useCase = PrepareAiMedia(FakeMediaPreparation(preparedBatch()));

      expect(
        () => useCase.execute(
          homeId: ' ',
          purpose: AiExtractionKind.receipt,
          assets: const <AiMediaAsset>[],
        ),
        throwsA(
          isA<AiPolicyViolation>().having(
            (error) => error.code,
            'code',
            'media_required',
          ),
        ),
      );
      expect(
        () => useCase.execute(
          homeId: 'home-2',
          purpose: AiExtractionKind.receipt,
          assets: <AiMediaAsset>[_mediaAsset()],
        ),
        throwsA(
          isA<AiPolicyViolation>().having(
            (error) => error.code,
            'code',
            'media_scope_mismatch',
          ),
        ),
      );
    });
  });

  group('receipt extraction outcomes', () {
    test('persists a valid proposal for human review', () async {
      final harness = _receiptHarness(
        (request) async => AiExtractionSuccess<ReceiptProposal>(
          proposal: receiptProposal(runId: request.runId),
          metadata: runMetadata,
        ),
      );

      final result = await _extractReceipt(harness);

      expect(result, isA<AiExtractionSuccess<ReceiptProposal>>());
      expect(harness.proposals.receipts, hasLength(1));
      expect(harness.runs.values['run-1']?.state, AiRunState.reviewRequired);
      expect(harness.runs.values['run-1']?.metadata, runMetadata);
      expect(harness.media.discardCalls, 1);
    });

    for (final scenario
        in <({String code, AiExtractionResult<ReceiptProposal> result})>[
          (
            code: 'provider_refused',
            result: const AiExtractionRefused<ReceiptProposal>(
              safeReason: 'The provider declined this image.',
            ),
          ),
          (
            code: 'provider_incomplete',
            result: const AiExtractionIncomplete<ReceiptProposal>(
              safeReason: 'The response ended before completion.',
            ),
          ),
          (
            code: 'rate_limited',
            result: const AiExtractionFailure<ReceiptProposal>(
              code: 'rate_limited',
              safeMessage: 'Try again later.',
            ),
          ),
        ]) {
      test('records ${scenario.code} without saving a proposal', () async {
        final harness = _receiptHarness((request) async => scenario.result);

        final result = await _extractReceipt(harness);

        expect(result, same(scenario.result));
        expect(harness.proposals.receipts, isEmpty);
        expect(harness.runs.values['run-1']?.state, AiRunState.failed);
        expect(harness.runs.values['run-1']?.safeFailureCode, scenario.code);
        expect(harness.media.discardCalls, 1);
      });
    }

    test(
      'records a validation failure before rejecting a mismatched proposal',
      () async {
        final harness = _receiptHarness(
          (request) async => AiExtractionSuccess<ReceiptProposal>(
            proposal: receiptProposal(runId: 'different-run'),
            metadata: runMetadata,
          ),
        );

        await expectLater(
          _extractReceipt(harness),
          throwsA(isA<ProposalValidationException>()),
        );

        expect(harness.proposals.receipts, isEmpty);
        expect(harness.runs.values['run-1']?.state, AiRunState.failed);
        expect(
          harness.runs.values['run-1']?.safeFailureCode,
          'invalid_structured_output',
        );
        expect(harness.media.discardCalls, 1);
      },
    );
  });

  group('stock-photo extraction outcomes', () {
    test('persists a pantry proposal and records review state', () async {
      final harness = _stockHarness(
        (request) async => AiExtractionSuccess<StockPhotoProposal>(
          proposal: stockProposal(runId: request.runId),
          metadata: _stockMetadata,
        ),
      );

      final result = await _extractStock(harness);

      expect(result, isA<AiExtractionSuccess<StockPhotoProposal>>());
      expect(harness.proposals.stocks, hasLength(1));
      expect(harness.runs.values['run-1']?.state, AiRunState.reviewRequired);
      expect(harness.media.discardCalls, 1);
    });

    test(
      'quarantines unrelated output without persisting candidates',
      () async {
        final harness = _stockHarness(
          (request) async => AiExtractionSuccess<StockPhotoProposal>(
            proposal: stockProposal(
              runId: request.runId,
              classification: StockImageClassification.unrelated,
              candidates: <StockCandidateProposal>[],
            ),
            metadata: _stockMetadata,
          ),
        );

        final result = await _extractStock(harness);

        expect(result, isA<AiExtractionQuarantined<StockPhotoProposal>>());
        expect(harness.proposals.stocks, isEmpty);
        expect(harness.runs.values['run-1']?.state, AiRunState.quarantined);
      },
    );

    for (final scenario
        in <
          ({
            String code,
            AiRunState state,
            AiExtractionResult<StockPhotoProposal> result,
          })
        >[
          (
            code: 'provider_refused',
            state: AiRunState.failed,
            result: const AiExtractionRefused<StockPhotoProposal>(
              safeReason: 'Declined.',
            ),
          ),
          (
            code: 'provider_incomplete',
            state: AiRunState.failed,
            result: const AiExtractionIncomplete<StockPhotoProposal>(
              safeReason: 'Incomplete.',
            ),
          ),
          (
            code: 'timeout',
            state: AiRunState.failed,
            result: const AiExtractionFailure<StockPhotoProposal>(
              code: 'timeout',
              safeMessage: 'Timed out.',
            ),
          ),
          (
            code: 'quarantined',
            state: AiRunState.quarantined,
            result: const AiExtractionQuarantined<StockPhotoProposal>(
              classification: 'medicine',
            ),
          ),
        ]) {
      test('records stock ${scenario.code} with the correct state', () async {
        final harness = _stockHarness((request) async => scenario.result);

        final result = await _extractStock(harness);

        expect(result, same(scenario.result));
        expect(harness.runs.values['run-1']?.state, scenario.state);
        expect(harness.runs.values['run-1']?.safeFailureCode, scenario.code);
        expect(harness.media.discardCalls, 1);
      });
    }

    test('marks a schema/run mismatch as invalid structured output', () async {
      final harness = _stockHarness(
        (request) async => AiExtractionSuccess<StockPhotoProposal>(
          proposal: stockProposal(runId: 'different-run'),
          metadata: _stockMetadata,
        ),
      );

      await expectLater(
        _extractStock(harness),
        throwsA(isA<ProposalValidationException>()),
      );

      expect(harness.proposals.stocks, isEmpty);
      expect(harness.runs.values['run-1']?.state, AiRunState.failed);
      expect(
        harness.runs.values['run-1']?.safeFailureCode,
        'invalid_structured_output',
      );
      expect(harness.media.discardCalls, 1);
    });
  });

  group('approval validation', () {
    test(
      'receipt approval rejects unstable keys and unresolved lines',
      () async {
        final proposals = FakeProposalRepository();
        final proposal = receiptProposal();
        proposals.receipts[proposal.id] = proposal;
        final commits = FakeReceiptCommit();
        final useCase = ApproveReceiptProposal(
          proposals: proposals,
          commits: commits,
        );
        final unresolved = _reviewedReceipt(
          proposal,
          resolution: const CatalogResolution(
            kind: CatalogResolutionKind.unresolved,
          ),
        );

        await expectLater(
          useCase.execute(review: unresolved, idempotencyKey: 'short'),
          throwsA(
            isA<AiPolicyViolation>().having(
              (error) => error.code,
              'code',
              'invalid_idempotency_key',
            ),
          ),
        );
        await expectLater(
          useCase.execute(
            review: unresolved,
            idempotencyKey: 'receipt-invalid-0001',
          ),
          throwsA(
            isA<AiPolicyViolation>().having(
              (error) => error.code,
              'code',
              'invalid_receipt_review',
            ),
          ),
        );
        expect(commits.calls, 0);
      },
    );

    test(
      'count close rejects unknown proposals and invalid quantities',
      () async {
        final proposals = FakeProposalRepository();
        final proposal = stockProposal();
        final commits = FakeStockCommit();
        final useCase = CloseStockPhotoCount(
          proposals: proposals,
          commits: commits,
        );
        final review = _reviewedStockCount(proposal, quantity: 2);

        await expectLater(
          useCase.execute(review: review, idempotencyKey: 'stock-invalid-0001'),
          throwsA(
            isA<AiPolicyViolation>().having(
              (error) => error.code,
              'code',
              'proposal_not_approvable',
            ),
          ),
        );

        proposals.stocks[proposal.id] = proposal;
        await expectLater(
          useCase.execute(
            review: _reviewedStockCount(proposal, quantity: double.nan),
            idempotencyKey: 'stock-invalid-0002',
          ),
          throwsA(
            isA<AiPolicyViolation>().having(
              (error) => error.code,
              'code',
              'invalid_stock_review',
            ),
          ),
        );
        expect(commits.calls, 0);
      },
    );
  });

  group('presentation controllers', () {
    test(
      'provider controller exposes success and safe policy failure',
      () async {
        final providers = FakeProviderRepository();
        final gateway = FakeGateway(route: AiGatewayRoute.serverProxyCloud);
        final controller = AiProviderConfigurationController(
          ConfigureAiProvider(
            policy: const AiPrivacyPolicy(),
            providers: providers,
            gateways: FakeGatewayResolver(<AiGatewayRoute, AiProviderGateway>{
              AiGatewayRoute.serverProxyCloud: gateway,
            }),
            serverCredentials: FakeServerCredentials(),
            credentialVault: FakeCredentialVault(),
          ),
        );
        addTearDown(controller.dispose);

        await controller.save(profile: serverProvider());
        expect(controller.savedProfile?.id, 'provider-1');
        expect(controller.safeError, isNull);
        expect(controller.isSaving, isFalse);

        await controller.save(
          profile: serverProvider(
            availability: AiProviderAvailability.missingBackendContract,
          ),
        );
        expect(
          controller.safeError,
          'The secure provider service is not available yet.',
        );
        expect(controller.isSaving, isFalse);
      },
    );

    test(
      'receipt extraction controller maps success and safe failures',
      () async {
        final successHarness = _receiptHarness(
          (request) async => AiExtractionSuccess<ReceiptProposal>(
            proposal: receiptProposal(runId: request.runId),
            metadata: runMetadata,
          ),
        );
        final successController = ReceiptExtractionController(
          successHarness.useCase,
        );
        addTearDown(successController.dispose);

        await _controllerExtractReceipt(successController);

        expect(
          successController.state,
          ExtractionControllerState.reviewRequired,
        );
        expect(successController.proposal?.id, 'receipt-proposal-1');
        expect(successController.safeMessage, isNull);

        final failureHarness = _receiptHarness(
          (request) async => const AiExtractionFailure<ReceiptProposal>(
            code: 'timeout',
            safeMessage: 'The provider timed out.',
          ),
        );
        final failureController = ReceiptExtractionController(
          failureHarness.useCase,
        );
        addTearDown(failureController.dispose);

        await _controllerExtractReceipt(failureController);

        expect(failureController.state, ExtractionControllerState.failed);
        expect(failureController.safeMessage, 'The provider timed out.');
      },
    );

    test('receipt controller quarantines medical output', () async {
      final harness = _receiptHarness(
        (request) async => AiExtractionSuccess<ReceiptProposal>(
          proposal: receiptProposal(
            runId: request.runId,
            classification: ReceiptDocumentClassification.medicineLeaflet,
            lines: <ReceiptLineProposal>[],
          ),
          metadata: runMetadata,
        ),
      );
      final controller = ReceiptExtractionController(harness.useCase);
      addTearDown(controller.dispose);

      await _controllerExtractReceipt(controller);

      expect(controller.state, ExtractionControllerState.quarantined);
      expect(controller.proposal, isNull);
      expect(controller.safeMessage, contains('quarantined'));
    });

    test('stock controller maps refusal and quarantine outcomes', () async {
      final refusedHarness = _stockHarness(
        (request) async => const AiExtractionRefused<StockPhotoProposal>(
          safeReason: 'The image was refused.',
        ),
      );
      final refusedController = StockPhotoExtractionController(
        refusedHarness.useCase,
      );
      addTearDown(refusedController.dispose);

      await _controllerExtractStock(refusedController);

      expect(refusedController.state, ExtractionControllerState.failed);
      expect(refusedController.safeMessage, 'The image was refused.');

      final quarantineHarness = _stockHarness(
        (request) async => const AiExtractionQuarantined<StockPhotoProposal>(
          classification: 'medicine',
        ),
      );
      final quarantineController = StockPhotoExtractionController(
        quarantineHarness.useCase,
      );
      addTearDown(quarantineController.dispose);

      await _controllerExtractStock(quarantineController);

      expect(quarantineController.state, ExtractionControllerState.quarantined);
      expect(quarantineController.proposal, isNull);
      expect(quarantineController.safeMessage, contains('quarantined'));
    });

    test(
      'catalog controller trims queries, clears, and reports failure',
      () async {
        final lookup = _CatalogLookup();
        final controller = CatalogCandidateController(lookup);
        addTearDown(controller.dispose);

        await controller.search(homeId: 'home-1', query: '  rice  ');
        expect(lookup.queries, <String>['rice']);
        expect(controller.candidates.single.productName, 'Rice');
        expect(controller.isSearching, isFalse);

        await controller.search(homeId: 'home-1', query: ' ');
        expect(controller.candidates, isEmpty);
        expect(lookup.queries, <String>['rice']);

        lookup.fail = true;
        await controller.search(homeId: 'home-1', query: 'beans');
        expect(controller.candidates, isEmpty);
        expect(
          controller.safeError,
          'Catalog search is temporarily unavailable.',
        );
        expect(controller.isSearching, isFalse);
      },
    );

    test(
      'review controllers reject actions that cannot mutate stock',
      () async {
        final receiptProposalValue = receiptProposal();
        final receiptController = ReceiptReviewController(
          proposal: receiptProposalValue,
          homeId: 'home-1',
          approvedBy: 'user-1',
          approval: ApproveReceiptProposal(
            proposals: FakeProposalRepository(),
            commits: FakeReceiptCommit(),
          ),
          idempotencyKey: () => 'receipt-controller-0001',
        );
        addTearDown(receiptController.dispose);

        await receiptController.approve();
        expect(
          receiptController.safeError,
          'Resolve at least one receipt line before approval.',
        );
        receiptController.resolveLine(
          line: receiptLine(lineId: 'not-in-proposal'),
          resolution: const CatalogResolution(
            kind: CatalogResolutionKind.privateProduct,
            privateProductName: 'Other',
          ),
          quantity: 1,
        );
        expect(receiptController.selectedLineIds, isEmpty);

        final quarantined = stockProposal(
          classification: StockImageClassification.unrelated,
          candidates: <StockCandidateProposal>[],
        );
        final stockController = StockPhotoReviewController(
          proposal: quarantined,
          homeId: 'home-1',
          sessionId: 'session-1',
          locationId: 'location-1',
          closedBy: 'user-1',
          closeCount: CloseStockPhotoCount(
            proposals: FakeProposalRepository(),
            commits: FakeStockCommit(),
          ),
          idempotencyKey: () => 'stock-controller-0001',
        );
        addTearDown(stockController.dispose);

        await stockController.close();
        expect(
          stockController.safeError,
          'Quarantined content cannot be used for a stock count.',
        );
      },
    );
  });
}

AiMediaAsset _mediaAsset() => AiMediaAsset(
  id: 'media-1',
  homeId: 'home-1',
  localReference: 'local://receipt-1',
  purpose: AiExtractionKind.receipt,
  mimeType: 'image/jpeg',
  byteLength: 12000,
  createdAt: DateTime.utc(2026, 7, 30),
  width: 1200,
  height: 1600,
);

final class _ReceiptHarness {
  const _ReceiptHarness({
    required this.useCase,
    required this.media,
    required this.runs,
    required this.proposals,
  });

  final ExtractReceiptProposal useCase;
  final FakeMediaPreparation media;
  final FakeRunRepository runs;
  final FakeProposalRepository proposals;
}

_ReceiptHarness _receiptHarness(ReceiptGatewayHandler handler) {
  final media = FakeMediaPreparation(preparedBatch());
  final runs = FakeRunRepository();
  final proposals = FakeProposalRepository();
  final gateway = FakeGateway(
    route: AiGatewayRoute.serverProxyCloud,
    receiptHandler: handler,
  );
  return _ReceiptHarness(
    useCase: ExtractReceiptProposal(
      policy: const AiPrivacyPolicy(),
      gateways: FakeGatewayResolver(<AiGatewayRoute, AiProviderGateway>{
        AiGatewayRoute.serverProxyCloud: gateway,
      }),
      media: media,
      runs: runs,
      proposals: proposals,
      identifiers: FakeIdentifiers(),
      clock: () => DateTime.utc(2026, 7, 30),
    ),
    media: media,
    runs: runs,
    proposals: proposals,
  );
}

Future<AiExtractionResult<ReceiptProposal>> _extractReceipt(
  _ReceiptHarness harness,
) {
  final provider = serverProvider();
  final media = preparedBatch();
  return harness.useCase.execute(
    provider: provider,
    privacyMode: AiPrivacyMode.serverProxyCloud,
    media: media,
    consent: consentFor(provider: provider, media: media),
  );
}

Future<void> _controllerExtractReceipt(ReceiptExtractionController controller) {
  final provider = serverProvider();
  final media = preparedBatch();
  return controller.extract(
    provider: provider,
    privacyMode: AiPrivacyMode.serverProxyCloud,
    media: media,
    consent: consentFor(provider: provider, media: media),
  );
}

final class _StockHarness {
  const _StockHarness({
    required this.useCase,
    required this.media,
    required this.runs,
    required this.proposals,
  });

  final ExtractStockPhotoProposal useCase;
  final FakeMediaPreparation media;
  final FakeRunRepository runs;
  final FakeProposalRepository proposals;
}

_StockHarness _stockHarness(StockGatewayHandler handler) {
  final batch = preparedBatch(purpose: AiExtractionKind.stockPhoto);
  final media = FakeMediaPreparation(batch);
  final runs = FakeRunRepository();
  final proposals = FakeProposalRepository();
  final gateway = FakeGateway(
    route: AiGatewayRoute.serverProxyCloud,
    stockHandler: handler,
  );
  return _StockHarness(
    useCase: ExtractStockPhotoProposal(
      policy: const AiPrivacyPolicy(),
      gateways: FakeGatewayResolver(<AiGatewayRoute, AiProviderGateway>{
        AiGatewayRoute.serverProxyCloud: gateway,
      }),
      media: media,
      runs: runs,
      proposals: proposals,
      identifiers: FakeIdentifiers(),
      clock: () => DateTime.utc(2026, 7, 30),
    ),
    media: media,
    runs: runs,
    proposals: proposals,
  );
}

Future<AiExtractionResult<StockPhotoProposal>> _extractStock(
  _StockHarness harness,
) {
  final provider = serverProvider();
  final media = preparedBatch(purpose: AiExtractionKind.stockPhoto);
  return harness.useCase.execute(
    provider: provider,
    privacyMode: AiPrivacyMode.serverProxyCloud,
    media: media,
    consent: consentFor(provider: provider, media: media),
  );
}

Future<void> _controllerExtractStock(
  StockPhotoExtractionController controller,
) {
  final provider = serverProvider();
  final media = preparedBatch(purpose: AiExtractionKind.stockPhoto);
  return controller.extract(
    provider: provider,
    privacyMode: AiPrivacyMode.serverProxyCloud,
    media: media,
    consent: consentFor(provider: provider, media: media),
  );
}

ReviewedReceipt _reviewedReceipt(
  ReceiptProposal proposal, {
  required CatalogResolution resolution,
}) => ReviewedReceipt(
  proposalId: proposal.id,
  runId: proposal.runId,
  homeId: 'home-1',
  approvedBy: 'user-1',
  approvedAt: DateTime.utc(2026, 7, 30),
  humanConfirmed: true,
  lines: <ReviewedReceiptLine>[
    ReviewedReceiptLine(
      proposalLineId: proposal.lines.single.lineId,
      resolution: resolution,
      quantity: 2,
    ),
  ],
);

ReviewedStockCount _reviewedStockCount(
  StockPhotoProposal proposal, {
  required double quantity,
}) => ReviewedStockCount(
  proposalId: proposal.id,
  runId: proposal.runId,
  homeId: 'home-1',
  sessionId: 'session-1',
  locationId: 'location-1',
  closedBy: 'user-1',
  closedAt: DateTime.utc(2026, 7, 30),
  explicitlyClosed: true,
  items: <ConfirmedStockItem>[
    ConfirmedStockItem(
      proposalCandidateId: proposal.candidates.single.candidateId,
      resolution: const CatalogResolution(
        kind: CatalogResolutionKind.privateProduct,
        privateProductName: 'Rice',
      ),
      quantity: quantity,
    ),
  ],
);

const AiRunMetadata _stockMetadata = AiRunMetadata(
  providerKind: AiProviderKind.openAi,
  model: 'gpt-5-mini',
  protocol: AiEndpointProtocol.openAiResponses,
  promptVersion: 'stock-photo-extraction-v1',
  schemaVersion: 'stock-photo-v1',
  processingTime: Duration(milliseconds: 450),
);

final class _CatalogLookup implements CatalogCandidateLookupPort {
  final List<String> queries = <String>[];
  bool fail = false;

  @override
  Future<List<CatalogCandidate>> search({
    required String homeId,
    required String query,
    int limit = 20,
  }) async {
    queries.add(query);
    if (fail) {
      throw StateError('catalog unavailable');
    }
    return const <CatalogCandidate>[
      CatalogCandidate(
        packId: 'pack-rice-1kg',
        productName: 'Rice',
        packDescription: '1 kg',
        isPrivateToHome: true,
      ),
    ];
  }
}
