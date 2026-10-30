import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/purchase_services.dart';
import 'package:providentia/features/purchasing/domain/receipt_spend.dart';
import 'package:providentia/features/purchasing/presentation/receipt_spend_card.dart';

void main() {
  test(
    'declared receipt spend survives missing prices and explicit discounts',
    () {
      final receipt = _receipt(
        'declared',
        total: 850,
        lines: [
          _line('discount', total: 700, unitPrice: 500, quantity: 2),
          _line('unknown'),
        ],
      );
      final spend = ReceiptSpendAmount.fromReceipt(receipt);
      expect(spend.amount, _money(850));
      expect(spend.source, ReceiptSpendSource.declared);
      expect(spend.products.knownTotal, _money(700));
      expect(spend.products.isComplete, isFalse);
      expect(spend.products.difference, isNull);
      expect(
        ReceiptSpendSummary.fromReceipts(
          homeId: 'home-a',
          receipts: [receipt],
        ).singleCurrencyAmount,
        _money(850),
      );
    },
  );

  test(
    'unit-price derivation rounds per line HALF_UP; explicit totals win',
    () {
      final spend = ReceiptSpendAmount.fromReceipt(
        _receipt(
          'derived',
          lines: [
            _line('derived', unitPrice: 1, quantity: 0.5),
            _line('discount', unitPrice: 1000, quantity: 2, total: 1750),
          ],
        ),
      );
      expect(spend.amount, _money(1751));
      expect(spend.source, ReceiptSpendSource.derived);
      expect(spend.pricedLineCount, 2);
    },
  );

  test('partial, unknown, zero and empty evidence remain distinct', () {
    final partial = ReceiptSpendAmount.fromReceipt(
      _receipt(
        'partial',
        lines: [_line('priced', total: 0), _line('unpriced')],
      ),
    );
    expect(partial.amount, isNull);
    expect(partial.knownSubtotal, _money(0));
    expect(partial.source, ReceiptSpendSource.partial);
    final unknown = ReceiptSpendAmount.fromReceipt(
      _receipt('unknown', lines: [_line('no-price')]),
    );
    expect(unknown.amount, isNull);
    expect(unknown.knownSubtotal, isNull);
    expect(unknown.source, ReceiptSpendSource.unknown);
    expect(ReceiptSpendAmount.fromReceipt(_receipt('empty')).amount, isNull);
    expect(
      ReceiptSpendAmount.fromReceipt(_receipt('zero', total: 0)).amount,
      _money(0),
    );
    expect(
      ReceiptSpendAmount.fromReceipt(
        _receipt('line-zero', lines: [_line('zero', total: 0)]),
      ).amount,
      _money(0),
    );
  });

  test(
    'headers counted once; incomplete receipt subtotals never certify spend',
    () {
      final summary = ReceiptSpendSummary.fromReceipts(
        homeId: 'home-a',
        receipts: [
          _receipt(
            'header',
            total: 1000,
            lines: [_line('one', total: 500), _line('two', total: 600)],
          ),
          _receipt(
            'partial',
            lines: [_line('priced', total: 200), _line('unpriced')],
          ),
          _receipt('unknown'),
          _receipt('draft', total: 99999, status: PurchaseReceiptStatus.draft),
        ],
      );
      final row = summary.currencies.single;
      expect(summary.receiptCount, 3);
      expect(row.amount, isNull);
      expect(row.knownSubtotal, _money(1200));
      expect(row.completeReceiptCount, 1);
      expect(row.partialReceiptCount, 1);
      expect(row.unknownReceiptCount, 1);
    },
  );

  test(
    'header and product edits keep receipt spend and discrepancy separate',
    () {
      final original = ReceiptSpendAmount.fromReceipt(
        _receipt('same', total: 850, lines: [_line('product', total: 1000)]),
      );
      final lineEdited = ReceiptSpendAmount.fromReceipt(
        _receipt('same', total: 850, lines: [_line('product', total: 900)]),
      );
      final headerEdited = ReceiptSpendAmount.fromReceipt(
        _receipt('same', total: 900, lines: [_line('product', total: 900)]),
      );
      expect(original.amount, _money(850));
      expect(original.products.difference, _money(-150));
      expect(lineEdited.amount, _money(850));
      expect(lineEdited.products.difference, _money(-50));
      expect(headerEdited.amount, _money(900));
      expect(headerEdited.products.difference, _money(0));
    },
  );

  test('large multi-receipt sums never silently round cents on web', () {
    final summary = ReceiptSpendSummary.fromReceipts(
      homeId: 'home-a',
      receipts: [
        _receipt('large', total: 9007199254740991),
        _receipt('small', total: 1),
      ],
    );
    expect(summary.currencies.single.knownSubtotal, isNull);
    expect(summary.singleCurrencyAmount, isNull);
  });

  test('calendar bounds are inclusive and currencies never mix', () {
    final summary = ReceiptSpendSummary.fromReceipts(
      homeId: 'home-a',
      fromDate: DateTime.utc(2026, 10, 1),
      throughDate: DateTime.utc(2026, 10, 26),
      receipts: [
        _receipt('start', total: 100, date: DateTime.utc(2026, 10, 1)),
        _receipt('end', total: 200, currency: 'USD'),
        _receipt('outside', total: 10000, date: DateTime.utc(2026, 9, 30)),
      ],
    );
    expect(summary.currencies.map((row) => row.currency), ['NAD', 'USD']);
    expect(summary.currencies.first.amount, _money(100));
    expect(summary.currencies.last.amount, _money(200, 'USD'));
    expect(summary.singleCurrencyAmount, isNull);
  });

  test('home isolation and duplicate receipt identities fail closed', () {
    expect(
      () => ReceiptSpendSummary.fromReceipts(
        homeId: 'home-b',
        receipts: [_receipt('a')],
      ),
      throwsStateError,
    );
    expect(
      () => ReceiptSpendSummary.fromReceipts(
        homeId: 'home-a',
        receipts: [_receipt('a'), _receipt('a')],
      ),
      throwsStateError,
    );
    expect(
      () => const PurchaseHistoryGrouper().groupRecent(
        homeId: 'home-b',
        lines: [],
        receipts: [_receipt('a')],
      ),
      throwsStateError,
    );
  });

  test('header-only receipts remain grouped after last-line removal', () {
    final receipt = _receipt('header-only', total: 7500);
    final groups = const PurchaseHistoryGrouper().groupRecent(
      homeId: 'home-a',
      lines: [],
      receipts: [receipt],
    );
    expect(groups.single.id, 'receipt:header-only');
    expect(groups.single.lines, isEmpty);
    expect(groups.single.receipt, same(receipt));
    expect(
      ReceiptSpendAmount.fromReceipt(groups.single.receipt!).amount,
      _money(7500),
    );
  });

  testWidgets(
    'spending loading and failed reads do not claim an empty receipt history',
    (tester) async {
      final empty = ReceiptSpendSummary.fromReceipts(
        homeId: 'home-a',
        receipts: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptSpendCard(summary: empty, hasLoaded: false),
          ),
        ),
      );
      expect(find.text('Loading saved receipt spending…'), findsOneWidget);
      expect(find.text('No finished receipt spending recorded.'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptSpendCard(
              summary: empty,
              hasLoaded: false,
              readFailed: true,
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Receipt spending is unavailable'),
        findsOneWidget,
      );
      expect(find.text('No finished receipt spending recorded.'), findsNothing);
    },
  );

  testWidgets(
    'spend card separates currencies and incomplete product breakdown',
    (tester) async {
      final summary = ReceiptSpendSummary.fromReceipts(
        homeId: 'home-a',
        receipts: [
          _receipt('header', total: 1000, lines: [_line('unknown')]),
          _receipt('foreign', total: 250, currency: 'USD'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReceiptSpendCard(summary: summary)),
        ),
      );
      expect(find.text('NAD 10.00'), findsOneWidget);
      expect(find.text('USD 2.50'), findsOneWidget);
      expect(
        find.textContaining('Currencies are shown separately'),
        findsOneWidget,
      );
      expect(
        find.textContaining('entered-products breakdown is incomplete'),
        findsNWidgets(2),
      );
      expect(find.textContaining('all saved purchase dates'), findsOneWidget);
    },
  );
}

