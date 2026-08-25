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
import 'package:providentia/core/synchronization/privacy_safe_sync_metrics.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/administration/application/catalog_merge_workflow.dart';
import 'package:providentia/features/administration/application/catalog_workbench_controller.dart';
import 'package:providentia/features/administration/application/platform_administration_controller.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';
import 'package:providentia/features/administration/infrastructure/api11_platform_administration_transport.dart';
import 'package:providentia/features/administration/infrastructure/generated_catalog_administration_repository.dart';
import 'package:providentia/features/administration/presentation/catalog_workbench_page.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/receipt_ai_handoff_controller.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia/features/ai_integration/infrastructure/captured_file_cleanup.dart';
import 'package:providentia/features/ai_integration/infrastructure/generated_server_ai_repository.dart';
import 'package:providentia/features/ai_integration/infrastructure/media_acquisition_service.dart';
import 'package:providentia/features/ai_integration/infrastructure/receipt_page_media_editor.dart';
import 'package:providentia/features/ai_integration/infrastructure/receipt_pdf_rasterizer.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_home_ai_composition.dart';
import 'package:providentia/features/ai_integration/presentation/camera_capture_page.dart';
import 'package:providentia/features/ai_integration/presentation/home_ai_hub_page.dart';
import 'package:providentia/features/ai_integration/presentation/receipt_ai_handoff_page.dart';
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
import 'package:providentia/features/inventory/application/stock_camera_capture_session.dart';
import 'package:providentia/features/inventory/application/stock_photo_count_controller.dart';
import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';
import 'package:providentia/features/inventory/infrastructure/item_master_refreshing_synchronization.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/reporting/application/household_report_service.dart';
import 'package:providentia/features/reporting/application/reporting_controller.dart';
import 'package:providentia/features/reporting/infrastructure/generated_household_report_repository.dart';
import 'package:providentia/features/reporting/presentation/household_reports_page.dart';
import 'package:providentia/features/shopping/application/online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/application/shopping_interaction_capabilities.dart';
import 'package:providentia/features/shopping/infrastructure/drift_shopping_suggestion_cache.dart';
import 'package:providentia/features/shopping/infrastructure/generated_online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';
import 'package:providentia/features/sync_conflicts/application/sync_conflict_repository.dart';
import 'package:providentia/features/sync_conflicts/infrastructure/drift_sync_conflict_repository.dart';
import 'package:providentia/features/sync_conflicts/presentation/sync_conflict_controller.dart';
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
  late final ProductionHomeRevocationBoundary _homeRevocationBoundary;
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
    _homeRevocationBoundary = ProductionHomeRevocationBoundary(
      purge: (homeId) {
        _scheduleRevokedHomePurge(homeId);
        return _revokedHomePurges[homeId]!;
      },
    );
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
                      homeRevocationBoundary: _homeRevocationBoundary,
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
    required this.homeRevocationBoundary,
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
  final ProductionHomeRevocationBoundary homeRevocationBoundary;
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

