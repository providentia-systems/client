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

part 'stock_photo_count_acquisition.dart';
part 'stock_photo_count_review.dart';
part 'stock_photo_count_internals.dart';

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
    this.serverCandidate,
    this.counted = false,
    this.rejected = false,
  });

  final StockCandidateProposal proposal;
  final String? homeProductId;
  final double? quantity;
  final AiReviewCandidate? serverCandidate;
  final bool counted;
  final bool rejected;

  bool get resolved => counted || rejected;

  StockPhotoCandidateReview copyWith({
    String? homeProductId,
    bool clearHomeProduct = false,
    double? quantity,
    bool clearQuantity = false,
    AiReviewCandidate? serverCandidate,
    bool? counted,
    bool? rejected,
  }) => StockPhotoCandidateReview(
    proposal: proposal,
    homeProductId: clearHomeProduct
        ? null
        : (homeProductId ?? this.homeProductId),
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    serverCandidate: serverCandidate ?? this.serverCandidate,
    counted: counted ?? this.counted,
    rejected: rejected ?? this.rejected,
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
        ...candidates.where((candidate) => !candidate.resolved),
        ...candidates.where((candidate) => candidate.resolved),
      ]);
}

typedef StockPhotoAssetPicker = Future<List<AiMediaAsset>> Function();
typedef StockPhotoProviderLoader = Future<AiProviderProfile> Function();
typedef StockPhotoAiRouteLoader = Future<StockPhotoAiRoute> Function();
typedef StockCandidateReviewer =
    Future<AiExtractionReview> Function({
      required AiReviewCandidate candidate,
      required AiCandidateDecision decision,
    });

/// UI-independent acquisition ports for the three explicit stock-image
/// sources. Every source is consumed by [StockPhotoCountController.selectAssets].
final class StockPhotoAcquisitionActions {
  const StockPhotoAcquisitionActions({
    required this.takePhoto,
    required this.chooseGallery,
    required this.uploadFiles,
  });

  final StockPhotoAssetPicker takePhoto;
  final StockPhotoAssetPicker chooseGallery;
  final StockPhotoAssetPicker uploadFiles;
}

final class StockPhotoAiRoute {
  const StockPhotoAiRoute({
    required this.profile,
    required this.gateway,
    required this.privacyMode,
    this.reviewCandidate,
  });

  final AiProviderProfile profile;
  final AiProviderGateway gateway;
  final AiPrivacyMode privacyMode;
  final StockCandidateReviewer? reviewCandidate;

  void validate() {
    final expected = switch (gateway.route) {
      AiGatewayRoute.serverProxyCloud => AiPrivacyMode.serverProxyCloud,
      AiGatewayRoute.directStrictLocal => AiPrivacyMode.strictLocal,
    };
    if (privacyMode != expected ||
        privacyMode == AiPrivacyMode.serverProxyCloud &&
            profile.transport != AiTransport.serverProxy ||
        privacyMode == AiPrivacyMode.strictLocal &&
            profile.transport != AiTransport.directNative ||
        privacyMode == AiPrivacyMode.serverProxyCloud &&
            reviewCandidate == null ||
        privacyMode == AiPrivacyMode.strictLocal && reviewCandidate != null) {
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
    StockCandidateReviewer? reviewCandidate,
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
                reviewCandidate: reviewCandidate,
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