Money _money(int minor, [String currency = 'NAD']) =>
    Money(minorUnits: minor, currency: currency);

PurchaseReceiptCapture _receipt(
  String id, {
  int? total,
  String currency = 'NAD',
  DateTime? date,
  PurchaseReceiptStatus status = PurchaseReceiptStatus.committed,
  List<PurchaseReceiptLineCapture> lines = const [],
}) => PurchaseReceiptCapture(
  id: id,
  homeId: 'home-a',
  purchaseDate: date ?? DateTime.utc(2026, 10, 26),
  currency: currency,
  total: total == null ? null : _money(total, currency),
  notes: '',
  revision: 1,
  status: status,
  synchronizationState: PurchaseSynchronizationState.synchronized,
  lines: [
    for (final line in lines)
      PurchaseReceiptLineCapture(
        id: line.id,
        homeId: line.homeId,
        receiptId: id,
        rawDescription: line.rawDescription,
        quantity: line.quantity,
        quantityText: line.quantityText,
        revision: line.revision,
        approvalStatus: line.approvalStatus,
        synchronizationState: line.synchronizationState,
        lineTotal: line.lineTotal,
        unitPrice: line.unitPrice,
      ),
  ],
);

PurchaseReceiptLineCapture _line(
  String id, {
  int? total,
  int? unitPrice,
  double quantity = 1,
}) => PurchaseReceiptLineCapture(
  id: id,
  homeId: 'home-a',
  receiptId: 'receipt',
  rawDescription: 'Synthetic product',
  quantity: quantity,
  quantityText: quantity.toString(),
  lineTotal: total == null ? null : _money(total),
  unitPrice: unitPrice == null ? null : _money(unitPrice),
  revision: 1,
  approvalStatus: PurchaseLineApprovalStatus.unresolved,
  synchronizationState: PurchaseSynchronizationState.synchronized,
);
