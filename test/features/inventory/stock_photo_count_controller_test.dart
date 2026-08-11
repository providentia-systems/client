import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_provider_gateway.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/application/stock_photo_count_controller.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

void main() {
  test(
    'photo candidates create ordinary lines only and explicit close happens once',
    () async {
      final harness = _Harness();
      await harness.openCount();

      await harness.stock.selectPhotos();
      expect(harness.preparer.lastAssets, hasLength(2));
      expect(harness.stock.state.prepared!.orderedHashes, <String>[
        _hashA,
        _hashB,
      ]);
      expect(harness.repository.saved.single.lines, isEmpty);
      expect(harness.repository.movements, isEmpty);

      harness.stock.confirmTransmission();
      expect(harness.stock.state.consentConfirmed, isTrue);
      await harness.stock.extract();
      expect(harness.gateway.lastRequest!.targetId, harness.sessionId);
      expect(harness.stock.state.status, StockPhotoCountStatus.review);
      expect(harness.repository.saved.single.lines, isEmpty);

      harness.stock.matchCandidate('candidate-1', _item.id);
      harness.stock.setQuantity('candidate-1', 4);
      await harness.stock.confirmCandidate('candidate-1');

      final withLine = harness.repository.saved.last;
      expect(withLine.status, CountSessionStatus.open);
      expect(withLine.lines, hasLength(1));
      expect(withLine.lines.single.source, CountSource.photo);
      expect(withLine.lines.single.observedQuantity, 4);
      expect(harness.repository.movements, isEmpty);

      await harness.inventory.closeCount();
      expect(
        harness.repository.saved.where(
          (session) => session.status == CountSessionStatus.closed,
        ),
        hasLength(1),
      );
      expect(harness.repository.movements, isEmpty);
      expect(() => harness.inventory.closeCount(), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(harness.preparer.discarded, isNotEmpty);
      harness.dispose();
    },
  );

  test('exact selections are de-duplicated before ordered consent', () async {
    final harness = _Harness(assets: <AiMediaAsset>[_assetA, _assetA, _assetB]);
    await harness.openCount();

    await harness.stock.selectPhotos();

    expect(harness.preparer.lastAssets.map((asset) => asset.id), <String>[
      'source-a',
      'source-b',
    ]);
    harness.stock.confirmTransmission();
    expect(harness.stock.state.consentConfirmed, isTrue);
    expect(harness.stock.state.prepared!.orderedHashes, <String>[
      _hashA,
      _hashB,
    ]);
    harness.dispose();
  });

  test(
    'cancel creates no movement and clears ephemeral review bytes',
    () async {
      final harness = _Harness();
      await harness.openCount();
      await harness.stock.selectPhotos();

      await harness.inventory.cancelCount();
      await Future<void>.delayed(Duration.zero);

      expect(
        harness.repository.saved.last.status,
        CountSessionStatus.cancelled,
      );
      expect(harness.repository.movements, isEmpty);
      expect(harness.preparer.discarded, isNotEmpty);
      expect(harness.stock.state.status, StockPhotoCountStatus.idle);
      harness.dispose();
    },
  );

  test('authorization loss clears bytes and denies further review', () async {
    final harness = _Harness();
    await harness.openCount();
    await harness.stock.selectPhotos();

    await harness.stock.authorizationLost();

    expect(harness.preparer.discarded, isNotEmpty);
    expect(harness.stock.state.prepared, isNull);
    expect(harness.stock.state.status, StockPhotoCountStatus.accessDenied);
    expect(harness.repository.movements, isEmpty);
    harness.dispose();
  });

  for (final failurePoint in <String>['readiness', 'extraction']) {
    test(
      'gateway $failurePoint denial is terminal with no count mutation',
      () async {
        final harness = _Harness(
          readinessError: failurePoint == 'readiness'
              ? const AiGatewayAuthorizationDeniedException()
              : null,
          extractionError: failurePoint == 'extraction'
              ? const AiGatewayAuthorizationDeniedException()
              : null,
        );
        await harness.openCount();
        await harness.stock.selectPhotos();
        harness.stock.confirmTransmission();

        await harness.stock.extract();

        expect(harness.stock.state.status, StockPhotoCountStatus.accessDenied);
        expect(harness.stock.state.prepared, isNull);
        expect(harness.stock.confirmedConsent, isNull);
        expect(harness.preparer.hasPreparedBytes, isFalse);
        expect(harness.authorizationDenials, 1);
        expect(harness.repository.saved.last.lines, isEmpty);
        expect(harness.repository.movements, isEmpty);

        await harness.stock.extract();
        expect(harness.authorizationDenials, 1);
        expect(harness.repository.saved.last.lines, isEmpty);
        harness.dispose();
      },
    );
  }

  test('server route authorization denial clears prepared photos', () async {
    final harness = _Harness(
      loadRouteError: const AiServerException(
        AiServerFailureKind.authorizationDenied,
      ),
    );
    await harness.openCount();

    await harness.stock.selectPhotos();

    expect(harness.stock.state.status, StockPhotoCountStatus.accessDenied);
    expect(harness.preparer.hasPreparedBytes, isFalse);
    expect(harness.authorizationDenials, 1);
    expect(harness.repository.saved.last.lines, isEmpty);
    expect(harness.repository.movements, isEmpty);
    harness.dispose();
  });

  test(
    'duplicate cross-image candidates cannot create two count lines',
    () async {
      final harness = _Harness(duplicateCandidates: true);
      await harness.openCount();
      await harness.stock.selectPhotos();
      harness.stock.confirmTransmission();
      await harness.stock.extract();

      expect(harness.stock.state.candidates, hasLength(1));
      expect(
        harness.stock.state.safeMessage,
        contains('overlapping candidate removed'),
      );
      harness.stock.matchCandidate('candidate-1', _item.id);
      harness.stock.setQuantity('candidate-1', 2);
      await harness.stock.confirmCandidate('candidate-1');

      expect(harness.repository.saved.last.lines, hasLength(1));
      harness.dispose();
    },
  );

  test(
    'home-switch disposal clears previews and blocks later candidate writes',
    () async {
      final harness = _Harness();
      await harness.openCount();
      await harness.stock.selectPhotos();
      harness.stock.confirmTransmission();
      await harness.stock.extract();
      harness.stock.matchCandidate('candidate-1', _item.id);
      harness.stock.setQuantity('candidate-1', 3);
      final writesBeforeDispose = harness.repository.saved.length;

      harness.stock.dispose();
      await Future<void>.delayed(Duration.zero);
      await harness.stock.confirmCandidate('candidate-1');

      expect(harness.preparer.hasPreparedBytes, isFalse);
      expect(harness.repository.saved, hasLength(writesBeforeDispose));
      harness.inventory.dispose();
      harness.repository.dispose();
    },
  );

  test(
    'strict-local stock route bypasses server gateway and binds consent',
    () async {
      final repository = _InventoryRepository();
      final preparer = _MediaPreparer();
      var nextId = 0;
      final inventory = InventoryController(
        repository: repository,
        homeId: 'home-1',
        idGenerator: () => 'id-${++nextId}',
        clock: () => DateTime.utc(2026, 8, 11),
      )..start();
      repository.emitItems(<InventoryItem>[_item]);
      await inventory.startCount(locationId: 'primary');
      await Future<void>.delayed(Duration.zero);
      final transport = _LocalTransport();
      final localGateway = StrictLocalProviderGateway(
        resolver: const _LocalResolver(),
        transport: transport,
        mediaReader: preparer,
      );
      final route = StockPhotoAiRoute(
        profile: _localProfile,
        gateway: localGateway,
        privacyMode: AiPrivacyMode.strictLocal,
      );
      final stock = StockPhotoCountController(
        homeId: 'home-1',
        inventory: inventory,
        mediaPreparation: preparer,
        mediaReader: preparer,
        pickAssets: () async => <AiMediaAsset>[_assetA, _assetB],
        loadRoute: () async => route,
        idGenerator: () => 'id-${++nextId}',
        clock: () => DateTime.utc(2026, 8, 11),
      );

      await stock.selectPhotos();
      expect(stock.state.privacyMode, AiPrivacyMode.strictLocal);
      expect(stock.state.provider?.endpoint?.origin, 'http://127.0.0.1:11434');
      stock.confirmTransmission();
      final consent = stock.confirmedConsent!;
      expect(consent.providerId, _localProfile.id);
      expect(consent.providerRevision, _localProfile.revision);
      expect(consent.orderedMediaHashes, <String>[_hashA, _hashB]);

      await stock.extract();
      expect(stock.state.status, StockPhotoCountStatus.review);
      expect(transport.paths, <String>['/api/tags', '/api/show', '/api/chat']);
      expect(
        transport.paths.any((path) => path.startsWith('/api/v1')),
        isFalse,
      );
      final messages = transport.chatBody!['messages']! as List<Object?>;
      final message = messages.single! as Map<String, Object?>;
      expect(message['images'], <String>[
        base64Encode(List<int>.filled(16, 1)),
        base64Encode(List<int>.filled(16, 2)),
      ]);
      expect(repository.movements, isEmpty);
      stock.dispose();
      inventory.dispose();
      repository.dispose();
    },
  );

  test('route/mode mismatch fails before gateway transmission', () async {
    final gateway = _Gateway(route: AiGatewayRoute.directStrictLocal);
    final harness = _Harness(
      route: StockPhotoAiRoute(
        profile: _localProfile,
        gateway: gateway,
        privacyMode: AiPrivacyMode.serverProxyCloud,
      ),
    );
    await harness.openCount();

    await harness.stock.selectPhotos();

    expect(harness.stock.state.status, StockPhotoCountStatus.failed);
    expect(gateway.lastRequest, isNull);
    harness.dispose();
  });

  test(
    'offline full item-master search adds a published pack before counting',
    () async {
      final harness = _Harness();
      harness.repository.emitItems(<InventoryItem>[
        _item,
        _catalogItem,
        _privateItem,
      ]);
      await harness.openReview();

      expect(
        harness.stock.searchItems('red bean').map((item) => item.id),
        contains(_catalogItem.id),
      );
      expect(
        harness.stock.searchItems('cupboard').map((item) => item.id),
        contains(_privateItem.id),
      );
      await harness.stock.selectCandidateItem('candidate-1', _catalogItem.id);

      expect(harness.repository.catalogCreates, 1);
      final review = harness.stock.state.candidates.single;
      expect(review.homeProductId, 'catalog-home-1');
      harness.stock.setQuantity('candidate-1', 3);
      await harness.stock.confirmCandidate('candidate-1');

      expect(
        harness.repository.saved.last.lines.single.itemId,
        'catalog-home-1',
      );
      expect(harness.repository.movements, isEmpty);
      harness.dispose();
    },
  );

  test('private candidate uses ordinary optimistic product creation', () async {
    final harness = _Harness();
    await harness.openReview();

    await harness.stock.createPrivateProductForCandidate(
      candidateId: 'candidate-1',
      privateName: 'Family rice jar',
      packText: 'large jar',
    );

    expect(harness.repository.privateCreates, 1);
    expect(
      harness.stock.state.candidates.single.homeProductId,
      'private-home-1',
    );
    harness.stock.setQuantity('candidate-1', 1);
    await harness.stock.confirmCandidate('candidate-1');
    expect(harness.repository.saved.last.lines.single.itemId, 'private-home-1');
    expect(harness.repository.movements, isEmpty);
    harness.dispose();
  });

  test(
    'lost product and count responses resolve projections without replay duplicates',
    () async {
      final harness = _Harness();
      harness.repository.emitItems(<InventoryItem>[_item, _catalogItem]);
      harness.repository.throwAfterCatalogProjection = true;
      await harness.openReview();

      await harness.stock.selectCandidateItem('candidate-1', _catalogItem.id);
      expect(harness.repository.catalogCreates, 1);
      expect(
        harness.stock.state.candidates.single.homeProductId,
        'catalog-home-1',
      );

      harness.stock.setQuantity('candidate-1', 2);
      harness.repository.throwAfterNextOpenSessionProjection = true;
      await harness.stock.confirmCandidate('candidate-1');
      await harness.stock.confirmCandidate('candidate-1');

      final projectedLines = harness.repository.saved
          .expand((session) => session.lines)
          .where((line) => line.photoId == 'proposal-1:candidate-1');
      expect(projectedLines, hasLength(1));
      expect(harness.stock.state.candidates.single.counted, isTrue);
      expect(harness.repository.movements, isEmpty);
      harness.dispose();
    },
  );

  test(
    'uncounted item-master matches sort before confirmed products',
    () async {
      final harness = _Harness();
      harness.repository.emitItems(<InventoryItem>[_item, _laterHomeItem]);
      await harness.openReview();
      harness.stock.matchCandidate('candidate-1', _item.id);
      harness.stock.setQuantity('candidate-1', 1);
      await harness.stock.confirmCandidate('candidate-1');

      expect(harness.stock.searchItems().map((item) => item.id), <String>[
        _laterHomeItem.id,
        _item.id,
      ]);
      harness.dispose();
    },
  );

  test('forged cross-home item-master selection cannot add or count', () async {
    final harness = _Harness();
    await harness.openReview();
    harness.repository.emitItems(<InventoryItem>[_item, _crossHomeCatalogItem]);
    await Future<void>.delayed(Duration.zero);

    await harness.stock.selectCandidateItem(
      'candidate-1',
      _crossHomeCatalogItem.id,
    );

    expect(harness.repository.catalogCreates, 0);
    expect(harness.stock.state.candidates.single.homeProductId, isNull);
    expect(harness.repository.saved.last.lines, isEmpty);
    expect(harness.repository.movements, isEmpty);
    harness.dispose();
  });

  test('two photo candidates cannot double-count one home product', () async {
    final harness = _Harness(distinctCandidates: true);
    await harness.openReview();
    expect(harness.stock.state.candidates, hasLength(2));
    for (final id in <String>['candidate-1', 'candidate-2']) {
      harness.stock.matchCandidate(id, _item.id);
      harness.stock.setQuantity(id, 2);
    }

    await harness.stock.confirmCandidate('candidate-1');
    await harness.stock.confirmCandidate('candidate-2');

    expect(harness.repository.saved.last.lines, hasLength(1));
    expect(
      harness.stock.state.safeMessage,
      'This product is already counted in the open session.',
    );
    expect(harness.repository.movements, isEmpty);
    harness.dispose();
  });
}

final class _Harness {
  _Harness({
    List<AiMediaAsset>? assets,
    bool duplicateCandidates = false,
    bool distinctCandidates = false,
    StockPhotoAiRoute? route,
    Object? readinessError,
    Object? extractionError,
    Object? loadRouteError,
  }) : repository = _InventoryRepository(),
       preparer = _MediaPreparer(),
       gateway = route?.gateway is _Gateway
           ? route!.gateway as _Gateway
           : _Gateway(
               duplicateCandidates: duplicateCandidates,
               distinctCandidates: distinctCandidates,
               readinessError: readinessError,
               extractionError: extractionError,
             ),
       _assets = assets ?? <AiMediaAsset>[_assetA, _assetB] {
    var nextId = 0;
    String id() => 'id-${++nextId}';
    inventory = InventoryController(
      repository: repository,
      homeId: 'home-1',
      idGenerator: id,
      clock: () => DateTime.utc(2026, 8, 11),
    )..start();
    repository.emitItems(<InventoryItem>[_item]);
    stock = route == null
        ? StockPhotoCountController(
            homeId: 'home-1',
            inventory: inventory,
            mediaPreparation: preparer,
            mediaReader: preparer,
            gateway: gateway,
            pickAssets: () async => _assets,
            loadProvider: () async {
              if (loadRouteError case final error?) throw error;
              return _profile;
            },
            idGenerator: id,
            onAuthorizationDenied: () async => authorizationDenials++,
            clock: () => DateTime.utc(2026, 8, 11),
          )
        : StockPhotoCountController(
            homeId: 'home-1',
            inventory: inventory,
            mediaPreparation: preparer,
            mediaReader: preparer,
            pickAssets: () async => _assets,
            loadRoute: () async => route,
            idGenerator: id,
            onAuthorizationDenied: () async => authorizationDenials++,
            clock: () => DateTime.utc(2026, 8, 11),
          );
  }

  final _InventoryRepository repository;
  final _MediaPreparer preparer;
  final _Gateway gateway;
  final List<AiMediaAsset> _assets;
  late final InventoryController inventory;
  late final StockPhotoCountController stock;
  int authorizationDenials = 0;

  String get sessionId => repository.saved.first.id;

  Future<void> openCount() async {
    await inventory.startCount(locationId: 'primary');
    await Future<void>.delayed(Duration.zero);
    expect(inventory.state.activeSession, isNotNull);
  }

  Future<void> openReview() async {
    await openCount();
    await stock.selectPhotos();
    stock.confirmTransmission();
    await stock.extract();
    expect(stock.state.status, StockPhotoCountStatus.review);
  }

  void dispose() {
    stock.dispose();
    inventory.dispose();
    repository.dispose();
  }
}

final class _InventoryRepository implements InventoryProductCreationRepository {
  final _items = StreamController<List<InventoryItem>>.broadcast();
  final _sessions = StreamController<StockCountSession?>.broadcast();
  final List<StockCountSession> saved = <StockCountSession>[];
  final List<StockMovement> movements = <StockMovement>[];
  List<InventoryItem> currentItems = <InventoryItem>[];
  int catalogCreates = 0;
  int privateCreates = 0;
  bool throwAfterCatalogProjection = false;
  bool throwAfterPrivateProjection = false;
  bool throwAfterNextOpenSessionProjection = false;

  void emitItems(List<InventoryItem> items) {
    currentItems = List<InventoryItem>.of(items);
    _items.add(List<InventoryItem>.unmodifiable(currentItems));
  }

  @override
  bool get supportsCatalogHomeProductCreation => true;

  @override
  bool get supportsPrivateHomeProductCreation => true;

  @override
  Future<InventoryProductCreationResult> createCatalogHomeProduct(
    CatalogHomeProductDraft draft,
  ) async {
    if (draft.homeId != 'home-1') {
      throw const InventoryProductCreationException(
        'Cross-home catalog selection was rejected.',
      );
    }
    final existing = currentItems
        .where(
          (item) =>
              item.isHomeProduct &&
              item.productId == draft.productId &&
              item.packId == draft.packId,
        )
        .firstOrNull;
    if (existing != null) {
      throw const InventoryProductCreationException(
        'This catalog pack is already selected.',
      );
    }
    catalogCreates++;
    final id = 'catalog-home-$catalogCreates';
    final projected = InventoryItem(
      id: id,
      homeId: draft.homeId,
      canonicalName: draft.canonicalName,
      packSize: draft.packSize,
      category: draft.category,
      brand: draft.brand,
      aliases: draft.aliases,
      isHomeProduct: true,
      productId: draft.productId,
      packId: draft.packId,
    );
    emitItems(<InventoryItem>[
      ...currentItems.where(
        (item) =>
            item.productId != draft.productId || item.packId != draft.packId,
      ),
      projected,
    ]);
    if (throwAfterCatalogProjection) {
      throw StateError('simulated lost catalog response');
    }
    return InventoryProductCreationResult(
      homeProductId: id,
      revision: 1,
      disposition: InventoryProductCreationDisposition.queued,
    );
  }

  @override
  Future<InventoryProductCreationResult> createPrivateHomeProduct(
    PrivateHomeProductDraft draft,
  ) async {
    if (draft.homeId != 'home-1') {
      throw const InventoryProductCreationException(
        'Cross-home private creation was rejected.',
      );
    }
    privateCreates++;
    final id = 'private-home-$privateCreates';
    final projected = InventoryItem(
      id: id,
      homeId: draft.homeId,
      canonicalName: draft.privateName.trim(),
      packSize: draft.originalPackText?.trim().isNotEmpty == true
          ? draft.originalPackText!.trim()
          : 'Unspecified pack',
      category: 'Uncategorized',
      isHomeProduct: true,
    );
    emitItems(<InventoryItem>[...currentItems, projected]);
    if (throwAfterPrivateProjection) {
      throw StateError('simulated lost private response');
    }
    return InventoryProductCreationResult(
      homeProductId: id,
      revision: 1,
      disposition: InventoryProductCreationDisposition.queued,
    );
  }

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
      _items.stream;

  @override
  Stream<StockCountSession?> watchActiveCountSession({
    required String homeId,
  }) => _sessions.stream;

  @override
  Future<void> saveCountSession(StockCountSession session) async {
    saved.add(session);
    _sessions.add(session.status == CountSessionStatus.open ? session : null);
    if (session.status == CountSessionStatus.open &&
        session.lines.isNotEmpty &&
        throwAfterNextOpenSessionProjection) {
      throwAfterNextOpenSessionProjection = false;
      throw StateError('simulated lost count response');
    }
  }

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) async {
    if (movement != null) movements.add(movement);
  }

  void dispose() {
    _items.close();
    _sessions.close();
  }
}