final class _ConnectedHomeWorkspaceState extends State<_ConnectedHomeWorkspace>
    with WidgetsBindingObserver {
  late final AppController _app;
  late final DriftHouseholdRepository _household;
  late final HouseholdFeatures _features;
  late final SyncConflictController _syncConflicts;
  late final PrivacySafeSyncMetrics _syncMetrics;
  late final ProductionResumeSyncGate _resumeSyncGate;
  late final Future<void> _ready;
  StrictLocalHomeAiComposition? _strictLocalAi;
  SyncMetricsSnapshot? _latestSyncMetrics;
  bool _revocationRouted = false;

  @override
  void initState() {
    super.initState();
    final localSync = DriftLocalSyncRepository(widget.database);
    final household = createProductionHouseholdRepository(
      database: widget.database,
      deviceId: widget.deviceId,
      onMutationCommitted: () => _app.refresh(),
    );
    _household = household;
    _syncMetrics = PrivacySafeSyncMetrics(
      sink: CallbackSyncMetricsSnapshotSink(
        (snapshot) => _latestSyncMetrics = snapshot,
      ),
    );
    AppSynchronization synchronization = SyncCoordinator(
      local: localSync,
      remote: GeneratedSyncGateway(widget.api),
      connectivity: GeneratedApiConnectivityProbe(widget.api),
      metrics: _syncMetrics,
    );
    if (widget.access.inventoryRead) {
      synchronization = ItemMasterRefreshingSynchronization(
        delegate: synchronization,
        source: GeneratedHomeItemMasterSource(widget.api),
        replaceCache: household.replaceCatalogItemMaster,
        homeId: widget.home.id,
      );
    }
    synchronization = RevocationGuardedSynchronization(
      delegate: synchronization,
      gate: widget.syncRevocationGate,
      homeId: widget.home.id,
    );
    _app = AppController(
      synchronization: synchronization,
      activeHomeId: widget.home.id,
    );
    _resumeSyncGate = ProductionResumeSyncGate(refresh: _app.refresh);
    WidgetsBinding.instance.addObserver(this);
    _syncConflicts = SyncConflictController(
      repository: DriftSyncConflictRepository(
        conflictStore: localSync,
        homeId: widget.home.id,
        accessResolver: (_) => SyncConflictAccess(
          mayReview: true,
          mayResolve:
              widget.access.inventoryWrite ||
              widget.access.purchasesWrite ||
              widget.access.shoppingWrite,
        ),
        resolutionAuthorization: _mayResolveConflict,
      ),
    );
    _app.addListener(_handleSynchronizationState);
    _ready = _prepareLocalWorkspace(household);
    final inventory = InventoryController(
      repository: household,
      homeId: widget.home.id,
    );
    final permissions = widget.homesController.snapshot.effectivePermissions;
    final aiCapabilities = AiHomeCapabilities.fromPermissions(
      homeId: widget.home.id,
      permissions: permissions,
    );
    final preparedStore = MemoryEphemeralPreparedMediaStore();
    if (aiCapabilities.hasAnyAccess) {
      _strictLocalAi = StrictLocalHomeAiComposition.create(
        database: widget.database,
        homeId: widget.home.id,
        mediaReader: preparedStore,
        idGenerator: UuidV4Generator().call,
      );
    }
    StockPhotoCountController? stockPhotoCount;
    StockPhotoAcquisitionActions? stockPhotoAcquisition;
    if (widget.access.inventoryWrite &&
        aiCapabilities.mayRead &&
        aiCapabilities.mayUse) {
      final sources = RegisteredMediaSourceReader();
      final mediaPreparation = ProductionRegisteredSourceClearingMediaPreparer(
        delegate: SanitizingImageMediaPreparer(
          sources: sources,
          prepared: preparedStore,
        ),
        sources: sources,
      );
      final acquisition = MediaAcquisitionService(registry: sources);
      final aiRepository = GeneratedServerAiRepository(widget.api);
      final serverGateway = Api17AiGateway(
        client: widget.api,
        mediaReader: preparedStore,
      );
      Future<StockPhotoAiRoute> loadServerRoute() async {
        final workspace = await aiRepository.loadWorkspace(
          homeId: widget.home.id,
        );
        if (workspace.homeId != widget.home.id ||
            workspace.settings.mode != AiServerMode.serverProxy) {
          throw const AiServerException(AiServerFailureKind.validation);
        }
        for (final profileId in workspace.policy.extractionProfileIds) {
          final profile = workspace.profile(profileId);
          if (profile != null && profile.enabled) {
            return StockPhotoAiRoute(
              profile: profile,
              gateway: serverGateway,
              privacyMode: AiPrivacyMode.serverProxyCloud,
            );
          }
        }
        throw const AiServerException(AiServerFailureKind.validation);
      }

      Future<StockPhotoAiRoute> loadPreferredRoute() async {
        final strictLocalAi = _strictLocalAi;
        final strictLocalProfileSelected =
            strictLocalAi != null &&
            await strictLocalAi.activeStockProfileId() != null;
        return selectProductionStockAiRoute(
          strictLocalProfileSelected: strictLocalProfileSelected,
          loadStrictLocalRoute: strictLocalAi?.loadActiveStockRoute,
          loadServerRoute: loadServerRoute,
        );
      }

      Future<List<AiMediaAsset>> takeStockPhoto() async {
        Future<AiMediaAsset?> captureOne() async {
          if (!mounted) return null;
          final captured = await showCameraCapture(context);
          if (captured == null) return null;
          if (!mounted) {
            await discardCapturedFile(captured.path);
            return null;
          }
          return acquisition.registerCapturedPhoto(
            captured,
            homeId: widget.home.id,
            purpose: AiExtractionKind.stockPhoto,
          );
        }

        Future<StockCameraCaptureDecision> chooseNext(
          List<AiMediaAsset> captured,
        ) async {
          if (!mounted) return StockCameraCaptureDecision.discard;
          return await showDialog<StockCameraCaptureDecision>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: Text(
                    'Review ${captured.length} stock photo${captured.length == 1 ? '' : 's'}',
                  ),
                  content: const Text(
                    'Continue to sanitization and consent, or add another view of the storeroom. A maximum of eight images is accepted.',
                  ),
                  actions: <Widget>[
                    TextButton(
                      key: const Key('stock-camera-discard'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(StockCameraCaptureDecision.discard),
                      child: const Text('Discard'),
                    ),
                    OutlinedButton(
                      key: const Key('stock-camera-continue'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(StockCameraCaptureDecision.continueToReview),
                      child: Text('Continue with ${captured.length}'),
                    ),
                    FilledButton(
                      key: const Key('stock-camera-another'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(StockCameraCaptureDecision.takeAnother),
                      child: const Text('Take another'),
                    ),
                  ],
                ),
              ) ??
              StockCameraCaptureDecision.discard;
        }

        return collectStockCameraAssets(
          homeId: widget.home.id,
          capture: captureOne,
          chooseNext: chooseNext,
          discard: (assets) async {
            for (final asset in assets) {
              sources.remove(asset.id);
            }
          },
        );
      }

      Future<List<AiMediaAsset>> chooseStockGallery() =>
          acquisition.choosePhotos(
            homeId: widget.home.id,
            purpose: AiExtractionKind.stockPhoto,
            limit: 8,
          );

      Future<List<AiMediaAsset>> uploadStockFiles() => acquisition.chooseFiles(
        homeId: widget.home.id,
        purpose: AiExtractionKind.stockPhoto,
        imagesOnly: true,
        limit: 8,
      );

      stockPhotoCount = StockPhotoCountController(
        homeId: widget.home.id,
        inventory: inventory,
        mediaPreparation: mediaPreparation,
        mediaReader: preparedStore,
        pickAssets: chooseStockGallery,
        loadRoute: loadPreferredRoute,
        idGenerator: UuidV4Generator().call,
        onAuthorizationDenied: _handleHomeAuthorizationLost,
      );
      stockPhotoAcquisition = StockPhotoAcquisitionActions(
        takePhoto: takeStockPhoto,
        chooseGallery: chooseStockGallery,
        uploadFiles: uploadStockFiles,
      );
    }
    _features = HouseholdFeatures(
      inventory: inventory,
      purchasing: PurchasingController(
        repository: household,
        productCreationRepository: household,
        homeId: widget.home.id,
        mayWrite: widget.access.purchasesWrite,
      ),
      shopping: ShoppingController(
        repository: household,
        homeId: widget.home.id,
        suggestionRepository: CachedOnlineShoppingSuggestionRepository(
          remote: GeneratedOnlineShoppingSuggestionRepository(widget.api),
          cache: DriftShoppingSuggestionCache(widget.database),
        ),
        capabilities: ShoppingInteractionCapabilities.onlineEvidenceSuggestions,
        onAuthorizationDenied: _handleHomeAuthorizationLost,
      ),
      stockPhotoCount: stockPhotoCount,
      stockPhotoAcquisition: stockPhotoAcquisition,
    );
  }

  @visibleForTesting
  SyncMetricsSnapshot get syncMetricsSnapshot =>
      _latestSyncMetrics ?? _syncMetrics.snapshot;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeSyncGate.resume();
    }
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
          syncConflictController: _syncConflicts,
          onCountReconciliation: (_) {
            _app.selectSection(AppSection.stock);
          },
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
            householdAiPageBuilder: _connectedHouseholdAiPageBuilder,
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

  bool _mayResolveConflict(SyncConflict conflict) {
    final entityType = conflict.entityType;
    if (entityType.startsWith('inventory-')) {
      return widget.access.inventoryWrite;
    }
    if (entityType.startsWith('purchasing-')) {
      return widget.access.purchasesWrite;
    }
    if (entityType.startsWith('shopping-')) {
      return widget.access.shoppingWrite;
    }
    return false;
  }

  WidgetBuilder get _connectedHouseholdAiPageBuilder => (_) {
    final permissions = widget.homesController.snapshot.effectivePermissions;
    final capabilities = AiHomeCapabilities.fromPermissions(
      homeId: widget.home.id,
      permissions: permissions,
    );
    if (!widget.identityController.snapshot.isAuthenticated ||
        !capabilities.mayRead) {
      return const _ProtectedRouteUnavailable();
    }
    final strictLocalAi = _strictLocalAi;
    return HomeAiHubPage(
      mayManageLocalProfiles: capabilities.mayManage && strictLocalAi != null,
      strictLocalSettingsPageBuilder: (_) =>
          strictLocalAi?.settingsPage() ?? const _ProtectedRouteUnavailable(),
      serverProxyPageBuilder: (_) => ProductionServerAiRoute(
        api: widget.api,
        homeId: widget.home.id,
        capabilities: capabilities,
        protectedRouteRegistry: widget.protectedRouteRegistry,
        onAuthorizationLost: _handleHomeAuthorizationLost,
        purchaseRepository: _household,
        mayWritePurchases:
            widget.access.purchasesRead && widget.access.purchasesWrite,
        onReceiptDraftReady: (_) {
          widget.workspaceNavigatorKey.currentState?.popUntil(
            (route) => route.isFirst,
          );
          _app.selectSection(AppSection.purchases);
        },
      ),
    );
  };

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
    if (!_revocationRouted && mounted) {
      _resumeSyncGate.markReady();
    }
  }

  void _handleSynchronizationState() {
    if (_revocationRouted ||
        _app.syncSummary.availability != SyncAvailability.authorizationDenied) {
      return;
    }
    unawaited(_handleHomeAuthorizationLost());
  }

  Future<void> _handleHomeAuthorizationLost() async {
    if (_revocationRouted) return;
    _revocationRouted = true;
    final stockPhotoCount = _features.stockPhotoCount;
    if (stockPhotoCount != null &&
        stockPhotoCount.state.status != StockPhotoCountStatus.accessDenied) {
      await stockPhotoCount.authorizationLost();
    }
    await widget.homeRevocationBoundary.revokePurgeAndRoute(
      homeId: widget.home.id,
      resumeSyncGate: _resumeSyncGate,
      routeAway: () =>
          widget.homesController.handleMembershipRevoked(widget.home.id),
    );
  }

  @override
  void dispose() {
    // The nested ProvidentiaApp owns the feature bundle, but blocking this
    // controller here closes the home-switch race before any async extraction
    // can hand a reviewed candidate to the outgoing home's inventory.
    WidgetsBinding.instance.removeObserver(this);
    _resumeSyncGate.dispose();
    _features.stockPhotoCount?.dispose();
    _strictLocalAi?.dispose();
    _app.removeListener(_handleSynchronizationState);
    super.dispose();
  }
}

