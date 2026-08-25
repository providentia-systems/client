import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/application/catalog_store_price_contribution_controller.dart';
import 'package:providentia/features/catalog/application/catalog_store_price_service.dart';
import 'package:providentia/features/catalog/application/catalog_submission_intent.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/domain/catalog_store_price_models.dart';
import 'package:providentia/features/catalog/infrastructure/platform_catalog_submission_intent_store.dart';
import 'package:providentia/features/catalog/presentation/catalog_store_price_contribution_page.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

void main() {
  test('store-price preview is a closed, normalized public DTO', () {
    final service = CatalogStorePriceService(
      _StorePriceRepository(),
      clock: () => DateTime.utc(2026, 8, 25, 22),
    );

    final observation = service.preview(
      source: _source(),
      storeName: ' Corner Shop ',
      storeLocation: ' Windhoek West ',
      price: '12.990',
      currency: 'nad',
      observedOn: DateTime(2026, 8, 24, 23, 59),
    );

    expect(observation.toPayloadJson(), <String, Object?>{
      'productId': _productId,
      'packId': _packId,
      'storeName': 'Corner Shop',
      'storeLocation': 'Windhoek West',
      'price': '12.990',
      'currency': 'NAD',
      'observedOn': '2026-08-24',
    });
    for (final forbidden in <String>{
      'homeId',
      'homeProductId',
      'userId',
      'email',
      'quantity',
      'receipt',
      'privateNote',
      'media',
    }) {
      expect(observation.toPayloadJson(), isNot(contains(forbidden)));
    }
    expect(
      () => service.preview(
        source: _source(),
        storeName: 'Corner Shop',
        price: '12.9',
        currency: 'NAD',
        observedOn: DateTime.utc(2026, 8, 24),
      ),
      throwsArgumentError,
    );
    expect(
      () => service.preview(
        source: _source(),
        storeName: 'Corner Shop',
        price: '12.99',
        currency: 'NAD',
        observedOn: DateTime.utc(2026, 8, 26),
      ),
      throwsArgumentError,
    );
  });

  test(
    'server opt-in and per-observation confirmation are independent',
    () async {
      final repository = _StorePriceRepository();
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      await controller.loadConsent();
      controller.selectSource(_source());
      _preview(controller);
      await controller.submit();

      expect(repository.attemptedSubmissionIds, isEmpty);
      controller.setExplicitConsent(true);
      await controller.submit();

      expect(repository.attemptedSubmissionIds, <String>[_submissionId]);
      expect(controller.status, CatalogStorePriceContributionStatus.submitted);
      expect(controller.submission?.type, CatalogContributionType.storePrice);
      expect(controller.submission?.contributionId, _contributionId);
    },
  );

  test(
    'disabled store-price consent prevents selection and submission',
    () async {
      final repository = _StorePriceRepository(storePriceConsent: false);
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      await controller.loadConsent();
      controller.selectSource(_source());

      expect(
        controller.status,
        CatalogStorePriceContributionStatus.consentRequired,
      );
      expect(controller.source, isNull);
      expect(repository.attemptedSubmissionIds, isEmpty);
    },
  );

  test('durable fingerprint reuses one UUID after process death', () async {
    final intentStore = MemoryCatalogSubmissionIntentStore();
    final repository = _StorePriceRepository(
      failure: const CatalogContributionUnavailableException(),
    );
    final first = _controller(
      repository,
      submissionIntents: CatalogSubmissionIntentCoordinator(
        store: intentStore,
        idGenerator: () => _submissionId,
      ),
    );
    await first.loadConsent();
    first.selectSource(_source());
    _preview(first);
    first.setExplicitConsent(true);
    await first.submit();
    expect(first.status, CatalogStorePriceContributionStatus.offline);
    first.dispose();

    repository.failure = null;
    final restored = _controller(
      repository,
      submissionIntents: CatalogSubmissionIntentCoordinator(
        store: intentStore,
        idGenerator: () => _otherSubmissionId,
      ),
    );
    addTearDown(restored.dispose);
    await restored.loadConsent();
    restored.selectSource(_source());
    _preview(restored);
    restored.setExplicitConsent(true);
    await restored.submit();

    expect(repository.attemptedSubmissionIds, <String>[
      _submissionId,
      _submissionId,
    ]);
    expect(restored.status, CatalogStorePriceContributionStatus.submitted);
  });

  test('authorization loss clears shop data and invokes boundary', () async {
    var losses = 0;
    final repository = _StorePriceRepository(
      failure: const CatalogContributionForbiddenException(),
    );
    final controller = _controller(
      repository,
      onAuthorizationLost: () async => losses++,
    );
    addTearDown(controller.dispose);

    await controller.loadConsent();
    controller.selectSource(_source());
    _preview(controller);
    controller.setExplicitConsent(true);
    await controller.submit();

    expect(controller.status, CatalogStorePriceContributionStatus.forbidden);
    expect(controller.source, isNull);
    expect(controller.observation, isNull);
    expect(controller.pendingSubmissionId, isNull);
    expect(losses, 1);
  });

  test('platform intent store persists only a hash slot and UUID', () async {
    final storage = _MemorySecureStorage();
    final store = PlatformCatalogSubmissionIntentStore(storage: storage);
    final key = CatalogSubmissionIntentKey.forPayload(
      type: CatalogContributionIntentType.storePrice,
      homeId: _homeId,
      sourceEntityId: _homeProductId,
      expectedConsentRevision: 4,
      payload: <String, Object?>{
        'storeName': 'Private local spelling',
        'price': '12.99',
      },
    );
    final intent = CatalogSubmissionIntent(
      key: key,
      submissionId: _submissionId,
    );
    final nextRevision = CatalogSubmissionIntentKey.forPayload(
      type: CatalogContributionIntentType.storePrice,
      homeId: _homeId,
      sourceEntityId: _homeProductId,
      expectedConsentRevision: 5,
      payload: <String, Object?>{
        'storeName': 'Private local spelling',
        'price': '12.99',
      },
    );

    await store.write(intent);
    final persisted = storage.values.entries.single;

    expect(
      persisted.key,
      startsWith('providentia.catalog-submission-intent.v1.'),
    );
    expect(persisted.key, isNot(contains(_homeId)));
    expect(persisted.key, isNot(contains('Private local spelling')));
    expect(persisted.value, _submissionId);
    expect(nextRevision.storageSlot, isNot(key.storageSlot));
    expect(await store.read(key), _submissionId);
    await store.delete(intent);
    expect(storage.values, isEmpty);
  });

  testWidgets('production route submits only a reviewed linked product price', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final repository = _StorePriceRepository();
    final inventory = InventoryController(
      repository: _InventoryRepository(<InventoryItem>[
        _linkedInventoryItem(),
        InventoryItem(
          id: _privateOnlyId,
          homeId: _homeId,
          canonicalName: 'Private flour',
          packSize: '2 kg bag',
          category: 'Baking',
          isHomeProduct: true,
        ),
      ]),
      homeId: _homeId,
    );
    final registry = ProductionProtectedRouteRegistry();
    addTearDown(inventory.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionCatalogStorePriceContributionRoute(
          consentRepository: repository,
          storePriceRepository: repository,
          inventoryController: inventory,
          homeId: _homeId,
          defaultCurrency: 'NAD',
          protectedRouteRegistry: registry,
          onAuthorizationLost: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('store-price-product')));
    await tester.pumpAndSettle();
    expect(find.text('Private flour · 2 kg bag'), findsNothing);
    await tester.tap(find.text('Rolled oats · 1 kg bag').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('store-price-store-name')),
      'Corner Shop',
    );
    await tester.enterText(
      find.byKey(const Key('store-price-store-location')),
      'Windhoek West',
    );
    await tester.enterText(find.byKey(const Key('store-price-price')), '12.99');
    tester.testTextInput.hide();
    final formList = find
        .descendant(
          of: find.byType(CatalogStorePriceContributionPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('store-price-review')),
      300,
      scrollable: formList,
    );
    await tester.tap(find.byKey(const Key('store-price-review')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('store-price-preview')),
      300,
      scrollable: formList,
    );

    expect(find.byKey(const Key('store-price-preview')), findsOneWidget);
    expect(repository.attemptedSubmissionIds, isEmpty);
    await tester.scrollUntilVisible(
      find.byKey(const Key('submit-store-price-contribution')),
      300,
      scrollable: formList,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('submit-store-price-contribution')),
          )
          .onPressed,
      isNull,
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('store-price-explicit-checkbox')),
      300,
      scrollable: formList,
    );
    await tester.tap(find.byKey(const Key('store-price-explicit-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit-store-price-contribution')));
    await tester.pumpAndSettle();

    expect(repository.attemptedSubmissionIds, hasLength(1));
    expect(find.text('Store price submitted for review'), findsOneWidget);

    registry.clearSensitiveState();
    await tester.pump();
    expect(find.text('Corner Shop'), findsNothing);
    expect(find.text('Store price submitted for review'), findsNothing);
  });
}

