// GENERATED FILE - DO NOT EDIT.
// Source: contracts/providentia-v1.json
// Contract SHA-256: 0d9f9472b1af44c0bde5dfcd18489dc8fc07cd2a783dadcd9496a13d5de97786

library;

import 'dart:convert';

import 'package:http/http.dart' as http;

final class ApiOperation {
  const ApiOperation({
    required this.operationId,
    required this.method,
    required this.pathTemplate,
    required this.multipart,
  });

  final String operationId;
  final String method;
  final String pathTemplate;
  final bool multipart;
}

final class ApiResponse {
  ApiResponse({
    required this.statusCode,
    required Map<String, String> headers,
    required this.body,
  }) : headers = Map<String, String>.unmodifiable(headers);

  final int statusCode;
  final Map<String, String> headers;
  final Object? body;

  Map<String, Object?> requireObject() {
    final value = body;
    if (value is! Map<String, Object?>) {
      throw const FormatException('Expected an object response body.');
    }
    return value;
  }

  List<Object?> requireList() {
    final value = body;
    if (value is! List<Object?>) {
      throw const FormatException('Expected an array response body.');
    }
    return value;
  }
}

final class HealthStatus {
  const HealthStatus({required this.status, required this.timestamp});

  factory HealthStatus.fromJson(Map<String, Object?> json) {
    return HealthStatus(
      status: _requiredString(json, 'status'),
      timestamp: _requiredDateTime(json, 'timestamp'),
    );
  }

  final String status;
  final DateTime timestamp;
}

final class ReadinessCheck {
  const ReadinessCheck({required this.status, this.detail});

  factory ReadinessCheck.fromJson(Map<String, Object?> json) {
    return ReadinessCheck(
      status: _requiredString(json, 'status'),
      detail: _optionalString(json, 'detail'),
    );
  }

  final String status;
  final String? detail;
}

final class ReadinessStatus {
  const ReadinessStatus({required this.status, required this.checks});

  factory ReadinessStatus.fromJson(Map<String, Object?> json) {
    final checksJson = _requiredObject(json, 'checks');
    return ReadinessStatus(
      status: _requiredString(json, 'status'),
      checks: Map<String, ReadinessCheck>.unmodifiable(
        checksJson.map(
          (String key, Object? value) => MapEntry<String, ReadinessCheck>(
            key,
            ReadinessCheck.fromJson(_objectValue(value, 'checks.$key')),
          ),
        ),
      ),
    );
  }

  final String status;
  final Map<String, ReadinessCheck> checks;
}

final class SystemInfo {
  const SystemInfo({
    required this.product,
    required this.apiVersion,
    required this.applicationVersion,
    required this.environment,
    required this.runtime,
    required this.databaseDriver,
    required this.queueAdapter,
    required this.queueBroker,
  });

  factory SystemInfo.fromJson(Map<String, Object?> json) {
    return SystemInfo(
      product: _requiredString(json, 'product'),
      apiVersion: _requiredString(json, 'apiVersion'),
      applicationVersion: _requiredString(json, 'applicationVersion'),
      environment: _requiredString(json, 'environment'),
      runtime: _requiredString(json, 'runtime'),
      databaseDriver: _requiredString(json, 'databaseDriver'),
      queueAdapter: _requiredString(json, 'queueAdapter'),
      queueBroker: _requiredString(json, 'queueBroker'),
    );
  }

  final String product;
  final String apiVersion;
  final String applicationVersion;
  final String environment;
  final String runtime;
  final String databaseDriver;
  final String queueAdapter;
  final String queueBroker;
}

final class SyncOperation {
  SyncOperation({
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.baseRevision,
    required this.clientTimestamp,
    required this.payloadSchemaVersion,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  final String operationId;
  final String entityType;
  final String entityId;
  final String operationType;
  final int? baseRevision;
  final DateTime clientTimestamp;
  final int payloadSchemaVersion;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'operationId': operationId,
    'entityType': entityType,
    'entityId': entityId,
    'operationType': operationType,
    'baseRevision': baseRevision,
    'clientTimestamp': clientTimestamp.toUtc().toIso8601String(),
    'payloadSchemaVersion': payloadSchemaVersion,
    'payload': payload,
  };
}

final class SyncOperationResult {
  SyncOperationResult({
    required this.operationId,
    required this.status,
    this.revision,
    this.changeCursor,
    this.detail,
    Map<String, Object?>? representation,
    Map<String, Object?>? conflict,
  }) : representation = representation == null
           ? null
           : Map<String, Object?>.unmodifiable(representation),
       conflict = conflict == null
           ? null
           : Map<String, Object?>.unmodifiable(conflict);

  factory SyncOperationResult.fromJson(Map<String, Object?> json) {
    return SyncOperationResult(
      operationId: _requiredString(json, 'operationId'),
      status: _requiredString(json, 'status'),
      revision: _optionalInteger(json, 'revision'),
      changeCursor: _optionalString(json, 'changeCursor'),
      detail: _optionalString(json, 'detail'),
      representation: _optionalObject(json, 'representation'),
      conflict: _optionalObject(json, 'conflict'),
    );
  }

