import 'package:http/http.dart' as http;
import 'package:providentia/features/purchasing/application/purchase_receipt_history.dart';
import 'package:providentia/features/purchasing/domain/purchase_calendar.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Uses ordinary authenticated household reads. This never changes membership,
/// clears local work, or substitutes an HTTP result for queued local intent.
final class GeneratedPurchaseReceiptHistoryReader
    implements PurchaseReceiptHistoryReader {
  const GeneratedPurchaseReceiptHistoryReader(this._api);
  final ProvidentiaApiClient _api;

  @override
  Future<PurchaseReceiptHistorySnapshot> load({
    required String homeId,
    required String receiptId,
  }) async {
    try {
      _uuidValue(homeId);
      _uuidValue(receiptId);
      final responses = await Future.wait([
        _api.getReceipt(homeId: homeId, receiptId: receiptId),
        _api.listReceiptDateCorrections(homeId: homeId, receiptId: receiptId),
        _api.listReceiptLineCorrections(homeId: homeId, receiptId: receiptId),
      ]);
      final receipt = responses[0].requireObject();
      if (_uuid(receipt, 'id') != receiptId ||
          _uuid(receipt, 'homeId') != homeId) {
        throw const FormatException('Receipt history binding mismatch.');
      }
      final entries = <PurchaseReceiptAuditEntry>[];
      final auditIds = <String>{};
      for (var index = 1; index < responses.length; index++) {
        final body = responses[index].requireObject();
        if ((body['homeId'] != null && _uuid(body, 'homeId') != homeId) ||
            (body['receiptId'] != null &&
                _uuid(body, 'receiptId') != receiptId) ||
            (body.containsKey('data') && body.containsKey('corrections'))) {
          throw const FormatException('Ambiguous correction history binding.');
        }
        // API 2.4 publishes `data`. Older responses used `corrections`; its
        // rows receive the same identity checks and cannot override `data`.
        final rows = body.containsKey('data')
            ? body['data']
            : body['corrections'];
        if (rows is! List<Object?>) {
          throw const FormatException('Invalid correction history.');
        }
        for (final raw in rows) {
          if (raw is! Map<String, Object?> ||
              _uuid(raw, 'receiptId') != receiptId ||
              (raw['homeId'] != null && _uuid(raw, 'homeId') != homeId)) {
            throw const FormatException('Correction history binding mismatch.');
          }
          final auditId = _uuid(raw, 'id');
          if (!auditIds.add(auditId.toLowerCase())) {
            throw const FormatException(
              'Duplicate correction history identity.',
            );
          }
          final next = raw['nextLine'];
          if (index == 2) {
            final lineId = _uuid(raw, 'lineId');
            _validateLine(
              raw['originalLine'],
              homeId,
              receiptId,
              lineId,
              nullable: true,
            );
            _validateLine(next, homeId, receiptId, lineId);
          } else if (raw['originalLine'] != null || next != null) {
            throw const FormatException(
              'Unexpected line history on a date correction.',
            );
          }
          for (final key in ['originalPurchaseDate', 'purchaseDate']) {
            if (raw[key] != null) parsePurchaseDay(_text(raw, key));
          }
          entries.add(
            PurchaseReceiptAuditEntry(
              id: auditId,
              kind: index == 1 ? 'Purchase day correction' : 'Line correction',
              reason: _text(raw, 'reason'),
              at: _date(raw['correctedAt']),
              state: PurchaseReceiptAuditState.accepted,
              originalPurchaseDay: _optional(raw['originalPurchaseDate']),
              purchaseDay: _optional(raw['purchaseDate']),
              lineDescription: next is Map<String, Object?>
                  ? _optional(next['rawDescription'])
                  : null,
            ),
          );
        }
      }
      return PurchaseReceiptHistorySnapshot(
        homeId: homeId,
        receiptId: receiptId,
        createdAt: receipt['createdAt'] == null
            ? null
            : _date(receipt['createdAt']),
        entries: List.unmodifiable(entries),
      );
    } on PurchaseReceiptHistoryException {
      rethrow;
    } on ProvidentiaApiException catch (error) {
      throw PurchaseReceiptHistoryException(switch (error.statusCode) {
        401 =>
          'Sign in again to refresh receipt history. Saved work is retained.',
        403 || 404 =>
          'Receipt history is unavailable with the current household permissions. Saved work is retained.',
        _ =>
          'Receipt history could not be refreshed. Saved history and pending work are retained.',
      });
    } on FormatException {
      throw const PurchaseReceiptHistoryException(
        'The receipt history response was invalid. Saved history is retained.',
      );
    } on http.ClientException {
      throw const PurchaseReceiptHistoryException(
        'Connect to refresh receipt history. Saved history remains available.',
      );
    }
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String _uuidValue(Object? value) {
  if (value is! String || !_uuidPattern.hasMatch(value)) {
    throw const FormatException('Invalid receipt history identity.');
  }
  return value;
}

String _uuid(Map<String, Object?> row, String key) => _uuidValue(row[key]);

void _validateLine(
  Object? value,
  String homeId,
  String receiptId,
  String lineId, {
  bool nullable = false,
}) {
  if (value == null && nullable) return;
  if (value is! Map<String, Object?> ||
      _uuid(value, 'id') != lineId ||
      _uuid(value, 'receiptId') != receiptId ||
      (value['lineId'] != null && _uuid(value, 'lineId') != lineId) ||
      (value['homeId'] != null && _uuid(value, 'homeId') != homeId)) {
    throw const FormatException(
      'Nested receipt-line history binding mismatch.',
    );
  }
}

String _text(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid history text.');
  }
  return value;
}

String? _optional(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Invalid optional history text.');
  }
  return value;
}

DateTime _date(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid history timestamp.');
  }
  final normalized =
      RegExp(
        r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{1,6})?$',
      ).hasMatch(value)
      ? '${value.replaceFirst(' ', 'T')}Z'
      : value;
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d)$',
  ).hasMatch(normalized)) {
    throw const FormatException('Invalid history timestamp.');
  }
  parsePurchaseDay(normalized.substring(0, 10));
  return DateTime.parse(normalized).toUtc();
}
