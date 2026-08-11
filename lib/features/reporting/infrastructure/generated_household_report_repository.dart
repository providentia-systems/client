import 'package:http/http.dart' as http;
import 'package:providentia/features/reporting/application/household_report_service.dart';
import 'package:providentia/features/reporting/domain/household_report.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Current-contract adapter for the four independently audited home reports.
///
/// No response map crosses this boundary. Every envelope and row is mapped
/// through a closed parser, and any nested `homeId` supplied by the server is
/// required to match the route home before the result is constructed.
final class GeneratedHouseholdReportRepository
    implements HouseholdReportRepository {
  const GeneratedHouseholdReportRepository(this._client);

  final ProvidentiaApiClient _client;

  @override
  Future<HouseholdReport> load({required String homeId}) {
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
    return _run(() async {
      final responses = await Future.wait<ApiResponse>(<Future<ApiResponse>>[
        _client.getInventoryReport(homeId: homeId),
        _client.getPurchaseReport(homeId: homeId),
        _client.getConsumptionReport(homeId: homeId),
        _client.getSuggestionReport(homeId: homeId),
      ]);
      final inventory = _report(
        responses[0],
        expectedHomeId: homeId,
        expectedKind: HouseholdReportKind.inventory,
      );
      final purchases = _report(
        responses[1],
        expectedHomeId: homeId,
        expectedKind: HouseholdReportKind.purchases,
      );
      final consumption = _report(
        responses[2],
        expectedHomeId: homeId,
        expectedKind: HouseholdReportKind.consumption,
      );
      final suggestions = _report(
        responses[3],
        expectedHomeId: homeId,
        expectedKind: HouseholdReportKind.suggestions,
      );
      final reports = <_ParsedReport>[
        inventory,
        purchases,
        consumption,
        suggestions,
      ];
      final generatedAt = reports
          .map((report) => report.metadata.asOf)
          .reduce((left, right) => left.isAfter(right) ? left : right);

      return HouseholdReport(
        homeId: homeId,
        generatedAt: generatedAt,
        sourceReports: reports
            .map((report) => report.metadata)
            .toList(growable: false),
        inventoryFacts: inventory.data
            .map((row) => _inventoryFact(row, homeId))
            .toList(growable: false),
        purchaseTotals: purchases.data
            .map((row) => _purchaseTotal(row, homeId))
            .toList(growable: false),
        consumptionEstimates: consumption.data
            .map((row) => _consumptionEstimate(row, homeId))
            .toList(growable: false),
        shoppingSuggestions: suggestions.data
            .map((row) => _suggestion(row, homeId))
            .toList(growable: false),
        suggestionPriceComparisons: suggestions.priceComparisons
            .map((row) => _priceComparison(row, homeId))
            .toList(growable: false),
      );
    });
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ReportRepositoryException {
      rethrow;
    } on ProvidentiaApiException catch (error) {
      throw ReportRepositoryException(switch (error.statusCode) {
        401 => ReportRepositoryFailureKind.authenticationRequired,
        403 || 404 => ReportRepositoryFailureKind.forbidden,
        409 => ReportRepositoryFailureKind.conflict,
        _ => ReportRepositoryFailureKind.unavailable,
      });
    } on FormatException {
      throw const ReportRepositoryException(
        ReportRepositoryFailureKind.invalidResponse,
      );
    } on ArgumentError {
      throw const ReportRepositoryException(
        ReportRepositoryFailureKind.invalidResponse,
      );
    } on http.ClientException {
      throw const ReportRepositoryException(
        ReportRepositoryFailureKind.unavailable,
      );
    }
  }
}

final class _ParsedReport {
  const _ParsedReport({
    required this.metadata,
    required this.data,
    required this.priceComparisons,
  });

  final HouseholdReportMetadata metadata;
  final List<Map<String, Object?>> data;
  final List<Map<String, Object?>> priceComparisons;
}

