import 'package:http/http.dart' as http;
import 'package:providentia/features/administration/application/catalog_administration_ports.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

typedef CatalogAdministrationClock = DateTime Function();

/// Role-scoped catalog administration through the current pinned contract.
///
/// Only platform roles can create local capabilities. Home membership and
/// household permissions are deliberately absent from this boundary. Every
/// queue mapper constructs an attribution-free DTO from an explicit allowlist
/// instead of forwarding server maps to presentation code.
final class GeneratedCatalogAdministrationRepository
    implements
        CatalogModerationRepository,
        CatalogProposalDecisionRepository,
        CatalogContributionModerationRepository,
        CatalogConflictResolutionRepository,
        CatalogIconRepository,
        CatalogMergeRepository {
  factory GeneratedCatalogAdministrationRepository(
    ProvidentiaApiClient client, {
    required Set<PlatformRole> platformRoles,
    CatalogAdministrationClock? clock,
    Future<void> Function()? onAuthorizationLost,
  }) => GeneratedCatalogAdministrationRepository._(
    client,
    Set<CatalogCapability>.unmodifiable(
      capabilitiesForPlatformRoles(platformRoles),
    ),
    clock ?? DateTime.now,
    onAuthorizationLost,
  );

  GeneratedCatalogAdministrationRepository._(
    this._client,
    this.capabilities,
    this._clock,
    this._onAuthorizationLost,
  );

  final ProvidentiaApiClient _client;
  final CatalogAdministrationClock _clock;
  final Future<void> Function()? _onAuthorizationLost;
  bool _authorizationLossNotified = false;

  @override
  final Set<CatalogCapability> capabilities;

  static Set<CatalogCapability> capabilitiesForPlatformRoles(
    Set<PlatformRole> roles,
  ) {
    final reviewer = roles.any(
      const <PlatformRole>{
        PlatformRole.platformAdministrator,
        PlatformRole.catalogCurator,
        PlatformRole.catalogReviewer,
      }.contains,
    );
    final curator = roles.any(
      const <PlatformRole>{
        PlatformRole.platformAdministrator,
        PlatformRole.catalogCurator,
      }.contains,
    );
    return <CatalogCapability>{
      if (reviewer) CatalogCapability.review,
      if (curator) ...<CatalogCapability>{
        CatalogCapability.curate,
        CatalogCapability.manageIcons,
        CatalogCapability.previewMerges,
        CatalogCapability.executeMerges,
        CatalogCapability.reverseMerges,
      },
    };
  }

  @override
  Future<List<CatalogQueueItem>> loadQueue() async {
    _require(CatalogCapability.review);
    final queues = await Future.wait<List<CatalogQueueItem>>(
      <Future<List<CatalogQueueItem>>>[
        loadWorkbenchQueue('proposals'),
        loadContributionQueue(),
        loadWorkbenchQueue('duplicates'),
        loadWorkbenchQueue('aliases'),
        loadWorkbenchQueue('barcodes'),
        if (capabilities.contains(CatalogCapability.manageIcons))
          loadWorkbenchQueue('icons'),
        if (capabilities.contains(CatalogCapability.reverseMerges))
          loadWorkbenchQueue('merges'),
      ],
    );
    return List<CatalogQueueItem>.unmodifiable(queues.expand((items) => items));
  }

  Future<List<CatalogQueueItem>> loadWorkbenchQueue(String queue) {
    _require(CatalogCapability.review);
    if (!const <String>{
      'proposals',
      'duplicates',
      'aliases',
      'barcodes',
      'icons',
      'merges',
    }.contains(queue)) {
      throw ArgumentError.value(queue, 'queue', 'is not supported');
    }
    return _run(() async {
      final rows = await _workbenchRows(queue);
      return rows
          .map((row) => _workbenchItem(queue, row))
          .toList(growable: false);
    });
  }

  @override
  Future<List<CatalogQueueItem>> loadContributionQueue() {
    _require(CatalogCapability.review);
    return _run(() async {
      final object = (await _client.listCatalogContributionReviewQueue(
        query: const <String, String>{
          'status': 'pending',
          'limit': '50',
          'offset': '0',
        },
      )).requireObject();
      return _objectRows(
        object,
        'data',
      ).map(_contributionItem).toList(growable: false);
    });
  }

  @override
  Future<CatalogModerationDecisionResult> decideProposal(
    CatalogReviewDecision decision,
  ) {
    _require(CatalogCapability.review);
    final body = _decisionBody(decision, contribution: false);
    return _run(() async {
      final object = (await _client.decideCatalogProposal(
        proposalId: decision.proposalId,
        body: body,
      )).requireObject();
      return CatalogModerationDecisionResult(
        status: _reviewStatus(_string(object, 'status')),
        entityType: _optionalString(object['entityType']),
        entityId: _optionalString(object['entityId']),
      );
    });
  }

  @override
  Future<void> decideContribution(CatalogReviewDecision decision) {
    _require(CatalogCapability.review);
    final body = _decisionBody(decision, contribution: true);
    return _run(() async {
      await _client.decideCatalogContribution(
        contributionId: decision.proposalId,
        body: body,
      );
    });
  }

  @override
  Future<void> keepExistingConflict({
    required String conflictId,
    required String reason,
    required int expectedRevision,
  }) {
    _require(CatalogCapability.review);
    final cleanedReason = reason.trim();
    if (cleanedReason.isEmpty || expectedRevision < 1) {
      throw const CatalogValidationException();
    }
    return _run(() async {
      await _client.keepExistingCatalogConflict(
        conflictId: conflictId,
        body: <String, Object?>{
          'reason': cleanedReason,
          'expectedRevision': expectedRevision,
        },
      );
    });
  }

  @override
  Future<CatalogRevisionResult> putIcon(CatalogIconWrite icon) async {
    _require(CatalogCapability.manageIcons);
    return _run(() async {
      final object = (await _client.putCatalogIcon(
        targetType: icon.targetType.name,
        targetId: icon.targetId,
        body: <String, Object?>{
          'assetDigest': icon.assetDigest,
          'mediaType': icon.mediaType,
          'altText': icon.altText.trim(),
          'width': icon.width,
          'height': icon.height,
          'byteSize': icon.byteSize,
          'provenance': icon.provenance.trim(),
          'expectedRevision': icon.expectedRevision,
        },
      )).requireObject();
      return CatalogRevisionResult(
        id: _string(object, 'id'),
        revision: _positiveInteger(object, 'revision'),
      );
    });
  }

  @override
  Future<CatalogMergePreview> previewMerge({
    required String survivorProductId,
    required List<String> absorbedProductIds,
  }) {
    _require(CatalogCapability.previewMerges);
    return _run(() async {
      final object = (await _client.previewCatalogMerge(
        body: <String, Object?>{
          'survivorId': survivorProductId,
          'duplicateIds': absorbedProductIds,
        },
      )).requireObject();
      return _mergePreview(
        object,
        requestedSurvivorId: survivorProductId,
        requestedDuplicateIds: absorbedProductIds,
        createdAt: _clock().toUtc(),
      );
    });
  }

  @override
  Future<CatalogMergePreview> previewReversal({required String mergeEventId}) {
    _require(CatalogCapability.reverseMerges);
    return _run(() async {
      final rows = await _workbenchRows('merges');
      final row = rows.where((candidate) => candidate['id'] == mergeEventId);
      if (row.isEmpty || row.first['status'] != 'applied') {
        throw const CatalogConflictException();
      }
      final merge = row.first;
      return CatalogMergePreview(
        previewId: mergeEventId,
        kind: CatalogMergePlanKind.reversal,
        survivorProductId: _string(merge, 'survivorId'),
        absorbedProductIds: _stringList(merge['mergedIds']),
        expectedRevisions: <String, int>{
          mergeEventId: _positiveInteger(merge, 'revision'),
        },
        impact: const CatalogMergeImpact(
          globalAliasCount: 0,
          globalPackCount: 0,
          globalBarcodeCount: 0,
          hasPrivateReferences: true,
        ),
        createdAt: _clock().toUtc(),
      );
    });
  }

  @override
  Future<CatalogMergeResult> execute({
    required CatalogMergePreview preview,
    required String idempotencyKey,
    required String reason,
  }) {
    final cleanedReason = reason.trim();
    if (cleanedReason.isEmpty || idempotencyKey.trim().isEmpty) {
      throw const CatalogValidationException();
    }
    return preview.kind == CatalogMergePlanKind.merge
        ? _applyMerge(preview, idempotencyKey, cleanedReason)
        : _reverseMerge(preview, idempotencyKey, cleanedReason);
  }

  Future<CatalogMergeResult> _applyMerge(
    CatalogMergePreview preview,
    String idempotencyKey,
    String reason,
  ) {
    _require(CatalogCapability.executeMerges);
    if (!preview.eligible) {
      throw const CatalogConflictException();
    }
    final survivorRevision =
        preview.expectedRevisions[preview.survivorProductId];
    final duplicateRevisions = <String, int>{};
    for (final id in preview.absorbedProductIds) {
      final revision = preview.expectedRevisions[id];
      if (revision == null) {
        throw const CatalogStaleRevisionException();
      }
      duplicateRevisions[id] = revision;
    }
    if (survivorRevision == null) {
      throw const CatalogStaleRevisionException();
    }
    return _run(() async {
      final object = (await _client.applyCatalogMerge(
        headers: <String, String>{'Idempotency-Key': idempotencyKey},
        body: <String, Object?>{
          'survivorId': preview.survivorProductId,
          'expectedSurvivorRevision': survivorRevision,
          'duplicateRevisions': duplicateRevisions,
          'reason': reason,
        },
      )).requireObject();
      return _mergeResult(object, idempotencyKey: idempotencyKey);
    });
  }

  Future<CatalogMergeResult> _reverseMerge(
    CatalogMergePreview preview,
    String idempotencyKey,
    String reason,
  ) {
    _require(CatalogCapability.reverseMerges);
    final revision = preview.expectedRevisions[preview.previewId];
    if (revision == null) {
      throw const CatalogStaleRevisionException();
    }
    return _run(() async {
      final object = (await _client.reverseCatalogMerge(
        mergeId: preview.previewId,
        headers: <String, String>{'Idempotency-Key': idempotencyKey},
        body: <String, Object?>{'expectedRevision': revision, 'reason': reason},
      )).requireObject();
      return _mergeResult(object, idempotencyKey: idempotencyKey);
    });
  }

  Future<List<Map<String, Object?>>> _workbenchRows(String queue) async {
    final object = (await _client.getCatalogWorkbench(
      query: <String, String>{'queue': queue, 'limit': '50', 'offset': '0'},
    )).requireObject();
    return _objectRows(object, 'data');
  }

  CatalogMergeResult _mergeResult(
    Map<String, Object?> object, {
    required String idempotencyKey,
  }) {
    final status = _string(object, 'status');
    if (status != 'applied' && status != 'reversed') {
      throw const FormatException('Unknown catalog merge status.');
    }
    return CatalogMergeResult(
      eventId: _string(object, 'id'),
      idempotencyKey: idempotencyKey,
      completedAt: _clock().toUtc(),
      reversed: status == 'reversed',
    );
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CatalogContractUnavailableException {
      rethrow;
    } on CatalogForbiddenException {
      rethrow;
    } on CatalogConflictException {
      rethrow;
    } on CatalogStaleRevisionException {
      rethrow;
    } on CatalogValidationException {
      rethrow;
    } on CatalogUnsupportedDecisionException {
      rethrow;
    } on ProvidentiaApiException catch (error) {
      final failure = _administrationFailure(error);
      if (failure is CatalogForbiddenException && !_authorizationLossNotified) {
        _authorizationLossNotified = true;
        await _onAuthorizationLost?.call();
      }
      throw failure;
    } on FormatException {
      throw const CatalogContractUnavailableException();
    } on ArgumentError {
      throw const CatalogContractUnavailableException();
    } on http.ClientException {
      throw const CatalogContractUnavailableException();
    }
  }

  void _require(CatalogCapability capability) {
    if (!capabilities.contains(capability)) {
      throw const CatalogForbiddenException();
    }
  }
}