final class _MediaPreparer
    implements AiMediaPreparationPort, PreparedMediaByteReader {
  List<AiMediaAsset> lastAssets = const <AiMediaAsset>[];
  final List<PreparedMediaBatch> discarded = <PreparedMediaBatch>[];
  bool hasPreparedBytes = false;

  @override
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) async {
    lastAssets = List<AiMediaAsset>.of(assets);
    hasPreparedBytes = true;
    return PreparedMediaBatch(
      id: 'batch-1',
      homeId: homeId,
      purpose: purpose,
      media: assets
          .map((asset) => asset.id == 'source-a' ? _preparedA : _preparedB)
          .toList(growable: false),
    );
  }

  @override
  Future<void> discard(PreparedMediaBatch batch) async {
    discarded.add(batch);
    hasPreparedBytes = false;
  }

  @override
  Future<Uint8List> read(PreparedAiMedia media) async => Uint8List.fromList(
    List<int>.filled(
      media.byteLength,
      media.sourceMediaId == 'source-a' ? 1 : 2,
    ),
  );
}

final class _Gateway implements AiProviderGateway {
  _Gateway({
    this.duplicateCandidates = false,
    this.distinctCandidates = false,
    this.route = AiGatewayRoute.serverProxyCloud,
    this.readinessError,
    this.extractionError,
  });

