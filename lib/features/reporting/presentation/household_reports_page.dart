import 'dart:async';

import 'package:flutter/material.dart';
import 'package:providentia/features/reporting/application/reporting_controller.dart';
import 'package:providentia/features/reporting/domain/household_report.dart';

final class HouseholdReportsPage extends StatelessWidget {
  const HouseholdReportsPage({required this.controller, super.key});

  final ReportingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return switch (controller.status) {
          ReportingStatus.idle => _ReportMessage(
            icon: Icons.assessment_outlined,
            title: 'Household reports',
            detail:
                'Load private reports for the currently selected home. Data '
                'from other homes is rejected.',
            action: controller.load,
            actionLabel: 'Load reports',
          ),
          ReportingStatus.loading => const Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Loading household reports',
            ),
          ),
          ReportingStatus.contractUnavailable => _ReportMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Reports are temporarily unavailable',
            detail:
                'The report response could not be verified safely. Refresh '
                'and try again later.',
            action: controller.load,
            actionLabel: 'Check again',
          ),
          ReportingStatus.forbidden => _ReportMessage(
            icon: Icons.lock_outline_rounded,
            title: 'Home access required',
            detail:
                'Platform and catalog roles do not grant access to household '
                'reports.',
            action: controller.load,
            actionLabel: 'Check access',
          ),
          ReportingStatus.failure => _ReportMessage(
            icon: Icons.error_outline_rounded,
            title: 'Reports could not be loaded',
            detail:
                'No report detail is shown. Your selected home remains '
                'unchanged.',
            action: controller.load,
            actionLabel: 'Try again',
          ),
          ReportingStatus.ready => _ReadyReport(
            report: controller.report!,
            onRefresh: controller.load,
          ),
        };
      },
    );
  }
}

String _inventoryDetail(InventoryReportFact line) {
  final unit = line.stockUnit == null ? '' : ' ${line.stockUnit}';
  return <String>[
    line.factualQuantity == null
        ? 'Quantity unknown'
        : 'Quantity ${line.factualQuantity}$unit',
    switch (line.quantityState) {
      InventoryReportQuantityState.unknown => 'No recorded stock evidence',
      InventoryReportQuantityState.uncertain =>
        'Uncertain ledger balance; requires review',
      InventoryReportQuantityState.recorded => 'Recorded ledger balance',
      InventoryReportQuantityState.unavailable =>
        'Stock evidence unavailable in this response',
    },
    if (line.quantityState == InventoryReportQuantityState.unavailable &&
        line.uncertain == true)
      'Uncertainty reported; review stock evidence',
    if (line.factualQuantity != null)
      'Ledger quantity is not a verified physical count',
    if (line.stockUnit == null) 'Stock unit unavailable',
    if (line.pendingQuantity != null)
      'Pending quantity ${line.pendingQuantity}$unit',
    if (line.checkpointId != null)
      'An observation checkpoint anchors this ledger balance',
    if (line.balanceUpdatedAt != null)
      'Balance updated ${line.balanceUpdatedAt!.toUtc().toIso8601String()}',
    ...line.limitations,
    if (line.packText.isNotEmpty) line.packText,
    if (line.configuredMinimum != null)
      'Minimum ${line.configuredMinimum}$unit',
  ].join(' · ');
}

String _purchaseTitle(PurchaseReportTotal line) {
  final prefix = '${line.month} · ${line.currency}';
  if (line.total != null) return '$prefix ${line.total}';
  if (line.knownSubtotal != null) {
    return '$prefix ${line.knownSubtotal} known subtotal';
  }
  return '$prefix · Spend unknown';
}

String _purchaseDetail(PurchaseReportTotal line) {
  return <String>[
    '${line.receiptCount} receipt${line.receiptCount == 1 ? '' : 's'}',
    if (line.storeName != null) line.storeName!,
    switch (line.pricingComplete) {
      true => 'Complete receipt spend',
      false => 'Incomplete pricing; total spend is unknown',
      null => 'Pricing completeness unavailable in this response',
    },
    switch (line.amountSource) {
      PurchaseReportAmountSource.declared => 'Declared receipt totals',
      PurchaseReportAmountSource.derived =>
        'Derived from entered product prices',
      PurchaseReportAmountSource.mixed => 'Declared and derived receipt totals',
      PurchaseReportAmountSource.partial => 'Available amounts only',
      PurchaseReportAmountSource.unknown => 'Receipt amounts unavailable',
      PurchaseReportAmountSource.unavailable => 'Amount source unavailable',
    },
    if (line.completeReceiptCount != null)
      '${line.completeReceiptCount} completely priced',
    if (line.partialReceiptCount != null)
      '${line.partialReceiptCount} partially priced',
    if (line.unknownReceiptCount != null)
      '${line.unknownReceiptCount} with unknown prices',
  ].join(' · ');
}