/// Small explicit serialization gate for foreground resume refreshes. It owns
/// no home identifiers or household data and drops duplicate lifecycle events
/// while one refresh is running.
@visibleForTesting
final class ProductionResumeSyncGate {
  factory ProductionResumeSyncGate({
    required Future<void> Function() refresh,
  }) => ProductionResumeSyncGate._(refresh);

  ProductionResumeSyncGate._(this._refresh);

  final Future<void> Function() _refresh;
  bool _ready = false;
  bool _revoked = false;
  bool _disposed = false;
  bool _running = false;
  Future<void>? _inFlight;

  bool get isRunning => _running;

  void markReady() {
    if (_disposed || _revoked) return;
    _ready = true;
  }

  void markRevoked() {
    _revoked = true;
    _ready = false;
  }

  void resume() {
    if (!_ready || _revoked || _disposed || _running) return;
    _running = true;
    _inFlight = _run();
    unawaited(_inFlight);
  }

  Future<void> settle() => _inFlight ?? Future<void>.value();

  Future<void> _run() async {
    try {
      await _refresh();
    } catch (_) {
      // AppController and SyncCoordinator expose safe state; lifecycle
      // delivery must never leak transport errors as unhandled exceptions.
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _ready = false;
  }
}

/// Production ordering boundary for an inaccessible home: block foreground
/// resume work first, wait for synchronization to quiesce and private data to
/// be purged, then close the workspace. Purge failure never preserves access;
/// routing still happens and the false result keeps re-entry fail closed.
@visibleForTesting
final class ProductionHomeRevocationBoundary {
  const ProductionHomeRevocationBoundary({required this.purge});

