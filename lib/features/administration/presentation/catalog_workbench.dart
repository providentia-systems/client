import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/administration/application/catalog_workbench_controller.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';

final class CatalogWorkbench extends StatelessWidget {
  const CatalogWorkbench({
    required this.controller,
    this.onReview,
    this.onPreviewMerge,
    super.key,
  });

  final CatalogWorkbenchController controller;
  final ValueChanged<CatalogQueueItem>? onReview;
  final ValueChanged<CatalogQueueItem>? onPreviewMerge;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return switch (controller.status) {
          CatalogWorkbenchStatus.idle ||
          CatalogWorkbenchStatus.loading => const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Loading catalog review queue',
            ),
          ),
          CatalogWorkbenchStatus.contractUnavailable => _WorkbenchMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Catalog administration is not connected',
            detail:
                'The catalog service could not be reached or its response did '
                'not match the current pinned contract.',
            actionLabel: 'Check again',
            onAction: controller.refresh,
          ),
          CatalogWorkbenchStatus.forbidden => _WorkbenchMessage(
            icon: Icons.lock_outline_rounded,
            title: 'Catalog role required',
            detail:
                'This account cannot access the sanitized catalog workbench. '
                'Household data is never available from this surface.',
            actionLabel: 'Check access',
            onAction: controller.refresh,
          ),
          CatalogWorkbenchStatus.conflict => _WorkbenchMessage(
            icon: Icons.sync_problem_rounded,
            title: 'Catalog change conflict',
            detail:
                'Another catalog revision changed this review. Reload before '
                'making a decision.',
            actionLabel: 'Reload queue',
            onAction: controller.refresh,
          ),
          CatalogWorkbenchStatus.stale => _WorkbenchMessage(
            icon: Icons.history_toggle_off_rounded,
            title: 'Merge preview is stale',
            detail:
                'Generate a new revision-bound preview before executing or '
                'reversing a merge.',
            actionLabel: 'Refresh',
            onAction: controller.refresh,
          ),
          CatalogWorkbenchStatus.failure => _WorkbenchMessage(
            icon: Icons.error_outline_rounded,
            title: 'Catalog workbench unavailable',
            detail:
                'No private catalog or household detail was loaded. Try again.',
            actionLabel: 'Try again',
            onAction: controller.refresh,
          ),
          CatalogWorkbenchStatus.ready => _ReadyWorkbench(
            controller: controller,
            onReview: onReview,
            onPreviewMerge: onPreviewMerge,
          ),
        };
      },
    );
  }
}

final class _ReadyWorkbench extends StatelessWidget {
  const _ReadyWorkbench({
    required this.controller,
    required this.onReview,
    required this.onPreviewMerge,
  });

  final CatalogWorkbenchController controller;
  final ValueChanged<CatalogQueueItem>? onReview;
  final ValueChanged<CatalogQueueItem>? onPreviewMerge;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final queue = _QueuePanel(controller: controller);
        final detail = _DetailPanel(
          item: controller.selectedItem,
          capabilities: controller.capabilities,
          onReview: onReview,
          onPreviewMerge: onPreviewMerge,
        );
        if (constraints.maxWidth >= 840) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(width: 360, child: queue),
              const VerticalDivider(width: 1),
              Expanded(child: detail),
            ],
          );
        }
        return CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(child: queue),
            SliverToBoxAdapter(child: detail),
          ],
        );
      },
    );
  }
}

final class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.controller});

  final CatalogWorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        primary: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Catalog review',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh catalog queue',
                    onPressed: controller.refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const Text('Sanitized global catalog records only'),
              const SizedBox(height: 12),
              if (controller.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No catalog reviews are waiting.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                for (final item in controller.items)
                  Card(
                    child: ListTile(
                      selected: item.id == controller.selectedItemId,
                      leading: Icon(_iconFor(item.kind)),
                      title: Text(item.title),
                      subtitle: Text(
                        item.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text('r${item.revision}'),
                      onTap: () {
                        controller.select(item.id);
                      },
                    ),
                  ),
              if (controller.auditEvents.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Catalog audit history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                for (final event in controller.auditEvents.take(3))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history_rounded),
                    title: Text(event.action),
                    subtitle: Text('${event.targetType} · ${event.reason}'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(CatalogQueueKind kind) {
    return switch (kind) {
      CatalogQueueKind.proposal => Icons.post_add_rounded,
      CatalogQueueKind.duplicate => Icons.compare_arrows_rounded,
      CatalogQueueKind.alias => Icons.alternate_email_rounded,
      CatalogQueueKind.barcode => Icons.qr_code_rounded,
      CatalogQueueKind.pack => Icons.inventory_2_outlined,
      CatalogQueueKind.category => Icons.category_outlined,
      CatalogQueueKind.icon => Icons.image_outlined,
    };
  }
}

final class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.item,
    required this.capabilities,
    required this.onReview,
    required this.onPreviewMerge,
  });

  final CatalogQueueItem? item;
  final Set<CatalogCapability> capabilities;
  final ValueChanged<CatalogQueueItem>? onReview;
  final ValueChanged<CatalogQueueItem>? onPreviewMerge;

  @override
  Widget build(BuildContext context) {
    final selected = item;
    if (selected == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Select a sanitized catalog review.'),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    selected.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(selected.summary),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      Chip(label: Text(selected.kind.name)),
                      Chip(label: Text(selected.status.name)),
                      Chip(label: Text('revision ${selected.revision}')),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'This review contains no home identity, stock, price, '
                    'receipt, private alias, note, image, or AI metadata.',
                  ),
                  const SizedBox(height: 20),
                  if (_mayReview(selected, capabilities))
                    FilledButton.icon(
                      onPressed: onReview == null
                          ? null
                          : () {
                              onReview!(selected);
                            },
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text(
                        selected.source == CatalogQueueSource.icon
                            ? 'Add validated icon metadata'
                            : 'Review sanitized record',
                      ),
                    )
                  else
                    const Text(
                      'Read-only reviewer view. A curator must commit changes.',
                    ),
                  if (selected.kind == CatalogQueueKind.duplicate) ...<Widget>[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed:
                          capabilities.contains(
                                CatalogCapability.previewMerges,
                              ) &&
                              onPreviewMerge != null
                          ? () {
                              onPreviewMerge!(selected);
                            }
                          : null,
                      icon: const Icon(Icons.preview_outlined),
                      label: Text(
                        selected.source == CatalogQueueSource.merge
                            ? 'Preview revision-bound reversal'
                            : 'Generate revision-bound merge preview',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _mayReview(CatalogQueueItem item, Set<CatalogCapability> capabilities) =>
      item.source == CatalogQueueSource.icon
      ? capabilities.contains(CatalogCapability.manageIcons)
      : capabilities.contains(CatalogCapability.review);
}

final class _WorkbenchMessage extends StatelessWidget {
  const _WorkbenchMessage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 48),
                const SizedBox(height: 14),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(detail, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: () {
                    unawaited(onAction());
                  },
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
