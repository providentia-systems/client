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
import 'package:providentia/core/security/platform_pending_login_link_store.dart';
import 'package:providentia/core/security/platform_session_coordination.dart';
import 'package:providentia/core/security/platform_session_credential_store.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/features/administration/application/platform_administration_controller.dart';
import 'package:providentia/features/administration/infrastructure/api11_platform_administration_transport.dart';
import 'package:providentia/features/homes/application/home_session_manager.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/infrastructure/api11_home_transport.dart';
import 'package:providentia/features/homes/infrastructure/drift_active_home_store.dart';
import 'package:providentia/features/homes/infrastructure/home_data_revocation.dart';
import 'package:providentia/features/homes/presentation/home_selection_page.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';
import 'package:providentia/features/identity/application/identity_session_manager.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/infrastructure/api11_identity_transport.dart';
import 'package:providentia/features/identity/infrastructure/secure_login_link_request_factory.dart';
import 'package:providentia/features/identity/presentation/account_access_page.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';
import 'package:providentia/features/identity/presentation/login_link_sign_in_page.dart';
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
  late final PlatformAdministrationController _platformAdministrationController;
  late final ProductionSessionSecurityBoundary _sessionSecurityBoundary;
  late final Future<void> _initialization;
  StreamSubscription<IdentitySessionSnapshot>? _identitySubscription;
  SessionHttpClient? _authorizedTransport;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final Map<String, Future<bool>> _revokedHomePurges = <String, Future<bool>>{};
  final HomeSyncRevocationGate _homeSyncRevocationGate =
      HomeSyncRevocationGate();

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
    final identityTransport = Api11IdentityTransport(
      _identityApi,
      sessionTransport: sessionTransport,
    );
    _identityManager = IdentitySessionManager(
      transport: identityTransport,
      credentialStore: PlatformSessionCredentialStore(),
      pendingLoginLinkStore: PlatformPendingLoginLinkStore(),
      loginLinkRequestFactory: SecureLoginLinkRequestFactory(),
      sessionCoordination: PlatformSessionCoordination(),
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
      transport: Api11HomeTransport(_authorizedApi),
      activeHomeStore: DriftActiveHomeStore(_database),
      onActiveHomeChanged: _identityManager.updateActiveHome,
      onHomeAccessRevoked: _scheduleRevokedHomePurge,
      coordinateActiveHomeMutation: ({required homeId, required mutation}) =>
          _identityManager.coordinateActiveHomeMutation<HomeSummary>(
            homeId: homeId,
            mutation: mutation,
          ),
      coordinateActiveHomeClearMutation: ({required mutation}) =>
          _identityManager.coordinateActiveHomeMutation<void>(
            homeId: null,
            mutation: mutation,
          ),
    );
    _homesController = HomesController(homes);
    _platformAdministrationController = PlatformAdministrationController(
      Api11PlatformAdministrationTransport(_authorizedApi),
      onAuthorizationLost: _handlePlatformAuthorizationLost,
    );
    _sessionSecurityBoundary = ProductionSessionSecurityBoundary(
      navigatorKey: _navigatorKey,
      homesController: _homesController,
      platformAdministrationController: _platformAdministrationController,
    );
    _identitySubscription = _identityManager.states.listen(
      _sessionSecurityBoundary.handleIdentitySession,
    );
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
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Providentia',
          theme: ProvidentiaTheme.light(),
          highContrastTheme: ProvidentiaTheme.light(highContrast: true),
          home: LoginLinkSignInPage(
            controller: _identityController,
            developmentPasswordAvailable:
                widget.configuration.enableDevelopmentPasswordLogin,
            authenticatedBuilder: (context, identitySnapshot) =>
                HomeSelectionPage(
                  controller: _homesController,
                  sessionActiveHomeId:
                      identitySnapshot.session?.activeHomeId ??
                      identitySnapshot.currentUser?.activeHomeId,
                  accountPageBuilder: (context) => AccountAccessPage(
                    identityController: _identityController,
                    homesController: _homesController,
                    platformAdministrationController:
                        identitySnapshot.currentUser?.isPlatformAdministrator ??
                            false
                        ? _platformAdministrationController
                        : null,
                  ),
                  onSignOut: _signOut,
                  activeHomeBuilder: (context, home) {
                    final permissions =
                        _homesController.snapshot.effectivePermissions;
                    final permissionKey = permissions.toList(growable: false)
                      ..sort();
                    return _ConnectedHomeWorkspace(
                      key: ValueKey<String>(
                        '${home.id}:${permissionKey.join(',')}',
                      ),
                      home: home,
                      access: HouseholdWorkspaceAccess.fromPermissions(
                        permissions,
                      ),
                      revokedDataPurge: _revokedHomePurges[home.id],
                      syncRevocationGate: _homeSyncRevocationGate,
                      database: _database,
                      api: _authorizedApi,
                      identityController: _identityController,
                      homesController: _homesController,
                      platformAdministrationController:
                          identitySnapshot
                                  .currentUser
                                  ?.isPlatformAdministrator ??
                              false
                          ? _platformAdministrationController
                          : null,
                      onChangeHome: _homesController.returnToChooser,
                      onSignOut: _signOut,
                    );
                  },
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
        await _identitySubscription?.cancel();
        _homesController.dispose();
        _platformAdministrationController.dispose();
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

  Future<void> _handlePlatformAuthorizationLost() async {
    _sessionSecurityBoundary.dismissProtectedRoutes();
    await _identityController.refreshCurrentUser();
  }

  void _scheduleRevokedHomePurge(String homeId) {
    final quiesced = _homeSyncRevocationGate.revokeAndWait(homeId);
    _revokedHomePurges[homeId] = quiesced
        .then((_) => RevokedHomeDataPurger(_database).purge(homeId))
        .then((_) => true, onError: (Object _, StackTrace _) => false);
  }
}

/// Central fail-closed boundary for routes and controller snapshots that are
/// meaningful only while an authenticated session exists.
@visibleForTesting
final class ProductionSessionSecurityBoundary {
  const ProductionSessionSecurityBoundary({
    required this.navigatorKey,
    required this.homesController,
    required this.platformAdministrationController,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final HomesController homesController;
  final PlatformAdministrationController platformAdministrationController;

  void handleIdentitySession(IdentitySessionSnapshot snapshot) {
    if (snapshot.isAuthenticated) {
      return;
    }
    homesController.handleAuthenticationLost();
    platformAdministrationController.clearSensitiveState();
    dismissProtectedRoutes();
  }

  void dismissProtectedRoutes() {
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }
}

final class _ConnectedHomeWorkspace extends StatefulWidget {
  const _ConnectedHomeWorkspace({
    required this.home,
    required this.access,
    required this.revokedDataPurge,
    required this.syncRevocationGate,
    required this.database,
    required this.api,
    required this.identityController,
    required this.homesController,
    required this.platformAdministrationController,
    required this.onChangeHome,
    required this.onSignOut,
    super.key,
  });

  final HomeSummary home;
  final HouseholdWorkspaceAccess access;
  final Future<bool>? revokedDataPurge;
  final HomeSyncRevocationGate syncRevocationGate;
  final AppDatabase database;
  final ProvidentiaApiClient api;
  final IdentityController identityController;
  final HomesController homesController;
  final PlatformAdministrationController? platformAdministrationController;
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
  bool _revocationRouted = false;

  @override
  void initState() {
    super.initState();
    final localSync = DriftLocalSyncRepository(widget.database);
    final synchronization = RevocationGuardedSynchronization(
      delegate: SyncCoordinator(
        local: localSync,
        remote: GeneratedSyncGateway(widget.api),
        connectivity: GeneratedApiConnectivityProbe(widget.api),
      ),
      gate: widget.syncRevocationGate,
      homeId: widget.home.id,
    );
    _app = AppController(
      synchronization: synchronization,
      activeHomeId: widget.home.id,
    );
    _app.addListener(_handleSynchronizationState);
    final household = DriftHouseholdRepository(widget.database);
    _ready = _prepareLocalWorkspace(household);
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
          access: widget.access,
          onChangeHome: widget.onChangeHome,
          onSignOut: widget.onSignOut,
          accountPageBuilder: (context) => AccountAccessPage(
            identityController: widget.identityController,
            homesController: widget.homesController,
            platformAdministrationController:
                widget.platformAdministrationController,
          ),
        );
      },
    );
  }

  Future<void> _prepareLocalWorkspace(
    DriftHouseholdRepository household,
  ) async {
    final purge = widget.revokedDataPurge;
    if (purge != null && !await purge) {
      throw StateError('Revoked-home cache could not be purged safely.');
    }
    if (purge != null) {
      widget.syncRevocationGate.reauthorize(widget.home.id);
    }
    if (widget.access.shoppingWrite) {
      await household.ensureHomeInitialized(homeId: widget.home.id);
    }
  }

  void _handleSynchronizationState() {
    if (_revocationRouted ||
        _app.syncSummary.availability != SyncAvailability.authorizationDenied) {
      return;
    }
    _revocationRouted = true;
    unawaited(widget.homesController.handleMembershipRevoked(widget.home.id));
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
