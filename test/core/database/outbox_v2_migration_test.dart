import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';

void main() {
  test(
    'v2 outbox migration preserves every immutable envelope and execution state',
    () async {
      const states = [
        'pending',
        'syncing',
        'retry_wait',
        'blocked_conflict',
        'blocked_validation',
        'blocked_authorization',
        'acknowledged',
        'superseded',
      ];
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('''CREATE TABLE client_operations (
        operation_id TEXT NOT NULL PRIMARY KEY, device_id TEXT NOT NULL,
        home_id TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
        operation_type TEXT NOT NULL, base_revision INTEGER NULL,
        client_timestamp INTEGER NOT NULL, payload_schema_version INTEGER NOT NULL DEFAULT 1,
        payload TEXT NOT NULL, retry_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NULL, last_safe_error TEXT NULL, state TEXT NOT NULL,
        server_cursor TEXT NULL, acknowledged_at INTEGER NULL)''');
            for (var i = 0; i < states.length; i++) {
              raw.execute(
                '''INSERT INTO client_operations
          (operation_id, device_id, home_id, entity_type, entity_id, operation_type,
           base_revision, client_timestamp, payload, retry_count, state, server_cursor)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
                [
                  'operation-$i',
                  'original-device-$i',
                  'home-$i',
                  'item',
                  'item-$i',
                  'create',
                  4,
                  1234,
                  '{"quantity":2}',
                  3,
                  states[i],
                  'original-cursor',
                ],
              );
            }
            raw.execute('PRAGMA user_version = 2');
          },
        ),
      );
      addTearDown(database.close);
      final rows = await database.select(database.clientOperations).get();
      expect(database.schemaVersion, 3);
      expect(rows.length, states.length);
      for (var i = 0; i < states.length; i++) {
        final row = rows.singleWhere(
          (row) => row.operationId == 'operation-$i',
        );
        expect(row.deviceId, 'original-device-$i');
        expect(row.homeId, 'home-$i');
        expect(row.payload, '{"quantity":2}');
        expect(row.baseRevision, 4);
        expect(row.clientTimestamp.millisecondsSinceEpoch, 1234000);
        expect(row.retryCount, 3);
        expect(row.serverCursor, 'original-cursor');
        expect(row.state, states[i]);
        expect(row.originatingAccountId, isNull);
        expect(row.enqueueSequence, isNull);
        expect(row.safeFailureCode, isNull);
        expect(row.requestCorrelationId, isNull);
      }
      expect(await database.allocateOperationSequence(), 1);
      expect(await database.allocateOperationSequence(), 2);
    },
  );
}
