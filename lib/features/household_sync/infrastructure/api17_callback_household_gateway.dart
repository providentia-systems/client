import 'package:providentia/features/household_sync/application/household_api17_ports.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

final class Api17RawResponse {
  const Api17RawResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Object? body;
}

typedef Api17ListHomeStockCall =
    Future<Api17RawResponse> Function({
      required String homeId,
      required Map<String, String> headers,
    });

typedef Api17CreateStockAdjustmentCall =
    Future<Api17RawResponse> Function({
      required String homeId,
      required Map<String, Object?> body,
      required Map<String, String> headers,
    });

/// Small compatibility bridge around the generated API 1.7 client.
///
/// Callbacks keep this production adapter compilable while the generated 1.7
/// client is staged as `providentia_api_client.next.dart`. Bootstrap supplies
/// callbacks that invoke `listHomeStock` and `createStockAdjustment` after the
/// generated client promotion.
final class Api17CallbackHouseholdGateway implements HouseholdApi17Gateway {
  const Api17CallbackHouseholdGateway({
    required SessionAuthorizer authorizer,
    required Api17ListHomeStockCall listHomeStock,
    required Api17CreateStockAdjustmentCall createStockAdjustment,
  }) : _authorizer = authorizer,
       _listHomeStock = listHomeStock,
       _createStockAdjustment = createStockAdjustment;

  final SessionAuthorizer _authorizer;
  final Api17ListHomeStockCall _listHomeStock;
  final Api17CreateStockAdjustmentCall _createStockAdjustment;

  @override
  Future<List<Api17HomeStockRecord>> listHomeStock(String homeId) async {
    final response = await _authorized(
      (headers) => _listHomeStock(homeId: homeId, headers: headers),
    );
    try {
      final object = _object(response.body);
      final data = object['data'];
      if (data is! List<Object?>) {
        throw const FormatException('Expected a data array.');
      }
      return immutableList(data.map(_stockRecord));
    } on FormatException {
      throw _invalidResponse();
    } on ArgumentError {
      throw _invalidResponse();
    }
  }

  @override
  Future<Api17StockMovementReceipt> createHomeLevelStockAdjustment(
    Api17HomeLevelStockAdjustment adjustment,
  ) async {
    final response = await _authorized(
      (headers) => _createStockAdjustment(
        homeId: adjustment.homeId,
        headers: <String, String>{
          ...headers,
          'Idempotency-Key': adjustment.operationId,
        },
        body: <String, Object?>{
          'homeProductId': adjustment.homeProductId,
          'quantityDelta': _decimal(adjustment.quantityDelta),
          'reason': adjustment.reason.trim(),
          'operationId': adjustment.operationId,
        },
      ),
    );
    try {
      final object = _object(response.body);
      final receipt = Api17StockMovementReceipt(
        id: _string(object, 'id'),
        homeId: _string(object, 'homeId'),
        homeProductId: _string(object, 'homeProductId'),
        quantityDelta: _numberString(object, 'quantityDelta'),
        sourceId: _string(object, 'sourceId'),
        occurredAt: _dateTime(object, 'occurredAt'),
      );
      if (receipt.homeId != adjustment.homeId ||
          receipt.homeProductId != adjustment.homeProductId ||
          (receipt.quantityDelta - adjustment.quantityDelta).abs() >
              0.000000001) {
        throw const FormatException('Adjustment response did not match.');
      }
      return receipt;
    } on FormatException {
      throw _invalidResponse();
    }
  }

  Future<Api17RawResponse> _authorized(
    Future<Api17RawResponse> Function(Map<String, String> headers) request,
  ) async {
    if (!await _authorizer.ensureFresh()) {
      throw const HouseholdApiException(
        kind: HouseholdApiFailureKind.authentication,
        safeMessage: 'Sign in again to access household data.',
        statusCode: 401,
      );
    }
    Api17RawResponse response;
    try {
      response = await request(_headers());
    } on HouseholdApiException {
      rethrow;
    } on Exception {
      throw const HouseholdApiException(
        kind: HouseholdApiFailureKind.network,
        safeMessage: 'Household data could not be reached.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _statusFailure(response.statusCode);
    }
    return response;
  }

  Map<String, String> _headers() => <String, String>{
    if (_authorizer.sessionTransport == ClientSessionTransport.nativeBearer &&
        _authorizer.accessToken != null)
      'Authorization': 'Bearer ${_authorizer.accessToken}',
    if (_authorizer.sessionTransport == ClientSessionTransport.webCookie &&
        _authorizer.csrfToken != null)
      'X-CSRF-Token': _authorizer.csrfToken!,
  };
}

Api17HomeStockRecord _stockRecord(Object? value) {
  final object = _object(value);
  return Api17HomeStockRecord(
    id: _string(object, 'id'),
    homeId: _string(object, 'homeId'),
    productId: _optionalString(object['productId']),
    packId: _optionalString(object['packId']),
    privateName: _optionalString(object['privateName']),
    originalPackText: _optionalString(object['originalPackText']),
    productName: _optionalString(object['productName']),
    brandName: _optionalString(object['brandName']),
    categoryId: _optionalString(object['categoryId']),
    quantity: _numberString(object, 'quantity'),
    revision: _integer(object, 'revision'),
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected an object.');
  }
  return value;
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String? _optionalString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

double _numberString(Map<String, Object?> object, String key) {
  final parsed = double.tryParse(_string(object, key));
  if (parsed == null || !parsed.isFinite) {
    throw FormatException('Invalid $key.');
  }
  return parsed;
}

int _integer(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is int) return value;
  throw FormatException('Invalid $key.');
}

DateTime _dateTime(Map<String, Object?> object, String key) {
  final value = DateTime.tryParse(_string(object, key));
  if (value == null) throw FormatException('Invalid $key.');
  return value.toUtc();
}

String _decimal(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'must be finite');
  }
  var encoded = value.toStringAsFixed(8);
  encoded = encoded.replaceFirst(RegExp(r'0+$'), '');
  encoded = encoded.replaceFirst(RegExp(r'\.$'), '');
  final parsed = double.parse(encoded);
  if ((parsed - value).abs() > 0.000000001 ||
      !RegExp(
        r'^-?(?:0|[1-9][0-9]{0,8})(?:\.[0-9]{1,8})?$',
      ).hasMatch(encoded)) {
    throw ArgumentError.value(
      value,
      'value',
      'cannot be represented by the API decimal contract',
    );
  }
  return encoded;
}

HouseholdApiException _invalidResponse() => const HouseholdApiException(
  kind: HouseholdApiFailureKind.invalidResponse,
  safeMessage: 'The server returned invalid household data.',
);

HouseholdApiException _statusFailure(int statusCode) {
  final kind = switch (statusCode) {
    401 => HouseholdApiFailureKind.authentication,
    403 || 404 => HouseholdApiFailureKind.authorization,
    409 => HouseholdApiFailureKind.conflict,
    400 || 422 => HouseholdApiFailureKind.validation,
    >= 500 => HouseholdApiFailureKind.unavailable,
    _ => HouseholdApiFailureKind.network,
  };
  final message = switch (kind) {
    HouseholdApiFailureKind.authentication =>
      'Sign in again to access household data.',
    HouseholdApiFailureKind.authorization =>
      'This session cannot access the selected home.',
    HouseholdApiFailureKind.conflict =>
      'Household data changed on another device. Refresh and try again.',
    HouseholdApiFailureKind.validation =>
      'The household change was not accepted.',
    _ => 'The household service is temporarily unavailable.',
  };
  return HouseholdApiException(
    kind: kind,
    safeMessage: message,
    statusCode: statusCode,
  );
}
