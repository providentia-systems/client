import 'package:http/http.dart' as http;
import 'package:providentia/features/shopping/application/online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Closed, home-scoped mapping boundary for the generated shopping-
/// intelligence operations. No response map or backend problem detail leaves
/// this adapter.
final class GeneratedOnlineShoppingSuggestionRepository
    implements OnlineShoppingSuggestionRepository {
  GeneratedOnlineShoppingSuggestionRepository(
    this._client, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ProvidentiaApiClient _client;
  final DateTime Function() _clock;

  @override
  Future<ShoppingSuggestionFeed> list({required String homeId}) =>
      _run(() async {
        _uuidValue(homeId, 'homeId');
        final body = (await _client.listShoppingSuggestions(
          homeId: homeId,
        )).requireObject();
        _rejectCrossHomeValue(body, homeId);
        final suggestions = _objectList(
          body,
          'data',
        ).map((row) => _suggestion(row, homeId)).toList(growable: false);
        if (suggestions.map((row) => row.id).toSet().length !=
            suggestions.length) {
          throw const FormatException(
            'The suggestion feed contains duplicate identifiers.',
          );
        }
        return ShoppingSuggestionFeed(
          suggestions: suggestions,
          fromVerifiedCache: false,
          verifiedAt: _clock().toUtc(),
        );
      });

  @override
  Future<OnlineShoppingSuggestionExplanation> explanation({
    required String homeId,
    required String suggestionId,
  }) => _run(() async {
    _uuidValue(homeId, 'homeId');
    _uuidValue(suggestionId, 'suggestionId');
    final body = (await _client.getShoppingSuggestionExplanation(
      homeId: homeId,
      suggestionId: suggestionId,
    )).requireObject();
    _rejectCrossHomeValue(body, homeId);
    final parsed = _explanation(body, homeId);
    if (parsed.id != suggestionId) {
      throw const FormatException(
        'The explanation does not match the requested suggestion.',
      );
    }
    return parsed;
  });

  @override
  Future<OnlineSuggestionFeedbackReceipt> recordFeedback(
    OnlineSuggestionFeedback feedback,
  ) => _run(() async {
    _uuidValue(feedback.homeId, 'homeId');
    _uuidValue(feedback.suggestionId, 'suggestionId');
    final body = (await _client.createShoppingSuggestionFeedback(
      homeId: feedback.homeId,
      suggestionId: feedback.suggestionId,
      body: <String, Object?>{
        'decision': switch (feedback.decision) {
          OnlineSuggestionDecision.accepted => 'accepted',
          OnlineSuggestionDecision.edited => 'edited',
          OnlineSuggestionDecision.dismissed => 'dismissed',
          OnlineSuggestionDecision.snoozed => 'snoozed',
        },
        'resultQuantity': feedback.resultQuantity?.value,
        'reason': feedback.reason,
      },
    )).requireObject();
    _rejectCrossHomeValue(body, feedback.homeId);
    return OnlineSuggestionFeedbackReceipt(id: _uuid(body, 'id'));
  });

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on OnlineSuggestionException {
      rethrow;
    } on ProvidentiaApiException catch (error) {
      throw OnlineSuggestionException(switch (error.statusCode) {
        401 => OnlineSuggestionFailureKind.authenticationRequired,
        403 || 404 => OnlineSuggestionFailureKind.authorizationDenied,
        _ => OnlineSuggestionFailureKind.unavailable,
      });
    } on FormatException {
      throw const OnlineSuggestionException(
        OnlineSuggestionFailureKind.invalidResponse,
      );
    } on ArgumentError {
      throw const OnlineSuggestionException(
        OnlineSuggestionFailureKind.invalidResponse,
      );
    } on http.ClientException {
      throw const OnlineSuggestionException(
        OnlineSuggestionFailureKind.unavailable,
      );
    }
  }
}

