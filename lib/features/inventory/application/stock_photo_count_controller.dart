import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';
import 'package:providentia/features/ai_integration/domain/proposal_validation.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

enum StockPhotoCountStatus {
  idle,
  preparing,
  awaitingConsent,
  processing,
  review,
  failed,
  accessDenied,
}

final class StockPhotoCandidateReview {
  const StockPhotoCandidateReview({
    required this.proposal,
    this.homeProductId,
    this.quantity,
    this.counted = false,
  });

  final StockCandidateProposal proposal;
  final String? homeProductId;
  final double? quantity;
  final bool counted;

  StockPhotoCandidateReview copyWith({
    String? homeProductId,
    bool clearHomeProduct = false,
    double? quantity,
    bool clearQuantity = false,
    bool? counted,
  }) => StockPhotoCandidateReview(
    proposal: proposal,
    homeProductId: clearHomeProduct
        ? null
        : (homeProductId ?? this.homeProductId),
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    counted: counted ?? this.counted,
  );
}

final class StockPhotoCountState {
  StockPhotoCountState({
    required this.status,
    this.prepared,
    this.provider,
    this.privacyMode,
    this.proposal,
    this.consentConfirmed = false,
    this.candidateBusyId,
    this.safeMessage,
    List<StockPhotoCandidateReview> candidates =
        const <StockPhotoCandidateReview>[],
  }) : candidates = UnmodifiableListView<StockPhotoCandidateReview>(
         List<StockPhotoCandidateReview>.of(candidates),
       );

  const StockPhotoCountState.idle()
    : status = StockPhotoCountStatus.idle,
      prepared = null,
      provider = null,
      privacyMode = null,
      proposal = null,
      consentConfirmed = false,
      candidateBusyId = null,
      safeMessage = null,
      candidates = const <StockPhotoCandidateReview>[];

  final StockPhotoCountStatus status;
  final PreparedMediaBatch? prepared;
  final AiProviderProfile? provider;
  final AiPrivacyMode? privacyMode;
  final StockPhotoProposal? proposal;
  final bool consentConfirmed;
  final String? candidateBusyId;
  final String? safeMessage;
  final List<StockPhotoCandidateReview> candidates;

  List<StockPhotoCandidateReview> get uncountedFirst =>
      List<StockPhotoCandidateReview>.unmodifiable(<StockPhotoCandidateReview>[
        ...candidates.where((candidate) => !candidate.counted),
        ...candidates.where((candidate) => candidate.counted),
      ]);
}

typedef StockPhotoAssetPicker = Future<List<AiMediaAsset>> Function();
typedef StockPhotoProviderLoader = Future<AiProviderProfile> Function();
typedef StockPhotoAiRouteLoader = Future<StockPhotoAiRoute> Function();

final class StockPhotoAiRoute {
  const StockPhotoAiRoute({
    required this.profile,
    required this.gateway,
    required this.privacyMode,
  });

  final AiProviderProfile profile;
  final AiProviderGateway gateway;
  final AiPrivacyMode privacyMode;

  void validate() {
    final expected = switch (gateway.route) {
      AiGatewayRoute.serverProxyCloud => AiPrivacyMode.serverProxyCloud,
      AiGatewayRoute.directStrictLocal => AiPrivacyMode.strictLocal,
    };
    if (privacyMode != expected ||
        privacyMode == AiPrivacyMode.serverProxyCloud &&
            profile.transport != AiTransport.serverProxy ||
        privacyMode == AiPrivacyMode.strictLocal &&
            profile.transport != AiTransport.directNative) {
      throw const AiPolicyViolation(
        code: 'ai_route_mismatch',
        safeMessage: 'The selected AI privacy route is not configured safely.',
      );
    }
  }
}

