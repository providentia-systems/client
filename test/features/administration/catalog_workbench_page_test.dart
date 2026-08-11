import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/administration/application/catalog_administration_ports.dart';
import 'package:providentia/features/administration/application/catalog_merge_workflow.dart';
import 'package:providentia/features/administration/application/catalog_workbench_controller.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';
import 'package:providentia/features/administration/presentation/catalog_workbench_page.dart';

void main() {
  testWidgets(
    'review action invokes the revision-bound proposal decision port',
    (tester) async {
      final repository = _RecordingAdministrationRepository(
        queue: <CatalogQueueItem>[
          CatalogQueueItem(
            id: 'proposal-a',
            kind: CatalogQueueKind.proposal,
            title: 'Rolled oats',
            summary: 'Sanitized identity evidence',
            status: CatalogReviewStatus.pending,
            revision: 4,
          ),
        ],
      );
      final controller = CatalogWorkbenchController(repository);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogWorkbenchPage(
            controller: controller,
            proposalDecisions: repository,
            contributionDecisions: repository,
            conflictDecisions: repository,
            iconRepository: repository,
            mergeWorkflow: CatalogMergeWorkflow(repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final reviewButton = find.text('Review sanitized record');
      await tester.ensureVisible(reviewButton);
      await tester.tap(reviewButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('catalog-review-reason')),
        'Verified public identity',
      );
      await tester.tap(find.byKey(const Key('approve-catalog-review')));
      await tester.pumpAndSettle();

      expect(repository.proposalDecisions, hasLength(1));
      final decision = repository.proposalDecisions.single;
      expect(decision.proposalId, 'proposal-a');
      expect(decision.expectedRevision, 4);
      expect(decision.decision, CatalogReviewDecisionKind.approve);
      expect(decision.reason, 'Verified public identity');
    },
  );

  testWidgets('merge callback previews and executes the returned revisions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _RecordingAdministrationRepository(
      queue: <CatalogQueueItem>[
        CatalogQueueItem(
          id: 'conflict-a',
          kind: CatalogQueueKind.duplicate,
          title: 'Duplicate identity conflict',
          summary: 'Sanitized global identities',
          status: CatalogReviewStatus.conflict,
          revision: 3,
          source: CatalogQueueSource.conflict,
          relatedCatalogIds: const <String>['product-a', 'product-b'],
        ),
      ],
    );
    final controller = CatalogWorkbenchController(repository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CatalogWorkbenchPage(
          controller: controller,
          proposalDecisions: repository,
          contributionDecisions: repository,
          conflictDecisions: repository,
          iconRepository: repository,
          mergeWorkflow: CatalogMergeWorkflow(repository),
          idGenerator: () => 'operation-a',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final previewButton = find.text('Generate revision-bound merge preview');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('catalog-merge-reason')),
      'Confirmed duplicate products',
    );
    await tester.tap(find.byKey(const Key('execute-catalog-merge')));
    await tester.pumpAndSettle();

    expect(repository.previewRequests, <List<String>>[
      <String>['product-a', 'product-b'],
    ]);
    expect(repository.executions, hasLength(1));
    expect(repository.executions.single.idempotencyKey, 'operation-a');
    expect(repository.executions.single.reason, 'Confirmed duplicate products');
    expect(
      repository.executions.single.preview.expectedRevisions,
      <String, int>{'product-a': 7, 'product-b': 2},
    );
  });

  testWidgets(
    'icon action validates and invokes revision-bound metadata port',
    (tester) async {
      final repository = _RecordingAdministrationRepository(
        queue: <CatalogQueueItem>[
          CatalogQueueItem(
            id: 'category-a',
            kind: CatalogQueueKind.icon,
            title: 'Breakfast cereal',
            summary: 'Published catalog record needs icon metadata',
            status: CatalogReviewStatus.pending,
            revision: 6,
            source: CatalogQueueSource.icon,
            iconTargetType: CatalogIconTargetType.category,
          ),
        ],
      );
      final controller = CatalogWorkbenchController(repository);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CatalogWorkbenchPage(
            controller: controller,
            proposalDecisions: repository,
            contributionDecisions: repository,
            conflictDecisions: repository,
            iconRepository: repository,
            mergeWorkflow: CatalogMergeWorkflow(repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final iconButton = find.text('Add validated icon metadata');
      await tester.ensureVisible(iconButton);
      await tester.tap(iconButton);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save-catalog-icon')));
      await tester.pump();
      expect(
        find.byKey(const Key('catalog-icon-validation-error')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('catalog-icon-digest')),
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      await tester.enterText(
        find.byKey(const Key('catalog-icon-alt-text')),
        'Breakfast cereal category',
      );
      await tester.enterText(
        find.byKey(const Key('catalog-icon-byte-size')),
        '2048',
      );
      await tester.enterText(
        find.byKey(const Key('catalog-icon-provenance')),
        'Commissioned catalog asset',
      );
      await tester.tap(find.byKey(const Key('save-catalog-icon')));
      await tester.pumpAndSettle();

      expect(repository.icons, hasLength(1));
      final icon = repository.icons.single;
      expect(icon.targetType, CatalogIconTargetType.category);
      expect(icon.targetId, 'category-a');
      expect(icon.expectedRevision, 6);
      expect(icon.width, 256);
      expect(icon.height, 256);
      expect(icon.byteSize, 2048);
    },
  );
}

final class _Execution {
  const _Execution({
    required this.preview,
    required this.idempotencyKey,
    required this.reason,
  });

  final CatalogMergePreview preview;
  final String idempotencyKey;
  final String reason;
}

final class _RecordingAdministrationRepository
    implements
        CatalogModerationRepository,
        CatalogProposalDecisionRepository,
        CatalogContributionModerationRepository,
        CatalogConflictResolutionRepository,
        CatalogIconRepository,
        CatalogMergeRepository {
  _RecordingAdministrationRepository({required this.queue});

  final List<CatalogQueueItem> queue;
  final List<CatalogReviewDecision> proposalDecisions =
      <CatalogReviewDecision>[];
  final List<CatalogReviewDecision> contributionDecisions =
      <CatalogReviewDecision>[];
  final List<List<String>> previewRequests = <List<String>>[];
  final List<_Execution> executions = <_Execution>[];
  final List<CatalogIconWrite> icons = <CatalogIconWrite>[];

  @override
  Set<CatalogCapability> get capabilities => const <CatalogCapability>{
    CatalogCapability.review,
    CatalogCapability.manageIcons,
    CatalogCapability.previewMerges,
    CatalogCapability.executeMerges,
    CatalogCapability.reverseMerges,
  };

  @override
  Future<List<CatalogQueueItem>> loadQueue() async => queue;

  @override
  Future<CatalogModerationDecisionResult> decideProposal(
    CatalogReviewDecision decision,
  ) async {
    proposalDecisions.add(decision);
    return const CatalogModerationDecisionResult(
      status: CatalogReviewStatus.approved,
    );
  }

  @override
  Future<List<CatalogQueueItem>> loadContributionQueue() async => queue;

  @override
  Future<void> decideContribution(CatalogReviewDecision decision) async {
    contributionDecisions.add(decision);
  }

  @override
  Future<void> keepExistingConflict({
    required String conflictId,
    required String reason,
    required int expectedRevision,
  }) async {}

  @override
  Future<CatalogRevisionResult> putIcon(CatalogIconWrite icon) async {
    icons.add(icon);
    return CatalogRevisionResult(id: icon.targetId, revision: 1);
  }

  @override
  Future<CatalogMergePreview> previewMerge({
    required String survivorProductId,
    required List<String> absorbedProductIds,
  }) async {
    previewRequests.add(<String>[survivorProductId, ...absorbedProductIds]);
    return CatalogMergePreview(
      previewId: 'preview-a',
      kind: CatalogMergePlanKind.merge,
      survivorProductId: survivorProductId,
      absorbedProductIds: absorbedProductIds,
      expectedRevisions: <String, int>{
        survivorProductId: 7,
        for (final id in absorbedProductIds) id: 2,
      },
      impact: const CatalogMergeImpact(
        globalAliasCount: 1,
        globalPackCount: 2,
        globalBarcodeCount: 0,
        hasPrivateReferences: true,
        privateReferenceCount: 3,
      ),
      createdAt: DateTime.utc(2026, 8, 11),
    );
  }

  @override
  Future<CatalogMergePreview> previewReversal({required String mergeEventId}) {
    throw UnimplementedError();
  }

  @override
  Future<CatalogMergeResult> execute({
    required CatalogMergePreview preview,
    required String idempotencyKey,
    required String reason,
  }) async {
    executions.add(
      _Execution(
        preview: preview,
        idempotencyKey: idempotencyKey,
        reason: reason,
      ),
    );
    return CatalogMergeResult(
      eventId: 'merge-a',
      idempotencyKey: idempotencyKey,
      completedAt: DateTime.utc(2026, 8, 11),
      reversed: false,
    );
  }
}
