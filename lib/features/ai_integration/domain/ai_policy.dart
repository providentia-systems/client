import 'package:providentia/features/ai_integration/domain/ai_models.dart';

final class AiPolicyViolation implements Exception {
  const AiPolicyViolation({required this.code, required this.safeMessage});

  final String code;
  final String safeMessage;

  @override
  String toString() => 'AiPolicyViolation($code): $safeMessage';
}

final class AiPrivacyPolicy {
  const AiPrivacyPolicy();

  static const String disclosureVersion = 'providentia-ai-privacy-v1';
  static const int maximumPreparedPages = 20;
  static const int maximumPreparedBytesPerPage = 20 * 1024 * 1024;
  static const int maximumPreparedPixelsPerPage = 40 * 1000 * 1000;
  static final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
  static const Set<String> _preparedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  void validateProfile(AiProviderProfile profile) {
    if (profile.id.trim().isEmpty ||
        profile.homeId.trim().isEmpty ||
        profile.displayName.trim().isEmpty ||
        profile.model.trim().isEmpty) {
      throw const AiPolicyViolation(
        code: 'invalid_provider_profile',
        safeMessage: 'Complete all required provider settings.',
      );
    }
    if (!profile.enabled) {
      throw const AiPolicyViolation(
        code: 'provider_disabled',
        safeMessage: 'This AI provider is disabled.',
      );
    }
    if (profile.availability != AiProviderAvailability.available) {
      throw AiPolicyViolation(
        code:
            profile.availability ==
                AiProviderAvailability.missingBackendContract
            ? 'provider_contract_unavailable'
            : 'provider_unavailable',
        safeMessage:
            profile.availability ==
                AiProviderAvailability.missingBackendContract
            ? 'The secure provider service is not available yet.'
            : 'This AI provider is not available.',
      );
    }
    if (!profile.capabilities.contains(AiCapability.vision) ||
        !profile.capabilities.contains(AiCapability.strictJsonSchema)) {
      throw const AiPolicyViolation(
        code: 'required_capability_missing',
        safeMessage:
            'This provider cannot safely return structured image results.',
      );
    }
    if (profile.kind == AiProviderKind.openAi &&
        profile.transport != AiTransport.serverProxy) {
      throw const AiPolicyViolation(
        code: 'openai_requires_proxy',
        safeMessage:
            'OpenAI must use the secure Providentia server connection.',
      );
    }
    if (profile.kind == AiProviderKind.openAi &&
        !profile.capabilities.contains(AiCapability.storeFalse)) {
      throw const AiPolicyViolation(
        code: 'store_false_required',
        safeMessage:
            'The OpenAI connection must support disabled response storage.',
      );
    }
    if (profile.transport == AiTransport.serverProxy &&
        !profile.credentialConfigured) {
      throw const AiPolicyViolation(
        code: 'provider_not_configured',
        safeMessage: 'Configure this provider before using AI.',
      );
    }
    if (profile.transport == AiTransport.directNative) {
      final endpoint = profile.endpoint;
      if (endpoint == null || !_isSafeLocalEndpoint(endpoint)) {
        throw const AiPolicyViolation(
          code: 'unsafe_local_endpoint',
          safeMessage:
              'Strict local AI requires a loopback or private-network endpoint.',
        );
      }
      if (endpoint.userInfo.isNotEmpty ||
          endpoint.query.isNotEmpty ||
          endpoint.fragment.isNotEmpty) {
        throw const AiPolicyViolation(
          code: 'unsafe_endpoint_components',
          safeMessage:
              'The local endpoint cannot contain credentials, a query, or a fragment.',
        );
      }
    }
  }

