import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/features/catalog/application/catalog_product_image_contribution_controller.dart';
import 'package:providentia/features/catalog/application/catalog_product_image_service.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/application/catalog_submission_intent.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/domain/catalog_product_image_models.dart';
import 'package:providentia/features/catalog/presentation/catalog_product_image_contribution_page.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

void main() {
  test(
    'closed image domain rejects invalid identity, digest and review data',
    () {
      expect(
        () => CatalogProductImageSource(
          homeId: 'not-a-uuid',
          homeProductId: _homeProductId,
          displayName: 'Rolled oats',
        ),
        throwsArgumentError,
      );
      expect(
        () => CatalogProductImageSubmission(
          contributionId: _submissionId,
          status: CatalogProductImageSubmissionStatus.pending,
          revision: 1,
          assetDigest: 'not-a-digest',
        ),
        throwsArgumentError,
      );
      final service = CatalogProductImageService(_ImageRepository());
      expect(() => service.normalizeAltText('   '), throwsArgumentError);
      expect(
        () => service.normalizeAltText('unsafe\ntext'),
        throwsArgumentError,
      );
    },
  );

  test(
    'both explicit reviews gate submission and success zeroizes bytes',
    () async {
      final repository = _ImageRepository();
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      await controller.loadConsent();
      controller.selectSource(_source);
      await controller.acquire(() async => _draft());
      final selectedBytes = controller.image!.previewBytes;
      controller.setAltText(' Front of the oats package ');
      await controller.submit();
      expect(repository.submissionIds, isEmpty);

      controller.setRightsConfirmed(true);
      await controller.submit();
      expect(repository.submissionIds, isEmpty);

      controller.setSubmissionConfirmed(true);
      await controller.submit();
      expect(repository.submissionIds, <String>[_submissionId]);
      expect(repository.altTexts, <String>['Front of the oats package']);
      expect(
        controller.status,
        CatalogProductImageContributionStatus.submitted,
      );
      expect(controller.image, isNull);
      expect(selectedBytes, everyElement(0));
    },
  );

  test('ambiguous offline retry reuses one exact submission UUID', () async {
    final repository = _ImageRepository(
      failure: const CatalogContributionUnavailableException(),
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await _prepare(controller);
    await controller.submit();
    expect(controller.status, CatalogProductImageContributionStatus.offline);
    expect(controller.pendingSubmissionId, _submissionId);

    repository.failure = null;
    await controller.submit();
    expect(repository.submissionIds, <String>[_submissionId, _submissionId]);
    expect(controller.status, CatalogProductImageContributionStatus.submitted);
  });

  test(
    '409 conflict retires the intent and requires fresh exact review',
    () async {
      final store = _IntentStore();
      final repository = _ImageRepository(
        failure: const CatalogContributionConflictException(),
      );
      final controller = _controller(
        repository,
        submissionIntents: CatalogSubmissionIntentCoordinator(
          store: store,
          idGenerator: () => _submissionId,
        ),
      );
      addTearDown(controller.dispose);

      await _prepare(controller);
      await controller.submit();

      expect(controller.status, CatalogProductImageContributionStatus.conflict);
      expect(controller.pendingSubmissionId, isNull);
      expect(controller.submissionConfirmed, isFalse);
      expect(controller.image, isNotNull);
      expect(store.deletedIds, <String>[_submissionId]);
      controller.reviewAfterConflict();
      expect(controller.status, CatalogProductImageContributionStatus.ready);
      expect(controller.maySubmit, isFalse);
    },
  );

  test('consent revision reload retires old intent before retry', () async {
    final store = _IntentStore();
    final repository = _ImageRepository(
      failure: const CatalogContributionUnavailableException(),
    );
    var id = 0;
    final controller = _controller(
      repository,
      submissionIntents: CatalogSubmissionIntentCoordinator(
        store: store,
        idGenerator: () => id++ == 0 ? _submissionId : _otherSubmissionId,
      ),
    );
    addTearDown(controller.dispose);

    await _prepare(controller);
    await controller.submit();
    expect(controller.pendingSubmissionId, _submissionId);
    repository
      ..consentRevision = 5
      ..failure = null;

    await controller.loadConsent();
    expect(controller.pendingSubmissionId, isNull);
    expect(store.deletedIds, contains(_submissionId));
    controller.setSubmissionConfirmed(true);
    await controller.submit();

    expect(repository.consentRevisions, <int>[4, 5]);
    expect(repository.submissionIds, <String>[
      _submissionId,
      _otherSubmissionId,
    ]);
  });

  test(
    'consent revocation releases image and retires pending intent',
    () async {
      final store = _IntentStore();
      final repository = _ImageRepository(
        failure: const CatalogContributionUnavailableException(),
      );
      final controller = _controller(
        repository,
        submissionIntents: CatalogSubmissionIntentCoordinator(
          store: store,
          idGenerator: () => _submissionId,
        ),
      );
      addTearDown(controller.dispose);

      await _prepare(controller);
      final selectedBytes = controller.image!.previewBytes;
      await controller.submit();
      repository
        ..shareProductImages = false
        ..consentRevision = 5;
      await controller.loadConsent();

      expect(
        controller.status,
        CatalogProductImageContributionStatus.consentRequired,
      );
      expect(controller.source, isNull);
      expect(controller.image, isNull);
      expect(selectedBytes, everyElement(0));
      expect(store.deletedIds, contains(_submissionId));
    },
  );

  test(
    'authorization purge and stale acquisition both zeroize bytes',
    () async {
      var authorizationLosses = 0;
      final repository = _ImageRepository(
        failure: const CatalogContributionForbiddenException(),
      );
      final controller = _controller(
        repository,
        onAuthorizationLost: () async => authorizationLosses++,
      );
      addTearDown(controller.dispose);

      await _prepare(controller);
      final submittedBytes = controller.image!.previewBytes;
      await controller.submit();
      expect(
        controller.status,
        CatalogProductImageContributionStatus.forbidden,
      );
      expect(submittedBytes, everyElement(0));
      expect(authorizationLosses, 1);

      final second = _controller(_ImageRepository());
      addTearDown(second.dispose);
      await second.loadConsent();
      second.selectSource(_source);
      final completer = Completer<CatalogProductImageDraft?>();
      final staleDraft = _draft();
      final staleBytes = staleDraft.previewBytes;
      final acquisition = second.acquire(() => completer.future);
      second.clearSensitiveState();
      completer.complete(staleDraft);
      await acquisition;
      expect(staleBytes, everyElement(0));
      expect(second.image, isNull);
    },
  );

  testWidgets('reachable page reviews a local preview before submission', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final repository = _ImageRepository();
    final inventory = InventoryController(
      repository: _InventoryRepository(<InventoryItem>[
        _inventoryItem,
        InventoryItem(
          id: _catalogOnlyId,
          homeId: _homeId,
          canonicalName: 'Global-only product',
          packSize: '500 g',
          category: 'Other',
          isHomeProduct: false,
        ),
      ]),
      homeId: _homeId,
    );
    final registry = ProductionProtectedRouteRegistry();
    addTearDown(inventory.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionCatalogProductImageContributionRoute(
          consentRepository: repository,
          imageRepository: repository,
          inventoryController: inventory,
          homeId: _homeId,
          protectedRouteRegistry: registry,
          onAuthorizationLost: () async {},
          acquisition: CatalogProductImageAcquisitionActions(
            takePhoto: () async => _draft(),
            chooseGallery: () async => null,
            chooseFile: () async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-image-product')));
    await tester.pumpAndSettle();
    expect(find.text('Global-only product · 500 g'), findsNothing);
    await tester.tap(find.text('Rolled oats · 1 kg bag').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-image-camera')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('catalog-image-metadata')), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-image-privacy-notice')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('catalog-image-alt-text')),
      'Front of the oats package',
    );
    tester.testTextInput.hide();
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('catalog-image-submit')),
      300,
      scrollable: list,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('catalog-image-submit')))
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('catalog-image-rights')),
      300,
      scrollable: list,
    );
    await tester.tap(find.byKey(const Key('catalog-image-rights')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('catalog-image-submit-confirmation')),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('catalog-image-submit')),
      300,
      scrollable: list,
    );
    await tester.tap(find.byKey(const Key('catalog-image-submit')));
    await tester.pumpAndSettle();

    expect(repository.submissionIds, hasLength(1));
    expect(find.text('Image submitted for review'), findsOneWidget);
    registry.clearSensitiveState();
    await tester.pump();
    expect(find.text('Image submitted for review'), findsNothing);
  });
}