  final String operationId;
  final String status;
  final int? revision;
  final String? changeCursor;
  final String? detail;
  final Map<String, Object?>? representation;
  final Map<String, Object?>? conflict;
}

final class SyncPushResponse {
  const SyncPushResponse({
    required this.protocolVersion,
    required this.batchId,
    required this.requestId,
    required this.serverTime,
    required this.results,
    required this.highWaterCursor,
  });

  factory SyncPushResponse.fromJson(Map<String, Object?> json) {
    return SyncPushResponse(
      protocolVersion: _requiredInteger(json, 'protocolVersion'),
      batchId: _requiredString(json, 'batchId'),
      requestId: _requiredString(json, 'requestId'),
      serverTime: _requiredDateTime(json, 'serverTime'),
      results: _requiredObjectList(
        json,
        'results',
      ).map(SyncOperationResult.fromJson).toList(growable: false),
      highWaterCursor: _requiredString(json, 'highWaterCursor'),
    );
  }

  final int protocolVersion;
  final String batchId;
  final String requestId;
  final DateTime serverTime;
  final List<SyncOperationResult> results;
  final String highWaterCursor;
}

final class SyncChange {
  SyncChange({
    required this.cursor,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.revision,
    required this.serverTimestamp,
    required this.representationSchemaVersion,
    Map<String, Object?>? representation,
    Map<String, Object?>? tombstone,
  }) : representation = representation == null
           ? null
           : Map<String, Object?>.unmodifiable(representation),
       tombstone = tombstone == null
           ? null
           : Map<String, Object?>.unmodifiable(tombstone);

  factory SyncChange.fromJson(Map<String, Object?> json) {
    return SyncChange(
      cursor: _requiredString(json, 'cursor'),
      entityType: _requiredString(json, 'entityType'),
      entityId: _requiredString(json, 'entityId'),
      operation: _requiredString(json, 'operation'),
      revision: _requiredInteger(json, 'revision'),
      serverTimestamp: _requiredDateTime(json, 'serverTimestamp'),
      representationSchemaVersion: _requiredInteger(
        json,
        'representationSchemaVersion',
      ),
      representation: _optionalObject(json, 'representation'),
      tombstone: _optionalObject(json, 'tombstone'),
    );
  }

  final String cursor;
  final String entityType;
  final String entityId;
  final String operation;
  final int revision;
  final DateTime serverTimestamp;
  final int representationSchemaVersion;
  final Map<String, Object?>? representation;
  final Map<String, Object?>? tombstone;
}

final class SyncPullResponse {
  const SyncPullResponse({
    required this.protocolVersion,
    required this.requestId,
    required this.fromCursor,
    required this.pageCursor,
    required this.highWaterCursor,
    required this.hasMore,
    required this.changes,
  });

  factory SyncPullResponse.fromJson(Map<String, Object?> json) {
    return SyncPullResponse(
      protocolVersion: _requiredInteger(json, 'protocolVersion'),
      requestId: _requiredString(json, 'requestId'),
      fromCursor: _requiredString(json, 'fromCursor'),
      pageCursor: _requiredString(json, 'pageCursor'),
      highWaterCursor: _requiredString(json, 'highWaterCursor'),
      hasMore: _requiredBoolean(json, 'hasMore'),
      changes: _requiredObjectList(
        json,
        'changes',
      ).map(SyncChange.fromJson).toList(growable: false),
    );
  }

  final int protocolVersion;
  final String requestId;
  final String fromCursor;
  final String pageCursor;
  final String highWaterCursor;
  final bool hasMore;
  final List<SyncChange> changes;
}

final class SyncBootstrapResponse {
  const SyncBootstrapResponse({
    required this.protocolVersion,
    required this.requestId,
    required this.snapshotCursor,
    required this.records,
  });

  factory SyncBootstrapResponse.fromJson(Map<String, Object?> json) {
    return SyncBootstrapResponse(
      protocolVersion: _requiredInteger(json, 'protocolVersion'),
      requestId: _requiredString(json, 'requestId'),
      snapshotCursor: _requiredString(json, 'snapshotCursor'),
      records: _requiredObjectList(json, 'records'),
    );
  }

  final int protocolVersion;
  final String requestId;
  final String snapshotCursor;
  final List<Map<String, Object?>> records;
}

final class ProblemDetails {
  const ProblemDetails({
    required this.type,
    required this.title,
    required this.status,
    required this.requestId,
    this.detail,
    this.instance,
    this.extensions = const <String, Object?>{},
  });

  factory ProblemDetails.fromJson(Map<String, Object?> json) {
    final extensions = Map<String, Object?>.of(json)
      ..remove('type')
      ..remove('title')
      ..remove('status')
      ..remove('detail')
      ..remove('instance')
      ..remove('requestId');

    return ProblemDetails(
      type: _requiredString(json, 'type'),
      title: _requiredString(json, 'title'),
      status: _integerValue(json['status'], 'status'),
      requestId: _requiredString(json, 'requestId'),
      detail: _optionalString(json, 'detail'),
      instance: _optionalString(json, 'instance'),
      extensions: Map<String, Object?>.unmodifiable(extensions),
    );
  }

  final String type;
  final String title;
  final int status;
  final String requestId;
  final String? detail;
  final String? instance;
  final Map<String, Object?> extensions;
}

final class ProvidentiaApiException implements Exception {
  const ProvidentiaApiException({
    required this.statusCode,
    required this.problem,
    this.requestId,
  });

  final int statusCode;
  final ProblemDetails problem;
  final String? requestId;

