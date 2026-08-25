part of 'stock_photo_count_controller.dart';

extension StockPhotoCountReview on StockPhotoCountController {
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
}
