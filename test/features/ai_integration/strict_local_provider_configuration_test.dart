import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/strict_local_provider_configuration.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';

void main() {
  test('ordinary configuration round-trips without a secret field', () {
    final configuration = _configuration(credentialConfigured: true);

    final json = configuration.toJson();
    final decoded = StrictLocalProviderConfiguration.fromJson(json);

    expect(json.keys, isNot(contains('secret')));
    expect(json.values, isNot(contains('native-secret')));
    expect(decoded.profileId, configuration.profileId);
    expect(decoded.endpoint, configuration.endpoint);
    expect(decoded.credentialConfigured, isTrue);
  });

  test(
    'credential is written only through native vault before settings',
    () async {
      final calls = <String>[];
      final vault = _Vault(calls: calls, supportsNativeSecrets: true);
      final store = _Store(calls);
      final service = StrictLocalProviderConfigurationService(
        store: store,
        credentialVault: vault,
      );

      await service.save(
        configuration: _configuration(credentialConfigured: true),
        replacementSecret: 'native-secret',
      );

      expect(calls, <String>['vault.write', 'vault.contains', 'store.save']);
      expect(store.saved!.toJson().values, isNot(contains('native-secret')));
    },
  );

  test('browser-like vault cannot accept a credential', () async {
    final service = StrictLocalProviderConfigurationService(
      store: _Store(<String>[]),
      credentialVault: _Vault(calls: <String>[], supportsNativeSecrets: false),
    );

    await expectLater(
      service.save(
        configuration: _configuration(credentialConfigured: true),
        replacementSecret: 'must-not-persist',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('disclosure binds endpoint, model, purpose, hashes, and consent', () {
    final profile = _configuration(credentialConfigured: false).toProfile();
    final media = PreparedMediaBatch(
      id: 'batch-1',
      homeId: 'home-1',
      purpose: AiExtractionKind.receipt,
      media: const <PreparedAiMedia>[
        PreparedAiMedia(
          sourceMediaId: 'media-1',
          ephemeralReference: 'ephemeral://1',
          previewReference: 'preview://1',
          sha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          mimeType: 'image/jpeg',
          byteLength: 10,
          width: 10,
          height: 10,
          pageIndex: 0,
        ),
      ],
    );

    final disclosure = StrictLocalConsentFactory.disclosure(
      provider: profile,
      media: media,
    );
    final consent = StrictLocalConsentFactory.confirm(
      provider: profile,
      media: media,
      explicitlyConfirmed: true,
      confirmedAt: DateTime.utc(2026, 8, 11),
    );

    expect(disclosure.providerName, 'Kitchen Ollama');
    expect(disclosure.model, 'llava:latest');
    expect(disclosure.endpoint.origin, 'http://127.0.0.1:11434');
    expect(disclosure.privacyStatement, contains('does not route'));
    expect(consent.privacyMode, AiPrivacyMode.strictLocal);
    expect(consent.orderedMediaHashes, media.orderedHashes);
    expect(
      () => StrictLocalConsentFactory.confirm(
        provider: profile,
        media: media,
        explicitlyConfirmed: false,
        confirmedAt: DateTime.utc(2026, 8, 11),
      ),
      throwsA(isA<Exception>()),
    );
  });
}

StrictLocalProviderConfiguration _configuration({
  required bool credentialConfigured,
}) => StrictLocalProviderConfiguration(
  profileId: 'local-1',
  homeId: 'home-1',
  displayName: 'Kitchen Ollama',
  kind: AiProviderKind.ollama,
  endpoint: Uri.parse('http://127.0.0.1:11434'),
  model: 'llava:latest',
  capabilities: const <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
  },
  credentialConfigured: credentialConfigured,
  attestedAt: DateTime.utc(2026, 8, 11),
  revision: 1,
);

final class _Store implements StrictLocalProviderConfigurationStore {
  _Store(this.calls);

  final List<String> calls;
  StrictLocalProviderConfiguration? saved;

  @override
  Future<StrictLocalProviderConfiguration?> findById({
    required String homeId,
    required String profileId,
  }) async =>
      saved?.homeId == homeId && saved?.profileId == profileId ? saved : null;

  @override
  Future<String?> readActiveProfileId(String homeId) async => null;

  @override
  Future<void> setActiveProfileId({
    required String homeId,
    required String? profileId,
  }) async {}

  @override
  Future<void> delete({
    required String homeId,
    required String profileId,
  }) async {}

  @override
  Future<List<StrictLocalProviderConfiguration>> listForHome(
    String homeId,
  ) async => <StrictLocalProviderConfiguration>[];

  @override
  Future<void> save(StrictLocalProviderConfiguration configuration) async {
    calls.add('store.save');
    saved = configuration;
  }
}

final class _Vault implements CredentialVault {
  _Vault({required this.calls, required this.supportsNativeSecrets});

  final List<String> calls;

  @override
  final bool supportsNativeSecrets;

  bool present = false;

  @override
  Future<bool> contains(String profileId) async {
    calls.add('vault.contains');
    return present;
  }

  @override
  Future<void> delete(String profileId) async {
    calls.add('vault.delete');
    present = false;
  }

  @override
  Future<void> write({
    required String profileId,
    required String secret,
  }) async {
    calls.add('vault.write');
    present = true;
  }
}
