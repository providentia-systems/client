import 'package:http/http.dart' as http;
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Current-contract adapter for account and home data-governance requests.
///
/// It maps only allowlisted fields, drops backend diagnostic failure details,
/// and rejects any unexpected home attribution before returning domain values.
final class GeneratedDataGovernanceRepository
    implements DataGovernanceRepository {
  const GeneratedDataGovernanceRepository(this._client);

  final ProvidentiaApiClient _client;

  @override
  Future<DataGovernanceRequest> requestAccountExport() => _run(() async {
    final response = await _client.requestAccountDataExport();
    return _request(
      response.requireObject(),
      expectedKind: DataGovernanceRequestKind.accountExport,
      expectedScope: DataGovernanceScope.account,
    );
  });

  @override
  Future<DataGovernanceRequest> requestAccountErasure() => _run(() async {
    final response = await _client.requestAccountErasure();
    return _request(
      response.requireObject(),
      expectedKind: DataGovernanceRequestKind.accountErasure,
      expectedScope: DataGovernanceScope.account,
    );
  });

  @override
  Future<DataGovernanceRequest> requestHomeExport({required String homeId}) {
    _requireHomeId(homeId);
    return _run(() async {
      final response = await _client.requestHomeDataExport(homeId: homeId);
      return _request(
        response.requireObject(),
        expectedKind: DataGovernanceRequestKind.homeExport,
        expectedScope: DataGovernanceScope.home,
        expectedHomeId: homeId,
      );
    });
  }

  @override
  Future<DataGovernanceRequest> requestHomeErasure({required String homeId}) {
    _requireHomeId(homeId);
    return _run(() async {
      final response = await _client.requestHomeErasure(homeId: homeId);
      return _request(
        response.requireObject(),
        expectedKind: DataGovernanceRequestKind.homeErasure,
        expectedScope: DataGovernanceScope.home,
        expectedHomeId: homeId,
      );
    });
  }

  @override
  Future<List<DataGovernanceRequest>> listAccountRequests() => _run(() async {
    final response = await _client.listAccountDataGovernanceRequests(
      query: const <String, String>{'limit': '50', 'offset': '0'},
    );
    return _requestList(
      response.requireObject(),
      expectedScope: DataGovernanceScope.account,
    );
  });

  @override
  Future<List<DataGovernanceRequest>> listHomeRequests({
    required String homeId,
  }) {
    _requireHomeId(homeId);
    return _run(() async {
      final response = await _client.listHomeDataGovernanceRequests(
        homeId: homeId,
        query: const <String, String>{'limit': '50', 'offset': '0'},
      );
      return _requestList(
        response.requireObject(),
        expectedScope: DataGovernanceScope.home,
        expectedHomeId: homeId,
      );
    });
  }

  @override
  Future<void> cancelRequest({
    required String requestId,
    required int expectedRevision,
  }) {
    if (!_uuidPattern.hasMatch(requestId) || expectedRevision < 1) {
      throw ArgumentError('A valid request ID and revision are required.');
    }
    return _run(() async {
      await _client.cancelDataGovernanceRequest(
        requestId: requestId,
        body: <String, Object?>{'expectedRevision': expectedRevision},
      );
    });
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DataGovernanceRepositoryException {
      rethrow;
    } on ProvidentiaApiException catch (error) {
      throw DataGovernanceRepositoryException(switch (error.statusCode) {
        400 || 422 => DataGovernanceFailureKind.invalidRequest,
        401 => DataGovernanceFailureKind.authenticationRequired,
        403 || 404 => DataGovernanceFailureKind.forbidden,
        409 => DataGovernanceFailureKind.conflict,
        _ => DataGovernanceFailureKind.unavailable,
      });
    } on FormatException {
      throw const DataGovernanceRepositoryException(
        DataGovernanceFailureKind.invalidResponse,
      );
    } on ArgumentError {
      throw const DataGovernanceRepositoryException(
        DataGovernanceFailureKind.invalidResponse,
      );
    } on http.ClientException {
      throw const DataGovernanceRepositoryException(
        DataGovernanceFailureKind.unavailable,
      );
    }
  }
}

List<DataGovernanceRequest> _requestList(
  Map<String, Object?> envelope, {
  required DataGovernanceScope expectedScope,
  String? expectedHomeId,
}) {
  _rejectUnexpectedHomeAttribution(envelope, expectedHomeId);
  final data = envelope['data'];
  if (data is! List<Object?>) {
    throw const FormatException('Missing governance request list.');
  }
  return data
      .map((value) {
        if (value is! Map<String, Object?>) {
          throw const FormatException('Invalid governance request item.');
        }
        return _request(
          value,
          expectedScope: expectedScope,
          expectedHomeId: expectedHomeId,
        );
      })
      .toList(growable: false);
}

