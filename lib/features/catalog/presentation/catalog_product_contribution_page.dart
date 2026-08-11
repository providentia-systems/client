import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/catalog/application/catalog_product_contribution_controller.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/presentation/catalog_proposal_panel.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

final class CatalogProductContributionPage extends StatefulWidget {
  const CatalogProductContributionPage({
    required this.controller,
    required this.inventoryController,
    super.key,
  });

  final CatalogProductContributionController controller;
  final InventoryController inventoryController;

  @override
  State<CatalogProductContributionPage> createState() =>
      _CatalogProductContributionPageState();
}

final class _CatalogProductContributionPageState
    extends State<CatalogProductContributionPage> {
  @override
  void initState() {
    super.initState();
    widget.inventoryController.start();
    widget.inventoryController.addListener(_reconcileInventory);
    unawaited(widget.controller.loadConsent());
  }

  void _reconcileInventory() {
    widget.controller.reconcileAvailableProductIds(
      _items.map((item) => item.id).toSet(),
    );
  }

  List<InventoryItem> get _items => widget.inventoryController.state.items
      .where(
        (item) => item.homeId == widget.controller.homeId && item.isHomeProduct,
      )
      .toList(growable: false);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Contribute a product')),
    body: ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.controller,
        widget.inventoryController,
      ]),
      builder: (context, _) => _buildBody(context),
    ),
  );

  Widget _buildBody(BuildContext context) {
    final controller = widget.controller;
    return switch (controller.status) {
      CatalogProductContributionStatus.idle ||
      CatalogProductContributionStatus.loading => const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Checking product-identity sharing consent',
        ),
      ),
      CatalogProductContributionStatus.consentRequired => _ContributionState(
        icon: Icons.policy_outlined,
        title: 'Product-identity sharing is off',
        detail:
            'Enable Product identity in Catalog sharing before selecting an '
            'item. Changing that setting will not submit anything.',
        actionLabel: 'Check consent again',
        onAction: controller.loadConsent,
      ),
      CatalogProductContributionStatus.authenticationRequired =>
        const _ContributionState(
          icon: Icons.lock_clock_outlined,
          title: 'Sign in again',
          detail: 'Your session ended before the contribution was submitted.',
        ),
      CatalogProductContributionStatus.forbidden => const _ContributionState(
        icon: Icons.lock_outline,
        title: 'Contribution permission required',
        detail: 'Your current home role cannot contribute catalog products.',
      ),
      CatalogProductContributionStatus.conflict => _ContributionState(
        icon: Icons.sync_problem_outlined,
        title: 'Catalog contribution changed elsewhere',
        detail: 'Nothing was submitted. Check current consent and try again.',
        actionLabel: 'Reload consent',
        onAction: controller.loadConsent,
      ),
      CatalogProductContributionStatus.offline => _ContributionState(
        icon: Icons.cloud_off_outlined,
        title: 'Catalog contribution unavailable offline',
        detail: 'Nothing was submitted. Reconnect before trying again.',
        actionLabel: 'Try again',
        onAction: controller.loadConsent,
      ),
      CatalogProductContributionStatus.failure => _ContributionState(
        icon: Icons.error_outline,
        title: 'Catalog contribution unavailable',
        detail: 'Nothing was submitted. Review the item and try again.',
        actionLabel: 'Try again',
        onAction: controller.loadConsent,
      ),
      CatalogProductContributionStatus.submitted => _Submitted(
        onAnother: controller.contributeAnother,
      ),
      CatalogProductContributionStatus.ready ||
      CatalogProductContributionStatus.submitting => _ContributionForm(
        controller: controller,
        items: _items,
        inventoryLoading: widget.inventoryController.state.loading,
      ),
    };
  }

  @override
  void dispose() {
    widget.inventoryController.removeListener(_reconcileInventory);
    super.dispose();
  }
}

final class _ContributionForm extends StatelessWidget {
  const _ContributionForm({
    required this.controller,
    required this.items,
    required this.inventoryLoading,
  });

  final CatalogProductContributionController controller;
  final List<InventoryItem> items;
  final bool inventoryLoading;

  @override
  Widget build(BuildContext context) {
    final selectedId = controller.product?.homeProductId;
    final selectedExists = items.any((item) => item.id == selectedId);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Choose one inventory item',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Server product-identity consent is active at revision '
          '${controller.serverConsent?.revision}. Selecting an item does not '
          'submit it.',
          key: const Key('catalog-contribution-server-consent'),
        ),
        const SizedBox(height: 16),
        if (inventoryLoading)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading inventory products',
          )
        else if (items.isEmpty)
          const Text('No active-home inventory items are available.')
        else
          DropdownButtonFormField<String>(
            key: const Key('catalog-contribution-product'),
            initialValue: selectedExists ? selectedId : null,
            decoration: const InputDecoration(labelText: 'Inventory item'),
            items: items
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.id,
                    child: Text('${item.canonicalName} · ${item.packSize}'),
                  ),
                )
                .toList(growable: false),
            onChanged:
                controller.status == CatalogProductContributionStatus.submitting
                ? null
                : (id) {
                    if (id == null) return;
                    final item = items.firstWhere(
                      (candidate) => candidate.id == id,
                    );
                    controller.selectProduct(
                      privateProductIdentityPreview(item),
                    );
                  },
          ),
        if (controller.proposal case final proposal?) ...<Widget>[
          const SizedBox(height: 16),
          CatalogProposalPanel(
            proposal: proposal,
            consented: controller.explicitlyConsented,
            enabled:
                controller.status == CatalogProductContributionStatus.ready,
            onConsentChanged: controller.setExplicitConsent,
            onSubmit: () => unawaited(controller.submit()),
          ),
        ],
      ],
    );
  }
}

/// Exact bridge from private inventory state into the catalog allowlist.
///
/// The home and local product identifiers remain endpoint-scoping values on
/// [PrivateProduct]. They are excluded by the proposal wire serializer.
/// Quantity, unit, aliases, notes, receipts, media, and AI data are not mapped.
@visibleForTesting
PrivateProduct privateProductIdentityPreview(InventoryItem item) =>
    PrivateProduct(
      homeId: item.homeId,
      homeProductId: item.id,
      displayName: item.canonicalName,
      brand: item.brand.trim().isEmpty ? null : item.brand.trim(),
      packText: item.packSize,
      categoryLabel: item.category,
    );

final class _Submitted extends StatelessWidget {
  const _Submitted({required this.onAnother});

  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.check_circle_outline, size: 52),
          const SizedBox(height: 12),
          Text(
            'Submitted for catalog review',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Only the displayed product-identity fields were submitted. Your '
            'inventory and quantity were not changed.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('contribute-another-product'),
            onPressed: onAnother,
            child: const Text('Contribute another item'),
          ),
        ],
      ),
    ),
  );
}

final class _ContributionState extends StatelessWidget {
  const _ContributionState({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final Future<void> Function()? onAction;

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
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => unawaited(onAction!()),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