Future<void> _prepare(
  CatalogProductImageContributionController controller,
) async {
  await controller.loadConsent();
  controller.selectSource(_source);
  await controller.acquire(() async => _draft());
  controller.setAltText('Front of the oats package');
  controller.setRightsConfirmed(true);
  controller.setSubmissionConfirmed(true);
}

CatalogProductImageContributionController _controller(
  _ImageRepository repository, {
  CatalogSubmissionIntentCoordinator? submissionIntents,
  Future<void> Function()? onAuthorizationLost,
}) => CatalogProductImageContributionController(
  consentRepository: repository,
  service: CatalogProductImageService(repository),
  homeId: _homeId,
  canContribute: true,
  submissionIntents: submissionIntents,
  submissionIdGenerator: () => _submissionId,
  onAuthorizationLost: onAuthorizationLost,
);

CatalogProductImageDraft _draft() => CatalogProductImageDraft(
  bytes: Uint8List.fromList(
    image_codec.encodePng(image_codec.Image(width: 32, height: 24)),
  ),
  mediaType: CatalogProductImageMediaType.png,
  width: 32,
  height: 24,
);

final CatalogProductImageSource _source = CatalogProductImageSource(
  homeId: _homeId,
  homeProductId: _homeProductId,
  displayName: 'Rolled oats',
);

