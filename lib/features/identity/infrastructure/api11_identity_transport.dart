import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

final class Api11IdentityTransport
    implements IdentityTransportPort, AbortBoundIdentityTransportPort {
  const Api11IdentityTransport(
    this._client, {
    required this.sessionTransport,
    this.networkTimeout = const Duration(seconds: 12),
  });

  final ProvidentiaApiClient _client;
  @override
  final Duration networkTimeout;

  @override
  final ClientSessionTransport sessionTransport;

  @override
  Future<LoginLinkStartReceipt> startLoginLink(
    LoginLinkStartCommand command,
  ) async {
    try {
      final response = await _invoke(
        operationId: 'startLoginLink',
        body: <String, Object?>{
          'requestId': command.requestId,
          'email': command.email,
          'applicationKind': 'homeowner',
          'pollChallenge': command.pollChallenge,
          'codeChallenge': command.codeChallenge,
          'codeChallengeMethod': 'S256',
          'state': command.state,
          'installationId': command.device.id,
          'deviceName': command.device.name,
          'platform': command.device.platform,
          'transport': _transportName(command.transport),
          if (command.requestedSessionIdleSeconds != null)
            'requestedSessionIdleSeconds': command.requestedSessionIdleSeconds,
        },
      );
      final object = response.requireObject();
      if (object['accepted'] != true) {
        throw const FormatException('Expected a generic accepted response.');
      }
      final returnedRequestId = _string(object, 'requestId');
      if (returnedRequestId != command.requestId) {
        throw const FormatException('Login request identity changed.');
      }
      return LoginLinkStartReceipt(
        requestId: returnedRequestId,
        expiresAt: _dateTime(object, 'expiresAt'),
        pollInterval: Duration(
          seconds: _integer(object, 'pollIntervalSeconds'),
        ),
      );
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on FormatException {
      throw _malformedIdentityResponse('Invalid login request response.');
    } on ArgumentError {
      throw _malformedIdentityResponse('Invalid login request response.');
    } on http.ClientException {
      throw _identityNetworkFailure();
    }
  }

  @override
  Future<LoginLinkStatusView> getLoginLinkStatus({
    required String requestId,
    required String pollToken,
  }) async {
    try {
      final object = (await _invoke(
        operationId: 'getLoginLinkStatus',
        pathParameters: <String, String>{'requestId': requestId},
        body: <String, Object?>{'pollToken': pollToken},
      )).requireObject();
      if (_string(object, 'applicationKind') != 'homeowner') {
        throw const FormatException('Login application kind changed.');
      }
      return LoginLinkStatusView(
        requestId: _string(object, 'requestId'),
        status: _loginStatus(_string(object, 'status')),
        expiresAt: _dateTime(object, 'expiresAt'),
        approvedAt: _optionalDateTime(object['approvedAt']),
      );
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on FormatException {
      throw _malformedIdentityResponse('Invalid login request status.');
    } on ArgumentError {
      throw _malformedIdentityResponse('Invalid login request status.');
    } on http.ClientException {
      throw _identityNetworkFailure();
    }
  }

  @override
  Future<SessionGrant> exchangeLoginLink({
    required PendingLoginLinkRequest request,
  }) async {
    try {
      final response = await _invoke(
        operationId: 'exchangeLoginLink',
        pathParameters: <String, String>{'requestId': request.requestId},
        body: <String, Object?>{
          'pollToken': request.pollToken,
          'codeVerifier': request.codeVerifier,
          'state': request.state,
        },
      );
      return _grant(response.requireObject());
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on FormatException {
      throw _malformedIdentityResponse('Invalid session response.');
    } on ArgumentError {
      throw _malformedIdentityResponse('Invalid session response.');
    } on http.ClientException {
      throw _identityNetworkFailure();
    }
  }

  @override
  Future<void> cancelLoginLink({
    required String requestId,
    required String pollToken,
  }) async {
    try {
      await _invoke(
        operationId: 'cancelLoginLink',
        pathParameters: <String, String>{'requestId': requestId},
        body: <String, Object?>{'pollToken': pollToken},
      );
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on http.ClientException {
      throw _identityNetworkFailure();
    }
  }

  @override
  Future<SessionGrant> refreshSession({String? refreshToken}) async {
    try {
      final response = await _invoke(
        operationId: 'refreshSession',
        body: <String, Object?>{
          if (sessionTransport == ClientSessionTransport.nativeBearer)
            'refreshToken': refreshToken,
        },
      );
      return _grant(response.requireObject());
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on FormatException {
      throw _malformedIdentityResponse('Invalid session response.');
    } on ArgumentError {
      throw _malformedIdentityResponse('Invalid session response.');
    } on http.ClientException {
      throw _identityNetworkFailure();
    }
  }

  @override
  Future<CurrentUserView> getCurrentUser({
    String? accessToken,
    String? csrfToken,
  }) async {
    try {
      final object = (await _invoke(
        operationId: 'getCurrentUser',
        headers: _authorization(accessToken, csrfToken),
      )).requireObject();
      final homes = object['homes'];
      final pendingInvitations = object['pendingInvitations'];
      final roles = object['platformRoles'];
      if (homes is! List<Object?> ||
          pendingInvitations is! List<Object?> ||
          roles is! List<Object?>) {
        throw const FormatException('Expected user collections.');
      }
      return CurrentUserView(
        userId: _string(object, 'userId'),
        email: _string(object, 'email'),
        emailVerified: _boolean(object, 'emailVerified'),
        displayName: _optionalString(object['displayName']),
        locale: _optionalString(object['locale']),
        timezone: _optionalString(object['timezone']),
        activeHomeId: _optionalString(object['activeHomeId']),
        homes: homes.map(_currentUserHome).toList(growable: false),
        pendingInvitations: pendingInvitations
            .map(_currentUserInvitation)
            .toList(growable: false),
        platformRoles: roles.map(_platformRole).toSet(),
        currentSession: _deviceSession(object['currentSession']),
      );
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on FormatException {
      throw _malformedIdentityResponse('Account details were invalid.');
    } on ArgumentError {
      throw _malformedIdentityResponse('Account details were invalid.');
    } on http.ClientException {
      throw _identityNetworkFailure();
    }
  }

  @override
  Future<void> logout({
    String? accessToken,
    String? refreshToken,
    String? csrfToken,
  }) async {
    try {
      await _invoke(
        operationId: 'logout',
        headers: _authorization(accessToken, csrfToken),
        body:
            sessionTransport == ClientSessionTransport.nativeBearer &&
                refreshToken != null
            ? <String, Object?>{'refreshToken': refreshToken}
            : null,
      );
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on http.ClientException {
      throw _identityNetworkFailure();
    }
  }

  @override
  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  }) async {
    try {
      final object = (await _invoke(
        operationId: 'listDeviceSessions',
        headers: _authorization(accessToken, csrfToken),
      )).requireObject();
      final data = object['data'];
      if (data is! List<Object?>) {
        throw const FormatException('Expected device session data.');
      }
      return data.map(_deviceSession).toList(growable: false);
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on FormatException {
      throw _malformedIdentityResponse('Invalid device session list.');
    } on ArgumentError {
      throw _malformedIdentityResponse('Invalid device session list.');
    } on http.ClientException {
      throw _identityNetworkFailure();
    }
  }

  @override
  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  }) async {
    try {
      await _invoke(
        operationId: 'revokeDeviceSession',
        pathParameters: <String, String>{'sessionId': sessionId},
        headers: _authorization(accessToken, csrfToken),
      );
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on http.ClientException {
      throw _identityNetworkFailure();
    }
  }

  SessionGrant _grant(Map<String, Object?> json) {
    final returnedTransport = _sessionTransport(_string(json, 'transport'));
    if (returnedTransport != sessionTransport) {
      throw const FormatException('Session transport changed.');
    }
    if (!json.containsKey('refreshExpiresAt') ||
        !json.containsKey('idleExpiresAt') ||
        !json.containsKey('refreshIdleTtlSeconds')) {
      throw const FormatException('Missing session expiry declaration.');
    }
    final refreshIdleTtlSeconds = _optionalInteger(
      json['refreshIdleTtlSeconds'],
    );
    final metadata = SessionMetadata(
      sessionId: _string(json, 'sessionId'),
      deviceId: _string(json, 'deviceId'),
      installationId: _string(json, 'installationId'),
      userId: _string(json, 'userId'),
      accessExpiresAt: _dateTime(json, 'accessExpiresAt'),
      refreshExpiresAt: _optionalDateTime(json['refreshExpiresAt']),
      idleExpiresAt: _optionalDateTime(json['idleExpiresAt']),
      refreshIdleTtl: refreshIdleTtlSeconds == null
          ? null
          : Duration(seconds: refreshIdleTtlSeconds),
      transport: returnedTransport,
      activeHomeId: _optionalString(json['activeHomeId']),
    );
    final secrets = switch (returnedTransport) {
      ClientSessionTransport.nativeBearer => SessionSecrets(
        accessToken: _string(json, 'accessToken'),
        refreshToken: _string(json, 'refreshToken'),
      ),
      ClientSessionTransport.webCookie => _webSessionSecrets(json),
    };
    return SessionGrant(metadata: metadata, secrets: secrets);
  }

  DeviceSessionView _deviceSession(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Expected a device session object.');
    }
    if (!value.containsKey('refreshExpiresAt') ||
        !value.containsKey('idleExpiresAt')) {
      throw const FormatException('Missing device session expiry declaration.');
    }
    return DeviceSessionView(
      id: _string(value, 'id'),
      deviceId: _string(value, 'deviceId'),
      deviceName: _optionalString(value['deviceName']) ?? 'Unknown device',
      platform: _optionalString(value['platform']) ?? 'unknown',
      transport: _sessionTransport(_string(value, 'transport')),
      current: _boolean(value, 'current'),
      activeHomeId: _optionalString(value['activeHomeId']),
      createdAt: _dateTime(value, 'createdAt'),
      lastSeenAt: _dateTime(value, 'lastSeenAt'),
      accessExpiresAt: _dateTime(value, 'accessExpiresAt'),
      refreshExpiresAt: _optionalDateTime(value['refreshExpiresAt']),
      idleExpiresAt: _optionalDateTime(value['idleExpiresAt']),
      revokedAt: _optionalDateTime(value['revokedAt']),
    );
  }

  CurrentUserHomeView _currentUserHome(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Expected a home object.');
    }
    return CurrentUserHomeView(
      id: _string(value, 'id'),
      name: _string(value, 'name'),
      role: _string(value, 'role'),
    );
  }

  CurrentUserInvitationView _currentUserInvitation(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Expected an invitation object.');
    }
    if (_string(value, 'status') != 'pending') {
      throw const FormatException('Expected a pending invitation.');
    }
    return CurrentUserInvitationView(
      id: _string(value, 'id'),
      homeId: _string(value, 'homeId'),
      homeName: _string(value, 'homeName'),
      inviterUserId: _string(value, 'inviterUserId'),
      inviterDisplayName: _optionalString(value['inviterDisplayName']),
      role: _string(value, 'role'),
      expiresAt: _dateTime(value, 'expiresAt'),
      revision: _integer(value, 'revision'),
    );
  }

  Map<String, String> _authorization(String? accessToken, String? csrfToken) =>
      <String, String>{
        if (sessionTransport == ClientSessionTransport.nativeBearer &&
            accessToken != null)
          'Authorization': 'Bearer $accessToken',
        if (sessionTransport == ClientSessionTransport.webCookie &&
            csrfToken != null)
          'X-CSRF-Token': csrfToken,
      };

  Future<ApiResponse> _invoke({
    required String operationId,
    Map<String, String> pathParameters = const <String, String>{},
    Map<String, String> headers = const <String, String>{},
    Map<String, Object?>? body,
  }) {
    if (networkTimeout <= Duration.zero) {
      throw ArgumentError.value(networkTimeout, 'networkTimeout');
    }
    final abort = Completer<void>();
    return _client
        .invokeOperation(
          operationId: operationId,
          pathParameters: pathParameters,
          headers: headers,
          body: body,
          abortTrigger: abort.future,
        )
        .timeout(
          networkTimeout,
          onTimeout: () {
            if (!abort.isCompleted) abort.complete();
            throw http.ClientException(
              'Identity request timed out and was aborted.',
            );
          },
        );
  }
}

SessionSecrets _webSessionSecrets(Map<String, Object?> json) {
  if (json['accessToken'] != null || json['refreshToken'] != null) {
    throw const FormatException(
      'Browser session responses cannot expose bearer credentials.',
    );
  }
  return SessionSecrets(csrfToken: _string(json, 'csrfToken'));
}

IdentityTransportException _malformedIdentityResponse(String detail) =>
    IdentityTransportException(
      kind: IdentityFailureKind.validation,
      safeMessage: 'The identity service returned invalid data. $detail',
    );

IdentityTransportException
_identityNetworkFailure() => const IdentityTransportException(
  kind: IdentityFailureKind.network,
  safeMessage:
      'The identity service could not be reached. Check your connection and try again.',
);

IdentityTransportException _identityFailure(ProvidentiaApiException error) {
  final kind = switch (error.statusCode) {
    400 || 422 => IdentityFailureKind.validation,
    401 => IdentityFailureKind.authentication,
    403 => IdentityFailureKind.forbidden,
    409 => IdentityFailureKind.conflict,
    410 => IdentityFailureKind.loginRequestExpired,
    429 => IdentityFailureKind.rateLimited,
    >= 500 => IdentityFailureKind.unavailable,
    _ => IdentityFailureKind.network,
  };
  final message = switch (kind) {
    IdentityFailureKind.authentication =>
      'This private login proof or session was not accepted.',
    IdentityFailureKind.loginRequestExpired =>
      'This login link expired. Request a new one.',
    IdentityFailureKind.forbidden => 'This session no longer has access.',
    IdentityFailureKind.rateLimited =>
      'Too many attempts. Wait a moment before trying again.',
    IdentityFailureKind.conflict =>
      'This login request was already completed. Request a new login link.',
    IdentityFailureKind.validation => 'Check the supplied sign-in details.',
    _ => 'The identity service is temporarily unavailable.',
  };
  return IdentityTransportException(kind: kind, safeMessage: message);
}

LoginLinkRequestStatus _loginStatus(String value) => switch (value) {
  'pending' => LoginLinkRequestStatus.pending,
  'approved' => LoginLinkRequestStatus.approved,
  'denied' => LoginLinkRequestStatus.denied,
  'exchanged' => LoginLinkRequestStatus.exchanged,
  'expired' => LoginLinkRequestStatus.expired,
  'cancelled' => LoginLinkRequestStatus.cancelled,
  _ => throw FormatException('Unknown login request status.'),
};

PlatformRole _platformRole(Object? value) => switch (value) {
  'platform_administrator' => PlatformRole.platformAdministrator,
  'catalog_curator' => PlatformRole.catalogCurator,
  'catalog_reviewer' => PlatformRole.catalogReviewer,
  'billing_operator' => PlatformRole.billingOperator,
  _ => throw const FormatException('Unknown platform role.'),
};

ClientSessionTransport _sessionTransport(String value) => switch (value) {
  'native' => ClientSessionTransport.nativeBearer,
  'web' => ClientSessionTransport.webCookie,
  _ => throw const FormatException('Unknown session transport.'),
};

String _transportName(ClientSessionTransport transport) => switch (transport) {
  ClientSessionTransport.nativeBearer => 'native',
  ClientSessionTransport.webCookie => 'web',
};

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value case final String text when text.isNotEmpty) return text;
  throw const FormatException('Expected a non-empty string or null.');
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Missing $key.');
}

int? _optionalInteger(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  throw const FormatException('Expected an integer or null.');
}

bool _boolean(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Missing $key.');
}

DateTime _dateTime(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  if (value == null) {
    throw FormatException('Invalid $key.');
  }
  return value.toUtc();
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  if (value case final String source) {
    final parsed = DateTime.tryParse(source);
    if (parsed != null) return parsed.toUtc();
  }
  throw const FormatException('Expected a date-time string or null.');
}
