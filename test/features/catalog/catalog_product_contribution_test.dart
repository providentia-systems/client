import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/features/catalog/application/catalog_product_contribution_controller.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/application/catalog_submission_intent.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/presentation/catalog_product_contribution_page.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

void main() {
  test(
    'server consent and explicit per-item opt-in are independent gates',
    () async {
      final repository = _ContributionRepository();
      final controller = CatalogProductContributionController(
        consentRepository: repository,
        proposalService: CatalogProposalService(repository),
        homeId: _homeId,
        locale: 'en-NA',
        canContribute: true,
        submissionIdGenerator: () => _submissionId,
      );
      addTearDown(controller.dispose);

      await controller.loadConsent();
      final privateProduct = privateProductIdentityPreview(_inventoryItem());
      controller.selectProduct(privateProduct);
      final payload = controller.proposal!.toIdentityContributionJson();

      expect(controller.status, CatalogProductContributionStatus.ready);
      expect(payload, <String, Object?>{
        'canonicalName': 'Rolled oats',
        'brand': 'Example',
        'categoryLabel': 'Breakfast cereal',
        'packText': '1 kg bag',
      });
      for (final forbidden in <String>{
        'homeId',
        'homeProductId',
        'quantity',
        'unit',
        'aliases',
        'privateNote',
        'receipt',
        'media',
        'aiMetadata',
      }) {
        expect(payload, isNot(contains(forbidden)));
      }

      await controller.submit();
      expect(repository.submissions, isEmpty);

      controller.setExplicitConsent(true);
      await controller.submit();

      expect(repository.submissions, hasLength(1));
      expect(repository.submissions.single.homeId, _homeId);
      expect(repository.submissions.single.homeProductId, _productId);
      expect(repository.submissions.single.submissionId, _submissionId);
      expect(controller.status, CatalogProductContributionStatus.submitted);
    },
  );

  test(
    'disabled server consent prevents item selection and submission',
    () async {
      final repository = _ContributionRepository(identityConsent: false);
      final controller = CatalogProductContributionController(
        consentRepository: repository,
        proposalService: CatalogProposalService(repository),
        homeId: _homeId,
        locale: 'en-NA',
        canContribute: true,
      );
      addTearDown(controller.dispose);

      await controller.loadConsent();
      controller.selectProduct(privateProductIdentityPreview(_inventoryItem()));
      controller.setExplicitConsent(true);
      await controller.submit();

      expect(
        controller.status,
        CatalogProductContributionStatus.consentRequired,
      );
      expect(controller.proposal, isNull);
      expect(repository.submissions, isEmpty);
    },
  );

  test('missing home permission fails before the consent repository', () async {
    final repository = _ContributionRepository();
    final controller = CatalogProductContributionController(
      consentRepository: repository,
      proposalService: CatalogProposalService(repository),
      homeId: _homeId,
      locale: 'en-NA',
      canContribute: false,
    );
    addTearDown(controller.dispose);

    await controller.loadConsent();

    expect(controller.status, CatalogProductContributionStatus.forbidden);
    expect(repository.consentLoads, 0);
  });

  test('selection fails closed across the active-home boundary', () async {
    final repository = _ContributionRepository();
    final controller = CatalogProductContributionController(
      consentRepository: repository,
      proposalService: CatalogProposalService(repository),
      homeId: _homeId,
      locale: 'en-NA',
      canContribute: true,
    );
    addTearDown(controller.dispose);
    await controller.loadConsent();

    expect(
      () => controller.selectProduct(
        privateProductIdentityPreview(
          InventoryItem(
            id: 'other-product',
            homeId: 'other-home',
            canonicalName: 'Private other-home item',
            packSize: '1 unit',
            category: 'Private category',
          ),
        ),
      ),
      throwsStateError,
    );
    expect(controller.proposal, isNull);
    expect(repository.submissions, isEmpty);
  });

  for (final scenario
      in <({Exception failure, CatalogProductContributionStatus status})>[
        (
          failure: const CatalogContributionConflictException(),
          status: CatalogProductContributionStatus.conflict,
        ),
        (
          failure: const CatalogContributionUnavailableException(),
          status: CatalogProductContributionStatus.offline,
        ),
      ]) {
    test('${scenario.status.name} load failure exposes safe state', () async {
      final repository = _ContributionRepository(loadFailure: scenario.failure);
      final controller = CatalogProductContributionController(
        consentRepository: repository,
        proposalService: CatalogProposalService(repository),
        homeId: _homeId,
        locale: 'en-NA',
        canContribute: true,
      );
      addTearDown(controller.dispose);

      await controller.loadConsent();

      expect(controller.status, scenario.status);
      expect(controller.proposal, isNull);
      expect(repository.submissions, isEmpty);
    });
  }

  test(
    'authorization loss clears selected private state and invokes boundary',
    () async {
      var authorizationLosses = 0;
      final repository = _ContributionRepository(
        submitFailure: const CatalogContributionForbiddenException(),
      );
      final controller = CatalogProductContributionController(
        consentRepository: repository,
        proposalService: CatalogProposalService(repository),
        homeId: _homeId,
        locale: 'en-NA',
        canContribute: true,
        onAuthorizationLost: () async {
          authorizationLosses += 1;
        },
      );
      addTearDown(controller.dispose);

      await controller.loadConsent();
      controller.selectProduct(privateProductIdentityPreview(_inventoryItem()));
      controller.setExplicitConsent(true);
      await controller.submit();

      expect(controller.status, CatalogProductContributionStatus.forbidden);
      expect(controller.product, isNull);
      expect(controller.proposal, isNull);
      expect(authorizationLosses, 1);
    },
  );

  test('an ambiguous retry reuses the exact submission intent UUID', () async {
    final repository = _ContributionRepository(
      submitFailure: const CatalogContributionUnavailableException(),
    );
    final controller = CatalogProductContributionController(
      consentRepository: repository,
      proposalService: CatalogProposalService(repository),
      homeId: _homeId,
      locale: 'en-NA',
      canContribute: true,
      submissionIdGenerator: () => _submissionId,
    );
    addTearDown(controller.dispose);

    await controller.loadConsent();
    controller.selectProduct(privateProductIdentityPreview(_inventoryItem()));
    controller.setExplicitConsent(true);
    await controller.submit();

    expect(controller.status, CatalogProductContributionStatus.offline);
    expect(controller.pendingSubmissionId, _submissionId);
    expect(repository.attemptedSubmissionIds, <String>[_submissionId]);

    repository.submitFailure = null;
    await controller.loadConsent();
    controller.setExplicitConsent(true);
    await controller.submit();

    expect(repository.attemptedSubmissionIds, <String>[
      _submissionId,
      _submissionId,
    ]);
    expect(controller.status, CatalogProductContributionStatus.submitted);
    expect(controller.pendingSubmissionId, isNull);
  });

  test(
    'an identical retry after process death reuses its durable UUID',
    () async {
      final intentStore = MemoryCatalogSubmissionIntentStore();
      final repository = _ContributionRepository(
        submitFailure: const CatalogContributionUnavailableException(),
      );
      final first = CatalogProductContributionController(
        consentRepository: repository,
        proposalService: CatalogProposalService(repository),
        homeId: _homeId,
        locale: 'en-NA',
        canContribute: true,
        submissionIntents: CatalogSubmissionIntentCoordinator(
          store: intentStore,
          idGenerator: () => _submissionId,
        ),
      );
      await first.loadConsent();
      first.selectProduct(privateProductIdentityPreview(_inventoryItem()));
      first.setExplicitConsent(true);
      await first.submit();
      first.dispose();

      repository.submitFailure = null;
      final restored = CatalogProductContributionController(
        consentRepository: repository,
        proposalService: CatalogProposalService(repository),
        homeId: _homeId,
        locale: 'en-NA',
        canContribute: true,
        submissionIntents: CatalogSubmissionIntentCoordinator(
          store: intentStore,
          idGenerator: () => _otherSubmissionId,
        ),
      );
      addTearDown(restored.dispose);
      await restored.loadConsent();
      restored.selectProduct(privateProductIdentityPreview(_inventoryItem()));
      restored.setExplicitConsent(true);
      await restored.submit();

      expect(repository.attemptedSubmissionIds, <String>[
        _submissionId,
        _submissionId,
      ]);
      expect(restored.status, CatalogProductContributionStatus.submitted);
    },
  );

  testWidgets(
    'production route requires checkbox and clears through registry',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      final repository = _ContributionRepository();
      final inventory = InventoryController(
        repository: _InventoryRepository(<InventoryItem>[
          _inventoryItem(),
          _legacyInventoryItem(),
        ]),
        homeId: _homeId,
      );
      final registry = ProductionProtectedRouteRegistry();
      addTearDown(inventory.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionCatalogProductContributionRoute(
            consentRepository: repository,
            proposalRepository: repository,
            inventoryController: inventory,
            homeId: _homeId,
            locale: 'en-NA',
            protectedRouteRegistry: registry,
            onAuthorizationLost: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('catalog-contribution-product')));
      await tester.pumpAndSettle();
      expect(find.text('Legacy flour · 2 kg bag'), findsNothing);
      await tester.tap(find.text('Rolled oats · 1 kg bag').last);
      await tester.pumpAndSettle();

      expect(find.text('Sanitized catalog proposal'), findsOneWidget);
      expect(repository.submissions, isEmpty);
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('submit-catalog-contribution')),
      );
      expect(submit.onPressed, isNull);

      await tester.tap(
        find.byKey(const Key('catalog-contribution-explicit-checkbox')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('submit-catalog-contribution')));
      await tester.pumpAndSettle();

      expect(repository.submissions, hasLength(1));
      expect(find.text('Submitted for catalog review'), findsOneWidget);

      registry.clearSensitiveState();
      await tester.pump();
      expect(find.text('Submitted for catalog review'), findsNothing);
      expect(find.text('Rolled oats'), findsNothing);
    },
  );
}

