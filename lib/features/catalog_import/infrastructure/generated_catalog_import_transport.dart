import 'package:http/http.dart' as http;
import 'package:providentia/features/catalog_import/application/catalog_import_ports.dart';
import 'package:providentia/features/catalog_import/domain/catalog_import_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Pinned-contract boundary for staged household catalog imports.
///
/// Every call is home-scoped, the client-supplied `Idempotency-Key` header is
/// forwarded verbatim so retries replay instead of duplicating, and each
/// response is checked against the requesting home before it is surfaced.
final class GeneratedCatalogImportTransport implements CatalogImportGateway {
  const GeneratedCatalogImportTransport(this._client);

  final ProvidentiaApiClient _client;

  @override
  Future<CatalogImportBatchView> stage({
    required String homeId,
    required String idempotencyKey,
    required List<Map<String, Object?>> records,
  }) {
    if (idempotencyKey.length < 8 || idempotencyKey.length > 128) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'must be 8 through 128 characters',
      );
    }
    if (records.isEmpty ||
        records.length > CatalogImportPolicy.maxRecordsPerStage) {
      throw ArgumentError.value(
        records.length,
        'records',
        'must contain 1 through ${CatalogImportPolicy.maxRecordsPerStage} '
            'records',
      );
    }
    return _run(() async {
      final object = (await _client.stageHomeCatalogImport(
        homeId: homeId,
        headers: <String, String>{'Idempotency-Key': idempotencyKey},
        body: <String, Object?>{'records': records},
      )).requireObject();
      return _batch(object, expectedHomeId: homeId);
    });
  }

  @override
  Future<CatalogImportBatchView> fetch({
    required String homeId,
    required String importId,
  }) {
    return _run(() async {
      final object = (await _client.getHomeCatalogImport(
        homeId: homeId,
        importId: importId,
      )).requireObject();
      return _batch(object, expectedHomeId: homeId);
    });
  }

  @override
  Future<CatalogImportBatchView> confirm({
    required String homeId,
    required String importId,
    required int expectedRevision,
  }) {
    if (expectedRevision < 1) {
      throw ArgumentError.value(
        expectedRevision,
        'expectedRevision',
        'must be positive',
      );
    }
    return _run(() async {
      final object = (await _client.confirmHomeCatalogImport(
        homeId: homeId,
        importId: importId,
        body: <String, Object?>{
          'expectedRevision': expectedRevision,
          'confirmation': CatalogImportPolicy.confirmationWord,
        },
      )).requireObject();
      return _batch(object, expectedHomeId: homeId);
    });
  }

  Future<CatalogImportBatchView> _run(
    Future<CatalogImportBatchView> Function() action,
  ) async {
    try {
      return await action();
    } on ProvidentiaApiException catch (error) {
      throw switch (error.statusCode) {
        401 => const CatalogImportAuthenticationRequiredException(),
        403 => const CatalogImportForbiddenException(),
        409 => const CatalogImportConflictException(),
        413 => const CatalogImportTooLargeException(),
        400 || 422 => const CatalogImportValidationException(),
        _ => const CatalogImportUnavailableException(),
      };
    } on FormatException {
      throw const CatalogImportUnavailableException();
    } on ArgumentError {
      rethrow;
    } on http.ClientException {
      throw const CatalogImportUnavailableException();
    }
  }
}

CatalogImportBatchView _batch(
  Map<String, Object?> object, {
  required String expectedHomeId,
}) {
  final homeId = _string(object, 'homeId');
  if (homeId != expectedHomeId) {
    throw const FormatException('Catalog import crossed the home boundary.');
  }
  final rowsValue = object['rows'];
  if (rowsValue is! List<Object?>) {
    throw const FormatException('Missing rows.');
  }
  return CatalogImportBatchView(
    id: _string(object, 'id'),
    homeId: homeId,
    status: CatalogImportBatchStatus.parse(_string(object, 'status')),
    rowCount: _integer(object, 'rowCount'),
    validCount: _integer(object, 'validCount'),
    errorCount: _integer(object, 'errorCount'),
    importedCount: _integer(object, 'importedCount'),
    skippedCount: _integer(object, 'skippedCount'),
    revision: _integer(object, 'revision'),
    replayed: object['replayed'] == true,
    rows: <CatalogImportRowView>[
      for (final row in rowsValue)
        if (row is Map<String, Object?>)
          _row(row)
        else
          throw const FormatException('Malformed import row.'),
    ],
  );
}

CatalogImportRowView _row(Map<String, Object?> object) {
  final record = object['record'];
  return CatalogImportRowView(
    position: _integer(object, 'position'),
    recordType: _string(object, 'recordType'),
    resolution: CatalogImportRowResolution.parse(_string(object, 'resolution')),
    record: record is Map<String, Object?> ? record : const <String, Object?>{},
    errorCode: _optionalString(object, 'errorCode'),
    errorDetail: _optionalString(object, 'errorDetail'),
  );
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Malformed $key.');
  return value;
}

int _integer(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! int) {
    throw FormatException('Missing $key.');
  }
  return value;
}
