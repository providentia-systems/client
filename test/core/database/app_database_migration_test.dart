import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';

void main() {
  test('v1 to v2 preserves and rebases pending client operations', () async {
    final executor = NativeDatabase.memory(
      setup: (raw) {
        raw.execute('''
          CREATE TABLE local_records (
            home_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            revision INTEGER NOT NULL DEFAULT 0,
            is_tombstone INTEGER NOT NULL DEFAULT 0
              CHECK (is_tombstone IN (0, 1)),
            updated_at INTEGER NOT NULL,
            synchronized_at INTEGER NULL,
            PRIMARY KEY (home_id, entity_type, entity_id)
          )
        ''');
        raw.execute('''
          CREATE TABLE client_operations (
            operation_id TEXT NOT NULL PRIMARY KEY,
            device_id TEXT NOT NULL,
            home_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation_type TEXT NOT NULL,
            base_revision INTEGER NULL,
            client_timestamp INTEGER NOT NULL,
            payload TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER NULL,
            last_safe_error TEXT NULL,
            state TEXT NOT NULL,
            server_cursor TEXT NULL,
            acknowledged_at INTEGER NULL
          )
        ''');
        raw.execute('''
          INSERT INTO client_operations (
            operation_id, device_id, home_id, entity_type, entity_id,
            operation_type, base_revision, client_timestamp, payload, state
          ) VALUES (
            'pending-1', 'device-1', 'home-1', 'inventory_balance',
            'record-1', 'set_count', NULL, 0, '{"quantity":2}', 'pending'
          )
        ''');
        raw.execute('PRAGMA user_version = 1');
      },
    );
    final database = AppDatabase(executor);
    addTearDown(database.close);

    final pending = await database
        .select(database.clientOperations)
        .getSingle();

    expect(database.schemaVersion, 2);
    expect(pending.operationId, 'pending-1');
    expect(pending.state, 'pending');
    expect(pending.baseRevision, isNull);
    expect(pending.payloadSchemaVersion, 1);
    expect(await database.select(database.localSyncCursors).get(), isEmpty);
    expect(await database.select(database.syncConflictRecords).get(), isEmpty);
  });
}
