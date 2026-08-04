import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

/// Compatibility transport for the currently published Laminas API 1.7.
///
/// The product-facing application boundary is passwordless-first, but API 1.7
/// still authenticates with a password. This adapter keeps that compatibility
/// isolated so it can be deleted when the approved challenge contract lands.
final class Api17IdentityTransport
    implements IdentityTransportPort, LegacyPasswordIdentityTransportPort {
  Api17IdentityTransport({
    required ProvidentiaApiClient client,
    required this.sessionTransport,
  }) : _client = client;

  final ProvidentiaApiClient _client;

  @override
  final ClientSessionTransport sessionTransport;

  Future<SessionGrant> loginWithPassword({
    required String email,
    required String password,
    required DeviceDescriptor device,
  }) async {
    try {
      final response = await _client.login(
        body: <String, Object?>{
          'email': email.trim().toLowerCase(),
          'password': password,
          'deviceId': device.id,
          'deviceName': device.name,
          'platform': device.platform,
          'transport': _transportName,
        },
      );
      return _grant(response.requireObject());
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    }
  }

  @override
  Future<PasswordlessChallengeReceipt> requestPasswordlessChallenge({
    required String email,
  }) {
    throw const IdentityTransportException(
      kind: IdentityFailureKind.unavailable,
      safeMessage:
          'Passwordless sign-in is awaiting the published backend challenge contract.',
    );
  }

  @override
  Future<SessionGrant> completePasswordlessChallenge({
    required PasswordlessProof proof,
    required DeviceDescriptor device,
  }) {
    throw const IdentityTransportException(
      kind: IdentityFailureKind.unavailable,
      safeMessage:
          'Passwordless sign-in is awaiting the published backend challenge contract.',
    );
  }

  @override
  Future<SessionGrant> refreshSession({String? refreshToken}) async {
    try {
      final response = await _client.refreshSession(
        body: <String, Object?>{
          if (sessionTransport == ClientSessionTransport.nativeBearer)
            'refreshToken': refreshToken,
        },
      );
      return _grant(response.requireObject());
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    }
  }

  @override
  Future<void> logout({String? accessToken, String? csrfToken}) async {
    try {
      await _client.logout(headers: _authorization(accessToken, csrfToken));
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    }
  }

  @override
  Future<List<DeviceSessionView>> listDeviceSessions({
    String? accessToken,
    String? csrfToken,
  }) async {
    try {
      final response = await _client.listDeviceSessions(
        headers: _authorization(accessToken, csrfToken),
      );
      final object = response.requireObject();
      final data = object['data'];
      if (data is! List<Object?>) {
        throw const FormatException('Expected device session data.');
      }
      return data.map(_deviceSession).toList(growable: false);
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    } on FormatException {
      throw const IdentityTransportException(
        kind: IdentityFailureKind.unavailable,
        safeMessage: 'The server returned an invalid session list.',
      );
    }
  }

  @override
  Future<void> revokeDeviceSession({
    required String sessionId,
    String? accessToken,
    String? csrfToken,
  }) async {
    try {
      await _client.revokeDeviceSession(
        sessionId: sessionId,
        headers: _authorization(accessToken, csrfToken),
      );
    } on ProvidentiaApiException catch (error) {
      throw _identityFailure(error);
    }
  }

  String get _transportName => switch (sessionTransport) {
    ClientSessionTransport.nativeBearer => 'native',
    ClientSessionTransport.webCookie => 'web',
  };

  SessionGrant _grant(Map<String, Object?> json) {
    final metadata = SessionMetadata(
      sessionId: _string(json, 'sessionId'),
      deviceId: _string(json, 'deviceId'),
      accessExpiresAt: _dateTime(json, 'accessExpiresAt'),
      transport: sessionTransport,
    );
    final secrets = switch (sessionTransport) {
      ClientSessionTransport.nativeBearer => SessionSecrets(
        accessToken: _string(json, 'accessToken'),
        refreshToken: _string(json, 'refreshToken'),
      ),
      ClientSessionTransport.webCookie => SessionSecrets(
        csrfToken: _optionalString(json['csrfToken']),
      ),
    };
    return SessionGrant(metadata: metadata, secrets: secrets);
  }

  DeviceSessionView _deviceSession(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Expected a device session object.');
    }
    return DeviceSessionView(
      id: _string(value, 'id'),
      deviceId: _string(value, 'deviceId'),
      deviceName: _optionalString(value['deviceName']) ?? 'Unknown device',
      platform: _optionalString(value['platform']) ?? 'unknown',
      activeHomeId: _optionalString(value['activeHomeId']),
      createdAt: _dateTime(value, 'createdAt'),
      lastSeenAt: _dateTime(value, 'lastSeenAt'),
      revokedAt: _optionalDateTime(value['revokedAt']),
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
}

IdentityTransportException _identityFailure(ProvidentiaApiException error) {
  final kind = switch (error.statusCode) {
    400 || 422 => IdentityFailureKind.validation,
    401 => IdentityFailureKind.authentication,
    403 => IdentityFailureKind.forbidden,
    429 => IdentityFailureKind.rateLimited,
    >= 500 => IdentityFailureKind.unavailable,
    _ => IdentityFailureKind.network,
  };
  final message = switch (kind) {
    IdentityFailureKind.authentication =>
      'The sign-in details or session were not accepted.',
    IdentityFailureKind.forbidden => 'This session no longer has access.',
    IdentityFailureKind.rateLimited =>
      'Too many attempts. Wait a moment before trying again.',
    IdentityFailureKind.validation => 'Check the supplied sign-in details.',
    _ => 'The identity service is temporarily unavailable.',
  };
  return IdentityTransportException(kind: kind, safeMessage: message);
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key.');
  }
  return value;
}

String? _optionalString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

DateTime _dateTime(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  if (value == null) {
    throw FormatException('Invalid $key.');
  }
  return value.toUtc();
}

DateTime? _optionalDateTime(Object? value) => switch (value) {
  final String source => DateTime.tryParse(source)?.toUtc(),
  _ => null,
};
