import 'package:drift/drift.dart';
import 'package:providentia/core/database/browser_database_contract.dart';

/// Browser persistence requires an explicitly unlocked, memory-only executor.
/// Never fall back to the legacy plaintext database or a persisted browser key.
QueryExecutor openPlatformDatabase() =>
    throw const BrowserDatabaseProtectionException('unlock_required');
