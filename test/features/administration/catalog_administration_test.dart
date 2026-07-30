import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/administration/application/catalog_administration_ports.dart';
import 'package:providentia/features/administration/application/catalog_merge_workflow.dart';
import 'package:providentia/features/administration/application/catalog_workbench_controller.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';
import 'package:providentia/features/administration/presentation/catalog_workbench.dart';

void main() {
  group('catalog review models', () {
    test(
      'identity rules and barcode conflicts always require human review',
      () {
        const candidate = DuplicateCandidate(
          id: 'duplicate-1',
          leftProductId: 'tea-bags',
          rightProductId: 'tea-loose',
          signals: <DuplicateSignal>[
            DuplicateSignal(
              dimension: 'form',
              leftValue: 'bags',
              rightValue: 'loose leaf',
              score: 0.2,
              identityRuleConflict: true,
            ),
          ],
          revision: 2,
        );
        const barcode = BarcodeConflict(
          id: 'barcode-1',
          normalizedBarcode: '6001234567890',
          productIds: <String>['pack-1', 'pack-2'],
          revision: 1,
        );

        expect(candidate.hasIdentityRuleConflict, isTrue);
        expect(barcode.requiresHumanDecision, isTrue);
      },
    );

    test('moderation models contain sanitized catalog evidence only', () {
      const proposal = CatalogModerationProposal(
        id: 'proposal-1',
        canonicalName: 'Rice Basmati',
        locale: 'en-NA',
        status: CatalogReviewStatus.pending,
        revision: 3,
        brand: 'Himalaya Queen',
        packText: '5 kg',
      );
      const decision = CatalogReviewDecision(
        proposalId: 'proposal-1',
        decision: CatalogReviewDecisionKind.approve,
        reason: 'Identity confirmed',
        expectedRevision: 3,
      );
      const alias = AliasReview(
        id: 'alias-1',
        alias: 'Self Raising Wheat Flour',
        locale: 'en-NA',
        candidateProductIds: <String>['flour-1'],
        revision: 2,
      );
      const pack = PackNormalizationReview(
        id: 'pack-1',
        originalPackText: '5 kg bag',
        amount: 5,
        unitCode: 'kg',
        baseAmount: 5000,
        baseUnitCode: 'g',
        revision: 1,
      );
      const category = CategoryReview(
        id: 'category-1',
        productId: 'rice-1',
        currentCategoryId: 'pantry',
        proposedCategoryId: 'rice',
        revision: 4,
      );
      const icon = CatalogIconReview(
        id: 'icon-1',
        targetId: 'rice-1',
        mimeType: 'image/png',
        sha256: 'digest',
        width: 128,
        height: 128,
        accessibilityLabel: 'Rice bag',
        provenance: 'Commissioned generic icon',
        licence: 'Proprietary project asset',
        revision: 1,
      );
      final audit = CatalogAuditEvent(
        id: 'audit-1',
        action: 'proposal.reviewed',
        targetType: 'proposal',
        targetId: 'proposal-1',
        reason: 'Identity confirmed',
        occurredAt: _instant,
        requestId: 'request-1',
      );

      expect(proposal.canonicalName, 'Rice Basmati');
      expect(decision.expectedRevision, proposal.revision);
      expect(alias.candidateProductIds, <String>['flour-1']);
      expect(pack.baseAmount, 5000);
      expect(category.proposedCategoryId, 'rice');
      expect(icon.accessibilityLabel, 'Rice bag');
      expect(audit.requestId, 'request-1');
    });
  });

  group('revision-bound merge workflow', () {
    test(
      'rejects stale previews, blank reasons and missing capability',
      () async {
        final repository = _MergeRepository(
          capabilities: <CatalogCapability>{
            CatalogCapability.previewMerges,
            CatalogCapability.executeMerges,
          },
        );
        final workflow = CatalogMergeWorkflow(repository);
        final preview = await workflow.previewMerge(
          survivorProductId: 'product-a',
          absorbedProductIds: <String>['product-b'],
        );

        expect(
          () => workflow.execute(
            preview: preview,
            currentRevisions: <String, int>{'product-a': 4, 'product-b': 9},
            idempotencyKey: 'operation-1',
            reason: 'stale',
          ),
          throwsA(isA<CatalogStaleRevisionException>()),
        );
        expect(
          () => workflow.execute(
            preview: preview,
            currentRevisions: preview.expectedRevisions,
            idempotencyKey: 'operation-1',
            reason: ' ',
          ),
          throwsA(isA<CatalogMergeReasonRequiredException>()),
        );
        expect(
          () => workflow.previewReversal(mergeEventId: 'event-1'),
          throwsA(isA<CatalogMergeCapabilityException>()),
        );
        expect(
          () => workflow.previewMerge(
            survivorProductId: 'product-a',
            absorbedProductIds: <String>['product-a'],
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'coalesces identical execution and supports reversal preview',
      () async {
        final repository = _MergeRepository(
          capabilities: CatalogCapability.values.toSet(),
        );
        final workflow = CatalogMergeWorkflow(repository);
        final preview = await workflow.previewMerge(
          survivorProductId: 'product-a',
          absorbedProductIds: <String>['product-b'],
        );
        final first = workflow.execute(
          preview: preview,
          currentRevisions: preview.expectedRevisions,
          idempotencyKey: 'operation-1',
          reason: 'Confirmed duplicate',
        );
        final second = workflow.execute(
          preview: preview,
          currentRevisions: preview.expectedRevisions,
          idempotencyKey: 'operation-1',
          reason: 'Confirmed duplicate',
        );

        expect(await first, same(await second));
        expect(repository.executeCount, 1);
        expect(
          () => workflow.execute(
            preview: preview,
            currentRevisions: preview.expectedRevisions,
            idempotencyKey: 'operation-1',
            reason: 'Different command',
          ),
          throwsA(isA<CatalogConflictException>()),
        );
        final reversal = await workflow.previewReversal(
          mergeEventId: 'event-1',
        );
        expect(reversal.kind, CatalogMergePlanKind.reversal);
        expect(reversal.impact.hasPrivateReferences, isTrue);
      },
    );
  });

  group('workbench controller', () {
    test('maps safe transport states without carrying private data', () async {
      final cases = <_QueueMode, CatalogWorkbenchStatus>{
        _QueueMode.unavailable: CatalogWorkbenchStatus.contractUnavailable,
        _QueueMode.forbidden: CatalogWorkbenchStatus.forbidden,
        _QueueMode.conflict: CatalogWorkbenchStatus.conflict,
        _QueueMode.stale: CatalogWorkbenchStatus.stale,
        _QueueMode.failure: CatalogWorkbenchStatus.failure,
      };
      for (final entry in cases.entries) {
        final controller = CatalogWorkbenchController(
          _ModerationRepository(mode: entry.key),
        );
        await controller.refresh();
        expect(controller.status, entry.value);
        expect(controller.items, isEmpty);
        controller.dispose();
      }
    });

    test('denies a repository without review capability', () async {
      final controller = CatalogWorkbenchController(
        _ModerationRepository(
          mode: _QueueMode.ready,
          capabilities: const <CatalogCapability>{},
        ),
      );
      await controller.refresh();
      expect(controller.status, CatalogWorkbenchStatus.forbidden);
      expect(() => controller.select('missing'), throwsArgumentError);
    });

    test('explicit unavailable adapter fails closed', () async {
      final repository = UnavailableCatalogAdministrationRepository(
        capabilities: const <CatalogCapability>{
          CatalogCapability.review,
          CatalogCapability.readAudit,
        },
      );
      final controller = CatalogWorkbenchController(repository);
      await controller.refresh();
      expect(controller.status, CatalogWorkbenchStatus.contractUnavailable);
      expect(
        () => repository.previewMerge(
          survivorProductId: 'a',
          absorbedProductIds: const <String>['b'],
        ),
        throwsA(isA<CatalogContractUnavailableException>()),
      );
    });
  });

  testWidgets('responsive workbench renders queue, detail and safe errors', (
    tester,
  ) async {
    final repository = _ModerationRepository(mode: _QueueMode.ready);
    final controller = CatalogWorkbenchController(repository);
    await controller.refresh();

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CatalogWorkbench(controller: controller)),
      ),
    );

    expect(find.text('Catalog review'), findsOneWidget);
    expect(find.text('Rice Basmati'), findsWidgets);
    expect(find.textContaining('contains no home identity'), findsOneWidget);
    await tester.tap(find.text('Rice Basmati').first);
    await tester.pump();
    expect(find.text('Generate revision-bound merge preview'), findsOneWidget);
    expect(find.text('Catalog audit history'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_rounded), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);

    repository.mode = _QueueMode.unavailable;
    await controller.refresh();
    await tester.pump();
    expect(
      find.text('Catalog administration is not connected'),
      findsOneWidget,
    );
    expect(find.textContaining('stock'), findsNothing);
  });

  testWidgets(
    'workbench renders narrow, empty, read-only and safe state cards',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final readOnly = CatalogWorkbenchController(
        _ModerationRepository(
          mode: _QueueMode.ready,
          capabilities: const <CatalogCapability>{CatalogCapability.review},
        ),
      );
      await readOnly.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CatalogWorkbench(controller: readOnly)),
        ),
      );
      expect(find.textContaining('Read-only reviewer view'), findsOneWidget);
      await tester.tap(find.text('Rice Basmati').first);
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Generate revision-bound merge preview',
              ),
            )
            .onPressed,
        isNull,
      );

      final empty = CatalogWorkbenchController(
        _ModerationRepository(mode: _QueueMode.ready, empty: true),
      );
      await empty.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CatalogWorkbench(controller: empty)),
        ),
      );
      expect(find.text('No catalog reviews are waiting.'), findsOneWidget);
      expect(find.text('Select a sanitized catalog review.'), findsOneWidget);

      final safeStates = <_QueueMode, String>{
        _QueueMode.forbidden: 'Catalog role required',
        _QueueMode.conflict: 'Catalog change conflict',
        _QueueMode.stale: 'Merge preview is stale',
        _QueueMode.failure: 'Catalog workbench unavailable',
      };
      for (final entry in safeStates.entries) {
        final controller = CatalogWorkbenchController(
          _ModerationRepository(mode: entry.key),
        );
        await controller.refresh();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: CatalogWorkbench(controller: controller)),
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
        expect(find.textContaining('private server detail'), findsNothing);
      }
    },
  );
}