Map<String, Object?> _decisionBody(
  CatalogReviewDecision decision, {
  required bool contribution,
}) {
  if (decision.decision == CatalogReviewDecisionKind.recommend) {
    throw const CatalogUnsupportedDecisionException();
  }
  final reason = decision.reason.trim();
  if (reason.isEmpty || decision.expectedRevision < 1) {
    throw const CatalogValidationException();
  }
  return <String, Object?>{
    'decision': switch (decision.decision) {
      CatalogReviewDecisionKind.approve =>
        contribution ? 'approved' : 'approve',
      CatalogReviewDecisionKind.reject => contribution ? 'rejected' : 'reject',
      CatalogReviewDecisionKind.recommend => throw StateError('unreachable'),
    },
    'reason': reason,
    'expectedRevision': decision.expectedRevision,
  };
}

CatalogQueueItem _workbenchItem(String queue, Map<String, Object?> object) {
  if (queue == 'proposals') {
    final type = _string(object, 'proposalType');
    final payload = _optionalObject(object['payload']);
    return CatalogQueueItem(
      id: _string(object, 'id'),
      kind: _proposalKind(type),
      title: _proposalTitle(type, payload),
      summary: 'Review sanitized ${_displayType(type)} catalog evidence',
      status: _reviewStatus(_string(object, 'moderationStatus')),
      revision: _positiveInteger(object, 'revision'),
    );
  }
  if (const <String>{'duplicates', 'aliases', 'barcodes'}.contains(queue)) {
    final relatedCatalogIds = switch (queue) {
      'duplicates' => <String>[
        _string(object, 'existingEntityId'),
        _string(object, 'candidateEntityId'),
      ],
      _ => const <String>[],
    };
    return CatalogQueueItem(
      id: _string(object, 'id'),
      kind: switch (queue) {
        'duplicates' => CatalogQueueKind.duplicate,
        'aliases' => CatalogQueueKind.alias,
        _ => CatalogQueueKind.barcode,
      },
      title: switch (queue) {
        'duplicates' => 'Duplicate identity conflict',
        'aliases' => 'Alias identity conflict',
        _ => 'Barcode identity conflict',
      },
      summary: 'Review sanitized global catalog identities',
      status: CatalogReviewStatus.conflict,
      revision: _positiveInteger(object, 'revision'),
      source: CatalogQueueSource.conflict,
      relatedCatalogIds: relatedCatalogIds,
    );
  }
  if (queue == 'icons') {
    return CatalogQueueItem(
      id: _string(object, 'targetId'),
      kind: CatalogQueueKind.icon,
      title: _string(object, 'canonicalName'),
      summary: 'Published catalog record needs icon metadata',
      status: CatalogReviewStatus.pending,
      revision: _positiveInteger(object, 'revision'),
      source: CatalogQueueSource.icon,
      relatedCatalogIds: <String>[_string(object, 'targetId')],
      iconTargetType: _iconTargetType(_string(object, 'targetType')),
    );
  }
  final mergedIds = _stringList(object['mergedIds']);
  return CatalogQueueItem(
    id: _string(object, 'id'),
    kind: CatalogQueueKind.duplicate,
    title: 'Catalog merge',
    summary: '${mergedIds.length} duplicate catalog records',
    status: _reviewStatus(_string(object, 'status')),
    revision: _positiveInteger(object, 'revision'),
    source: CatalogQueueSource.merge,
    relatedCatalogIds: <String>[_string(object, 'survivorId'), ...mergedIds],
  );
}

