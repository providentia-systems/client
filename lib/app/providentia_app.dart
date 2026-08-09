import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/app/household_features.dart';
import 'package:providentia/core/design_system/providentia_theme.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/inventory/presentation/inventory_workspace.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_workspace.dart';
import 'package:providentia/features/shopping/presentation/shopping_controller.dart';
import 'package:providentia/features/shopping/presentation/shopping_workspace.dart';

/// Presentation capabilities derived from the active home policy returned by
/// the backend. Unknown or absent permissions remain denied.
final class HouseholdWorkspaceAccess {
  const HouseholdWorkspaceAccess({
    required this.inventoryRead,
    required this.inventoryWrite,
    required this.purchasesRead,
    required this.purchasesWrite,
    required this.shoppingRead,
    required this.shoppingWrite,
  });

  factory HouseholdWorkspaceAccess.fromPermissions(Set<String> permissions) {
    return HouseholdWorkspaceAccess(
      inventoryRead: permissions.contains(HomePermissions.inventoryRead),
      inventoryWrite: permissions.contains(HomePermissions.inventoryWrite),
      purchasesRead: permissions.contains(HomePermissions.purchasesRead),
      purchasesWrite: permissions.contains(HomePermissions.purchasesWrite),
      shoppingRead: permissions.contains(HomePermissions.shoppingRead),
      shoppingWrite: permissions.contains(HomePermissions.shoppingWrite),
    );
  }

  static const HouseholdWorkspaceAccess denied = HouseholdWorkspaceAccess(
    inventoryRead: false,
    inventoryWrite: false,
    purchasesRead: false,
    purchasesWrite: false,
    shoppingRead: false,
    shoppingWrite: false,
  );

  final bool inventoryRead;
  final bool inventoryWrite;
  final bool purchasesRead;
  final bool purchasesWrite;
  final bool shoppingRead;
  final bool shoppingWrite;

  bool mayRead(AppSection section) => switch (section) {
    AppSection.home => true,
    AppSection.stock => inventoryRead,
    AppSection.purchases => purchasesRead,
    AppSection.lists => shoppingRead,
  };
}

class ProvidentiaApp extends StatefulWidget {
  const ProvidentiaApp({
    required this.controller,
    this.features,
    this.access = HouseholdWorkspaceAccess.denied,
    this.onChangeHome,
    this.onSignOut,
    this.accountPageBuilder,
    this.onDispose,
    super.key,
  });

  final AppController controller;
  final HouseholdFeatures? features;
  final HouseholdWorkspaceAccess access;
  final Future<void> Function()? onChangeHome;
  final Future<void> Function()? onSignOut;
  final WidgetBuilder? accountPageBuilder;
  final VoidCallback? onDispose;

  @override
  State<ProvidentiaApp> createState() => _ProvidentiaAppState();
}

class _ProvidentiaAppState extends State<ProvidentiaApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
    _startReadableFeatures();
  }

  @override
  void didUpdateWidget(covariant ProvidentiaApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startReadableFeatures();
  }

  void _startReadableFeatures() {
    final features = widget.features;
    if (features == null) {
      return;
    }
    if (widget.access.inventoryRead) {
      features.inventory.start();
    }
    if (widget.access.purchasesRead) {
      features.purchasing.start();
    }
    if (widget.access.shoppingRead) {
      features.shopping.start();
    }
  }

  @override
  void dispose() {
    widget.features?.dispose();
    widget.controller.dispose();
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Providentia',
      theme: ProvidentiaTheme.light(),
      highContrastTheme: ProvidentiaTheme.light(highContrast: true),
      home: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          return _AdaptiveShell(
            controller: widget.controller,
            features: widget.features,
            access: widget.access,
            onChangeHome: widget.onChangeHome,
            onSignOut: widget.onSignOut,
            accountPageBuilder: widget.accountPageBuilder,
          );
        },
      ),
    );
  }
}

class _AdaptiveShell extends StatelessWidget {
  const _AdaptiveShell({
    required this.controller,
    required this.features,
    required this.access,
    required this.onChangeHome,
    required this.onSignOut,
    required this.accountPageBuilder,
  });

