import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/catalog/application/catalog_sharing_controller.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';

final class CatalogSharingPage extends StatefulWidget {
  const CatalogSharingPage({required this.controller, super.key});

  final CatalogSharingController controller;

  @override
  State<CatalogSharingPage> createState() => _CatalogSharingPageState();
}

final class _CatalogSharingPageState extends State<CatalogSharingPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalog sharing')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final consent = controller.consent;
          if (consent != null) {
            return _ConsentForm(controller: controller, consent: consent);
          }
          return switch (controller.status) {
            CatalogSharingStatus.idle ||
            CatalogSharingStatus.loading => const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading catalog-sharing choices',
              ),
            ),
            CatalogSharingStatus.authenticationRequired => const _SafeState(
              icon: Icons.lock_clock_outlined,
              title: 'Sign in again',
              detail: 'Your session ended before these choices could load.',
            ),
            CatalogSharingStatus.forbidden => const _SafeState(
              icon: Icons.lock_outline,
              title: 'Catalog-sharing permission required',
              detail: 'Your current home role cannot view these choices.',
            ),
            CatalogSharingStatus.conflict => _SafeState(
              icon: Icons.sync_problem_outlined,
              title: 'Choices changed elsewhere',
              detail: 'Reload the latest revision before changing consent.',
              onRetry: controller.load,
            ),
            CatalogSharingStatus.offline => _SafeState(
              icon: Icons.cloud_off_outlined,
              title: 'Catalog choices unavailable offline',
              detail: 'Your saved choices were not changed. Try again online.',
              onRetry: controller.load,
            ),
            CatalogSharingStatus.failure ||
            CatalogSharingStatus.saving ||
            CatalogSharingStatus.ready => _SafeState(
              icon: Icons.error_outline,
              title: 'Catalog choices unavailable',
              detail: 'No sharing choice was changed. Try again.',
              onRetry: controller.load,
            ),
          };
        },
      ),
    );
  }
}

final class _ConsentForm extends StatelessWidget {
  const _ConsentForm({required this.controller, required this.consent});

  final CatalogSharingController controller;
  final CatalogSharingConsent consent;

  @override
  Widget build(BuildContext context) {
    final enabled =
        controller.mayEdit && controller.status != CatalogSharingStatus.saving;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Choose each category separately',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Turning on a category does not submit an item. Sharing happens only '
          'after a separate, explicit contribution action.',
          key: Key('catalog-sharing-explicit-notice'),
        ),
        const SizedBox(height: 8),
        Text(
          'Notice ${CatalogSharingConsent.currentNoticeVersion} · revision ${consent.revision}',
          key: const Key('catalog-sharing-revision'),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const Key('share-product-identity'),
          title: const Text('Product identity'),
          subtitle: const Text(
            'Canonical name and approved identity fields only',
          ),
          value: consent.shareProductIdentity,
          onChanged: enabled ? controller.setProductIdentity : null,
        ),
        SwitchListTile(
          key: const Key('share-public-images'),
          title: const Text('Public product images'),
          subtitle: const Text('Images selected for public catalog use only'),
          value: consent.shareProductImages,
          onChanged: enabled ? controller.setProductImages : null,
        ),
        SwitchListTile(
          key: const Key('share-store-prices'),
          title: const Text('Store price observations'),
          subtitle: const Text('Store and observed price fields only'),
          value: consent.shareStorePrices,
          onChanged: enabled ? controller.setStorePrices : null,
        ),
        const SizedBox(height: 12),
        const Text(
          'Home identity, household stock, quantities, receipts, private notes, '
          'and AI metadata are never included in a catalog review.',
        ),
        if (!controller.mayEdit) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            'You can contribute when enabled, but only a home role with catalog '
            'consent permission can change these choices.',
            key: Key('catalog-sharing-read-only'),
          ),
        ],
        if (controller.status == CatalogSharingStatus.saving) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(
            semanticsLabel: 'Saving catalog-sharing choice',
          ),
        ],
      ],
    );
  }
}

final class _SafeState extends StatelessWidget {
  const _SafeState({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => unawaited(onRetry!()),
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