final DateTime _instant = DateTime.utc(2026, 7, 30);

enum _QueueMode { ready, unavailable, forbidden, conflict, stale, failure }

final class _ModerationRepository
    implements CatalogModerationRepository, CatalogAuditRepository {
  _ModerationRepository({
    required this.mode,
    this.empty = false,
    this.capabilities = const <CatalogCapability>{
      CatalogCapability.review,
      CatalogCapability.curate,
      CatalogCapability.previewMerges,
      CatalogCapability.readAudit,
    },
  });

  _QueueMode mode;
  final bool empty;

  @override
  final Set<CatalogCapability> capabilities;

  @override
  Future<List<CatalogAuditEvent>> loadAudit() async {
    return <CatalogAuditEvent>[
      CatalogAuditEvent(
        id: 'audit-1',
        action: 'proposal.reviewed',
        targetType: 'proposal',
        targetId: 'proposal-1',
        reason: 'Identity confirmed',
        occurredAt: _instant,
        requestId: 'request-1',
      ),
    ];
  }

  @override
  Future<List<CatalogQueueItem>> loadQueue() async {
    switch (mode) {
      case _QueueMode.unavailable:
        throw const CatalogContractUnavailableException();
      case _QueueMode.forbidden:
        throw const CatalogForbiddenException();
      case _QueueMode.conflict:
        throw const CatalogConflictException();
      case _QueueMode.stale:
        throw const CatalogStaleRevisionException();
      case _QueueMode.failure:
        throw Exception('private transport detail');
      case _QueueMode.ready:
        if (empty) {
          return const <CatalogQueueItem>[];
        }
        return CatalogQueueKind.values
            .map(
              (kind) => CatalogQueueItem(
                id: '${kind.name}-1',
                kind: kind,
                title: kind == CatalogQueueKind.duplicate
                    ? 'Rice Basmati'
                    : '${kind.name} review',
                summary: 'Review sanitized ${kind.name} evidence',
                status: CatalogReviewStatus.pending,
                revision: 2,
              ),
            )
            .toList(growable: false);
    }
  }
}