/// Coordinates photo intelligence around an already-open ordinary stock count.
/// Prepared bytes remain ephemeral through review and every durable write is
/// delegated to [InventoryController.recordPhotoCount].
final class StockPhotoCountController extends ChangeNotifier {
  factory StockPhotoCountController({
    required String homeId,
    required InventoryController inventory,
    required AiMediaPreparationPort mediaPreparation,
    required PreparedMediaByteReader mediaReader,
    AiProviderGateway? gateway,
    required StockPhotoAssetPicker pickAssets,
    StockPhotoProviderLoader? loadProvider,
    StockPhotoAiRouteLoader? loadRoute,
    required String Function() idGenerator,
    Future<void> Function()? onAuthorizationDenied,
    DateTime Function()? clock,
    AiPrivacyPolicy policy = const AiPrivacyPolicy(),
  }) {
    final effectiveLoader =
        loadRoute ??
        (gateway != null && loadProvider != null
            ? () async => StockPhotoAiRoute(
                profile: await loadProvider(),
                gateway: gateway,
                privacyMode: switch (gateway.route) {
                  AiGatewayRoute.serverProxyCloud =>
                    AiPrivacyMode.serverProxyCloud,
                  AiGatewayRoute.directStrictLocal => AiPrivacyMode.strictLocal,
                },
              )
            : null);
    if (effectiveLoader == null) {
      throw ArgumentError('Provide loadRoute or gateway with loadProvider.');
    }
    return StockPhotoCountController._(
      homeId: homeId,
      inventory: inventory,
      mediaPreparation: mediaPreparation,
      mediaReader: mediaReader,
      pickAssets: pickAssets,
      loadRoute: effectiveLoader,
      idGenerator: idGenerator,
      onAuthorizationDenied: onAuthorizationDenied,
      clock: clock ?? DateTime.now,
      policy: policy,
    );
  }

  StockPhotoCountController._({
    required this.homeId,
    required InventoryController inventory,
    required this._mediaPreparation,
    required this._mediaReader,
    required this._pickAssets,
    required this._loadRoute,
    required this._idGenerator,
    required this._onAuthorizationDenied,
    required this._clock,
    required this._policy,
  }) : _inventory = inventory {
    if (homeId.trim().isEmpty || inventory.homeId != homeId) {
      throw ArgumentError('Stock-photo workflow crossed a home boundary.');
    }
    _inventory.addListener(_handleInventoryChange);
  }

  final String homeId;
  final InventoryController _inventory;
  final AiMediaPreparationPort _mediaPreparation;
  final PreparedMediaByteReader _mediaReader;
  final StockPhotoAssetPicker _pickAssets;
  final StockPhotoAiRouteLoader _loadRoute;
  final String Function() _idGenerator;
  final Future<void> Function()? _onAuthorizationDenied;
  final DateTime Function() _clock;
  final AiPrivacyPolicy _policy;
  StockPhotoCountState _state = const StockPhotoCountState.idle();
  AiConsent? _consent;
  StockPhotoAiRoute? _activeRoute;
  final Set<String> _pendingCandidateIds = <String>{};
  final Set<String> _pendingHomeProductIds = <String>{};
  int _accessEpoch = 0;
  bool _disposed = false;
  bool _authorizationDenialReported = false;

  StockPhotoCountState get state => _state;
  AiConsent? get confirmedConsent => _consent;
  bool get canCreatePrivateProduct => _inventory.canCreatePrivateProduct;
  bool get canAddCatalogProduct => _inventory.canAddCatalogProduct;

  List<InventoryItem> get homeProducts =>
      searchItems().where((item) => item.isHomeProduct).toList(growable: false);

  /// Searches the complete home-authorized offline item master, including
  /// existing private/home products and published packs that have not yet been
  /// selected for the household. Items not already confirmed in this count are
  /// deliberately shown first.
  List<InventoryItem> searchItems([String query = '']) {
    final normalizedQuery = _normalizeSearch(query);
    final confirmed =
        _inventory.state.activeSession?.confirmedLines
            .map((line) => line.itemId)
            .toSet() ??
        const <String>{};
    final items = _inventory.state.items
        .where(
          (item) =>
              item.homeId == homeId &&
              (normalizedQuery.isEmpty ||
                  <String>[
                    item.canonicalName,
                    item.brand,
                    item.packSize,
                    item.category,
                    ...item.aliases,
                  ].any(
                    (value) =>
                        _normalizeSearch(value).contains(normalizedQuery),
                  )),
        )
        .toList(growable: false);
    items.sort((left, right) {
      final leftCounted = confirmed.contains(left.id);
      final rightCounted = confirmed.contains(right.id);
      if (leftCounted != rightCounted) return leftCounted ? 1 : -1;
      final name = left.canonicalName.compareTo(right.canonicalName);
      if (name != 0) return name;
      final pack = left.packSize.compareTo(right.packSize);
      return pack != 0 ? pack : left.id.compareTo(right.id);
    });
    return List<InventoryItem>.unmodifiable(items);
  }