DataGovernanceRequest _request(
  Map<String, Object?> object, {
  DataGovernanceRequestKind? expectedKind,
  required DataGovernanceScope expectedScope,
  String? expectedHomeId,
}) {
  _rejectUnexpectedHomeAttribution(object, expectedHomeId);
  final kind = switch (_requiredString(object, 'requestKind')) {
    'account_export' => DataGovernanceRequestKind.accountExport,
    'account_erasure' => DataGovernanceRequestKind.accountErasure,
    'home_export' => DataGovernanceRequestKind.homeExport,
    'home_erasure' => DataGovernanceRequestKind.homeErasure,
    _ => throw const FormatException('Invalid governance request kind.'),
  };
  final scope = switch (_requiredString(object, 'scopeType')) {
    'account' => DataGovernanceScope.account,
    'home' => DataGovernanceScope.home,
    _ => throw const FormatException('Invalid governance request scope.'),
  };
  if ((expectedKind != null && kind != expectedKind) ||
      scope != expectedScope) {
    throw const FormatException('Governance operation/response mismatch.');
  }
  final status = switch (_requiredString(object, 'status')) {
    'queued' => DataGovernanceRequestStatus.queued,
    'processing' => DataGovernanceRequestStatus.processing,
    'completed' => DataGovernanceRequestStatus.completed,
    'failed' => DataGovernanceRequestStatus.failed,
    'cancelled' => DataGovernanceRequestStatus.cancelled,
    _ => throw const FormatException('Invalid governance request status.'),
  };
  final disclosureValue = object['retainedDataDisclosure'];
  if (disclosureValue is! List<Object?>) {
    throw const FormatException('Missing retained-data disclosure.');
  }
  final disclosures = disclosureValue
      .map((value) {
        if (value is! Map<String, Object?> ||
            value.keys.any(
              (key) => !const <String>{
                'category',
                'treatment',
                'reason',
              }.contains(key),
            )) {
          throw const FormatException('Invalid retained-data disclosure.');
        }
        return RetainedDataDisclosure(
          category: _requiredString(value, 'category', allowEmpty: true),
          treatment: _requiredString(value, 'treatment', allowEmpty: true),
          reason: _requiredString(value, 'reason', allowEmpty: true),
        );
      })
      .toList(growable: false);

  // Validate the optional diagnostic field but intentionally do not retain it.
  _optionalString(object['failureReason'], allowEmpty: true);

  return DataGovernanceRequest(
    id: _requiredUuid(object, 'id'),
    kind: kind,
    scope: scope,
    status: status,
    revision: _positiveInteger(object, 'revision'),
    retainedDataDisclosure: disclosures,
    homeId: expectedScope == DataGovernanceScope.home ? expectedHomeId : null,
    artifactExpiresAt: _optionalDateTime(object['artifactExpiresAt']),
    createdAt: _optionalDateTime(object['createdAt']),
    updatedAt: _optionalDateTime(object['updatedAt']),
  );
}

void _rejectUnexpectedHomeAttribution(Object? value, String? expectedHomeId) {
  if (value is Map<String, Object?>) {
    if (value.containsKey('homeId')) {
      final suppliedHomeId = value['homeId'];
      if ((expectedHomeId == null && suppliedHomeId != null) ||
          (expectedHomeId != null && suppliedHomeId != expectedHomeId)) {
        throw const FormatException('Unexpected home attribution.');
      }
    }
    for (final nested in value.values) {
      _rejectUnexpectedHomeAttribution(nested, expectedHomeId);
    }
  } else if (value is List<Object?>) {
    for (final nested in value) {
      _rejectUnexpectedHomeAttribution(nested, expectedHomeId);
    }
  }
}

String _requiredString(
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

String _requiredUuid(Map<String, Object?> object, String key) {
  final value = _requiredString(object, key);
  if (!_uuidPattern.hasMatch(value)) {
    throw FormatException('Invalid $key UUID.');
  }
  return value;
}

int _positiveInteger(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! int || value < 1) {
    throw FormatException('Invalid $key revision.');
  }
  return value;
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

void _requireHomeId(String homeId) {
  if (!_uuidPattern.hasMatch(homeId)) {
    throw ArgumentError.value(homeId, 'homeId', 'must be a UUID');
  }
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
