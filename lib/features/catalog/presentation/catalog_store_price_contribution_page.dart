import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:providentia/features/catalog/application/catalog_store_price_contribution_controller.dart';
import 'package:providentia/features/catalog/domain/catalog_store_price_models.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

final class CatalogStorePriceContributionPage extends StatefulWidget {
  const CatalogStorePriceContributionPage({
    required this.controller,
    required this.inventoryController,
    required this.defaultCurrency,
    super.key,
  });

  final CatalogStorePriceContributionController controller;
  final InventoryController inventoryController;
  final String defaultCurrency;

  @override
  State<CatalogStorePriceContributionPage> createState() =>
      _CatalogStorePriceContributionPageState();
}

final class _CatalogStorePriceContributionPageState
    extends State<CatalogStorePriceContributionPage> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _storeName = TextEditingController();
  final TextEditingController _storeLocation = TextEditingController();
  final TextEditingController _price = TextEditingController();
  late final TextEditingController _currency;
  late DateTime _observedOn;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _currency = TextEditingController(
      text: widget.defaultCurrency.trim().toUpperCase(),
    );
    final now = DateTime.now();
    _observedOn = DateTime(now.year, now.month, now.day);
    widget.inventoryController.start();
    widget.inventoryController.addListener(_reconcileInventory);
    widget.controller.addListener(_clearTerminalPrivateInput);
    unawaited(widget.controller.loadConsent());
  }

  List<InventoryItem> get _items => widget.inventoryController.state.items
      .where(
        (item) =>
            item.homeId == widget.controller.homeId &&
            item.isHomeProduct &&
            item.productId != null &&
            item.packId != null,
      )
      .toList(growable: false);

  void _reconcileInventory() {
    widget.controller.reconcileAvailableSourceIds(
      _items.map((item) => item.id).toSet(),
    );
  }

  void _clearTerminalPrivateInput() {
    if (_clearing) return;
    final status = widget.controller.status;
    if (status != CatalogStorePriceContributionStatus.idle &&
        status != CatalogStorePriceContributionStatus.submitted &&
        status != CatalogStorePriceContributionStatus.authenticationRequired &&
        status != CatalogStorePriceContributionStatus.forbidden &&
        status != CatalogStorePriceContributionStatus.sourceUnavailable) {
      return;
    }
    _clearing = true;
    _storeName.clear();
    _storeLocation.clear();
    _price.clear();
    final now = DateTime.now();
    _observedOn = DateTime(now.year, now.month, now.day);
    _clearing = false;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Share a store price')),
    body: ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.controller,
        widget.inventoryController,
      ]),
      builder: (context, _) => _body(context),
    ),
  );

  Widget _body(BuildContext context) {
    final controller = widget.controller;
    return switch (controller.status) {
      CatalogStorePriceContributionStatus.idle ||
      CatalogStorePriceContributionStatus.loading => const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Checking store-price sharing consent',
        ),
      ),
      CatalogStorePriceContributionStatus.consentRequired => _StorePriceState(
        icon: Icons.policy_outlined,
        title: 'Store-price sharing is off',
        detail:
            'Enable Store price observations in Catalog sharing first. '
            'Changing that setting never submits a price.',
        actionLabel: 'Check consent again',
        onAction: controller.loadConsent,
      ),
      CatalogStorePriceContributionStatus.authenticationRequired =>
        const _StorePriceState(
          icon: Icons.lock_clock_outlined,
          title: 'Sign in again',
          detail: 'Your session ended before this price was submitted.',
        ),
      CatalogStorePriceContributionStatus.forbidden => const _StorePriceState(
        icon: Icons.lock_outline,
        title: 'Contribution permission required',
        detail: 'Your current home role cannot share catalog prices.',
      ),
      CatalogStorePriceContributionStatus.sourceUnavailable => _StorePriceState(
        icon: Icons.inventory_2_outlined,
        title: 'Choose the product again',
        detail:
            'The selected home product is no longer eligible. No price was '
            'submitted.',
        actionLabel: 'Reload consent',
        onAction: controller.loadConsent,
      ),
      CatalogStorePriceContributionStatus.conflict => _StorePriceState(
        icon: Icons.sync_problem_outlined,
        title: 'Contribution changed elsewhere',
        detail:
            'No changed payload was retried. Reload consent and review the '
            'price again.',
        actionLabel: 'Reload consent',
        onAction: controller.loadConsent,
      ),
      CatalogStorePriceContributionStatus.offline => _StorePriceState(
        icon: Icons.cloud_off_outlined,
        title: 'Store-price contribution unavailable offline',
        detail:
            'The exact submission intent is retained for an idempotent retry.',
        actionLabel: 'Try again',
        onAction: controller.loadConsent,
      ),
      CatalogStorePriceContributionStatus.failure => _StorePriceState(
        icon: Icons.error_outline,
        title: 'Store price could not be submitted',
        detail: 'Review every shared field before trying again.',
        actionLabel: 'Reload consent',
        onAction: controller.loadConsent,
      ),
      CatalogStorePriceContributionStatus.submitted => _StorePriceSubmitted(
        onAnother: controller.contributeAnother,
      ),
      CatalogStorePriceContributionStatus.ready ||
      CatalogStorePriceContributionStatus.submitting => _formContent(context),
    };
  }

  Widget _formContent(BuildContext context) {
    final controller = widget.controller;
    final busy =
        controller.status == CatalogStorePriceContributionStatus.submitting;
    final selectedId = controller.source?.homeProductId;
    final selectedExists = _items.any((item) => item.id == selectedId);
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'Review one public price observation',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Store-price consent is active at revision '
            '${controller.serverConsent?.revision}. Nothing is shared until '
            'you review the exact fields and confirm.',
            key: const Key('store-price-server-consent'),
          ),
          const SizedBox(height: 16),
          if (widget.inventoryController.state.loading)
            const LinearProgressIndicator(
              semanticsLabel: 'Loading catalog-linked products',
            )
          else if (_items.isEmpty)
            const Text(
              'No active home product is linked to a published catalog pack. '
              'Private-only items stay private and cannot report a global price.',
            )
          else
            DropdownButtonFormField<String>(
              key: const Key('store-price-product'),
              initialValue: selectedExists ? selectedId : null,
              decoration: const InputDecoration(labelText: 'Product and pack'),
              items: _items
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text('${item.canonicalName} · ${item.packSize}'),
                    ),
                  )
                  .toList(growable: false),
              validator: (value) => value == null ? 'Choose a product.' : null,
              onChanged: busy
                  ? null
                  : (id) {
                      if (id == null) return;
                      controller.selectSource(
                        catalogStorePriceSourcePreview(
                          _items.firstWhere((item) => item.id == id),
                        ),
                      );
                    },
            ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('store-price-store-name'),
            controller: _storeName,
            enabled: !busy,
            maxLength: 191,
            decoration: const InputDecoration(labelText: 'Store name'),
            validator: (value) => _required(value, 'Enter the store name.'),
            onChanged: (_) => _discardChangedPreview(),
          ),
          TextFormField(
            key: const Key('store-price-store-location'),
            controller: _storeLocation,
            enabled: !busy,
            maxLength: 191,
            decoration: const InputDecoration(
              labelText: 'Store location (optional)',
            ),
            onChanged: (_) => _discardChangedPreview(),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: const Key('store-price-price'),
                  controller: _price,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(labelText: 'Pack price'),
                  validator: (value) =>
                      RegExp(
                        r'^(?:0|[1-9][0-9]{0,11})\.[0-9]{2,4}$',
                      ).hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Use a decimal price with 2 to 4 digits after the point.',
                  onChanged: (_) => _discardChangedPreview(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const Key('store-price-currency'),
                  controller: _currency,
                  enabled: !busy,
                  maxLength: 3,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                  ],
                  decoration: const InputDecoration(labelText: 'Currency'),
                  validator: (value) =>
                      RegExp(r'^[A-Za-z]{3}$').hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Use 3 letters.',
                  onChanged: (_) => _discardChangedPreview(),
                ),
              ),
            ],
          ),
          ListTile(
            key: const Key('store-price-observed-on'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Observed on'),
            subtitle: Text(_date(_observedOn)),
            trailing: const Icon(Icons.calendar_month_outlined),
            onTap: busy ? null : _chooseDate,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('store-price-review'),
            onPressed: busy ? null : _review,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review shared fields'),
          ),
          if (controller.observation case final observation?) ...<Widget>[
            const SizedBox(height: 20),
            _StorePricePreview(observation: observation),
            CheckboxListTile(
              key: const Key('store-price-explicit-checkbox'),
              value: controller.explicitlyConsented,
              onChanged: busy
                  ? null
                  : (value) => controller.setExplicitConsent(value ?? false),
              title: const Text(
                'Share exactly this product, pack, store, location, price, '
                'currency, and date for public catalog review.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            FilledButton.icon(
              key: const Key('submit-store-price-contribution'),
              onPressed: controller.maySubmit && !busy
                  ? () => unawaited(controller.submit())
                  : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(busy ? 'Submitting' : 'Submit store price'),
            ),
          ],
        ],
      ),
    );
  }

  void _discardChangedPreview() {
    if (!_clearing && widget.controller.observation != null) {
      widget.controller.discardPreview();
    }
  }

  void _review() {
    if (!(_form.currentState?.validate() ?? false)) return;
    widget.controller.preview(
      storeName: _storeName.text,
      storeLocation: _storeLocation.text,
      price: _price.text,
      currency: _currency.text,
      observedOn: _observedOn,
    );
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _observedOn,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (selected == null || !mounted) return;
    setState(() => _observedOn = selected);
    _discardChangedPreview();
  }

  @override
  void dispose() {
    widget.inventoryController.removeListener(_reconcileInventory);
    widget.controller.removeListener(_clearTerminalPrivateInput);
    _storeName.dispose();
    _storeLocation.dispose();
    _price.dispose();
    _currency.dispose();
    super.dispose();
  }
}

