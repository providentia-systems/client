import 'package:drift/backends.dart';
import 'package:providentia/core/database/browser_database_contract.dart';
import 'package:sqlite3/common.dart';

/// A memory-only SQLite connection whose durable unit is a whole encrypted
/// snapshot. Drift's sequential delegate lock covers encryption and the durable
/// write, including COMMIT, so no successful write can outrun its checkpoint.
final class CheckpointDatabase extends DelegatedDatabase {
  CheckpointDatabase({
    required CommonDatabase database,
    required Future<void> Function() checkpoint,
    required Future<void> Function() dispose,
  }) : super(
         _CheckpointDelegate(database, checkpoint, dispose),
         isSequential: true,
         logStatements: false,
       );

  Future<bool>? _opening;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _opening ??= _open(user);

  Future<bool> _open(QueryExecutorUser user) async {
    try {
      final opened = await super.ensureOpen(user);
      await (delegate as _CheckpointDelegate).finishOpening();
      return opened;
    } on Object {
      await close();
      rethrow;
    }
  }

  // DelegatedDatabase normally does nothing if never opened; our already-open
  // memory connection and browser lock must be disposed in that case as well.
  @override
  Future<void> close() => delegate.close();
}

final class _CheckpointDelegate extends DatabaseDelegate {
  _CheckpointDelegate(this.database, this.checkpoint, this.dispose);
  final CommonDatabase database;
  final Future<void> Function() checkpoint;
  final Future<void> Function() dispose;
  bool _opened = false;
  bool _initializing = true;
  bool _dirty = true;
  bool _failed = false;
  Future<void>? _closing;
  Future<void>? _pendingCheckpoint;

  @override
  bool get isOpen => _opened;
  @override
  TransactionDelegate get transactionDelegate =>
      const NoTransactionDelegate(start: 'BEGIN IMMEDIATE');
  @override
  late final DbVersionDelegate versionDelegate = _CheckpointVersion(this);

  @override
  Future<void> open(QueryExecutorUser db) async {
    _check();
    _opened = true;
  }

  void _check() {
    if (_failed || _closing != null) {
      throw const BrowserDatabaseProtectionException('database_locked');
    }
  }

  Future<void> finishOpening() async {
    _initializing = false;
    await _persist();
  }

  Future<void> _persist() async {
    if (_initializing || !_dirty || !database.autocommit) return;
    try {
      await (_pendingCheckpoint = checkpoint());
      _dirty = false;
    } on Object {
      // The disk copy remains the last atomic committed checkpoint. Refuse ALL
      // further work; retrying against newer unpersisted memory is unsafe.
      _failed = true;
      throw const BrowserDatabaseProtectionException('checkpoint_failed');
    } finally {
      _pendingCheckpoint = null;
    }
  }

  Future<T> _run<T>(T Function() action, {required bool writes}) async {
    _check();
    late final T result;
    try {
      result = action();
      if (writes) _dirty = true;
    } on Object {
      throw const BrowserDatabaseProtectionException('query_failed');
    }
    await _persist();
    return result;
  }

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) async {
    _check();
    try {
      final prepared = database.prepare(statement, checkNoTail: true);
      try {
        return await _run(
          () => QueryResult.fromRows(prepared.select(args).toList()),
          writes: !prepared.isReadOnly,
        );
      } finally {
        prepared.close();
      }
    } on BrowserDatabaseProtectionException {
      rethrow;
    } on Object {
      throw const BrowserDatabaseProtectionException('query_failed');
    }
  }

  @override
  Future<void> runCustom(String statement, List<Object?> args) {
    // Drift rolls back after a failed COMMIT. The memory transaction already
    // ended; acknowledge only that cleanup without resuming poisoned access.
    if (_failed && statement == 'ROLLBACK TRANSACTION' && database.autocommit) {
      return Future<void>.value();
    }
    return _run(() => database.execute(statement, args), writes: true);
  }

  @override
  Future<int> runInsert(String statement, List<Object?> args) => _run(() {
    database.execute(statement, args);
    return database.lastInsertRowId;
  }, writes: true);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) => _run(() {
    database.execute(statement, args);
    return database.updatedRows;
  }, writes: true);

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _opened = false;
    try {
      try {
        await _pendingCheckpoint;
      } on Object {
        // The failed checkpoint already stopped further work.
      }
      // Never persist an unfinished transaction or failed checkpoint on close.
      database.close();
    } finally {
      await dispose();
    }
  }
}

final class _CheckpointVersion extends DynamicVersionDelegate {
  const _CheckpointVersion(this.delegate);
  final _CheckpointDelegate delegate;

  @override
  Future<int> get schemaVersion async => delegate.database.userVersion;

  @override
  Future<void> setSchemaVersion(int version) async {
    delegate.database.userVersion = version;
    delegate._dirty = true;
  }
}
