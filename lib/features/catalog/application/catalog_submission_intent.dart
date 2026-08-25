import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';

enum CatalogContributionIntentType { productIdentity, productImage, storePrice }

/// Non-reversible identity for one exact contribution request.
///
/// The durable store sees only hashes and a UUID. Household identifiers and
/// contribution payload fields never enter its key or value in plaintext.
final class CatalogSubmissionIntentKey {
  CatalogSubmissionIntentKey._({
    required this.storageSlot,
    required this.payloadFingerprint,
  });

  factory CatalogSubmissionIntentKey.forPayload({
    required CatalogContributionIntentType type,
    required String homeId,
    required String sourceEntityId,
    required int expectedConsentRevision,
    required Map<String, Object?> payload,
  }) {
    if (expectedConsentRevision < 1) {
      throw ArgumentError.value(
        expectedConsentRevision,
        'expectedConsentRevision',
        'must be positive',
      );
    }
    final canonicalPayload = _canonicalJson(<String, Object?>{
      'expectedConsentRevision': expectedConsentRevision,
      'payload': payload,
    });
    final payloadFingerprint = sha256
        .convert(utf8.encode(canonicalPayload))
        .toString();
    final slotMaterial = <String>[
      type.name,
      homeId,
      sourceEntityId,
      payloadFingerprint,
    ].join('\n');
    return CatalogSubmissionIntentKey._(
      storageSlot: sha256.convert(utf8.encode(slotMaterial)).toString(),
      payloadFingerprint: payloadFingerprint,
    );
  }

  final String storageSlot;
  final String payloadFingerprint;
}

final class CatalogSubmissionIntent {
  CatalogSubmissionIntent({required this.key, required this.submissionId}) {
    if (!isUuid(submissionId)) {
      throw ArgumentError.value(submissionId, 'submissionId', 'must be a UUID');
    }
  }

  final CatalogSubmissionIntentKey key;
  final String submissionId;
}

abstract interface class CatalogSubmissionIntentStore {
  Future<String?> read(CatalogSubmissionIntentKey key);

  Future<void> write(CatalogSubmissionIntent intent);

  Future<void> delete(CatalogSubmissionIntent intent);
}

/// Persists an idempotency UUID before transport and retires it only after a
/// known terminal result. An app restart can therefore replay the same exact
/// payload and consent revision under the same server idempotency key.
final class CatalogSubmissionIntentCoordinator {
  factory CatalogSubmissionIntentCoordinator({
    required CatalogSubmissionIntentStore store,
    String Function()? idGenerator,
  }) => CatalogSubmissionIntentCoordinator._(
    store,
    idGenerator ?? UuidV4Generator().call,
  );

  CatalogSubmissionIntentCoordinator._(this._store, this._idGenerator);

  final CatalogSubmissionIntentStore _store;
  final String Function() _idGenerator;

  Future<CatalogSubmissionIntent> obtain(CatalogSubmissionIntentKey key) async {
    try {
      final existing = await _store.read(key);
      if (existing != null) {
        return CatalogSubmissionIntent(key: key, submissionId: existing);
      }
      final intent = CatalogSubmissionIntent(
        key: key,
        submissionId: _idGenerator(),
      );
      await _store.write(intent);
      return intent;
    } on CatalogContributionUnavailableException {
      rethrow;
    } on Object {
      throw const CatalogContributionUnavailableException();
    }
  }

  Future<void> retire(CatalogSubmissionIntent intent) async {
    try {
      await _store.delete(intent);
    } on CatalogContributionUnavailableException {
      rethrow;
    } on Object {
      throw const CatalogContributionUnavailableException();
    }
  }
}

final class MemoryCatalogSubmissionIntentStore
    implements CatalogSubmissionIntentStore {
  final Map<String, String> _ids = <String, String>{};

  @override
  Future<String?> read(CatalogSubmissionIntentKey key) async =>
      _ids[key.storageSlot];

  @override
  Future<void> write(CatalogSubmissionIntent intent) async {
    _ids[intent.key.storageSlot] = intent.submissionId;
  }

  @override
  Future<void> delete(CatalogSubmissionIntent intent) async {
    if (_ids[intent.key.storageSlot] == intent.submissionId) {
      _ids.remove(intent.key.storageSlot);
    }
  }
}

String _canonicalJson(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList(growable: false)..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List<Object?>) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  if (value == null || value is String || value is num || value is bool) {
    return jsonEncode(value);
  }
  throw ArgumentError.value(value, 'payload', 'contains an unsupported value');
}
