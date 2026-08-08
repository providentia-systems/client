import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/app/household_features.dart';
import 'package:providentia/app/providentia_app.dart';
import 'package:providentia/core/config/runtime_configuration.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/design_system/providentia_theme.dart';
import 'package:providentia/core/networking/api_client_factory.dart';
import 'package:providentia/core/networking/credentialed_http_client.dart';
import 'package:providentia/core/networking/generated_api_connectivity_probe.dart';
import 'package:providentia/core/networking/session_http_client.dart';
import 'package:providentia/core/security/device_identity_store.dart';
import 'package:providentia/core/security/platform_session_credential_store.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/infrastructure/api17_home_transport.dart';
import 'package:providentia/features/homes/infrastructure/drift_active_home_store.dart';
import 'package:providentia/features/homes/presentation/home_selection_page.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/infrastructure/api17_identity_transport.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';
import 'package:providentia/features/identity/presentation/passwordless_sign_in_page.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Production composition root: identity -> authorized homes -> active home ->
/// local-first household workspace. No home ID or bearer token is required at
/// build time, and every server call is bound to the authenticated session.
final class ProductionBootstrapApp extends StatefulWidget {
  const ProductionBootstrapApp({required this.configuration, super.key});

  final RuntimeConfiguration configuration;

  @override
  State<ProductionBootstrapApp> createState() => _ProductionBootstrapAppState();
}

final class _ProductionBootstrapAppState extends State<ProductionBootstrapApp> {
  late final AppDatabase _database;
  late final ProvidentiaApiClient _identityApi;
  late final ProvidentiaApiClient _authorizedApi;
  late final IdentitySessionManager _identityManager;
  late final IdentityController _identityController;
  late final HomesController _homesController;
  late final Future<void> _initialization;
  SessionHttpClient? _authorizedTransport;

  @override
  void initState() {
    super.initState();
    _database = AppDatabase.defaults();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    final deviceId = await DeviceIdentityStore().getOrCreate();
    final sessionTransport = kIsWeb
        ? ClientSessionTransport.webCookie
        : ClientSessionTransport.nativeBearer;
    _identityApi = const ApiClientFactory().create(
      configuration: widget.configuration,
    );
    final identityTransport = Api17IdentityTransport(
      client: _identityApi,
      sessionTransport: sessionTransport,
    );
    _identityManager = IdentitySessionManager(
      transport: identityTransport,
      credentialStore: PlatformSessionCredentialStore(),
      device: DeviceDescriptor(
        id: deviceId,
        name: _deviceName,
        platform: _platformName,
      ),
    );
    _identityController = IdentityController(_identityManager);

    _authorizedTransport = SessionHttpClient(
      inner: createCredentialedHttpClient(),
      sessions: _identityManager,
    );
    _authorizedApi = const ApiClientFactory().create(
      configuration: widget.configuration,
      httpClient: _authorizedTransport,
    );
    final homes = HomeSessionManager(
      transport: Api17HomeTransport(_authorizedApi),
      activeHomeStore: DriftActiveHomeStore(_database),
      onActiveHomeChanged: _identityManager.updateActiveHome,
    );
    _homesController = HomesController(homes);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _StartupFailureApp();
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupProgressApp();
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Providentia',
          theme: ProvidentiaTheme.light(),
          highContrastTheme: ProvidentiaTheme.light(highContrast: true),
          home: PasswordlessSignInPage(
            controller: _identityController,
            passwordlessSignInAvailable: false,
            authenticatedChild: HomeSelectionPage(
              controller: _homesController,
              activeHomeBuilder: (context, home) => _ConnectedHomeWorkspace(
                key: ValueKey<String>(home.id),
                home: home,
                database: _database,
                api: _authorizedApi,
                onChangeHome: _homesController.returnToChooser,
                onSignOut: _signOut,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(
      _initialization.then((_) async {
        _homesController.dispose();
        _identityController.dispose();
        await _identityManager.dispose();
        _authorizedApi.close();
        _authorizedTransport?.close();
        _identityApi.close();
        await _database.close();
      }),
    );
    super.dispose();
  }

  String get _platformName => kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          TargetPlatform.windows => 'windows',
          TargetPlatform.macOS => 'macos',
          TargetPlatform.linux => 'linux',
          TargetPlatform.fuchsia => 'fuchsia',
        };

  String get _deviceName => kIsWeb ? 'Providentia web' : 'Providentia app';

  Future<void> _signOut() async {
    final logout = _identityController.logout();
    await _homesController.returnToChooser();
    await logout;
  }
}

final class _ConnectedHomeWorkspace extends StatefulWidget {
  const _ConnectedHomeWorkspace({
    required this.home,
    required this.database,
    required this.api,
    required this.onChangeHome,
    required this.onSignOut,
    super.key,
  });

  final HomeSummary home;
  final AppDatabase database;
  final ProvidentiaApiClient api;
  final Future<void> Function() onChangeHome;
  final Future<void> Function() onSignOut;

  @override
  State<_ConnectedHomeWorkspace> createState() =>
      _ConnectedHomeWorkspaceState();
}

final class _ConnectedHomeWorkspaceState
    extends State<_ConnectedHomeWorkspace> {
  late final AppController _app;
  late final HouseholdFeatures _features;
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    final localSync = DriftLocalSyncRepository(widget.database);
    final synchronization = SyncCoordinator(
      local: localSync,
      remote: GeneratedSyncGateway(widget.api),
      connectivity: GeneratedApiConnectivityProbe(widget.api),
    );
    _app = AppController(
      synchronization: synchronization,
      activeHomeId: widget.home.id,
    );
    final household = DriftHouseholdRepository(widget.database);
    _ready = household.ensureHomeInitialized(homeId: widget.home.id);
    _features = HouseholdFeatures(
      inventory: InventoryController(
        repository: household,
        homeId: widget.home.id,
      ),
      purchasing: PurchasingController(
        repository: household,
        homeId: widget.home.id,
      ),
      shopping: ShoppingController(
        repository: household,
        homeId: widget.home.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _WorkspaceFailure();
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ProvidentiaApp(
          controller: _app,
          features: _features,
          onChangeHome: widget.onChangeHome,
          onSignOut: widget.onSignOut,
        );
      },
    );
  }
}

final class _StartupProgressApp extends StatelessWidget {
  const _StartupProgressApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Preparing secure application storage',
        ),
      ),
    ),
  );
}

final class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Secure application storage could not be initialized. Close and reopen Providentia to try again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}

final class _WorkspaceFailure extends StatelessWidget {
  const _WorkspaceFailure();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('The selected home could not be opened safely.'),
      ),
    ),
  );
}
