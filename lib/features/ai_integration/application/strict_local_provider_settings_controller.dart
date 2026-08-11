import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/strict_local_provider_configuration.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';

enum StrictLocalSettingsStatus { idle, loading, saving, ready, failed }

final class StrictLocalProviderDraft {
  const StrictLocalProviderDraft({
    this.profileId,
    required this.displayName,
    required this.kind,
    required this.endpoint,
    required this.model,
    required this.multiImage,
    required this.requiresAuthentication,
    required this.explicitlyAttested,
    this.replacementSecret,
  });

  final String? profileId;
  final String displayName;
  final AiProviderKind kind;
  final String endpoint;
  final String model;
  final bool multiImage;
  final bool requiresAuthentication;
  final bool explicitlyAttested;
  final String? replacementSecret;
}

final class StrictLocalProviderSettingsState {
  StrictLocalProviderSettingsState({
    required this.status,
    required List<StrictLocalProviderConfiguration> configurations,
    this.activeProfileId,
    this.safeMessage,
    Map<String, AiGatewayReadiness> readiness =
        const <String, AiGatewayReadiness>{},
  }) : configurations = UnmodifiableListView(configurations),
       readiness = UnmodifiableMapView(readiness);

  const StrictLocalProviderSettingsState.idle()
    : status = StrictLocalSettingsStatus.idle,
      configurations = const <StrictLocalProviderConfiguration>[],
      activeProfileId = null,
      safeMessage = null,
      readiness = const <String, AiGatewayReadiness>{};

  final StrictLocalSettingsStatus status;
  final List<StrictLocalProviderConfiguration> configurations;
  final String? activeProfileId;
  final String? safeMessage;
  final Map<String, AiGatewayReadiness> readiness;
}

final class StrictLocalProviderSettingsController extends ChangeNotifier {
  factory StrictLocalProviderSettingsController({
    required String homeId,
    required StrictLocalProviderConfigurationStore store,
    required AiProviderGateway gateway,
    required CredentialVault credentialVault,
    required String Function() idGenerator,
    DateTime Function()? clock,
  }) => StrictLocalProviderSettingsController._(
    homeId,
    store,
    gateway,
    credentialVault,
    idGenerator,
    clock ?? DateTime.now,
  );

  StrictLocalProviderSettingsController._(
    this.homeId,
    this._store,
    this._gateway,
    this._credentialVault,
    this._idGenerator,
    this._clock,
  ) : _service = StrictLocalProviderConfigurationService(
        store: _store,
        credentialVault: _credentialVault,
      ) {
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
  }

  final String homeId;
  final StrictLocalProviderConfigurationStore _store;
  final AiProviderGateway _gateway;
  final CredentialVault _credentialVault;
  final StrictLocalProviderConfigurationService _service;
  final String Function() _idGenerator;
  final DateTime Function() _clock;
  StrictLocalProviderSettingsState _state =
      const StrictLocalProviderSettingsState.idle();
  bool _disposed = false;

  StrictLocalProviderSettingsState get state => _state;
  bool get supportsAuthenticatedProfiles =>
      _credentialVault.supportsNativeSecrets;

  Future<void> load() async {
    if (_disposed) return;
    _setState(
      StrictLocalProviderSettingsState(
        status: StrictLocalSettingsStatus.loading,
        configurations: _state.configurations,
        activeProfileId: _state.activeProfileId,
      ),
    );
    try {
      final configurations = await _store.listForHome(homeId);
      final active = await _store.readActiveProfileId(homeId);
      _setState(
        StrictLocalProviderSettingsState(
          status: StrictLocalSettingsStatus.ready,
          configurations: configurations,
          activeProfileId: active,
          readiness: _state.readiness,
        ),
      );
    } on Object {
      _fail('Local AI settings could not be loaded safely.');
    }
  }

