import 'dart:convert';

/// Durable lifecycle of a locally-created client operation.
enum ClientOperationState {
  pending('pending'),
  syncing('syncing'),
  retryWait('retry_wait'),
  blockedConflict('blocked_conflict'),
  blockedValidation('blocked_validation'),
  blockedAuthorization('blocked_authorization'),
  superseded('superseded'),
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
  uploadsPending,
  uploadsBlocked,
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
    this.pullCompleted = false,
    this.remainingUploads = 0,
  });

  final SyncRunStatus status;
  final String? safeMessage;
  final int acknowledgedCount;
  final int pulledChangeCount;
  final bool pullCompleted;
  final int remainingUploads;

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

enum SyncConflictRemoteKind { upsert, tombstone, unavailable }

enum SyncConflictResolutionChoice {
  acceptRemote('accept_remote'),
  reapplyLocal('reapply_local'),
  reconcileCount('reconcile_count');

  const SyncConflictResolutionChoice(this.storageValue);

  final String storageValue;
}

/// Immutable evidence for the local intent which encountered a conflict.
final class SyncConflictLocalEvidence {
  SyncConflictLocalEvidence({
    required this.operationId,
    required this.operationType,
    required Map<String, Object?> commandPayload,
    required Map<String, Object?>? representation,
    required this.isDeletion,
  }) : commandPayload = Map<String, Object?>.unmodifiable(commandPayload),
       representation = representation == null
           ? null
           : Map<String, Object?>.unmodifiable(representation);

  final String operationId;
  final String operationType;
  final Map<String, Object?> commandPayload;
  final Map<String, Object?>? representation;
  final bool isDeletion;
}

/// Immutable authoritative evidence captured when the conflict was detected.
final class SyncConflictRemoteEvidence {
  SyncConflictRemoteEvidence({
    required this.kind,
    required this.revision,
    required Map<String, Object?>? representation,
    this.deletedAt,
  }) : representation = representation == null
           ? null
           : Map<String, Object?>.unmodifiable(representation);

  final SyncConflictRemoteKind kind;
  final int? revision;
  final Map<String, Object?>? representation;
  final DateTime? deletedAt;
}

/// Home-scoped, unresolved synchronization evidence presented for review.
final class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.detectedAt,
    required this.local,
    required this.remote,
  });

  final String id;
  final String homeId;
  final String entityType;
  final String entityId;
  final String kind;
  final DateTime detectedAt;
  final SyncConflictLocalEvidence local;
  final SyncConflictRemoteEvidence remote;

  bool get requiresCountReconciliation =>
      entityType == 'inventory-count-session' ||
      entityType == 'inventory-count-line' ||
      local.operationType.startsWith('inventory.count-');

  bool get canAcceptRemote =>
      !requiresCountReconciliation &&
      remote.kind != SyncConflictRemoteKind.unavailable &&
      remote.revision != null;

  bool get canReapplyLocal =>
      !requiresCountReconciliation && remote.revision != null;
}

/// Safe failure surfaced by explicit conflict-review operations.
final class SyncConflictResolutionException implements Exception {
  const SyncConflictResolutionException(this.safeMessage);

  final String safeMessage;

  @override
  String toString() => safeMessage;
}

final class LocalMutation {
  factory LocalMutation({
    required String operationId,
    required String deviceId,
    String? originatingAccountId,
    required String homeId,
    required String entityType,
    required String entityId,
    required String operationType,
    int? baseRevision,
    required DateTime clientTimestamp,
    required int payloadSchemaVersion,
    required Map<String, Object?> payload,
  }) {
    _requireNonEmpty(operationId, 'operationId');
    _requireNonEmpty(deviceId, 'deviceId');
    if (originatingAccountId != null) {
      _requireNonEmpty(originatingAccountId, 'originatingAccountId');
    }
    _requireNonEmpty(homeId, 'homeId');
    _requireNonEmpty(entityType, 'entityType');
    _requireNonEmpty(entityId, 'entityId');
    _requireNonEmpty(operationType, 'operationType');
    if (baseRevision != null && baseRevision < 0) {
      throw ArgumentError.value(
        baseRevision,
        'baseRevision',
        'must not be negative',
      );
    }
    if (payloadSchemaVersion < 1) {
      throw ArgumentError.value(
        payloadSchemaVersion,
        'payloadSchemaVersion',
        'must be at least one',
      );
    }
    return LocalMutation._(
      operationId: operationId,
      deviceId: deviceId,
      originatingAccountId: originatingAccountId,
      homeId: homeId,
      entityType: entityType,
      entityId: entityId,
      operationType: operationType,
      baseRevision: baseRevision,
      clientTimestamp: clientTimestamp,
      payloadSchemaVersion: payloadSchemaVersion,
      payload: Map<String, Object?>.unmodifiable(payload),
    );
  }

