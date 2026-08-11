import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/receipt_ai_handoff_controller.dart';
import 'package:providentia/features/ai_integration/application/server_ai_repository.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/presentation/receipt_ai_handoff_page.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';

void main() {
  test('reviewed handoff remains non-mutating before final confirmation', () {
    final repository = _CaptureRepository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    expect(controller.status, ReceiptAiHandoffStatus.awaitingConfirmation);
    expect(repository.draftCalls, 0);
    expect(repository.lineCalls, 0);
    expect(repository.capture, isNull);
    expect(repository.stockMovementCalls, 0);
  });

  test(
    'confirmation creates one draft and unreviewed lines without commit',
    () async {
      final repository = _CaptureRepository();
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      expect(await controller.confirm(), isTrue);

      expect(repository.draftCalls, 1);
      expect(repository.lineCalls, 2);
      expect(repository.approvalCalls, 0);
      expect(repository.commitCalls, 0);
      expect(repository.stockMovementCalls, 0);
      expect(repository.capture?.sourceReference, 'ai-extraction:extract-1');
      expect(repository.capture?.status, PurchaseReceiptStatus.draft);
      expect(
        repository.capture?.lines.every(
          (line) =>
              line.approvalStatus == PurchaseLineApprovalStatus.unreviewed,
        ),
        isTrue,
      );
      expect(
        controller.status,
        ReceiptAiHandoffStatus.readyForPurchasingReview,
      );
    },
  );

  test('lost responses and replay do not duplicate draft or lines', () async {
    final repository = _CaptureRepository(
      loseFirstDraftResponse: true,
      loseFirstLineResponse: true,
    );
    final first = _controller(repository);
    addTearDown(first.dispose);

    expect(await first.confirm(), isTrue);
    expect(repository.draftCalls, 1);
    expect(repository.lineCalls, 2);
    expect(repository.capture?.lines, hasLength(2));

    final replay = _controller(repository);
    addTearDown(replay.dispose);
    expect(await replay.confirm(), isTrue);

    expect(repository.draftCalls, 1);
    expect(repository.lineCalls, 2);
    expect(repository.capture?.lines, hasLength(2));
    expect(repository.approvalCalls, 0);
    expect(repository.commitCalls, 0);
  });

  test('home or purchase-write loss permanently invalidates the draft', () {
    final foreignRepository = _CaptureRepository();
    final foreign = _controller(foreignRepository);
    addTearDown(foreign.dispose);
    foreign.updateAccess(activeHomeId: 'home-2', mayWritePurchases: true);

    final readonlyRepository = _CaptureRepository();
    final readonly = _controller(readonlyRepository);
    addTearDown(readonly.dispose);
    readonly.updateAccess(activeHomeId: 'home-1', mayWritePurchases: false);

    expect(foreign.status, ReceiptAiHandoffStatus.invalidated);
    expect(readonly.status, ReceiptAiHandoffStatus.invalidated);
    expect(foreign.canConfirm, isFalse);
    expect(readonly.canConfirm, isFalse);
    expect(foreignRepository.draftCalls, 0);
    expect(readonlyRepository.draftCalls, 0);
  });

  test('pending and rejected candidates never enter a handoff', () {
    final pending = _review(AiCandidateReviewStatus.pending);
    final rejected = _review(AiCandidateReviewStatus.rejected);

    expect(
      () => const AiReviewHandoffBuilder().build(pending),
      throwsA(isA<AiServerException>()),
    );
    expect(
      () => const AiReviewHandoffBuilder().build(rejected),
      throwsA(isA<AiServerException>()),
    );
  });

  testWidgets('page requires a second explicit confirmation then routes', (
    tester,
  ) async {
    final repository = _CaptureRepository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    String? routedReceiptId;

    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptAiHandoffPage(
          controller: controller,
          onOpenPurchasingReview: (receiptId) {
            routedReceiptId = receiptId;
          },
        ),
      ),
    );

    expect(repository.capture, isNull);
    expect(find.byKey(const Key('receipt-ai-no-stock-disclosure')), findsOne);
    await tester.scrollUntilVisible(
      find.byKey(const Key('receipt-ai-final-confirm')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('receipt-ai-final-confirm')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('receipt-ai-final-understanding')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('receipt-ai-final-confirm')));
    await tester.pumpAndSettle();

    expect(repository.capture?.lines, hasLength(2));
    expect(routedReceiptId, repository.capture?.id);
    expect(repository.approvalCalls, 0);
    expect(repository.commitCalls, 0);
    expect(repository.stockMovementCalls, 0);
  });
}

ReceiptAiHandoffController _controller(_CaptureRepository repository) =>
    ReceiptAiHandoffController(
      handoff: const AiReviewHandoffBuilder().build(
        _review(AiCandidateReviewStatus.accepted),
      ),
      repository: repository,
      activeHomeId: 'home-1',
      mayWritePurchases: true,
      recoveryTimeout: const Duration(milliseconds: 50),
    );

AiExtractionReview _review(AiCandidateReviewStatus status) {
  final header = AiReceiptHeaderPayload(
    merchant: 'Home Market',
    receiptNumber: 'R-42',
    purchaseDate: DateTime.utc(2026, 8, 11),
    currency: 'NAD',
    totalMinorUnits: 3500,
    taxMinorUnits: 0,
    notes: 'Reviewed from the receipt image.',
  );
  return AiExtractionReview(
    homeId: 'home-1',
    extractionId: 'extract-1',
    kind: AiExtractionKind.receipt,
    candidates: <AiReviewCandidate>[
      _candidate(
        position: 0,
        status: status,
        description: 'Rice',
        lineTotalMinorUnits: 2000,
        header: header,
      ),
      if (status != AiCandidateReviewStatus.rejected)
        _candidate(
          position: 1,
          status: status,
          description: 'Beans',
          lineTotalMinorUnits: 1500,
          header: header,
        ),
    ],
  );
}

