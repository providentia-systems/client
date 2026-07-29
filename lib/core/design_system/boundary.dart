/// Phase 1 boundary marker for the future responsive design system.
///
/// The backend-owned token artifact is pinned under `contracts/design-tokens`.
/// Widgets do not consume it until the approved Phase 3 implementation.
abstract final class DesignSystemBoundary {
  static const String implementationPhase = 'Phase 3';
}
