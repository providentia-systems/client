import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/strict_local_provider_configuration.dart';
import 'package:providentia/features/ai_integration/application/strict_local_provider_settings_controller.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/drift_strict_local_provider_configuration_store.dart';
import 'package:providentia/features/ai_integration/presentation/strict_local_provider_settings_page.dart';

void main() {
  late AppDatabase database;
  late DriftStrictLocalProviderConfigurationStore store;
  late _Gateway gateway;
  late StrictLocalProviderSettingsController controller;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftStrictLocalProviderConfigurationStore(database);
    gateway = _Gateway();
    controller = StrictLocalProviderSettingsController(
      homeId: 'home-1',
      store: store,
      gateway: gateway,
      credentialVault: const DisabledCredentialVault(),
      idGenerator: () => 'profile-1',
      clock: () => DateTime.utc(2026, 8, 11),
    );
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'saves, selects, and readiness-tests an attested Ollama profile',
    () async {
      await controller.save(_ollamaDraft());

      expect(controller.state.status, StrictLocalSettingsStatus.ready);
      expect(controller.state.configurations, hasLength(1));
      expect(controller.state.activeProfileId, 'profile-1');
      final stored = controller.state.configurations.single;
      expect(stored.toJson(), isNot(contains('secret')));

      await controller.testReadiness('profile-1');
      expect(controller.state.readiness['profile-1']?.isReady, isTrue);
      expect(
        gateway.readinessProfiles.single.endpoint?.origin,
        'http://127.0.0.1:11434',
      );
    },
  );

  test(
    'rejects HTTP generic LAN and unattested/authenticated profiles',
    () async {
      await controller.save(
        StrictLocalProviderDraft(
          displayName: 'Compatible',
          kind: AiProviderKind.openAiCompatible,
          endpoint: 'http://192.168.1.10:8080',
          model: 'vision',
          multiImage: true,
          requiresAuthentication: false,
          explicitlyAttested: true,
        ),
      );
      expect(controller.state.safeMessage, contains('HTTPS'));

      await controller.save(
        StrictLocalProviderDraft(
          displayName: 'Ollama',
          kind: AiProviderKind.ollama,
          endpoint: 'http://127.0.0.1:11434',
          model: 'llava',
          multiImage: true,
          requiresAuthentication: true,
          explicitlyAttested: true,
          replacementSecret: 'must-not-store',
        ),
      );
      expect(controller.state.safeMessage, contains('unavailable'));
      expect(await store.listForHome('home-1'), isEmpty);

      await controller.save(
        StrictLocalProviderDraft(
          displayName: 'Ollama',
          kind: AiProviderKind.ollama,
          endpoint: 'http://127.0.0.1:11434',
          model: 'llava',
          multiImage: true,
          requiresAuthentication: false,
          explicitlyAttested: false,
        ),
      );
      expect(controller.state.safeMessage, contains('Confirm'));
    },
  );

  test('server proxy route requires an explicit selection', () async {
    await controller.save(_ollamaDraft());
    expect(await store.readActiveProfileId('home-1'), 'profile-1');

    await controller.selectServerProxyRoute();

    expect(controller.state.activeProfileId, isNull);
    expect(await store.readActiveProfileId('home-1'), isNull);
  });

  testWidgets('page shows privacy disclosure and disables browser auth', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StrictLocalProviderSettingsPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('strict-local-settings-disclosure')), findsOne);
    expect(find.textContaining('does not receive them'), findsOne);
    final auth = tester.widget<SwitchListTile>(
      find.widgetWithText(
        SwitchListTile,
        'Endpoint requires bearer authentication',
      ),
    );
    expect(auth.onChanged, isNull);
  });

  testWidgets('page exposes an explicit switch back to the server route', (
    tester,
  ) async {
    await controller.save(_ollamaDraft());
    await tester.pumpWidget(
      MaterialApp(
        home: StrictLocalProviderSettingsPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.state.activeProfileId, 'profile-1');

    await tester.scrollUntilVisible(
      find.byKey(const Key('strict-local-server-route')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('strict-local-server-route')));
    await tester.pumpAndSettle();

    expect(controller.state.activeProfileId, isNull);
    expect(await store.readActiveProfileId('home-1'), isNull);
    expect(find.textContaining('Cloud processing disclosure'), findsOneWidget);
  });
}

StrictLocalProviderDraft _ollamaDraft() => const StrictLocalProviderDraft(
  displayName: 'Kitchen Ollama',
  kind: AiProviderKind.ollama,
  endpoint: 'http://127.0.0.1:11434',
  model: 'llava:latest',
  multiImage: true,
  requiresAuthentication: false,
  explicitlyAttested: true,
);

final class _Gateway implements AiProviderGateway {
  final List<AiProviderProfile> readinessProfiles = <AiProviderProfile>[];

  @override
  AiGatewayRoute get route => AiGatewayRoute.directStrictLocal;

  @override
  Future<AiGatewayReadiness> readiness(AiProviderProfile profile) async {
    readinessProfiles.add(profile);
    return const AiGatewayReadiness.ready();
  }

  @override
  Future<AiExtractionResult<ReceiptProposal>> extractReceipt(
    AiExtractionRequest request,
  ) => throw UnimplementedError();

  @override
  Future<AiExtractionResult<StockPhotoProposal>> extractStockPhoto(
    AiExtractionRequest request,
  ) => throw UnimplementedError();
}
