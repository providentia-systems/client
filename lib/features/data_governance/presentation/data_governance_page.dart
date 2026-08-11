import 'package:flutter/material.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';
import 'package:providentia/features/data_governance/presentation/data_governance_controller.dart';

final class DataGovernancePage extends StatefulWidget {
  const DataGovernancePage({required this.controller, super.key});

  final DataGovernanceController controller;

  @override
  State<DataGovernancePage> createState() => _DataGovernancePageState();
}

final class _DataGovernancePageState extends State<DataGovernancePage> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your data')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, child) {
          final controller = widget.controller;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              const Text(
                'Exports and erasure requests',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Exports are prepared asynchronously. Erasure requests require '
                'an explicit confirmation and may retain legally required data.',
              ),
              if (controller.status == DataGovernanceViewStatus.loading ||
                  controller.status ==
                      DataGovernanceViewStatus.submitting) ...<Widget>[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (controller.notice != DataGovernanceNotice.none) ...<Widget>[
                const SizedBox(height: 16),
                _NoticeCard(notice: controller.notice),
              ],
              const SizedBox(height: 24),
              _scopeSection(
                context,
                title: 'Account',
                requests: controller.accountRequests,
                exportCapability: DataGovernanceCapability.accountExport,
                erasureCapability: DataGovernanceCapability.accountErasure,
                cancelCapability: DataGovernanceCapability.cancelAccountRequest,
                onExport: controller.requestAccountExport,
                onErase: controller.requestAccountErasure,
              ),
              if (controller.capabilities.allows(
                    DataGovernanceCapability.homeRequestsRead,
                  ) ||
                  controller.capabilities.allows(
                    DataGovernanceCapability.homeExport,
                  ) ||
                  controller.capabilities.allows(
                    DataGovernanceCapability.homeErasure,
                  )) ...<Widget>[
                const SizedBox(height: 24),
                _scopeSection(
                  context,
                  title: 'Selected home',
                  requests: controller.homeRequests,
                  exportCapability: DataGovernanceCapability.homeExport,
                  erasureCapability: DataGovernanceCapability.homeErasure,
                  cancelCapability: DataGovernanceCapability.cancelHomeRequest,
                  onExport: controller.requestHomeExport,
                  onErase: controller.requestHomeErasure,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _scopeSection(
    BuildContext context, {
    required String title,
    required List<DataGovernanceRequest> requests,
    required DataGovernanceCapability exportCapability,
    required DataGovernanceCapability erasureCapability,
    required DataGovernanceCapability cancelCapability,
    required Future<void> Function() onExport,
    required Future<void> Function(ErasureConfirmation) onErase,
  }) {
    final capabilities = widget.controller.capabilities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (capabilities.allows(exportCapability))
              FilledButton.tonalIcon(
                key: Key('${title.toLowerCase().replaceAll(' ', '-')}-export'),
                onPressed: onExport,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Request export'),
              ),
            if (capabilities.allows(erasureCapability))
              OutlinedButton.icon(
                key: Key('${title.toLowerCase().replaceAll(' ', '-')}-erase'),
                onPressed: () => _confirmErasure(context, onErase),
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Request erasure'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (requests.isEmpty)
          const Text('No requests yet.')
        else
          ...requests.map(
            (request) => _RequestCard(
              request: request,
              canCancel:
                  request.canBeCancelled &&
                  capabilities.allows(cancelCapability),
              onCancel: () => widget.controller.cancel(request),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmErasure(
    BuildContext context,
    Future<void> Function(ErasureConfirmation) command,
  ) async {
    final confirmation = await showDialog<ErasureConfirmation>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ErasureConfirmationDialog(),
    );
    if (confirmation != null && mounted) {
      await command(confirmation);
    }
  }
}

final class _ErasureConfirmationDialog extends StatefulWidget {
  const _ErasureConfirmationDialog();

  @override
  State<_ErasureConfirmationDialog> createState() =>
      _ErasureConfirmationDialogState();
}

final class _ErasureConfirmationDialogState
    extends State<_ErasureConfirmationDialog> {
  final TextEditingController _textController = TextEditingController();
  ErasureConfirmation? _confirmation;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm erasure request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'This may permanently remove data. Type ERASE exactly to continue.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('erasure-confirmation-input'),
            controller: _textController,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (value) {
              setState(() {
                _confirmation = ErasureConfirmation.tryCreate(value);
              });
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-erasure'),
          onPressed: _confirmation == null
              ? null
              : () => Navigator.of(context).pop(_confirmation),
          child: const Text('Submit erasure request'),
        ),
      ],
    );
  }
}

final class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.canCancel,
    required this.onCancel,
  });

  final DataGovernanceRequest request;
  final bool canCancel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('data-request-${request.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(_kindLabel(request.kind)),
            Text('Status: ${request.status.name}'),
            if (request.retainedDataDisclosure.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text('Retained-data disclosure'),
              ...request.retainedDataDisclosure.map(
                (item) => Text(
                  '${item.category}: ${item.treatment} — ${item.reason}',
                ),
              ),
            ],
            if (canCancel)
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancel request'),
              ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(DataGovernanceRequestKind kind) => switch (kind) {
    DataGovernanceRequestKind.accountExport => 'Account export',
    DataGovernanceRequestKind.accountErasure => 'Account erasure',
    DataGovernanceRequestKind.homeExport => 'Home export',
    DataGovernanceRequestKind.homeErasure => 'Home erasure',
  };
}

final class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final DataGovernanceNotice notice;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('data-governance-notice'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_message(notice)),
      ),
    );
  }

  String _message(DataGovernanceNotice notice) => switch (notice) {
    DataGovernanceNotice.none => '',
    DataGovernanceNotice.requestQueued => 'Your request has been queued.',
    DataGovernanceNotice.requestCancelled => 'The request was cancelled.',
    DataGovernanceNotice.authenticationRequired =>
      'Sign in again to manage your data requests.',
    DataGovernanceNotice.forbidden =>
      'You do not have permission for this data request.',
    DataGovernanceNotice.conflict =>
      'This request changed. Refresh and try again.',
    DataGovernanceNotice.invalidRequest => 'The request could not be accepted.',
    DataGovernanceNotice.invalidResponse || DataGovernanceNotice.unavailable =>
      'Data requests are temporarily unavailable.',
  };
}