  void authorizeExtraction({
    required AiProviderProfile profile,
    required AiPrivacyMode privacyMode,
    required PreparedMediaBatch media,
    required AiConsent consent,
  }) {
    validateProfile(profile);
    if (profile.homeId != media.homeId) {
      throw const AiPolicyViolation(
        code: 'home_scope_mismatch',
        safeMessage: 'The provider and media must belong to the active home.',
      );
    }
    switch (privacyMode) {
      case AiPrivacyMode.serverProxyCloud:
        if (profile.transport != AiTransport.serverProxy) {
          throw const AiPolicyViolation(
            code: 'proxy_route_required',
            safeMessage:
                'This provider is not configured for secure cloud use.',
          );
        }
      case AiPrivacyMode.strictLocal:
        if (profile.transport != AiTransport.directNative ||
            profile.kind == AiProviderKind.openAi ||
            profile.strictLocalAttestedAt == null) {
          throw const AiPolicyViolation(
            code: 'strict_local_not_attested',
            safeMessage:
                'Strict local mode requires an attested local or self-hosted provider.',
          );
        }
        if (_looksLikeOllamaCloudModel(profile.model)) {
          throw const AiPolicyViolation(
            code: 'cloud_model_forbidden',
            safeMessage:
                'Cloud-routed models are disabled in strict local mode.',
          );
        }
      case AiPrivacyMode.directCloudAdvanced:
        throw const AiPolicyViolation(
          code: 'direct_cloud_disabled',
          safeMessage:
              'Direct cloud credentials are disabled. Use the secure server connection.',
        );
    }
    if (media.media.isEmpty) {
      throw const AiPolicyViolation(
        code: 'media_required',
        safeMessage: 'Add at least one image or receipt page.',
      );
    }
    if (media.media.length > maximumPreparedPages) {
      throw const AiPolicyViolation(
        code: 'media_page_limit',
        safeMessage: 'Select no more than 20 images or receipt pages.',
      );
    }
    if (media.media.length > 1 &&
        !profile.capabilities.contains(AiCapability.multiImage)) {
      throw const AiPolicyViolation(
        code: 'multi_image_unsupported',
        safeMessage: 'This provider cannot safely process multiple images.',
      );
    }
    final pageIndexes = <int>{};
    for (final item in media.media) {
      final pixels = item.width * item.height;
      if (!_sha256Pattern.hasMatch(item.sha256) ||
          !_preparedMimeTypes.contains(item.mimeType) ||
          item.ephemeralReference.trim().isEmpty ||
          item.previewReference.trim().isEmpty ||
          item.byteLength <= 0 ||
          item.byteLength > maximumPreparedBytesPerPage ||
          item.width <= 0 ||
          item.height <= 0 ||
          pixels > maximumPreparedPixelsPerPage ||
          item.pageIndex < 0 ||
          !pageIndexes.add(item.pageIndex)) {
        throw const AiPolicyViolation(
          code: 'unsafe_prepared_media',
          safeMessage:
              'A selected image did not pass Providentia media safety checks.',
        );
      }
    }
    if (!_consentMatches(profile, privacyMode, media, consent)) {
      throw const AiPolicyViolation(
        code: 'consent_required',
        safeMessage:
            'Review the provider and privacy details, then confirm again.',
      );
    }
  }

  bool consentMatches({
    required AiProviderProfile profile,
    required AiPrivacyMode privacyMode,
    required PreparedMediaBatch media,
    required AiConsent consent,
  }) => _consentMatches(profile, privacyMode, media, consent);

  bool _consentMatches(
    AiProviderProfile profile,
    AiPrivacyMode privacyMode,
    PreparedMediaBatch media,
    AiConsent consent,
  ) {
    if (consent.providerId != profile.id ||
        consent.providerRevision != profile.revision ||
        consent.privacyMode != privacyMode ||
        consent.purpose != media.purpose ||
        consent.disclosureVersion != disclosureVersion ||
        consent.orderedMediaHashes.length != media.media.length) {
      return false;
    }
    for (var index = 0; index < media.media.length; index++) {
      if (consent.orderedMediaHashes[index] != media.media[index].sha256) {
        return false;
      }
    }
    return true;
  }

  bool _isSafeLocalEndpoint(Uri endpoint) {
    if (endpoint.scheme != 'http' && endpoint.scheme != 'https') {
      return false;
    }
    final host = endpoint.host.toLowerCase();
    if (host == 'localhost' ||
        host == '::1' ||
        host == '0:0:0:0:0:0:0:1' ||
        host.endsWith('.local')) {
      return true;
    }
    if (host.contains(':')) {
      final firstGroup = int.tryParse(host.split(':').first, radix: 16);
      // IPv6 unique-local addresses are eligible for strict-local routing.
      // The direct gateway still rejects metadata, rebinding, and unsafe peers.
      return firstGroup != null && firstGroup & 0xfe00 == 0xfc00;
    }
    final octets = host.split('.').map(int.tryParse).toList(growable: false);
    if (octets.length != 4 || octets.any((part) => part == null)) {
      return false;
    }
    final values = octets.cast<int>();
    if (values.any((part) => part < 0 || part > 255)) {
      return false;
    }
    return values[0] == 10 ||
        values[0] == 127 ||
        (values[0] == 192 && values[1] == 168) ||
        (values[0] == 172 && values[1] >= 16 && values[1] <= 31);
  }

  bool _looksLikeOllamaCloudModel(String model) {
    final normalized = model.trim().toLowerCase();
    return normalized.endsWith(':cloud') || normalized.endsWith('-cloud');
  }
}