  final Future<bool> Function(String homeId) purge;

  Future<bool> revokePurgeAndRoute({
    required String homeId,
    required ProductionResumeSyncGate resumeSyncGate,
    required Future<void> Function() routeAway,
  }) async {
    resumeSyncGate.markRevoked();
    var purged = false;
    try {
      purged = await purge(homeId);
    } finally {
      await routeAway();
    }
    return purged;
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
    this.purchaseRepository,
    this.mayWritePurchases = false,
    this.onReceiptDraftReady,
    super.key,
  });

  final ProvidentiaApiClient api;
  final String homeId;
  final AiHomeCapabilities capabilities;
  final ProductionProtectedRouteRegistry protectedRouteRegistry;
  final Future<void> Function() onAuthorizationLost;
  final PurchaseCaptureRepository? purchaseRepository;
  final bool mayWritePurchases;
  final ValueChanged<String>? onReceiptDraftReady;

  @override
  State<ProductionServerAiRoute> createState() =>
      _ProductionServerAiRouteState();
}

final class _ProductionServerAiRouteState
    extends State<ProductionServerAiRoute> {
  late final RegisteredMediaSourceReader _sources;
  late final MemoryEphemeralPreparedMediaStore _prepared;
  late final MediaAcquisitionService _acquisition;
  late final ReceiptPageMediaEditor _receiptEditor;
  late final ReceiptPdfRasterizer _receiptPdfRasterizer;
  late final ServerAiWorkspaceController _controller;
  late final VoidCallback _clearSensitiveStateCallback;
  bool _handlingAuthorizationLoss = false;
  bool _sensitiveStateCleared = false;
  bool _picking = false;
  ReceiptAiHandoffController? _receiptHandoff;

  @override
  void initState() {
    super.initState();
    _sources = RegisteredMediaSourceReader();
    _prepared = MemoryEphemeralPreparedMediaStore();
    _acquisition = MediaAcquisitionService(registry: _sources);
    _receiptEditor = ReceiptPageMediaEditor(sources: _sources);
    _receiptPdfRasterizer = ReceiptPdfRasterizer(sources: _sources);
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
    captureSingleImage: _captureSingleImage,
    pickFileImage: _pickFileImage,
    pickMultipleImages: _pickMultipleImages,
    pickReceiptPdf: _pickReceiptPdf,
    readLocalImage: _receiptEditor.readPreview,
    transformReceiptPage: _receiptEditor.transform,
    discardLocalImages: _receiptEditor.discard,
    readPreparedImage: _prepared.read,
    onReviewHandoff: _handleReviewHandoff,
  );

  Future<AiMediaAsset?> _captureSingleImage(AiExtractionKind kind) async {
    if (_picking || _sensitiveStateCleared) return null;
    _picking = true;
    _clearRegisteredSources();
    try {
      final captured = await showCameraCapture(context);
      if (captured == null) return null;
      if (!mounted || _sensitiveStateCleared) {
        await discardCapturedFile(captured.path);
        return null;
      }
      return await _acquisition.registerCapturedPhoto(
        captured,
        homeId: widget.homeId,
        purpose: kind,
      );
    } on Object {
      _clearRegisteredSources();
      if (mounted && !_sensitiveStateCleared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The captured image could not be opened safely.'),
          ),
        );
      }
      return null;
    } finally {
      _picking = false;
    }
  }

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

  Future<AiMediaAsset?> _pickFileImage(AiExtractionKind kind) async {
    if (_picking || _sensitiveStateCleared) return null;
    _picking = true;
    _clearRegisteredSources();
    try {
      final selected = await _acquisition.chooseFiles(
        homeId: widget.homeId,
        purpose: kind,
        allowMultiple: false,
        imagesOnly: true,
        limit: 1,
      );
      if (!mounted || _sensitiveStateCleared || selected.length != 1) {
        _clearRegisteredSources();
        return null;
      }
      return selected.single;
    } on MediaAcquisitionException catch (error) {
      _clearRegisteredSources();
      if (mounted && !_sensitiveStateCleared) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.safeMessage)));
      }
      return null;
    } catch (_) {
      _clearRegisteredSources();
      if (mounted && !_sensitiveStateCleared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The selected image file could not be opened safely.',
            ),
          ),
        );
      }
      return null;
    } finally {
      _picking = false;
    }
  }

  Future<List<AiMediaAsset>> _pickMultipleImages(AiExtractionKind kind) async {
    if (_picking ||
        _sensitiveStateCleared ||
        kind != AiExtractionKind.receipt) {
      return const <AiMediaAsset>[];
    }
    _picking = true;
    _clearRegisteredSources();
    try {
      final selected = await _acquisition.choosePhotos(
        homeId: widget.homeId,
        purpose: AiExtractionKind.receipt,
        limit: 8,
      );
      if (!mounted || _sensitiveStateCleared) {
        _clearRegisteredSources();
        return const <AiMediaAsset>[];
      }
      return selected;
    } on Object {
      _clearRegisteredSources();
      if (mounted && !_sensitiveStateCleared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The selected receipt pages could not be opened safely.',
            ),
          ),
        );
      }
      return const <AiMediaAsset>[];
    } finally {
      _picking = false;
    }
  }

  Future<List<AiMediaAsset>> _pickReceiptPdf() async {
    if (_picking || _sensitiveStateCleared) {
      return const <AiMediaAsset>[];
    }
    _picking = true;
    _clearRegisteredSources();
    try {
      final selected = await _receiptPdfRasterizer.choose(
        homeId: widget.homeId,
      );
      if (!mounted || _sensitiveStateCleared) {
        _clearRegisteredSources();
        return const <AiMediaAsset>[];
      }
      return selected;
    } on MediaAcquisitionException catch (error) {
      _clearRegisteredSources();
      if (mounted && !_sensitiveStateCleared) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.safeMessage)));
      }
      return const <AiMediaAsset>[];
    } catch (_) {
      _clearRegisteredSources();
      if (mounted && !_sensitiveStateCleared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The receipt PDF could not be opened safely.'),
          ),
        );
      }
      return const <AiMediaAsset>[];
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
    final purchaseRepository = widget.purchaseRepository;
    if (handoff.kind == AiExtractionKind.receipt &&
        purchaseRepository != null &&
        widget.onReceiptDraftReady != null) {
      if (_receiptHandoff != null) return;
      final controller = ReceiptAiHandoffController(
        handoff: handoff,
        repository: purchaseRepository,
        activeHomeId: widget.homeId,
        mayWritePurchases: widget.mayWritePurchases,
      );
      _receiptHandoff = controller;
      unawaited(
        Navigator.of(context)
            .push<void>(
              MaterialPageRoute<void>(
                builder: (_) => ReceiptAiHandoffPage(
                  controller: controller,
                  onOpenPurchasingReview: widget.onReceiptDraftReady!,
                ),
              ),
            )
            .whenComplete(() {
              controller.dispose();
              if (identical(_receiptHandoff, controller)) {
                _receiptHandoff = null;
              }
            }),
      );
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
    _receiptHandoff?.updateAccess(activeHomeId: '', mayWritePurchases: false);
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
    _receiptHandoff?.dispose();
    _receiptHandoff = null;
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

/// Chooses the explicitly selected AI route. An active strict-local selection
/// fails closed when it cannot be loaded or verified; only the absence of a
/// local selection permits the server-proxy route.
@visibleForTesting
Future<StockPhotoAiRoute> selectProductionStockAiRoute({
  required bool strictLocalProfileSelected,
  StockPhotoAiRouteLoader? loadStrictLocalRoute,
  required StockPhotoAiRouteLoader loadServerRoute,
}) async {
  if (!strictLocalProfileSelected) return loadServerRoute();
  final localLoader = loadStrictLocalRoute;
  if (localLoader == null) {
    throw const AiPolicyViolation(
      code: 'strict_local_provider_unavailable',
      safeMessage:
          'The selected local AI provider is unavailable. Switch to the '
          'server route explicitly before using cloud AI.',
    );
  }
  final route = await localLoader();
  route.validate();
  final readiness = await route.gateway.readiness(route.profile);
  if (!readiness.isReady) {
    throw AiPolicyViolation(
      code: 'strict_local_provider_unavailable',
      safeMessage:
          readiness.safeMessage ??
          'The selected local AI provider is unavailable. Switch to the '
              'server route explicitly before using cloud AI.',
    );
  }
  return route;
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