  final bool duplicateCandidates;
  final bool distinctCandidates;
  final Object? readinessError;
  final Object? extractionError;
  @override
  final AiGatewayRoute route;
  AiExtractionRequest? lastRequest;

  @override
  Future<AiGatewayReadiness> readiness(AiProviderProfile profile) async {
    if (readinessError case final error?) throw error;
    return const AiGatewayReadiness.ready();
  }

  @override
  Future<AiExtractionResult<ReceiptProposal>> extractReceipt(
    AiExtractionRequest request,
  ) => throw UnimplementedError();

  @override
  Future<AiExtractionResult<StockPhotoProposal>> extractStockPhoto(
    AiExtractionRequest request,
  ) async {
    lastRequest = request;
    if (extractionError case final error?) throw error;
    return AiExtractionSuccess<StockPhotoProposal>(
      proposal: StockPhotoProposal(
        id: 'proposal-1',
        runId: request.runId,
        schemaVersion: request.schemaVersion,
        classification: StockImageClassification.pantryStock,
        candidates: <StockCandidateProposal>[
          _candidate('candidate-1'),
          if (duplicateCandidates) _candidate('candidate-2'),
          if (distinctCandidates) _candidate('candidate-2', name: 'Beans'),
        ],
        warnings: const <String>[],
      ),
      metadata: AiRunMetadata(
        providerKind: request.provider.kind,
        model: request.provider.model,
        protocol: request.provider.protocol,
        promptVersion: request.promptVersion,
        schemaVersion: request.schemaVersion,
        processingTime: Duration.zero,
      ),
    );
  }