  const LocalMutation._({
    required this.operationId,
    required this.deviceId,
    this.originatingAccountId,
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.baseRevision,
    required this.clientTimestamp,
    required this.payloadSchemaVersion,
    required this.payload,
  });

  final String operationId;
  final String deviceId;
  final String? originatingAccountId;
  final String homeId;
  final String entityType;
  final String entityId;
  final String operationType;
  final int? baseRevision;
  final DateTime clientTimestamp;
  final int payloadSchemaVersion;
  final Map<String, Object?> payload;

  String get encodedPayload => jsonEncode(payload);

  static void _requireNonEmpty(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
  }
}

final class PendingClientOperation {
  const PendingClientOperation({
    required this.operationId,
    required this.deviceId,
    this.originatingAccountId,
    required this.homeId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    this.baseRevision,
    required this.clientTimestamp,
    required this.payloadSchemaVersion,
    required this.payload,
    required this.retryCount,
    this.enqueueSequence,
  });

  final String operationId;
  final String deviceId;
  final String? originatingAccountId;
  final String homeId;
  final String entityType;
  final String entityId;
  final String operationType;
  final int? baseRevision;
  final DateTime clientTimestamp;
  final int payloadSchemaVersion;
  final Map<String, Object?> payload;
  final int retryCount;
  final int? enqueueSequence;
}

final class PushOperationResult {
  PushOperationResult({
    required this.operationId,
    required this.kind,
    this.acceptedRevision,
    this.changeCursor,
    this.safeMessage,
    this.code,
    this.requestId,
    Map<String, Object?>? remotePayload,
  }) : remotePayload = remotePayload == null
           ? null
           : Map<String, Object?>.unmodifiable(remotePayload);

  final String operationId;
  final PushResultKind kind;
  final int? acceptedRevision;
  final String? changeCursor;
  final String? safeMessage;
  final String? code;
  final String? requestId;
  final Map<String, Object?>? remotePayload;
}

final class PushResponse {
  const PushResponse({required this.results});

  final List<PushOperationResult> results;
}

final class OperationStatusItem {
  const OperationStatusItem({required this.operationId, this.result});

  final String operationId;
  final PushOperationResult? result;

  bool get isKnown => result != null;
}

final class OperationStatusResponse {
  OperationStatusResponse({required List<OperationStatusItem> operations})
    : operations = List<OperationStatusItem>.unmodifiable(operations);

  final List<OperationStatusItem> operations;
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
  int get blocked =>
      blockedConflicts + blockedValidation + blockedAuthorization;
  int get unresolved => waiting + blocked;

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

/// A saved command does not belong to this dispatch binding. This is not an
/// expired login, and must never trigger credential refresh or intent rebinding.
final class BindingSyncException implements Exception {
  const BindingSyncException(this.safeMessage, {required this.code});

  final String safeMessage;
  final String code;
}

/// Only documented classifications enter diagnostics. Server prose is not a code.
String? sanitizedSyncFailureCode(String? code) {
  if (code == null) return null;
  return const <String>{
        'device_binding_mismatch',
        'account_binding_mismatch',
        'origin_account_unknown',
        'home_access_denied',
        'permission_denied',
        'resource_unavailable',
        'revision_conflict',
        'revision_mismatch',
        'operation_id_reuse',
        'invalid_command',
        'service_unavailable',
        'concurrent_write',
        'unclassified_http_denial',
        'unclassified_failure',
      }.contains(code)
      ? code
      : 'unclassified_failure';
}
