/// Stable description of a bounded client feature.
///
/// Phase 1 registers boundaries only. It does not implement feature workflows.
class FeatureDescriptor {
  const FeatureDescriptor({required this.id, required this.displayName});

  final String id;
  final String displayName;
}