  Future<Uint8List> readPreview(PreparedAiMedia media) {
    final prepared = _state.prepared;
    if (prepared == null ||
        !prepared.media.any(
          (item) =>
              item.sha256 == media.sha256 &&
              item.ephemeralReference == media.ephemeralReference,
        )) {
      throw StateError('This preview is no longer authorized.');
    }
    return _mediaReader.read(media);
  }

  Future<void> selectPhotos() async {
    if (_disposed || _state.status == StockPhotoCountStatus.accessDenied) {
      return;
    }
    final session = _inventory.state.activeSession;
    if (session == null || session.status != CountSessionStatus.open) {
      _fail('Start an ordinary stock count before selecting photos.');
      return;
    }
    final epoch = _accessEpoch;
    await _discardPrepared();
    _consent = null;
    _activeRoute = null;
    _setState(StockPhotoCountState(status: StockPhotoCountStatus.preparing));
    try {
      final selected = await _pickAssets();
      if (!_current(epoch)) return;
      final seenSourceIds = <String>{};
      final uniqueAssets = selected
          .where(
            (asset) =>
                asset.homeId == homeId &&
                asset.purpose == AiExtractionKind.stockPhoto &&
                seenSourceIds.add(asset.id),
          )
          .toList(growable: false);
      if (uniqueAssets.isEmpty) {
        _setState(const StockPhotoCountState.idle());
        return;
      }
      if (uniqueAssets.length > 8 || uniqueAssets.length != selected.length) {
        if (uniqueAssets.length > 8) {
          throw const AiPolicyViolation(
            code: 'stock_photo_limit',
            safeMessage: 'Select no more than eight stock photos.',
          );
        }
      }
      final prepared = await _mediaPreparation.prepare(
        homeId: homeId,
        purpose: AiExtractionKind.stockPhoto,
        assets: uniqueAssets,
      );
      if (!_current(epoch)) {
        await _mediaPreparation.discard(prepared);
        return;
      }
      final hashes = <String>{};
      final uniqueMedia = <PreparedAiMedia>[];
      final duplicates = <PreparedAiMedia>[];
      for (final media in prepared.media) {
        (hashes.add(media.sha256) ? uniqueMedia : duplicates).add(media);
      }
      if (duplicates.isNotEmpty) {
        await _mediaPreparation.discard(
          PreparedMediaBatch(
            id: '${prepared.id}-duplicates',
            homeId: homeId,
            purpose: AiExtractionKind.stockPhoto,
            media: duplicates,
          ),
        );
      }
      if (uniqueMedia.isEmpty) {
        throw const AiPolicyViolation(
          code: 'stock_photo_empty',
          safeMessage: 'No distinct stock photos remained after preparation.',
        );
      }
      final uniqueBatch = PreparedMediaBatch(
        id: prepared.id,
        homeId: homeId,
        purpose: AiExtractionKind.stockPhoto,
        media: uniqueMedia,
      );
      _setState(
        StockPhotoCountState(
          status: StockPhotoCountStatus.preparing,
          prepared: uniqueBatch,
        ),
      );
      final route = await _loadRoute();
      if (!_current(epoch)) {
        await _mediaPreparation.discard(uniqueBatch);
        return;
      }
      route.validate();
      final provider = route.profile;
      _policy.validateProfile(provider);
      if (provider.homeId != homeId) {
        throw const AiPolicyViolation(
          code: 'home_scope_mismatch',
          safeMessage: 'The selected provider belongs to another home.',
        );
      }
      if (uniqueMedia.length > 1 &&
          !provider.capabilities.contains(AiCapability.multiImage)) {
        throw const AiPolicyViolation(
          code: 'multi_image_unsupported',
          safeMessage:
              'The selected provider does not support multiple images.',
        );
      }
      _activeRoute = route;
      _setState(
        StockPhotoCountState(
          status: StockPhotoCountStatus.awaitingConsent,
          prepared: uniqueBatch,
          provider: provider,
          privacyMode: route.privacyMode,
          safeMessage: duplicates.isEmpty
              ? null
              : '${duplicates.length} exact duplicate image${duplicates.length == 1 ? '' : 's'} removed.',
        ),
      );
    } on AiServerException catch (error) {
      if (error.kind == AiServerFailureKind.authorizationDenied) {
        await _denyAccess(error.safeMessage);
      } else {
        await _discardPrepared();
        if (_current(epoch)) _fail(error.safeMessage);
      }
    } on AiPolicyViolation catch (error) {
      await _discardPrepared();
      if (_current(epoch)) _fail(error.safeMessage);
    } catch (_) {
      await _discardPrepared();
      if (_current(epoch)) {
        _fail('The selected photos could not be prepared safely.');
      }
    }
  }

