import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class LocalRecords extends Table {
  TextColumn get homeId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get payload => text()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  BoolColumn get isTombstone => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get synchronizedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    homeId,
    entityType,
    entityId,
  };

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[];
}

class ClientOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get deviceId => text()();
  TextColumn get homeId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operationType => text()();
  IntColumn get baseRevision => integer().nullable()();
  DateTimeColumn get clientTimestamp => dateTime()();

  /// Introduced in schema v2. Existing pending operations are rebased to v1.
  IntColumn get payloadSchemaVersion =>
      integer().withDefault(const Constant(1))();

  TextColumn get payload => text()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastSafeError => text().nullable()();
  TextColumn get state => text()();
  TextColumn get serverCursor => text().nullable()();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{operationId};
}

class LocalSyncCursors extends Table {
  TextColumn get homeId => text()();
  TextColumn get feed => text().withDefault(const Constant('home_changes'))();
  IntColumn get protocolVersion => integer().withDefault(const Constant(1))();
  IntColumn get schemaGeneration => integer().withDefault(const Constant(2))();
  TextColumn get cursor => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    homeId,
    feed,
    protocolVersion,
    schemaGeneration,
  };
}

class RecordTombstones extends Table {
  TextColumn get homeId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  IntColumn get revision => integer()();
  TextColumn get cursor => text()();
  DateTimeColumn get deletedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{
    homeId,
    entityType,
    entityId,
  };
}

class LocalMediaMetadata extends Table {
  TextColumn get mediaId => text()();
  TextColumn get homeId => text()();
  TextColumn get purpose => text()();
  TextColumn get localReference => text()();
  TextColumn get sha256 => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get byteLength => integer().nullable()();
  TextColumn get uploadState =>
      text().withDefault(const Constant('local_only'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{mediaId};
}

class SyncConflictRecords extends Table {
  TextColumn get conflictId => text()();
  TextColumn get operationId => text().unique()();
  TextColumn get homeId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get conflictKind => text()();
  TextColumn get localPayload => text()();
  TextColumn get remotePayload => text().nullable()();
  IntColumn get remoteRevision => integer().nullable()();
  DateTimeColumn get detectedAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get resolution => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{conflictId};
}

@DriftDatabase(
  tables: <Type>[
    LocalRecords,
    ClientOperations,
    LocalSyncCursors,
    RecordTombstones,
    LocalMediaMetadata,
    SyncConflictRecords,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.defaults()
    : super(
        driftDatabase(
          name: 'providentia',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.dart.js'),
          ),
        ),
      );

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        // The default value preserves every pending operation and explicitly
        // rebases its payload to schema version 1.
        await migrator.addColumn(
          clientOperations,
          clientOperations.payloadSchemaVersion,
        );
        await migrator.createTable(localSyncCursors);
        await migrator.createTable(recordTombstones);
        await migrator.createTable(localMediaMetadata);
        await migrator.createTable(syncConflictRecords);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Schema drift is enforced by the exported-schema CI gate, while
      // executable upgrade behavior is covered by the migration tests.
    },
  );
}
