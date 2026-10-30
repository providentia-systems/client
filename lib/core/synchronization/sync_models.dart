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
    this.failureCode,
    this.blockedOperationType,
    this.nextRetryAt,
  });

  final SyncRunStatus status;
  final String? safeMessage;
  final int acknowledgedCount;
  final int pulledChangeCount;
  final bool pullCompleted;
  final int remainingUploads;

  /// Allowlisted classification, never inferred from translated server prose.
  final String? failureCode;

  /// Safe command type of the first unresolved household dependency.
  /// No command payload or household/entity identity belongs in diagnostics.
  final String? blockedOperationType;
  final DateTime? nextRetryAt;

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
    this.entityId,
    this.entityType,
    this.commandType,
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
  final String? entityId;
  final String? entityType;
  final String? commandType;
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
    this.failureCode,
    this.blockedOperationType,
    this.nextRetryAt,
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
      lastSafeError = null,
      failureCode = null,
      blockedOperationType = null,
      nextRetryAt = null;

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
  final String? failureCode;
  final String? blockedOperationType;
  final DateTime? nextRetryAt;

  /// Later operations wait behind the first unresolved predecessor; this is
  /// not a count of independently failing purchases or receipts.
  int get waitingBehindFirst => unresolved > 0 ? unresolved - 1 : 0;

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
    String? failureCode,
    String? blockedOperationType,
    DateTime? nextRetryAt,
    bool clearDiagnostics = false,
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
      failureCode: clearDiagnostics ? null : (failureCode ?? this.failureCode),
      blockedOperationType: clearDiagnostics
          ? null
          : (blockedOperationType ?? this.blockedOperationType),
      nextRetryAt: clearDiagnostics ? null : (nextRetryAt ?? this.nextRetryAt),
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
        'authentication_required',
        'network_unavailable',
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
        'unsupported_operation',
        'unsupported_command',
        'unsupported_payload_schema',
        'unsupported_schema_version',
        'unsupported_protocol_version',
        'service_unavailable',
        'concurrent_write',
        'unclassified_http_denial',
        'unclassified_failure',
      }.contains(code)
      ? code
      : 'unclassified_failure';
}

/// Explicit machine classifications for a capability the remote cannot accept.
/// Neither HTTP 422 alone nor backend prose establishes an installed version.
bool isUnsupportedBackendFailureCode(String? code) => const <String>{
  'unsupported_operation',
  'unsupported_command',
  'unsupported_payload_schema',
  'unsupported_schema_version',
  'unsupported_protocol_version',
}.contains(code);

/// User-facing diagnosis is driven only by a documented safe code. In
/// particular, command-level authorization blocks do not prove home revocation.
String syncFailureHeading(String? code) => switch (code) {
  'device_binding_mismatch' => 'Review this device and session',
  'account_binding_mismatch' => 'Use the original account',
  'origin_account_unknown' => 'Review saved-operation provenance',
  'authentication_required' => 'Sign in to continue',
  'home_access_denied' => 'Access to this home changed',
  'permission_denied' => 'Review permission for this change',
  'revision_conflict' ||
  'revision_mismatch' ||
  'concurrent_write' => 'Review a synchronization conflict',
  'unsupported_operation' ||
  'unsupported_command' ||
  'unsupported_payload_schema' ||
  'unsupported_schema_version' ||
  'unsupported_protocol_version' => 'Verify the supported backend',
  'invalid_command' ||
  'resource_unavailable' => 'Review a change before syncing',
  'network_unavailable' || 'service_unavailable' => 'Synchronization paused',
  _ => 'Review synchronization',
};