CatalogStorePriceSource catalogStorePriceSourcePreview(InventoryItem item) {
  final productId = item.productId;
  final packId = item.packId;
  if (!item.isHomeProduct || productId == null || packId == null) {
    throw ArgumentError('Choose a home product linked to a catalog pack.');
  }
  return CatalogStorePriceSource(
    homeId: item.homeId,
    homeProductId: item.id,
    productId: productId,
    packId: packId,
    displayName: item.canonicalName,
    packText: item.packSize,
  );
}

final class _StorePricePreview extends StatelessWidget {
  const _StorePricePreview({required this.observation});

  final CatalogStorePriceObservation observation;

  @override
  Widget build(BuildContext context) {
    final payload = observation.toPayloadJson();
    return Card(
      key: const Key('store-price-preview'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Exact public review payload',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Product: ${observation.source.displayName}'),
            Text('Pack: ${observation.source.packText}'),
            Text('Store: ${payload['storeName']}'),
            if (payload['storeLocation'] case final String location)
              Text('Location: $location'),
            Text('Price: ${payload['price']} ${payload['currency']}'),
            Text('Observed: ${payload['observedOn']}'),
            const SizedBox(height: 8),
            const Text(
              'Household identity, user identity, stock quantity, receipts, '
              'notes, and images are not included.',
            ),
          ],
        ),
      ),
    );
  }
}

final class _StorePriceSubmitted extends StatelessWidget {
  const _StorePriceSubmitted({required this.onAnother});

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
            'Store price submitted for review',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'The private form fields were cleared. Only the exact reviewed '
            'public observation was submitted.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('contribute-another-store-price'),
            onPressed: onAnother,
            child: const Text('Share another price'),
          ),
        ],
      ),
    ),
  );
}

final class _StorePriceState extends StatelessWidget {
  const _StorePriceState({
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
        constraints: const BoxConstraints(maxWidth: 540),
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

String? _required(String? value, String message) =>
    value == null || value.trim().isEmpty ? message : null;

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