  void confirmTransmission() {
    if (_disposed || _state.status == StockPhotoCountStatus.accessDenied) {
      return;
    }
    final prepared = _state.prepared;
    final provider = _state.provider;
    final route = _activeRoute;
    if (prepared == null || provider == null || route == null) {
      _fail('Select and review the prepared images first.');
      return;
    }
    final consent = AiConsent(
      providerId: provider.id,
      providerRevision: provider.revision,
      privacyMode: route.privacyMode,
      purpose: AiExtractionKind.stockPhoto,
      orderedMediaHashes: prepared.orderedHashes,
      disclosureVersion: AiPrivacyPolicy.disclosureVersion,
      confirmedAt: _clock().toUtc(),
    );
    try {
      _policy.authorizeExtraction(
        profile: provider,
        privacyMode: route.privacyMode,
        media: prepared,
        consent: consent,
      );
      _consent = consent;
      _setState(
        StockPhotoCountState(
          status: StockPhotoCountStatus.awaitingConsent,
          prepared: prepared,
          provider: provider,
          privacyMode: route.privacyMode,
          consentConfirmed: true,
          safeMessage: _state.safeMessage,
        ),
      );
    } on AiPolicyViolation catch (error) {
      _fail(error.safeMessage, prepared: prepared, provider: provider);
    }
  }