CatalogIconTargetType _iconTargetType(String value) => switch (value) {
  'product' => CatalogIconTargetType.product,
  'category' => CatalogIconTargetType.category,
  _ => throw const FormatException('Unknown catalog icon target type.'),
};

CatalogQueueItem _contributionItem(Map<String, Object?> object) {
  final type = _string(object, 'contributionType');
  final payload = _optionalObject(object['payload']);
  return CatalogQueueItem(
    id: _string(object, 'id'),
    kind: switch (type) {
      'product_image' => CatalogQueueKind.icon,
      _ => CatalogQueueKind.proposal,
    },
    title: _contributionTitle(type, payload),
    summary: 'Review an attribution-free ${_displayType(type)} contribution',
    status: _reviewStatus(
      _optionalString(object['status']) ?? _string(object, 'moderationStatus'),
    ),
    revision: _positiveInteger(object, 'revision'),
    source: CatalogQueueSource.consentContribution,
  );
}

CatalogMergePreview _mergePreview(
  Map<String, Object?> object, {
  required String requestedSurvivorId,
  required List<String> requestedDuplicateIds,
  required DateTime createdAt,
}) {
  final survivorId = _string(object, 'survivorId');
  final duplicateIds = _stringList(object['duplicateIds']);
  if (survivorId != requestedSurvivorId ||
      !_sameStrings(duplicateIds, requestedDuplicateIds)) {
    throw const FormatException('Catalog merge response changed identities.');
  }
  final expectedRevisions = <String, int>{};
  for (final product in _objectList(object['products'], 'products')) {
    expectedRevisions[_string(product, 'id')] = _positiveInteger(
      product,
      'revision',
    );
  }
  final expectedIds = <String>{survivorId, ...duplicateIds};
  if (!expectedRevisions.keys.toSet().containsAll(expectedIds)) {
    throw const FormatException('Catalog merge revisions were incomplete.');
  }
  final counts = _requiredObject(object, 'affectedCounts');
  final privateReferences = _nonNegativeInteger(counts, 'homeReferences');
  return CatalogMergePreview(
    previewId: 'merge:$survivorId:${duplicateIds.join(',')}',
    kind: CatalogMergePlanKind.merge,
    survivorProductId: survivorId,
    absorbedProductIds: duplicateIds,
    expectedRevisions: <String, int>{
      for (final id in expectedIds) id: expectedRevisions[id]!,
    },
    impact: CatalogMergeImpact(
      globalAliasCount: _nonNegativeInteger(counts, 'aliases'),
      globalPackCount: _nonNegativeInteger(counts, 'packs'),
      globalBarcodeCount: 0,
      globalVariantCount: _nonNegativeInteger(counts, 'variants'),
      globalIconCount: _nonNegativeInteger(counts, 'icons'),
      privateReferenceCount: privateReferences,
      hasPrivateReferences: privateReferences > 0,
    ),
    createdAt: createdAt,
    eligible: _boolean(object, 'eligible'),
    conflicts: _stringList(object['conflicts']),
  );
}

