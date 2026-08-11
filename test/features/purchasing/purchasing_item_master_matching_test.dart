import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_workspace.dart';

void main() {
  test(
    'verified offline item master ranks exact aliases and rejects foreign replacement',
    () async {
      final purchases = _MatchingPurchaseRepository();
      final inventory = _MatchingInventoryRepository();
      final controller = PurchasingController(
        repository: purchases,
        productCreationRepository: inventory,
        homeId: 'home-a',
        mayWrite: true,
      );
      addTearDown(() async {
        controller.dispose();
        await purchases.close();
        await inventory.close();
      });
      controller.start();
      purchases.emitDraft(rawDescription: 'ROYAL BASMATI', pack: '1 KG');
      inventory.emit(_itemMaster());
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.matchCandidates, hasLength(3));
      final rice = controller.state.matchCandidates.singleWhere(
        (candidate) => candidate.packId == 'pack-rice',
      );
      expect(rice.kind, PurchaseMatchCandidateKind.unselectedPublishedPack);
      expect(rice.name, 'Basmati rice');
      expect(rice.brand, 'Royal');
      expect(rice.category, 'Grains');
      expect(rice.packSize, '1 kg');
      expect(rice.aliases, contains('Royal Basmati'));

      final ranked = controller.rankedCandidatesFor(
        controller.state.capture!.lines.single,
      );
      expect(ranked.first.candidate.id, 'pack-rice');
      expect(ranked.first.basis, PurchaseMatchBasis.exactDescriptionAndPack);

      inventory.emit(<InventoryItem>[
        _item(
          id: 'foreign',
          homeId: 'home-b',
          name: 'Foreign private product',
          isHomeProduct: true,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.matchCandidates, hasLength(3));
      expect(controller.state.captureError, contains('access was rejected'));
    },
  );

  test(
    'catalog selection retries a lost approval without duplicate creation or pre-commit movement',
    () async {
      final purchases = _MatchingPurchaseRepository(
        throwAfterApprovalOnce: true,
      );
      final inventory = _MatchingInventoryRepository();
      final controller = PurchasingController(
        repository: purchases,
        productCreationRepository: inventory,
        homeId: 'home-a',
        mayWrite: true,
      );
      addTearDown(() async {
        controller.dispose();
        await purchases.close();
        await inventory.close();
      });
      controller.start();
      purchases.emitDraft(rawDescription: 'Royal Basmati', pack: '1 kg');
      inventory.emit(_itemMaster());
      await Future<void>.delayed(Duration.zero);

      expect(
        await controller.approveCandidate(
          lineId: 'line-a',
          candidateId: 'pack-rice',
        ),
        isFalse,
      );
      await Future<void>.delayed(Duration.zero);

      expect(inventory.catalogCreateCalls, 1);
      expect(purchases.approvalCalls, 1);
      expect(purchases.lastApprovedHomeProductId, 'home-product-new-catalog');
      expect(inventory.movementCalls, 0);
      expect(purchases.commitCalls, 0);
      expect(controller.state.capture?.reviewComplete, isTrue);

      expect(
        await controller.approveCandidate(
          lineId: 'line-a',
          candidateId: 'pack-rice',
        ),
        isTrue,
      );
      expect(inventory.catalogCreateCalls, 1);
      expect(purchases.approvalCalls, 1);
      expect(purchases.commitCalls, 0);

      expect(await controller.commitDraft(), isTrue);
      expect(purchases.commitCalls, 1);
      expect(inventory.movementCalls, 0);
      expect(await controller.commitDraft(), isTrue);
      expect(purchases.commitCalls, 2);
    },
  );

  test(
    'private product approval and unresolved choice stay home-private and explicit',
    () async {
      final purchases = _MatchingPurchaseRepository();
      final inventory = _MatchingInventoryRepository();
      final controller = PurchasingController(
        repository: purchases,
        productCreationRepository: inventory,
        homeId: 'home-a',
        mayWrite: true,
      );
      addTearDown(() async {
        controller.dispose();
        await purchases.close();
        await inventory.close();
      });
      controller.start();
      purchases.emitDraft(rawDescription: 'Local bakery loaf', pack: '600 g');
      inventory.emit(_itemMaster());
      await Future<void>.delayed(Duration.zero);

      expect(await controller.leaveLineUnresolved('line-a'), isTrue);
      expect(inventory.privateCreateCalls, 0);
      expect(purchases.approvalCalls, 0);
      expect(purchases.unresolvedCalls, 1);
      expect(purchases.commitCalls, 0);
      expect(controller.state.capture?.lines.single.unresolved, isTrue);
      expect(controller.state.capture?.reviewComplete, isTrue);
      expect(controller.state.captureNotice, contains('no price or stock'));

      expect(
        await controller.createPrivateProductAndApprove(
          lineId: 'line-a',
          privateName: 'Local bakery loaf',
          originalPackText: '600 g',
        ),
        isTrue,
      );

      expect(inventory.privateCreateCalls, 1);
      expect(inventory.catalogCreateCalls, 0);
      expect(purchases.lastApprovedHomeProductId, 'home-product-new-private');
      expect(purchases.commitCalls, 0);
      expect(inventory.movementCalls, 0);
    },
  );

  testWidgets(
    'workspace explains rank basis and ordinary catalog/private choices',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final purchases = _MatchingPurchaseRepository();
      final inventory = _MatchingInventoryRepository();
      final controller = PurchasingController(
        repository: purchases,
        productCreationRepository: inventory,
        homeId: 'home-a',
        mayWrite: true,
      );
      addTearDown(() async {
        controller.dispose();
        await purchases.close();
        await inventory.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      purchases.emitDraft(rawDescription: 'Royal Basmati', pack: '1 kg');
      inventory.emit(_itemMaster());
      await tester.pumpAndSettle();

      expect(
        find.text('Top suggestion: exact normalized description and pack'),
        findsOne,
      );
      expect(
        find.byKey(const Key('purchase-no-alias-publication-line-a')),
        findsOne,
      );
      expect(find.byKey(const Key('purchase-create-private-line-a')), findsOne);

      await tester.tap(find.byKey(const Key('purchase-line-match-line-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Basmati rice · 1 kg').last);
      await tester.pumpAndSettle();

      expect(find.text('Add pack to home and approve'), findsOne);
      expect(find.textContaining('Why this match: exact normalized'), findsOne);
      expect(purchases.commitCalls, 0);
      expect(inventory.movementCalls, 0);
    },
  );
}

List<InventoryItem> _itemMaster() => <InventoryItem>[
  _item(
    id: 'home-flour',
    name: 'Stone-ground flour',
    pack: '2 kg',
    category: 'Baking',
    brand: 'Mill House',
    aliases: const <String>['Flour stoneground'],
    isHomeProduct: true,
    productId: 'product-flour',
    packId: 'pack-flour',
  ),
  _item(
    id: 'pack-rice',
    name: 'Basmati rice',
    pack: '1 kg',
    category: 'Grains',
    brand: 'Royal',
    aliases: const <String>['Royal Basmati'],
    productId: 'product-rice',
    packId: 'pack-rice',
  ),
  // A stale duplicate pack must not produce a duplicate review choice.
  _item(
    id: 'stale-pack-rice',
    name: 'Basmati rice duplicate',
    pack: '1 kg',
    category: 'Grains',
    productId: 'product-rice',
    packId: 'pack-rice',
  ),
  _item(
    id: 'home-private',
    name: 'Neighbour jam',
    pack: 'jar',
    category: 'Uncategorized',
    isHomeProduct: true,
  ),
];

InventoryItem _item({
  required String id,
  String homeId = 'home-a',
  required String name,
  String pack = 'unit',
  String category = 'Uncategorized',
  String brand = '',
  List<String> aliases = const <String>[],
  bool isHomeProduct = false,
  String? productId,
  String? packId,
}) => InventoryItem(
  id: id,
  homeId: homeId,
  canonicalName: name,
  packSize: pack,
  category: category,
  brand: brand,
  aliases: aliases,
  isHomeProduct: isHomeProduct,
  productId: productId,
  packId: packId,
);

final class _MatchingInventoryRepository
    implements InventoryProductCreationRepository {
  final StreamController<List<InventoryItem>> _items =
      StreamController<List<InventoryItem>>.broadcast();
  int catalogCreateCalls = 0;
  int privateCreateCalls = 0;
  int movementCalls = 0;

  void emit(List<InventoryItem> items) => _items.add(items);

  @override
  bool get supportsCatalogHomeProductCreation => true;

  @override
  bool get supportsPrivateHomeProductCreation => true;

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) =>
      _items.stream;

  @override
  Future<InventoryProductCreationResult> createCatalogHomeProduct(
    CatalogHomeProductDraft draft,
  ) async {
    catalogCreateCalls++;
    return const InventoryProductCreationResult(
      homeProductId: 'home-product-new-catalog',
      revision: 1,
      disposition: InventoryProductCreationDisposition.queued,
    );
  }

  @override
  Future<InventoryProductCreationResult> createPrivateHomeProduct(
    PrivateHomeProductDraft draft,
  ) async {
    privateCreateCalls++;
    return const InventoryProductCreationResult(
      homeProductId: 'home-product-new-private',
      revision: 1,
      disposition: InventoryProductCreationDisposition.queued,
    );
  }

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) async {
    movementCalls++;
  }

  @override
  Future<void> saveCountSession(StockCountSession session) async {}

  @override
  Stream<StockCountSession?> watchActiveCountSession({
    required String homeId,
  }) => const Stream<StockCountSession?>.empty();

  Future<void> close() => _items.close();
}

final class _MatchingPurchaseRepository implements PurchaseCaptureRepository {
  _MatchingPurchaseRepository({this.throwAfterApprovalOnce = false});

  final bool throwAfterApprovalOnce;
  final StreamController<PurchaseReceiptCapture?> _captures =
      StreamController<PurchaseReceiptCapture?>.broadcast();
  PurchaseReceiptCapture? _current;
  int approvalCalls = 0;
  int unresolvedCalls = 0;
  int commitCalls = 0;
  String? lastApprovedHomeProductId;
  bool _approvalThrown = false;

  void emitDraft({required String rawDescription, required String pack}) {
    _current = PurchaseReceiptCapture(
      id: 'receipt-a',
      homeId: 'home-a',
      purchaseDate: DateTime.utc(2026, 8, 11),
      currency: 'NAD',
      notes: '',
      revision: 1,
      status: PurchaseReceiptStatus.draft,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: <PurchaseReceiptLineCapture>[
        PurchaseReceiptLineCapture(
          id: 'line-a',
          homeId: 'home-a',
          receiptId: 'receipt-a',
          rawDescription: rawDescription,
          originalPackText: pack,
          quantity: 1,
          lineTotal: Money(minorUnits: 1000, currency: 'NAD'),
          revision: 1,
          approvalStatus: PurchaseLineApprovalStatus.unreviewed,
          synchronizationState: PurchaseSynchronizationState.pending,
        ),
      ],
    );
    _captures.add(_current);
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
  }) => Stream<List<PurchaseMatchCandidate>>.value(
    const <PurchaseMatchCandidate>[],
  );

  @override
  Future<PurchaseMutationResult> approveReceiptLine({
    required String homeId,
    required String receiptId,
    required String lineId,
    required String homeProductId,
  }) async {
    approvalCalls++;
    lastApprovedHomeProductId = homeProductId;
    final current = _current!;
    final line = current.lines.single;
    _current = PurchaseReceiptCapture(
      id: current.id,
      homeId: homeId,
      purchaseDate: current.purchaseDate,
      currency: current.currency,
      notes: current.notes,
      revision: current.revision + 1,
      status: PurchaseReceiptStatus.draft,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: <PurchaseReceiptLineCapture>[
        PurchaseReceiptLineCapture(
          id: line.id,
          homeId: homeId,
          receiptId: receiptId,
          rawDescription: line.rawDescription,
          originalPackText: line.originalPackText,
          quantity: line.quantity,
          lineTotal: line.lineTotal,
          homeProductId: homeProductId,
          revision: line.revision + 1,
          approvalStatus: PurchaseLineApprovalStatus.approved,
          synchronizationState: PurchaseSynchronizationState.pending,
        ),
      ],
    );
    _captures.add(_current);
    if (throwAfterApprovalOnce && !_approvalThrown) {
      _approvalThrown = true;
      throw const PurchaseCaptureException(
        'The approval response was lost; retry safely.',
      );
    }
    return PurchaseMutationResult(
      entityId: lineId,
      revision: line.revision + 1,
      disposition: PurchaseMutationDisposition.queued,
    );
  }

  @override
  Future<PurchaseMutationResult> markReceiptLineUnresolved({
    required String homeId,
    required String receiptId,
    required String lineId,
  }) async {
    unresolvedCalls++;
    final current = _current!;
    final line = current.lines.single;
    _current = PurchaseReceiptCapture(
      id: current.id,
      homeId: homeId,
      purchaseDate: current.purchaseDate,
      currency: current.currency,
      notes: current.notes,
      revision: current.revision + 1,
      status: PurchaseReceiptStatus.draft,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: <PurchaseReceiptLineCapture>[
        PurchaseReceiptLineCapture(
          id: line.id,
          homeId: homeId,
          receiptId: receiptId,
          rawDescription: line.rawDescription,
          originalPackText: line.originalPackText,
          quantity: line.quantity,
          lineTotal: line.lineTotal,
          revision: line.revision + 1,
          approvalStatus: PurchaseLineApprovalStatus.unresolved,
          synchronizationState: PurchaseSynchronizationState.pending,
        ),
      ],
    );
    _captures.add(_current);
    return PurchaseMutationResult(
      entityId: lineId,
      revision: line.revision + 1,
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
    _current = PurchaseReceiptCapture(
      id: current.id,
      homeId: current.homeId,
      purchaseDate: current.purchaseDate,
      currency: current.currency,
      notes: current.notes,
      revision: current.revision + 1,
      status: PurchaseReceiptStatus.committed,
      synchronizationState: PurchaseSynchronizationState.pending,
      lines: current.lines,
    );
    _captures.add(_current);
    return PurchaseMutationResult(
      entityId: receiptId,
      revision: _current!.revision,
      disposition: PurchaseMutationDisposition.queued,
    );
  }

  @override
  Future<PurchaseMutationResult> createReceiptDraft(
    PurchaseReceiptDraftRequest request,
  ) => throw UnimplementedError();

  @override
  Future<PurchaseMutationResult> addReceiptLine(
    PurchaseReceiptLineRequest request,
  ) => throw UnimplementedError();

  Future<void> close() => _captures.close();
}
