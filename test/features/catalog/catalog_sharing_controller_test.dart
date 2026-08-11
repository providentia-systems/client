import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/application/catalog_sharing_controller.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/presentation/catalog_sharing_page.dart';

void main() {
  test(
    'each consent category preserves the others and uses the current revision',
    () async {
      final repository = _ConsentRepository(consent: _consent(revision: 4));
      final controller = CatalogSharingController(
        repository: repository,
        homeId: _homeId,
        canManageConsent: true,
        canContribute: true,
      );
      addTearDown(controller.dispose);

      await controller.load();
      await controller.setProductIdentity(true);
      await controller.setProductImages(true);
      await controller.setStorePrices(true);

      expect(
        repository.updates
            .map((update) => update.expectedRevision)
            .toList(growable: false),
        <int>[4, 5, 6],
      );
      expect(repository.updates[0].shareProductIdentity, isTrue);
      expect(repository.updates[0].shareProductImages, isFalse);
      expect(repository.updates[0].shareStorePrices, isFalse);
      expect(repository.updates[1].shareProductIdentity, isTrue);
      expect(repository.updates[1].shareProductImages, isTrue);
      expect(repository.updates[1].shareStorePrices, isFalse);
      expect(repository.updates[2].shareProductIdentity, isTrue);
      expect(repository.updates[2].shareProductImages, isTrue);
      expect(repository.updates[2].shareStorePrices, isTrue);
      expect(controller.consent?.revision, 7);
    },
  );

  test(
    'contribution permission alone is read-only and never writes consent',
    () async {
      final repository = _ConsentRepository(consent: _consent(revision: 2));
      final controller = CatalogSharingController(
        repository: repository,
        homeId: _homeId,
        canManageConsent: false,
        canContribute: true,
      );
      addTearDown(controller.dispose);

      await controller.load();
      await controller.setProductIdentity(true);

      expect(controller.status, CatalogSharingStatus.ready);
      expect(controller.mayEdit, isFalse);
      expect(repository.updates, isEmpty);
    },
  );

  test('conflict discards the stale revision and requires a reload', () async {
    final repository = _ConsentRepository(
      consent: _consent(revision: 2),
      updateFailure: const CatalogContributionConflictException(),
    );
    final controller = CatalogSharingController(
      repository: repository,
      homeId: _homeId,
      canManageConsent: true,
      canContribute: false,
    );
    addTearDown(controller.dispose);

    await controller.load();
    await controller.setProductImages(true);

    expect(controller.status, CatalogSharingStatus.conflict);
    expect(controller.consent, isNull);
    expect(repository.updates.single.expectedRevision, 2);
  });

  test(
    'authorization loss clears consent and invokes the session boundary',
    () async {
      var authorizationLosses = 0;
      final repository = _ConsentRepository(
        consent: _consent(revision: 1),
        updateFailure: const CatalogContributionForbiddenException(),
      );
      final controller = CatalogSharingController(
        repository: repository,
        homeId: _homeId,
        canManageConsent: true,
        canContribute: false,
        onAuthorizationLost: () async => authorizationLosses++,
      );
      addTearDown(controller.dispose);

      await controller.load();
      await controller.setStorePrices(true);

      expect(controller.status, CatalogSharingStatus.forbidden);
      expect(controller.consent, isNull);
      expect(authorizationLosses, 1);
    },
  );

  testWidgets('page states no implicit submission and exposes three switches', (
    tester,
  ) async {
    final repository = _ConsentRepository(consent: _consent(revision: 3));
    final controller = CatalogSharingController(
      repository: repository,
      homeId: _homeId,
      canManageConsent: true,
      canContribute: true,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CatalogSharingPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('catalog-sharing-explicit-notice')),
      findsOneWidget,
    );
    expect(find.textContaining('does not submit an item'), findsOneWidget);
    expect(find.byKey(const Key('share-product-identity')), findsOneWidget);
    expect(find.byKey(const Key('share-public-images')), findsOneWidget);
    expect(find.byKey(const Key('share-store-prices')), findsOneWidget);
    expect(find.textContaining('revision 3'), findsOneWidget);
  });
}

const String _homeId = 'home-a';

CatalogSharingConsent _consent({
  required int revision,
  bool productIdentity = false,
  bool productImages = false,
  bool storePrices = false,
}) => CatalogSharingConsent(
  homeId: _homeId,
  shareProductIdentity: productIdentity,
  shareProductImages: productImages,
  shareStorePrices: storePrices,
  noticeVersion: CatalogSharingConsent.currentNoticeVersion,
  revision: revision,
);

final class _ConsentRepository implements CatalogSharingConsentRepository {
  _ConsentRepository({required this.consent, this.updateFailure});

  CatalogSharingConsent consent;
  final Exception? updateFailure;
  final List<CatalogSharingConsentUpdate> updates =
      <CatalogSharingConsentUpdate>[];

  @override
  Future<CatalogSharingConsent> loadConsent({required String homeId}) async {
    expect(homeId, _homeId);
    return consent;
  }

  @override
  Future<CatalogSharingConsent> updateConsent({
    required String homeId,
    required CatalogSharingConsentUpdate update,
  }) async {
    expect(homeId, _homeId);
    updates.add(update);
    final failure = updateFailure;
    if (failure != null) throw failure;
    consent = _consent(
      revision: update.expectedRevision + 1,
      productIdentity: update.shareProductIdentity,
      productImages: update.shareProductImages,
      storePrices: update.shareStorePrices,
    );
    return consent;
  }
}
