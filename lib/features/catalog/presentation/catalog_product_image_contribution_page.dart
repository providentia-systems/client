import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:providentia/features/catalog/application/catalog_product_image_contribution_controller.dart';
import 'package:providentia/features/catalog/domain/catalog_product_image_models.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';

final class CatalogProductImageAcquisitionActions {
  const CatalogProductImageAcquisitionActions({
    required this.takePhoto,
    required this.chooseGallery,
    required this.chooseFile,
  });

  final CatalogProductImageAcquisition takePhoto;
  final CatalogProductImageAcquisition chooseGallery;
  final CatalogProductImageAcquisition chooseFile;
}

final class CatalogProductImageContributionPage extends StatefulWidget {
  const CatalogProductImageContributionPage({
    required this.controller,
    required this.inventoryController,
    required this.acquisition,
    super.key,
  });

  final CatalogProductImageContributionController controller;
  final InventoryController inventoryController;
  final CatalogProductImageAcquisitionActions acquisition;

  @override
  State<CatalogProductImageContributionPage> createState() =>
      _CatalogProductImageContributionPageState();
}

final class _CatalogProductImageContributionPageState
    extends State<CatalogProductImageContributionPage> {
  final TextEditingController _altText = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.inventoryController.start();
    widget.inventoryController.addListener(_reconcileInventory);
    unawaited(widget.controller.loadConsent());
  }

  List<InventoryItem> get _items => widget.inventoryController.state.items
      .where(
        (item) => item.homeId == widget.controller.homeId && item.isHomeProduct,
      )
      .toList(growable: false);

  void _reconcileInventory() {
    widget.controller.reconcileAvailableSourceIds(
      _items.map((item) => item.id).toSet(),
    );
  }

  Future<void> _acquire(CatalogProductImageAcquisition action) async {
    await widget.controller.acquire(action);
    if (mounted && _altText.text != widget.controller.altText) {
      _altText.text = widget.controller.altText;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Contribute a product image')),
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
      CatalogProductImageContributionStatus.idle ||
      CatalogProductImageContributionStatus.loading => const Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Checking product-image sharing consent',
        ),
      ),
      CatalogProductImageContributionStatus.consentRequired =>
        _ContributionState(
          icon: Icons.policy_outlined,
          title: 'Public product-image sharing is off',
          detail:
              'Enable Public product images in Catalog sharing, then return '
              'and check the current consent revision.',
          actionLabel: 'Check consent again',
          onAction: controller.loadConsent,
        ),
      CatalogProductImageContributionStatus.authenticationRequired =>
        const _ContributionState(
          icon: Icons.lock_clock_outlined,
          title: 'Sign in again',
          detail: 'The selected image was removed when your session ended.',
        ),
      CatalogProductImageContributionStatus.forbidden =>
        const _ContributionState(
          icon: Icons.lock_outline,
          title: 'Contribution permission required',
          detail: 'Your current home role cannot contribute catalog images.',
        ),
      CatalogProductImageContributionStatus.sourceUnavailable =>
        _ContributionState(
          icon: Icons.inventory_2_outlined,
          title: 'Inventory item no longer available',
          detail: 'The private source and selected image were removed.',
          actionLabel: 'Choose another item',
          onAction: () async => controller.loadConsent(),
        ),
      CatalogProductImageContributionStatus.submitted => _Submitted(
        onAnother: controller.contributeAnother,
      ),
      CatalogProductImageContributionStatus.ready ||
      CatalogProductImageContributionStatus.acquiring ||
      CatalogProductImageContributionStatus.submitting ||
      CatalogProductImageContributionStatus.conflict ||
      CatalogProductImageContributionStatus.imageTooLarge ||
      CatalogProductImageContributionStatus.imageUnsupported ||
      CatalogProductImageContributionStatus.imageInvalid ||
      CatalogProductImageContributionStatus.serviceUnavailable ||
      CatalogProductImageContributionStatus.offline ||
      CatalogProductImageContributionStatus.failure => _ContributionForm(
        controller: controller,
        items: _items,
        inventoryLoading: widget.inventoryController.state.loading,
        acquisition: widget.acquisition,
        altTextController: _altText,
        acquire: _acquire,
      ),
    };
  }

  @override
  void dispose() {
    widget.inventoryController.removeListener(_reconcileInventory);
    _altText.dispose();
    super.dispose();
  }
}

final class _ContributionForm extends StatelessWidget {
  const _ContributionForm({
    required this.controller,
    required this.items,
    required this.inventoryLoading,
    required this.acquisition,
    required this.altTextController,
    required this.acquire,
  });

  final CatalogProductImageContributionController controller;
  final List<InventoryItem> items;
  final bool inventoryLoading;
  final CatalogProductImageAcquisitionActions acquisition;
  final TextEditingController altTextController;
  final Future<void> Function(CatalogProductImageAcquisition) acquire;