final class _MergeRepository implements CatalogMergeRepository {
  _MergeRepository({required this.capabilities});

  @override
  final Set<CatalogCapability> capabilities;

  int executeCount = 0;

  @override
  Future<CatalogMergeResult> execute({
    required CatalogMergePreview preview,
    required String idempotencyKey,
    required String reason,
  }) async {
    executeCount++;
    return CatalogMergeResult(
      eventId: 'event-$executeCount',
      idempotencyKey: idempotencyKey,
      completedAt: _instant,
      reversed: preview.kind == CatalogMergePlanKind.reversal,
    );
  }

  @override
  Future<CatalogMergePreview> previewMerge({
    required String survivorProductId,
    required List<String> absorbedProductIds,
  }) async {
    return CatalogMergePreview(
      previewId: 'preview-1',
      kind: CatalogMergePlanKind.merge,
      survivorProductId: survivorProductId,
      absorbedProductIds: absorbedProductIds,
      expectedRevisions: const <String, int>{'product-a': 4, 'product-b': 8},
      impact: const CatalogMergeImpact(
        globalAliasCount: 2,
        globalPackCount: 1,
        globalBarcodeCount: 0,
        hasPrivateReferences: true,
      ),
      createdAt: _instant,
    );
  }

  @override
  Future<CatalogMergePreview> previewReversal({
    required String mergeEventId,
  }) async {
    return CatalogMergePreview(
      previewId: 'reversal-1',
      kind: CatalogMergePlanKind.reversal,
      survivorProductId: 'product-a',
      absorbedProductIds: const <String>['product-b'],
      expectedRevisions: const <String, int>{'product-a': 5},
      impact: const CatalogMergeImpact(
        globalAliasCount: 2,
        globalPackCount: 1,
        globalBarcodeCount: 0,
        hasPrivateReferences: true,
      ),
      createdAt: _instant,
    );
  }
}
