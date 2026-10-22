import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/receipt_price_widgets.dart';

void main() {
  testWidgets(
    'saved sum changes with readback, removal and receipt selection',
    (tester) async {
      Future<void> show(
        List<PurchaseReceiptLineCapture> lines,
        int? expected,
      ) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptAmountSummary(
              receipt: _receipt(lines, expected: expected),
            ),
          ),
        ),
      );
      await show([_line(total: 62550)], 85000);
      expect(find.text('Products entered: NAD 625.50'), findsOneWidget);
      expect(find.text('Remaining: NAD 224.50'), findsOneWidget);

      await show([_line(total: 85000)], 85000);
      expect(find.text('Difference: NAD 0.00'), findsOneWidget);
      await show([_line(total: 90000)], 85000);
      expect(find.text('Over by: NAD 50.00'), findsOneWidget);
      await show([], null);
      expect(find.text('Products entered: NAD 0.00'), findsOneWidget);
      expect(find.text('Receipt total: Not entered'), findsOneWidget);
      expect(find.textContaining('Difference unavailable'), findsOneWidget);
      expect(find.text('Over by: NAD 50.00'), findsNothing);
    },
  );

  testWidgets('unknown price stays incomplete but explicit zero balances', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReceiptAmountSummary(receipt: _receipt([_line()], expected: 0)),
        ),
      ),
    );
    expect(find.byKey(const Key('receipt-incomplete-prices')), findsOneWidget);
    expect(find.text('Difference: NAD 0.00'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReceiptAmountSummary(
            receipt: _receipt([_line(total: 0)], expected: 0),
          ),
        ),
      ),
    );
    expect(find.text('Difference: NAD 0.00'), findsOneWidget);
  });

  testWidgets('price details separate purchased pack amount from stock', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final line = _line(quantity: '4', unitPrice: 3250);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ReceiptLinePriceDetails(line: line, currency: 'NAD'),
          ),
        ),
      ),
    );
    expect(find.text('4 × 1 kg @ NAD 32.50 = NAD 130.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit discounted amount is visible with discrepancy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReceiptLinePriceDetails(
            line: _line(quantity: '4', unitPrice: 2500, total: 9000),
            currency: 'NAD',
          ),
        ),
      ),
    );
    expect(find.text('4 × 1 kg @ NAD 25.00 = NAD 90.00'), findsOneWidget);
    expect(find.textContaining('NAD 100.00'), findsOneWidget);
  });

  testWidgets(
    'overflowing comparison retains explicit preview and saved price',
    (tester) async {
      final quantity = TextEditingController(text: '999999999');
      final unitPrice = TextEditingController(text: '999999999999.99');
      final lineTotal = TextEditingController(text: '90');
      addTearDown(quantity.dispose);
      addTearDown(unitPrice.dispose);
      addTearDown(lineTotal.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ReceiptLinePricePreview(
                    quantity: quantity,
                    unitPrice: unitPrice,
                    lineTotal: lineTotal,
                    currency: 'NAD',
                  ),
                  ReceiptLinePriceDetails(
                    line: _line(
                      quantity: '999999999',
                      unitPrice: 99999999999999,
                      total: 9000,
                    ),
                    currency: 'NAD',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('NAD 90.00 (entered amount)'), findsOneWidget);
      expect(find.textContaining('= NAD 90.00'), findsOneWidget);
      expect(
        find.textContaining('comparison is unavailable'),
        findsNWidgets(2),
      );
      expect(
        find.byKey(const Key('receipt-line-preview-discrepancy')),
        findsNothing,
      );
      expect(lineTotal.text, '90');
      lineTotal.clear();
      await tester.pump();
      expect(find.textContaining('NAD 90.00 (entered amount)'), findsNothing);
      expect(
        find.textContaining('Unsaved line preview: The receipt amount exceeds'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsaved preview responds without changing saved sum', (
    tester,
  ) async {
    final quantity = TextEditingController(text: '4');
    final unitPrice = TextEditingController(text: '32.50');
    final lineTotal = TextEditingController();
    addTearDown(quantity.dispose);
    addTearDown(unitPrice.dispose);
    addTearDown(lineTotal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ReceiptAmountSummary(receipt: _receipt([], expected: 85000)),
              ReceiptLinePricePreview(
                quantity: quantity,
                unitPrice: unitPrice,
                lineTotal: lineTotal,
                currency: 'NAD',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.textContaining('NAD 130.00 (calculated)'), findsOneWidget);
    expect(find.text('Products entered: NAD 0.00'), findsOneWidget);
    lineTotal.text = '90';
    await tester.pump();
    expect(find.textContaining('NAD 90.00 (entered amount)'), findsOneWidget);
    expect(
      find.byKey(const Key('receipt-line-preview-discrepancy')),
      findsOneWidget,
    );
    quantity.text = '';
    await tester.pump();
    expect(find.textContaining('Use a quantity'), findsOneWidget);
    expect(find.textContaining('Unsaved line preview:'), findsOneWidget);
    expect(find.text('Products entered: NAD 0.00'), findsOneWidget);
    unitPrice.text = '-1';
    await tester.pump();
    expect(find.textContaining('non-negative amount'), findsOneWidget);
    expect(find.text('Products entered: NAD 0.00'), findsOneWidget);
  });
}

PurchaseReceiptCapture _receipt(
  List<PurchaseReceiptLineCapture> lines, {
  int? expected,
}) => PurchaseReceiptCapture(
  id: 'receipt',
  homeId: 'home',
  purchaseDate: DateTime.utc(2026, 10, 22),
  currency: 'NAD',
  total: expected == null ? null : Money(minorUnits: expected, currency: 'NAD'),
  notes: '',
  revision: 1,
  status: PurchaseReceiptStatus.draft,
  synchronizationState: PurchaseSynchronizationState.pending,
  lines: lines,
);

PurchaseReceiptLineCapture _line({
  String quantity = '1',
  int? unitPrice,
  int? total,
}) => PurchaseReceiptLineCapture(
  id: 'line',
  homeId: 'home',
  receiptId: 'receipt',
  rawDescription: 'A long product name that still needs a readable price',
  quantity: double.parse(quantity),
  quantityText: quantity,
  originalPackText: '1 kg',
  unitPrice: unitPrice == null
      ? null
      : Money(minorUnits: unitPrice, currency: 'NAD'),
  lineTotal: total == null ? null : Money(minorUnits: total, currency: 'NAD'),
  revision: 1,
  approvalStatus: PurchaseLineApprovalStatus.unresolved,
  synchronizationState: PurchaseSynchronizationState.pending,
);
