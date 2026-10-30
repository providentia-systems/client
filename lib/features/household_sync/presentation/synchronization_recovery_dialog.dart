import 'package:flutter/material.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/synchronization_recovery.dart';

/// Recovery is available only inside an authorized home workspace. It preserves
/// the encrypted queue in place; it never exposes raw pending payloads.
final class SynchronizationRecoveryDialog extends StatefulWidget {
  const SynchronizationRecoveryDialog({
    super.key,
    required this.homeId,
    required this.recovery,
  });
  final String homeId;
  final AppSyncRecovery recovery;

  @override
  State<SynchronizationRecoveryDialog> createState() =>
      _SynchronizationRecoveryDialogState();
}

final class _SynchronizationRecoveryDialogState
    extends State<SynchronizationRecoveryDialog> {
  bool _busy = false;
  String? _message;
  SyncRecoveryInspection? _inspection;

  @override
  void initState() {
    super.initState();
    _inspect();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on AuthenticationSyncException {
      if (mounted) {
        setState(
          () => _message =
              'Sign in with the original account, then reopen this home. Saved work remains on this device.',
        );
      }
    } on BindingSyncException {
      if (mounted) {
        setState(
          () => _message =
              'The original account or device binding does not match. Saved operations have not been reassigned or sent. Restore the original session or request recovery review.',
        );
      }
    } on Exception {
      if (mounted) {
        setState(
          () => _message =
              'Recovery could not be verified. Saved work remains preserved. Check your connection, sign in with the original account, and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inspect() => _run(() async {
    final inspection = await widget.recovery.inspectRecovery(widget.homeId);
    if (mounted) setState(() => _inspection = inspection);
  });

  Future<void> _recover({required bool rebuild}) => _run(() async {
    final outcome = rebuild
        ? await widget.recovery.rebuildSavedHome(widget.homeId)
        : await widget.recovery.revalidateSavedOperations(widget.homeId);
    if (!mounted) return;
    setState(() => _message = outcome.message);
    final inspection = await widget.recovery.inspectRecovery(widget.homeId);
    if (mounted) setState(() => _inspection = inspection);
  });

  @override
  Widget build(BuildContext context) {
    final inspection = _inspection;
    return AlertDialog(
      title: const Text('Recover this home'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Refresh server-saved products, receipts and stock in this existing home. Pending work stays protected in this device’s encrypted database with its original account, home, device, operation IDs and order.',
              ),
              const SizedBox(height: 12),
              const Text(
                'A server export does not include unsynchronized local work. Do not clear storage, create another home or re-enter purchases as a recovery step. Work already deleted from this device cannot be reconstructed here.',
              ),
              if (inspection != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${inspection.saved.unresolved} saved operation(s) await synchronization or review; ${inspection.saved.blocked} are blocked.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Verified backend revision: ${inspection.diagnostics.buildRevision ?? 'unavailable'}',
                ),
                Text('Contract: ${inspection.diagnostics.contractHash}'),
                Text(
                  'Migrations: ${inspection.diagnostics.migrationStatus}; contract lock ${inspection.diagnostics.contractMatchesLock ? 'matches' : 'does not match'}.',
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, key: const Key('sync-recovery-result')),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: _busy ? null : _inspect,
          child: const Text('Verify session'),
        ),
        TextButton(
          onPressed: _busy || inspection == null
              ? null
              : () => _recover(rebuild: false),
          child: const Text('Review blocked work'),
        ),
        FilledButton(
          onPressed: _busy || inspection == null
              ? null
              : () => _recover(rebuild: true),
          child: const Text('Refresh saved records'),
        ),
      ],
    );
  }
}
