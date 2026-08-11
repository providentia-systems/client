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
import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/core/synchronization/generated_sync_gateway.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/features/administration/application/catalog_merge_workflow.dart';
import 'package:providentia/features/administration/application/catalog_workbench_controller.dart';
import 'package:providentia/features/administration/application/platform_administration_controller.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';
import 'package:providentia/features/administration/infrastructure/api11_platform_administration_transport.dart';
import 'package:providentia/features/administration/infrastructure/generated_catalog_administration_repository.dart';
import 'package:providentia/features/administration/presentation/catalog_workbench_page.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia/features/ai_integration/infrastructure/generated_server_ai_repository.dart';
import 'package:providentia/features/ai_integration/infrastructure/media_acquisition_service.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';
import 'package:providentia/features/ai_integration/presentation/server_ai_workspace_controller.dart';
import 'package:providentia/features/ai_integration/presentation/server_ai_workspace_page.dart';
import 'package:providentia/features/catalog/application/catalog_product_contribution_controller.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/application/catalog_sharing_controller.dart';
import 'package:providentia/features/catalog/infrastructure/generated_catalog_contribution_repository.dart';
import 'package:providentia/features/catalog/presentation/catalog_product_contribution_page.dart';
import 'package:providentia/features/catalog/presentation/catalog_sharing_page.dart';
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';
import 'package:providentia/features/data_governance/infrastructure/generated_data_governance_repository.dart';
import 'package:providentia/features/data_governance/presentation/data_governance_controller.dart';
import 'package:providentia/features/data_governance/presentation/data_governance_page.dart';
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
import 'package:providentia/features/reporting/application/household_report_service.dart';
import 'package:providentia/features/reporting/application/reporting_controller.dart';
import 'package:providentia/features/reporting/infrastructure/generated_household_report_repository.dart';
import 'package:providentia/features/reporting/presentation/household_reports_page.dart';
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
  late final String _deviceId;
  late final ProvidentiaApiClient _identityApi;
  late final ProvidentiaApiClient _authorizedApi;
  late final IdentitySessionManager _identityManager;
  late final IdentityController _identityController;
  late final HomesController _homesController;
  late final PlatformAdministrationController _platformAdministrationController;
  late final ProductionSessionSecurityBoundary _sessionSecurityBoundary;
  late final Future<void> _initialization;
  GeneratedCatalogAdministrationRepository? _catalogAdministrationRepository;
  CatalogWorkbenchController? _catalogWorkbenchController;
  Set<CatalogCapability> _catalogCapabilities = const <CatalogCapability>{};
  StreamSubscription<IdentitySessionSnapshot>? _identitySubscription;
  SessionHttpClient? _authorizedTransport;
  final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> _workspaceNavigatorKey =
      GlobalKey<NavigatorState>();
  final ProductionProtectedRouteRegistry _protectedRouteRegistry =
      ProductionProtectedRouteRegistry();
  String? _securedHomeId;
  Set<String> _securedHomePermissions = const <String>{};
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
    _deviceId = await DeviceIdentityStore().getOrCreate();
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
        id: _deviceId,
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
      rootNavigatorKey: _rootNavigatorKey,
      workspaceNavigatorKey: _workspaceNavigatorKey,
      homesController: _homesController,
      platformAdministrationController: _platformAdministrationController,
      clearCatalogAdministration: _clearCatalogAdministration,
      clearProtectedRouteState: _protectedRouteRegistry.clearSensitiveState,
    );
    _securedHomeId = _homesController.snapshot.activeHome?.id;
    _securedHomePermissions = Set<String>.unmodifiable(
      _homesController.snapshot.effectivePermissions,
    );
    _homesController.addListener(_handleHomeSecurityState);
    _identitySubscription = _identityManager.states.listen(
      _handleIdentitySession,
    );
    _handleIdentitySession(_identityManager.snapshot);
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
          navigatorKey: _rootNavigatorKey,
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
                    catalogSharingPageBuilder: _catalogSharingPageBuilder(
                      _homesController.snapshot.activeHome,
                      _homesController.snapshot.effectivePermissions,
                    ),
                    catalogAdministrationPageBuilder:
                        _catalogAdministrationPageBuilder,
                    householdReportsPageBuilder: _householdReportsPageBuilder,
                    householdAiPageBuilder: _householdAiPageBuilder,
                    dataGovernancePageBuilder: _dataGovernancePageBuilder,
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
                      deviceId: _deviceId,
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
                      catalogSharingPageBuilder: _catalogSharingPageBuilder(
                        home,
                        permissions,
                      ),
                      canContributeCatalog: mayContributeCatalogProduct(
                        permissions,
                      ),
                      catalogAdministrationPageBuilder:
                          _catalogAdministrationPageBuilder,
                      householdReportsPageBuilder: _householdReportsPageBuilder,
                      householdAiPageBuilder: _householdAiPageBuilder,
                      dataGovernancePageBuilder: _dataGovernancePageBuilder,
                      protectedRouteRegistry: _protectedRouteRegistry,
                      onCatalogAuthorizationLost:
                          _handleCatalogSharingAuthorizationLost,
                      workspaceNavigatorKey: _workspaceNavigatorKey,
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
        _homesController.removeListener(_handleHomeSecurityState);
        _homesController.dispose();
        _platformAdministrationController.dispose();
        _catalogWorkbenchController?.dispose();
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

  void _handleIdentitySession(IdentitySessionSnapshot snapshot) {
    _sessionSecurityBoundary.handleIdentitySession(snapshot);
    final roles = snapshot.isAuthenticated
        ? snapshot.currentUser?.platformRoles ?? const <PlatformRole>{}
        : const <PlatformRole>{};
    final nextCapabilities =
        GeneratedCatalogAdministrationRepository.capabilitiesForPlatformRoles(
          roles,
        );
    if (setEquals(nextCapabilities, _catalogCapabilities)) return;
    _sessionSecurityBoundary.handleCatalogRoleChange(
      previousCapabilities: _catalogCapabilities,
      currentCapabilities: nextCapabilities,
    );
    _catalogWorkbenchController?.dispose();
    _catalogAdministrationRepository = null;
    _catalogWorkbenchController = null;
    _catalogCapabilities = Set<CatalogCapability>.unmodifiable(
      nextCapabilities,
    );
    if (nextCapabilities.contains(CatalogCapability.review)) {
      final repository = GeneratedCatalogAdministrationRepository(
        _authorizedApi,
        platformRoles: roles,
        onAuthorizationLost: _handleCatalogAuthorizationLost,
      );
      _catalogAdministrationRepository = repository;
      _catalogWorkbenchController = CatalogWorkbenchController(repository);
    }
    if (mounted) setState(() {});
  }

  void _clearCatalogAdministration() {
    _catalogWorkbenchController?.clearSensitiveState();
  }

  Future<void> _handleCatalogAuthorizationLost() async {
    _sessionSecurityBoundary.dismissProtectedRoutes();
    _clearCatalogAdministration();
    await _identityController.refreshCurrentUser();
  }

  Future<void> _handleCatalogSharingAuthorizationLost() async {
    _sessionSecurityBoundary.dismissProtectedRoutes();
    await Future.wait<void>(<Future<void>>[
      _identityController.refreshCurrentUser(),
      if (_homesController.snapshot.activeHome != null)
        _homesController.refreshGovernance(),
    ]);
  }

  void _handleHomeSecurityState() {
    final currentHomeId = _homesController.snapshot.activeHome?.id;
    final currentPermissions = Set<String>.unmodifiable(
      _homesController.snapshot.effectivePermissions,
    );
    _sessionSecurityBoundary.handleHomeAccessChange(
      previousHomeId: _securedHomeId,
      currentHomeId: currentHomeId,
      previousPermissions: _securedHomePermissions,
      currentPermissions: currentPermissions,
    );
    _securedHomeId = currentHomeId;
    _securedHomePermissions = currentPermissions;
  }

  WidgetBuilder get _householdReportsPageBuilder => (_) {
    final home = _homesController.snapshot.activeHome;
    final permissions = _homesController.snapshot.effectivePermissions;
    if (home == null ||
        !permissions.contains(HomePermissions.reportsRead) ||
        !_identityController.snapshot.isAuthenticated) {
      return const _ProtectedRouteUnavailable();
    }
    return ProductionHouseholdReportsRoute(
      repository: GeneratedHouseholdReportRepository(_authorizedApi),
      homeId: home.id,
      protectedRouteRegistry: _protectedRouteRegistry,
      onAuthorizationLost: _handleCatalogSharingAuthorizationLost,
    );
  };

  WidgetBuilder get _dataGovernancePageBuilder => (_) {
    if (!_identityController.snapshot.isAuthenticated) {
      return const _ProtectedRouteUnavailable();
    }
    final home = _homesController.snapshot.activeHome;
    final permissions = home == null
        ? const <String>{}
        : _homesController.snapshot.effectivePermissions;
    return ProductionDataGovernanceRoute(
      repository: GeneratedDataGovernanceRepository(_authorizedApi),
      capabilities: DataGovernanceCapabilities.fromEffectivePermissions(
        authenticated: true,
        effectiveHomePermissions: permissions,
      ),
      activeHomeId: home?.id,
      protectedRouteRegistry: _protectedRouteRegistry,
      onAuthorizationLost: _handleCatalogSharingAuthorizationLost,
    );
  };

  WidgetBuilder get _householdAiPageBuilder => (_) {
    final home = _homesController.snapshot.activeHome;
    final permissions = _homesController.snapshot.effectivePermissions;
    final capabilities = home == null
        ? null
        : AiHomeCapabilities.fromPermissions(
            homeId: home.id,
            permissions: permissions,
          );
    if (!_identityController.snapshot.isAuthenticated ||
        home == null ||
        capabilities == null ||
        !capabilities.mayRead) {
      return const _ProtectedRouteUnavailable();
    }
    return ProductionServerAiRoute(
      api: _authorizedApi,
      homeId: home.id,
      capabilities: capabilities,
      protectedRouteRegistry: _protectedRouteRegistry,
      onAuthorizationLost: _handleCatalogSharingAuthorizationLost,
    );
  };

  WidgetBuilder? _catalogSharingPageBuilder(
    HomeSummary? home,
    Set<String> permissions,
  ) {
    if (home == null || !mayAccessCatalogSharing(permissions)) return null;
    return (_) => _ProductionCatalogSharingRoute(
      repository: GeneratedCatalogContributionRepository(_authorizedApi),
      homeId: home.id,
      canManageConsent: permissions.contains(
        HomePermissions.catalogConsentManage,
      ),
      canContribute: permissions.contains(HomePermissions.catalogContribute),
      protectedRouteRegistry: _protectedRouteRegistry,
      onAuthorizationLost: _handleCatalogSharingAuthorizationLost,
    );
  }

  WidgetBuilder? get _catalogAdministrationPageBuilder {
    final repository = _catalogAdministrationRepository;
    final controller = _catalogWorkbenchController;
    if (repository == null || controller == null) return null;
    return (_) => CatalogWorkbenchPage(
      controller: controller,
      proposalDecisions: repository,
      contributionDecisions: repository,
      conflictDecisions: repository,
      iconRepository: repository,
      mergeWorkflow: CatalogMergeWorkflow(repository),
    );
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
    required this.rootNavigatorKey,
    required this.workspaceNavigatorKey,
    required this.homesController,
    required this.platformAdministrationController,
    this.clearCatalogAdministration,
    this.clearProtectedRouteState,
  });

  final GlobalKey<NavigatorState> rootNavigatorKey;
  final GlobalKey<NavigatorState> workspaceNavigatorKey;
  final HomesController homesController;
  final PlatformAdministrationController platformAdministrationController;
  final VoidCallback? clearCatalogAdministration;
  final VoidCallback? clearProtectedRouteState;

  void handleIdentitySession(IdentitySessionSnapshot snapshot) {
    if (snapshot.isAuthenticated) {
      return;
    }
    dismissProtectedRoutes();
    clearCatalogAdministration?.call();
    platformAdministrationController.clearSensitiveState();
    homesController.handleAuthenticationLost();
  }

  void handleCatalogRoleChange({
    required Set<CatalogCapability> previousCapabilities,
    required Set<CatalogCapability> currentCapabilities,
  }) {
    if (previousCapabilities.difference(currentCapabilities).isEmpty) return;
    dismissProtectedRoutes();
    clearCatalogAdministration?.call();
  }

  void handleHomeAccessChange({
    required String? previousHomeId,
    required String? currentHomeId,
    required Set<String> previousPermissions,
    required Set<String> currentPermissions,
  }) {
    final leftOrChangedWorkspace =
        previousHomeId != null && previousHomeId != currentHomeId;
    final lostPermission = previousPermissions
        .difference(currentPermissions)
        .isNotEmpty;
    if (leftOrChangedWorkspace || lostPermission) {
      dismissProtectedRoutes();
    }
  }

  void dismissProtectedRoutes() {
    // Inner routes must be dismissed first. Otherwise removing the outer
    // workspace can dispose sensitive controllers while a nested route still
    // owns listeners to them.
    workspaceNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    clearProtectedRouteState?.call();
  }
}