  Future<void> save(StrictLocalProviderDraft draft) async {
    if (_disposed) return;
    try {
      if (!draft.explicitlyAttested) {
        throw const AiPolicyViolation(
          code: 'strict_local_attestation_required',
          safeMessage:
              'Confirm that this endpoint is controlled by your local network.',
        );
      }
      if (draft.kind != AiProviderKind.ollama &&
          draft.kind != AiProviderKind.openAiCompatible) {
        throw const AiPolicyViolation(
          code: 'unsupported_local_provider',
          safeMessage: 'Choose Ollama or OpenAI-compatible LAN.',
        );
      }
      final endpoint = Uri.tryParse(draft.endpoint.trim());
      if (endpoint == null ||
          draft.kind == AiProviderKind.openAiCompatible &&
              endpoint.scheme != 'https') {
        throw const AiPolicyViolation(
          code: 'https_required',
          safeMessage:
              'OpenAI-compatible LAN profiles require an HTTPS endpoint.',
        );
      }
      if (draft.requiresAuthentication &&
          !_credentialVault.supportsNativeSecrets) {
        throw const AiPolicyViolation(
          code: 'native_credential_store_required',
          safeMessage:
              'Authenticated local profiles are unavailable on this platform.',
        );
      }
      final existing = draft.profileId == null
          ? null
          : await _store.findById(homeId: homeId, profileId: draft.profileId!);
      final profileId = existing?.profileId ?? _idGenerator();
      final configuration = StrictLocalProviderConfiguration(
        profileId: profileId,
        homeId: homeId,
        displayName: draft.displayName.trim(),
        kind: draft.kind,
        endpoint: endpoint,
        model: draft.model.trim(),
        capabilities: <AiCapability>{
          AiCapability.vision,
          AiCapability.strictJsonSchema,
          if (draft.multiImage) AiCapability.multiImage,
        },
        credentialConfigured: draft.requiresAuthentication,
        attestedAt: _clock().toUtc(),
        revision: (existing?.revision ?? 0) + 1,
      );
      _setState(
        StrictLocalProviderSettingsState(
          status: StrictLocalSettingsStatus.saving,
          configurations: _state.configurations,
          activeProfileId: _state.activeProfileId,
          readiness: _state.readiness,
        ),
      );
      await _service.save(
        configuration: configuration,
        replacementSecret: draft.replacementSecret,
      );
      if (_state.activeProfileId == null) {
        await _store.setActiveProfileId(homeId: homeId, profileId: profileId);
      }
      await load();
    } on AiPolicyViolation catch (error) {
      _fail(error.safeMessage);
    } on Object {
      _fail('The local AI profile could not be saved safely.');
    }
  }

  Future<void> testReadiness(String profileId) async {
    if (_disposed) return;
    try {
      final configuration = await _store.findById(
        homeId: homeId,
        profileId: profileId,
      );
      if (configuration == null) throw StateError('Missing profile.');
      final result = await _gateway.readiness(configuration.toProfile());
      _setState(
        StrictLocalProviderSettingsState(
          status: StrictLocalSettingsStatus.ready,
          configurations: _state.configurations,
          activeProfileId: _state.activeProfileId,
          readiness: <String, AiGatewayReadiness>{
            ..._state.readiness,
            profileId: result,
          },
          safeMessage: result.safeMessage,
        ),
      );
    } on Object {
      _fail('The local AI provider could not be verified safely.');
    }
  }

  Future<void> select(String profileId) async {
    if (_disposed) return;
    try {
      await _store.setActiveProfileId(homeId: homeId, profileId: profileId);
      await load();
    } on Object {
      _fail('The local AI profile could not be selected.');
    }
  }

  Future<void> selectServerProxyRoute() async {
    if (_disposed) return;
    try {
      await _store.setActiveProfileId(homeId: homeId, profileId: null);
      await load();
    } on Object {
      _fail('The server AI route could not be selected safely.');
    }
  }

  Future<void> delete(String profileId) async {
    if (_disposed) return;
    try {
      await _service.delete(homeId: homeId, profileId: profileId);
      await load();
    } on Object {
      _fail('The local AI profile could not be deleted safely.');
    }
  }

  void _fail(String message) => _setState(
    StrictLocalProviderSettingsState(
      status: StrictLocalSettingsStatus.failed,
      configurations: _state.configurations,
      activeProfileId: _state.activeProfileId,
      readiness: _state.readiness,
      safeMessage: message,
    ),
  );

  void _setState(StrictLocalProviderSettingsState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
