import 'package:drift/drift.dart';

/// Safe codes only. Never includes a passphrase, SQL, household data or paths.
final class BrowserDatabaseProtectionException implements Exception {
  const BrowserDatabaseProtectionException(this.code);
  final String code;

  @override
  String toString() => 'Browser database protection is unavailable ($code).';
}

enum BrowserDatabaseState { create, unlock }

/// Local encryption is independent of email-code account authentication.
abstract interface class BrowserDatabaseVault {
  Future<BrowserDatabaseState> prepare();
  Future<BrowserDatabaseSession> unlock(String passphrase);
  Future<void> close();
}

abstract interface class BrowserDatabaseSession {
  QueryExecutor get executor;
  Future<void> close();
}