CatalogStorePriceContributionController _controller(
  _StorePriceRepository repository, {
  CatalogSubmissionIntentCoordinator? submissionIntents,
  Future<void> Function()? onAuthorizationLost,
}) => CatalogStorePriceContributionController(
  consentRepository: repository,
  service: CatalogStorePriceService(
    repository,
    clock: () => DateTime.utc(2026, 8, 25),
  ),
  homeId: _homeId,
  canContribute: true,
  submissionIntents: submissionIntents,
  submissionIdGenerator: () => _submissionId,
  onAuthorizationLost: onAuthorizationLost,
);

void _preview(CatalogStorePriceContributionController controller) {
  controller.preview(
    storeName: 'Corner Shop',
    storeLocation: 'Windhoek West',
    price: '12.99',
    currency: 'NAD',
    observedOn: DateTime.utc(2026, 8, 24),
  );
}

CatalogStorePriceSource _source() => CatalogStorePriceSource(
  homeId: _homeId,
  homeProductId: _homeProductId,
  productId: _productId,
  packId: _packId,
  displayName: 'Rolled oats',
  packText: '1 kg bag',
);

InventoryItem _linkedInventoryItem() => InventoryItem(
  id: _homeProductId,
  homeId: _homeId,
  canonicalName: 'Rolled oats',
  packSize: '1 kg bag',
  category: 'Breakfast cereal',
  isHomeProduct: true,
  productId: _productId,
  packId: _packId,
);