  StockCandidateProposal _candidate(String id, {String name = 'Rice'}) =>
      StockCandidateProposal(
        candidateId: id,
        brand: const ExtractedField<String>(value: 'Brand', confidence: 0.9),
        productName: ExtractedField<String>(value: name, confidence: 0.9),
        variant: const ExtractedField<String>(value: null, confidence: 0),
        packDescription: const ExtractedField<String>(
          value: '1 kg',
          confidence: 0.9,
        ),
        quantityMinimum: 2,
        quantityMaximum: 2,
        confidence: 0.9,
        warnings: const <String>[],
      );
}

final InventoryItem _item = InventoryItem(
  id: 'home-product-1',
  homeId: 'home-1',
  canonicalName: 'Rice',
  packSize: '1 kg',
  category: 'Pantry',
  isHomeProduct: true,
  productId: 'product-1',
  packId: 'pack-1',
);

final InventoryItem _catalogItem = InventoryItem(
  id: 'catalog-pack-2',
  homeId: 'home-1',
  canonicalName: 'Red beans',
  packSize: '410 g',
  category: 'Pantry',
  brand: 'Harvest',
  aliases: const <String>['kidney beans'],
  productId: 'product-2',
  packId: 'pack-2',
);

final InventoryItem _privateItem = InventoryItem(
  id: 'private-existing',
  homeId: 'home-1',
  canonicalName: 'Cupboard mix',
  packSize: 'one jar',
  category: 'Private',
  isHomeProduct: true,
);