  Future<void> extract() async {
    if (_disposed || _state.status == StockPhotoCountStatus.accessDenied) {
      return;
    }
    final session = _inventory.state.activeSession;
    final prepared = _state.prepared;
    final provider = _state.provider;
    final consent = _consent;
    final route = _activeRoute;
    if (session == null ||
        session.status != CountSessionStatus.open ||
        prepared == null ||
        provider == null ||
        consent == null ||
        route == null ||
        route.profile.id != provider.id ||
        route.profile.revision != provider.revision) {
      _fail(
        'Keep the stock count open and confirm transmission first.',
        prepared: prepared,
        provider: provider,
        privacyMode: route?.privacyMode,
      );
      return;
    }
    final epoch = _accessEpoch;
    _setState(
      StockPhotoCountState(
        status: StockPhotoCountStatus.processing,
        prepared: prepared,
        provider: provider,
        privacyMode: route.privacyMode,
        consentConfirmed: true,
      ),
    );
    try {
      _policy.authorizeExtraction(
        profile: provider,
        privacyMode: route.privacyMode,
        media: prepared,
        consent: consent,
      );
      route.validate();
      final readiness = await route.gateway.readiness(provider);
      if (!readiness.isReady) {
        throw AiPolicyViolation(
          code: 'provider_unavailable',
          safeMessage: readiness.safeMessage ?? 'The AI provider is not ready.',
        );
      }
      if (!_current(epoch)) return;
      final result = await route.gateway.extractStockPhoto(
        AiExtractionRequest(
          runId: _idGenerator(),
          homeId: homeId,
          kind: AiExtractionKind.stockPhoto,
          provider: provider,
          privacyMode: route.privacyMode,
          media: prepared,
          schemaVersion: AiProposalSchemas.stockPhotoVersion,
          promptVersion: 'stock-photo-extraction-v1',
          timeout: const Duration(seconds: 45),
          targetId: session.id,
        ),
      );
      if (!_current(epoch)) return;
      switch (result) {
        case AiExtractionSuccess<StockPhotoProposal>():
          final deduplicated = _deduplicateCandidates(
            result.proposal.candidates,
          );
          final reviews = deduplicated.$1
              .map(
                (candidate) => StockPhotoCandidateReview(
                  proposal: candidate,
                  quantity:
                      candidate.quantityMinimum.isFinite &&
                          candidate.quantityMinimum >= 0 &&
                          candidate.quantityMinimum == candidate.quantityMaximum
                      ? candidate.quantityMinimum
                      : null,
                ),
              )
              .toList(growable: false);
          _consent = null;
          _setState(
            StockPhotoCountState(
              status: StockPhotoCountStatus.review,
              prepared: prepared,
              provider: provider,
              privacyMode: route.privacyMode,
              proposal: result.proposal,
              candidates: reviews,
              safeMessage: deduplicated.$2 == 0
                  ? null
                  : '${deduplicated.$2} overlapping candidate${deduplicated.$2 == 1 ? '' : 's'} removed; confirm the retained count once.',
            ),
          );
        case AiExtractionQuarantined<StockPhotoProposal>():
          await _discardPrepared();
          _fail('The images were quarantined and cannot update inventory.');
        case AiExtractionFailure<StockPhotoProposal>():
          await _discardPrepared();
          _fail(result.safeMessage);
        case AiExtractionRefused<StockPhotoProposal>():
          await _discardPrepared();
          _fail(result.safeReason);
        case AiExtractionIncomplete<StockPhotoProposal>():
          await _discardPrepared();
          _fail(result.safeReason);
      }
    } on AiGatewayAuthorizationDeniedException catch (error) {
      await _denyAccess(error.safeMessage);
    } on AiServerException catch (error) {
      if (error.kind == AiServerFailureKind.authorizationDenied) {
        await _denyAccess(error.safeMessage);
      } else {
        await _discardPrepared();
        if (_current(epoch)) _fail(error.safeMessage);
      }
    } on AiPolicyViolation catch (error) {
      await _discardPrepared();
      if (_current(epoch)) _fail(error.safeMessage);
    } catch (_) {
      await _discardPrepared();
      if (_current(epoch)) {
        _fail('Stock-photo extraction could not be completed safely.');
      }
    }
  }

  void matchCandidate(String candidateId, String? homeProductId) {
    if (_disposed || _state.status != StockPhotoCountStatus.review) return;
    final product = homeProductId == null
        ? null
        : homeProducts.where((item) => item.id == homeProductId).firstOrNull;
    if (homeProductId != null && product == null) {
      _fail('Choose a product from the active home.', keepReview: true);
      return;
    }
    _updateCandidate(
      candidateId,
      (candidate) => candidate.copyWith(
        homeProductId: product?.id,
        clearHomeProduct: product == null,
        counted: false,
      ),
    );
  }

