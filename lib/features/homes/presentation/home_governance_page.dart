import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';

final class HomeGovernancePage extends StatefulWidget {
  const HomeGovernancePage({
    required this.controller,
    required this.currentUserId,
    super.key,
  });

  final HomesController controller;
  final String currentUserId;

  @override
  State<HomeGovernancePage> createState() => _HomeGovernancePageState();
}

final class _HomeGovernancePageState extends State<HomeGovernancePage> {
  static const List<String> _knownPermissions = <String>[
    ...HomePermissions.owner,
  ];

  final TextEditingController _inviteEmail = TextEditingController();
  HomeRole _inviteRole = HomeRole.member;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refreshGovernance());
  }

  @override
  void dispose() {
    _inviteEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home access')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final snapshot = widget.controller.snapshot;
          final home = snapshot.activeHome;
          if (home == null) {
            return const Center(child: Text('Select a home first.'));
          }
          final permissions = snapshot.effectivePermissions;
          final canInvite = permissions.contains(HomePermissions.membersInvite);
          final canManageMembers = permissions.contains(
            HomePermissions.membersManage,
          );
          final canManagePolicies = permissions.contains(
            HomePermissions.permissionsManage,
          );
          return RefreshIndicator(
            onRefresh: widget.controller.refreshGovernance,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                Text(
                  home.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text('Your role: ${home.role.name}'),
                if (permissions.contains(
                  HomePermissions.homeManage,
                )) ...<Widget>[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('edit-home-settings'),
                    onPressed: () => _editHome(home),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit home settings'),
                  ),
                ],
                if (snapshot.safeMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    snapshot.safeMessage!,
                    key: const Key('governance-message'),
                  ),
                ],
                if (snapshot.pendingInvitations.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  Text(
                    'Your pending invitations',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ...snapshot.pendingInvitations.map(_pendingInvitation),
                ],
                if (permissions.contains(
                  HomePermissions.membersRead,
                )) ...<Widget>[
                  const SizedBox(height: 24),
                  Text(
                    'Members',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ...snapshot.memberships.map(
                    (membership) => _membership(
                      membership,
                      canManageMembers: canManageMembers,
                    ),
                  ),
                ],
                if (canInvite) ...<Widget>[
                  const SizedBox(height: 24),
                  Text(
                    'Invite someone',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('home-invitation-email'),
                    controller: _inviteEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<HomeRole>(
                    key: const Key('home-invitation-role'),
                    initialValue: _inviteRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items:
                        const <HomeRole>[
                              HomeRole.manager,
                              HomeRole.member,
                              HomeRole.viewer,
                            ]
                            .map(
                              (role) => DropdownMenuItem<HomeRole>(
                                value: role,
                                child: Text(role.name),
                              ),
                            )
                            .toList(growable: false),
                    onChanged: (role) {
                      if (role != null) setState(() => _inviteRole = role);
                    },
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const Key('send-home-invitation'),
                    onPressed: () => unawaited(
                      widget.controller.invite(
                        email: _inviteEmail.text,
                        role: _inviteRole,
                      ),
                    ),
                    icon: const Icon(Icons.outgoing_mail),
                    label: const Text('Send invitation'),
                  ),
                ],
                if (snapshot.invitations.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  Text(
                    'Sent invitations',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ...snapshot.invitations.map(_sentInvitation),
                ],
                if (canManagePolicies &&
                    snapshot.permissionPolicies.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  Text(
                    'Role permissions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Permissions come from the server policy for each home role.',
                  ),
                  ...snapshot.permissionPolicies.map(_policy),
                ],
                if (home.role != HomeRole.owner) ...<Widget>[
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    key: const Key('leave-active-home'),
                    onPressed: () =>
                        unawaited(widget.controller.leaveActiveHome()),
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text('Leave this home'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pendingInvitation(RecipientHomeInvitation invitation) => Card(
    child: ListTile(
      key: Key('governance-pending-invitation-${invitation.id}'),
      title: Text(invitation.homeName),
      subtitle: Text('${invitation.role.name} access'),
      trailing: FilledButton(
        onPressed: () =>
            unawaited(widget.controller.acceptPendingInvitation(invitation)),
        child: const Text('Accept'),
      ),
    ),
  );

  Widget _membership(
    HomeMembership membership, {
    required bool canManageMembers,
  }) {
    final editable =
        canManageMembers &&
        membership.role != HomeRole.owner &&
        membership.userId != widget.currentUserId;
    return Card(
      child: ListTile(
        key: Key('home-membership-${membership.userId}'),
        leading: Icon(
          membership.userId == widget.currentUserId
              ? Icons.person_rounded
              : Icons.person_outline_rounded,
        ),
        title: Text(membership.displayName),
        subtitle: Text(membership.email ?? membership.role.name),
        trailing: editable
            ? DropdownButton<HomeRole>(
                value: membership.role,
                items:
                    const <HomeRole>[
                          HomeRole.manager,
                          HomeRole.member,
                          HomeRole.viewer,
                        ]
                        .map(
                          (role) => DropdownMenuItem<HomeRole>(
                            value: role,
                            child: Text(role.name),
                          ),
                        )
                        .toList(growable: false),
                onChanged: (role) {
                  if (role != null) {
                    unawaited(
                      widget.controller.changeMembershipRole(
                        membership: membership,
                        role: role,
                      ),
                    );
                  }
                },
              )
            : Chip(label: Text(membership.role.name)),
      ),
    );
  }

  Widget _sentInvitation(HomeInvitation invitation) => Card(
    child: ListTile(
      key: Key('sent-home-invitation-${invitation.id}'),
      title: Text(invitation.email),
      subtitle: Text(
        '${invitation.role.name} · ${invitation.status.name} · expires ${DateFormat.yMMMd().format(invitation.expiresAt.toLocal())}',
      ),
      trailing: invitation.mayBeRevoked
          ? IconButton(
              tooltip: 'Revoke invitation',
              onPressed: () =>
                  unawaited(widget.controller.revokeInvitation(invitation)),
              icon: const Icon(Icons.cancel_outlined),
            )
          : null,
    ),
  );

  Widget _policy(HomePermissionPolicy policy) => Card(
    child: ListTile(
      key: Key('permission-policy-${policy.role.name}'),
      title: Text(policy.role.name),
      subtitle: Text((policy.permissions.toList()..sort()).join(', ')),
      trailing: policy.configurable
          ? IconButton(
              tooltip: 'Edit ${policy.role.name} permissions',
              onPressed: () => _editPolicy(policy),
              icon: const Icon(Icons.edit_outlined),
            )
          : const Chip(label: Text('Fixed')),
    ),
  );

  Future<void> _editPolicy(HomePermissionPolicy policy) async {
    final selected = policy.permissions.toSet();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${policy.role.name} permissions'),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: _knownPermissions
                  .map(
                    (permission) => CheckboxListTile(
                      value: selected.contains(permission),
                      title: Text(permission),
                      onChanged: (checked) => setDialogState(() {
                        if (checked ?? false) {
                          selected.add(permission);
                        } else {
                          selected.remove(permission);
                        }
                      }),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved ?? false) {
      await widget.controller.updatePermissionPolicy(
        policy: policy,
        permissions: selected,
      );
    }
  }

  Future<void> _editHome(HomeSummary home) async {
    var name = home.name;
    var locale = home.locale;
    var currency = home.currency;
    var timezone = home.timezone;
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit home settings'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  key: const Key('edit-home-name'),
                  initialValue: name,
                  onChanged: (value) => name = value,
                  decoration: const InputDecoration(labelText: 'Home name'),
                  validator: _required,
                ),
                TextFormField(
                  key: const Key('edit-home-locale'),
                  initialValue: locale,
                  onChanged: (value) => locale = value,
                  decoration: const InputDecoration(labelText: 'Locale'),
                  validator: (value) => (value?.trim().length ?? 0) >= 2
                      ? null
                      : 'Enter a locale.',
                ),
                TextFormField(
                  key: const Key('edit-home-currency'),
                  initialValue: currency,
                  onChanged: (value) => currency = value,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  validator: (value) =>
                      RegExp(r'^[A-Za-z]{3}$').hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Use 3 letters.',
                ),
                TextFormField(
                  key: const Key('edit-home-timezone'),
                  initialValue: timezone,
                  onChanged: (value) => timezone = value,
                  decoration: const InputDecoration(labelText: 'Time zone'),
                  validator: _required,
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState?.validate() ?? false) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved ?? false) {
      await widget.controller.updateActiveHome(
        name: name,
        locale: locale,
        currency: currency,
        timezone: timezone,
      );
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
}
