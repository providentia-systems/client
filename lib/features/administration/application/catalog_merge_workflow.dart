import 'dart:async';

import 'package:providentia/features/administration/application/catalog_administration_ports.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';

final class CatalogMergeCapabilityException implements Exception {
  const CatalogMergeCapabilityException(this.requiredCapability);

  final CatalogCapability requiredCapability;
}

final class CatalogMergeReasonRequiredException implements Exception {
  const CatalogMergeReasonRequiredException();
}

final class CatalogMergeWorkflow {
  CatalogMergeWorkflow(this._repository);

  final CatalogMergeRepository _repository;
  final Map<String, Future<CatalogMergeResult>> _inFlight =
      <String, Future<CatalogMergeResult>>{};
  final Map<String, CatalogMergeResult> _completed =
      <String, CatalogMergeResult>{};
  final Map<String, String> _commandDigests = <String, String>{};

  Future<CatalogMergePreview> previewMerge({
    required String survivorProductId,
    required List<String> absorbedProductIds,
  }) {
    _require(CatalogCapability.previewMerges);
    if (absorbedProductIds.isEmpty ||
        absorbedProductIds.contains(survivorProductId)) {
      throw ArgumentError(
        'A merge needs a distinct survivor and at least one absorbed product.',
      );
    }
    return _repository.previewMerge(
      survivorProductId: survivorProductId,
      absorbedProductIds: absorbedProductIds,
    );
  }

  Future<CatalogMergePreview> previewReversal({required String mergeEventId}) {
    _require(CatalogCapability.reverseMerges);
    return _repository.previewReversal(mergeEventId: mergeEventId);
  }

  Future<CatalogMergeResult> execute({
    required CatalogMergePreview preview,
    required Map<String, int> currentRevisions,
    required String idempotencyKey,
    required String reason,
  }) {
    final requiredCapability = preview.kind == CatalogMergePlanKind.merge
        ? CatalogCapability.executeMerges
        : CatalogCapability.reverseMerges;
    _require(requiredCapability);
    if (reason.trim().isEmpty) {
      throw const CatalogMergeReasonRequiredException();
    }
    if (!_sameRevisions(preview.expectedRevisions, currentRevisions)) {
      throw const CatalogStaleRevisionException();
    }
    final cleanedReason = reason.trim();
    final digest = _digest(preview, cleanedReason);
    final previousDigest = _commandDigests[idempotencyKey];
    if (previousDigest != null && previousDigest != digest) {
      throw const CatalogConflictException();
    }
    _commandDigests[idempotencyKey] = digest;
    final completed = _completed[idempotencyKey];
    if (completed != null) {
      return Future<CatalogMergeResult>.value(completed);
    }
    final running = _inFlight[idempotencyKey];
    if (running != null) {
      return running;
    }
    final future = _repository.execute(
      preview: preview,
      idempotencyKey: idempotencyKey,
      reason: cleanedReason,
    );
    _inFlight[idempotencyKey] = future;
    unawaited(
      future.then<void>(
        (result) {
          _inFlight.remove(idempotencyKey);
          _completed[idempotencyKey] = result;
        },
        onError: (Object _, StackTrace _) {
          _inFlight.remove(idempotencyKey);
        },
      ),
    );
    return future;
  }

  void _require(CatalogCapability capability) {
    if (!_repository.capabilities.contains(capability)) {
      throw CatalogMergeCapabilityException(capability);
    }
  }

  bool _sameRevisions(Map<String, int> expected, Map<String, int> current) {
    if (expected.length != current.length) {
      return false;
    }
    return expected.entries.every((entry) => current[entry.key] == entry.value);
  }

  String _digest(CatalogMergePreview preview, String reason) {
    final revisions = preview.expectedRevisions.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String>[
      preview.previewId,
      preview.kind.name,
      preview.survivorProductId,
      ...preview.absorbedProductIds,
      ...revisions.map((entry) => '${entry.key}:${entry.value}'),
      reason,
    ].join('|');
  }
}