/// Clears route-owned sensitive projections as soon as route dismissal starts,
/// rather than retaining them for the duration of an outgoing route animation.
@visibleForTesting
final class ProductionProtectedRouteRegistry {
  final Set<VoidCallback> _clearers = <VoidCallback>{};

  void register(VoidCallback clearer) => _clearers.add(clearer);

  void unregister(VoidCallback clearer) => _clearers.remove(clearer);

  void clearSensitiveState() {
    for (final clearer in List<VoidCallback>.of(_clearers)) {
      clearer();
    }
  }
}

final class _ConnectedHomeWorkspace extends StatefulWidget {
  const _ConnectedHomeWorkspace({
    required this.home,
    required this.access,
    required this.revokedDataPurge,
    required this.syncRevocationGate,
    required this.database,
    required this.deviceId,
    required this.api,
    required this.identityController,
    required this.homesController,
    required this.platformAdministrationController,
    required this.catalogSharingPageBuilder,
    required this.canContributeCatalog,
    required this.catalogAdministrationPageBuilder,
    required this.householdReportsPageBuilder,
    required this.householdAiPageBuilder,
    required this.dataGovernancePageBuilder,
    required this.protectedRouteRegistry,
    required this.onCatalogAuthorizationLost,
    required this.workspaceNavigatorKey,
    required this.onChangeHome,
    required this.onSignOut,
    super.key,
  });

