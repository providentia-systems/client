import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/catalog_import/application/catalog_import_controller.dart';
import 'package:providentia/features/catalog_import/domain/catalog_import_models.dart';

/// Desktop and web spreadsheet import: pick, map columns, validate, stage,
/// review the server resolutions, and apply behind one explicit confirmation.
final class CatalogImportPage extends StatelessWidget {
  const CatalogImportPage({required this.controller, super.key});

  final CatalogImportController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from spreadsheet')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final state = controller.state;
          return switch (state.phase) {
            CatalogImportPhase.idle => _PickStep(controller: controller),
            CatalogImportPhase.loadingFile => const _Progress(
              label: 'Reading the selected spreadsheet',
            ),
            CatalogImportPhase.mapping => _MappingStep(controller: controller),
            CatalogImportPhase.staging => _StagingStep(controller: controller),
            CatalogImportPhase.review => _ReviewStep(controller: controller),
            CatalogImportPhase.confirming => const _Progress(
              label: 'Applying the reviewed records',
            ),
            CatalogImportPhase.completed => _CompletedStep(
              controller: controller,
            ),
            CatalogImportPhase.accessDenied => const _SafeState(
              icon: Icons.lock_outline,
              title: 'Catalog-import permission required',
              detail:
                  'Your current home role cannot import spreadsheets. Nothing '
                  'was applied.',
            ),
          };
        },
      ),
    );
  }
}

final class _PickStep extends StatelessWidget {
  const _PickStep({required this.controller});

  final CatalogImportController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Bring a product list into this home',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a .csv or .xlsx file of at most 10 MB with up to '
          '5000 rows. You will map its columns, review what the service '
          'resolves, and nothing is applied before your explicit '
          'confirmation.',
        ),
        _SafeMessage(message: controller.state.safeMessage),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('catalog-import-pick-file'),
            onPressed: () => unawaited(controller.pickSpreadsheet()),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Choose spreadsheet'),
          ),
        ),
      ],
    );
  }
}

final class _MappingStep extends StatelessWidget {
  const _MappingStep({required this.controller});

  final CatalogImportController controller;

