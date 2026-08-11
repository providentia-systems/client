import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/administration/application/catalog_administration_ports.dart';
import 'package:providentia/features/administration/application/catalog_merge_workflow.dart';
import 'package:providentia/features/administration/application/catalog_workbench_controller.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';
import 'package:providentia/features/administration/presentation/catalog_workbench.dart';

/// Production moderation surface. Every visible action reaches a revision-
/// bound application port; no button is backed by a placeholder callback.
final class CatalogWorkbenchPage extends StatefulWidget {
  const CatalogWorkbenchPage({
    required this.controller,
    required this.proposalDecisions,
    required this.contributionDecisions,
    required this.conflictDecisions,
    required this.iconRepository,
    required this.mergeWorkflow,
    this.idGenerator,
    super.key,
  });

  final CatalogWorkbenchController controller;
  final CatalogProposalDecisionRepository proposalDecisions;
  final CatalogContributionModerationRepository contributionDecisions;
  final CatalogConflictResolutionRepository conflictDecisions;
  final CatalogIconRepository iconRepository;
  final CatalogMergeWorkflow mergeWorkflow;
  final String Function()? idGenerator;

  @override
  State<CatalogWorkbenchPage> createState() => _CatalogWorkbenchPageState();
}

final class _CatalogWorkbenchPageState extends State<CatalogWorkbenchPage> {
  bool _actionRunning = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Catalog administration')),
    body: Stack(
      children: <Widget>[
        CatalogWorkbench(
          controller: widget.controller,
          onReview: (item) => unawaited(_review(item)),
          onPreviewMerge: (item) => unawaited(_previewMerge(item)),
        ),
        if (_actionRunning)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Applying catalog administration action',
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _review(CatalogQueueItem item) async {
    if (_actionRunning) return;
    if (item.source == CatalogQueueSource.merge) {
      await _previewMerge(item);
      return;
    }
    if (item.source == CatalogQueueSource.icon) {
      final icon = await showDialog<CatalogIconWrite>(
        context: context,
        builder: (_) => _CatalogIconDialog(item: item),
      );
      if (icon == null) return;
      await _runAction(() async {
        await widget.iconRepository.putIcon(icon);
      });
      return;
    }
    if (item.source == CatalogQueueSource.conflict) {
      final reason = await _reasonDialog(
        title: 'Keep the existing catalog identity?',
        actionLabel: 'Keep existing',
      );
      if (reason == null) return;
      await _runAction(
        () => widget.conflictDecisions.keepExistingConflict(
          conflictId: item.id,
          reason: reason,
          expectedRevision: item.revision,
        ),
      );
      return;
    }
    final request = await _reviewDialog(item);
    if (request == null) return;
    final decision = CatalogReviewDecision(
      proposalId: item.id,
      decision: request.decision,
      reason: request.reason,
      expectedRevision: item.revision,
    );
    await _runAction(() async {
      if (item.source == CatalogQueueSource.consentContribution) {
        await widget.contributionDecisions.decideContribution(decision);
      } else {
        await widget.proposalDecisions.decideProposal(decision);
      }
    });
  }

  Future<void> _previewMerge(CatalogQueueItem item) async {
    if (_actionRunning) return;
    try {
      setState(() => _actionRunning = true);
      final preview = item.source == CatalogQueueSource.merge
          ? await widget.mergeWorkflow.previewReversal(mergeEventId: item.id)
          : await _previewConflictMerge(item);
      if (!mounted) return;
      setState(() => _actionRunning = false);
      final reason = await _mergeConfirmation(preview);
      if (reason == null || !mounted) return;
      setState(() => _actionRunning = true);
      final idGenerator = widget.idGenerator ?? UuidV4Generator().call;
      await widget.mergeWorkflow.execute(
        preview: preview,
        currentRevisions: preview.expectedRevisions,
        idempotencyKey: idGenerator(),
        reason: reason,
      );
      if (!mounted) return;
      await widget.controller.refresh();
      if (mounted) _showSuccess('Catalog merge action completed.');
    } on Exception {
      if (mounted) _showFailure();
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  Future<CatalogMergePreview> _previewConflictMerge(CatalogQueueItem item) {
    final ids = item.relatedCatalogIds;
    if (ids.length < 2) {
      throw const CatalogValidationException();
    }
    return widget.mergeWorkflow.previewMerge(
      survivorProductId: ids.first,
      absorbedProductIds: ids.skip(1).toList(growable: false),
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() => _actionRunning = true);
    try {
      await action();
      await widget.controller.refresh();
      if (mounted) _showSuccess('Catalog review saved.');
    } on Exception {
      if (mounted) _showFailure();
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  Future<_ReviewRequest?> _reviewDialog(CatalogQueueItem item) {
    var reason = '';
    return showDialog<_ReviewRequest>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Review ${item.title}'),
        content: TextField(
          key: const Key('catalog-review-reason'),
          onChanged: (value) => reason = value,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Audit reason',
            helperText: 'Required and recorded in the catalog audit trail',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('reject-catalog-review'),
            onPressed: () => _completeReview(
              context,
              reason,
              CatalogReviewDecisionKind.reject,
            ),
            child: const Text('Reject'),
          ),
          FilledButton(
            key: const Key('approve-catalog-review'),
            onPressed: () => _completeReview(
              context,
              reason,
              CatalogReviewDecisionKind.approve,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _completeReview(
    BuildContext context,
    String reason,
    CatalogReviewDecisionKind decision,
  ) {
    final cleaned = reason.trim();
    if (cleaned.isEmpty) return;
    Navigator.pop(context, _ReviewRequest(decision: decision, reason: cleaned));
  }

  Future<String?> _reasonDialog({
    required String title,
    required String actionLabel,
  }) {
    var reason = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const Key('catalog-conflict-reason'),
          onChanged: (value) => reason = value,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Audit reason'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-catalog-conflict'),
            onPressed: () {
              final cleaned = reason.trim();
              if (cleaned.isNotEmpty) Navigator.pop(context, cleaned);
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<String?> _mergeConfirmation(CatalogMergePreview preview) {
    var reason = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          preview.kind == CatalogMergePlanKind.merge
              ? 'Execute revision-bound merge?'
              : 'Reverse revision-bound merge?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '${preview.impact.globalAliasCount} aliases, '
                '${preview.impact.globalPackCount} packs, and '
                '${preview.impact.privateReferenceCount} private references '
                'would be relinked without exposing household details.',
              ),
              if (preview.conflicts.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text('Conflicts: ${preview.conflicts.join(', ')}'),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const Key('catalog-merge-reason'),
                onChanged: (value) => reason = value,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Audit reason'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('execute-catalog-merge'),
            onPressed: preview.eligible
                ? () {
                    final cleaned = reason.trim();
                    if (cleaned.isNotEmpty) Navigator.pop(context, cleaned);
                  }
                : null,
            child: Text(
              preview.kind == CatalogMergePlanKind.merge ? 'Merge' : 'Reverse',
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'The catalog action was not applied. Reload and try again.',
        ),
      ),
    );
  }
}

final class _ReviewRequest {
  const _ReviewRequest({required this.decision, required this.reason});

  final CatalogReviewDecisionKind decision;
  final String reason;
}

final class _CatalogIconDialog extends StatefulWidget {
  const _CatalogIconDialog({required this.item});

  final CatalogQueueItem item;

  @override
  State<_CatalogIconDialog> createState() => _CatalogIconDialogState();
}

final class _CatalogIconDialogState extends State<_CatalogIconDialog> {
  late final TextEditingController _digest;
  late final TextEditingController _altText;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _byteSize;
  late final TextEditingController _provenance;
  String _mediaType = 'image/png';
  String? _safeError;

  @override
  void initState() {
    super.initState();
    _digest = TextEditingController();
    _altText = TextEditingController();
    _width = TextEditingController(text: '256');
    _height = TextEditingController(text: '256');
    _byteSize = TextEditingController();
    _provenance = TextEditingController();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Add icon metadata for ${widget.item.title}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            key: const Key('catalog-icon-digest'),
            controller: _digest,
            decoration: const InputDecoration(labelText: 'SHA-256 digest'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('catalog-icon-media-type'),
            initialValue: _mediaType,
            decoration: const InputDecoration(labelText: 'Media type'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'image/png', child: Text('image/png')),
              DropdownMenuItem(value: 'image/webp', child: Text('image/webp')),
              DropdownMenuItem(
                value: 'image/svg+xml',
                child: Text('image/svg+xml'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mediaType = value);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('catalog-icon-alt-text'),
            controller: _altText,
            maxLength: 191,
            decoration: const InputDecoration(labelText: 'Alt text'),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('catalog-icon-width'),
                  controller: _width,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Width'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('catalog-icon-height'),
                  controller: _height,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Height'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('catalog-icon-byte-size'),
            controller: _byteSize,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Byte size'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('catalog-icon-provenance'),
            controller: _provenance,
            maxLength: 191,
            decoration: const InputDecoration(labelText: 'Provenance'),
          ),
          if (_safeError != null)
            Text(_safeError!, key: const Key('catalog-icon-validation-error')),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('save-catalog-icon'),
        onPressed: _save,
        child: const Text('Save icon metadata'),
      ),
    ],
  );

  void _save() {
    final targetType = widget.item.iconTargetType;
    if (targetType == null) {
      setState(() => _safeError = 'The icon target is unavailable.');
      return;
    }
    try {
      final icon = CatalogIconWrite(
        targetType: targetType,
        targetId: widget.item.id,
        assetDigest: _digest.text.trim(),
        mediaType: _mediaType,
        altText: _altText.text.trim(),
        width: int.tryParse(_width.text.trim()) ?? -1,
        height: int.tryParse(_height.text.trim()) ?? -1,
        byteSize: int.tryParse(_byteSize.text.trim()) ?? -1,
        provenance: _provenance.text.trim(),
        expectedRevision: widget.item.revision,
      );
      Navigator.pop(context, icon);
    } on ArgumentError {
      setState(
        () => _safeError =
            'Enter a valid digest, media type, alt text, dimensions, byte '
            'size, and provenance.',
      );
    }
  }

  @override
  void dispose() {
    _digest.dispose();
    _altText.dispose();
    _width.dispose();
    _height.dispose();
    _byteSize.dispose();
    _provenance.dispose();
    super.dispose();
  }
}
