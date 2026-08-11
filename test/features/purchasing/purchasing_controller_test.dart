import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_workspace.dart';

void main() {
  testWidgets(
    'purchasing workspace switches from receipts to monthly history',
    (tester) async {
      final repository = _PurchaseRepository();
      final controller = PurchasingController(
        repository: repository,
        homeId: 'home-a',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      repository.lines.add(<PurchaseLine>[
        _line(
          'recent',
          PurchaseSource.recentReceipt,
          DateTime.utc(2026, 7, 18),
        ),
        _line(
          'history',
          PurchaseSource.historicalImport,
          DateTime.utc(2026, 4),
        ),
      ]);
      await tester.pump();

      expect(find.text('Metro Fresh'), findsOneWidget);
      expect(
        find.byKey(const Key('purchase-capture-read-only')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('purchase-start-receipt')), findsNothing);
      await tester.tap(find.text('History'));
      await tester.pump();
      expect(find.text('2026-04'), findsOneWidget);
      expect(find.text('1 purchase lines'), findsOneWidget);

      controller.dispose();
      await repository.close();
    },
  );

  testWidgets('writer sees private receipt capture controls', (tester) async {
    final repository = _CaptureRepository();
    final controller = PurchasingController(
      repository: repository,
      homeId: 'home-a',
      mayWrite: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PurchasingWorkspace(controller: controller)),
      ),
    );
    repository.emitInitial();
    await tester.pump();

    expect(find.byKey(const Key('purchase-start-receipt')), findsOneWidget);
    await tester.tap(find.byKey(const Key('purchase-start-receipt')));
    await tester.pump();
    expect(find.byKey(const Key('purchase-create-draft')), findsOneWidget);
    expect(find.text('Private receipt notes (this home only)'), findsOneWidget);

    controller.dispose();
    await repository.close();
  });

  testWidgets(
    'writer validates, reviews, and synchronizes a private receipt in the workspace',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _CaptureRepository();
      final controller = PurchasingController(
        repository: repository,
        homeId: 'home-a',
        mayWrite: true,
      );
      addTearDown(() async {
        controller.dispose();
        await repository.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      repository.emitInitial();
      await tester.pump();

      await tester.tap(find.byKey(const Key('purchase-start-receipt')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('purchase-receipt-currency')),
        'NA',
      );
      await tester.tap(find.byKey(const Key('purchase-create-draft')));
      await tester.pump();
      expect(
        find.text('Currency must use a three-letter uppercase code.'),
        findsOneWidget,
      );
      expect(repository.createCalls, 0);

      await tester.enterText(
        find.byKey(const Key('purchase-receipt-currency')),
        'nad',
      );
      await tester.enterText(
        find.byKey(const Key('purchase-receipt-total')),
        '123.456',
      );
      await tester.tap(find.byKey(const Key('purchase-create-draft')));
      await tester.pump();
      expect(
        find.text(
          'Receipt total must be a non-negative amount with at most two decimals.',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('purchase-receipt-total')),
        '123.45',
      );
      await tester.enterText(
        find.byKey(const Key('purchase-receipt-notes')),
        'Private household note',
      );
      await tester.enterText(
        find.byKey(const Key('purchase-receipt-reference')),
        'receipt-local-42',
      );
      await tester.tap(find.byKey(const Key('purchase-create-draft')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, 1);
      expect(repository.lastDraftRequest?.homeId, 'home-a');
      expect(repository.lastDraftRequest?.currency, 'NAD');
      expect(
        repository.lastDraftRequest?.total,
        Money(minorUnits: 12345, currency: 'NAD'),
      );
      expect(repository.lastDraftRequest?.notes, 'Private household note');
      expect(repository.lastDraftRequest?.sourceReference, 'receipt-local-42');
      expect(
        find.byKey(const Key('purchase-authoritative-confirmation')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('purchase-review-required')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('purchase-line-description')),
        'Stone-ground flour',
      );
      await tester.enterText(
        find.byKey(const Key('purchase-line-total')),
        '12.999',
      );
      await tester.tap(find.byKey(const Key('purchase-add-line')));
      await tester.pump();
      expect(
        find.text(
          'Add a valid unit price or line total with at most two decimals.',
        ),
        findsOneWidget,
      );
      expect(repository.lastLineRequest, isNull);

      await tester.enterText(
        find.byKey(const Key('purchase-line-quantity')),
        '1.5',
      );
      await tester.enterText(
        find.byKey(const Key('purchase-line-pack')),
        '2 kg bag',
      );
      await tester.enterText(
        find.byKey(const Key('purchase-line-total')),
        '12.99',
      );
      await tester.tap(find.byKey(const Key('purchase-add-line')));
      await tester.pumpAndSettle();

      expect(repository.lastLineRequest?.homeId, 'home-a');
      expect(repository.lastLineRequest?.receiptId, 'receipt-a');
      expect(repository.lastLineRequest?.rawDescription, 'Stone-ground flour');
      expect(repository.lastLineRequest?.quantity, 1.5);
      expect(repository.lastLineRequest?.originalPackText, '2 kg bag');
      expect(
        repository.lastLineRequest?.lineTotal,
        Money(minorUnits: 1299, currency: 'NAD'),
      );
      expect(find.byKey(const Key('purchase-line-line-a')), findsOneWidget);

      final approveButton = find.byKey(
        const Key('purchase-approve-line-line-a'),
      );
      expect(tester.widget<FilledButton>(approveButton).onPressed, isNull);
      await tester.tap(find.byKey(const Key('purchase-line-match-line-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flour · 2 kg').last);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(approveButton).onPressed, isNotNull);
      await tester.tap(approveButton);
      await tester.pumpAndSettle();

      expect(repository.approvalCalls, 1);
      expect(
        find.textContaining('Approved: Flour · revision 2'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('purchase-review-required')), findsNothing);

      await tester.tap(find.byKey(const Key('purchase-commit-receipt')));
      await tester.pumpAndSettle();
      expect(repository.commitCalls, 1);
      expect(
        find.text('Commit queued locally; awaiting server confirmation.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('purchase-retry-commit')), findsOneWidget);

      await tester.tap(find.byKey(const Key('purchase-retry-commit')));
      await tester.pumpAndSettle();
      expect(repository.commitCalls, 2);
      repository.synchronizeCommit();
      await tester.pumpAndSettle();
      expect(find.text('Commit synchronized.'), findsOneWidget);
      expect(find.byKey(const Key('purchase-retry-commit')), findsNothing);
    },
  );

  testWidgets(
    'recent receipt groups disclose synchronization and pricing completeness',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _PurchaseRepository();
      final controller = PurchasingController(
        repository: repository,
        homeId: 'home-a',
      );
      addTearDown(() async {
        controller.dispose();
        await repository.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      repository.lines.add(<PurchaseLine>[
        PurchaseLine(
          id: 'pending-priced',
          homeId: 'home-a',
          receiptId: 'receipt-pending',
          purchasedAt: DateTime.utc(2026, 8, 10),
          datePrecision: PurchaseDatePrecision.exactDay,
          storeName: 'Corner Shop',
          rawDescription: 'Unnormalized rice',
          canonicalName: 'Brown rice',
          packSize: '1 kg',
          quantity: 2,
          source: PurchaseSource.recentReceipt,
          lineTotal: Money(minorUnits: 2599, currency: 'NAD'),
          pendingSynchronization: true,
        ),
        PurchaseLine(
          id: 'synced-unpriced',
          homeId: 'home-a',
          receiptId: 'receipt-synced',
          purchasedAt: DateTime.utc(2026, 8, 9),
          datePrecision: PurchaseDatePrecision.exactDay,
          storeName: 'Market',
          rawDescription: 'Apples',
          packSize: 'loose',
          quantity: 1.25,
          source: PurchaseSource.recentReceipt,
        ),
        PurchaseLine(
          id: 'legacy',
          homeId: 'home-a',
          purchasedAt: DateTime.utc(2026, 8, 8),
          datePrecision: PurchaseDatePrecision.exactDay,
          storeName: 'Imported Store',
          rawDescription: 'Legacy beans',
          packSize: '500 g',
          quantity: 1,
          source: PurchaseSource.recentReceipt,
          lineTotal: Money(minorUnits: 800, currency: 'NAD'),
        ),
      ]);
      await tester.pump();

      expect(find.text('3 receipt groups'), findsOneWidget);
      expect(find.text('NAD 33.99'), findsOneWidget);
      expect(find.text('Receipt pending synchronization'), findsOneWidget);
      expect(find.text('Receipt'), findsOneWidget);
      expect(find.text('Legacy date/store grouping'), findsOneWidget);
      expect(find.text('NAD 25.99'), findsOneWidget);

      await tester.tap(find.text('Corner Shop'));
      await tester.pumpAndSettle();
      expect(find.text('Brown rice'), findsOneWidget);
      expect(find.text('NAD 25.99'), findsNWidgets(2));

      await tester.tap(find.text('Market'));
      await tester.pumpAndSettle();
      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('1.250'), findsOneWidget);

      repository.lines.add(<PurchaseLine>[
        PurchaseLine(
          id: 'unpriced-only',
          homeId: 'home-a',
          receiptId: 'receipt-unpriced',
          purchasedAt: DateTime.utc(2026, 8, 11),
          datePrecision: PurchaseDatePrecision.exactDay,
          storeName: 'Market',
          rawDescription: 'Loose produce',
          packSize: 'loose',
          quantity: 1,
          source: PurchaseSource.recentReceipt,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Incomplete prices'), findsOneWidget);
    },
  );

  test(
    'capture controller denies incomplete review and never claims commit',
    () async {
      final repository = _CaptureRepository();
      final controller = PurchasingController(
        repository: repository,
        homeId: 'home-a',
        mayWrite: true,
      );
      controller.start();
      repository.emitInitial();
      await Future<void>.delayed(Duration.zero);

      expect(
        await controller.createDraft(
          purchaseDate: DateTime.utc(2026, 8, 11),
          currency: 'NAD',
        ),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        await controller.addLine(
          rawDescription: 'Flour',
          quantity: 1,
          lineTotal: Money(minorUnits: 1200, currency: 'NAD'),
        ),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);

      expect(await controller.commitDraft(), isFalse);
      expect(repository.commitCalls, 0);
      expect(
        controller.state.captureError,
        'Every receipt line must be explicitly matched and approved.',
      );

      expect(
        await controller.approveLine(
          lineId: 'line-a',
          homeProductId: 'product-a',
        ),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(await controller.commitDraft(), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(repository.commitCalls, 1);
      expect(
        controller.state.captureNotice,
        'The receipt commit is queued; server confirmation is pending.',
      );
      expect(controller.state.capture?.commitAwaitingConfirmation, isTrue);

      expect(await controller.commitDraft(), isTrue);
      expect(repository.commitCalls, 2);
      expect(
        controller.state.captureNotice,
        'The receipt commit remains queued; server confirmation is pending.',
      );

      controller.dispose();
      await repository.close();
    },
  );

  test(
    'read-only controller rejects capture without invoking repository',
    () async {
      final repository = _CaptureRepository();
      final controller = PurchasingController(
        repository: repository,
        homeId: 'home-a',
      );

      expect(
        await controller.createDraft(
          purchaseDate: DateTime.utc(2026, 8, 11),
          currency: 'NAD',
        ),
        isFalse,
      );
      expect(repository.createCalls, 0);
      expect(
        controller.state.captureError,
        'Purchase capture is unavailable for this read-only home.',
      );

      controller.dispose();
      await repository.close();
    },
  );
}

PurchaseLine _line(String id, PurchaseSource source, DateTime at) =>
    PurchaseLine(
      id: id,
      homeId: 'home-a',
      purchasedAt: at,
      datePrecision: source == PurchaseSource.recentReceipt
          ? PurchaseDatePrecision.exactDay
          : PurchaseDatePrecision.monthOnly,
      storeName: 'Metro Fresh',
      rawDescription: 'Rice',
      packSize: '1 kg',
      quantity: 1,
      source: source,
      lineTotal: source == PurchaseSource.recentReceipt
          ? Money(minorUnits: 1000, currency: 'NAD')
          : null,
    );

class _PurchaseRepository implements PurchaseRepository {
  final lines = StreamController<List<PurchaseLine>>.broadcast();

  @override
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId}) =>
      lines.stream;

  @override
  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  }) => const Stream<List<PriceObservation>>.empty();

  Future<void> close() => lines.close();
}

final class _CaptureRepository implements PurchaseCaptureRepository {
  final _captures = StreamController<PurchaseReceiptCapture?>.broadcast();
  final _candidates =
      StreamController<List<PurchaseMatchCandidate>>.broadcast();
  PurchaseReceiptCapture? _current;
  PurchaseReceiptDraftRequest? lastDraftRequest;
  PurchaseReceiptLineRequest? lastLineRequest;
  int createCalls = 0;
  int approvalCalls = 0;
  int commitCalls = 0;

  void emitInitial() {
    _captures.add(_current);
    _candidates.add(<PurchaseMatchCandidate>[
      PurchaseMatchCandidate(
        id: 'product-a',
        homeId: 'home-a',
        name: 'Flour',
        packSize: '2 kg',
      ),
    ]);
  }

  @override
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId}) =>
      Stream<List<PurchaseLine>>.value(const <PurchaseLine>[]);

  @override
  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  }) => const Stream<List<PriceObservation>>.empty();

  @override
  Stream<PurchaseReceiptCapture?> watchActiveReceiptCapture({
    required String homeId,
  }) => _captures.stream;

  @override
  Stream<List<PurchaseMatchCandidate>> watchPurchaseMatchCandidates({
    required String homeId,
  }) => _candidates.stream;

  @override
  Future<PurchaseMutationResult> createReceiptDraft(
    PurchaseReceiptDraftRequest request,
  ) async {
    createCalls++;
    lastDraftRequest = request;
    _current = PurchaseReceiptCapture(
      id: 'receipt-a',
      homeId: request.homeId,
      purchaseDate: request.purchaseDate,
      currency: request.currency,
      notes: request.notes,
      revision: 1,
      status: PurchaseReceiptStatus.draft,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: const <PurchaseReceiptLineCapture>[],
    );
    _captures.add(_current);
    return const PurchaseMutationResult(
      entityId: 'receipt-a',
      revision: 1,
      disposition: PurchaseMutationDisposition.queued,
    );
  }

  @override
  Future<PurchaseMutationResult> addReceiptLine(
    PurchaseReceiptLineRequest request,
  ) async {
    lastLineRequest = request;
    _current = PurchaseReceiptCapture(
      id: 'receipt-a',
      homeId: request.homeId,
      purchaseDate: DateTime.utc(2026, 8, 11),
      currency: 'NAD',
      notes: '',
      revision: 2,
      status: PurchaseReceiptStatus.draft,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: <PurchaseReceiptLineCapture>[
        PurchaseReceiptLineCapture(
          id: 'line-a',
          homeId: request.homeId,
          receiptId: request.receiptId,
          rawDescription: request.rawDescription,
          quantity: request.quantity,
          lineTotal: request.lineTotal,
          revision: 1,
          approvalStatus: PurchaseLineApprovalStatus.unreviewed,
          synchronizationState: PurchaseSynchronizationState.pending,
        ),
      ],
    );
    _captures.add(_current);
    return const PurchaseMutationResult(
      entityId: 'line-a',
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
    final current = _current!;
    final line = current.lines.single;
    _current = PurchaseReceiptCapture(
      id: current.id,
      homeId: homeId,
      purchaseDate: current.purchaseDate,
      currency: current.currency,
      notes: current.notes,
      revision: 3,
      status: PurchaseReceiptStatus.draft,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: <PurchaseReceiptLineCapture>[
        PurchaseReceiptLineCapture(
          id: lineId,
          homeId: homeId,
          receiptId: receiptId,
          rawDescription: line.rawDescription,
          quantity: line.quantity,
          lineTotal: line.lineTotal,
          homeProductId: homeProductId,
          revision: 2,
          approvalStatus: PurchaseLineApprovalStatus.approved,
          synchronizationState: PurchaseSynchronizationState.pending,
        ),
      ],
    );
    _captures.add(_current);
    return PurchaseMutationResult(
      entityId: lineId,
      revision: 2,
      disposition: PurchaseMutationDisposition.queued,
    );
  }

  @override
  Future<PurchaseMutationResult> commitReceipt({
    required String homeId,
    required String receiptId,
  }) async {
    commitCalls++;
    final current = _current!;
    if (current.status == PurchaseReceiptStatus.committed) {
      return PurchaseMutationResult(
        entityId: receiptId,
        revision: current.revision,
        disposition: PurchaseMutationDisposition.alreadyQueued,
      );
    }
    _current = PurchaseReceiptCapture(
      id: current.id,
      homeId: homeId,
      purchaseDate: current.purchaseDate,
      currency: current.currency,
      notes: current.notes,
      revision: 4,
      status: PurchaseReceiptStatus.committed,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: current.lines,
    );
    _captures.add(_current);
    return PurchaseMutationResult(
      entityId: receiptId,
      revision: 4,
      disposition: PurchaseMutationDisposition.queued,
    );
  }

  void synchronizeCommit() {
    final current = _current!;
    _current = PurchaseReceiptCapture(
      id: current.id,
      homeId: current.homeId,
      purchaseDate: current.purchaseDate,
      currency: current.currency,
      notes: current.notes,
      revision: current.revision,
      status: PurchaseReceiptStatus.committed,
      synchronizationState: PurchaseSynchronizationState.synchronized,
      lines: current.lines,
    );
    _captures.add(_current);
  }

  Future<void> close() async {
    await _captures.close();
    await _candidates.close();
  }
}