  final AppController controller;
  final HouseholdFeatures? features;
  final HouseholdWorkspaceAccess access;
  final Future<void> Function()? onChangeHome;
  final Future<void> Function()? onSignOut;
  final WidgetBuilder? accountPageBuilder;

  static const double phoneBreakpoint = 700;
  static const double desktopBreakpoint = 1100;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final content = _ContentViewport(
          controller: controller,
          features: features,
          access: access,
        );

        if (width < phoneBreakpoint) {
          return Scaffold(
            key: const Key('phone-shell'),
            body: content,
            bottomNavigationBar: _BottomNavigation(controller: controller),
            floatingActionButton: _accountActions,
          );
        }

        if (width < desktopBreakpoint) {
          return Scaffold(
            key: const Key('tablet-shell'),
            body: Row(
              children: <Widget>[
                SafeArea(
                  right: false,
                  child: _NavigationRail(controller: controller),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
            floatingActionButton: _accountActions,
          );
        }

        return Scaffold(
          key: const Key('desktop-shell'),
          body: Row(
            children: <Widget>[
              SafeArea(
                right: false,
                child: _NavigationSidebar(controller: controller),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
          floatingActionButton: _accountActions,
        );
      },
    );
  }

  Widget? get _accountActions {
    if (onChangeHome == null &&
        onSignOut == null &&
        accountPageBuilder == null) {
      return null;
    }
    return _AccountActionsButton(
      onChangeHome: onChangeHome,
      onSignOut: onSignOut,
      accountPageBuilder: accountPageBuilder,
    );
  }
}

enum _AccountAction { manageAccess, changeHome, signOut }

class _AccountActionsButton extends StatelessWidget {
  const _AccountActionsButton({
    required this.onChangeHome,
    required this.onSignOut,
    required this.accountPageBuilder,
  });

  final Future<void> Function()? onChangeHome;
  final Future<void> Function()? onSignOut;
  final WidgetBuilder? accountPageBuilder;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: ProvidentiaColors.surfaceStrong,
      shape: const CircleBorder(),
      child: PopupMenuButton<_AccountAction>(
        key: const Key('account-actions'),
        tooltip: 'Account actions',
        icon: const Icon(Icons.person_outline_rounded),
        onSelected: (action) {
          if (action == _AccountAction.manageAccess) {
            final builder = accountPageBuilder;
            if (builder != null) {
              unawaited(
                Navigator.of(
                  context,
                ).push<void>(MaterialPageRoute<void>(builder: builder)),
              );
            }
            return;
          }
          final callback = switch (action) {
            _AccountAction.manageAccess => null,
            _AccountAction.changeHome => onChangeHome,
            _AccountAction.signOut => onSignOut,
          };
          if (callback != null) {
            unawaited(callback());
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<_AccountAction>>[
          if (accountPageBuilder != null)
            const PopupMenuItem<_AccountAction>(
              value: _AccountAction.manageAccess,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.manage_accounts_outlined),
                title: Text('Account & access'),
              ),
            ),
          if (onChangeHome != null)
            const PopupMenuItem<_AccountAction>(
              value: _AccountAction.changeHome,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.home_work_outlined),
                title: Text('Change home'),
              ),
            ),
          if (onSignOut != null)
            const PopupMenuItem<_AccountAction>(
              value: _AccountAction.signOut,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout_rounded),
                title: Text('Sign out'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ContentViewport extends StatelessWidget {
  const _ContentViewport({
    required this.controller,
    required this.features,
    required this.access,
  });

  final AppController controller;
  final HouseholdFeatures? features;
  final HouseholdWorkspaceAccess access;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final page = switch (controller.section) {
      AppSection.home => _HomeWorkspace(
        controller: controller,
        features: features,
        access: access,
      ),
      AppSection.stock =>
        features == null
            ? const _UnavailableWorkspace(title: 'Stock')
            : !access.inventoryRead
            ? const _AccessDeniedWorkspace(title: 'Stock')
            : access.inventoryWrite
            ? InventoryWorkspace(controller: features!.inventory)
            : _ReadOnlyInventoryWorkspace(controller: features!.inventory),
      AppSection.purchases =>
        features == null
            ? const _UnavailableWorkspace(title: 'Purchases')
            : !access.purchasesRead
            ? const _AccessDeniedWorkspace(title: 'Purchases')
            : access.purchasesWrite
            ? PurchasingWorkspace(controller: features!.purchasing)
            : _ReadOnlyPurchasingWorkspace(controller: features!.purchasing),
      AppSection.lists =>
        features == null
            ? const _UnavailableWorkspace(title: 'Lists')
            : !access.shoppingRead
            ? const _AccessDeniedWorkspace(title: 'Lists')
            : access.shoppingWrite
            ? ShoppingWorkspace(controller: features!.shopping)
            : _ReadOnlyShoppingWorkspace(controller: features!.shopping),
    };

    return SafeArea(
      left: false,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 160),
        child: KeyedSubtree(key: ValueKey(controller.section), child: page),
      ),
    );
  }
}

class _HomeWorkspace extends StatelessWidget {
  const _HomeWorkspace({
    required this.controller,
    required this.features,
    required this.access,
  });

  final AppController controller;
  final HouseholdFeatures? features;
  final HouseholdWorkspaceAccess access;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const Key('home-workspace'),
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 700 ? 20 : 32,
            24,
            MediaQuery.sizeOf(context).width < 700 ? 20 : 40,
            32,
          ),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const _BrandBar(),
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text(
                        'Your pantry, ready',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'A calm, local-first workspace for your household.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    _SyncStatusCard(
                      summary: controller.syncSummary,
                      onRetry: controller.refresh,
                    ),
                    const SizedBox(height: 20),
                    _QuickActions(
                      receiptEnabled: features != null && access.purchasesWrite,
                      stockEnabled: features != null && access.inventoryWrite,
                      onReceipt: () =>
                          controller.selectSection(AppSection.purchases),
                      onStockPhoto: () =>
                          controller.selectSection(AppSection.stock),
                    ),
                    const SizedBox(height: 20),
                    if (features == null)
                      const _OverviewGrid(
                        features: null,
                        access: HouseholdWorkspaceAccess.denied,
                      )
                    else
                      ListenableBuilder(
                        listenable: Listenable.merge(<Listenable>[
                          features!.inventory,
                          features!.purchasing,
                          features!.shopping,
                        ]),
                        builder: (context, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _OverviewGrid(features: features, access: access),
                            if (access.inventoryRead) ...<Widget>[
                              const SizedBox(height: 20),
                              _RecentStockPanel(features: features!),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    _WorkspacePanel(
                      controller: controller,
                      features: features,
                      access: access,
                    ),
                    const SizedBox(height: 20),
                    const _ContractBoundaryNotice(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.receiptEnabled,
    required this.stockEnabled,
    required this.onReceipt,
    required this.onStockPhoto,
  });

  final bool receiptEnabled;
  final bool stockEnabled;
  final VoidCallback onReceipt;
  final VoidCallback onStockPhoto;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        FilledButton.icon(
          key: const Key('receipt-capture-action'),
          onPressed: receiptEnabled ? onReceipt : null,
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Review a receipt'),
        ),
        OutlinedButton.icon(
          key: const Key('stock-photo-action'),
          onPressed: stockEnabled ? onStockPhoto : null,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Count from photos'),
        ),
      ],
    );
  }
}

