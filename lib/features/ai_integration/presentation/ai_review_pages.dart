import 'package:flutter/material.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/presentation/ai_controllers.dart';

final class AiPrivacyConsentCard extends StatelessWidget {
  const AiPrivacyConsentCard({required this.controller, super.key});

  final AiConsentController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final provider = controller.provider;
        final disclosure = switch (controller.privacyMode) {
          AiPrivacyMode.serverProxyCloud =>
            'A sanitized copy leaves this device, passes through Providentia '
                'without being stored by Providentia, and is sent to '
                '${provider.displayName}. Provider retention terms still apply.',
          AiPrivacyMode.strictLocal =>
            'Processing uses your attested local or self-hosted endpoint. '
                'No cloud provider is selected.',
          AiPrivacyMode.directCloudAdvanced =>
            'Direct cloud credentials are disabled. Use the secure server connection.',
        };
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Review privacy before sending',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(disclosure),
                const SizedBox(height: 8),
                const Text(
                  'The original stays on this device. Only the sanitized '
                  'preview shown here is eligible for processing.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I confirm this provider, privacy route, and media',
                  ),
                  value: controller.isConfirmed,
                  onChanged:
                      controller.privacyMode ==
                          AiPrivacyMode.directCloudAdvanced
                      ? null
                      : (value) {
                          if (value ?? false) {
                            controller.confirm();
                          } else {
                            controller.revoke();
                          }
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class AiProviderSettingsPanel extends StatelessWidget {
  const AiProviderSettingsPanel({
    required this.profiles,
    this.onConfigure,
    super.key,
  });

  final List<AiProviderProfile> profiles;
  final ValueChanged<AiProviderProfile>? onConfigure;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'AI is off. Configure a provider before using receipt or stock-photo extraction.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: profiles.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final route = switch (profile.transport) {
          AiTransport.serverProxy =>
            'Secure server proxy · provider key is not stored on this device',
          AiTransport.directNative =>
            'Direct local/self-hosted · native secure vault when required',
        };
        return Card(
          child: ListTile(
            title: Text(profile.displayName),
            subtitle: Text('${profile.model}\n$route'),
            isThreeLine: true,
            trailing: Icon(
              profile.availability == AiProviderAvailability.available &&
                      profile.enabled
                  ? Icons.verified_outlined
                  : Icons.warning_amber_rounded,
            ),
            onTap: onConfigure == null ? null : () => onConfigure!(profile),
          ),
        );
      },
    );
  }
}

final class ReceiptProposalReviewPage extends StatelessWidget {
  const ReceiptProposalReviewPage({
    required this.controller,
    this.catalogSearch,
    super.key,
  });