  final HomeSummary home;
  final HouseholdWorkspaceAccess access;
  final Future<bool>? revokedDataPurge;
  final HomeSyncRevocationGate syncRevocationGate;
  final AppDatabase database;
  final String deviceId;
  final ProvidentiaApiClient api;
  final IdentityController identityController;
  final HomesController homesController;
  final PlatformAdministrationController? platformAdministrationController;
  final WidgetBuilder? catalogSharingPageBuilder;
  final bool canContributeCatalog;
  final WidgetBuilder? catalogAdministrationPageBuilder;
  final WidgetBuilder householdReportsPageBuilder;
  final WidgetBuilder householdAiPageBuilder;
  final WidgetBuilder dataGovernancePageBuilder;
  final ProductionProtectedRouteRegistry protectedRouteRegistry;
  final Future<void> Function() onCatalogAuthorizationLost;
  final GlobalKey<NavigatorState> workspaceNavigatorKey;
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
    final household = createProductionHouseholdRepository(
      database: widget.database,
      deviceId: widget.deviceId,
      onMutationCommitted: _app.refresh,
    );
    _ready = _prepareLocalWorkspace(household);
    _features = HouseholdFeatures(
      inventory: InventoryController(
        repository: household,
        homeId: widget.home.id,
      ),
      purchasing: PurchasingController(
        repository: household,
        homeId: widget.home.id,
        mayWrite: widget.access.purchasesWrite,
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
          navigatorKey: widget.workspaceNavigatorKey,
          onChangeHome: widget.onChangeHome,
          onSignOut: widget.onSignOut,
          accountPageBuilder: (context) => AccountAccessPage(
            identityController: widget.identityController,
            homesController: widget.homesController,
            platformAdministrationController:
                widget.platformAdministrationController,
            catalogSharingPageBuilder: widget.catalogSharingPageBuilder,
            catalogContributionPageBuilder: _catalogContributionPageBuilder,
            catalogAdministrationPageBuilder:
                widget.catalogAdministrationPageBuilder,
            householdReportsPageBuilder: widget.householdReportsPageBuilder,
            householdAiPageBuilder: widget.householdAiPageBuilder,
            dataGovernancePageBuilder: widget.dataGovernancePageBuilder,
          ),
        );
      },
    );
  }

  WidgetBuilder? get _catalogContributionPageBuilder {
    if (!widget.canContributeCatalog) return null;
    return (_) {
      final repository = GeneratedCatalogContributionRepository(widget.api);
      return ProductionCatalogProductContributionRoute(
        consentRepository: repository,
        proposalRepository: repository,
        inventoryController: _features.inventory,
        homeId: widget.home.id,
        locale: widget.home.locale,
        protectedRouteRegistry: widget.protectedRouteRegistry,
        onAuthorizationLost: widget.onCatalogAuthorizationLost,
      );
    };
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
    await _app.start();
    if (_app.syncSummary.availability == SyncAvailability.authorizationDenied) {
      throw StateError('The selected home is no longer authorized.');
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

final class _ProductionCatalogSharingRoute extends StatefulWidget {
  const _ProductionCatalogSharingRoute({
    required this.repository,
    required this.homeId,
    required this.canManageConsent,
    required this.canContribute,
    required this.protectedRouteRegistry,
    required this.onAuthorizationLost,
  });

  final GeneratedCatalogContributionRepository repository;
  final String homeId;
  final bool canManageConsent;
  final bool canContribute;
  final ProductionProtectedRouteRegistry protectedRouteRegistry;
  final Future<void> Function() onAuthorizationLost;

  @override
  State<_ProductionCatalogSharingRoute> createState() =>
      _ProductionCatalogSharingRouteState();
}

final class _ProductionCatalogSharingRouteState
    extends State<_ProductionCatalogSharingRoute> {
  late final CatalogSharingController _controller;
  late final VoidCallback _clearSensitiveState;

  @override
  void initState() {
    super.initState();
    _controller = CatalogSharingController(
      repository: widget.repository,
      homeId: widget.homeId,
      canManageConsent: widget.canManageConsent,
      canContribute: widget.canContribute,
      onAuthorizationLost: widget.onAuthorizationLost,
    );
    _clearSensitiveState = _controller.clearSensitiveState;
    widget.protectedRouteRegistry.register(_clearSensitiveState);
  }

  @override
  Widget build(BuildContext context) =>
      CatalogSharingPage(controller: _controller);

  @override
  void dispose() {
    widget.protectedRouteRegistry.unregister(_clearSensitiveState);
    _clearSensitiveState();
    _controller.dispose();
    super.dispose();
  }
}

/// Route-owned bridge from the selected home's private inventory projection to
/// an explicit, allowlisted product-identity contribution.
@visibleForTesting
final class ProductionCatalogProductContributionRoute extends StatefulWidget {
  const ProductionCatalogProductContributionRoute({
    required this.consentRepository,
    required this.proposalRepository,
    required this.inventoryController,
    required this.homeId,
    required this.locale,
    required this.protectedRouteRegistry,
    required this.onAuthorizationLost,
    super.key,
  });

  final CatalogSharingConsentRepository consentRepository;
  final CatalogProposalRepository proposalRepository;
  final InventoryController inventoryController;
  final String homeId;
  final String locale;
  final ProductionProtectedRouteRegistry protectedRouteRegistry;
  final Future<void> Function() onAuthorizationLost;

  @override
  State<ProductionCatalogProductContributionRoute> createState() =>
      _ProductionCatalogProductContributionRouteState();
}

final class _ProductionCatalogProductContributionRouteState
    extends State<ProductionCatalogProductContributionRoute> {
  late final CatalogProductContributionController _controller;
  late final VoidCallback _clearSensitiveState;

  @override
  void initState() {
    super.initState();
    _controller = CatalogProductContributionController(
      consentRepository: widget.consentRepository,
      proposalService: CatalogProposalService(widget.proposalRepository),
      homeId: widget.homeId,
      locale: widget.locale,
      canContribute: true,
      onAuthorizationLost: widget.onAuthorizationLost,
    );
    _clearSensitiveState = _controller.clearSensitiveState;
    widget.protectedRouteRegistry.register(_clearSensitiveState);
  }

  @override
  Widget build(BuildContext context) => CatalogProductContributionPage(
    controller: _controller,
    inventoryController: widget.inventoryController,
  );

  @override
  void dispose() {
    widget.protectedRouteRegistry.unregister(_clearSensitiveState);
    _clearSensitiveState();
    _controller.dispose();
    super.dispose();
  }
}

/// Route-owned reporting composition. The controller can never outlive the
/// protected route or retain a completed response after that route is removed.
@visibleForTesting
final class ProductionHouseholdReportsRoute extends StatefulWidget {
  const ProductionHouseholdReportsRoute({
    required this.repository,
    required this.homeId,
    required this.protectedRouteRegistry,
    this.onAuthorizationLost,
    super.key,
  });

  final HouseholdReportRepository repository;
  final String homeId;
  final ProductionProtectedRouteRegistry protectedRouteRegistry;
  final Future<void> Function()? onAuthorizationLost;

  @override
  State<ProductionHouseholdReportsRoute> createState() =>
      _ProductionHouseholdReportsRouteState();
}

final class _ProductionHouseholdReportsRouteState
    extends State<ProductionHouseholdReportsRoute> {
  late final ReportingController _controller;
  late final VoidCallback _clearSensitiveState;
  bool _handlingAuthorizationLoss = false;

  @override
  void initState() {
    super.initState();
    _controller = ReportingController(
      service: HouseholdReportService(widget.repository),
      activeHomeId: widget.homeId,
    )..addListener(_handleControllerState);
    _clearSensitiveState = _controller.clearSensitiveState;
    widget.protectedRouteRegistry.register(_clearSensitiveState);
    unawaited(_controller.load());
  }

  void _handleControllerState() {
    if (_controller.status != ReportingStatus.forbidden ||
        _handlingAuthorizationLoss) {
      return;
    }
    _handlingAuthorizationLoss = true;
    final callback = widget.onAuthorizationLost;
    if (callback != null) unawaited(callback());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Household reports')),
    body: HouseholdReportsPage(controller: _controller),
  );

  @override
  void dispose() {
    widget.protectedRouteRegistry.unregister(_clearSensitiveState);
    _clearSensitiveState();
    _controller.removeListener(_handleControllerState);
    _controller.dispose();
    super.dispose();
  }
}

/// Route-owned account/home governance composition with immutable
/// permission-derived capabilities for this protected route generation.
@visibleForTesting
final class ProductionDataGovernanceRoute extends StatefulWidget {
  const ProductionDataGovernanceRoute({
    required this.repository,
    required this.capabilities,
    required this.protectedRouteRegistry,
    this.activeHomeId,
    this.onAuthorizationLost,
    super.key,
  });

  final DataGovernanceRepository repository;
  final DataGovernanceCapabilities capabilities;
  final ProductionProtectedRouteRegistry protectedRouteRegistry;
  final String? activeHomeId;
  final Future<void> Function()? onAuthorizationLost;

  @override
  State<ProductionDataGovernanceRoute> createState() =>
      _ProductionDataGovernanceRouteState();
}

final class _ProductionDataGovernanceRouteState
    extends State<ProductionDataGovernanceRoute> {
  late final DataGovernanceController _controller;
  late final VoidCallback _clearSensitiveState;
  bool _handlingAuthorizationLoss = false;

  @override
  void initState() {
    super.initState();
    _controller = DataGovernanceController(
      DataGovernanceService(
        repository: widget.repository,
        capabilities: widget.capabilities,
        activeHomeId: widget.activeHomeId,
      ),
    )..addListener(_handleControllerState);
    _clearSensitiveState = _controller.clearSensitiveState;
    widget.protectedRouteRegistry.register(_clearSensitiveState);
  }

  void _handleControllerState() {
    if (_handlingAuthorizationLoss ||
        !const <DataGovernanceNotice>{
          DataGovernanceNotice.authenticationRequired,
          DataGovernanceNotice.forbidden,
        }.contains(_controller.notice)) {
      return;
    }
    _handlingAuthorizationLoss = true;
    final callback = widget.onAuthorizationLost;
    if (callback != null) unawaited(callback());
  }

  @override
  Widget build(BuildContext context) =>
      DataGovernancePage(controller: _controller);

  @override
  void dispose() {
    widget.protectedRouteRegistry.unregister(_clearSensitiveState);
    _clearSensitiveState();
    _controller.removeListener(_handleControllerState);
    _controller.dispose();
    super.dispose();
  }
}

/// Route-owned production composition for server-proxy household AI. The
/// controller has no purchasing or inventory mutation dependency; a completed
/// candidate review is only a handoff to those ordinary command surfaces.
@visibleForTesting
final class ProductionServerAiRoute extends StatefulWidget {
  const ProductionServerAiRoute({
    required this.api,
    required this.homeId,
    required this.capabilities,
    required this.protectedRouteRegistry,
    required this.onAuthorizationLost,
    super.key,
  });

  final ProvidentiaApiClient api;
  final String homeId;
  final AiHomeCapabilities capabilities;
  final ProductionProtectedRouteRegistry protectedRouteRegistry;
  final Future<void> Function() onAuthorizationLost;

  @override
  State<ProductionServerAiRoute> createState() =>
      _ProductionServerAiRouteState();
}

final class _ProductionServerAiRouteState
    extends State<ProductionServerAiRoute> {
  late final RegisteredMediaSourceReader _sources;
  late final MemoryEphemeralPreparedMediaStore _prepared;
  late final MediaAcquisitionService _acquisition;
  late final ServerAiWorkspaceController _controller;
  late final VoidCallback _clearSensitiveStateCallback;
  bool _handlingAuthorizationLoss = false;
  bool _sensitiveStateCleared = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _sources = RegisteredMediaSourceReader();
    _prepared = MemoryEphemeralPreparedMediaStore();
    _acquisition = MediaAcquisitionService(registry: _sources);
    final capabilities = widget.capabilities.homeId == widget.homeId
        ? widget.capabilities
        : AiHomeCapabilities.fromPermissions(
            homeId: widget.homeId,
            permissions: const <String>{},
            active: false,
          );
    _controller = ServerAiWorkspaceController(
      repository: GeneratedServerAiRepository(widget.api),
      media: ProductionRegisteredSourceClearingMediaPreparer(
        delegate: SanitizingImageMediaPreparer(
          sources: _sources,
          prepared: _prepared,
        ),
        sources: _sources,
      ),
      gateway: Api17AiGateway(client: widget.api, mediaReader: _prepared),
      identifiers: ProductionAiIdentifierFactory(),
      capabilities: capabilities,
    )..addListener(_handleControllerState);
    _clearSensitiveStateCallback = _clearSensitiveState;
    widget.protectedRouteRegistry.register(_clearSensitiveStateCallback);
  }

  @override
  Widget build(BuildContext context) => ServerAiWorkspacePage(
    controller: _controller,
    pickSingleImage: _pickSingleImage,
    onReviewHandoff: _handleReviewHandoff,
  );

  Future<AiMediaAsset?> _pickSingleImage(AiExtractionKind kind) async {
    if (_picking || _sensitiveStateCleared) return null;
    _picking = true;
    _clearRegisteredSources();
    try {
      final selected = await _acquisition.choosePhotos(
        homeId: widget.homeId,
        purpose: kind,
        limit: 1,
      );
      if (!mounted || _sensitiveStateCleared || selected.length != 1) {
        _clearRegisteredSources();
        return null;
      }
      return selected.single;
    } on Object {
      _clearRegisteredSources();
      if (mounted && !_sensitiveStateCleared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The selected image could not be opened safely.'),
          ),
        );
      }
      return null;
    } finally {
      _picking = false;
    }
  }

  void _handleReviewHandoff(AiReviewHandoff handoff) {
    if (!mounted ||
        handoff.homeId != widget.homeId ||
        !handoff.requiresOrdinaryDomainCommand) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Accepted candidates still require an ordinary purchasing or inventory command and final confirmation. No household data changed.',
        ),
      ),
    );
  }

  void _handleControllerState() {
    if (_controller.status == ServerAiWorkspaceStatus.failed ||
        _controller.status == ServerAiWorkspaceStatus.accessDenied) {
      _clearRegisteredSources();
    }
    if (_handlingAuthorizationLoss) return;
    final lostAuthorization =
        _controller.status == ServerAiWorkspaceStatus.accessDenied ||
        (_controller.status == ServerAiWorkspaceStatus.failed &&
            const <String>{
              'Sign in again before using household AI.',
              'Your current household role does not allow this AI action.',
            }.contains(_controller.safeMessage));
    if (!lostAuthorization) return;
    _handlingAuthorizationLoss = true;
    unawaited(widget.onAuthorizationLost());
  }

  void _clearSensitiveState() {
    if (_sensitiveStateCleared) return;
    _sensitiveStateCleared = true;
    _handlingAuthorizationLoss = true;
    _clearRegisteredSources();
    unawaited(
      _controller.updateCapabilities(
        AiHomeCapabilities.fromPermissions(
          homeId: widget.homeId,
          permissions: const <String>{},
          active: false,
        ),
      ),
    );
  }

  void _clearRegisteredSources() {
    for (final sourceId in List<String>.of(_sources.registeredIds)) {
      _sources.remove(sourceId);
    }
  }

  @override
  void dispose() {
    widget.protectedRouteRegistry.unregister(_clearSensitiveStateCallback);
    _controller.removeListener(_handleControllerState);
    _clearSensitiveState();
    _controller.dispose();
    super.dispose();
  }
}