  @override
  String toString() {
    final message = problem.detail ?? problem.title;
    return 'ProvidentiaApiException($statusCode): $message';
  }
}

final class ProvidentiaApiClient {
  ProvidentiaApiClient({
    required this.baseUri,
    http.Client? httpClient,
    bool closeHttpClient = false,
    Map<String, String> defaultHeaders = const <String, String>{},
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null || closeHttpClient,
       _defaultHeaders = Map<String, String>.unmodifiable(defaultHeaders) {
    if (!baseUri.hasScheme || !baseUri.hasAuthority) {
      throw ArgumentError.value(baseUri, 'baseUri', 'must be absolute');
    }
  }

  final Uri baseUri;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Map<String, String> _defaultHeaders;

  static const Map<String, ApiOperation> operations = <String, ApiOperation>{
    "acceptHomeInvitation": ApiOperation(
      operationId: "acceptHomeInvitation",
      method: "POST",
      pathTemplate: "/api/v1/home-invitations/accept",
      multipart: false,
    ),
    "applyCatalogMerge": ApiOperation(
      operationId: "applyCatalogMerge",
      method: "POST",
      pathTemplate: "/api/v1/catalog-admin/merges",
      multipart: false,
    ),
    "approveReceiptLine": ApiOperation(
      operationId: "approveReceiptLine",
      method: "POST",
      pathTemplate:
          "/api/v1/homes/{homeId}/receipts/{receiptId}/lines/{lineId}/approve",
      multipart: false,
    ),
    "bootstrapHomeSynchronization": ApiOperation(
      operationId: "bootstrapHomeSynchronization",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/sync/bootstrap",
      multipart: false,
    ),
    "changeHomeMembershipRole": ApiOperation(
      operationId: "changeHomeMembershipRole",
      method: "PATCH",
      pathTemplate: "/api/v1/homes/{homeId}/memberships/{userId}",
      multipart: false,
    ),
    "closeStockCountSession": ApiOperation(
      operationId: "closeStockCountSession",
      method: "POST",
      pathTemplate:
          "/api/v1/homes/{homeId}/stock-count-sessions/{sessionId}/close",
      multipart: false,
    ),
    "commitReceipt": ApiOperation(
      operationId: "commitReceipt",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/receipts/{receiptId}/commit",
      multipart: false,
    ),
    "completePasswordReset": ApiOperation(
      operationId: "completePasswordReset",
      method: "POST",
      pathTemplate: "/api/v1/auth/password-reset/complete",
      multipart: false,
    ),
    "createAiExtraction": ApiOperation(
      operationId: "createAiExtraction",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/ai/extractions",
      multipart: true,
    ),
    "createHome": ApiOperation(
      operationId: "createHome",
      method: "POST",
      pathTemplate: "/api/v1/homes",
      multipart: false,
    ),
    "createHomeInvitation": ApiOperation(
      operationId: "createHomeInvitation",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/invitations",
      multipart: false,
    ),
    "createHomeLocation": ApiOperation(
      operationId: "createHomeLocation",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/locations",
      multipart: false,
    ),
    "createHomeProduct": ApiOperation(
      operationId: "createHomeProduct",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/products",
      multipart: false,
    ),
    "createReceipt": ApiOperation(
      operationId: "createReceipt",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/receipts",
      multipart: false,
    ),
    "createReceiptLine": ApiOperation(
      operationId: "createReceiptLine",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/receipts/{receiptId}/lines",
      multipart: false,
    ),
    "createShoppingList": ApiOperation(
      operationId: "createShoppingList",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/shopping-lists",
      multipart: false,
    ),
    "createShoppingListLine": ApiOperation(
      operationId: "createShoppingListLine",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/shopping-lists/{listId}/lines",
      multipart: false,
    ),
    "createShoppingSuggestionFeedback": ApiOperation(
      operationId: "createShoppingSuggestionFeedback",
      method: "POST",
      pathTemplate:
          "/api/v1/homes/{homeId}/shopping-suggestions/{suggestionId}/feedback",
      multipart: false,
    ),
    "createShoppingSuggestionRun": ApiOperation(
      operationId: "createShoppingSuggestionRun",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/shopping-suggestion-runs",
      multipart: false,
    ),
    "createStockAdjustment": ApiOperation(
      operationId: "createStockAdjustment",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/stock-adjustments",
      multipart: false,
    ),
    "createStore": ApiOperation(
      operationId: "createStore",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/stores",
      multipart: false,
    ),
    "createSuggestionBacktest": ApiOperation(
      operationId: "createSuggestionBacktest",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/suggestion-backtests",
      multipart: false,
    ),
    "decideCatalogProposal": ApiOperation(
      operationId: "decideCatalogProposal",
      method: "POST",
      pathTemplate: "/api/v1/catalog-admin/proposals/{proposalId}/decision",
      multipart: false,
    ),
    "deleteAiProviderCredential": ApiOperation(
      operationId: "deleteAiProviderCredential",
      method: "DELETE",
      pathTemplate: "/api/v1/homes/{homeId}/ai/credentials/{providerId}",
      multipart: false,
    ),
    "getAiExtraction": ApiOperation(
      operationId: "getAiExtraction",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/ai/extractions/{extractionId}",
      multipart: false,
    ),
    "getAiSettings": ApiOperation(
      operationId: "getAiSettings",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/ai/settings",
      multipart: false,
    ),
    "getCatalogProduct": ApiOperation(
      operationId: "getCatalogProduct",
      method: "GET",
      pathTemplate: "/api/v1/catalog/products/{productId}",
      multipart: false,
    ),
    "getCatalogWorkbench": ApiOperation(
      operationId: "getCatalogWorkbench",
      method: "GET",
      pathTemplate: "/api/v1/catalog-admin/workbench",
      multipart: false,
    ),
    "getConsumptionReport": ApiOperation(
      operationId: "getConsumptionReport",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/reports/consumption",
      multipart: false,
    ),
    "getHome": ApiOperation(
      operationId: "getHome",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}",
      multipart: false,
    ),
    "getHomeDashboard": ApiOperation(
      operationId: "getHomeDashboard",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/dashboard",
      multipart: false,
    ),
    "getInventoryReport": ApiOperation(
      operationId: "getInventoryReport",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/reports/inventory",
      multipart: false,
    ),
    "getLiveness": ApiOperation(
      operationId: "getLiveness",
      method: "GET",
      pathTemplate: "/health/live",
      multipart: false,
    ),
    "getMetrics": ApiOperation(
      operationId: "getMetrics",
      method: "GET",
      pathTemplate: "/metrics",
      multipart: false,
    ),
    "getPurchaseReport": ApiOperation(
      operationId: "getPurchaseReport",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/reports/purchases",
      multipart: false,
    ),
    "getPurchaseSummary": ApiOperation(
      operationId: "getPurchaseSummary",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/purchase-summary",
      multipart: false,
    ),
    "getReadiness": ApiOperation(
      operationId: "getReadiness",
      method: "GET",
      pathTemplate: "/health/ready",
      multipart: false,
    ),
    "getReceipt": ApiOperation(
      operationId: "getReceipt",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/receipts/{receiptId}",
      multipart: false,
    ),
    "getShoppingList": ApiOperation(
      operationId: "getShoppingList",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/shopping-lists/{listId}",
      multipart: false,
    ),
    "getShoppingSuggestionExplanation": ApiOperation(
      operationId: "getShoppingSuggestionExplanation",
      method: "GET",
      pathTemplate:
          "/api/v1/homes/{homeId}/shopping-suggestions/{suggestionId}/explanation",
      multipart: false,
    ),
    "getStockCountSession": ApiOperation(
      operationId: "getStockCountSession",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/stock-count-sessions/{sessionId}",
      multipart: false,
    ),
    "getStockPreference": ApiOperation(
      operationId: "getStockPreference",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/stock-preferences/{homeProductId}",
      multipart: false,
    ),
    "getSuggestionBacktest": ApiOperation(
      operationId: "getSuggestionBacktest",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/suggestion-backtests/{backtestId}",
      multipart: false,
    ),
    "getSuggestionReport": ApiOperation(
      operationId: "getSuggestionReport",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/reports/suggestions",
      multipart: false,
    ),
    "getSystemInfo": ApiOperation(
      operationId: "getSystemInfo",
      method: "GET",
      pathTemplate: "/api/v1/system/info",
      multipart: false,
    ),
    "keepExistingCatalogConflict": ApiOperation(
      operationId: "keepExistingCatalogConflict",
      method: "POST",
      pathTemplate:
          "/api/v1/catalog-admin/conflicts/{conflictId}/keep-existing",
      multipart: false,
    ),
    "leaveHome": ApiOperation(
      operationId: "leaveHome",
      method: "DELETE",
      pathTemplate: "/api/v1/homes/{homeId}/memberships/me",
      multipart: false,
    ),
    "listConsumptionEstimates": ApiOperation(
      operationId: "listConsumptionEstimates",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/consumption-estimates",
      multipart: false,
    ),
    "listDeviceSessions": ApiOperation(
      operationId: "listDeviceSessions",
      method: "GET",
      pathTemplate: "/api/v1/auth/sessions",
      multipart: false,
    ),
    "listHomeLocations": ApiOperation(
      operationId: "listHomeLocations",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/locations",
      multipart: false,
    ),
    "listHomeMemberships": ApiOperation(
      operationId: "listHomeMemberships",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/memberships",
      multipart: false,
    ),
    "listHomeProducts": ApiOperation(
      operationId: "listHomeProducts",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/products",
      multipart: false,
    ),
    "listHomes": ApiOperation(
      operationId: "listHomes",
      method: "GET",
      pathTemplate: "/api/v1/homes",
      multipart: false,
    ),
    "listHomeStock": ApiOperation(
      operationId: "listHomeStock",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/stock",
      multipart: false,
    ),
    "listInventoryBalances": ApiOperation(
      operationId: "listInventoryBalances",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/inventory-balances",
      multipart: false,
    ),
    "listPriceComparisons": ApiOperation(
      operationId: "listPriceComparisons",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/price-comparisons",
      multipart: false,
    ),
    "listReceipts": ApiOperation(
      operationId: "listReceipts",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/receipts",
      multipart: false,
    ),
    "listShoppingLists": ApiOperation(
      operationId: "listShoppingLists",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/shopping-lists",
      multipart: false,
    ),
    "listShoppingSuggestions": ApiOperation(
      operationId: "listShoppingSuggestions",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/shopping-suggestions",
      multipart: false,
    ),
    "listStockCountSessions": ApiOperation(
      operationId: "listStockCountSessions",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/stock-count-sessions",
      multipart: false,
    ),
    "listStockMovements": ApiOperation(
      operationId: "listStockMovements",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/stock-movements",
      multipart: false,
    ),
    "login": ApiOperation(
      operationId: "login",
      method: "POST",
      pathTemplate: "/api/v1/auth/login",
      multipart: false,
    ),
    "logout": ApiOperation(
      operationId: "logout",
      method: "POST",
      pathTemplate: "/api/v1/auth/logout",
      multipart: false,
    ),
    "previewCatalogMerge": ApiOperation(
      operationId: "previewCatalogMerge",
      method: "POST",
      pathTemplate: "/api/v1/catalog-admin/merges/preview",
      multipart: false,
    ),
    "pullHomeSynchronization": ApiOperation(
      operationId: "pullHomeSynchronization",
      method: "GET",
      pathTemplate: "/api/v1/homes/{homeId}/sync/pull",
      multipart: false,
    ),
    "pushHomeSynchronization": ApiOperation(
      operationId: "pushHomeSynchronization",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/sync/push",
      multipart: false,
    ),
    "putAiProviderCredential": ApiOperation(
      operationId: "putAiProviderCredential",
      method: "PUT",
      pathTemplate: "/api/v1/homes/{homeId}/ai/credentials/{providerId}",
      multipart: false,
    ),
    "putAiSettings": ApiOperation(
      operationId: "putAiSettings",
      method: "PUT",
      pathTemplate: "/api/v1/homes/{homeId}/ai/settings",
      multipart: false,
    ),
    "putCatalogIcon": ApiOperation(
      operationId: "putCatalogIcon",
      method: "PUT",
      pathTemplate: "/api/v1/catalog-admin/icons/{targetType}/{targetId}",
      multipart: false,
    ),
    "putStockCountLine": ApiOperation(
      operationId: "putStockCountLine",
      method: "PUT",
      pathTemplate:
          "/api/v1/homes/{homeId}/stock-count-sessions/{sessionId}/lines/{lineId}",
      multipart: false,
    ),
    "putStockPreference": ApiOperation(
      operationId: "putStockPreference",
      method: "PUT",
      pathTemplate: "/api/v1/homes/{homeId}/stock-preferences/{homeProductId}",
      multipart: false,
    ),
    "rebuildInventoryBalances": ApiOperation(
      operationId: "rebuildInventoryBalances",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/inventory-balances/rebuild",
      multipart: false,
    ),
    "refreshSession": ApiOperation(
      operationId: "refreshSession",
      method: "POST",
      pathTemplate: "/api/v1/auth/refresh",
      multipart: false,
    ),
    "registerAccount": ApiOperation(
      operationId: "registerAccount",
      method: "POST",
      pathTemplate: "/api/v1/auth/register",
      multipart: false,
    ),
    "requestPasswordReset": ApiOperation(
      operationId: "requestPasswordReset",
      method: "POST",
      pathTemplate: "/api/v1/auth/password-reset/request",
      multipart: false,
    ),
    "resendEmailVerification": ApiOperation(
      operationId: "resendEmailVerification",
      method: "POST",
      pathTemplate: "/api/v1/auth/verify-email/resend",
      multipart: false,
    ),
    "reverseCatalogMerge": ApiOperation(
      operationId: "reverseCatalogMerge",
      method: "POST",
      pathTemplate: "/api/v1/catalog-admin/merges/{mergeId}/reverse",
      multipart: false,
    ),
    "reviewAiExtractionCandidate": ApiOperation(
      operationId: "reviewAiExtractionCandidate",
      method: "PUT",
      pathTemplate:
          "/api/v1/homes/{homeId}/ai/extractions/{extractionId}/candidates/{position}",
      multipart: false,
    ),
    "revokeDeviceSession": ApiOperation(
      operationId: "revokeDeviceSession",
      method: "DELETE",
      pathTemplate: "/api/v1/auth/sessions/{sessionId}",
      multipart: false,
    ),
    "searchCatalogProducts": ApiOperation(
      operationId: "searchCatalogProducts",
      method: "GET",
      pathTemplate: "/api/v1/catalog/products",
      multipart: false,
    ),
    "setShoppingListLineChecked": ApiOperation(
      operationId: "setShoppingListLineChecked",
      method: "PUT",
      pathTemplate:
          "/api/v1/homes/{homeId}/shopping-lists/{listId}/lines/{lineId}/checked",
      multipart: false,
    ),
    "startStockCountSession": ApiOperation(
      operationId: "startStockCountSession",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/stock-count-sessions",
      multipart: false,
    ),
    "submitCatalogProposal": ApiOperation(
      operationId: "submitCatalogProposal",
      method: "POST",
      pathTemplate: "/api/v1/catalog/proposals",
      multipart: false,
    ),
    "switchHome": ApiOperation(
      operationId: "switchHome",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/switch",
      multipart: false,
    ),
    "transferHomeOwnership": ApiOperation(
      operationId: "transferHomeOwnership",
      method: "POST",
      pathTemplate: "/api/v1/homes/{homeId}/ownership-transfer",
      multipart: false,
    ),
    "verifyEmail": ApiOperation(
      operationId: "verifyEmail",
      method: "POST",
      pathTemplate: "/api/v1/auth/verify-email",
      multipart: false,
    ),
  };

  Future<HealthStatus> getLiveness() async {
    final response = await _get('/health/live', accept: 'application/json');
    return HealthStatus.fromJson(_decodeObject(response.body));
  }

  Future<ReadinessStatus> getReadiness() async {
    final response = await _get('/health/ready', accept: 'application/json');
    return ReadinessStatus.fromJson(_decodeObject(response.body));
  }

  Future<SystemInfo> getSystemInfo() async {
    final response = await _get(
      '/api/v1/system/info',
      accept: 'application/json',
    );
    return SystemInfo.fromJson(_decodeObject(response.body));
  }

  Future<String> getMetrics() async {
    final response = await _get('/metrics', accept: 'text/plain');
    return response.body;
  }

  Future<SyncPushResponse> pushHomeSynchronization({
    required String homeId,
    required String idempotencyKey,
    required String batchId,
    required String deviceId,
    required String? lastPulledCursor,
    required List<SyncOperation> operations,
  }) async {
    final response = await _postJson(
      '/api/v1/homes/${Uri.encodeComponent(homeId)}/sync/push',
      body: <String, Object?>{
        'protocolVersion': 1,
        'batchId': batchId,
        'deviceId': deviceId,
        'lastPulledCursor': lastPulledCursor,
        'operations': operations
            .map((operation) => operation.toJson())
            .toList(growable: false),
      },
      extraHeaders: <String, String>{'Idempotency-Key': idempotencyKey},
    );
    return SyncPushResponse.fromJson(_decodeObject(response.body));
  }

  Future<SyncPullResponse> pullHomeSynchronization({
    required String homeId,
    String? cursor,
    int limit = 250,
  }) async {
    final response = await _get(
      '/api/v1/homes/${Uri.encodeComponent(homeId)}/sync/pull',
      accept: 'application/json',
      query: <String, String>{'cursor': ?cursor, 'limit': limit.toString()},
    );
    return SyncPullResponse.fromJson(_decodeObject(response.body));
  }

  Future<SyncBootstrapResponse> bootstrapHomeSynchronization({
    required String homeId,
  }) async {
    final response = await _get(
      '/api/v1/homes/${Uri.encodeComponent(homeId)}/sync/bootstrap',
      accept: 'application/json',
    );
    return SyncBootstrapResponse.fromJson(_decodeObject(response.body));
  }

  Future<ApiResponse> invokeOperation({
    required String operationId,
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
    Map<String, Object?>? body,
    Map<String, String> formFields = const <String, String>{},
    List<http.MultipartFile> files = const <http.MultipartFile>[],
  }) async {
    final operation = operations[operationId];
    if (operation == null) {
      throw ArgumentError.value(
        operationId,
        'operationId',
        'is not in the contract',
      );
    }

    var requestPath = operation.pathTemplate;
    final expectedNames = RegExp(
      r'\{([^}]+)\}',
    ).allMatches(requestPath).map((match) => match.group(1)!).toSet();
    final missing = expectedNames.difference(pathParameters.keys.toSet());
    final unexpected = pathParameters.keys.toSet().difference(expectedNames);
    if (missing.isNotEmpty || unexpected.isNotEmpty) {
      throw ArgumentError(
        'Invalid path parameters for $operationId; '
        'missing: $missing, unexpected: $unexpected.',
      );
    }
    for (final entry in pathParameters.entries) {
      requestPath = requestPath.replaceAll(
        '{${entry.key}}',
        Uri.encodeComponent(entry.value),
      );
    }

    late final http.Response response;
    final requestHeaders = <String, String>{
      ..._defaultHeaders,
      ...headers,
      'Accept': 'application/json',
    };
    if (operation.multipart) {
      if (body != null) {
        throw ArgumentError.value(
          body,
          'body',
          'is invalid for multipart operations',
        );
      }
      final request = http.MultipartRequest(
        operation.method,
        _endpoint(requestPath, query: query),
      )..headers.addAll(requestHeaders);
      request.fields.addAll(formFields);
      request.files.addAll(files);
      response = await http.Response.fromStream(
        await _httpClient.send(request),
      );
    } else {
      if (formFields.isNotEmpty || files.isNotEmpty) {
        throw ArgumentError('Multipart fields are invalid for $operationId.');
      }
      final request = http.Request(
        operation.method,
        _endpoint(requestPath, query: query),
      )..headers.addAll(requestHeaders);
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      response = await http.Response.fromStream(
        await _httpClient.send(request),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response);
    }
    final responseBody = response.bodyBytes.isEmpty
        ? null
        : _decodeResponseBody(response);
    return ApiResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: responseBody,
    );
  }