_ParsedReport _report(
  ApiResponse response, {
  required String expectedHomeId,
  required HouseholdReportKind expectedKind,
}) {
  final object = response.requireObject();
  _rejectCrossHomeValue(object, expectedHomeId);
  final kind = switch (_string(object, 'type')) {
    'inventory' => HouseholdReportKind.inventory,
    'purchases' => HouseholdReportKind.purchases,
    'consumption' => HouseholdReportKind.consumption,
    'suggestions' => HouseholdReportKind.suggestions,
    _ => throw const FormatException('Unknown home report type.'),
  };
  if (kind != expectedKind) {
    throw const FormatException('Home report operation/type mismatch.');
  }
  final data = _objectList(object, 'data');
  final comparisons = object['priceComparisons'] == null
      ? const <Map<String, Object?>>[]
      : _objectList(object, 'priceComparisons');
  if (kind != HouseholdReportKind.suggestions && comparisons.isNotEmpty) {
    throw const FormatException('Unexpected report price comparisons.');
  }
  return _ParsedReport(
    metadata: HouseholdReportMetadata(
      homeId: expectedHomeId,
      kind: kind,
      asOf: _dateTime(object, 'asOf'),
      quantitySemantics: _optionalString(object['quantitySemantics']),
      currencyPolicy: _optionalString(object['currencyPolicy']),
      from: _optionalDate(object['from']),
      through: _optionalDate(object['through']),
    ),
    data: data,
    priceComparisons: comparisons,
  );
}

InventoryReportFact _inventoryFact(Map<String, Object?> object, String homeId) {
  return InventoryReportFact(
    homeId: homeId,
    homeProductId: _uuid(object, 'homeProductId'),
    productName: _string(object, 'productName'),
    packText: _string(object, 'packText', allowEmpty: true),
    factualQuantity: _decimal(object, 'factualQuantity'),
    balanceRevision: _optionalPositiveInteger(object['balanceRevision']),
    lastMovementId: _optionalUuid(object['lastMovementId']),
    balanceUpdatedAt: _optionalDateTime(object['balanceUpdatedAt']),
    configuredMinimum: _optionalDecimal(object['configuredMinimum']),
    alwaysKeep: _optionalBoolean(object['alwaysKeep']),
    neverSuggest: _optionalBoolean(object['neverSuggest']),
  );
}

PurchaseReportTotal _purchaseTotal(Map<String, Object?> object, String homeId) {
  final month = _string(object, 'month');
  final currency = _string(object, 'currency');
  if (!_monthPattern.hasMatch(month) || !_currencyPattern.hasMatch(currency)) {
    throw const FormatException('Invalid purchase report key.');
  }
  return PurchaseReportTotal(
    homeId: homeId,
    month: month,
    currency: currency,
    storeId: _optionalUuid(object['storeId']),
    storeName: _optionalString(object['storeName']),
    receiptCount: _nonNegativeInteger(object, 'receiptCount'),
    total: _decimal(object, 'total'),
  );
}

ConsumptionReportEstimate _consumptionEstimate(
  Map<String, Object?> object,
  String homeId,
) {
  return ConsumptionReportEstimate(
    homeId: homeId,
    id: _uuid(object, 'id'),
    homeProductId: _uuid(object, 'homeProductId'),
    productName: _string(object, 'productName'),
    method: _string(object, 'method'),
    dailyRate: _decimal(object, 'dailyRate'),
    variability: _decimal(object, 'variability'),
    sampleIntervals: _nonNegativeInteger(object, 'sampleIntervals'),
    coverageDays: _nonNegativeInteger(object, 'coverageDays'),
    purchaseSamples: _nonNegativeInteger(object, 'purchaseSamples'),
    purchaseCadenceDays: _optionalPositiveInteger(
      object['purchaseCadenceDays'],
    ),
    nextExpectedShoppingAt: _optionalDateTime(object['nextExpectedShoppingAt']),
    confidenceScore: _confidence(object, 'confidenceScore'),
    confidenceBand: _confidenceBand(object, 'confidenceBand'),
    evidenceFrom: _optionalDateTime(object['evidenceFrom']),
    evidenceTo: _optionalDateTime(object['evidenceTo']),
    limitations: _stringList(object, 'limitations'),
    asOf: _dateTime(object, 'asOf'),
    inputWatermark: _watermark(object, 'inputWatermark'),
  );
}

