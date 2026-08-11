import 'package:flutter/material.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';

final class CatalogProposalPanel extends StatelessWidget {
  const CatalogProposalPanel({
    required this.proposal,
    required this.consented,
    required this.onConsentChanged,
    required this.onSubmit,
    this.enabled = true,
    super.key,
  });

  final SanitizedCatalogProposal proposal;
  final bool consented;
  final ValueChanged<bool> onConsentChanged;
  final VoidCallback onSubmit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final values = proposal.toIdentityContributionJson().entries.toList(
      growable: false,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Sanitized catalog proposal',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Only the fields shown below will be submitted. Household '
              'identity, stock, prices, receipts, notes and media stay private.',
            ),
            const SizedBox(height: 12),
            for (final entry in values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('${entry.key}: ${entry.value}'),
              ),
            const SizedBox(height: 12),
            CheckboxListTile(
              key: const Key('catalog-contribution-explicit-checkbox'),
              contentPadding: EdgeInsets.zero,
              value: consented,
              onChanged: enabled
                  ? (value) {
                      onConsentChanged(value ?? false);
                    }
                  : null,
              title: const Text('Submit this sanitized proposal for review'),
            ),
            FilledButton(
              key: const Key('submit-catalog-contribution'),
              onPressed: enabled && consented ? onSubmit : null,
              child: const Text('Submit proposal'),
            ),
          ],
        ),
      ),
    );
  }
}