class _BrandBar extends StatelessWidget {
  const _BrandBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Semantics(
          key: const Key('brand-mark-semantics'),
          label: 'Providentia',
          image: true,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: ProvidentiaColors.mint,
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(
                Icons.eco_rounded,
                color: ProvidentiaColors.forest,
                size: 30,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Providentia',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton.outlined(
          tooltip: 'Notifications',
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({required this.summary, required this.onRetry});

  final SyncSummary summary;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final conflict = summary.blockedConflicts > 0;
    final validation = summary.blockedValidation > 0;
    final authentication =
        summary.availability == SyncAvailability.authenticationRequired;
    final authorization =
        summary.availability == SyncAvailability.authorizationDenied ||
        summary.blockedAuthorization > 0;
    final waiting = summary.waiting > 0;
    final offline = summary.availability == SyncAvailability.offline;
    final unavailable =
        summary.availability == SyncAvailability.temporarilyUnavailable;
    final checking = summary.availability == SyncAvailability.checking;

    final (icon, title, detail, background, foreground) = conflict
        ? (
            Icons.sync_problem_rounded,
            'Review a synchronization conflict',
            '${summary.blockedConflicts} change needs your decision.',
            ProvidentiaColors.warningSurface,
            ProvidentiaColors.warning,
          )
        : validation
        ? (
            Icons.rule_rounded,
            'Review a change before syncing',
            summary.lastSafeError ??
                '${summary.blockedValidation} local change needs correction.',
            ProvidentiaColors.warningSurface,
            ProvidentiaColors.warning,
          )
        : authentication
        ? (
            Icons.lock_outline_rounded,
            'Sign in to continue',
            'Your local changes remain safely on this device.',
            ProvidentiaColors.warningSurface,
            ProvidentiaColors.warning,
          )
        : authorization
        ? (
            Icons.person_off_outlined,
            'Access to this home changed',
            summary.lastSafeError ??
                'Your local data is preserved while access is reviewed.',
            ProvidentiaColors.warningSurface,
            ProvidentiaColors.warning,
          )
        : waiting || offline || unavailable
        ? (
            Icons.cloud_off_outlined,
            waiting ? 'Saved on this device — waiting to sync' : 'Sync paused',
            unavailable
                ? summary.lastSafeError ??
                      'The service is temporarily unavailable. Try again.'
                : waiting
                ? '${summary.waiting} local change'
                      '${summary.waiting == 1 ? '' : 's'} waiting.'
                : 'You can keep working while offline.',
            ProvidentiaColors.warningSurface,
            ProvidentiaColors.warning,
          )
        : checking || summary.isSynchronizing
        ? (
            Icons.sync_rounded,
            'Checking synchronization',
            'Your local workspace is available.',
            ProvidentiaColors.mint,
            ProvidentiaColors.forest,
          )
        : (
            Icons.cloud_done_outlined,
            'Up to date',
            'Local data is ready and the service is available.',
            ProvidentiaColors.mint,
            ProvidentiaColors.forest,
          );

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $detail',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: foreground.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(icon, color: foreground, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: foreground),
                    ),
                    const SizedBox(height: 2),
                    Text(detail),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!summary.isSynchronizing)
                IconButton(
                  key: const Key('manual-sync'),
                  tooltip: 'Retry synchronization',
                  onPressed: () async {
                    await onRetry();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.features, required this.access});

