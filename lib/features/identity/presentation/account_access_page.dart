import 'package:flutter/material.dart';
import 'package:providentia/features/administration/application/platform_administration_controller.dart';
import 'package:providentia/features/administration/presentation/platform_administrators_page.dart';
import 'package:providentia/features/homes/presentation/home_governance_page.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';
import 'package:providentia/features/identity/presentation/device_sessions_page.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';

final class AccountAccessPage extends StatelessWidget {
  const AccountAccessPage({
    required this.identityController,
    required this.homesController,
    this.platformAdministrationController,
    super.key,
  });

  final IdentityController identityController;
  final HomesController homesController;
  final PlatformAdministrationController? platformAdministrationController;

  @override
  Widget build(BuildContext context) {
    final user = identityController.snapshot.currentUser;
    final home = homesController.snapshot.activeHome;
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
          if (platformAdministrationController != null)
            ListTile(
              key: const Key('open-platform-administrators'),
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Platform administrators'),
              subtitle: const Text(
                'Add, review, or revoke global administrators',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => PlatformAdministratorsPage(
                    controller: platformAdministrationController!,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