final InventoryItem _laterHomeItem = InventoryItem(
  id: 'home-product-z',
  homeId: 'home-1',
  canonicalName: 'Zucchini jars',
  packSize: '500 g',
  category: 'Pantry',
  isHomeProduct: true,
);

final InventoryItem _crossHomeCatalogItem = InventoryItem(
  id: 'forged-catalog',
  homeId: 'home-2',
  canonicalName: 'Forged product',
  packSize: '1 kg',
  category: 'Pantry',
  productId: 'forged-product',
  packId: 'forged-pack',
);

final AiMediaAsset _assetA = AiMediaAsset(
  id: 'source-a',
  homeId: 'home-1',
  localReference: 'registered://a.jpg',
  purpose: AiExtractionKind.stockPhoto,
  mimeType: 'image/jpeg',
  byteLength: 16,
  createdAt: DateTime.utc(2026, 8, 11),
);

final AiMediaAsset _assetB = AiMediaAsset(
  id: 'source-b',
  homeId: 'home-1',
  localReference: 'registered://b.jpg',
  purpose: AiExtractionKind.stockPhoto,
  mimeType: 'image/jpeg',
  byteLength: 16,
  createdAt: DateTime.utc(2026, 8, 11),
);

const String _hashA =
    'cc8cd41cef907c4d216069122c4b89936211361f9050a717a1e37ad1862e952f';
