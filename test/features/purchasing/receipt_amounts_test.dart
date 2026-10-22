import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/receipt_amounts.dart';

void main() {
  group('exact purchased line amounts', () {
    test('uses purchased pack count instead of converted stock quantity', () {
      final line = _line(
        quantity: 4,
        quantityText: '4',
        unitPrice: _money(3250),
        stockQuantity: '4000',
      );
      final amounts = ReceiptLineAmounts.resolve(line, currency: 'NAD');
      expect(amounts.total, _money(13000));
      expect(amounts.calculatedTotal, _money(13000));
      expect(amounts.hasDiscrepancy, isFalse);
      expect(amounts.error, isNull);
      expect(
        ReceiptLineAmounts.resolve(
          _line(quantity: 1, unitPrice: _money(13000), stockQuantity: '4000'),
          currency: 'NAD',
        ).total,
        _money(13000),
      );
    });

    test('rounds each decimal quantity HALF_UP at the minor-unit boundary', () {
      for (final entry in <String, int>{
        '0.49999999': 0,
        '0.5': 1,
        '0.50000001': 1,
        '1.49999999': 1,
        '1.5': 2,
        '2.5': 3,
      }.entries) {
        expect(
          calculatePurchasedLineTotal(
            quantityText: entry.key,
            unitPrice: _money(1),
          ),
          _money(entry.value),
          reason: entry.key,
        );
      }
      expect(
        calculatePurchasedLineTotal(
          quantityText: '1.23456789',
          unitPrice: _money(3250),
        ),
        _money(4012),
      );
    });

    test('keeps an explicit discounted total and flags its discrepancy', () {
      final amounts = ReceiptLineAmounts.resolve(
        _line(quantity: 4, unitPrice: _money(2500), total: _money(9000)),
        currency: 'NAD',
      );
      expect(amounts.total, _money(9000));
      expect(amounts.calculatedTotal, _money(10000));
      expect(amounts.hasDiscrepancy, isTrue);
    });

    test('retains valid explicit zero or total when comparison overflows', () {
      for (final entered in [0, 9000]) {
        final line = _line(
          quantity: 999999999,
          quantityText: '999999999',
          unitPrice: _money(99999999999999),
          total: _money(entered),
        );
        final amounts = ReceiptLineAmounts.resolve(line, currency: 'NAD');
        expect(amounts.total, _money(entered));
        expect(amounts.calculatedTotal, isNull);
        expect(amounts.hasDiscrepancy, isFalse);
        expect(amounts.error, contains('arithmetic comparison is unavailable'));
        final receipt = ReceiptAmounts.fromReceipt(
          _receipt([line], total: _money(entered)),
        );
        expect(receipt.knownTotal, _money(entered));
        expect(receipt.isComplete, isTrue);
        expect(receipt.difference, _money(0));
      }
    });

    test('overflow without explicit amount remains unknown and actionable', () {
      final amounts = ReceiptLineAmounts.resolve(
        _line(quantity: 999999999, unitPrice: _money(99999999999999)),
        currency: 'NAD',
      );
      expect(amounts.total, isNull);
      expect(amounts.error, contains('exceeds the supported range'));
      expect(amounts.error, contains('Enter a valid receipt line total'));
      for (final invalidPrice in [-1, 9007199254740992]) {
        final invalid = ReceiptLineAmounts.resolve(
          _line(unitPrice: _money(invalidPrice), total: _money(9000)),
          currency: 'NAD',
        );
        expect(invalid.total, isNull);
        expect(invalid.error, isNotNull);
      }
    });

    test('total-only does not invent a unit price', () {
      final amounts = ReceiptLineAmounts.resolve(
        _line(quantity: 3, total: _money(1000)),
        currency: 'NAD',
      );
      expect(amounts.total, _money(1000));
      expect(amounts.calculatedTotal, isNull);
      expect(amounts.hasDiscrepancy, isFalse);
    });

    test('unknown and explicit zero amounts remain distinct', () {
      expect(
        ReceiptLineAmounts.resolve(_line(), currency: 'NAD').total,
        isNull,
      );
      expect(
        ReceiptLineAmounts.resolve(
          _line(unitPrice: _money(0)),
          currency: 'NAD',
        ).total,
        _money(0),
      );
      expect(
        ReceiptLineAmounts.resolve(
          _line(total: _money(0), unitPrice: _money(100)),
          currency: 'NAD',
        ).total,
        _money(0),
      );
    });

    test('supports scientific-notation legacy quantity without float math', () {
      final line = _line(quantity: 0.0000001, unitPrice: _money(5000000));
      expect(purchasedLineQuantityText(line), '0.0000001');
      expect(
        ReceiptLineAmounts.resolve(line, currency: 'NAD').total,
        _money(1),
      );
    });

    test('prefers exact quantity text over its double projection', () {
      final line = _line(
        quantity: 1.5,
        quantityText: '1.49999999',
        unitPrice: _money(1),
      );
      expect(
        ReceiptLineAmounts.resolve(line, currency: 'NAD').total,
        _money(1),
      );
    });

    test(
      'rejects invalid quantity, negative price and unsafe integer results',
      () {
        for (final quantity in <String>[
          '',
          '0',
          '-1',
          'NaN',
          '1e3',
          '0.000000001',
          '1000000000',
        ]) {
          expect(
            () => calculatePurchasedLineTotal(
              quantityText: quantity,
              unitPrice: _money(1),
            ),
            throwsArgumentError,
            reason: quantity,
          );
        }
        expect(
          () => calculatePurchasedLineTotal(
            quantityText: '1',
            unitPrice: _money(-1),
          ),
          throwsArgumentError,
        );
        expect(
          () => calculatePurchasedLineTotal(
            quantityText: '999999999',
            unitPrice: _money(99999999999999),
          ),
          throwsArgumentError,
        );
        final invalid = ReceiptLineAmounts.resolve(
          _line(total: _money(-1)),
          currency: 'NAD',
        );
        expect(invalid.total, isNull);
        expect(invalid.error, isNotNull);
      },
    );

    test('never counts a line with mixed or foreign currency', () {
      for (final line in <PurchaseReceiptLineCapture>[
        _line(unitPrice: _money(100, currency: 'USD')),
        _line(total: _money(100, currency: 'USD')),
        _line(
          unitPrice: _money(100, currency: 'USD'),
          total: _money(100),
        ),
      ]) {
        final result = ReceiptLineAmounts.resolve(line, currency: 'NAD');
        expect(result.total, isNull);
        expect(result.currencyMismatch, isTrue);
        expect(result.error, isNotNull);
      }
    });
  });

  group('saved receipt reconciliation', () {
    test('shows remaining, balanced and over from saved amounts', () {
      final base = <PurchaseReceiptLineCapture>[_line(total: _money(62550))];
      expect(
        ReceiptAmounts.fromReceipt(
          _receipt(base, total: _money(85000)),
        ).difference,
        _money(22450),
      );
      expect(
        ReceiptAmounts.fromReceipt(
          _receipt([
            ...base,
            _line(id: 'b', total: _money(22450)),
          ], total: _money(85000)),
        ).difference,
        _money(0),
      );
      expect(
        ReceiptAmounts.fromReceipt(
          _receipt([
            ...base,
            _line(id: 'b', total: _money(22500)),
          ], total: _money(85000)),
        ).difference,
        _money(-50),
      );
    });

    test('includes unresolved prices without stock approval implications', () {
      final result = ReceiptAmounts.fromReceipt(
        _receipt([
          _line(total: _money(100)),
          _line(
            id: 'b',
            unitPrice: _money(200),
            quantity: 2,
            status: PurchaseLineApprovalStatus.unresolved,
          ),
          _line(
            id: 'c',
            total: _money(300),
            status: PurchaseLineApprovalStatus.approved,
          ),
        ]),
      );
      expect(result.knownTotal, _money(800));
      expect(result.isComplete, isTrue);
    });

    test('unknown amounts prevent a false balanced announcement', () {
      final result = ReceiptAmounts.fromReceipt(
        _receipt([
          _line(total: _money(100)),
          _line(id: 'unknown'),
        ], total: _money(100)),
      );
      expect(result.knownTotal, _money(100));
      expect(result.unpricedLineCount, 1);
      expect(result.isComplete, isFalse);
      expect(result.difference, isNull);
    });

    test('zero expected total differs from an absent expected total', () {
      final missing = ReceiptAmounts.fromReceipt(_receipt([]));
      final zero = ReceiptAmounts.fromReceipt(_receipt([], total: _money(0)));
      expect(missing.knownTotal, _money(0));
      expect(missing.isComplete, isTrue);
      expect(missing.expectedTotal, isNull);
      expect(missing.difference, isNull);
      expect(zero.expectedTotal, _money(0));
      expect(zero.difference, _money(0));
    });

    test('rounds lines before summing rather than rounding an aggregate', () {
      final result = ReceiptAmounts.fromReceipt(
        _receipt([
          _line(quantity: 0.5, unitPrice: _money(1)),
          _line(id: 'b', quantity: 0.5, unitPrice: _money(1)),
        ]),
      );
      expect(result.knownTotal, _money(2));
    });

    test(
      'recomputes edits, removals and readback without cached double counting',
      () {
        final local = _line(quantity: 4, unitPrice: _money(3250));
        final readback = _line(
          quantity: 4,
          unitPrice: _money(3250),
          total: _money(13000),
        );
        expect(
          ReceiptAmounts.fromReceipt(_receipt([local])).knownTotal,
          _money(13000),
        );
        expect(
          ReceiptAmounts.fromReceipt(_receipt([readback])).knownTotal,
          _money(13000),
        );
        expect(
          ReceiptAmounts.fromReceipt(
            _receipt([_line(quantity: 2, unitPrice: _money(3250))]),
          ).knownTotal,
          _money(6500),
        );
        expect(ReceiptAmounts.fromReceipt(_receipt([])).knownTotal, _money(0));
      },
    );

    test(
      'discloses foreign line and expected currencies without combining them',
      () {
        final result = ReceiptAmounts.fromReceipt(
          _receipt([
            _line(total: _money(100)),
            _line(
              id: 'usd',
              total: _money(200, currency: 'USD'),
            ),
          ], total: _money(300, currency: 'USD')),
        );
        expect(result.knownTotal, _money(100));
        expect(result.currencyMismatchCount, 1);
        expect(result.unpricedLineCount, 1);
        expect(result.expectedTotal, isNull);
        expect(result.expectedTotalError, isNotNull);
        expect(result.difference, isNull);
      },
    );

    test('refuses an unsafe aggregate rather than losing cents on web', () {
      final result = ReceiptAmounts.fromReceipt(
        _receipt([
          _line(total: _money(9007199254740991)),
          _line(id: 'extra', total: _money(1)),
        ]),
      );
      expect(result.knownTotal, _money(9007199254740991));
      expect(result.unpricedLineCount, 1);
      expect(result.isComplete, isFalse);
    });
  });

  group('receipt amount input and formatting', () {
    test('parses optional values without coercing malformed inputs', () {
      expect(parseReceiptMoney(' ', currency: 'NAD'), isNull);
      expect(parseReceiptMoney('0', currency: 'NAD'), _money(0));
      expect(parseReceiptMoney('32.5', currency: 'NAD'), _money(3250));
      expect(parseReceiptMoney(' 32.50 ', currency: 'NAD'), _money(3250));
      expect(
        parseReceiptMoney('999999999999.99', currency: 'NAD'),
        _money(99999999999999),
      );
      for (final invalid in <String>[
        '-1',
        'NaN',
        '1.234',
        '1,00',
        '.5',
        '1e2',
        '1000000000000',
      ]) {
        expect(
          () => parseReceiptMoney(invalid, currency: 'NAD'),
          throwsArgumentError,
          reason: invalid,
        );
      }
      expect(
        () => parseReceiptMoney('1', currency: 'nad'),
        throwsArgumentError,
      );
    });

    test('formats exact minor units including negatives and large values', () {
      expect(formatReceiptMoney(_money(0)), 'NAD 0.00');
      expect(formatReceiptMoney(_money(1)), 'NAD 0.01');
      expect(formatReceiptMoney(_money(-50)), 'NAD -0.50');
      expect(
        formatReceiptMoney(_money(9007199254740991)),
        'NAD 90071992547409.91',
      );
    });
  });
}

