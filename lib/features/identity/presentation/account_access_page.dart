import 'package:flutter/material.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/home_governance_page.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';
import 'package:providentia/features/identity/presentation/device_sessions_page.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';

final class AccountAccessPage extends StatelessWidget {
  const AccountAccessPage({
    required this.identityController,
    required this.homesController,
    this.catalogSharingPageBuilder,
    this.catalogContributionPageBuilder,
    this.householdReportsPageBuilder,
    this.householdAiPageBuilder,
    this.dataGovernancePageBuilder,
    super.key,
  });

  final IdentityController identityController;
  final HomesController homesController;
  final WidgetBuilder? catalogSharingPageBuilder;
  final WidgetBuilder? catalogContributionPageBuilder;
  final WidgetBuilder? householdReportsPageBuilder;
  final WidgetBuilder? householdAiPageBuilder;
  final WidgetBuilder? dataGovernancePageBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        identityController,
        homesController,
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final user = identityController.snapshot.currentUser;
    final home = homesController.snapshot.activeHome;
    final permissions = homesController.snapshot.effectivePermissions;
    return Scaffold(
      appBar: AppBar(title: const Text('Account & access')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(user?.email ?? 'Signed-in account'),
            subtitle: Text(
              home == null
                  ? 'No active home'
                  : '${home.name} · ${home.role.name}',
            ),
          ),
          const Divider(),
          ListTile(
            key: const Key('open-signed-in-devices'),
            leading: const Icon(Icons.devices_outlined),
            title: const Text('Signed-in devices'),
            subtitle: const Text(
              'Review the current device and revoke sessions',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    DeviceSessionsPage(controller: identityController),
              ),
            ),
          ),
          if (home != null && user != null)
            ListTile(
              key: const Key('open-home-governance'),
              leading: const Icon(Icons.group_outlined),
              title: const Text('Home members & roles'),
              subtitle: Text(
                '${homesController.snapshot.pendingInvitations.length} pending invitations for you',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => HomeGovernancePage(
                    controller: homesController,
                    currentUserId: user.userId,
                  ),
                ),
              ),
            ),
          if (home != null &&
              householdReportsPageBuilder != null &&
              mayAccessHouseholdReports(permissions))
            ListTile(
              key: const Key('open-household-reports'),
              leading: const Icon(Icons.assessment_outlined),
              title: const Text('Household reports'),
              subtitle: const Text(
                'View private evidence for the selected home',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: householdReportsPageBuilder!),
              ),
            ),
          if (user != null &&
              home != null &&
              householdAiPageBuilder != null &&
              mayAccessHouseholdAi(permissions))
            ListTile(
              key: const Key('open-household-ai'),
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Household AI'),
              subtitle: const Text(
                'Prepare one private image for explicit, reviewed extraction',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: householdAiPageBuilder!),
              ),
            ),
          if (user != null && dataGovernancePageBuilder != null)
            ListTile(
              key: const Key('open-data-governance'),
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Your data'),
              subtitle: Text(
                home == null ||
                        !permissions.any(
                          const <String>{
                            HomePermissions.dataExport,
                            HomePermissions.dataErasure,
                          }.contains,
                        )
                    ? 'Request account exports or erasure'
                    : 'Manage account and selected-home data requests',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: dataGovernancePageBuilder!),
              ),
            ),
          if (home != null &&
              catalogSharingPageBuilder != null &&
              mayAccessCatalogSharing(permissions))
            ListTile(
              key: const Key('open-catalog-sharing'),
              leading: const Icon(Icons.share_outlined),
              title: const Text('Catalog sharing'),
              subtitle: const Text(
                'Choose each public catalog contribution category separately',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: catalogSharingPageBuilder!),
              ),
            ),
          if (home != null &&
              catalogContributionPageBuilder != null &&
              mayContributeCatalogProduct(permissions))
            ListTile(
              key: const Key('open-catalog-product-contribution'),
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Contribute a product'),
              subtitle: const Text(
                'Choose one item and preview the exact public fields',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: catalogContributionPageBuilder!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Report access comes exclusively from the selected home's effective policy;
/// platform roles never satisfy this household-data gate.
@visibleForTesting
bool mayAccessHouseholdReports(Set<String> permissions) =>
    permissions.contains(HomePermissions.reportsRead);

/// AI discovery is an exact active-home permission check. Platform roles do
/// not grant access to household settings, media, or candidate reviews.
@visibleForTesting
bool mayAccessHouseholdAi(Set<String> permissions) =>
    permissions.contains(HomePermissions.aiRead);

/// Catalog sharing is available only through the selected home's exact
/// consent-management or contribution permission.
bool mayAccessCatalogSharing(Set<String> permissions) => permissions.any(
  const <String>{
    HomePermissions.catalogConsentManage,
    HomePermissions.catalogContribute,
  }.contains,
);

bool mayContributeCatalogProduct(Set<String> permissions) =>
    permissions.contains(HomePermissions.catalogContribute) &&
    permissions.contains(HomePermissions.inventoryRead);
