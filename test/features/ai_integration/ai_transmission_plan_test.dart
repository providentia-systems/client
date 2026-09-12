import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/domain/ai_transmission_plan.dart';

void main() {
  test(
    'disclosure includes exact primary, fallback, and validation endpoints',
    () {
      final plan = AiTransmissionPlan.fromJson(_plan());
      expect(plan.recipientDescriptions, [
        'Primary: openai · primary',
        'Fallback: ollama · fallback · http://192.168.1.20:11434/api/chat',
        'Validation: anthropic · validator',
      ]);
    },
  );

  test('missing bindings and unexpected fields fail closed', () {
    final invalid = <Map<String, Object?>>[
      {..._plan(), 'sha256': 'invalid'},
      {..._plan(), 'settingsRevision': -1},
      {..._plan(), 'extractionProfiles': <Object?>[]},
      {..._plan(), 'extra': true},
      {..._plan()}..remove('validationProfile'),
      {
        ..._plan(),
        'extractionProfiles': [
          {'profileId': 'unbound'},
        ],
      },
      {..._plan(), 'validationProfile': 'unexpected'},
    ];
    for (final json in invalid) {
      expect(() => AiTransmissionPlan.fromJson(json), throwsFormatException);
    }
  });
}

Map<String, Object?> _recipient(
  String id,
  String provider, {
  String? endpoint,
}) => {
  'profileId': id,
  'revision': 1,
  'provider': provider,
  'model': id,
  'endpoint': endpoint,
};

Map<String, Object?> _plan() => {
  'settingsRevision': 2,
  'policyRevision': 4,
  'sha256': 'a' * 64,
  'extractionProfiles': [
    _recipient('primary', 'openai'),
    _recipient(
      'fallback',
      'ollama',
      endpoint: 'http://192.168.1.20:11434/api/chat',
    ),
  ],
  'validationProfile': _recipient('validator', 'anthropic'),
};