Money _money(int minorUnits, {String currency = 'NAD'}) =>
    Money(minorUnits: minorUnits, currency: currency);

PurchaseReceiptLineCapture _line({
  String id = 'line',
  double quantity = 1,
  String? quantityText,
  Money? unitPrice,
  Money? total,
  String? stockQuantity,
  PurchaseLineApprovalStatus status = PurchaseLineApprovalStatus.unreviewed,
}) => PurchaseReceiptLineCapture(
  id: id,
  homeId: 'home',
  receiptId: 'receipt',
  rawDescription: 'Rice',
  quantity: quantity,
  quantityText: quantityText,
  unitPrice: unitPrice,
  lineTotal: total,
  originalPackText: '1 kg',
  stockQuantity: stockQuantity,
  stockUnit: 'g',
  homeProductId: status == PurchaseLineApprovalStatus.approved ? 'rice' : null,
  revision: 1,
  approvalStatus: status,
  synchronizationState: PurchaseSynchronizationState.pending,
);

PurchaseReceiptCapture _receipt(
  List<PurchaseReceiptLineCapture> lines, {
  Money? total,
}) => PurchaseReceiptCapture(
  id: 'receipt',
  homeId: 'home',
  purchaseDate: DateTime.utc(2026, 10, 21),
  currency: 'NAD',
  total: total,
  notes: '',
  revision: 1,
  status: PurchaseReceiptStatus.draft,
  synchronizationState: PurchaseSynchronizationState.pending,
  lines: lines,
);