String syncRecoveryInstruction(String? code) => switch (code) {
  'device_binding_mismatch' =>
    'Open Review account/session and verify the original account. Device-binding recovery requires the supported backend recovery update; retry cannot reassign saved operations. Saved operations are preserved.',
  'account_binding_mismatch' =>
    'Sign in with the account that saved these changes, then review synchronization. Do not recreate the pending purchases.',
  'origin_account_unknown' =>
    'The original account could not be verified. Review account/session; saved-operation provenance requires supported recovery before retrying. Automatic reassignment is blocked.',
  'authentication_required' =>
    'Sign in again to continue synchronization. Saved local changes remain on this device.',
  'home_access_denied' =>
    'Review access to this home before continuing. A verified home denial cannot be repaired by retrying a purchase.',
  'permission_denied' =>
    'Review the permission required for the first blocked change. Later saved changes remain queued behind it.',
  'revision_conflict' || 'revision_mismatch' || 'concurrent_write' =>
    'Open synchronization conflict review in Home and compare the saved and server versions before retrying.',
  'unsupported_operation' ||
  'unsupported_command' ||
  'unsupported_payload_schema' ||
  'unsupported_schema_version' ||
  'unsupported_protocol_version' =>
    'This server cannot accept the saved command or its schema. Verify the supported API 2.4.0 backend and required capability before retrying. The original queue, operation IDs and order are preserved; do not re-enter purchases or reassign saved work.',
  'invalid_command' =>
    'Review the first blocked entry and verify that the server supports this Client’s API 2.4.0 commands and payload schema. This rejection alone does not identify the installed version. The saved queue and original operation IDs are preserved; retry after correcting the entry or server compatibility.',
  'resource_unavailable' =>
    'Review and correct the first blocked change in Home synchronization. Later changes cannot skip this dependency.',
  'operation_id_reuse' =>
    'Review this saved operation before continuing. Its identity cannot be safely reused for a different change.',
  'network_unavailable' || 'service_unavailable' =>
    'Reconnect and use Retry synchronization to try again safely with the existing operation identities.',
  _ =>
    'Open Home synchronization to review the first unresolved change. Your saved queue is preserved.',
};

/// A command name is translated through a closed list so diagnostics cannot
/// accidentally display a private description or an unrecognized raw value.
String syncOperationLabel(String? type) => switch (type) {
  'purchasing.receipt.create' => 'Create receipt',
  'purchasing.receipt.update' => 'Update receipt details',
  'purchasing.receipt.commit' => 'Finish receipt',
  'purchasing.receipt.cancel' => 'Cancel receipt',
  'purchasing.receipt-line.create' => 'Add receipt line',
  'purchasing.receipt-line.purchase' => 'Save purchased receipt line',
  'purchasing.receipt-line.update' => 'Correct receipt line',
  'purchasing.receipt-line.correct' => 'Correct finished receipt line',
  'purchasing.receipt.correct-date' => 'Correct receipt purchase date',
  'purchasing.receipt-line.remove' => 'Remove receipt line',
  'purchasing.receipt-line.approve' => 'Approve receipt line',
  'purchasing.receipt-line.unresolve' => 'Leave receipt line unresolved',
  'purchasing.store.create' => 'Create store',
  'purchasing.store.update' => 'Update store',
  'shopping.list.create' => 'Create shopping list',
  'shopping.list.update' => 'Update shopping list',
  'shopping.list-line.create' => 'Add shopping item',
  'shopping.list-line.update' => 'Update shopping item',
  'shopping.list-line.relink' => 'Change shopping product link',
  'shopping.list-line.checked' => 'Check shopping item',
  'shopping.preference.put' => 'Update stock preference',
  'shopping.suggestion-feedback.create' => 'Save shopping feedback',
  'inventory.location.create' => 'Create storage location',
  'inventory.location.update' => 'Update storage location',
  'inventory.home-product.create' => 'Create household product',
  'inventory.home-product.update' => 'Update household product',
  'inventory.home-category.create' => 'Create household category',
  'inventory.home-category.update' => 'Update household category',
  'inventory.adjustment.create' => 'Adjust stock quantity',
  'inventory.count-session.create' => 'Start stock count',
  'inventory.count-line.upsert' => 'Save stock count line',
  'inventory.count-line.remove' => 'Remove stock count line',
  'inventory.count-session.close' => 'Finish stock count',
  'inventory.count-session.review' => 'Review stock count evidence',
  'inventory.count-session.cancel' => 'Cancel stock count',
  _ => 'Household change',
};
