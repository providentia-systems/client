/// Phase 1 boundary marker for secure credentials and device sessions.
///
/// Authentication workflows and secure-store adapters begin in Phase 2.
abstract final class SecurityBoundary {
  static const String implementationPhase = 'Phase 2';
}
