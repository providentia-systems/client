/// Exact fixed-scale purchasing arithmetic. Transport quantities never pass
/// through binary floating point before multiplication or balance addition.
final class PurchaseQuantity {
  PurchaseQuantity._(this._scaled);
  factory PurchaseQuantity.parse(String text, {bool positive = false}) {
    if (!RegExp(r'^-?(?:0|[1-9][0-9]{0,8})(?:\.[0-9]{1,8})?$').hasMatch(text)) {
      throw ArgumentError('Use a quantity with at most eight decimal places.');
    }
    final negative = text.startsWith('-');
    final parts = (negative ? text.substring(1) : text).split('.');
    final scaled =
        BigInt.parse(parts.first) * _scale +
        BigInt.parse(parts.length == 1 ? '0' : parts.last.padRight(8, '0'));
    final value = negative ? -scaled : scaled;
    if (positive && value <= BigInt.zero) {
      throw ArgumentError('The purchased quantity must be positive.');
    }
    return PurchaseQuantity._(value);
  }
  static final BigInt _scale = BigInt.from(100000000);
  final BigInt _scaled;
  PurchaseQuantity operator +(PurchaseQuantity other) =>
      PurchaseQuantity._(_scaled + other._scaled);
  PurchaseQuantity operator -(PurchaseQuantity other) =>
      PurchaseQuantity._(_scaled - other._scaled);
  PurchaseQuantity operator *(PurchaseQuantity other) {
    final product = _scaled * other._scaled;
    if (product.remainder(_scale) != BigInt.zero) {
      throw ArgumentError(
        'This pack quantity needs more than eight decimal places.',
      );
    }
    return PurchaseQuantity._(product ~/ _scale);
  }

  PurchaseQuantity operator /(PurchaseQuantity other) {
    if (other._scaled <= BigInt.zero) {
      throw ArgumentError('A pack conversion denominator must be positive.');
    }
    final numerator = _scaled * _scale;
    if (numerator.remainder(other._scaled) != BigInt.zero) {
      throw ArgumentError(
        'This pack conversion needs more than eight decimal places.',
      );
    }
    return PurchaseQuantity._(numerator ~/ other._scaled);
  }

  PurchaseQuantity divideByThousand() {
    if (_scaled.remainder(BigInt.from(1000)) != BigInt.zero) {
      throw ArgumentError(
        'This pack conversion needs more than eight decimal places.',
      );
    }
    return PurchaseQuantity._(_scaled ~/ BigInt.from(1000));
  }

  bool get isNegative => _scaled.isNegative;
  @override
  String toString() {
    final value = _scaled.abs();
    final whole = value ~/ _scale;
    final fraction = (value % _scale)
        .toString()
        .padLeft(8, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '${_scaled.isNegative ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
  }
}

/// Convert a published pack to the home stock measurement without interpreting
/// packaging text. Both sides use catalog normalized measurement snapshots.
PurchaseQuantity purchasePackConversionFactor({
  required String stockUnit,
  required String? selectedAmount,
  required String? selectedUnit,
  String? baseAmount,
  String? baseUnit,
  bool selectedIsBasePack = false,
}) {
  if (stockUnit == 'units') {
    if (selectedIsBasePack) return PurchaseQuantity.parse('1');
    if (baseAmount != null) {
      if (baseUnit != selectedUnit || selectedAmount == null) {
        throw ArgumentError(
          'Choose a pack with the same measurement as the stock base pack.',
        );
      }
      return PurchaseQuantity.parse(selectedAmount, positive: true) /
          PurchaseQuantity.parse(baseAmount, positive: true);
    }
    if (selectedUnit != 'units' || selectedAmount == null) {
      throw ArgumentError(
        'Choose a stock measurement or a base pack before using this pack.',
      );
    }
    return PurchaseQuantity.parse(selectedAmount, positive: true);
  }
  if (selectedAmount == null ||
      ((stockUnit == 'g' || stockUnit == 'kg')
          ? selectedUnit != 'g'
          : (stockUnit == 'ml' || stockUnit == 'l')
          ? selectedUnit != 'ml'
          : true)) {
    throw ArgumentError(
      'This pack cannot be converted to the stock measurement.',
    );
  }
  final amount = PurchaseQuantity.parse(selectedAmount, positive: true);
  return stockUnit == 'kg' || stockUnit == 'l'
      ? amount.divideByThousand()
      : amount;
}