ShoppingSuggestionReportLine _suggestion(
  Map<String, Object?> object,
  String homeId,
) {
  final status = _string(object, 'status');
  if (!const <String>{
    'active',
    'accepted',
    'dismissed',
    'snoozed',
  }.contains(status)) {
    throw const FormatException('Invalid shopping suggestion status.');
  }
  return ShoppingSuggestionReportLine(
    homeId: homeId,
    id: _uuid(object, 'id'),
    homeProductId: _uuid(object, 'homeProductId'),
    productName: _string(object, 'productName'),
    packText: _string(object, 'packText', allowEmpty: true),
    expectedDemand: _decimal(object, 'expectedDemand'),
    safetyStock: _decimal(object, 'safetyStock'),
    factualStock: _decimal(object, 'factualStock'),
    usableStock: _decimal(object, 'usableStock'),
    requiredQuantity: _decimal(object, 'requiredQuantity'),
    selectedPackId: _optionalUuid(object['selectedPackId']),
    packCount: _optionalNonNegativeInteger(object['packCount']),
    confidenceScore: _confidence(object, 'confidenceScore'),
    confidenceBand: _confidenceBand(object, 'confidenceBand'),
    status: status,
    expiresAt: _dateTime(object, 'expiresAt'),
    modelVersion: _string(object, 'modelVersion'),
    asOf: _dateTime(object, 'asOf'),
    inputWatermark: _watermark(object, 'inputWatermark'),
  );
}

SuggestionPriceComparisonReportLine _priceComparison(
  Map<String, Object?> object,
  String homeId,
) {
  final currency = _string(object, 'currency');
  if (!_currencyPattern.hasMatch(currency)) {
    throw const FormatException('Invalid comparison currency.');
  }
  return SuggestionPriceComparisonReportLine(
    homeId: homeId,
    suggestionId: _optionalUuid(object['suggestionId']),
    homeProductId: _optionalUuid(object['homeProductId']),
    productName: _optionalString(object['productName']),
    packId: _uuid(object, 'packId'),
    packText: _optionalString(object['packText'], allowEmpty: true),
    storeId: _optionalUuid(object['storeId']),
    storeName: _optionalString(object['storeName']),
    currency: currency,
    packCount: _nonNegativeInteger(object, 'packCount'),
    effectiveTotal: _decimal(object, 'effectiveTotal'),
    excessQuantity: _decimal(object, 'excessQuantity'),
    priceObservedAt: _dateTime(object, 'priceObservedAt'),
    selected: _boolean(object, 'selected'),
    reason: _string(object, 'reason', allowEmpty: true),
  );
}

void _rejectCrossHomeValue(Object? value, String expectedHomeId) {
  if (value is Map<String, Object?>) {
    if (value.containsKey('homeId') && value['homeId'] != expectedHomeId) {
      throw const FormatException('Cross-home report data rejected.');
    }
    for (final nested in value.values) {
      _rejectCrossHomeValue(nested, expectedHomeId);
    }
  } else if (value is List<Object?>) {
    for (final nested in value) {
      _rejectCrossHomeValue(nested, expectedHomeId);
    }
  }
}

List<Map<String, Object?>> _objectList(
  Map<String, Object?> object,
  String key,
) {
  final value = object[key];
  if (value is! List<Object?>) {
    throw FormatException('Missing $key list.');
  }
  return value
      .map((item) {
        if (item is! Map<String, Object?>) {
          throw FormatException('Invalid $key item.');
        }
        return item;
      })
      .toList(growable: false);
}

List<String> _stringList(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('Invalid $key list.');
  }
  return value.cast<String>().toList(growable: false);
}

