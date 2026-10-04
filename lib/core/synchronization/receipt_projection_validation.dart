import 'package:providentia/core/synchronization/sync_models.dart';

/// Validate the purchasing feed before persisting either records or a cursor.
/// Feed representations omit envelope metadata and are not HTTP Receipt DTOs.
/// Decimal strings remain strings: accepting JSON numbers here would conceal a
/// server contract error and lose precision before purchase history renders.
void validateReceiptProjection(RemoteChange change) {
  if (change.entityType != 'purchasing-receipt' &&
      change.entityType != 'purchasing-receipt-line') {
    return;
  }
  final value = change.payload;
  if (change.revision < 1 ||
      (value['id'] != null && value['id'] != change.entityId) ||
      (value['homeId'] != null && value['homeId'] != change.homeId) ||
      (value['revision'] != null && value['revision'] != change.revision)) {
    throw const FormatException('Receipt readback identity was invalid.');
  }
  if (change.kind != RemoteChangeKind.upsert) return;
  if (change.entityType == 'purchasing-receipt') {
    _oneOf(value, 'status', {'draft', 'committed', 'cancelled'});
    final date = _text(value, 'purchaseDate');
    final parsed = DateTime.tryParse(date);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date) {
      throw const FormatException('Receipt purchase date was invalid.');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(_text(value, 'currency'))) {
      throw const FormatException('Receipt currency was invalid.');
    }
    _optionalText(value, 'storeId');
    _optionalText(value, 'notes');
    _optionalText(value, 'sourceReference');
    _decimal(value, 'totalAmount', optional: true);
  } else {
    _text(value, 'receiptId');
    _text(value, 'rawDescription');
    _decimal(value, 'quantity', positive: true);
    _decimal(value, 'unitPrice', optional: true);
    _decimal(value, 'lineTotal', optional: true);
    _optionalText(value, 'originalPackText');
    _optionalText(value, 'homeProductId');
    _oneOf(value, 'approvalStatus', {
      'unreviewed',
      'approved',
      'approved-catalog',
      'unresolved',
      'removed',
    });
    final approval = value['approvalStatus'];
    if (((approval == 'approved' || approval == 'approved-catalog') &&
            value['homeProductId'] == null) ||
        (approval == 'unresolved' && value['homeProductId'] != null)) {
      throw const FormatException('Receipt line review binding was invalid.');
    }
  }
}

String _text(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! String || result.trim().isEmpty) {
    throw FormatException('Receipt $key must be a non-empty string.');
  }
  return result;
}

void _optionalText(Map<String, Object?> value, String key) {
  if (value[key] != null && value[key] is! String) {
    throw FormatException('Receipt $key must be a string.');
  }
}

void _oneOf(Map<String, Object?> value, String key, Set<String> allowed) {
  if (!allowed.contains(_text(value, key))) {
    throw FormatException('Receipt $key was invalid.');
  }
}

void _decimal(
  Map<String, Object?> value,
  String key, {
  bool optional = false,
  bool positive = false,
}) {
  if (optional && value[key] == null) return;
  final text = _text(value, key);
  final parsed = double.tryParse(text);
  if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$').hasMatch(text) ||
      parsed == null ||
      !parsed.isFinite ||
      parsed < 0 ||
      (positive && parsed == 0)) {
    throw FormatException('Receipt $key must be a valid decimal string.');
  }
}
