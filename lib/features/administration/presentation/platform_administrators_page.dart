import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:providentia/features/administration/application/platform_administration_controller.dart';
import 'package:providentia/features/administration/domain/platform_administrator_models.dart';

final class PlatformAdministratorsPage extends StatefulWidget {
  const PlatformAdministratorsPage({required this.controller, super.key});

  final PlatformAdministrationController controller;

  @override
  State<PlatformAdministratorsPage> createState() =>
      _PlatformAdministratorsPageState();
}

final class _PlatformAdministratorsPageState
    extends State<PlatformAdministratorsPage> {
  final TextEditingController _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Platform administrators')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final snapshot = widget.controller.snapshot;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Text(
                'Platform administration is global and never grants access to a home.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('platform-administrator-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                enabled: !snapshot.loading,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('grant-platform-administrator'),
                onPressed: snapshot.loading
                    ? null
                    : () => unawaited(widget.controller.grant(_email.text)),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add administrator'),
              ),
              if (snapshot.loading) ...<Widget>[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (snapshot.safeMessage != null) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  snapshot.safeMessage!,
                  key: const Key('platform-administrator-message'),
                ),
              ],
              const SizedBox(height: 24),
              ...snapshot.administrators.map(
                (administrator) => _administratorCard(
                  administrator,
                  isFinalActive:
                      administrator.status ==
                          PlatformAdministratorStatus.active &&
                      snapshot.administrators
                              .where(
                                (item) =>
                                    item.status ==
                                    PlatformAdministratorStatus.active,
                              )
                              .length ==
                          1,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _administratorCard(
    PlatformAdministrator administrator, {
    required bool isFinalActive,
  }) {
    final active = administrator.status == PlatformAdministratorStatus.active;
    return Card(
      child: ListTile(
        key: Key('platform-administrator-${administrator.id}'),
        leading: Icon(active ? Icons.verified_user : Icons.schedule),
        title: Text(administrator.email),
        subtitle: Text(
          '${active ? 'Active' : 'Pending verification'} · added ${DateFormat.yMMMd().format(administrator.createdAt.toLocal())}',
        ),
        trailing: IconButton(
          tooltip: isFinalActive
              ? 'The final active administrator cannot be revoked'
              : 'Revoke administrator',
          onPressed: widget.controller.snapshot.loading || isFinalActive
              ? null
              : () => unawaited(_confirmRevoke(administrator)),
          icon: const Icon(Icons.person_remove_outlined),
        ),
      ),
    );
  }

  Future<void> _confirmRevoke(PlatformAdministrator administrator) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke platform administrator?'),
        content: Text(
          '${administrator.email} will lose global administration access. Home memberships are unchanged.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await widget.controller.revoke(administrator);
    }
  }
}
