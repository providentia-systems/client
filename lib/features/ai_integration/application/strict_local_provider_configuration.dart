import 'dart:collection';

import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';

/// Persistable strict-local settings. This type intentionally has no secret
/// field so ordinary preferences/databases cannot accidentally retain one.
final class StrictLocalProviderConfiguration {
  StrictLocalProviderConfiguration({
    required this.profileId,
    required this.homeId,
    required this.displayName,
    required this.kind,
    required this.endpoint,
    required this.model,
    required Set<AiCapability> capabilities,
    required this.credentialConfigured,
    required this.attestedAt,
    required this.revision,
    this.enabled = true,
  }) : capabilities = UnmodifiableSetView<AiCapability>(
         Set<AiCapability>.of(capabilities),
       );

  factory StrictLocalProviderConfiguration.fromJson(Map<String, Object?> json) {
    const keys = <String>{
      'profileId',
      'homeId',
      'displayName',
      'kind',
      'endpoint',
      'model',
      'capabilities',
      'credentialConfigured',
      'attestedAt',
      'revision',
      'enabled',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException('Invalid strict-local configuration keys.');
    }
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid $key.');
      }
      return value;
    }

    final kindName = requiredString('kind');
    final kind = AiProviderKind.values
        .where(
          (item) =>
              item.name == kindName &&
              (item == AiProviderKind.ollama ||
                  item == AiProviderKind.openAiCompatible),
        )
        .firstOrNull;
    final rawCapabilities = json['capabilities'];
    final capabilities = rawCapabilities is List<Object?>
        ? rawCapabilities.map((value) {
            if (value is! String) {
              throw const FormatException('Invalid capability.');
            }
            return AiCapability.values
                .where((item) => item.name == value)
                .firstOrNull;
          }).toSet()
        : null;
    final endpoint = Uri.tryParse(requiredString('endpoint'));
    final attestedAt = DateTime.tryParse(requiredString('attestedAt'));
    final revision = json['revision'];
    final credentialConfigured = json['credentialConfigured'];
    final enabled = json['enabled'];
    if (kind == null ||
        capabilities == null ||
        capabilities.contains(null) ||
        endpoint == null ||
        attestedAt == null ||
        revision is! int ||
        revision < 1 ||
        credentialConfigured is! bool ||
        enabled is! bool) {
      throw const FormatException('Invalid strict-local configuration.');
    }
    return StrictLocalProviderConfiguration(
      profileId: requiredString('profileId'),
      homeId: requiredString('homeId'),
      displayName: requiredString('displayName'),
      kind: kind,
      endpoint: endpoint,
      model: requiredString('model'),
      capabilities: capabilities.cast<AiCapability>(),
      credentialConfigured: credentialConfigured,
      attestedAt: attestedAt,
      revision: revision,
      enabled: enabled,
    );
  }

  final String profileId;
  final String homeId;
  final String displayName;
  final AiProviderKind kind;
  final Uri endpoint;
  final String model;
  final Set<AiCapability> capabilities;
  final bool credentialConfigured;
  final DateTime attestedAt;
  final int revision;
  final bool enabled;

  AiProviderProfile toProfile() => AiProviderProfile(
    id: profileId,
    homeId: homeId,
    displayName: displayName,
    kind: kind,
    transport: AiTransport.directNative,
    protocol: switch (kind) {
      AiProviderKind.ollama => AiEndpointProtocol.ollamaChat,
      AiProviderKind.openAiCompatible =>
        AiEndpointProtocol.openAiChatCompletions,
      _ => throw ArgumentError.value(kind, 'kind', 'not a local provider'),
    },
    endpoint: endpoint,
    model: model,
    capabilities: capabilities,
    availability: AiProviderAvailability.available,
    credentialConfigured: credentialConfigured,
    strictLocalAttestedAt: attestedAt,
    revision: revision,
    enabled: enabled,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'profileId': profileId,
    'homeId': homeId,
    'displayName': displayName,
    'kind': kind.name,
    'endpoint': endpoint.toString(),
    'model': model,
    'capabilities': capabilities.map((item) => item.name).toList()..sort(),
    'credentialConfigured': credentialConfigured,
    'attestedAt': attestedAt.toUtc().toIso8601String(),
    'revision': revision,
    'enabled': enabled,
  };
}

abstract interface class StrictLocalProviderConfigurationStore {
  Future<void> save(StrictLocalProviderConfiguration configuration);

  Future<List<StrictLocalProviderConfiguration>> listForHome(String homeId);

  Future<StrictLocalProviderConfiguration?> findById({
    required String homeId,
    required String profileId,
  });

  Future<String?> readActiveProfileId(String homeId);

  Future<void> setActiveProfileId({
    required String homeId,
    required String? profileId,
  });

