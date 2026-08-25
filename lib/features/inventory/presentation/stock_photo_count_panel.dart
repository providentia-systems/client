import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/inventory/application/stock_photo_count_controller.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';

final class StockPhotoCountPanel extends StatelessWidget {
  const StockPhotoCountPanel({
    required this.controller,
    this.acquisition,
    super.key,
  });

  final StockPhotoCountController controller;
  final StockPhotoAcquisitionActions? acquisition;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        return Card(
          key: const Key('stock-photo-count-panel'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Count from stock photos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose 1–8 images. They are sanitized and kept only for '
                  'this review. Nothing changes inventory until you match a '
                  'home product, confirm a quantity, and explicitly finish '
                  'the ordinary count.',
                ),
                if (state.safeMessage != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    state.safeMessage!,
                    key: const Key('stock-photo-safe-message'),
                  ),
                ],
                const SizedBox(height: 12),
                ..._body(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, StockPhotoCountState state) {
    switch (state.status) {
      case StockPhotoCountStatus.idle:
      case StockPhotoCountStatus.failed:
        final actions = acquisition;
        if (actions != null) {
          return <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  key: const Key('stock-photo-camera'),
                  onPressed: () => controller.selectAssets(actions.takePhoto),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take photo'),
                ),
                OutlinedButton.icon(
                  key: const Key('stock-photo-gallery'),
                  onPressed: () =>
                      controller.selectAssets(actions.chooseGallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from gallery'),
                ),
                OutlinedButton.icon(
                  key: const Key('stock-photo-files'),
                  onPressed: () => controller.selectAssets(actions.uploadFiles),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Upload image files'),
                ),
              ],
            ),
          ];
        }
        return <Widget>[
          FilledButton.icon(
            key: const Key('stock-photo-select'),
            onPressed: controller.selectPhotos,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Choose stock photos'),
          ),
        ];
      case StockPhotoCountStatus.preparing:
      case StockPhotoCountStatus.processing:
        return const <Widget>[Center(child: CircularProgressIndicator())];
      case StockPhotoCountStatus.awaitingConsent:
        final provider = state.provider;
        return <Widget>[
          _PreviewStrip(controller: controller, media: state.prepared!.media),
          const SizedBox(height: 12),
          Text(
            provider == null
                ? 'Verifying the household provider…'
                : 'Provider: ${provider.displayName} · ${provider.model}',
            key: const Key('stock-photo-provider-disclosure'),
          ),
          const SizedBox(height: 4),
          Text(
            state.privacyMode == AiPrivacyMode.strictLocal
                ? 'Privacy route: direct strict local. Sanitized image bytes '
                      'go directly to ${provider?.endpoint?.origin ?? 'the selected LAN endpoint'} '
                      'and do not pass through the Providentia server.'
                : 'Privacy route: secure server proxy. Sanitized image bytes '
                      'are uploaded transiently for extraction and are not durable media.',
            key: const Key('stock-photo-privacy-disclosure'),
          ),
          const SizedBox(height: 4),
          Text(
            'Ordered digests: ${state.prepared!.orderedHashes.map((hash) => hash.substring(0, 12)).join(' → ')}',
            key: const Key('stock-photo-ordered-digests'),
          ),
          const SizedBox(height: 12),
          if (!state.consentConfirmed)
            FilledButton(
              key: const Key('stock-photo-confirm-consent'),
              onPressed: provider == null
                  ? null
                  : controller.confirmTransmission,
              child: const Text('Confirm provider and transmission'),
            )
          else
            FilledButton.icon(
              key: const Key('stock-photo-extract'),
              onPressed: controller.extract,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Analyze selected photos'),
            ),
          TextButton(
            onPressed: controller.abandonPhotos,
            child: const Text('Discard photos'),
          ),
        ];
      case StockPhotoCountStatus.review:
        return <Widget>[
          _PreviewStrip(controller: controller, media: state.prepared!.media),
          const SizedBox(height: 12),
          if (state.candidates.isEmpty)
            const Text('No stock candidates were found. The count stays open.'),
          for (final review in state.uncountedFirst)
            _CandidateReviewCard(
              key: ValueKey<String>(review.proposal.candidateId),
              controller: controller,
              review: review,
              busy: state.candidateBusyId == review.proposal.candidateId,
            ),
          const SizedBox(height: 8),
          const Text(
            'Photo candidates do not close the count. Use “Finish and apply” '
            'above only after reviewing the ordinary count lines.',
          ),
          TextButton(
            onPressed: controller.abandonPhotos,
            child: const Text('Discard review previews'),
          ),
        ];
      case StockPhotoCountStatus.accessDenied:
        return const <Widget>[
          Text('Photo intelligence is unavailable for this home.'),
        ];
    }
  }
}

