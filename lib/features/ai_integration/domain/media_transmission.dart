import 'dart:collection';
import 'dart:convert';

import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/media_intake.dart';

enum TransmissionProviderRole { primaryExtractor, independentValidator }

final class TransmissionProviderBinding {
  const TransmissionProviderBinding({
    required this.role,
    required this.providerId,
    required this.providerRevision,
    required this.displayName,
    required this.transport,
  });

  factory TransmissionProviderBinding.fromProfile({
    required TransmissionProviderRole role,
    required AiProviderProfile profile,
  }) => TransmissionProviderBinding(
    role: role,
    providerId: profile.id,
    providerRevision: profile.revision,
    displayName: profile.displayName,
    transport: profile.transport,
  );

  final TransmissionProviderRole role;
  final String providerId;
  final int providerRevision;
  final String displayName;
  final AiTransport transport;
}

final class AiTransmissionConsent {
  const AiTransmissionConsent({
    required this.manifestId,
    required this.canonicalBinding,
    required this.disclosureVersion,
    required this.confirmedBy,
    required this.confirmedAt,
    required this.explicitlyConfirmed,
  });

  final String manifestId;
  final String canonicalBinding;
  final String disclosureVersion;
  final String confirmedBy;
  final DateTime confirmedAt;
  final bool explicitlyConfirmed;
}

final class AiTransmissionManifest {
  AiTransmissionManifest._({
    required this.id,
    required this.batch,
    required this.privacyMode,
    required List<TransmissionProviderBinding> providers,
    required this.disclosureVersion,
    required this.createdAt,
    required this.applicationServerPersistsMedia,
  }) : providers = UnmodifiableListView<TransmissionProviderBinding>(providers);

  factory AiTransmissionManifest.create({
    required String id,
    required PreparedMediaEnvelope batch,
    required AiPrivacyMode privacyMode,
    required AiProviderProfile primaryProvider,
    AiProviderProfile? validatorProvider,
    required String disclosureVersion,
    required DateTime createdAt,
  }) {
    if (id.trim().isEmpty || disclosureVersion.trim().isEmpty) {
      throw const MediaPolicyViolation(
        code: 'transmission_manifest_metadata_required',
        safeMessage: 'Transmission disclosure metadata is missing.',
      );
    }
    if (primaryProvider.homeId != batch.homeId ||
        (validatorProvider != null &&
            validatorProvider.homeId != batch.homeId)) {
      throw const MediaPolicyViolation(
        code: 'provider_home_mismatch',
        safeMessage: 'The selected providers do not belong to this home.',
      );
    }
    if (validatorProvider != null &&
        validatorProvider.id == primaryProvider.id) {
      throw const MediaPolicyViolation(
        code: 'validator_not_independent',
        safeMessage: 'Choose a different provider for independent validation.',
      );
    }
    if (!primaryProvider.enabled ||
        primaryProvider.availability != AiProviderAvailability.available ||
        (validatorProvider != null &&
            (!validatorProvider.enabled ||
                validatorProvider.availability !=
                    AiProviderAvailability.available))) {
      throw const MediaPolicyViolation(
        code: 'provider_unavailable',
        safeMessage: 'A selected AI provider is not available.',
      );
    }
    _validatePrivacyTransport(privacyMode, primaryProvider.transport);
    if (validatorProvider != null) {
      _validatePrivacyTransport(privacyMode, validatorProvider.transport);
    }
    final providers = <TransmissionProviderBinding>[
      TransmissionProviderBinding.fromProfile(
        role: TransmissionProviderRole.primaryExtractor,
        profile: primaryProvider,
      ),
      if (validatorProvider != null)
        TransmissionProviderBinding.fromProfile(
          role: TransmissionProviderRole.independentValidator,
          profile: validatorProvider,
        ),
    ];
    return AiTransmissionManifest._(
      id: id,
      batch: batch,
      privacyMode: privacyMode,
      providers: providers,
      disclosureVersion: disclosureVersion,
      createdAt: createdAt.toUtc(),
      applicationServerPersistsMedia: false,
    );
  }

  final String id;
  final PreparedMediaEnvelope batch;
  final AiPrivacyMode privacyMode;
  final List<TransmissionProviderBinding> providers;
  final String disclosureVersion;
  final DateTime createdAt;
  final bool applicationServerPersistsMedia;

  MediaAudioPolicy get audioPolicy => batch.audioPolicy;

  bool get originalsRemainLocal =>
      batch.retention.original == OriginalMediaRetention.localOnly;

  bool get sendsToCloud => privacyMode == AiPrivacyMode.serverProxyCloud;

  String get canonicalConsentBinding => jsonEncode(<String, Object?>{
    'manifestVersion': 'providentia-ai-transmission-v1',
    'manifestId': id,
    'batchId': batch.id,
    'homeId': batch.homeId,
    'purpose': batch.purpose.name,
    'privacyMode': privacyMode.name,
    'providers': providers
        .map(
          (provider) => <String, Object?>{
            'role': provider.role.name,
            'id': provider.providerId,
            'revision': provider.providerRevision,
            'transport': provider.transport.name,
          },
        )
        .toList(growable: false),
    'mediaHashes': batch.orderedHashes,
    'totalPreparedBytes': batch.totalPreparedBytes,
    'audioIncluded': false,
    'applicationServerPersistsMedia': applicationServerPersistsMedia,
    'originalsRemainLocal': originalsRemainLocal,
    'disclosureVersion': disclosureVersion,
  });

  void authorize(AiTransmissionConsent consent) {
    if (!consent.explicitlyConfirmed ||
        consent.confirmedBy.trim().isEmpty ||
        consent.manifestId != id ||
        consent.disclosureVersion != disclosureVersion ||
        consent.canonicalBinding != canonicalConsentBinding ||
        consent.confirmedAt.toUtc().isBefore(createdAt)) {
      throw const MediaPolicyViolation(
        code: 'transmission_consent_mismatch',
        safeMessage:
            'Review and confirm the exact providers and media before transmission.',
      );
    }
  }

  AiConsent consentForProvider({
    required AiProviderProfile provider,
    required AiTransmissionConsent consent,
  }) {
    authorize(consent);
    final matches = providers.where(
      (binding) =>
          binding.providerId == provider.id &&
          binding.providerRevision == provider.revision,
    );
    if (matches.length != 1 || provider.homeId != batch.homeId) {
      throw const MediaPolicyViolation(
        code: 'provider_not_in_manifest',
        safeMessage:
            'The provider was not included in the confirmed disclosure.',
      );
    }
    return AiConsent(
      providerId: provider.id,
      providerRevision: provider.revision,
      privacyMode: privacyMode,
      purpose: batch.purpose,
      orderedMediaHashes: batch.orderedHashes,
      disclosureVersion: disclosureVersion,
      confirmedAt: consent.confirmedAt.toUtc(),
    );
  }
}

void _validatePrivacyTransport(AiPrivacyMode mode, AiTransport transport) {
  final valid = switch (mode) {
    AiPrivacyMode.serverProxyCloud => transport == AiTransport.serverProxy,
    AiPrivacyMode.strictLocal => transport == AiTransport.directNative,
    AiPrivacyMode.directCloudAdvanced => false,
  };
  if (!valid) {
    throw const MediaPolicyViolation(
      code: 'privacy_transport_mismatch',
      safeMessage: 'The provider does not match the selected privacy mode.',
    );
  }
}
