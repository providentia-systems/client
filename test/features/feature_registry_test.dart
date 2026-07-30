import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/feature_registry.dart';

void main() {
  test('feature registry exposes every stable bounded context once', () {
    final ids = featureRegistry.map((feature) => feature.id).toList();

    expect(
      ids,
      <String>[
        'identity',
        'homes',
        'catalog',
        'inventory',
        'purchasing',
        'shopping',
        'ai_integration',
        'administration',
        'reporting',
      ],
    );
    expect(ids.toSet(), hasLength(ids.length));
    expect(
      featureRegistry.every(
        (feature) =>
            feature.id.trim().isNotEmpty &&
            feature.displayName.trim().isNotEmpty,
      ),
      isTrue,
    );
  });
}
