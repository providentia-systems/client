import 'package:flutter/material.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/core/design_system/providentia_theme.dart';
import 'package:providentia/core/synchronization/sync_models.dart';

class ProvidentiaApp extends StatefulWidget {
  const ProvidentiaApp({required this.controller, this.onDispose, super.key});

  final AppController controller;
  final VoidCallback? onDispose;

  @override
  State<ProvidentiaApp> createState() => _ProvidentiaAppState();
}

class _ProvidentiaAppState extends State<ProvidentiaApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void dispose() {
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
          return _AdaptiveShell(controller: widget.controller);
        },
      ),
    );
  }
}

class _AdaptiveShell extends StatelessWidget {
  const _AdaptiveShell({required this.controller});

  final AppController controller;

  static const double phoneBreakpoint = 700;
  static const double desktopBreakpoint = 1100;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final content = _ContentViewport(controller: controller);

        if (width < phoneBreakpoint) {
          return Scaffold(
            key: const Key('phone-shell'),
            body: content,
            bottomNavigationBar: _BottomNavigation(controller: controller),
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
        );
      },
    );
  }
}

class _ContentViewport extends StatelessWidget {
  const _ContentViewport({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final page = switch (controller.section) {
      AppSection.home => _HomeWorkspace(controller: controller),
      AppSection.stock => const _DeferredWorkspace(
        icon: Icons.inventory_2_outlined,
        title: 'Stock',
        description:
            'The local data layer is ready for stock counts and balances. '
            'Inventory workflows arrive in Phase 5.',
      ),
      AppSection.purchases => const _DeferredWorkspace(
        icon: Icons.shopping_bag_outlined,
        title: 'Purchases',
        description:
            'Receipt and purchase-history surfaces remain intentionally '
            'deferred until Phase 5.',
      ),
      AppSection.lists => const _DeferredWorkspace(
        icon: Icons.format_list_bulleted_rounded,
        title: 'Lists',
        description:
            'The responsive workspace is prepared for manual and suggested '
            'lists without inventing Phase 5 behavior.',
      ),
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
  const _HomeWorkspace({required this.controller});

  final AppController controller;

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
                    _OverviewGrid(summary: controller.syncSummary),
                    const SizedBox(height: 20),
                    const _WorkspacePanel(),
                    const SizedBox(height: 20),
                    const _ImplementationNotice(),
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

class _BrandBar extends StatelessWidget {
  const _BrandBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Semantics(
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
  final AsyncCallback onRetry;

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
                  onPressed: onRetry,
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
  const _OverviewGrid({required this.summary});

  final SyncSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = <_OverviewData>[
      const _OverviewData(
        icon: Icons.grid_view_rounded,
        value: '4',
        label: 'Workspaces',
      ),
      const _OverviewData(
        icon: Icons.storage_rounded,
        value: 'Local',
        label: 'Offline store',
      ),
      _OverviewData(
        icon: Icons.sync_rounded,
        value: '${summary.waiting}',
        label: 'Waiting to sync',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 1;
        return GridView.count(
          key: const Key('overview-grid'),
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 3.7 : 2.1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cards
              .map((data) => _OverviewCard(data: data))
              .toList(growable: false),
        );
      },
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
  const _WorkspacePanel();

  @override
  Widget build(BuildContext context) {
    const workspaces = <(IconData, String, String)>[
      (
        Icons.inventory_2_outlined,
        'Stock workspace',
        'Prepared for count sessions and inventory balances',
      ),
      (
        Icons.shopping_bag_outlined,
        'Purchases workspace',
        'Prepared for receipt review and purchase history',
      ),
      (
        Icons.format_list_bulleted_rounded,
        'Lists workspace',
        'Prepared for manual and suggested shopping lists',
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
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          const Chip(label: Text('Phase 5')),
        ],
      ),
    );
  }
}

class _ImplementationNotice extends StatelessWidget {
  const _ImplementationNotice();

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
          'Prototype shell: the Fresh Market design system, persistent local '
          'database, and synchronization lifecycle are active. Inventory, '
          'purchase, and list workflows remain outside this phase.',
        ),
      ),
    );
  }
}

class _DeferredWorkspace extends StatelessWidget {
  const _DeferredWorkspace({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

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
                    Icon(icon, size: 52, color: ProvidentiaColors.forest),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(description, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    const Chip(label: Text('Workflow begins in Phase 5')),
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
      child: ColoredBox(
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
                'Local-first prototype',
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
