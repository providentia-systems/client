import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

/// Adapts the backend-owned generated API client to the durable local sync
/// model. Server vocabulary is translated only at this boundary.
final class GeneratedSyncGateway implements SyncRemoteGateway {
  const GeneratedSyncGateway(this._client);

  final generated.ProvidentiaApiClient _client;

  @override
  Future<PullPage> bootstrap({required String homeId}) async {
    try {
      final response = await _client.bootstrapHomeSynchronization(
        homeId: homeId,
      );
      if (response.protocolVersion != 1) {
        throw FormatException(
          'Unsupported sync protocol version ${response.protocolVersion}.',
        );
      }
      final changes = response.records
          .map((record) {
            final representation = _requiredObject(record, 'representation');
            return RemoteChange(
              cursor: response.snapshotCursor,
              homeId: homeId,
              entityType: _requiredString(record, 'entityType'),
              entityId: _requiredString(record, 'entityId'),
              kind: RemoteChangeKind.upsert,
              revision: _requiredInteger(record, 'revision'),
              serverTimestamp: _requiredDateTime(record, 'serverTimestamp'),
              payload: representation,
            );
          })
          .toList(growable: false);
      return PullPage(
        protocolVersion: response.protocolVersion,
        // The first local cursor is absent. The repository deliberately
        // accepts this server-issued snapshot boundary only for bootstrap.
        fromCursor: response.snapshotCursor,
        changes: changes,
        pageCursor: response.snapshotCursor,
        highWaterCursor: response.snapshotCursor,
        hasMore: false,
        requestId: response.requestId,
      );
    } on generated.ProvidentiaApiException catch (error) {
      if (error.statusCode == 401) {
        throw AuthenticationSyncException(_safeProblem(error));
      }
      if (error.statusCode == 403) {
        throw AuthorizationSyncException(_safeProblem(error));
      }
      throw RetryableSyncException(_safeProblem(error));
    }
  }

