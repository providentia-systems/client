import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/ai_use_cases.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';

import 'test_fixtures.dart';

void main() {
  group('receipt extraction', () {
    test('quarantines medical output without saving a proposal', () async {
      final media = FakeMediaPreparation(preparedBatch());
      final runs = FakeRunRepository();
      final proposals = FakeProposalRepository();
      final gateway = FakeGateway(
        route: AiGatewayRoute.serverProxyCloud,
        receiptHandler: (request) async => AiExtractionSuccess<ReceiptProposal>(
          proposal: receiptProposal(
            runId: request.runId,
            classification: ReceiptDocumentClassification.medicineLeaflet,
            lines: <ReceiptLineProposal>[],
          ),
          metadata: runMetadata,
        ),
      );
      final useCase = ExtractReceiptProposal(
        policy: const AiPrivacyPolicy(),
        gateways: FakeGatewayResolver(<AiGatewayRoute, AiProviderGateway>{
          AiGatewayRoute.serverProxyCloud: gateway,
        }),
        media: media,
        runs: runs,
        proposals: proposals,
        identifiers: FakeIdentifiers(),
        clock: () => DateTime.utc(2026, 7, 30),
      );
      final provider = serverProvider();
      final batch = preparedBatch();

      final result = await useCase.execute(
        provider: provider,
        privacyMode: AiPrivacyMode.serverProxyCloud,
        media: batch,
        consent: consentFor(provider: provider, media: batch),
      );

      expect(result, isA<AiExtractionQuarantined<ReceiptProposal>>());
      expect(proposals.receipts, isEmpty);
      expect(runs.values['run-1']?.state, AiRunState.quarantined);
      expect(media.discardCalls, 1);
      expect(gateway.requests.single.storeProviderResponse, isFalse);
    });

    test('fails closed when no server proxy gateway is composed', () async {
      final media = FakeMediaPreparation(preparedBatch());
      final runs = FakeRunRepository();
      final useCase = ExtractReceiptProposal(
        policy: const AiPrivacyPolicy(),
        gateways: FakeGatewayResolver(
          const <AiGatewayRoute, AiProviderGateway>{},
        ),
        media: media,
        runs: runs,
        proposals: FakeProposalRepository(),
        identifiers: FakeIdentifiers(),
      );
      final provider = serverProvider();
      final batch = preparedBatch();

      await expectLater(
        useCase.execute(
          provider: provider,
          privacyMode: AiPrivacyMode.serverProxyCloud,
          media: batch,
          consent: consentFor(provider: provider, media: batch),
        ),
        throwsA(
          isA<AiPolicyViolation>().having(
            (error) => error.code,
            'code',
            'gateway_contract_unavailable',
          ),
        ),
      );
      expect(media.discardCalls, 1);
      expect(runs.values['run-1']?.state, AiRunState.failed);
    });
  });

  group('human approval and idempotency', () {
    test('receipt commit cannot run before explicit human approval', () async {
      final proposals = FakeProposalRepository();
      final proposal = receiptProposal();
      proposals.receipts[proposal.id] = proposal;
      final commits = FakeReceiptCommit();
      final useCase = ApproveReceiptProposal(
        proposals: proposals,
        commits: commits,
      );
      final unapproved = ReviewedReceipt(
        proposalId: proposal.id,
        runId: proposal.runId,
        homeId: 'home-1',
        approvedBy: 'user-1',
        approvedAt: DateTime.utc(2026, 7, 30),
        humanConfirmed: false,
        lines: <ReviewedReceiptLine>[
          ReviewedReceiptLine(
            proposalLineId: proposal.lines.single.lineId,
            resolution: const CatalogResolution(
              kind: CatalogResolutionKind.privateProduct,
              privateProductName: 'Milk',
            ),
            quantity: 2,
          ),
        ],
      );

      await expectLater(
        useCase.execute(
          review: unapproved,
          idempotencyKey: 'receipt-approval-0001',
        ),
        throwsA(
          isA<AiPolicyViolation>().having(
            (error) => error.code,
            'code',
            'human_approval_required',
          ),
        ),
      );

      expect(commits.calls, 0);
      expect(proposals.receiptApprovalMarks, 0);
    });

    test('receipt retries reuse the stored idempotent outcome', () async {
      final proposals = FakeProposalRepository();
      final proposal = receiptProposal();
      proposals.receipts[proposal.id] = proposal;
      final commits = FakeReceiptCommit();
      final useCase = ApproveReceiptProposal(
        proposals: proposals,
        commits: commits,
      );
      final review = ReviewedReceipt(
        proposalId: proposal.id,
        runId: proposal.runId,
        homeId: 'home-1',
        approvedBy: 'user-1',
        approvedAt: DateTime.utc(2026, 7, 30),
        humanConfirmed: true,
        lines: <ReviewedReceiptLine>[
          ReviewedReceiptLine(
            proposalLineId: proposal.lines.single.lineId,
            resolution: const CatalogResolution(
              kind: CatalogResolutionKind.privateProduct,
              privateProductName: 'Milk',
            ),
            quantity: 2,
          ),
        ],
      );

      final first = await useCase.execute(
        review: review,
        idempotencyKey: 'receipt-approval-0001',
      );
      final second = await useCase.execute(
        review: review,
        idempotencyKey: 'receipt-approval-0001',
      );

      expect(first.resourceId, second.resourceId);
      expect(commits.calls, 1);
      expect(proposals.receiptApprovalMarks, 1);
    });

    test('stock count cannot mutate stock until explicitly closed', () async {
      final proposals = FakeProposalRepository();
      final proposal = stockProposal();
      proposals.stocks[proposal.id] = proposal;
      final commits = FakeStockCommit();
      final useCase = CloseStockPhotoCount(
        proposals: proposals,
        commits: commits,
      );
      final unclosed = ReviewedStockCount(
        proposalId: proposal.id,
        runId: proposal.runId,
        homeId: 'home-1',
        sessionId: 'session-1',
        locationId: 'location-1',
        closedBy: 'user-1',
        closedAt: DateTime.utc(2026, 7, 30),
        explicitlyClosed: false,
        items: const <ConfirmedStockItem>[],
      );

      await expectLater(
        useCase.execute(
          review: unclosed,
          idempotencyKey: 'stock-approval-0001',
        ),
        throwsA(
          isA<AiPolicyViolation>().having(
            (error) => error.code,
            'code',
            'explicit_close_required',
          ),
        ),
      );

      expect(commits.calls, 0);
      expect(proposals.countApprovalMarks, 0);
    });

    test('stock close retries reuse the stored idempotent outcome', () async {
      final proposals = FakeProposalRepository();
      final proposal = stockProposal();
      proposals.stocks[proposal.id] = proposal;
      final commits = FakeStockCommit();
      final useCase = CloseStockPhotoCount(
        proposals: proposals,
        commits: commits,
      );
      final review = ReviewedStockCount(
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
            quantity: 2,
          ),
        ],
      );

      await useCase.execute(
        review: review,
        idempotencyKey: 'stock-approval-0001',
      );
      await useCase.execute(
        review: review,
        idempotencyKey: 'stock-approval-0001',
      );

      expect(commits.calls, 1);
      expect(proposals.countApprovalMarks, 1);
    });
  });
}