CatalogQueueKind _proposalKind(String type) {
  return switch (type) {
    'pack' => CatalogQueueKind.pack,
    'alias' => CatalogQueueKind.alias,
    'barcode' => CatalogQueueKind.barcode,
    _ => CatalogQueueKind.proposal,
  };
}

String _proposalTitle(String type, Map<String, Object?>? payload) {
  final value = switch (type) {
    'product' => _optionalString(payload?['canonicalName']),
    'pack' => _optionalString(payload?['originalPackText']),
    'alias' => _optionalString(payload?['rawAlias']),
    'barcode' => _optionalString(payload?['barcode']),
    _ => null,
  };
  return value ?? '${_displayType(type)} proposal';
}

String _contributionTitle(String type, Map<String, Object?>? payload) {
  final value = switch (type) {
    'product_identity' => _optionalString(payload?['canonicalName']),
    'product_image' => _optionalString(payload?['altText']),
    'store_price' => _optionalString(payload?['storeName']),
    _ => null,
  };
  return value ?? '${_displayType(type)} contribution';
}

String _displayType(String value) => value.replaceAll('_', ' ');

CatalogReviewStatus _reviewStatus(String status) {
  return switch (status) {
    'pending' => CatalogReviewStatus.pending,
    'in_review' || 'open' => CatalogReviewStatus.inReview,
    'conflict' => CatalogReviewStatus.conflict,
    'approved' || 'applied' => CatalogReviewStatus.approved,
    'rejected' || 'reversed' || 'withdrawn' => CatalogReviewStatus.rejected,
    _ => throw const FormatException('Unknown catalog review status.'),
  };
}

