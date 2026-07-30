import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';
import 'package:providentia/features/ai_integration/presentation/ai_controllers.dart';

import 'test_fixtures.dart';

void main() {
  const policy = AiPrivacyPolicy();

  test('strict local permits only an attested direct local route', () {
    final provider = localProvider();
    final media = preparedBatch(purpose: AiExtractionKind.stockPhoto);
    final consent = consentFor(
      provider: provider,
      media: media,
      privacyMode: AiPrivacyMode.strictLocal,
    );

    expect(
      () => policy.authorizeExtraction(
        profile: provider,
        privacyMode: AiPrivacyMode.strictLocal,
        media: media,
        consent: consent,
      ),
      returnsNormally,
    );
  });

  test('strict local rejects an Ollama cloud-routed model', () {
    final provider = localProvider(model: 'qwen3-vl:cloud');
    final media = preparedBatch(purpose: AiExtractionKind.stockPhoto);

    expect(
      () => policy.authorizeExtraction(
        profile: provider,
        privacyMode: AiPrivacyMode.strictLocal,
        media: media,
        consent: consentFor(
          provider: provider,
          media: media,
          privacyMode: AiPrivacyMode.strictLocal,
        ),
      ),
      throwsA(
        isA<AiPolicyViolation>().having(
          (error) => error.code,
          'code',
          'cloud_model_forbidden',
        ),
      ),
    );
  });

  test('cloud extraction fails closed when the backend contract is absent', () {
    final provider = serverProvider(
      availability: AiProviderAvailability.missingBackendContract,
    );
    final media = preparedBatch();

    expect(
      () => policy.authorizeExtraction(
        profile: provider,
        privacyMode: AiPrivacyMode.serverProxyCloud,
        media: media,
        consent: consentFor(provider: provider, media: media),
      ),
      throwsA(
        isA<AiPolicyViolation>().having(
          (error) => error.code,
          'code',
          'provider_contract_unavailable',
        ),
      ),
    );
  });

  test('advanced direct cloud mode remains disabled', () {
    final provider = serverProvider();
    final media = preparedBatch();

    expect(
      () => policy.authorizeExtraction(
        profile: provider,
        privacyMode: AiPrivacyMode.directCloudAdvanced,
        media: media,
        consent: consentFor(
          provider: provider,
          media: media,
          privacyMode: AiPrivacyMode.directCloudAdvanced,
        ),
      ),
      throwsA(
        isA<AiPolicyViolation>().having(
          (error) => error.code,
          'code',
          'direct_cloud_disabled',
        ),
      ),
    );
  });

  test(
    'consent controller invalidates consent when provider revision changes',
    () {
      final provider = serverProvider();
      final media = preparedBatch();
      final controller = AiConsentController(
        provider: provider,
        privacyMode: AiPrivacyMode.serverProxyCloud,
        media: media,
        clock: () => DateTime.utc(2026, 7, 30),
      );
      addTearDown(controller.dispose);

      controller.confirm();
      expect(controller.isConfirmed, isTrue);

      controller.updateContext(
        provider: serverProvider(revision: 2),
        privacyMode: AiPrivacyMode.serverProxyCloud,
        media: media,
      );

      expect(controller.isConfirmed, isFalse);
    },
  );

  test('consent is bound to ordered sanitized media hashes', () {
    final provider = serverProvider();
    final first = preparedBatch();
    final second = preparedBatch(
      hash: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    final originalConsent = consentFor(provider: provider, media: first);

    expect(
      policy.consentMatches(
        profile: provider,
        privacyMode: AiPrivacyMode.serverProxyCloud,
        media: second,
        consent: originalConsent,
      ),
      isFalse,
    );
  });
}