  final HouseholdFeatures? features;
  final HouseholdWorkspaceAccess access;

  @override
  Widget build(BuildContext context) {
    final inventory = access.inventoryRead ? features?.inventory.state : null;
    final purchasing = access.purchasesRead ? features?.purchasing.state : null;
    final cards = <_OverviewData>[
      _OverviewData(
        icon: Icons.inventory_2_outlined,
        value: inventory == null || inventory.loading
            ? '—'
            : '${inventory.items.length}',
        label: 'Item master',
      ),
      _OverviewData(
        icon: Icons.check_circle_outline_rounded,
        value: inventory == null || inventory.loading
            ? '—'
            : '${inventory.items.where((item) => item.isCounted).length}',
        label: 'Counted stock',
      ),
      _OverviewData(
        icon: Icons.shopping_bag_outlined,
        value: purchasing == null || purchasing.loading
            ? '—'
            : '${purchasing.lines.where((line) => line.lineTotal != null).length}',
        label: 'Recent purchases',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 1;
        const spacing = 12.0;
        final columnWidth =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        final nominalExtent = columnWidth / (columns == 1 ? 3.7 : 2.1);

        return Wrap(
          key: const Key('overview-grid'),
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map(
                (data) => SizedBox(
                  width: columnWidth,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: nominalExtent),
                    child: _OverviewCard(data: data),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _RecentStockPanel extends StatelessWidget {
  const _RecentStockPanel({required this.features});

  final HouseholdFeatures features;

  @override
  Widget build(BuildContext context) {
    final items =
        features.inventory.state.items
            .where((item) => item.currentQuantity != null)
            .toList(growable: false)
          ..sort(
            (left, right) => (left.currentQuantity ?? 0).compareTo(
              right.currentQuantity ?? 0,
            ),
          );
    final visible = items.take(5);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Stock needing attention',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Complete a count to see stock here.'),
              )
            else
              for (final item in visible)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.canonicalName),
                  subtitle: Text('${item.packSize} · ${item.category}'),
                  trailing: Text(
                    item.currentQuantity == 0
                        ? 'Out of stock'
                        : '${item.currentQuantity!.toStringAsFixed(item.currentQuantity == item.currentQuantity!.roundToDouble() ? 0 : 2)} ${item.unit}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _OverviewData {
  const _OverviewData({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.data});

  final _OverviewData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            DecoratedBox(
              decoration: const BoxDecoration(
                color: ProvidentiaColors.mint,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(data.icon, color: ProvidentiaColors.greenDark),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(data.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspacePanel extends StatelessWidget {
  const _WorkspacePanel({
    required this.controller,
    required this.features,
    required this.access,
  });

  final AppController controller;
  final HouseholdFeatures? features;
  final HouseholdWorkspaceAccess access;

  @override
  Widget build(BuildContext context) {
    const workspaces = <(IconData, String, String, AppSection)>[
      (
        Icons.inventory_2_outlined,
        'Stock workspace',
        'Search the master, count stock, and review quantities',
        AppSection.stock,
      ),
      (
        Icons.shopping_bag_outlined,
        'Purchases workspace',
        'Review recent receipts and monthly purchase history',
        AppSection.purchases,
      ),
      (
        Icons.format_list_bulleted_rounded,
        'Lists workspace',
        'Manage manual and explainable suggested items',
        AppSection.lists,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Application workspaces',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final workspace in workspaces)
              _WorkspaceRow(
                icon: workspace.$1,
                title: workspace.$2,
                detail: workspace.$3,
                enabled: features != null && access.mayRead(workspace.$4),
                onTap: () => controller.selectSection(workspace.$4),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: ProvidentiaColors.canvas,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ProvidentiaColors.line),
              ),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Icon(icon, color: ProvidentiaColors.forest),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(detail),
                ],
              ),
            ),
            Icon(
              enabled
                  ? Icons.chevron_right_rounded
                  : Icons.lock_outline_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContractBoundaryNotice extends StatelessWidget {
  const _ContractBoundaryNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ProvidentiaColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ProvidentiaColors.line),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'Inventory, purchases, and lists are saved locally first and then '
          'synchronized through the pinned, generated backend contract when '
          'the service is available.',
        ),
      ),
    );
  }
}

class _ReadOnlyInventoryWorkspace extends StatelessWidget {
  const _ReadOnlyInventoryWorkspace({required this.controller});

  final InventoryController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        key: const Key('read-only-inventory-workspace'),
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('Stock', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 12),
          const _ReadOnlyNotice(),
          if (controller.state.safeError != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(controller.state.safeError!),
          ],
          const SizedBox(height: 12),
          for (final item in controller.visibleItems)
            Card(
              child: ListTile(
                title: Text(item.canonicalName),
                subtitle: Text('${item.packSize} · ${item.category}'),
                trailing: Text(
                  item.currentQuantity == null
                      ? 'Not counted'
                      : '${item.currentQuantity} ${item.unit}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadOnlyPurchasingWorkspace extends StatelessWidget {
  const _ReadOnlyPurchasingWorkspace({required this.controller});

  final PurchasingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        key: const Key('read-only-purchasing-workspace'),
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('Purchases', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 12),
          const _ReadOnlyNotice(),
          if (controller.state.safeError != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(controller.state.safeError!),
          ],
          const SizedBox(height: 12),
          for (final group in controller.recentGroups)
            Card(
              child: ListTile(
                title: Text(group.storeName),
                subtitle: Text(
                  '${group.lines.length} purchase line${group.lines.length == 1 ? '' : 's'}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadOnlyShoppingWorkspace extends StatelessWidget {
  const _ReadOnlyShoppingWorkspace({required this.controller});

  final ShoppingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final list = state.list;
        return ListView(
          key: const Key('read-only-shopping-workspace'),
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Text(
              'Shopping list',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            const _ReadOnlyNotice(),
            if (state.safeError != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(state.safeError!),
            ],
            if (list != null) ...<Widget>[
              const SizedBox(height: 12),
              for (final line in list.lines)
                ListTile(
                  leading: Icon(
                    line.checked
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                  ),
                  title: Text(line.name),
                  subtitle: Text(
                    line.explanation ?? 'Household shopping-list item',
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) => const Card(
    key: Key('household-read-only-notice'),
    child: ListTile(
      leading: Icon(Icons.visibility_outlined),
      title: Text('Read-only access'),
      subtitle: Text(
        'Your home role can view this information but cannot change it.',
      ),
    ),
  );
}

class _AccessDeniedWorkspace extends StatelessWidget {
  const _AccessDeniedWorkspace({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        key: const Key('household-access-denied'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.lock_outline_rounded, size: 52),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              const Text(
                'Your current home role does not allow this information to be viewed.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _UnavailableWorkspace extends StatelessWidget {
  const _UnavailableWorkspace({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: <Widget>[
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 52,
                      color: ProvidentiaColors.forest,
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'This feature requires a household data composition.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    const Chip(label: Text('Unavailable in preview mode')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<NavigationDestination> _destinations = <NavigationDestination>[
  NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
  NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Stock'),
  NavigationDestination(
    icon: Icon(Icons.shopping_bag_outlined),
    label: 'Purchases',
  ),
  NavigationDestination(
    icon: Icon(Icons.format_list_bulleted_rounded),
    label: 'Lists',
  ),
];

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      key: const Key('bottom-navigation'),
      selectedIndex: controller.section.index,
      onDestinationSelected: (index) {
        controller.selectSection(AppSection.values[index]);
      },
      destinations: _destinations,
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      key: const Key('navigation-rail'),
      selectedIndex: controller.section.index,
      onDestinationSelected: (index) {
        controller.selectSection(AppSection.values[index]);
      },
      labelType: NavigationRailLabelType.all,
      leading: const Padding(
        padding: EdgeInsets.only(bottom: 18),
        child: Icon(
          Icons.eco_rounded,
          color: ProvidentiaColors.forest,
          size: 34,
        ),
      ),
      destinations: _destinations
          .map(
            (destination) => NavigationRailDestination(
              icon: destination.icon,
              label: Text(destination.label),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _NavigationSidebar extends StatelessWidget {
  const _NavigationSidebar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('navigation-sidebar'),
      width: 256,
      child: Material(
        color: ProvidentiaColors.surfaceStrong,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const ListTile(
                leading: Icon(
                  Icons.eco_rounded,
                  color: ProvidentiaColors.forest,
                  size: 32,
                ),
                title: Text(
                  'Providentia',
                  style: TextStyle(
                    color: ProvidentiaColors.forest,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              for (var index = 0; index < _destinations.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    selected: controller.section.index == index,
                    selectedColor: ProvidentiaColors.forest,
                    selectedTileColor: ProvidentiaColors.mint,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: _destinations[index].icon,
                    title: Text(_destinations[index].label),
                    onTap: () {
                      controller.selectSection(AppSection.values[index]);
                    },
                  ),
                ),
              const Spacer(),
              const Text(
                'Local-first household workspace',
                textAlign: TextAlign.center,
                style: TextStyle(color: ProvidentiaColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