  static const int previewRowLimit = 8;
  static const int issueDisplayLimit = 20;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final grid = state.grid!;
    final validation = state.validation;
    final headerTexts = state.hasHeaderRow ? grid.rows.first : null;
    final previewRows = grid.rows
        .skip(state.hasHeaderRow ? 1 : 0)
        .take(previewRowLimit)
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Map the columns',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            OutlinedButton.icon(
              key: const Key('catalog-import-repick'),
              onPressed: () => unawaited(controller.pickSpreadsheet()),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Choose another file'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${grid.sourceName} · ${grid.rows.length - (state.hasHeaderRow ? 1 : 0)} data rows',
          key: const Key('catalog-import-source'),
        ),
        _SafeMessage(message: state.safeMessage),
        const SizedBox(height: 16),
        SegmentedButton<CatalogImportRecordType>(
          key: const Key('catalog-import-record-type'),
          segments: const <ButtonSegment<CatalogImportRecordType>>[
            ButtonSegment<CatalogImportRecordType>(
              value: CatalogImportRecordType.homeProduct,
              label: Text('Private products'),
            ),
            ButtonSegment<CatalogImportRecordType>(
              value: CatalogImportRecordType.catalogProductReference,
              label: Text('Link to catalog'),
            ),
          ],
          selected: <CatalogImportRecordType>{state.recordType},
          onSelectionChanged: (selection) =>
              controller.selectRecordType(selection.single),
        ),
        SwitchListTile(
          key: const Key('catalog-import-header-row'),
          contentPadding: EdgeInsets.zero,
          title: const Text('First row contains column names'),
          value: state.hasHeaderRow,
          onChanged: controller.setHasHeaderRow,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  for (var column = 0; column < grid.columnCount; column++)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: SizedBox(
                        width: 190,
                        child: _ColumnAssignment(
                          controller: controller,
                          column: column,
                          headerText: headerTexts == null
                              ? 'Column ${column + 1}'
                              : headerTexts[column],
                          assigned: state.mapping.fieldForColumn(column),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              DataTable(
                key: const Key('catalog-import-preview'),
                headingRowHeight: 34,
                columns: <DataColumn>[
                  for (var column = 0; column < grid.columnCount; column++)
                    DataColumn(
                      label: Text(
                        headerTexts == null
                            ? 'Column ${column + 1}'
                            : headerTexts[column],
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                rows: <DataRow>[
                  for (final row in previewRows)
                    DataRow(
                      cells: <DataCell>[
                        for (final cell in row)
                          DataCell(
                            SizedBox(
                              width: 166,
                              child: Text(
                                cell,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (validation != null) _ValidationSummary(validation: validation),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('catalog-import-stage'),
            onPressed: validation != null && validation.mayStage
                ? () => unawaited(controller.stage())
                : null,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(
              validation == null
                  ? 'Stage for review'
                  : 'Stage ${validation.records.length} row'
                        '${validation.records.length == 1 ? '' : 's'} for review',
            ),
          ),
        ),
      ],
    );
  }
}

final class _ColumnAssignment extends StatelessWidget {
  const _ColumnAssignment({
    required this.controller,
    required this.column,
    required this.headerText,
    required this.assigned,
  });

  final CatalogImportController controller;
  final int column;
  final String headerText;
  final CatalogImportField? assigned;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<CatalogImportField?>(
      key: Key('catalog-import-column-$column'),
      initialValue: assigned,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: headerText.trim().isEmpty
            ? 'Column ${column + 1}'
            : headerText,
        border: const OutlineInputBorder(),
      ),
      items: <DropdownMenuItem<CatalogImportField?>>[
        const DropdownMenuItem<CatalogImportField?>(child: Text('Ignored')),
        for (final field in CatalogImportField.values)
          DropdownMenuItem<CatalogImportField?>(
            value: field,
            child: Text(field.label),
          ),
      ],
      onChanged: (field) => controller.assignColumn(column, field),
    );
  }
}

final class _ValidationSummary extends StatelessWidget {
  const _ValidationSummary({required this.validation});

  final CatalogImportValidation validation;

  @override
  Widget build(BuildContext context) {
    final issues = validation.issues
        .take(_MappingStep.issueDisplayLimit)
        .toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              validation.blockingReason ??
                  '${validation.records.length} row'
                      '${validation.records.length == 1 ? '' : 's'} ready · '
                      '${validation.issues.length} with problems · '
                      '${validation.emptyRowCount} empty skipped',
              key: const Key('catalog-import-validation-summary'),
            ),
            if (issues.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Column(
                key: const Key('catalog-import-issues'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final issue in issues)
                    Text('Row ${issue.sourceRowNumber}: ${issue.message}'),
                  if (validation.issues.length > issues.length)
                    Text(
                      '… and ${validation.issues.length - issues.length} more '
                      'rows with problems.',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _StagingStep extends StatelessWidget {
  const _StagingStep({required this.controller});

  final CatalogImportController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state.busy) {
      return _Progress(
        label:
            'Staging batch ${state.stagedBatchCount + 1} of '
            '${state.batches.length}',
      );
    }
    return _SafeState(
      icon: Icons.cloud_off_outlined,
      title: 'Staging paused',
      detail:
          state.safeMessage ??
          'The import service was unavailable. Nothing was applied.',
      retryKey: const Key('catalog-import-retry-stage'),
      retryLabel: 'Retry staging',
      onRetry: controller.stage,
    );
  }
}

final class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.controller});

  final CatalogImportController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final reconciliation = state.reconciliation;
    return ListView(
      key: const Key('catalog-import-review'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Review before anything is applied',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        _SafeMessage(message: state.safeMessage),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            Chip(
              key: const Key('catalog-import-count-already-present'),
              avatar: const Icon(Icons.inventory_2_outlined, size: 18),
              label: Text('${reconciliation.alreadyPresent} already present'),
            ),
            Chip(
              key: const Key('catalog-import-count-link-catalog'),
              avatar: const Icon(Icons.link_outlined, size: 18),
              label: Text('${reconciliation.linkCatalog} link to catalog'),
            ),
            Chip(
              key: const Key('catalog-import-count-create-private'),
              avatar: const Icon(Icons.add_box_outlined, size: 18),
              label: Text('${reconciliation.createPrivate} new private'),
            ),
            Chip(
              key: const Key('catalog-import-count-error'),
              avatar: const Icon(Icons.error_outline, size: 18),
              label: Text('${reconciliation.errors} with errors'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final slot in state.batches)
          if (slot.batch != null) _BatchReviewCard(slot: slot),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('catalog-import-confirm'),
            onPressed: () => unawaited(_confirm(context)),
            icon: const Icon(Icons.playlist_add_check_outlined),
            label: const Text('Apply the reviewed records'),
          ),
        ),
      ],
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final reconciliation = controller.state.reconciliation;
    final remaining =
        controller.state.stagedBatchCount -
        controller.state.confirmedBatchCount;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('catalog-import-confirm-dialog'),
        title: const Text('Apply this import?'),
        content: Text(
          '${reconciliation.linkCatalog} catalog link'
          '${reconciliation.linkCatalog == 1 ? '' : 's'}, '
          '${reconciliation.createPrivate} new private product'
          '${reconciliation.createPrivate == 1 ? '' : 's'}, and '
          '${reconciliation.alreadyPresent} already-present row'
          '${reconciliation.alreadyPresent == 1 ? '' : 's'} across '
          '$remaining staged batch${remaining == 1 ? '' : 'es'}. '
          '${reconciliation.errors} row'
          '${reconciliation.errors == 1 ? '' : 's'} with errors stay'
          '${reconciliation.errors == 1 ? 's' : ''} unapplied. This applies '
          'the reviewed records to this home.',
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('catalog-import-confirm-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep reviewing'),
          ),
          FilledButton(
            key: const Key('catalog-import-confirm-apply'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply records'),
          ),
        ],
      ),
    );
    if (approved ?? false) {
      await controller.confirmStagedBatches();
    }
  }
}