  @override
  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
  }) async {
    if (operations.isEmpty) {
      return const PushResponse(results: <PushOperationResult>[]);
    }
    final deviceId = operations.first.deviceId;
    if (operations.any((operation) => operation.deviceId != deviceId)) {
      throw const FormatException(
        'A synchronization batch cannot contain multiple device IDs.',
      );
    }

    // Identical operation composition produces an identical UUID, while
    // adding/removing an operation produces a new batch identity. Individual
    // operation IDs remain the server's domain idempotency keys.
    final batchId = _batchId(operations);
    try {
      final response = await _client.pushHomeSynchronization(
        homeId: homeId,
        idempotencyKey: batchId,
        batchId: batchId,
        deviceId: deviceId,
        lastPulledCursor: lastPulledCursor,
        operations: operations
            .map(
              (operation) => generated.SyncOperation(
                operationId: operation.operationId,
                entityType: operation.entityType,
                entityId: operation.entityId,
                operationType: operation.operationType,
                baseRevision: operation.baseRevision,
                clientTimestamp: operation.clientTimestamp,
                payloadSchemaVersion: operation.payloadSchemaVersion,
                payload: operation.payload,
              ),
            )
            .toList(growable: false),
      );
      if (response.protocolVersion != 1 || response.batchId != batchId) {
        throw const FormatException(
          'Synchronization response identity did not match the request.',
        );
      }
      return PushResponse(
        results: response.results.map(_pushResult).toList(growable: false),
      );
    } on generated.ProvidentiaApiException catch (error) {
      if (error.statusCode == 401) {
        throw AuthenticationSyncException(_safeProblem(error));
      }
      if (error.statusCode == 403) {
        return PushResponse(
          results: operations
              .map(
                (operation) => PushOperationResult(
                  operationId: operation.operationId,
                  kind: PushResultKind.authorizationFailure,
                  safeMessage: _safeProblem(error),
                ),
              )
              .toList(growable: false),
        );
      }
      if (error.statusCode == 400 || error.statusCode == 422) {
        return PushResponse(
          results: operations
              .map(
                (operation) => PushOperationResult(
                  operationId: operation.operationId,
                  kind: PushResultKind.validationError,
                  safeMessage: _safeProblem(error),
                ),
              )
              .toList(growable: false),
        );
      }
      throw RetryableSyncException(_safeProblem(error));
    }
  }

  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) async {
    try {
      final response = await _client.pullHomeSynchronization(
        homeId: homeId,
        cursor: afterCursor,
      );
      if (response.protocolVersion != 1) {
        throw FormatException(
          'Unsupported sync protocol version ${response.protocolVersion}.',
        );
      }
      return PullPage(
        protocolVersion: response.protocolVersion,
        // On the first pull the request omits `cursor`; the server responds
        // with its canonical encoded genesis cursor. The local repository
        // accepts that server cursor only while no local cursor exists.
        fromCursor: response.fromCursor,
        pageCursor: response.pageCursor,
        highWaterCursor: response.highWaterCursor,
        hasMore: response.hasMore,
        requestId: response.requestId,
        changes: response.changes
            .map(
              (change) => RemoteChange(
                cursor: change.cursor,
                homeId: homeId,
                entityType: change.entityType,
                entityId: change.entityId,
                kind: switch (change.operation) {
                  'upsert' => RemoteChangeKind.upsert,
                  'delete' => RemoteChangeKind.tombstone,
                  _ => throw FormatException(
                    'Unknown sync operation ${change.operation}.',
                  ),
                },
                revision: change.revision,
                serverTimestamp: change.serverTimestamp,
                payload:
                    change.representation ??
                    change.tombstone ??
                    const <String, Object?>{},
              ),
            )
            .toList(growable: false),
      );
    } on generated.ProvidentiaApiException catch (error) {
      if (error.statusCode == 401) {
        throw AuthenticationSyncException(_safeProblem(error));
      }
      if (error.statusCode == 403) {
        throw AuthorizationSyncException(_safeProblem(error));
      }
      if (error.statusCode == 410 &&
          error.problem.type.endsWith('/sync_resync_required')) {
        throw ResyncRequiredSyncException(_safeProblem(error));
      }
      throw RetryableSyncException(_safeProblem(error));
    }
  }

  PushOperationResult _pushResult(generated.SyncOperationResult result) {
    return PushOperationResult(
      operationId: result.operationId,
      kind: switch (result.status) {
        'accepted' => PushResultKind.acknowledged,
        'conflict' => PushResultKind.conflict,
        'validation_error' => PushResultKind.validationError,
        'authorization_failure' => PushResultKind.authorizationFailure,
        'retryable_failure' => PushResultKind.retryableFailure,
        _ => throw FormatException(
          'Unknown synchronization result status ${result.status}.',
        ),
      },
      acceptedRevision: result.revision,
      changeCursor: result.changeCursor,
      safeMessage: result.detail,
      remotePayload: result.representation ?? result.conflict,
    );
  }

  String _safeProblem(generated.ProvidentiaApiException error) {
    return error.problem.detail ?? error.problem.title;
  }

  String _batchId(List<PendingClientOperation> operations) {
    final canonical = operations
        .map((operation) => operation.operationId)
        .join('\n');
    final characters = sha256
        .convert(utf8.encode(canonical))
        .toString()
        .substring(0, 32)
        .split('');
    characters[12] = '5';
    final variant = int.parse(characters[16], radix: 16);
    characters[16] = ((variant & 0x3) | 0x8).toRadixString(16);
    final hex = characters.join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! Map<String, Object?>) {
      throw FormatException('Expected bootstrap "$key" to be an object.');
    }
    return value;
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('Expected bootstrap "$key" to be a string.');
    }
    return value;
  }

  int _requiredInteger(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw FormatException('Expected bootstrap "$key" to be an integer.');
    }
    return value;
  }

  DateTime _requiredDateTime(Map<String, Object?> json, String key) {
    final value = DateTime.tryParse(_requiredString(json, key));
    if (value == null) {
      throw FormatException(
        'Expected bootstrap "$key" to be an RFC 3339 date-time.',
      );
    }
    return value;
  }
}