  /// Resolves a full item-master selection to a home product. Existing home
  /// products are matched directly; an unselected published pack goes through
  /// the ordinary optimistic `inventory.home-product.create` outbox path.
  Future<void> selectCandidateItem(
    String candidateId,
    String inventoryItemId,
  ) async {
    if (_disposed || _state.status != StockPhotoCountStatus.review) return;
    final review = _state.candidates
        .where((candidate) => candidate.proposal.candidateId == candidateId)
        .firstOrNull;
    if (review == null || review.counted) return;
    final item = searchItems()
        .where((candidate) => candidate.id == inventoryItemId)
        .firstOrNull;
    if (item == null || item.homeId != homeId) {
      _fail('Choose an item from the active home.', keepReview: true);
      return;
    }
    if (item.isHomeProduct) {
      matchCandidate(candidateId, item.id);
      return;
    }
    if (item.productId == null || item.packId == null) {
      _fail(
        'Choose a published catalog pack or a home product.',
        keepReview: true,
      );
      return;
    }
    final existing = _findCatalogHomeProduct(item);
    if (existing != null) {
      matchCandidate(candidateId, existing.id);
      return;
    }
    if (_pendingCandidateIds.contains(candidateId)) return;
    final epoch = _accessEpoch;
    _pendingCandidateIds.add(candidateId);
    _setReviewState(candidateBusyId: candidateId);
    try {
      await _inventory.addCatalogProduct(item);
      final projected = await _awaitProjectedHomeProduct(
        (candidate) =>
            candidate.productId == item.productId &&
            candidate.packId == item.packId,
      );
      if (!_current(epoch)) return;
      if (projected == null) {
        _fail(
          _inventory.state.productCreationError ??
              'The catalog pack could not be added safely.',
          keepReview: true,
        );
        return;
      }
      matchCandidate(candidateId, projected.id);
    } finally {
      _pendingCandidateIds.remove(candidateId);
      if (_current(epoch) &&
          _state.status == StockPhotoCountStatus.review &&
          _state.candidateBusyId == candidateId) {
        _setReviewState();
      }
    }
  }

  /// Creates a private item through the ordinary offline outbox, then waits
  /// for that optimistic home-product projection before it can be counted.
  Future<void> createPrivateProductForCandidate({
    required String candidateId,
    required String privateName,
    String? packText,
  }) async {
    if (_disposed || _state.status != StockPhotoCountStatus.review) return;
    final review = _state.candidates
        .where((candidate) => candidate.proposal.candidateId == candidateId)
        .firstOrNull;
    if (review == null || review.counted) return;
    if (_pendingCandidateIds.contains(candidateId)) return;
    final name = privateName.trim();
    final pack = packText?.trim();
    if (name.isEmpty) {
      _fail('Enter a private product name.', keepReview: true);
      return;
    }
    final existingIds = homeProducts.map((item) => item.id).toSet();
    final epoch = _accessEpoch;
    _pendingCandidateIds.add(candidateId);
    _setReviewState(candidateBusyId: candidateId);
    try {
      await _inventory.createPrivateProduct(
        privateName: name,
        originalPackText: pack == null || pack.isEmpty ? null : pack,
      );
      final projected = await _awaitProjectedHomeProduct(
        (candidate) =>
            !existingIds.contains(candidate.id) &&
            candidate.productId == null &&
            candidate.packId == null &&
            candidate.canonicalName.trim() == name &&
            (pack == null || pack.isEmpty || candidate.packSize.trim() == pack),
      );
      if (!_current(epoch)) return;
      if (projected == null) {
        _fail(
          _inventory.state.productCreationError ??
              'The private product could not be added safely.',
          keepReview: true,
        );
        return;
      }
      matchCandidate(candidateId, projected.id);
    } finally {
      _pendingCandidateIds.remove(candidateId);
      if (_current(epoch) &&
          _state.status == StockPhotoCountStatus.review &&
          _state.candidateBusyId == candidateId) {
        _setReviewState();
      }
    }
  }

  void setQuantity(String candidateId, double? quantity) {
    if (_disposed || _state.status != StockPhotoCountStatus.review) return;
    if (quantity != null && (!quantity.isFinite || quantity < 0)) {
      quantity = null;
    }
    _updateCandidate(
      candidateId,
      (candidate) => candidate.copyWith(
        quantity: quantity,
        clearQuantity: quantity == null,
        counted: false,
      ),
    );
  }

