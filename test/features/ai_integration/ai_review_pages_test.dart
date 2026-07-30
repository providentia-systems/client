import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/ai_use_cases.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/presentation/ai_controllers.dart';
import 'package:providentia/features/ai_integration/presentation/ai_review_pages.dart';

import 'test_fixtures.dart';

void main() {
  testWidgets('privacy confirmation is revoked when media changes', (
    tester,
  ) async {
    final provider = serverProvider();
    final controller = AiConsentController(
      provider: provider,
      privacyMode: AiPrivacyMode.serverProxyCloud,
      media: preparedBatch(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiPrivacyConsentCard(controller: controller)),
      ),
    );

    await tester.tap(
      find.text('I confirm this provider, privacy route, and media'),
    );
    await tester.pump();
    expect(controller.isConfirmed, isTrue);

    controller.updateContext(
      provider: provider,
      privacyMode: AiPrivacyMode.serverProxyCloud,
      media: preparedBatch(
        hash:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
    );
    await tester.pump();

    expect(controller.isConfirmed, isFalse);
    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isFalse);
  });

  testWidgets('receipt review cannot commit before a human selects a line', (
    tester,
  ) async {
    final proposals = FakeProposalRepository();
    final proposal = receiptProposal();
    proposals.receipts[proposal.id] = proposal;
    final commits = FakeReceiptCommit();
    final controller = ReceiptReviewController(
      proposal: proposal,
      homeId: 'home-1',
      approvedBy: 'user-1',
      approval: ApproveReceiptProposal(proposals: proposals, commits: commits),
      idempotencyKey: () => 'receipt-widget-0001',
      clock: () => DateTime.utc(2026, 7, 30),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ReceiptProposalReviewPage(controller: controller)),
    );

    expect(commits.calls, 0);
    final initialButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Approve selected lines'),
    );
    expect(initialButton.onPressed, isNull);

    await tester.tap(find.text('Use as private product'));
    await tester.pump();
    expect(commits.calls, 0);
    final enabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Approve selected lines'),
    );
    expect(enabledButton.onPressed, isNotNull);

    await tester.tap(find.text('Approve selected lines'));
    await tester.pumpAndSettle();

    expect(commits.calls, 1);
    expect(find.text('Receipt committed'), findsOneWidget);
  });

  testWidgets('medical receipt review exposes quarantine with no approval', (
    tester,
  ) async {
    final proposal = receiptProposal(
      classification: ReceiptDocumentClassification.medicineLeaflet,
      lines: <ReceiptLineProposal>[],
    );
    final controller = ReceiptReviewController(
      proposal: proposal,
      homeId: 'home-1',
      approvedBy: 'user-1',
      approval: ApproveReceiptProposal(
        proposals: FakeProposalRepository(),
        commits: FakeReceiptCommit(),
      ),
      idempotencyKey: () => 'receipt-widget-0002',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ReceiptProposalReviewPage(controller: controller)),
    );

    expect(find.text('This is not an eligible receipt'), findsOneWidget);
    expect(find.text('Approve selected lines'), findsNothing);
    expect(find.textContaining('cannot create'), findsOneWidget);
  });

  testWidgets('stock photo stays visible while confirmations move below', (
    tester,
  ) async {
    final proposals = FakeProposalRepository();
    final proposal = stockProposal();
    proposals.stocks[proposal.id] = proposal;
    final commits = FakeStockCommit();
    final controller = StockPhotoReviewController(
      proposal: proposal,
      homeId: 'home-1',
      sessionId: 'session-1',
      locationId: 'location-1',
      closedBy: 'user-1',
      closeCount: CloseStockPhotoCount(proposals: proposals, commits: commits),
      idempotencyKey: () => 'stock-widget-0001',
      clock: () => DateTime.utc(2026, 7, 30),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: StockPhotoReviewPage(
          controller: controller,
          mediaPreview: const ColoredBox(
            color: Colors.black12,
            child: Center(child: Text('Sanitized preview')),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('stock-media-preview')), findsOneWidget);
    expect(find.text('Sanitized preview'), findsOneWidget);
    expect(find.text('Confirm privately'), findsOneWidget);
    expect(commits.calls, 0);

    await tester.tap(find.text('Confirm privately'));
    await tester.pump();

    expect(find.byKey(const Key('stock-media-preview')), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget);
    expect(commits.calls, 0);

    await tester.tap(find.text('Review variance and close count'));
    await tester.pumpAndSettle();

    expect(commits.calls, 1);
    expect(find.text('Count closed'), findsOneWidget);
  });
}
