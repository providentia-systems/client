import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia/features/identity/presentation/identity_controller.dart';

final class DeviceSessionsPage extends StatefulWidget {
  const DeviceSessionsPage({required this.controller, super.key});

  final IdentityController controller;

  @override
  State<DeviceSessionsPage> createState() => _DeviceSessionsPageState();
}

final class _DeviceSessionsPageState extends State<DeviceSessionsPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.loadDeviceSessions());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signed-in devices')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final snapshot = widget.controller.snapshot;
          final now = DateTime.now().toUtc();
          final sessions =
              snapshot.deviceSessions
                  .where((session) => session.isActiveAt(now))
                  .toList(growable: false)
                ..sort((left, right) {
                  if (left.current != right.current) {
                    return left.current ? -1 : 1;
                  }
                  return right.lastSeenAt.compareTo(left.lastSeenAt);
                });
          if (sessions.isEmpty && widget.controller.isBusy) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: widget.controller.loadDeviceSessions,
            child: ListView(
              key: const Key('device-session-list'),
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                const Text(
                  'Sessions renew while you use Providentia. Web sessions expire after 30 days of inactivity; app sessions expire after 60 days.',
                ),
                const SizedBox(height: 16),
                if (sessions.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.devices_other_outlined),
                    title: Text('No signed-in devices could be loaded'),
                  )
                else
                  ...sessions.map(_sessionCard),
                if (snapshot.safeMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    snapshot.safeMessage!,
                    key: const Key('device-session-message'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sessionCard(DeviceSessionView session) {
    final formatter = DateFormat.yMMMd().add_jm();
    final transport = switch (session.transport) {
      ClientSessionTransport.nativeBearer => 'App',
      ClientSessionTransport.webCookie => 'Web',
    };
    return Card(
      child: ListTile(
        key: Key('device-session-${session.id}'),
        leading: Icon(
          session.current ? Icons.devices_rounded : Icons.devices_outlined,
        ),
        title: Text(
          session.current
              ? '${session.deviceName} · current device'
              : session.deviceName,
        ),
        subtitle: Text(
          '${session.platform} · $transport\n'
          'Last used ${formatter.format(session.lastSeenAt.toLocal())}\n'
          'Idle deadline ${formatter.format(session.idleExpiresAt.toLocal())}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          key: Key('revoke-device-session-${session.id}'),
          tooltip: session.current ? 'Sign out this device' : 'Revoke device',
          onPressed: widget.controller.isBusy
              ? null
              : () => unawaited(_confirmRevoke(session)),
          icon: const Icon(Icons.logout_rounded),
        ),
      ),
    );
  }

  Future<void> _confirmRevoke(DeviceSessionView session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          session.current ? 'Sign out this device?' : 'Revoke this device?',
        ),
        content: Text(
          session.current
              ? 'You will need a new login link to use Providentia here again.'
              : '${session.deviceName} will need a new login link the next time it connects.',
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
    if (confirmed == true) {
      await widget.controller.revokeDeviceSession(session.id);
    }
  }
}
