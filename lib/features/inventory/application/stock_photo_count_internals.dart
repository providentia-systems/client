part of 'stock_photo_count_controller.dart';

extension StockPhotoCountLifecycle on StockPhotoCountController {
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
}