final class _ReadyReport extends StatelessWidget {
  const _ReadyReport({required this.report, required this.onRefresh});

  final HouseholdReport report;
  final Future<void> Function() onRefresh;

  List<Widget> _sections() {
    // Current responses identify their sources even when every data list is
    // empty. Never select a legacy model merely because a report has no rows.
    if (report.sourceReports.isNotEmpty) {
      return <Widget>[
        _ReportSection(
          title: 'Inventory quantities',
          icon: Icons.inventory_2_outlined,
          emptyText: 'No inventory facts are available.',
          children: report.inventoryFacts
              .map(
                (line) => _ReportRow(
                  title: line.productName,
                  detail: _inventoryDetail(line),
                ),
              )
              .toList(growable: false),
        ),
        _ReportSection(
          title: 'Monthly purchases',
          icon: Icons.calendar_month_outlined,
          emptyText: 'No committed purchase totals are available.',
          children: report.purchaseTotals
              .map(
                (line) => _ReportRow(
                  title: _purchaseTitle(line),
                  detail: _purchaseDetail(line),
                ),
              )
              .toList(growable: false),
        ),
        _ReportSection(
          title: 'Consumption estimates',
          icon: Icons.insights_outlined,
          emptyText: 'No consumption estimates are available.',
          children: report.consumptionEstimates
              .map(
                (line) => _ReportRow(
                  title: '${line.productName} · ${line.confidenceBand.name}',
                  detail: <String>[
                    'Estimated quantity/day ${line.dailyRate}',
                    '${line.sampleIntervals} intervals over ${line.coverageDays} days',
                    ...line.limitations,
                  ].join(' · '),
                ),
              )
              .toList(growable: false),
        ),
        _ReportSection(
          title: 'Shopping suggestions',
          icon: Icons.shopping_cart_outlined,
          emptyText: 'No shopping suggestions are available.',
          children: report.shoppingSuggestions
              .map(
                (line) => _ReportRow(
                  title: line.productName,
                  detail:
                      'Suggested quantity ${line.requiredQuantity}'
                      '${line.packText.isEmpty ? '' : ' · ${line.packText}'}'
                      ' · ${line.status} · ${line.confidenceBand.name} confidence',
                ),
              )
              .toList(growable: false),
        ),
        _ReportSection(
          title: 'Suggestion price comparisons',
          icon: Icons.price_check_outlined,
          emptyText: 'No comparable suggestion prices are available.',
          children: report.suggestionPriceComparisons
              .map(
                (line) => _ReportRow(
                  title: line.productName ?? line.packText ?? 'Pack comparison',
                  detail:
                      '${line.currency} ${line.effectiveTotal}'
                      ' · ${line.packCount} packs'
                      '${line.storeName == null ? '' : ' · ${line.storeName}'}'
                      '${line.selected ? ' · Selected' : ''}'
                      '${line.reason.isEmpty ? '' : ' · ${line.reason}'}',
                ),
              )
              .toList(growable: false),
        ),
        _ReportSection(
          title: 'Report sources',
          icon: Icons.info_outline_rounded,
          emptyText: 'No report metadata is available.',
          children: report.sourceReports
              .map(
                (source) => _ReportRow(
                  title: source.kind.name,
                  detail: <String>[
                    'As of ${source.asOf.toUtc().toIso8601String()}',
                    if (source.quantitySemantics != null)
                      source.quantitySemantics!,
                    if (source.currencyPolicy != null) source.currencyPolicy!,
                  ].join(' · '),
                ),
              )
              .toList(growable: false),
        ),
      ];
    }

    return <Widget>[
      _ReportSection(
        title: 'Balances by location',
        icon: Icons.inventory_2_outlined,
        emptyText: 'No movement-based balances are available.',
        children: report.balances
            .map(
              (line) => _ReportRow(
                title: line.productName,
                detail:
                    '${line.quantity} ${line.unit} · ${line.locationName}'
                    '${line.hasDataQualityWarning ? ' · Check data' : ''}',
              ),
            )
            .toList(growable: false),
      ),
      _ReportSection(
        title: 'Movement ledger',
        icon: Icons.swap_vert_rounded,
        emptyText: 'No stock movements are available.',
        children: report.movements
            .map(
              (line) => _ReportRow(
                title: line.productName,
                detail:
                    '${line.movementType}: ${line.signedQuantity} ${line.unit}'
                    '${line.reversalOfMovementId == null ? '' : ' · reversal'}',
              ),
            )
            .toList(growable: false),
      ),
      _ReportSection(
        title: 'Monthly purchases',
        icon: Icons.calendar_month_outlined,
        emptyText: 'No approved monthly purchase facts are available.',
        children: report.monthlyPurchases
            .map(
              (line) => _ReportRow(
                title: line.productName,
                detail:
                    '${line.yearMonth}: ${line.originalQuantity} '
                    '${line.originalUnit}'
                    '${line.normalizedBaseQuantity == null ? '' : ' · '
                              '${line.normalizedBaseQuantity} '
                              '${line.normalizedBaseUnit} normalized'}',
              ),
            )
            .toList(growable: false),
      ),
      _ReportSection(
        title: 'Consumption evidence',
        icon: Icons.insights_outlined,
        emptyText: 'No reliable count interval is available.',
        children: report.consumption
            .map(
              (line) => _ReportRow(
                title: '${line.productName} · ${line.confidence.name}',
                detail: line.hasEstimate
                    ? '${line.estimatedDailyBaseQuantity} ${line.baseUnit}/day'
                          ' from ${line.eligibleIntervalCount} intervals'
                    : line.limitation,
              ),
            )
            .toList(growable: false),
      ),
      _ReportSection(
        title: 'Count variance',
        icon: Icons.rule_rounded,
        emptyText: 'No physical-count variance is available.',
        children: report.countVariances
            .map(
              (line) => _ReportRow(
                title: line.productName,
                detail:
                    '${line.locationName}: ${line.variance} ${line.unit} '
                    'variance',
              ),
            )
            .toList(growable: false),
      ),
      _ReportSection(
        title: 'Private price observations',
        icon: Icons.price_check_outlined,
        emptyText: 'No approved price observations are available.',
        children: report.prices
            .map(
              (line) => _ReportRow(
                title: '${line.productName} · ${line.packText}',
                detail:
                    '${line.currency} ${line.netPrice} at ${line.storeName} · '
                    '${line.observationCount} observation'
                    '${line.observationCount == 1 ? '' : 's'}'
                    '${line.comparable ? '' : ' · insufficient comparison'}',
              ),
            )
            .toList(growable: false),
      ),
      _ReportSection(
        title: 'Unresolved lines',
        icon: Icons.help_outline_rounded,
        emptyText: 'No unresolved purchase or count lines.',
        children: report.unresolved
            .map(
              (line) => _ReportRow(
                title: line.rawDescription,
                detail: line.sourceType,
              ),
            )
            .toList(growable: false),
      ),
      _ReportSection(
        title: 'Suggestion feedback',
        icon: Icons.feedback_outlined,
        emptyText: 'No suggestion feedback is available.',
        children: report.suggestionFeedback
            .map(
              (line) => _ReportRow(
                title: line.productName,
                detail: '${line.action} · ${line.algorithmVersion}',
              ),
            )
            .toList(growable: false),
      ),
      _BacktestSection(backtest: report.backtest),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: Focus(
        autofocus: true,
        child: CustomScrollView(
          primary: true,
          key: const Key('household-report-scroll'),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Household reports',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const Text(
                            'Private to the selected home · evidence-aware',
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh reports',
                      onPressed: () {
                        unawaited(onRefresh());
                      },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Scroll this page to see every report row. Sections expand to show all their records.',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.list(
                children: [
                  for (final section in _sections())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: section,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ReportSection extends StatelessWidget {
  const _ReportSection({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final IconData icon;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const Divider(),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(emptyText, textAlign: TextAlign.center),
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

final class _BacktestSection extends StatelessWidget {
  const _BacktestSection({required this.backtest});

  final BacktestCoverageReport? backtest;

  @override
  Widget build(BuildContext context) {
    final value = backtest;
    return _ReportSection(
      title: 'Suggestion evaluation',
      icon: Icons.science_outlined,
      emptyText:
          'No reliable historical periods are available for backtesting.',
      children: value == null
          ? const <Widget>[]
          : <Widget>[
              _ReportRow(
                title: value.algorithmVersion,
                detail:
                    'Coverage ${_percent(value.coverage)} · '
                    'precision ${_percent(value.precision)}',
              ),
              _ReportRow(
                title: 'Outcome evidence',
                detail:
                    '${value.missedStockOutCount} missed stock-outs · '
                    '${value.overbuyBaseQuantity} overbuy · '
                    '${_percent(value.overrideRate)} overrides',
              ),
            ],
    );
  }

  String _percent(double? value) {
    return value == null ? 'not available' : '${(value * 100).round()}%';
  }
}

final class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(detail),
    );
  }
}

final class _ReportMessage extends StatelessWidget {
  const _ReportMessage({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Future<void> Function() action;
  final String actionLabel;

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
                    unawaited(action());
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