const String _hashB =
    '292afde3b64e6636d68f1120d9242f1f85e38ef7bf306e4407c2303eb63791ef';

const PreparedAiMedia _preparedA = PreparedAiMedia(
  sourceMediaId: 'source-a',
  ephemeralReference: 'ephemeral://a',
  previewReference: 'ephemeral://a',
  sha256: _hashA,
  mimeType: 'image/jpeg',
  byteLength: 16,
  width: 100,
  height: 100,
  pageIndex: 0,
);

const PreparedAiMedia _preparedB = PreparedAiMedia(
  sourceMediaId: 'source-b',
  ephemeralReference: 'ephemeral://b',
  previewReference: 'ephemeral://b',
  sha256: _hashB,
  mimeType: 'image/jpeg',
  byteLength: 16,
  width: 100,
  height: 100,
  pageIndex: 1,
);

final AiProviderProfile _profile = AiProviderProfile(
  id: 'profile-1',
  homeId: 'home-1',
  displayName: 'Household vision',
  kind: AiProviderKind.openAi,
  transport: AiTransport.serverProxy,
  protocol: AiEndpointProtocol.openAiResponses,
  model: 'vision-production',
  capabilities: const <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
    AiCapability.multiImage,
    AiCapability.storeFalse,
  },
  availability: AiProviderAvailability.available,
  credentialConfigured: true,
);