  Future<void> delete({required String homeId, required String profileId});
}

final class DisabledCredentialVault implements CredentialVault {
  const DisabledCredentialVault();

  @override
  bool get supportsNativeSecrets => false;

  @override
  Future<bool> contains(String profileId) async => false;

  @override
  Future<void> delete(String profileId) async {}

  @override
  Future<void> write({
    required String profileId,
    required String secret,
  }) => throw const AiPolicyViolation(
    code: 'native_credential_store_required',
    safeMessage:
        'Local provider credentials require a native secure credential store.',
  );
}

final class StrictLocalProviderConfigurationService {
  const StrictLocalProviderConfigurationService({
    required StrictLocalProviderConfigurationStore store,
    required CredentialVault credentialVault,
    AiPrivacyPolicy privacyPolicy = const AiPrivacyPolicy(),
  }) : this._(store, credentialVault, privacyPolicy);

  const StrictLocalProviderConfigurationService._(
    this._store,
    this._credentialVault,
    this._privacyPolicy,
  );

  final StrictLocalProviderConfigurationStore _store;
  final CredentialVault _credentialVault;
  final AiPrivacyPolicy _privacyPolicy;

  Future<void> save({
    required StrictLocalProviderConfiguration configuration,
    String? replacementSecret,
  }) async {
    final profile = configuration.toProfile();
    _privacyPolicy.validateProfile(profile);
    if (replacementSecret != null) {
      if (!_credentialVault.supportsNativeSecrets) {
        throw const AiPolicyViolation(
          code: 'native_credential_store_required',
          safeMessage:
              'Local provider credentials require the native secure credential store.',
        );
      }
      if (replacementSecret.trim().isEmpty) {
        throw const AiPolicyViolation(
          code: 'empty_local_credential',
          safeMessage: 'Enter a non-empty local provider credential.',
        );
      }
      await _credentialVault.write(
        profileId: configuration.profileId,
        secret: replacementSecret,
      );
    }
    final credentialPresent = await _credentialVault.contains(
      configuration.profileId,
    );
    if (configuration.credentialConfigured != credentialPresent) {
      throw const AiPolicyViolation(
        code: 'credential_state_mismatch',
        safeMessage:
            'The local provider credential state could not be verified.',
      );
    }
    await _store.save(configuration);
  }

  Future<void> delete({
    required String homeId,
    required String profileId,
  }) async {
    await _credentialVault.delete(profileId);
    await _store.delete(homeId: homeId, profileId: profileId);
  }
}

final class StrictLocalPrivacyDisclosure {
  StrictLocalPrivacyDisclosure({
    required this.providerName,
    required this.model,
    required this.endpoint,
    required this.purpose,
    required List<String> orderedMediaHashes,
  }) : orderedMediaHashes = List<String>.unmodifiable(orderedMediaHashes);

  final String providerName;
  final String model;
  final Uri endpoint;
  final AiExtractionKind purpose;
  final List<String> orderedMediaHashes;

  String get privacyStatement =>
      'Prepared image bytes will be sent directly to $providerName at '
      '${endpoint.origin}. Providentia does not route this request through its '
      'cloud service. The local provider controls its own processing and retention.';
}

abstract final class StrictLocalConsentFactory {
  static StrictLocalPrivacyDisclosure disclosure({
    required AiProviderProfile provider,
    required PreparedMediaBatch media,
  }) {
    if (provider.endpoint == null ||
        provider.transport != AiTransport.directNative ||
        provider.homeId != media.homeId) {
      throw const AiPolicyViolation(
        code: 'invalid_strict_local_disclosure',
        safeMessage: 'The strict local disclosure could not be prepared.',
      );
    }
    return StrictLocalPrivacyDisclosure(
      providerName: provider.displayName,
      model: provider.model,
      endpoint: provider.endpoint!,
      purpose: media.purpose,
      orderedMediaHashes: List<String>.unmodifiable(media.orderedHashes),
    );
  }

  static AiConsent confirm({
    required AiProviderProfile provider,
    required PreparedMediaBatch media,
    required bool explicitlyConfirmed,
    required DateTime confirmedAt,
  }) {
    if (!explicitlyConfirmed) {
      throw const AiPolicyViolation(
        code: 'consent_required',
        safeMessage: 'Review the endpoint and privacy details, then confirm.',
      );
    }
    disclosure(provider: provider, media: media);
    return AiConsent(
      providerId: provider.id,
      providerRevision: provider.revision,
      privacyMode: AiPrivacyMode.strictLocal,
      purpose: media.purpose,
      orderedMediaHashes: media.orderedHashes,
      disclosureVersion: AiPrivacyPolicy.disclosureVersion,
      confirmedAt: confirmedAt,
    );
  }
}