Exception _administrationFailure(ProvidentiaApiException error) {
  final title = error.problem.title.toLowerCase();
  return switch (error.statusCode) {
    401 || 403 || 404 => const CatalogForbiddenException(),
    409 when title.contains('revision') =>
      const CatalogStaleRevisionException(),
    409 => const CatalogConflictException(),
    400 || 422 => const CatalogValidationException(),
    _ => const CatalogContractUnavailableException(),
  };
}

List<Map<String, Object?>> _objectRows(
  Map<String, Object?> object,
  String key,
) {
  return _objectList(object[key], key);
}

List<Map<String, Object?>> _objectList(Object? value, String name) {
  if (value is! List<Object?>) {
    throw FormatException('Expected $name list.');
  }
  return value
      .map((entry) {
        if (entry is! Map<String, Object?>) {
          throw FormatException('Expected $name object.');
        }
        return entry;
      })
      .toList(growable: false);
}

Map<String, Object?> _requiredObject(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('Missing $key.');
  }
  return value;
}

Map<String, Object?>? _optionalObject(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an optional object.');
  }
  return value;
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('Expected an optional string.');
  }
  final cleaned = value.trim();
  return cleaned.isEmpty ? null : cleaned;
}

int _positiveInteger(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! int || value < 1) {
    throw FormatException('Missing positive $key.');
  }
  return value;
}

int _nonNegativeInteger(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! int || value < 0) {
    throw FormatException('Missing non-negative $key.');
  }
  return value;
}

bool _boolean(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! bool) {
    throw FormatException('Missing $key.');
  }
  return value;
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?> || value.any((entry) => entry is! String)) {
    throw const FormatException('Expected a string list.');
  }
  return value.cast<String>();
}

bool _sameStrings(List<String> left, List<String> right) {
  return left.length == right.length && left.toSet().containsAll(right);
}
