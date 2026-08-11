import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/features/shopping/application/online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';

/// Device-local last-verified cache. It is never an outbox and never creates
/// server suggestion state; access revocation purges it through the cache port
/// and the existing whole-home purge.
final class DriftShoppingSuggestionCache implements ShoppingSuggestionCache {
  const DriftShoppingSuggestionCache(this._database);

  static const entityType = ClientLocalRecordTypes.shoppingSuggestionCache;
  static const _entityId = 'verified-feed';

  final AppDatabase _database;

  @override
  Future<VerifiedShoppingSuggestionSnapshot?> read({
    required String homeId,
  }) async {
    _requireUuid(homeId, 'homeId');
    final row =
        await (_database.select(_database.localRecords)..where(
              (record) =>
                  record.homeId.equals(homeId) &
                  record.entityType.equals(entityType) &
                  record.entityId.equals(_entityId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    try {
      final payload = jsonDecode(row.payload);
      if (payload is! Map<String, Object?> || payload['homeId'] != homeId) {
        throw const FormatException('Invalid suggestion cache scope.');
      }
      final values = payload['suggestions'];
      if (values is! List<Object?>) {
        throw const FormatException('Invalid suggestion cache rows.');
      }
      return VerifiedShoppingSuggestionSnapshot(
        homeId: homeId,
        verifiedAt: _dateTime(payload['verifiedAt'], 'verifiedAt'),
        suggestions: values
            .map((value) => _decodeSuggestion(value, homeId))
            .toList(growable: false),
      );
    } on FormatException {
      await clear(homeId: homeId);
      return null;
    } on ArgumentError {
      await clear(homeId: homeId);
      return null;
    } on StateError {
      await clear(homeId: homeId);
      return null;
    }
  }

  @override
  Future<void> replace(VerifiedShoppingSuggestionSnapshot snapshot) async {
    _requireUuid(snapshot.homeId, 'homeId');
    if (snapshot.suggestions.any(
      (suggestion) => suggestion.homeId != snapshot.homeId,
    )) {
      throw StateError('Cross-home suggestion cache write rejected.');
    }
    await _database
        .into(_database.localRecords)
        .insertOnConflictUpdate(
          LocalRecordsCompanion.insert(
            homeId: snapshot.homeId,
            entityType: entityType,
            entityId: _entityId,
            payload: jsonEncode(<String, Object?>{
              'homeId': snapshot.homeId,
              'verifiedAt': snapshot.verifiedAt.toUtc().toIso8601String(),
              'suggestions': snapshot.suggestions
                  .map(_encodeSuggestion)
                  .toList(growable: false),
            }),
            revision: const Value<int>(0),
            isTombstone: const Value<bool>(false),
            updatedAt: snapshot.verifiedAt.toUtc(),
            synchronizedAt: const Value<DateTime?>(null),
          ),
        );
  }

  @override
  Future<void> clear({required String homeId}) async {
    _requireUuid(homeId, 'homeId');
    await (_database.delete(_database.localRecords)..where(
          (record) =>
              record.homeId.equals(homeId) &
              record.entityType.equals(entityType),
        ))
        .go();
  }
}

Map<String, Object?> _encodeSuggestion(OnlineShoppingSuggestion suggestion) =>
    <String, Object?>{
      'id': suggestion.id,
      'homeId': suggestion.homeId,
      'homeProductId': suggestion.homeProductId,
      'productName': suggestion.productName,
      'packText': suggestion.packText,
      'expectedDemand': suggestion.expectedDemand.value,
      'safetyStock': suggestion.safetyStock.value,
      'factualStock': suggestion.factualStock.value,
      'usableStock': suggestion.usableStock.value,
      'requiredQuantity': suggestion.requiredQuantity.value,
      'selectedPackId': suggestion.selectedPackId,
      'packCount': suggestion.packCount,
      'confidenceScore': suggestion.confidenceScore.value,
      'confidenceBand': suggestion.confidenceBand.name,
      'status': suggestion.status.name,
      'expiresAt': suggestion.expiresAt.toUtc().toIso8601String(),
      'modelVersion': suggestion.modelVersion,
      'asOf': suggestion.asOf.toUtc().toIso8601String(),
      'inputWatermark': suggestion.inputWatermark,
    };

OnlineShoppingSuggestion _decodeSuggestion(Object? value, String homeId) {
  if (value is! Map<String, Object?> || value['homeId'] != homeId) {
    throw const FormatException('Invalid cached suggestion scope.');
  }
  final id = _uuid(value, 'id');
  final homeProductId = _uuid(value, 'homeProductId');
  final selectedPackId = _optionalUuid(value['selectedPackId']);
  final watermark = _string(value, 'inputWatermark');
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(watermark)) {
    throw const FormatException('Invalid cached suggestion watermark.');
  }
  return OnlineShoppingSuggestion(
    id: id,
    homeId: homeId,
    homeProductId: homeProductId,
    productName: _string(value, 'productName'),
    packText: _optionalString(value['packText']),
    expectedDemand: ExactDecimal(_string(value, 'expectedDemand')),
    safetyStock: ExactDecimal(_string(value, 'safetyStock')),
    factualStock: ExactDecimal(_string(value, 'factualStock')),
    usableStock: ExactDecimal(_string(value, 'usableStock')),
    requiredQuantity: ExactDecimal(_string(value, 'requiredQuantity')),
    selectedPackId: selectedPackId,
    packCount: _optionalInteger(value['packCount']),
    confidenceScore: ExactDecimal(_string(value, 'confidenceScore')),
    confidenceBand: ShoppingSuggestionConfidenceBand.values.byName(
      _string(value, 'confidenceBand'),
    ),
    status: OnlineShoppingSuggestionStatus.values.byName(
      _string(value, 'status'),
    ),
    expiresAt: _dateTime(value['expiresAt'], 'expiresAt'),
    modelVersion: _string(value, 'modelVersion'),
    asOf: _dateTime(value['asOf'], 'asOf'),
    inputWatermark: watermark,
  );
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty || value.length > 500) {
    throw FormatException('Invalid cached "$key".');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.length > 500) {
    throw const FormatException('Invalid cached optional text.');
  }
  return value;
}

String _uuid(Map<String, Object?> object, String key) {
  final value = _string(object, key);
  _requireUuid(value, key);
  return value;
}

String? _optionalUuid(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Invalid cached optional UUID.');
  }
  _requireUuid(value, 'optional UUID');
  return value;
}

int? _optionalInteger(Object? value) {
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw const FormatException('Invalid cached optional integer.');
  }
  return value;
}

DateTime _dateTime(Object? value, String label) {
  if (value is! String || !RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw FormatException('Invalid cached "$label".');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid cached "$label".');
  return parsed.toUtc();
}

void _requireUuid(String value, String label) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value)) {
    throw FormatException('Invalid "$label" UUID.');
  }
}
