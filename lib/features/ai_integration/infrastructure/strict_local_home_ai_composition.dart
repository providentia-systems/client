import 'package:flutter/widgets.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/strict_local_provider_configuration.dart';
import 'package:providentia/features/ai_integration/application/strict_local_provider_settings_controller.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia/features/ai_integration/infrastructure/drift_strict_local_provider_configuration_store.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_ai_composition.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_provider_gateway.dart';
import 'package:providentia/features/ai_integration/presentation/strict_local_provider_settings_page.dart';
import 'package:providentia/features/inventory/application/stock_photo_count_controller.dart';

final class StrictLocalHomeAiComposition {
  StrictLocalHomeAiComposition._({
    required this.homeId,
    required this.store,
    required this.gateway,
    required this.settingsController,
  });

  factory StrictLocalHomeAiComposition.create({
    required AppDatabase database,
    required String homeId,
    required PreparedMediaByteReader mediaReader,
    required String Function() idGenerator,
    CredentialVault credentialVault = const DisabledCredentialVault(),
    StrictLocalCredentialReader credentialReader =
        const DisabledStrictLocalCredentialReader(),
    DateTime Function()? clock,
  }) {
    final store = DriftStrictLocalProviderConfigurationStore(
      database,
      clock: clock,
    );
    final gateway = StrictLocalAiComposition.createForCurrentPlatform(
      mediaReader: mediaReader,
      credentialReader: credentialReader,
    );
    return StrictLocalHomeAiComposition._(
      homeId: homeId,
      store: store,
      gateway: gateway,
      settingsController: StrictLocalProviderSettingsController(
        homeId: homeId,
        store: store,
        gateway: gateway,
        credentialVault: credentialVault,
        idGenerator: idGenerator,
        clock: clock,
      ),
    );
  }

  final String homeId;
  final StrictLocalProviderConfigurationStore store;
  final AiProviderGateway gateway;
  final StrictLocalProviderSettingsController settingsController;

  Widget settingsPage({Key? key}) =>
      StrictLocalProviderSettingsPage(key: key, controller: settingsController);

  Future<String?> activeStockProfileId() => store.readActiveProfileId(homeId);

  Future<StockPhotoAiRoute> loadActiveStockRoute() async {
    final profileId = await store.readActiveProfileId(homeId);
    if (profileId == null) {
      throw StateError('No active strict-local provider is selected.');
    }
    final configuration = await store.findById(
      homeId: homeId,
      profileId: profileId,
    );
    if (configuration == null || !configuration.enabled) {
      throw StateError('The active strict-local provider is unavailable.');
    }
    return StockPhotoAiRoute(
      profile: configuration.toProfile(),
      gateway: gateway,
      privacyMode: AiPrivacyMode.strictLocal,
    );
  }

  void dispose() => settingsController.dispose();
}