final class _BatchReviewCard extends StatelessWidget {
  const _BatchReviewCard({required this.slot});

  final CatalogImportBatchSlot slot;

  static const int rowDisplayLimit = 50;

  @override
  Widget build(BuildContext context) {
    final batch = slot.batch!;
    final rows = batch.rows.take(rowDisplayLimit).toList(growable: false);
    return Card(
      key: Key('catalog-import-batch-${slot.index}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Batch ${slot.index + 1} · ${batch.rowCount} rows · '
              '${batch.status.wireName}'
              '${batch.replayed ? ' · replayed' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 170,
                      child: Text(_resolutionLabel(row.resolution)),
                    ),
                    Expanded(
                      child: Text(
                        row.resolution == CatalogImportRowResolution.error
                            ? '${row.displayName} — '
                                  '${row.errorDetail ?? row.errorCode ?? 'invalid row'}'
                            : row.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (batch.rows.length > rows.length)
              Text('… and ${batch.rows.length - rows.length} more rows.'),
          ],
        ),
      ),
    );
  }

  static String _resolutionLabel(CatalogImportRowResolution resolution) =>
      switch (resolution) {
        CatalogImportRowResolution.alreadyPresent => 'Already present',
        CatalogImportRowResolution.linkCatalog => 'Link to catalog',
        CatalogImportRowResolution.createPrivate => 'New private product',
        CatalogImportRowResolution.error => 'Error',
      };
}

final class _CompletedStep extends StatelessWidget {
  const _CompletedStep({required this.controller});

  final CatalogImportController controller;

  @override
  Widget build(BuildContext context) {
    final reconciliation = controller.state.reconciliation;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const Icon(Icons.check_circle_outline, size: 48),
        const SizedBox(height: 12),
        Text(
          'Import applied',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              key: const Key('catalog-import-reconciliation'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('${reconciliation.imported} rows imported'),
                Text('${reconciliation.skipped} rows skipped'),
                Text('${reconciliation.alreadyPresent} were already present'),
                Text('${reconciliation.linkCatalog} linked to the catalog'),
                Text(
                  '${reconciliation.createPrivate} created as private products',
                ),
                Text('${reconciliation.errors} rows had errors'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('catalog-import-start-over'),
            onPressed: controller.reset,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Import another spreadsheet'),
          ),
        ),
      ],
    );
  }
}

final class _SafeMessage extends StatelessWidget {
  const _SafeMessage({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        key: const Key('catalog-import-safe-message'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

final class _Progress extends StatelessWidget {
  const _Progress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircularProgressIndicator(semanticsLabel: label),
        const SizedBox(height: 12),
        Text(label),
      ],
    ),
  );
}

final class _SafeState extends StatelessWidget {
  const _SafeState({
    required this.icon,
    required this.title,
    required this.detail,
    this.retryKey,
    this.retryLabel,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Key? retryKey;
  final String? retryLabel;
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
                key: retryKey,
                onPressed: () => unawaited(onRetry!()),
                child: Text(retryLabel ?? 'Try again'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