  Future<void> confirmCandidate(String candidateId) async {
    if (_disposed || _state.status != StockPhotoCountStatus.review) return;
    final index = _state.candidates.indexWhere(
      (candidate) => candidate.proposal.candidateId == candidateId,
    );
    if (index < 0) return;
    final candidate = _state.candidates[index];
    if (candidate.counted || _pendingCandidateIds.contains(candidateId)) return;
    final quantity = candidate.quantity;
    final product = homeProducts
        .where((item) => item.id == candidate.homeProductId)
        .firstOrNull;
    if (product == null ||
        quantity == null ||
        !quantity.isFinite ||
        quantity < 0) {
      _fail(
        'Match a home product and confirm a concrete quantity.',
        keepReview: true,
      );
      return;
    }
    final proposal = _state.proposal;
    if (proposal == null) return;
    final photoReferenceId = '${proposal.id}:$candidateId';
    final session = _inventory.state.activeSession;
    if (session == null || session.status != CountSessionStatus.open) {
      _fail('Keep the ordinary stock count open.', keepReview: true);
      return;
    }
    final replayedLine = session.confirmedLines
        .where((line) => line.photoId == photoReferenceId)
        .firstOrNull;
    if (replayedLine != null) {
      if (replayedLine.itemId != product.id) {
        _fail(
          'This photo candidate was already matched differently.',
          keepReview: true,
        );
        return;
      }
      _updateCandidate(
        candidateId,
        (current) => current.copyWith(counted: true),
      );
      return;
    }
    if (session.confirmedLines.any((line) => line.itemId == product.id) ||
        _pendingHomeProductIds.contains(product.id)) {
      _fail(
        'This product is already counted in the open session.',
        keepReview: true,
      );
      return;
    }
    _pendingCandidateIds.add(candidateId);
    _pendingHomeProductIds.add(product.id);
    final epoch = _accessEpoch;
    _setReviewState(candidateBusyId: candidateId);
    try {
      await _inventory.recordPhotoCount(
        item: product,
        observedQuantity: quantity,
        proposalId: photoReferenceId,
      );
      if (!_current(epoch)) return;
      _updateCandidate(
        candidateId,
        (current) => current.copyWith(counted: true),
      );
    } catch (_) {
      final projected = await _awaitProjectedCountLine(photoReferenceId);
      if (!_current(epoch)) return;
      if (projected != null && projected.itemId == product.id) {
        _updateCandidate(
          candidateId,
          (current) => current.copyWith(counted: true),
        );
      } else {
        _fail(
          'The confirmed photo count could not be queued safely.',
          keepReview: true,
        );
      }
    } finally {
      _pendingCandidateIds.remove(candidateId);
      _pendingHomeProductIds.remove(product.id);
      if (_current(epoch) &&
          _state.status == StockPhotoCountStatus.review &&
          _state.candidateBusyId == candidateId) {
        _setReviewState();
      }
    }
  }

  Future<void> abandonPhotos() async {
    if (_disposed) return;
    _accessEpoch += 1;
    _consent = null;
    _activeRoute = null;
    await _discardPrepared();
    if (!_disposed) _setState(const StockPhotoCountState.idle());
  }

  Future<void> authorizationLost() async {
    await _denyAccess('Stock-photo access was removed for this home.');
  }

  void _handleInventoryChange() {
    if (_state.prepared != null && _inventory.state.activeSession == null) {
      unawaited(abandonPhotos());
    }
  }

  InventoryItem? _findCatalogHomeProduct(InventoryItem catalogItem) =>
      homeProducts
          .where(
            (candidate) =>
                candidate.productId == catalogItem.productId &&
                candidate.packId == catalogItem.packId,
          )
          .firstOrNull;