final AiProviderProfile _localProfile = AiProviderProfile(
  id: 'local-profile-1',
  homeId: 'home-1',
  displayName: 'Kitchen Ollama',
  kind: AiProviderKind.ollama,
  transport: AiTransport.directNative,
  protocol: AiEndpointProtocol.ollamaChat,
  endpoint: Uri.parse('http://127.0.0.1:11434'),
  model: 'llava:latest',
  capabilities: const <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
    AiCapability.multiImage,
  },
  availability: AiProviderAvailability.available,
  strictLocalAttestedAt: DateTime.utc(2026, 8, 11),
  revision: 3,
);

final class _LocalResolver implements StrictLocalNameResolver {
  const _LocalResolver();

  @override
  Future<List<String>> resolve(
    String host, {
    required Duration timeout,
  }) async => const <String>[];
}

final class _LocalTransport implements StrictLocalHttpTransport {
  final List<String> paths = <String>[];
  Map<String, Object?>? chatBody;

  @override
  bool get blocksRedirects => true;

  @override
  bool get exposesConnectedPeerAddress => true;

  @override
  Future<StrictLocalTransportResponse> send(
    StrictLocalTransportRequest request,
  ) async {
    paths.add(request.uri.path);
    final body = switch (request.uri.path) {
      '/api/tags' => <String, Object?>{
        'models': <Object?>[
          <String, Object?>{'name': 'llava:latest'},
        ],
      },
      '/api/show' => <String, Object?>{
        'capabilities': <Object?>['vision'],
      },
      '/api/chat' => () {
        chatBody =
            jsonDecode(utf8.decode(request.body!)) as Map<String, Object?>;
        return <String, Object?>{
          'message': <String, Object?>{
            'content': jsonEncode(<String, Object?>{
              'schemaVersion': 'stock-photo-v1',
              'classification': 'pantry_stock',
              'candidates': <Object?>[],
              'warnings': <Object?>[],
            }),
          },
        };
      }(),
      _ => throw StateError('Unexpected local path ${request.uri.path}'),
    };
    return StrictLocalTransportResponse(
      statusCode: 200,
      body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
      finalUri: request.uri,
      connectedPeerAddress: '127.0.0.1',
      redirected: false,
    );
  }
}