OnlineShoppingSuggestion _suggestion(
  Map<String, Object?> object,
  String homeId,
) {
  final status = switch (_string(object, 'status')) {
    'active' => OnlineShoppingSuggestionStatus.active,
    'accepted' => OnlineShoppingSuggestionStatus.accepted,
    'dismissed' => OnlineShoppingSuggestionStatus.dismissed,
    'snoozed' => OnlineShoppingSuggestionStatus.snoozed,
    _ => throw const FormatException('Unknown suggestion status.'),
  };
  final confidence = _confidence(object, 'confidenceBand');
  final asOf = _dateTime(object, 'asOf');
  final expiresAt = _dateTime(object, 'expiresAt');
  return OnlineShoppingSuggestion(
    id: _uuid(object, 'id'),
    homeId: homeId,
    homeProductId: _uuid(object, 'homeProductId'),
    productName: _nonEmptyString(object, 'productName'),
    packText: _optionalString(object['packText']),
    expectedDemand: _decimal(object, 'expectedDemand'),
    safetyStock: _decimal(object, 'safetyStock'),
    factualStock: _decimal(object, 'factualStock'),
    usableStock: _decimal(object, 'usableStock'),
    requiredQuantity: _decimal(object, 'requiredQuantity'),
    selectedPackId: _optionalUuid(object['selectedPackId']),
    packCount: _optionalInteger(object['packCount']),
    confidenceScore: _decimal(object, 'confidenceScore'),
    confidenceBand: confidence,
    status: status,
    expiresAt: expiresAt,
    modelVersion: _nonEmptyString(object, 'modelVersion'),
    asOf: asOf,
    inputWatermark: _watermark(object, 'inputWatermark'),
  );
}

OnlineShoppingSuggestionExplanation _explanation(
  Map<String, Object?> object,
  String homeId,
) {
  return OnlineShoppingSuggestionExplanation(
    id: _uuid(object, 'id'),
    homeId: homeId,
    homeProductId: _uuid(object, 'homeProductId'),
    requiredQuantity: _decimal(object, 'requiredQuantity'),
    confidenceScore: _decimal(object, 'confidenceScore'),
    confidenceBand: _confidence(object, 'confidenceBand'),
    factors: _objectList(
      object,
      'factors',
    ).map(_factor).toList(growable: false),
    limitations: _stringList(object, 'limitations'),
    packOptions: _objectList(
      object,
      'packOptions',
    ).map(_packOption).toList(growable: false),
    modelVersion: _nonEmptyString(object, 'modelVersion'),
    asOf: _dateTime(object, 'asOf'),
    inputWatermark: _watermark(object, 'inputWatermark'),
  );
}

ShoppingSuggestionFactor _factor(Map<String, Object?> object) {
  const allowedKeys = <String>{
    'expected-demand',
    'purchase-cadence',
    'minimum-reserve',
    'factual-stock',
    'required-quantity',
  };
  final key = _nonEmptyString(object, 'key');
  if (!allowedKeys.contains(key)) {
    throw const FormatException('Unknown suggestion evidence factor.');
  }
  final value = object['value'];
  final days = object['days'];
  final nextShoppingAt = object['nextExpectedShoppingAt'];
  return ShoppingSuggestionFactor(
    key: key,
    value: value == null ? null : _decimalValue(value, 'factor.value'),
    days: days == null ? null : _integerValue(days, 'factor.days'),
    nextExpectedShoppingAt: nextShoppingAt == null
        ? null
        : _dateTimeValue(nextShoppingAt, 'factor.nextExpectedShoppingAt'),
  );
}

SuggestionPackOption _packOption(Map<String, Object?> object) {
  final currency = _string(object, 'currency');
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
    throw const FormatException('Invalid price-option currency.');
  }
  return SuggestionPackOption(
    packId: _uuid(object, 'packId'),
    storeId: _optionalUuid(object['storeId']),
    currency: currency,
    packCount: _integer(object, 'packCount'),
    effectiveTotal: _decimal(object, 'effectiveTotal'),
    excessQuantity: _decimal(object, 'excessQuantity'),
    priceObservedAt: _dateTime(object, 'priceObservedAt'),
    selected: _boolean(object, 'selected'),
    reason: _nonEmptyString(object, 'reason'),
  );
}