  Future<InventoryItem?> _awaitProjectedHomeProduct(
    bool Function(InventoryItem item) matches,
  ) async {
    InventoryItem? find() => homeProducts.where(matches).firstOrNull;
    final immediate = find();
    if (immediate != null) return immediate;
    final completer = Completer<InventoryItem?>();
    void listener() {
      final projected = find();
      if (projected != null && !completer.isCompleted) {
        completer.complete(projected);
      }
    }

    _inventory.addListener(listener);
    try {
      listener();
      if (completer.isCompleted) return completer.future;
      return await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: find,
      );
    } finally {
      _inventory.removeListener(listener);
    }
  }

  Future<StockCountLine?> _awaitProjectedCountLine(String photoId) async {
    StockCountLine? find() => _inventory.state.activeSession?.confirmedLines
        .where((line) => line.photoId == photoId)
        .firstOrNull;
    final immediate = find();
    if (immediate != null) return immediate;
    final completer = Completer<StockCountLine?>();
    void listener() {
      final projected = find();
      if (projected != null && !completer.isCompleted) {
        completer.complete(projected);
      }
    }

    _inventory.addListener(listener);
    try {
      listener();
      if (completer.isCompleted) return completer.future;
      return await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: find,
      );
    } finally {
      _inventory.removeListener(listener);
    }
  }

  String _normalizeSearch(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'''[\s\-–—_/().,&'"]+'''), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  void _updateCandidate(
    String candidateId,
    StockPhotoCandidateReview Function(StockPhotoCandidateReview) update,
  ) {
    final candidates = _state.candidates
        .map(
          (candidate) => candidate.proposal.candidateId == candidateId
              ? update(candidate)
              : candidate,
        )
        .toList(growable: false);
    _setReviewState(candidates: candidates);
  }

  (List<StockCandidateProposal>, int) _deduplicateCandidates(
    List<StockCandidateProposal> candidates,
  ) {
    String normalized(String? value) =>
        (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final seen = <String>{};
    final unique = <StockCandidateProposal>[];
    var removed = 0;
    for (final candidate in candidates) {
      final key = <String>[
        normalized(candidate.productName.value),
        normalized(candidate.brand.value),
        normalized(candidate.variant.value),
        normalized(candidate.packDescription.value),
        candidate.quantityMinimum.toString(),
        candidate.quantityMaximum.toString(),
      ].join('|');
      if (seen.add(key)) {
        unique.add(candidate);
      } else {
        removed += 1;
      }
    }
    return (unique, removed);
  }

  void _setReviewState({
    List<StockPhotoCandidateReview>? candidates,
    String? candidateBusyId,
    String? safeMessage,
  }) {
    _setState(
      StockPhotoCountState(
        status: StockPhotoCountStatus.review,
        prepared: _state.prepared,
        provider: _state.provider,
        privacyMode: _state.privacyMode,
        proposal: _state.proposal,
        candidates: candidates ?? _state.candidates,
        candidateBusyId: candidateBusyId,
        safeMessage: safeMessage,
      ),
    );
  }

  void _fail(
    String message, {
    PreparedMediaBatch? prepared,
    AiProviderProfile? provider,
    AiPrivacyMode? privacyMode,
    bool keepReview = false,
  }) {
    if (keepReview && _state.proposal != null) {
      _setReviewState(safeMessage: message);
      return;
    }
    _setState(
      StockPhotoCountState(
        status: StockPhotoCountStatus.failed,
        prepared: prepared,
        provider: provider,
        privacyMode: privacyMode ?? _state.privacyMode,
        safeMessage: message,
      ),
    );
  }

  Future<void> _discardPrepared() async {
    final prepared = _state.prepared;
    await _discardBatch(prepared);
  }

  Future<void> _discardBatch(PreparedMediaBatch? prepared) async {
    if (prepared == null) return;
    try {
      await _mediaPreparation.discard(prepared);
    } catch (_) {
      // Access-loss and terminal cleanup must remain best-effort and non-leaky.
    }
  }

  Future<void> _denyAccess(String safeMessage) async {
    if (_disposed) return;
    _accessEpoch += 1;
    _consent = null;
    _activeRoute = null;
    _pendingCandidateIds.clear();
    _pendingHomeProductIds.clear();
    final prepared = _state.prepared;
    _setState(
      StockPhotoCountState(
        status: StockPhotoCountStatus.accessDenied,
        safeMessage: safeMessage,
      ),
    );
    final callback = _onAuthorizationDenied;
    final shouldReport = !_authorizationDenialReported && callback != null;
    _authorizationDenialReported = true;
    await _discardBatch(prepared);
    if (shouldReport && !_disposed) {
      try {
        await callback();
      } catch (_) {
        // The terminal access-denied state remains authoritative even if the
        // enclosing route is already being removed.
      }
    }
  }

  bool _current(int epoch) => !_disposed && epoch == _accessEpoch;

  void _setState(StockPhotoCountState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _accessEpoch += 1;
    _inventory.removeListener(_handleInventoryChange);
    _consent = null;
    _activeRoute = null;
    final prepared = _state.prepared;
    if (prepared != null) unawaited(_mediaPreparation.discard(prepared));
    super.dispose();
  }
}