final class _StorePriceRepository
    implements CatalogSharingConsentRepository, CatalogStorePriceRepository {
  _StorePriceRepository({this.storePriceConsent = true, this.failure});

  final bool storePriceConsent;
  Exception? failure;
  final List<String> attemptedSubmissionIds = <String>[];

  @override
  Future<CatalogSharingConsent> loadConsent({required String homeId}) async =>
      CatalogSharingConsent(
        homeId: homeId,
        shareProductIdentity: false,
        shareProductImages: false,
        shareStorePrices: storePriceConsent,
        noticeVersion: CatalogSharingConsent.currentNoticeVersion,
        revision: storePriceConsent ? 4 : 0,
      );

  @override
  Future<CatalogContributionReceipt> submitStorePrice({
    required String submissionId,
    required int expectedConsentRevision,
    required CatalogStorePriceObservation observation,
  }) async {
    attemptedSubmissionIds.add(submissionId);
    expect(expectedConsentRevision, 4);
    final currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
    return CatalogContributionReceipt(
      homeId: observation.source.homeId,
      sourceEntityId: observation.source.homeProductId,
      contributionId: _contributionId,
      type: CatalogContributionType.storePrice,
      status: CatalogProposalStatus.pending,
      revision: 1,
    );
  }

  @override
  Future<CatalogSharingConsent> updateConsent({
    required String homeId,
    required CatalogSharingConsentUpdate update,
  }) => throw UnimplementedError();
}

final class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
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

const String _homeId = '01912345-6789-4abc-8def-0123456789ab';
const String _homeProductId = '01912345-6789-4abc-8def-1123456789ab';
const String _productId = '01912345-6789-4abc-8def-2123456789ab';
const String _packId = '01912345-6789-4abc-8def-3123456789ab';
const String _submissionId = '01912345-6789-4abc-8def-4123456789ab';
const String _otherSubmissionId = '01912345-6789-4abc-8def-5123456789ab';
const String _contributionId = '01912345-6789-4abc-8def-6123456789ab';
const String _privateOnlyId = '01912345-6789-4abc-8def-7123456789ab';
