import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/features/ai_integration/application/strict_local_provider_configuration.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';

/// Home-scoped, local-only AI settings. No client operation is created, so
/// these reserved records are never pushed to the synchronization protocol.
final class DriftStrictLocalProviderConfigurationStore
    implements StrictLocalProviderConfigurationStore {
  DriftStrictLocalProviderConfigurationStore(
    this._database, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const String configurationRecordType =
      ClientLocalRecordTypes.strictLocalAiConfiguration;
  static const String selectionRecordType =
      ClientLocalRecordTypes.strictLocalAiSelection;
  static const String _activeEntityId = 'active';

  final AppDatabase _database;
  final DateTime Function() _clock;

  @override
  Future<void> save(StrictLocalProviderConfiguration configuration) {
    _requireScope(configuration.homeId, configuration.profileId);
    final encoded = jsonEncode(configuration.toJson());
    // Round-trip before opening the write transaction. This rejects any
    // representation the strict decoder could not safely restore.
    final decoded = StrictLocalProviderConfiguration.fromJson(
      jsonDecode(encoded) as Map<String, Object?>,
    );
    if (decoded.homeId != configuration.homeId ||
        decoded.profileId != configuration.profileId) {
      throw const FormatException('Local AI profile scope changed on encode.');
    }
    const AiPrivacyPolicy().validateProfile(decoded.toProfile());
    return _database.transaction(() async {
      final current = await _configurationRow(
        homeId: configuration.homeId,
        profileId: configuration.profileId,
      );
      if (current != null) {
        final existing = _decodeConfiguration(
          current,
          expectedHomeId: configuration.homeId,
        );
        if (configuration.revision < existing.revision ||
            configuration.revision == existing.revision &&
                current.payload != encoded) {
          throw StateError('Stale local AI profile replacement was rejected.');
        }
        if (current.payload == encoded) return;
      }
      await _database
          .into(_database.localRecords)
          .insertOnConflictUpdate(
            LocalRecordsCompanion.insert(
              homeId: configuration.homeId,
              entityType: configurationRecordType,
              entityId: configuration.profileId,
              payload: encoded,
              revision: Value<int>(configuration.revision),
              isTombstone: const Value<bool>(false),
              updatedAt: _clock().toUtc(),
              synchronizedAt: const Value<DateTime?>(null),
            ),
          );
    });
  }

  @override
  Future<List<StrictLocalProviderConfiguration>> listForHome(
    String homeId,
  ) async {
    _requireHome(homeId);
    final query = _database.select(_database.localRecords)
      ..where(
        (row) =>
            row.homeId.equals(homeId) &
            row.entityType.equals(configurationRecordType) &
            row.isTombstone.equals(false),
      )
      ..orderBy(<OrderingTerm Function(LocalRecords)>[
        (row) => OrderingTerm.asc(row.entityId),
      ]);
    final rows = await query.get();
    return rows
        .map((row) => _decodeConfiguration(row, expectedHomeId: homeId))
        .toList(growable: false);
  }

  @override
  Future<StrictLocalProviderConfiguration?> findById({
    required String homeId,
    required String profileId,
  }) async {
    _requireScope(homeId, profileId);
    final row = await _configurationRow(homeId: homeId, profileId: profileId);
    return row == null
        ? null
        : _decodeConfiguration(row, expectedHomeId: homeId);
  }

  @override
  Future<String?> readActiveProfileId(String homeId) async {
    _requireHome(homeId);
    final row = await _selectionRow(homeId);
    if (row == null) return null;
    final decoded = jsonDecode(row.payload);
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(const <String>{
          'profileId',
        }).isNotEmpty ||
        !decoded.containsKey('profileId') ||
        decoded['profileId'] is! String ||
        (decoded['profileId']! as String).trim().isEmpty) {
      throw const FormatException('Invalid active local AI profile record.');
    }
    final profileId = decoded['profileId']! as String;
    if (await findById(homeId: homeId, profileId: profileId) == null) {
      throw const FormatException(
        'The selected local AI profile is unavailable.',
      );
    }
    return profileId;
  }

  @override
  Future<void> setActiveProfileId({
    required String homeId,
    required String? profileId,
  }) {
    _requireHome(homeId);
    return _database.transaction(() async {
      if (profileId == null) {
        await _deleteSelection(homeId);
        return;
      }
      _requireScope(homeId, profileId);
      if (await _configurationRow(homeId: homeId, profileId: profileId) ==
          null) {
        throw StateError('The active local AI profile does not exist.');
      }
      await _database
          .into(_database.localRecords)
          .insertOnConflictUpdate(
            LocalRecordsCompanion.insert(
              homeId: homeId,
              entityType: selectionRecordType,
              entityId: _activeEntityId,
              payload: jsonEncode(<String, Object?>{'profileId': profileId}),
              revision: const Value<int>(1),
              isTombstone: const Value<bool>(false),
              updatedAt: _clock().toUtc(),
              synchronizedAt: const Value<DateTime?>(null),
            ),
          );
    });
  }

  @override
  Future<void> delete({required String homeId, required String profileId}) {
    _requireScope(homeId, profileId);
    return _database.transaction(() async {
      await (_database.delete(_database.localRecords)..where(
            (row) =>
                row.homeId.equals(homeId) &
                row.entityType.equals(configurationRecordType) &
                row.entityId.equals(profileId),
          ))
          .go();
      final active = await _selectionRow(homeId);
      if (active != null) {
        final decoded = jsonDecode(active.payload);
        if (decoded is Map<String, Object?> &&
            decoded['profileId'] == profileId) {
          await _deleteSelection(homeId);
        }
      }
    });
  }

  Future<LocalRecord?> _configurationRow({
    required String homeId,
    required String profileId,
  }) =>
      (_database.select(_database.localRecords)..where(
            (row) =>
                row.homeId.equals(homeId) &
                row.entityType.equals(configurationRecordType) &
                row.entityId.equals(profileId) &
                row.isTombstone.equals(false),
          ))
          .getSingleOrNull();

  Future<LocalRecord?> _selectionRow(String homeId) =>
      (_database.select(_database.localRecords)..where(
            (row) =>
                row.homeId.equals(homeId) &
                row.entityType.equals(selectionRecordType) &
                row.entityId.equals(_activeEntityId) &
                row.isTombstone.equals(false),
          ))
          .getSingleOrNull();

  Future<void> _deleteSelection(String homeId) =>
      (_database.delete(_database.localRecords)..where(
            (row) =>
                row.homeId.equals(homeId) &
                row.entityType.equals(selectionRecordType) &
                row.entityId.equals(_activeEntityId),
          ))
          .go();

  StrictLocalProviderConfiguration _decodeConfiguration(
    LocalRecord row, {
    required String expectedHomeId,
  }) {
    if (row.homeId != expectedHomeId ||
        row.entityType != configurationRecordType ||
        row.isTombstone) {
      throw const FormatException('Invalid local AI profile storage scope.');
    }
    final decoded = jsonDecode(row.payload);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid local AI profile payload.');
    }
    final configuration = StrictLocalProviderConfiguration.fromJson(decoded);
    if (configuration.homeId != row.homeId ||
        configuration.profileId != row.entityId ||
        configuration.revision != row.revision) {
      throw const FormatException('Local AI profile key mismatch.');
    }
    const AiPrivacyPolicy().validateProfile(configuration.toProfile());
    return configuration;
  }

  void _requireHome(String homeId) {
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
  }

  void _requireScope(String homeId, String profileId) {
    _requireHome(homeId);
    if (profileId.trim().isEmpty) {
      throw ArgumentError.value(profileId, 'profileId', 'must not be empty');
    }
  }
}