  @override
  Widget build(BuildContext context) {
    final busy =
        controller.status == CatalogProductImageContributionStatus.acquiring ||
        controller.status == CatalogProductImageContributionStatus.submitting;
    final selectedId = controller.source?.homeProductId;
    final selectedExists = items.any((item) => item.id == selectedId);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Review one image for public reuse',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Product-image sharing is active at consent revision '
          '${controller.serverConsent?.revision}. Nothing is uploaded until '
          'both confirmations are checked and Submit is pressed.',
          key: const Key('catalog-image-consent-revision'),
        ),
        const SizedBox(height: 16),
        if (inventoryLoading)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading private inventory products',
          )
        else if (items.isEmpty)
          const Text('No private inventory products are available.')
        else
          DropdownButtonFormField<String>(
            key: const Key('catalog-image-product'),
            initialValue: selectedExists ? selectedId : null,
            decoration: const InputDecoration(labelText: 'Private source item'),
            items: items
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.id,
                    child: Text('${item.canonicalName} · ${item.packSize}'),
                  ),
                )
                .toList(growable: false),
            onChanged: busy
                ? null
                : (id) {
                    if (id == null) return;
                    final item = items.firstWhere((item) => item.id == id);
                    altTextController.clear();
                    controller.selectSource(
                      CatalogProductImageSource(
                        homeId: item.homeId,
                        homeProductId: item.id,
                        displayName: item.canonicalName,
                      ),
                    );
                  },
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.tonalIcon(
              key: const Key('catalog-image-camera'),
              onPressed: busy || controller.source == null
                  ? null
                  : () => unawaited(acquire(acquisition.takePhoto)),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take photo'),
            ),
            OutlinedButton.icon(
              key: const Key('catalog-image-gallery'),
              onPressed: busy || controller.source == null
                  ? null
                  : () => unawaited(acquire(acquisition.chooseGallery)),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose photo'),
            ),
            OutlinedButton.icon(
              key: const Key('catalog-image-file'),
              onPressed: busy || controller.source == null
                  ? null
                  : () => unawaited(acquire(acquisition.chooseFile)),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Upload file'),
            ),
          ],
        ),
        if (controller.status ==
            CatalogProductImageContributionStatus.acquiring) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(
            semanticsLabel: 'Preparing selected catalog image',
          ),
        ],
        if (controller.safeMediaError case final message?) ...<Widget>[
          const SizedBox(height: 12),
          MaterialBanner(
            content: Text(message, key: const Key('catalog-image-media-error')),
            actions: <Widget>[
              TextButton(
                key: const Key('catalog-image-dismiss-error'),
                onPressed: controller.dismissMediaError,
                child: const Text('Review selection'),
              ),
            ],
          ),
        ],
        if (controller.image case final image?) ...<Widget>[
          const SizedBox(height: 16),
          Semantics(
            label: 'Local preview of the selected product image',
            image: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image.memory(
                  image.previewBytes,
                  key: ValueKey<String>(image.sourceDigest),
                  fit: BoxFit.contain,
                  gaplessPlayback: false,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 160,
                    child: Center(
                      child: Text('Local preview could not be rendered.'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${image.mediaType.wireName} · ${image.width}×${image.height} · '
            '${image.byteLength} bytes',
            key: const Key('catalog-image-metadata'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('catalog-image-alt-text'),
            controller: altTextController,
            enabled: !busy,
            maxLength: 191,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Public image description',
              hintText: 'Example: Front of a 1 kg rolled oats bag',
            ),
            onChanged: controller.setAltText,
          ),
          const SizedBox(height: 4),
          const Text(
            'The server verifies this exact file, removes metadata, and '
            're-encodes it as WebP in encrypted moderation quarantine. Your '
            'home, account, source item ID, and original digest are excluded '
            'from moderator and public projections.',
            key: Key('catalog-image-privacy-notice'),
          ),
          CheckboxListTile(
            key: const Key('catalog-image-rights'),
            contentPadding: EdgeInsets.zero,
            value: controller.rightsConfirmed,
            onChanged: busy
                ? null
                : (value) => controller.setRightsConfirmed(value ?? false),
            title: const Text(
              'I took this image or hold the rights and authorize public '
              'catalog reuse.',
            ),
            subtitle: const Text(
              CatalogProductImageDraft.rightsDeclarationVersion,
            ),
          ),
          CheckboxListTile(
            key: const Key('catalog-image-submit-confirmation'),
            contentPadding: EdgeInsets.zero,
            value: controller.submissionConfirmed,
            onChanged:
                busy ||
                    !controller.rightsConfirmed ||
                    controller.altText.trim().isEmpty
                ? null
                : (value) => controller.setSubmissionConfirmed(value ?? false),
            title: const Text(
              'Submit this exact preview and description for moderation.',
            ),
          ),
        ],
        if (controller.status ==
            CatalogProductImageContributionStatus.conflict) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            'The contribution or consent changed. Review the current fields '
            'before creating a new exact submission.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('catalog-image-review-conflict'),
              onPressed: controller.reviewAfterConflict,
              child: const Text('Review again'),
            ),
          ),
        ],
        if (const <CatalogProductImageContributionStatus>{
          CatalogProductImageContributionStatus.offline,
          CatalogProductImageContributionStatus.serviceUnavailable,
          CatalogProductImageContributionStatus.failure,
        }.contains(controller.status)) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            controller.status == CatalogProductImageContributionStatus.offline
                ? 'The result is unknown. Reconnect to retry the same stable submission.'
                : 'The result is unavailable. Retrying preserves the same stable submission.',
            key: const Key('catalog-image-retry-notice'),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('catalog-image-submit'),
          onPressed: controller.maySubmit && !busy
              ? () => unawaited(controller.submit())
              : null,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.publish_outlined),
          label: Text(
            controller.status == CatalogProductImageContributionStatus.offline
                ? 'Retry same submission'
                : 'Submit for moderation',
          ),
        ),
      ],
    );
  }
}

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
            'Image submitted for review',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'The local image bytes were removed. Publication still requires '
            'separate administrator approval.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('catalog-image-another'),
            onPressed: onAnother,
            child: const Text('Contribute another image'),
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