/// Removes picker-owned originals immediately after sanitization succeeds or
/// fails. The prepared store is independently discarded by the controller.
@visibleForTesting
final class ProductionRegisteredSourceClearingMediaPreparer
    implements AiMediaPreparationPort {
  const ProductionRegisteredSourceClearingMediaPreparer({
    required this.delegate,
    required this.sources,
  });

  final AiMediaPreparationPort delegate;
  final RegisteredMediaSourceReader sources;

  @override
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) async {
    try {
      return await delegate.prepare(
        homeId: homeId,
        purpose: purpose,
        assets: assets,
      );
    } finally {
      for (final asset in assets) {
        sources.remove(asset.id);
      }
    }
  }

  @override
  Future<void> discard(PreparedMediaBatch batch) => delegate.discard(batch);
}

/// UUIDv4 identities prevent extraction retries from sharing a durable intent
/// identifier while keeping identifier generation independent of API data.
@visibleForTesting
final class ProductionAiIdentifierFactory implements AiIdentifierFactory {
  ProductionAiIdentifierFactory({UuidV4Generator? generator})
    : _generator = generator ?? UuidV4Generator();

  final UuidV4Generator _generator;

  @override
  String nextId() => _generator();
}

final class _ProtectedRouteUnavailable extends StatelessWidget {
  const _ProtectedRouteUnavailable();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Your access changed. Return to Account & access.'),
      ),
    ),
  );
}

/// Reviewable production boundary for durable household writes.
///
/// Keeping device identity and the post-commit foreground-sync trigger
/// mandatory here prevents the connected workspace from silently falling back
/// to local-only semantics.
@visibleForTesting
DriftHouseholdRepository createProductionHouseholdRepository({
  required AppDatabase database,
  required String deviceId,
  required Future<void> Function() onMutationCommitted,
  DateTime Function()? clock,
  String Function()? idGenerator,
}) {
  return DriftHouseholdRepository(
    database,
    deviceId: deviceId,
    clock: clock,
    idGenerator: idGenerator,
    onMutationCommitted: onMutationCommitted,
  );
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
