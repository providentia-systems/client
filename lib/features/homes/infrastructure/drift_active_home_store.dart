import 'package:drift/drift.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/features/homes/application/home_ports.dart';

/// Non-authoritative local preference; authorization is always revalidated by
/// `listHomes` and `switchHome` before this value is used.
final class DriftActiveHomeStore implements ActiveHomeStore {
  const DriftActiveHomeStore(this._database);

  static const String _partition = '__local-profile__';
  static const String _entityType = 'client.active-home';
  static const String _entityId = 'active';

  final AppDatabase _database;

  @override
  Future<String?> read() async {
    final row =
        await (_database.select(_database.localRecords)..where(
              (record) =>
                  record.homeId.equals(_partition) &
                  record.entityType.equals(_entityType) &
                  record.entityId.equals(_entityId),
            ))
            .getSingleOrNull();
    final value = row?.payload.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String homeId) async {
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
    await _database
        .into(_database.localRecords)
        .insertOnConflictUpdate(
          LocalRecordsCompanion.insert(
            homeId: _partition,
            entityType: _entityType,
            entityId: _entityId,
            payload: homeId,
            updatedAt: DateTime.now().toUtc(),
            synchronizedAt: const Value<DateTime?>(null),
          ),
        );
  }

  @override
  Future<void> clear() async {
    await (_database.delete(_database.localRecords)..where(
          (record) =>
              record.homeId.equals(_partition) &
              record.entityType.equals(_entityType) &
              record.entityId.equals(_entityId),
        ))
        .go();
  }
}