final class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({required this.controller, required this.media});

  final StockPhotoCountController controller;
  final List<PreparedAiMedia> media;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        key: const Key('stock-photo-previews'),
        scrollDirection: Axis.horizontal,
        itemCount: media.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => SizedBox(
          width: 92,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FutureBuilder<Uint8List>(
              future: controller.readPreview(media[index]),
              builder: (context, snapshot) => snapshot.hasData
                  ? Image.memory(
                      snapshot.data!,
                      key: Key('stock-photo-preview-$index'),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _CandidateReviewCard extends StatefulWidget {
  const _CandidateReviewCard({
    required this.controller,
    required this.review,
    required this.busy,
    super.key,
  });

  final StockPhotoCountController controller;
  final StockPhotoCandidateReview review;
  final bool busy;

  @override
  State<_CandidateReviewCard> createState() => _CandidateReviewCardState();
}

final class _CandidateReviewCardState extends State<_CandidateReviewCard> {
  late final TextEditingController _quantity;
  late final TextEditingController _productSearch;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController(
      text: _quantityText(widget.review.quantity),
    );
    _productSearch = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant _CandidateReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.review.quantity != oldWidget.review.quantity &&
        !_quantity.selection.isValid) {
      _quantity.text = _quantityText(widget.review.quantity);
    }
    if (widget.review.homeProductId != oldWidget.review.homeProductId) {
      final selected = widget.controller.homeProducts
          .where((item) => item.id == widget.review.homeProductId)
          .firstOrNull;
      _productSearch.text = selected == null ? '' : _productLabel(selected);
    }
  }

  @override
  void dispose() {
    _quantity.dispose();
    _productSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proposal = widget.review.proposal;
    final productName = proposal.productName.value ?? 'Unidentified product';
    final metadata = <String>[
      ?proposal.brand.value,
      ?proposal.variant.value,
      ?proposal.packDescription.value,
      'Confidence ${(proposal.confidence * 100).round()}%',
    ].join(' · ');
    final selected = widget.controller.homeProducts
        .where((item) => item.id == widget.review.homeProductId)
        .firstOrNull;
    final matches = widget.controller
        .searchItems(_productSearch.text)
        .take(8)
        .toList(growable: false);
    return Card.outlined(
      color: widget.review.resolved
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(productName, style: Theme.of(context).textTheme.titleSmall),
            if (metadata.isNotEmpty) Text(metadata),
            if (proposal.warnings.isNotEmpty)
              Text(proposal.warnings.join(' · ')),
            const SizedBox(height: 8),
            TextField(
              key: Key('stock-photo-item-search-${proposal.candidateId}'),
              controller: _productSearch,
              enabled: !widget.review.resolved && !widget.busy,
              decoration: const InputDecoration(
                labelText: 'Search full item master',
                hintText: 'Name, brand, category, alias, or pack',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (selected != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Matched: ${_productLabel(selected)}',
                  key: Key('stock-photo-selected-${proposal.candidateId}'),
                ),
              ),
            if (!widget.review.resolved) ...<Widget>[
              const SizedBox(height: 6),
              for (final item in matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: OutlinedButton(
                    key: Key(
                      'stock-photo-item-${proposal.candidateId}-${item.id}',
                    ),
                    onPressed:
                        widget.busy ||
                            (!item.isHomeProduct &&
                                !widget.controller.canAddCatalogProduct)
                        ? null
                        : () => widget.controller.selectCandidateItem(
                            proposal.candidateId,
                            item.id,
                          ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${item.isHomeProduct ? 'Home' : 'Add catalog'} · ${_productLabel(item)}',
                      ),
                    ),
                  ),
                ),
              if (matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No item-master matches.'),
                ),
              TextButton.icon(
                key: Key('stock-photo-private-${proposal.candidateId}'),
                onPressed:
                    widget.busy || !widget.controller.canCreatePrivateProduct
                    ? null
                    : _createPrivateProduct,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Create private home product'),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              key: Key('stock-photo-quantity-${proposal.candidateId}'),
              controller: _quantity,
              enabled: !widget.review.resolved && !widget.busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Confirmed quantity',
              ),
              onChanged: (value) => widget.controller.setQuantity(
                proposal.candidateId,
                double.tryParse(value.trim()),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: Key('stock-photo-counted-${proposal.candidateId}'),
              onPressed: widget.review.resolved || widget.busy
                  ? null
                  : () => widget.controller.confirmCandidate(
                      proposal.candidateId,
                    ),
              child: Text(
                widget.review.counted
                    ? 'Photo counted'
                    : widget.review.rejected
                    ? 'Candidate rejected'
                    : widget.busy
                    ? 'Saving…'
                    : 'Confirm photo count',
              ),
            ),
            if (!widget.review.resolved) ...<Widget>[
              const SizedBox(height: 4),
              TextButton(
                key: Key('stock-photo-reject-${proposal.candidateId}'),
                onPressed:
                    widget.busy ||
                        widget.review.serverCandidate?.status ==
                            AiCandidateReviewStatus.accepted
                    ? null
                    : () => widget.controller.rejectCandidate(
                        proposal.candidateId,
                      ),
                child: const Text('Reject candidate'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _quantityText(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  static String _productLabel(InventoryItem item) =>
      '${item.canonicalName} · ${item.packSize}';

  Future<void> _createPrivateProduct() async {
    final proposal = widget.review.proposal;
    final name = TextEditingController(text: proposal.productName.value ?? '');
    final pack = TextEditingController(
      text: proposal.packDescription.value ?? '',
    );
    try {
      final input = await showDialog<(String, String?)>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Create private home product'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                key: const Key('stock-photo-private-name'),
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Private name'),
              ),
              TextField(
                key: const Key('stock-photo-private-pack'),
                controller: pack,
                decoration: const InputDecoration(labelText: 'Pack text'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('stock-photo-private-create'),
              onPressed: () {
                final privateName = name.text.trim();
                if (privateName.isEmpty) return;
                final packText = pack.text.trim();
                Navigator.of(
                  context,
                ).pop((privateName, packText.isEmpty ? null : packText));
              },
              child: const Text('Create and match'),
            ),
          ],
        ),
      );
      if (input == null || !mounted) return;
      await widget.controller.createPrivateProductForCandidate(
        candidateId: proposal.candidateId,
        privateName: input.$1,
        packText: input.$2,
      );
    } finally {
      name.dispose();
      pack.dispose();
    }
  }
}
