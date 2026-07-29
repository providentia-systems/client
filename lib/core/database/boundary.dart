/// Phase 1 boundary marker for the future Drift-backed local database.
///
/// Drift schemas, migrations, repositories, and outbox behavior belong to
/// Phase 3 and are deliberately absent from the foundation.
abstract final class DatabaseBoundary {
  static const String implementationPhase = 'Phase 3';
}