String _string(
  Map<String, Object?> object,
  String key, {
  bool allowEmpty = false,
}) {
  final value = object[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String? _optionalString(Object? value, {bool allowEmpty = false}) {
  if (value == null) {
    return null;
  }
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw const FormatException('Invalid optional string.');
  }
  return value;
}

String _uuid(Map<String, Object?> object, String key) {
  final value = _string(object, key);
  if (!_uuidPattern.hasMatch(value)) {
    throw FormatException('Invalid $key UUID.');
  }
  return value;
}

String? _optionalUuid(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String || !_uuidPattern.hasMatch(value)) {
    throw const FormatException('Invalid optional UUID.');
  }
  return value;
}

String _decimal(Map<String, Object?> object, String key) {
  final value = object[key];
  final normalized = value is String
      ? value
      : value is num
      ? '$value'
      : null;
  if (normalized == null || !_decimalPattern.hasMatch(normalized)) {
    throw FormatException('Invalid $key fixed decimal.');
  }
  return normalized;
}

String? _optionalDecimal(Object? value) {
  if (value == null) {
    return null;
  }
  final normalized = value is String
      ? value
      : value is num
      ? '$value'
      : null;
  if (normalized == null || !_decimalPattern.hasMatch(normalized)) {
    throw const FormatException('Invalid optional fixed decimal.');
  }
  return normalized;
}

String _confidence(Map<String, Object?> object, String key) {
  final value = _string(object, key);
  if (!_confidencePattern.hasMatch(value)) {
    throw FormatException('Invalid $key confidence.');
  }
  return value;
}

String _watermark(Map<String, Object?> object, String key) {
  final value = _string(object, key);
  if (!_watermarkPattern.hasMatch(value)) {
    throw FormatException('Invalid $key watermark.');
  }
  return value;
}

EvidenceConfidence _confidenceBand(Map<String, Object?> object, String key) {
  return switch (_string(object, key)) {
    'low' => EvidenceConfidence.low,
    'medium' => EvidenceConfidence.medium,
    'high' => EvidenceConfidence.high,
    _ => throw FormatException('Invalid $key confidence band.'),
  };
}

int _nonNegativeInteger(Map<String, Object?> object, String key) {
  final value = _integerValue(object[key]);
  if (value == null || value < 0) {
    throw FormatException('Invalid $key integer.');
  }
  return value;
}

int? _optionalNonNegativeInteger(Object? value) {
  if (value == null) {
    return null;
  }
  final parsed = _integerValue(value);
  if (parsed == null || parsed < 0) {
    throw const FormatException('Invalid optional integer.');
  }
  return parsed;
}

int? _optionalPositiveInteger(Object? value) {
  final parsed = _optionalNonNegativeInteger(value);
  if (parsed != null && parsed < 1) {
    throw const FormatException('Expected a positive integer.');
  }
  return parsed;
}

int? _integerValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
    return int.tryParse(value);
  }
  return null;
}

bool _boolean(Map<String, Object?> object, String key) {
  final value = _optionalBoolean(object[key]);
  if (value == null) {
    throw FormatException('Invalid $key boolean.');
  }
  return value;
}

bool? _optionalBoolean(Object? value) {
  return switch (value) {
    null => null,
    true || 1 || '1' => true,
    false || 0 || '0' => false,
    _ => throw const FormatException('Invalid optional boolean.'),
  };
}

DateTime _dateTime(Map<String, Object?> object, String key) {
  final value = DateTime.tryParse(_string(object, key));
  if (value == null) {
    throw FormatException('Invalid $key date-time.');
  }
  return value.toUtc();
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('Invalid optional date-time.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('Invalid optional date-time.');
  }
  return parsed.toUtc();
}

DateTime? _optionalDate(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String || !_datePattern.hasMatch(value)) {
    throw const FormatException('Invalid optional date.');
  }
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Invalid optional calendar date.');
  }
  return parsed;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _decimalPattern = RegExp(r'^-?(?:0|[1-9]\d{0,8})(?:\.\d{1,8})?$');
final RegExp _confidencePattern = RegExp(
  r'^(?:0(?:\.\d{1,4})?|1(?:\.0{1,4})?)$',
);
final RegExp _watermarkPattern = RegExp(r'^[a-f0-9]{64}$');
final RegExp _monthPattern = RegExp(r'^\d{4}-(?:0[1-9]|1[0-2])$');
final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