AiReviewCandidate _candidate({
  required int position,
  required AiCandidateReviewStatus status,
  required String description,
  required int lineTotalMinorUnits,
  required AiReceiptHeaderPayload header,
}) => AiReviewCandidate(
  homeId: 'home-1',
  extractionId: 'extract-1',
  position: position,
  type: AiCandidateType.receiptLine,
  label: description,
  status: status,
  revision: 2,
  receiptPayload: AiReceiptCandidatePayload(
    rawText: '$description 1 kg',
    description: description,
    quantity: 1,
    packText: '1 kg',
    unitPriceMinorUnits: lineTotalMinorUnits,
    lineTotalMinorUnits: lineTotalMinorUnits,
    header: header,
  ),
);

final class _CaptureRepository implements PurchaseCaptureRepository {
  _CaptureRepository({
    this.loseFirstDraftResponse = false,
    this.loseFirstLineResponse = false,
  });

  bool loseFirstDraftResponse;
  bool loseFirstLineResponse;
  int draftCalls = 0;
  int lineCalls = 0;
  int approvalCalls = 0;
  int commitCalls = 0;
  int stockMovementCalls = 0;
  PurchaseReceiptCapture? capture;

  @override
  Future<PurchaseMutationResult> createReceiptDraft(
    PurchaseReceiptDraftRequest request,
  ) async {
    draftCalls++;
    capture ??= PurchaseReceiptCapture(
      id: 'receipt-1',
      homeId: request.homeId,
      purchaseDate: request.purchaseDate,
      currency: request.currency,
      total: request.total,
      notes: request.notes,
      sourceReference: request.sourceReference,
      revision: 1,
      status: PurchaseReceiptStatus.draft,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: const <PurchaseReceiptLineCapture>[],
    );
    if (loseFirstDraftResponse) {
      loseFirstDraftResponse = false;
      throw StateError('simulated lost response');
    }
    return const PurchaseMutationResult(
      entityId: 'receipt-1',
      revision: 1,
      disposition: PurchaseMutationDisposition.queued,
    );
  }

  @override
  Future<PurchaseMutationResult> addReceiptLine(
    PurchaseReceiptLineRequest request,
  ) async {
    lineCalls++;
    final current = capture!;
    final lineId = 'line-${current.lines.length + 1}';
    final lines = <PurchaseReceiptLineCapture>[
      ...current.lines,
      PurchaseReceiptLineCapture(
        id: lineId,
        homeId: request.homeId,
        receiptId: request.receiptId,
        rawDescription: request.rawDescription,
        quantity: request.quantity,
        originalPackText: request.originalPackText,
        unitPrice: request.unitPrice,
        lineTotal: request.lineTotal,
        revision: 1,
        approvalStatus: PurchaseLineApprovalStatus.unreviewed,
        synchronizationState: PurchaseSynchronizationState.pending,
      ),
    ];
    capture = PurchaseReceiptCapture(
      id: current.id,
      homeId: current.homeId,
      purchaseDate: current.purchaseDate,
      currency: current.currency,
      total: current.total,
      notes: current.notes,
      sourceReference: current.sourceReference,
      revision: current.revision + 1,
      status: current.status,
      synchronizationState: current.synchronizationState,
      lines: lines,
    );
    if (loseFirstLineResponse) {
      loseFirstLineResponse = false;
      throw StateError('simulated lost response');
    }
    return PurchaseMutationResult(
      entityId: lineId,
      revision: 1,
      disposition: PurchaseMutationDisposition.queued,
    );
  }

  @override
  Future<PurchaseMutationResult> approveReceiptLine({
    required String homeId,
    required String receiptId,
    required String lineId,
    required String homeProductId,
  }) async {
    approvalCalls++;
    return PurchaseMutationResult(
      entityId: lineId,
      revision: 2,
      disposition: PurchaseMutationDisposition.queued,
    );
  }

  @override
  Future<PurchaseMutationResult> markReceiptLineUnresolved({
    required String homeId,
    required String receiptId,
    required String lineId,
  }) async => PurchaseMutationResult(
    entityId: lineId,
    revision: 2,
    disposition: PurchaseMutationDisposition.queued,
  );

  @override
  Future<PurchaseMutationResult> commitReceipt({
    required String homeId,
    required String receiptId,
  }) async {
    commitCalls++;
    return PurchaseMutationResult(
      entityId: receiptId,
      revision: 2,
      disposition: PurchaseMutationDisposition.queued,
    );
  }

  @override
  Stream<PurchaseReceiptCapture?> watchActiveReceiptCapture({
    required String homeId,
  }) => Stream<PurchaseReceiptCapture?>.value(capture);

  @override
  Stream<List<PurchaseMatchCandidate>> watchPurchaseMatchCandidates({
    required String homeId,
  }) => const Stream<List<PurchaseMatchCandidate>>.empty();

  @override
  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  }) => const Stream<List<PriceObservation>>.empty();

  @override
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId}) =>
      const Stream<List<PurchaseLine>>.empty();
}
