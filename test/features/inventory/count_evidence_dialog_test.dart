import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/count_evidence_dialog.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

void main() {
  test('physical observation requires a real date and explicit timezone', () {
    expect(
      parseCountObservation('2026-07-31T11:30:00+02:00'),
      DateTime.utc(2026, 7, 31, 9, 30),
    );
    expect(
      parseCountObservation('2024-02-29T23:30:00-02:00'),
      DateTime.utc(2024, 3, 1, 1, 30),
    );
    for (final text in [
      '2026-07-31T11:30:00',
      '2026-02-30T11:30:00Z',
      '2026-07-31T25:00:00Z',
      '2026-07-31T11:30:00+15:00',
      '2026-07-31T11:30:00+14:01',
    ]) {
      expect(() => parseCountObservation(text), throwsFormatException);
    }
  });

  testWidgets(
    'finishing keeps evidence unassessed until deliberately reviewed',
    (tester) async {
      final repository = _Repository(open: _session(closed: false));
      final controller = _controller(repository)..start();
      addTearDown(controller.dispose);
      await _show(tester, controller, repository.open!, false);
      expect(find.text('Unassessed — no reliability claim'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('count-complete-scope')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const Key('save-count-evidence')));
      await tester.pumpAndSettle();
      expect(repository.saved, isEmpty);
      expect(
        find.text('Enter a real observation time with timezone offset.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('count-observed-at')),
        '2026-07-31T11:30:00+02:00',
      );
      await tester.tap(find.byKey(const Key('save-count-evidence')));
      await tester.pumpAndSettle();
      final saved = repository.saved.single;
      expect(saved.status, CountSessionStatus.closed);
      expect(saved.scopeComplete, isFalse);
      expect(saved.reliability, 'unassessed');
      expect(saved.observedAt, DateTime.utc(2026, 7, 31, 9, 30));
      expect(saved.lines, hasLength(1));
      expect(saved.lines.single.observedQuantity, 4);
      expect(controller.countNotice, contains('server acceptance'));
    },
  );

  testWidgets(
    'accepted review requires complete reliable scope and retains input after rejection',
    (tester) async {
      final session = _session(closed: true);
      final repository = _Repository()..failReview = true;
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      await _show(tester, controller, session, true);
      await tester.enterText(
        find.byKey(const Key('count-review-reason')),
        'Correct the observed quantity',
      );
      await tester.enterText(
        find.byKey(const ValueKey('count-correction-line-one')),
        '2.5',
      );
      await tester.tap(find.byKey(const Key('count-reliability')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Reliable — checked complete observation').last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-count-evidence')));
      await tester.pumpAndSettle();
      expect(
        find.text('A reliable observation requires explicit complete scope.'),
        findsOneWidget,
      );
      expect(repository.reviewCalls, 0);
      await tester.tap(find.byKey(const Key('count-complete-scope')));
      await tester.tap(find.byKey(const Key('save-count-evidence')));
      await tester.pumpAndSettle();
      expect(repository.reviewCalls, 1);
      expect(find.textContaining('your input is kept'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('count-correction-line-one')),
            )
            .controller!
            .text,
        '2.5',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('count-review-reason')))
            .controller!
            .text,
        'Correct the observed quantity',
      );
      repository.failReview = false;
      await tester.tap(find.byKey(const Key('save-count-evidence')));
      await tester.pumpAndSettle();
      expect(repository.reviewCalls, 2);
      expect(repository.evidence!.scopeComplete, isTrue);
      expect(repository.evidence!.reliability, 'reliable');
      expect(repository.corrections!.single.id, 'line-one');
      expect(repository.corrections!.single.expectedRevision, 2);
      expect(repository.corrections!.single.quantity, '2.5');
      expect(
        controller.countNotice,
        contains('Accepted quantities and previous evidence'),
      );
    },
  );

  test(
    'count review fails closed for another home or missing write permission',
    () async {
      final repository = _Repository();
      final denied = InventoryController(
        repository: repository,
        homeId: 'home-one',
      );
      addTearDown(denied.dispose);
      expect(
        await denied.reviewAcceptedCount(
          session: _session(closed: true),
          evidence: StockCountEvidence(
            scopeComplete: false,
            reliability: 'partial',
            observedAt: DateTime.utc(2026, 7, 31),
          ),
          reason: 'Review',
          corrections: [],
        ),
        isFalse,
      );
      final allowed = _controller(repository);
      addTearDown(allowed.dispose);
      final foreign = StockCountSession(
        id: 'count-other',
        homeId: 'home-other',
        locationId: 'primary',
        startedAt: DateTime.utc(2026, 7, 31),
        status: CountSessionStatus.closed,
        closedAt: DateTime.utc(2026, 7, 31),
        revision: 3,
        serverAccepted: true,
      );
      expect(
        await allowed.reviewAcceptedCount(
          session: foreign,
          evidence: StockCountEvidence(
            scopeComplete: false,
            reliability: 'partial',
            observedAt: DateTime.utc(2026, 7, 31),
          ),
          reason: 'Review',
          corrections: [],
        ),
        isFalse,
      );
      expect(repository.reviewCalls, 0);
    },
  );
}

InventoryController _controller(_Repository repository) => InventoryController(
  repository: repository,
  homeId: 'home-one',
  mayReviewCounts: true,
  clock: () => DateTime.utc(2026, 8, 1),
);

StockCountSession _session({required bool closed}) => StockCountSession(
  id: 'count-one',
  homeId: 'home-one',
  locationId: 'primary',
  startedAt: DateTime.utc(2026, 7, 31),
  status: closed ? CountSessionStatus.closed : CountSessionStatus.open,
  closedAt: closed ? DateTime.utc(2026, 7, 31, 10) : null,
  revision: closed ? 3 : 1,
  serverAccepted: closed,
  observedAt: closed ? DateTime.utc(2026, 7, 31, 9) : null,
  scopeComplete: false,
  reliability: 'unassessed',
  observedTimezone: closed ? 'Africa/Windhoek' : null,
  lines: [
    StockCountLine(
      id: 'line-one',
      itemId: 'product-one',
      status: CountLineStatus.confirmed,
      source: CountSource.manual,
      observedQuantity: 4,
      revision: 2,
      unit: 'kg',
    ),
  ],
);

Future<void> _show(
  WidgetTester tester,
  InventoryController controller,
  StockCountSession session,
  bool accepted,
) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showCountEvidenceDialog(
              context: context,
              controller: controller,
              session: session,
              acceptedReview: accepted,
            ),
            child: const Text('Open evidence'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open evidence'));
  await tester.pumpAndSettle();
}

class _Repository
    implements InventoryRepository, InventoryCountReviewRepository {
  _Repository({this.open});
  final StockCountSession? open;
  final saved = <StockCountSession>[];
  bool failReview = false;
  int reviewCalls = 0;
  StockCountEvidence? evidence;
  List<StockCountLineCorrection>? corrections;
  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
      Stream.value([]);
  @override
  Stream<StockCountSession?> watchActiveCountSession({
    required String homeId,
  }) => Stream.value(open);
  @override
  Stream<List<StockCountSession>> watchCountSessions({
    required String homeId,
  }) => Stream.value([]);
  @override
  Future<void> saveCountSession(StockCountSession session) async {
    saved.add(session);
  }

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) async {}
  @override
  Future<void> reviewCountSession({
    required StockCountSession session,
    required StockCountEvidence evidence,
    required String reason,
    required List<StockCountLineCorrection> corrections,
  }) async {
    reviewCalls++;
    if (failReview) throw StateError('Synthetic stale revision');
    this.evidence = evidence;
    this.corrections = corrections;
  }
}
