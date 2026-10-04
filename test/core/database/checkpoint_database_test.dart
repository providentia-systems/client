import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/browser_database_contract.dart';
import 'package:providentia/core/database/checkpoint_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database raw;
  late AppDatabase database;
  late CheckpointDatabase executor;
  late List<List<Map<String, Object?>>> snapshots;
  late bool fail;
  late int disposed;
  Completer<void>? pending;
  setUp(() {
    raw = sqlite3.openInMemory();
    snapshots = [];
    fail = false;
    disposed = 0;
    pending = null;
    executor = CheckpointDatabase(
      database: raw,
      checkpoint: () async {
        await pending?.future;
        if (fail) throw StateError('synthetic write failure');
        snapshots.add(raw.select('SELECT * FROM local_records').toList());
      },
      dispose: () async {
        disposed++;
      },
    );
    database = AppDatabase(executor);
  });
  tearDown(() => database.close());

  Future<void> write(String id) => database
      .into(database.localRecords)
      .insert(
        LocalRecordsCompanion.insert(
          homeId: 'home',
          entityType: 'item',
          entityId: id,
          payload: '{}',
          updatedAt: DateTime.utc(2026),
        ),
      );

  test(
    'initial migration and schema version are checkpointed exactly once',
    () async {
      await database.select(database.localRecords).get();
      expect(raw.userVersion, 3);
      expect(snapshots, hasLength(1));
      expect(snapshots.single, isEmpty);
      await database.select(database.localRecords).get();
      expect(snapshots, hasLength(1));
    },
  );

  test(
    'transaction and nested savepoint are durable only at outer commit',
    () async {
      await database.select(database.localRecords).get();
      await database.transaction(() async {
        await write('one');
        await database.transaction(() => write('two'));
        expect(snapshots, hasLength(1));
      });
      expect(snapshots, hasLength(2));
      expect(snapshots.last, hasLength(2));
    },
  );

  test('rollback never checkpoints uncommitted work', () async {
    await database.select(database.localRecords).get();
    await expectLater(
      database.transaction(() async {
        await write('one');
        throw StateError('abort');
      }),
      throwsStateError,
    );
    expect(snapshots.every((rows) => rows.isEmpty), isTrue);
    expect(await database.select(database.localRecords).get(), isEmpty);
  });

  test(
    'failed checkpoint poisons reads and writes until cold reopen',
    () async {
      await database.select(database.localRecords).get();
      fail = true;
      await expectLater(
        write('one'),
        throwsA(
          isA<BrowserDatabaseProtectionException>().having(
            (e) => e.code,
            'code',
            'checkpoint_failed',
          ),
        ),
      );
      await expectLater(
        database.select(database.localRecords).get(),
        throwsA(isA<BrowserDatabaseProtectionException>()),
      );
      await expectLater(
        write('two'),
        throwsA(isA<BrowserDatabaseProtectionException>()),
      );
      expect(snapshots.single, isEmpty);
    },
  );

  test('failed COMMIT checkpoint retains prior durable transaction', () async {
    await write('before');
    fail = true;
    await expectLater(
      database.transaction(() async {
        await write('projection');
        await write('outbox');
      }),
      throwsA(isA<BrowserDatabaseProtectionException>()),
    );
    expect(snapshots.last.map((row) => row['entity_id']), ['before']);
    await expectLater(
      database.select(database.localRecords).get(),
      throwsA(isA<BrowserDatabaseProtectionException>()),
    );
  });

  test('write acknowledgement and later reads await persistence', () async {
    await database.select(database.localRecords).get();
    pending = Completer<void>();
    var wrote = false;
    final writeFuture = write('one').then((_) => wrote = true);
    var read = false;
    final readFuture = database
        .select(database.localRecords)
        .get()
        .then((_) => read = true);
    await Future<void>.delayed(Duration.zero);
    expect(wrote, isFalse);
    expect(read, isFalse);
    pending!.complete();
    await Future.wait([writeFuture, readFuture]);
    expect(snapshots.last, hasLength(1));
  });

  test('close waits for active checkpoint and is idempotent', () async {
    await database.select(database.localRecords).get();
    pending = Completer<void>();
    final writing = write('one');
    await Future<void>.delayed(Duration.zero);
    final closing = executor.close();
    expect(disposed, 0);
    pending!.complete();
    await writing;
    await closing;
    await executor.close();
    expect(disposed, 1);
  });

  test(
    'close before Drift opens still disposes memory and key ownership',
    () async {
      await executor.close();
      await executor.close();
      expect(disposed, 1);
      await expectLater(
        database.select(database.localRecords).get(),
        throwsA(isA<BrowserDatabaseProtectionException>()),
      );
    },
  );

  test(
    'RETURNING statements checkpoint writes and batched operations persist',
    () async {
      await database.select(database.localRecords).get();
      await database
          .customSelect(
            "INSERT INTO local_records (home_id, entity_type, entity_id, payload, updated_at) VALUES ('home','item','one','{}',0) RETURNING entity_id",
          )
          .get();
      expect(snapshots.last, hasLength(1));
      await database.batch((batch) {
        batch.insert(
          database.localRecords,
          LocalRecordsCompanion.insert(
            homeId: 'home',
            entityType: 'item',
            entityId: 'two',
            payload: '{}',
            updatedAt: DateTime.utc(2026),
          ),
        );
      });
      expect(snapshots.last, hasLength(2));
    },
  );

  test(
    'update/delete and safe query errors preserve executor behavior',
    () async {
      await write('one');
      expect(
        await database.customUpdate(
          "UPDATE local_records SET revision=2 WHERE entity_id='one'",
        ),
        1,
      );
      expect(snapshots.last.single['revision'], 2);
      await expectLater(
        database.customSelect('SELECT * FROM missing_private_table').get(),
        throwsA(
          isA<BrowserDatabaseProtectionException>().having(
            (e) => e.toString(),
            'safe',
            isNot(contains('missing_private_table')),
          ),
        ),
      );
      await database.delete(database.localRecords).go();
      expect(snapshots.last, isEmpty);
    },
  );
}
