import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:providentia/features/homes/domain/home_models.dart';
import 'package:providentia/features/homes/presentation/homes_controller.dart';
import 'package:providentia/features/profile/email_confirmation_dialog.dart';
import 'package:providentia/features/profile/profile_port.dart';

import 'home_profile_page.dart';
import 'member_permissions_page.dart';

final class HomeGovernancePage extends StatefulWidget {
  const HomeGovernancePage({
    required this.controller,
    required this.profilePort,
    required this.currentUserId,
    super.key,
  });

  final HomesController controller;
  final ProfilePort profilePort;
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
  String? _transferTargetUserId;

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
          final canTransferOwnership = permissions.contains(
            HomePermissions.ownershipTransfer,
          );
          final ownershipOffers = snapshot.ownershipTransfers
              .where((transfer) => transfer.isOfferedTo(widget.currentUserId))
              .toList(growable: false);
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
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => HomeProfilePage(
                          port: widget.profilePort,
                          homeId: home.id,
                          mayEdit: permissions.contains(
                            HomePermissions.homeManage,
                          ),
                        ),
                      ),
                    );
                    await widget.controller.refreshGovernance();
                  },
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Home profile and photo'),
                ),
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
                if (ownershipOffers.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 24),
                  Text(
                    'Ownership transfer for you',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ...ownershipOffers.map(
                    (transfer) => _ownershipOffer(transfer, home),
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
                      home: home,
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
                        <HomeRole>[
                              if (home.role == HomeRole.owner) HomeRole.owner,
                              if (home.role == HomeRole.owner) HomeRole.manager,
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
                if (canTransferOwnership) ..._ownershipSection(snapshot),
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
    required HomeSummary home,
    required bool canManageMembers,
  }) {
    // The caller's own row ends through Leave and the owner row changes only
    // through an accepted ownership transfer, so neither is editable here.
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
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.controller.snapshot.effectivePermissions.contains(
                    HomePermissions.permissionsManage,
                  ))
                    IconButton(
                      tooltip: 'Individual permissions',
                      icon: const Icon(Icons.tune),
                      onPressed: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => MemberPermissionsPage(
                              port: widget.profilePort,
                              home: home,
                              member: membership,
                            ),
                          ),
                        );
                        await widget.controller.refreshGovernance();
                      },
                    ),
                  DropdownButton<HomeRole>(
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
                  ),
                  IconButton(
                    key: Key('remove-home-membership-${membership.userId}'),
                    tooltip: 'Remove ${membership.displayName}',
                    onPressed: () =>
                        unawaited(_confirmRemoval(membership, home)),
                    icon: const Icon(Icons.person_remove_outlined),
                  ),
                ],
              )
            : Chip(label: Text(membership.role.name)),
      ),
    );
  }

  Future<void> _confirmRemoval(
    HomeMembership membership,
    HomeSummary home,
  ) async {
    final removed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${membership.displayName}?'),
        content: Text(
          'This immediately ends the ${membership.role.name} access of '
          '${membership.displayName} to ${home.name}. They can only return '
          'through a new invitation.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-remove-membership'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (removed ?? false) {
      await widget.controller.removeMembership(membership);
    }
  }

  Widget _ownershipOffer(HomeOwnershipTransfer transfer, HomeSummary home) =>
      Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            key: Key('ownership-transfer-offer-${transfer.id}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Become the owner of ${home.name}?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'The current owner proposed transferring ownership to you. '
                'Accepting makes you responsible for this home immediately.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton(
                    key: Key('accept-ownership-transfer-${transfer.id}'),
                    onPressed: () => unawaited(
                      widget.controller.acceptOwnershipTransfer(transfer),
                    ),
                    child: const Text('Accept ownership'),
                  ),
                  OutlinedButton(
                    key: Key('reject-ownership-transfer-${transfer.id}'),
                    onPressed: () => unawaited(
                      widget.controller.rejectOwnershipTransfer(transfer),
                    ),
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  List<Widget> _ownershipSection(HomeSessionSnapshot snapshot) {
    final eligible = snapshot.memberships
        .where(
          (membership) =>
              membership.isActive &&
              membership.role != HomeRole.owner &&
              membership.userId != widget.currentUserId,
        )
        .toList(growable: false);
    final pendingTransfers = snapshot.ownershipTransfers
        .where((transfer) => transfer.isPending)
        .toList(growable: false);
    final selectedTargetId =
        eligible.any((membership) => membership.userId == _transferTargetUserId)
        ? _transferTargetUserId
        : null;
    return <Widget>[
      const SizedBox(height: 24),
      Text('Ownership', style: Theme.of(context).textTheme.titleLarge),
      const Text(
        'Ownership changes only after the proposed member accepts an '
        'email-confirmed transfer proposal.',
      ),
      ...pendingTransfers.map(
        (transfer) => _pendingTransfer(transfer, snapshot.memberships),
      ),
      if (eligible.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('Invite another member before transferring ownership.'),
        )
      else ...<Widget>[
        const SizedBox(height: 10),
        DropdownButton<String>(
          key: const Key('ownership-transfer-target'),
          isExpanded: true,
          value: selectedTargetId,
          hint: const Text('Choose the proposed new owner'),
          items: eligible
              .map(
                (membership) => DropdownMenuItem<String>(
                  value: membership.userId,
                  child: Text(
                    '${membership.displayName} · ${membership.role.name}',
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (userId) => setState(() => _transferTargetUserId = userId),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const Key('propose-ownership-transfer'),
          onPressed: selectedTargetId == null
              ? null
              : () => unawaited(
                  _proposeOwnership(
                    eligible.firstWhere(
                      (membership) => membership.userId == selectedTargetId,
                    ),
                  ),
                ),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Propose ownership transfer'),
        ),
      ],
    ];
  }

  Widget _pendingTransfer(
    HomeOwnershipTransfer transfer,
    List<HomeMembership> memberships,
  ) => Card(
    child: ListTile(
      key: Key('ownership-transfer-${transfer.id}'),
      leading: const Icon(Icons.swap_horiz_rounded),
      title: Text(
        'Proposed to ${_memberName(transfer.targetUserId, memberships)}',
      ),
      subtitle: Text(
        '${transfer.status.name} · expires '
        '${DateFormat.yMMMd().format(transfer.expiresAt.toLocal())}',
      ),
      trailing: IconButton(
        key: Key('revoke-ownership-transfer-${transfer.id}'),
        tooltip: 'Revoke ownership transfer',
        onPressed: () =>
            unawaited(widget.controller.revokeOwnershipTransfer(transfer)),
        icon: const Icon(Icons.cancel_outlined),
      ),
    ),
  );

  String _memberName(String userId, List<HomeMembership> memberships) {
    for (final membership in memberships) {
      if (membership.userId == userId) {
        return membership.displayName;
      }
    }
    return 'Household member';
  }

  Future<void> _proposeOwnership(HomeMembership target) async {
    final confirmation = await confirmAccountEmail(
      context,
      widget.profilePort,
      action: 'ownership-transfer',
    );
    if (confirmation == null || !mounted) return;
    await widget.controller.proposeOwnershipTransfer(
      target: target,
      stepUpToken: '${confirmation['proofToken']}',
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
                  .where(
                    (permission) =>
                        (widget
                                        .controller
                                        .snapshot
                                        .activeHome
                                        ?.access['delegablePermissions']
                                    as List? ??
                                <Object?>[])
                            .contains(permission),
                  )
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
