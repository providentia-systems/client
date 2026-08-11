import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/features/sync_conflicts/presentation/sync_conflict_controller.dart';

typedef SyncCountReconciliationHandler =
    FutureOr<void> Function(SyncConflict conflict);

final class SyncConflictPage extends StatefulWidget {
  const SyncConflictPage({
    required this.controller,
    this.onCountReconciliation,
    super.key,
  });

  final SyncConflictController controller;
  final SyncCountReconciliationHandler? onCountReconciliation;

  @override
  State<SyncConflictPage> createState() => _SyncConflictPageState();
}

final class _SyncConflictPageState extends State<SyncConflictPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.start());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronization review')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          if (controller.status == SyncConflictReviewStatus.loading ||
              controller.status == SyncConflictReviewStatus.idle) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.status == SyncConflictReviewStatus.accessDenied) {
            return _Message(
              icon: Icons.lock_outline,
              title: 'Conflict review unavailable',
              detail:
                  controller.safeMessage ??
                  'Your current home role does not allow conflict review.',
            );
          }
          if (controller.status == SyncConflictReviewStatus.failed &&
              controller.conflicts.isEmpty) {
            return _Message(
              icon: Icons.sync_problem,
              title: 'Conflict evidence unavailable',
              detail:
                  controller.safeMessage ?? 'No conflict decision was changed.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Text(
                'Choose deliberately. Server and device evidence remain unchanged until a resolution commits atomically.',
              ),
              if (controller.safeMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(controller.safeMessage!),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (controller.conflicts.isEmpty)
                const _Message(
                  icon: Icons.cloud_done_outlined,
                  title: 'No conflicts need review',
                  detail: 'The current home has no unresolved evidence.',
                )
              else
                for (final conflict in controller.conflicts)
                  _ConflictCard(
                    conflict: conflict,
                    enabled:
                        !controller.isBusy && controller.canResolve(conflict),
                    onAcceptRemote: () => _confirm(
                      conflict: conflict,
                      title: 'Use the server version?',
                      detail:
                          'The blocked device operation will be superseded, not marked acknowledged.',
                      action: controller.acceptRemote,
                    ),
                    onReapplyLocal: () => _confirm(
                      conflict: conflict,
                      title: 'Reapply the device change?',
                      detail:
                          'A fresh operation will use the authoritative server revision.',
                      action: controller.reapplyLocal,
                    ),
                    onCountReconciliation: () => _confirmCount(conflict),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirm({
    required SyncConflict conflict,
    required String title,
    required String detail,
    required Future<bool> Function(SyncConflict conflict) action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-conflict-resolution'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await action(conflict);
  }

  Future<void> _confirmCount(SyncConflict conflict) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use the server count?'),
        content: const Text(
          'The stale device count command will be superseded without creating movements. Continue in Stock to review or start a fresh count.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-count-reconciliation'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use server count'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final resolved = await widget.controller.reconcileCount(conflict);
    if (!resolved || !mounted) return;
    await widget.onCountReconciliation?.call(conflict);
    if (mounted) Navigator.of(context).pop();
  }
}

final class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.enabled,
    required this.onAcceptRemote,
    required this.onReapplyLocal,
    required this.onCountReconciliation,
  });

  final SyncConflict conflict;
  final bool enabled;
  final VoidCallback onAcceptRemote;
  final VoidCallback onReapplyLocal;
  final VoidCallback onCountReconciliation;

  @override
  Widget build(BuildContext context) {
    final remoteSummary = switch (conflict.remote.kind) {
      SyncConflictRemoteKind.upsert =>
        'Server revision ${conflict.remote.revision ?? 'unknown'} is available.',
      SyncConflictRemoteKind.tombstone =>
        'The server deleted this record at revision ${conflict.remote.revision ?? 'unknown'}.',
      SyncConflictRemoteKind.unavailable =>
        'The server representation is not available yet.',
    };
    return Card(
      key: Key('sync-conflict-${conflict.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _safeEntityLabel(conflict.entityType),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Device intent: ${conflict.local.operationType}. $remoteSummary',
            ),
            const SizedBox(height: 12),
            if (conflict.requiresCountReconciliation)
              OutlinedButton.icon(
                key: Key('reconcile-count-${conflict.id}'),
                onPressed: enabled ? onCountReconciliation : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Reconcile count'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton(
                    key: Key('accept-remote-${conflict.id}'),
                    onPressed: enabled && conflict.canAcceptRemote
                        ? onAcceptRemote
                        : null,
                    child: const Text('Use server version'),
                  ),
                  FilledButton(
                    key: Key('reapply-local-${conflict.id}'),
                    onPressed: enabled && conflict.canReapplyLocal
                        ? onReapplyLocal
                        : null,
                    child: const Text('Reapply device change'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _safeEntityLabel(String entityType) => switch (entityType) {
    'inventory-count-session' || 'inventory-count-line' => 'Stock count',
    'inventory-balance' => 'Inventory balance',
    'purchasing-receipt' || 'purchasing-receipt-line' => 'Purchase',
    'shopping-list' || 'shopping-list-line' => 'Shopping list',
    _ => 'Household record',
  };
}

final class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(detail, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
