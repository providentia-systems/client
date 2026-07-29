/// Phase 1 boundary marker for synchronization orchestration.
///
/// Local outbox persistence begins in Phase 3 and the server protocol in
/// Phase 4.
abstract final class SynchronizationBoundary {
  static const String implementationPhase = 'Phase 4';
}