  Future<ApiResponse> acceptHomeInvitation({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "acceptHomeInvitation",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> applyCatalogMerge({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "applyCatalogMerge",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> approveReceiptLine({
    required String homeId,
    required String receiptId,
    required String lineId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "approveReceiptLine",
      pathParameters: <String, String>{
        "homeId": homeId,
        "receiptId": receiptId,
        "lineId": lineId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> changeHomeMembershipRole({
    required String homeId,
    required String userId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "changeHomeMembershipRole",
      pathParameters: <String, String>{"homeId": homeId, "userId": userId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> closeStockCountSession({
    required String homeId,
    required String sessionId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "closeStockCountSession",
      pathParameters: <String, String>{
        "homeId": homeId,
        "sessionId": sessionId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> commitReceipt({
    required String homeId,
    required String receiptId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "commitReceipt",
      pathParameters: <String, String>{
        "homeId": homeId,
        "receiptId": receiptId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> completePasswordReset({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "completePasswordReset",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createAiExtraction({
    required String homeId,
    Map<String, String> formFields = const <String, String>{},
    List<http.MultipartFile> files = const <http.MultipartFile>[],
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createAiExtraction",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      formFields: formFields,
      files: files,
    );
  }

  Future<ApiResponse> createHome({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createHome",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createHomeInvitation({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createHomeInvitation",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createHomeLocation({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createHomeLocation",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createHomeProduct({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createHomeProduct",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createReceipt({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createReceipt",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createReceiptLine({
    required String homeId,
    required String receiptId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createReceiptLine",
      pathParameters: <String, String>{
        "homeId": homeId,
        "receiptId": receiptId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createShoppingList({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createShoppingList",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createShoppingListLine({
    required String homeId,
    required String listId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createShoppingListLine",
      pathParameters: <String, String>{"homeId": homeId, "listId": listId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createShoppingSuggestionFeedback({
    required String homeId,
    required String suggestionId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createShoppingSuggestionFeedback",
      pathParameters: <String, String>{
        "homeId": homeId,
        "suggestionId": suggestionId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createShoppingSuggestionRun({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createShoppingSuggestionRun",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createStockAdjustment({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createStockAdjustment",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createStore({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createStore",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> createSuggestionBacktest({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "createSuggestionBacktest",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> decideCatalogProposal({
    required String proposalId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "decideCatalogProposal",
      pathParameters: <String, String>{"proposalId": proposalId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> deleteAiProviderCredential({
    required String homeId,
    required String providerId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "deleteAiProviderCredential",
      pathParameters: <String, String>{
        "homeId": homeId,
        "providerId": providerId,
      },
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getAiExtraction({
    required String homeId,
    required String extractionId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getAiExtraction",
      pathParameters: <String, String>{
        "homeId": homeId,
        "extractionId": extractionId,
      },
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getAiSettings({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getAiSettings",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getCatalogProduct({
    required String productId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getCatalogProduct",
      pathParameters: <String, String>{"productId": productId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getCatalogWorkbench({
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getCatalogWorkbench",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getConsumptionReport({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getConsumptionReport",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getHome({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getHome",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getHomeDashboard({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getHomeDashboard",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getInventoryReport({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getInventoryReport",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getPurchaseReport({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getPurchaseReport",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getPurchaseSummary({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getPurchaseSummary",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getReceipt({
    required String homeId,
    required String receiptId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getReceipt",
      pathParameters: <String, String>{
        "homeId": homeId,
        "receiptId": receiptId,
      },
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getShoppingList({
    required String homeId,
    required String listId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getShoppingList",
      pathParameters: <String, String>{"homeId": homeId, "listId": listId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getShoppingSuggestionExplanation({
    required String homeId,
    required String suggestionId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getShoppingSuggestionExplanation",
      pathParameters: <String, String>{
        "homeId": homeId,
        "suggestionId": suggestionId,
      },
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getStockCountSession({
    required String homeId,
    required String sessionId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getStockCountSession",
      pathParameters: <String, String>{
        "homeId": homeId,
        "sessionId": sessionId,
      },
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getStockPreference({
    required String homeId,
    required String homeProductId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getStockPreference",
      pathParameters: <String, String>{
        "homeId": homeId,
        "homeProductId": homeProductId,
      },
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getSuggestionBacktest({
    required String homeId,
    required String backtestId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getSuggestionBacktest",
      pathParameters: <String, String>{
        "homeId": homeId,
        "backtestId": backtestId,
      },
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> getSuggestionReport({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "getSuggestionReport",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> keepExistingCatalogConflict({
    required String conflictId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "keepExistingCatalogConflict",
      pathParameters: <String, String>{"conflictId": conflictId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> leaveHome({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "leaveHome",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listConsumptionEstimates({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listConsumptionEstimates",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listDeviceSessions({
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listDeviceSessions",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listHomeLocations({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listHomeLocations",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listHomeMemberships({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listHomeMemberships",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listHomeProducts({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listHomeProducts",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listHomes({
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listHomes",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listHomeStock({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listHomeStock",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listInventoryBalances({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listInventoryBalances",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listPriceComparisons({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listPriceComparisons",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listReceipts({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listReceipts",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listShoppingLists({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listShoppingLists",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listShoppingSuggestions({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listShoppingSuggestions",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listStockCountSessions({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listStockCountSessions",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> listStockMovements({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "listStockMovements",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> login({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "login",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> logout({
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "logout",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> previewCatalogMerge({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "previewCatalogMerge",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> putAiProviderCredential({
    required String homeId,
    required String providerId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "putAiProviderCredential",
      pathParameters: <String, String>{
        "homeId": homeId,
        "providerId": providerId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> putAiSettings({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "putAiSettings",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> putCatalogIcon({
    required String targetType,
    required String targetId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "putCatalogIcon",
      pathParameters: <String, String>{
        "targetType": targetType,
        "targetId": targetId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> putStockCountLine({
    required String homeId,
    required String sessionId,
    required String lineId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "putStockCountLine",
      pathParameters: <String, String>{
        "homeId": homeId,
        "sessionId": sessionId,
        "lineId": lineId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> putStockPreference({
    required String homeId,
    required String homeProductId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "putStockPreference",
      pathParameters: <String, String>{
        "homeId": homeId,
        "homeProductId": homeProductId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> rebuildInventoryBalances({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "rebuildInventoryBalances",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> refreshSession({
    Map<String, Object?>? body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "refreshSession",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> registerAccount({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "registerAccount",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> requestPasswordReset({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "requestPasswordReset",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> resendEmailVerification({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "resendEmailVerification",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> reverseCatalogMerge({
    required String mergeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "reverseCatalogMerge",
      pathParameters: <String, String>{"mergeId": mergeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> reviewAiExtractionCandidate({
    required String homeId,
    required String extractionId,
    required String position,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "reviewAiExtractionCandidate",
      pathParameters: <String, String>{
        "homeId": homeId,
        "extractionId": extractionId,
        "position": position,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> revokeDeviceSession({
    required String sessionId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "revokeDeviceSession",
      pathParameters: <String, String>{"sessionId": sessionId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> searchCatalogProducts({
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "searchCatalogProducts",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> setShoppingListLineChecked({
    required String homeId,
    required String listId,
    required String lineId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "setShoppingListLineChecked",
      pathParameters: <String, String>{
        "homeId": homeId,
        "listId": listId,
        "lineId": lineId,
      },
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> startStockCountSession({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "startStockCountSession",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> submitCatalogProposal({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "submitCatalogProposal",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> switchHome({
    required String homeId,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "switchHome",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
    );
  }

  Future<ApiResponse> transferHomeOwnership({
    required String homeId,
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "transferHomeOwnership",
      pathParameters: <String, String>{"homeId": homeId},
      query: query,
      headers: headers,
      body: body,
    );
  }

  Future<ApiResponse> verifyEmail({
    required Map<String, Object?> body,
    Map<String, String>? query,
    Map<String, String> headers = const <String, String>{},
  }) {
    return invokeOperation(
      operationId: "verifyEmail",
      pathParameters: const <String, String>{},
      query: query,
      headers: headers,
      body: body,
    );
  }

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<http.Response> _get(
    String path, {
    required String accept,
    Map<String, String>? query,
  }) async {
    final response = await _httpClient.get(
      _endpoint(path, query: query),
      headers: <String, String>{..._defaultHeaders, 'Accept': accept},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response);
    }
    return response;
  }

  Future<http.Response> _postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    final response = await _httpClient.post(
      _endpoint(path),
      headers: <String, String>{
        ..._defaultHeaders,
        ...extraHeaders,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response);
    }
    return response;
  }

  Uri _endpoint(String path, {Map<String, String>? query}) {
    return baseUri.replace(
      path: path,
      queryParameters: query?.isEmpty ?? true ? null : query,
      fragment: null,
    );
  }

  ProvidentiaApiException _toException(http.Response response) {
    ProblemDetails problem;
    try {
      problem = ProblemDetails.fromJson(_decodeObject(response.body));
    } on FormatException {
      problem = ProblemDetails(
        type: 'about:blank',
        title: 'HTTP request failed',
        status: response.statusCode,
        requestId: response.headers['x-request-id'] ?? 'unavailable',
        detail: response.body.isEmpty ? null : response.body,
      );
    }
    return ProvidentiaApiException(
      statusCode: response.statusCode,
      problem: problem,
      requestId: response.headers['x-request-id'] ?? problem.requestId,
    );
  }
}

Object? _decodeResponseBody(http.Response response) {
  final contentType = response.headers['content-type']?.toLowerCase() ?? '';
  final source = utf8.decode(response.bodyBytes);
  if (contentType.contains('json') ||
      source.startsWith('{') ||
      source.startsWith('[')) {
    return jsonDecode(source);
  }
  return source;
}

Map<String, Object?> _decodeObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return decoded;
}

Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected "$key" to be an object.');
  }
  return value;
}

Map<String, Object?>? _optionalObject(Map<String, Object?> json, String key) {
  final value = json[key];
  return value == null ? null : _objectValue(value, key);
}

List<Map<String, Object?>> _requiredObjectList(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('Expected "$key" to be an array.');
  }
  return value.map((item) => _objectValue(item, key)).toList(growable: false);
}

Map<String, Object?> _objectValue(Object? value, String key) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected "$key" to be an object.');
  }
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  return _stringValue(json[key], key);
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value == null ? null : _stringValue(value, key);
}

String _stringValue(Object? value, String key) {
  if (value is! String) {
    throw FormatException('Expected "$key" to be a string.');
  }
  return value;
}

int _integerValue(Object? value, String key) {
  if (value is! int) {
    throw FormatException('Expected "$key" to be an integer.');
  }
  return value;
}

int _requiredInteger(Map<String, Object?> json, String key) {
  return _integerValue(json[key], key);
}

int? _optionalInteger(Map<String, Object?> json, String key) {
  final value = json[key];
  return value == null ? null : _integerValue(value, key);
}

bool _requiredBoolean(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('Expected "$key" to be a boolean.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Expected "$key" to be an RFC 3339 date-time.');
  }
  return parsed;
}