  final ReceiptReviewController controller;
  final Widget? catalogSearch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review receipt')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final proposal = controller.proposal;
          if (proposal.requiresQuarantine ||
              proposal.classification ==
                  ReceiptDocumentClassification.unknown) {
            return const _QuarantineNotice(
              title: 'This is not an eligible receipt',
              message:
                  'The image was classified as medical, unrelated, or unknown. '
                  'It cannot create products, prices, or stock movements.',
            );
          }
          return SafeArea(
            child: Column(
              children: <Widget>[
                if (catalogSearch != null) catalogSearch!,
                _ReceiptHeaderCard(header: proposal.header),
                Expanded(
                  child: ListView.builder(
                    key: const Key('receipt-proposal-lines'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: proposal.lines.length,
                    itemBuilder: (context, index) {
                      final line = proposal.lines[index];
                      final selected = controller.selectedLineIds.contains(
                        line.lineId,
                      );
                      return _ReceiptLineCard(
                        line: line,
                        selected: selected,
                        onUsePrivateProduct: () {
                          controller.resolveLine(
                            line: line,
                            resolution: CatalogResolution(
                              kind: CatalogResolutionKind.privateProduct,
                              privateProductName:
                                  line.productName.value ?? line.rawText,
                            ),
                            quantity: line.quantity.value ?? 1,
                            unitPrice: line.unitPrice.value,
                            lineTotal: line.lineTotal.value,
                          );
                        },
                        onRemove: () => controller.removeLine(line.lineId),
                      );
                    },
                  ),
                ),
                _ApprovalBar(
                  primaryLabel: controller.isCommitted
                      ? 'Receipt committed'
                      : 'Approve selected lines',
                  busy: controller.isApproving,
                  enabled: controller.canApprove,
                  safeError: controller.safeError,
                  onPressed: controller.approve,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

final class StockPhotoReviewPage extends StatelessWidget {
  const StockPhotoReviewPage({
    required this.controller,
    required this.mediaPreview,
    this.catalogSearch,
    super.key,
  });

  final StockPhotoReviewController controller;
  final Widget mediaPreview;
  final Widget? catalogSearch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review stock photo')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final proposal = controller.proposal;
          if (proposal.requiresQuarantine ||
              proposal.classification == StockImageClassification.unknown) {
            return const _QuarantineNotice(
              title: 'This image cannot be counted',
              message:
                  'Medical, unrelated, or unknown images are quarantined and '
                  'cannot change stock.',
            );
          }
          final unconfirmed = proposal.candidates
              .where(
                (candidate) => !controller.confirmedCandidateIds.contains(
                  candidate.candidateId,
                ),
              )
              .toList(growable: false);
          final confirmed = proposal.candidates
              .where(
                (candidate) => controller.confirmedCandidateIds.contains(
                  candidate.candidateId,
                ),
              )
              .toList(growable: false);
          return SafeArea(
            child: Column(
              children: <Widget>[
                Semantics(
                  label: 'Selected stock photo remains visible during review',
                  image: true,
                  child: SizedBox(
                    key: const Key('stock-media-preview'),
                    height: 180,
                    width: double.infinity,
                    child: mediaPreview,
                  ),
                ),
                if (catalogSearch != null) catalogSearch!,
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    children: <Widget>[
                      Text(
                        'Suggestions to review',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (unconfirmed.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No unconfirmed suggestions.'),
                        ),
                      for (final candidate in unconfirmed)
                        _StockCandidateCard(
                          candidate: candidate,
                          confirmed: false,
                          onToggle: () {
                            controller.confirmCandidate(
                              candidate: candidate,
                              resolution: CatalogResolution(
                                kind: CatalogResolutionKind.privateProduct,
                                privateProductName:
                                    candidate.productName.value ??
                                    'Private household item',
                              ),
                              quantity: candidate.quantityMinimum,
                            );
                          },
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Confirmed',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (confirmed.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Confirmed items will move below.'),
                        ),
                      for (final candidate in confirmed)
                        _StockCandidateCard(
                          candidate: candidate,
                          confirmed: true,
                          onToggle: () => controller.unconfirmCandidate(
                            candidate.candidateId,
                          ),
                        ),
                    ],
                  ),
                ),
                _ApprovalBar(
                  primaryLabel: controller.isCommitted
                      ? 'Count closed'
                      : 'Review variance and close count',
                  busy: controller.isClosing,
                  enabled: controller.canClose,
                  safeError: controller.safeError,
                  onPressed: controller.close,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

final class _ReceiptHeaderCard extends StatelessWidget {
  const _ReceiptHeaderCard({required this.header});

  final ReceiptHeaderProposal header;

  @override
  Widget build(BuildContext context) {
    final store = header.storeName.value ?? 'Store needs review';
    final total = header.total.value;
    final currency = header.currency.value ?? '';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(store),
        subtitle: Text(
          <String>[
            if (header.purchaseDate.value != null) header.purchaseDate.value!,
            if (total != null) '$currency $total'.trim(),
          ].join(' · '),
        ),
      ),
    );
  }
}

final class _ReceiptLineCard extends StatelessWidget {
  const _ReceiptLineCard({
    required this.line,
    required this.selected,
    required this.onUsePrivateProduct,
    required this.onRemove,
  });

  final ReceiptLineProposal line;
  final bool selected;
  final VoidCallback onUsePrivateProduct;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = line.productName.value ?? line.rawText;
    final lowConfidence = line.confidence < 0.7;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (lowConfidence)
                  const Tooltip(
                    message: 'Low confidence — check every field',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      semanticLabel: 'Low confidence',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(line.rawText),
            if (line.warnings.isNotEmpty) Text(line.warnings.join(' · ')),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: selected
                  ? TextButton.icon(
                      onPressed: onRemove,
                      icon: const Icon(Icons.undo),
                      label: const Text('Return to review'),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: onUsePrivateProduct,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Use as private product'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _StockCandidateCard extends StatelessWidget {
  const _StockCandidateCard({
    required this.candidate,
    required this.confirmed,
    required this.onToggle,
  });

  final StockCandidateProposal candidate;
  final bool confirmed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final name = candidate.productName.value ?? 'Unidentified item';
    final quantity = candidate.quantityMinimum == candidate.quantityMaximum
        ? '${candidate.quantityMinimum}'
        : '${candidate.quantityMinimum}–${candidate.quantityMaximum}';
    return Card(
      child: ListTile(
        leading: Icon(
          confirmed ? Icons.check_circle_outline : Icons.help_outline,
        ),
        title: Text(name),
        subtitle: Text(
          'Visible quantity: $quantity'
          '${candidate.warnings.isEmpty ? '' : '\n${candidate.warnings.join(' · ')}'}',
        ),
        isThreeLine: candidate.warnings.isNotEmpty,
        trailing: TextButton(
          onPressed: onToggle,
          child: Text(confirmed ? 'Correct' : 'Confirm privately'),
        ),
      ),
    );
  }
}

final class _ApprovalBar extends StatelessWidget {
  const _ApprovalBar({
    required this.primaryLabel,
    required this.busy,
    required this.enabled,
    required this.safeError,
    required this.onPressed,
  });

  final String primaryLabel;
  final bool busy;
  final bool enabled;
  final String? safeError;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (safeError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  safeError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: enabled && !busy ? onPressed : null,
              child: busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(primaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

final class _QuarantineNotice extends StatelessWidget {
  const _QuarantineNotice({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.health_and_safety_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