final InventoryItem _inventoryItem = InventoryItem(
  id: _homeProductId,
  homeId: _homeId,
  canonicalName: 'Rolled oats',
  packSize: '1 kg bag',
  category: 'Breakfast cereal',
  isHomeProduct: true,
);

final class _ImageRepository
    implements CatalogSharingConsentRepository, CatalogProductImageRepository {
  _ImageRepository({this.failure});

  Exception? failure;
  bool shareProductImages = true;
  int consentRevision = 4;
  final List<String> submissionIds = <String>[];
  final List<int> consentRevisions = <int>[];
  final List<String> altTexts = <String>[];

  @override
  Future<CatalogSharingConsent> loadConsent({required String homeId}) async =>
      CatalogSharingConsent(
        homeId: homeId,
        shareProductIdentity: false,
        shareProductImages: shareProductImages,
        shareStorePrices: false,
        noticeVersion: CatalogSharingConsent.currentNoticeVersion,
        revision: consentRevision,
      );

  @override
  Future<CatalogProductImageSubmission> submitProductImage({
    required String submissionId,
    required int expectedConsentRevision,
    required CatalogProductImageSource source,
    required CatalogProductImageDraft image,
    required String altText,
  }) async {
    submissionIds.add(submissionId);
    consentRevisions.add(expectedConsentRevision);
    altTexts.add(altText);
    final currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
    return CatalogProductImageSubmission(
      contributionId: submissionId,
      status: CatalogProductImageSubmissionStatus.pending,
      revision: 1,
      assetDigest:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  }

  @override
  Future<CatalogSharingConsent> updateConsent({
    required String homeId,
    required CatalogSharingConsentUpdate update,
  }) => throw UnimplementedError();
}

final class _IntentStore implements CatalogSubmissionIntentStore {
  final Map<String, String> values = <String, String>{};
  final List<String> deletedIds = <String>[];

  @override
  Future<String?> read(CatalogSubmissionIntentKey key) async =>
      values[key.storageSlot];

  @override
  Future<void> write(CatalogSubmissionIntent intent) async {
    values[intent.key.storageSlot] = intent.submissionId;
  }

  @override
  Future<void> delete(CatalogSubmissionIntent intent) async {
    deletedIds.add(intent.submissionId);
    if (values[intent.key.storageSlot] == intent.submissionId) {
      values.remove(intent.key.storageSlot);
    }
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

const String _homeId = '01912345-6789-7abc-8def-0123456789ab';
const String _homeProductId = '01912345-6789-7abc-8def-1123456789ab';
const String _catalogOnlyId = '01912345-6789-7abc-8def-2123456789ab';
const String _submissionId = '01912345-6789-7abc-8def-3123456789ab';
const String _otherSubmissionId = '01912345-6789-7abc-8def-4123456789ab';
