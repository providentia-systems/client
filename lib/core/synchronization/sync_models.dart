import 'dart:convert';

/// Durable lifecycle of a locally-created client operation.
enum ClientOperationState {
  pending('pending'),
  syncing('syncing'),
  retryWait('retry_wait'),
  blockedConflict('blocked_conflict'),
  blockedValidation('blocked_validation'),
  blockedAuthorization('blocked_authorization'),
  acknowledged('acknowledged');

  const ClientOperationState(this.storageValue);

  final String storageValue;

  static ClientOperationState fromStorage(String value) {
    return values.firstWhere(
      (state) => state.storageValue == value,
      orElse: () =>
          throw FormatException('Unknown client operation state "$value".'),
    );
  }
}

enum SyncAvailability {
  checking,
  online,
  offline,
  temporarilyUnavailable,
  authenticationRequired,
  authorizationDenied,
}

enum SyncRunStatus {
  completed,
  alreadyRunning,
  offline,
  authenticationRequired,
  authorizationFailure,
  retryableFailure,
}

final class SyncRunOutcome {
  const SyncRunOutcome({
    required this.status,
    this.safeMessage,
    this.acknowledgedCount = 0,
    this.pulledChangeCount = 0,
  });

  final SyncRunStatus status;
  final String? safeMessage;
  final int acknowledgedCount;
  final int pulledChangeCount;

  bool get completed => status == SyncRunStatus.completed;
}

enum PushResultKind {
  acknowledged,
  conflict,
  validationError,
  authorizationFailure,
  retryableFailure,
}

enum RemoteChangeKind { upsert, tombstone }

final class LocalMutation {
  LocalMutation({
    required this.operationId,
    required this.deviceId,
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    this.baseRevision,
    required this.clientTimestamp,
    required this.payloadSchemaVersion,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  final String operationId;
  final String deviceId;
  final String homeId;
  final String entityType;
  final String entityId;
  final String operationType;
  final int? baseRevision;
  final DateTime clientTimestamp;
  final int payloadSchemaVersion;
  final Map<String, Object?> payload;

  String get encodedPayload => jsonEncode(payload);
}

final class PendingClientOperation {
  const PendingClientOperation({
    required this.operationId,
    required this.deviceId,
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    this.baseRevision,
    required this.clientTimestamp,
    required this.payloadSchemaVersion,
    required this.payload,
    required this.retryCount,
  });

  final String operationId;
  final String deviceId;
  final String homeId;
  final String entityType;
  final String entityId;
  final String operationType;
  final int? baseRevision;
  final DateTime clientTimestamp;
  final int payloadSchemaVersion;
  final Map<String, Object?> payload;
  final int retryCount;
}

final class PushOperationResult {
  PushOperationResult({
    required this.operationId,
    required this.kind,
    this.acceptedRevision,
    this.changeCursor,
    this.safeMessage,
    this.remotePayload,
  }) : remotePayload = remotePayload == null
           ? null
           : Map<String, Object?>.unmodifiable(remotePayload);

  final String operationId;
  final PushResultKind kind;
  final int? acceptedRevision;
  final String? changeCursor;
  final String? safeMessage;
  final Map<String, Object?>? remotePayload;
}

final class PushResponse {
  const PushResponse({required this.results});

  final List<PushOperationResult> results;
}

final class RemoteChange {
  RemoteChange({
    required this.cursor,
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.revision,
    required this.serverTimestamp,
    Map<String, Object?> payload = const <String, Object?>{},
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  final String cursor;
  final String homeId;
  final String entityType;
  final String entityId;
  final RemoteChangeKind kind;
  final int revision;
  final DateTime serverTimestamp;
  final Map<String, Object?> payload;
}

final class PullPage {
  const PullPage({
    required this.protocolVersion,
    required this.fromCursor,
    required this.changes,
    required this.pageCursor,
    required this.highWaterCursor,
    required this.hasMore,
    required this.requestId,
  });

  final int protocolVersion;
  final String? fromCursor;
  final List<RemoteChange> changes;
  final String pageCursor;
  final String highWaterCursor;
  final bool hasMore;
  final String requestId;
}

final class SyncSummary {
  const SyncSummary({
    required this.pending,
    required this.syncing,
    required this.retryWaiting,
    required this.blockedConflicts,
    required this.blockedValidation,
    required this.blockedAuthorization,
    required this.acknowledged,
    required this.availability,
    required this.isSynchronizing,
    this.lastSuccessfulSync,
    this.lastSafeError,
  });

  const SyncSummary.initial()
    : pending = 0,
      syncing = 0,
      retryWaiting = 0,
      blockedConflicts = 0,
      blockedValidation = 0,
      blockedAuthorization = 0,
      acknowledged = 0,
      availability = SyncAvailability.checking,
      isSynchronizing = false,
      lastSuccessfulSync = null,
      lastSafeError = null;

  final int pending;
  final int syncing;
  final int retryWaiting;
  final int blockedConflicts;
  final int blockedValidation;
  final int blockedAuthorization;
  final int acknowledged;
  final SyncAvailability availability;
  final bool isSynchronizing;
  final DateTime? lastSuccessfulSync;
  final String? lastSafeError;

  int get waiting => pending + syncing + retryWaiting;

  SyncSummary copyWith({
    int? pending,
    int? syncing,
    int? retryWaiting,
    int? blockedConflicts,
    int? blockedValidation,
    int? blockedAuthorization,
    int? acknowledged,
    SyncAvailability? availability,
    bool? isSynchronizing,
    DateTime? lastSuccessfulSync,
    String? lastSafeError,
    bool clearError = false,
  }) {
    return SyncSummary(
      pending: pending ?? this.pending,
      syncing: syncing ?? this.syncing,
      retryWaiting: retryWaiting ?? this.retryWaiting,
      blockedConflicts: blockedConflicts ?? this.blockedConflicts,
      blockedValidation: blockedValidation ?? this.blockedValidation,
      blockedAuthorization: blockedAuthorization ?? this.blockedAuthorization,
      acknowledged: acknowledged ?? this.acknowledged,
      availability: availability ?? this.availability,
      isSynchronizing: isSynchronizing ?? this.isSynchronizing,
      lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
      lastSafeError: clearError ? null : (lastSafeError ?? this.lastSafeError),
    );
  }
}

final class ConnectivityResult {
  const ConnectivityResult._(this.availability, this.safeMessage);

  const ConnectivityResult.online() : this._(SyncAvailability.online, null);

  const ConnectivityResult.offline([String? message])
    : this._(SyncAvailability.offline, message);

  const ConnectivityResult.authenticationRequired([String? message])
    : this._(SyncAvailability.authenticationRequired, message);

  final SyncAvailability availability;
  final String? safeMessage;
}

final class RetryableSyncException implements Exception {
  const RetryableSyncException(this.safeMessage);

  final String safeMessage;
}

final class AuthenticationSyncException implements Exception {
  const AuthenticationSyncException(this.safeMessage);

  final String safeMessage;
}

final class AuthorizationSyncException implements Exception {
  const AuthorizationSyncException(this.safeMessage);

  final String safeMessage;
}

final class ResyncRequiredSyncException implements Exception {
  const ResyncRequiredSyncException(this.safeMessage);

  final String safeMessage;
}