const String _homeId = 'home-a';
const String _productId = 'product-a';
const String _submissionId = '01912345-6789-4abc-8def-0123456789ab';
const String _otherSubmissionId = '01912345-6789-4abc-8def-1123456789ab';

InventoryItem _inventoryItem() => InventoryItem(
  id: _productId,
  homeId: _homeId,
  canonicalName: 'Rolled oats',
  packSize: '1 kg bag',
  category: 'Breakfast cereal',
  brand: 'Example',
  unit: 'kg',
  aliases: const <String>['Private pantry alias'],
  currentQuantity: 42,
  isHomeProduct: true,
);

InventoryItem _legacyInventoryItem() => InventoryItem(
  id: 'legacy-product',
  homeId: _homeId,
  canonicalName: 'Legacy flour',
  packSize: '2 kg bag',
  category: 'Legacy import',
  currentQuantity: 3,
);

final class _Submission {
  const _Submission({
    required this.submissionId,
    required this.homeId,
    required this.homeProductId,
    required this.proposal,
  });

  final String submissionId;
  final String homeId;
  final String homeProductId;
  final SanitizedCatalogProposal proposal;
}

final class _ContributionRepository
    implements CatalogSharingConsentRepository, CatalogProposalRepository {
  _ContributionRepository({
    this.identityConsent = true,
    this.loadFailure,
    this.submitFailure,
  });

  final bool identityConsent;
  final Exception? loadFailure;
  Exception? submitFailure;
  int consentLoads = 0;
  final List<String> attemptedSubmissionIds = <String>[];
  final List<_Submission> submissions = <_Submission>[];

  @override
  Future<CatalogSharingConsent> loadConsent({required String homeId}) async {
    consentLoads += 1;
    final failure = loadFailure;
    if (failure != null) throw failure;
    return CatalogSharingConsent(
      homeId: homeId,
      shareProductIdentity: identityConsent,
      shareProductImages: false,
      shareStorePrices: false,
      noticeVersion: CatalogSharingConsent.currentNoticeVersion,
      revision: identityConsent ? 3 : 0,
    );
  }

  @override
  Future<CatalogSharingConsent> updateConsent({
    required String homeId,
    required CatalogSharingConsentUpdate update,
  }) => throw UnimplementedError();

  @override
  Future<CatalogSubmissionLink> submit({
    required String submissionId,
    required String homeId,
    required String homeProductId,
    required int expectedConsentRevision,
    required SanitizedCatalogProposal proposal,
  }) async {
    attemptedSubmissionIds.add(submissionId);
    expect(expectedConsentRevision, 3);
    final failure = submitFailure;
    if (failure != null) throw failure;
    submissions.add(
      _Submission(
        submissionId: submissionId,
        homeId: homeId,
        homeProductId: homeProductId,
        proposal: proposal,
      ),
    );
    return CatalogSubmissionLink(
      homeId: homeId,
      homeProductId: homeProductId,
      proposalId: 'contribution-a',
      status: CatalogProposalStatus.pending,
    );
  }
}

final class _InventoryRepository implements InventoryRepository {
  const _InventoryRepository(this.items);

  final List<InventoryItem> items;

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
      Stream<List<InventoryItem>>.value(items);

  @override
  Stream<StockCountSession?> watchActiveCountSession({
    required String homeId,
  }) => Stream<StockCountSession?>.value(null);

  @override
  Future<void> saveCountSession(StockCountSession session) =>
      throw UnimplementedError();

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) => throw UnimplementedError();
}
