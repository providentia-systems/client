part of 'stock_photo_count_controller.dart';

extension StockPhotoCountAcquisition on StockPhotoCountController {
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

  Future<void> selectPhotos() => selectAssets(_pickAssets);

  /// Runs camera, gallery, and file-upload acquisitions through the same
  /// preparation, consent, review, and ordinary-count command boundary.
  Future<void> selectAssets(StockPhotoAssetPicker picker) async {
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
      final selected = await picker();
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
}