List<Map<String, Object?>> _objectList(
  Map<String, Object?> object,
  String key,
) {
  final value = object[key];
  if (value is! List<Object?>) {
    throw FormatException('Expected "$key" to be a list.');
  }
  return value.map((entry) => _object(entry, key)).toList(growable: false);
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected $label to be an object.');
  }
  return value;
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String) {
    throw FormatException('Expected "$key" to be a string.');
  }
  return value;
}

String _nonEmptyString(Map<String, Object?> object, String key) {
  final value = _string(object, key);
  if (value.trim().isEmpty || value.length > 500) {
    throw FormatException('Expected "$key" to contain bounded text.');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.length > 500) {
    throw const FormatException('Expected optional bounded text.');
  }
  return value;
}

String _uuid(Map<String, Object?> object, String key) =>
    _uuidValue(_string(object, key), key);

String _uuidValue(String value, String label) {
  if (!_uuidPattern.hasMatch(value)) {
    throw FormatException('Expected "$label" to be a UUID.');
  }
  return value;
}

String? _optionalUuid(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Expected an optional UUID.');
  }
  return _uuidValue(value, 'optional UUID');
}

ExactDecimal _decimal(Map<String, Object?> object, String key) =>
    _decimalValue(object[key], key);

ExactDecimal _decimalValue(Object? value, String label) {
  if (value is! String) {
    throw FormatException('Expected "$label" to be an exact decimal.');
  }
  try {
    return ExactDecimal(value);
  } on ArgumentError {
    throw FormatException('Expected "$label" to be an exact decimal.');
  }
}

int _integer(Map<String, Object?> object, String key) =>
    _integerValue(object[key], key);

int _integerValue(Object? value, String label) {
  if (value is! int || value < 0) {
    throw FormatException('Expected "$label" to be a non-negative integer.');
  }
  return value;
}

int? _optionalInteger(Object? value) {
  if (value == null) return null;
  return _integerValue(value, 'optional integer');
}

bool _boolean(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! bool) {
    throw FormatException('Expected "$key" to be a boolean.');
  }
  return value;
}

DateTime _dateTime(Map<String, Object?> object, String key) =>
    _dateTimeValue(object[key], key);

DateTime _dateTimeValue(Object? value, String label) {
  if (value is! String || !_offsetDateTime.hasMatch(value)) {
    throw FormatException('Expected "$label" to be an offset date-time.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Expected "$label" to be a date-time.');
  }
  return parsed.toUtc();
}

ShoppingSuggestionConfidenceBand _confidence(
  Map<String, Object?> object,
  String key,
) => switch (_string(object, key)) {
  'low' => ShoppingSuggestionConfidenceBand.low,
  'medium' => ShoppingSuggestionConfidenceBand.medium,
  'high' => ShoppingSuggestionConfidenceBand.high,
  _ => throw const FormatException('Unknown suggestion confidence band.'),
};

String _watermark(Map<String, Object?> object, String key) {
  final value = _string(object, key);
  if (!_watermarkPattern.hasMatch(value)) {
    throw FormatException('Expected "$key" to be a SHA-256 watermark.');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! List<Object?> ||
      value.any(
        (entry) =>
            entry is! String || entry.trim().isEmpty || entry.length > 500,
      )) {
    throw FormatException('Expected "$key" to be a bounded string list.');
  }
  final strings = value.cast<String>();
  if (strings.toSet().length != strings.length) {
    throw FormatException('Expected "$key" to contain unique values.');
  }
  return List<String>.unmodifiable(strings);
}

void _rejectCrossHomeValue(Object? value, String expectedHomeId) {
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      if (entry.key == 'homeId' && entry.value != expectedHomeId) {
        throw const FormatException('Cross-home response value rejected.');
      }
      _rejectCrossHomeValue(entry.value, expectedHomeId);
    }
  } else if (value is List<Object?>) {
    for (final entry in value) {
      _rejectCrossHomeValue(entry, expectedHomeId);
    }
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _watermarkPattern = RegExp(r'^[a-f0-9]{64}$');
final RegExp _offsetDateTime = RegExp(r'(?:Z|[+-]\d{2}:\d{2})$');
