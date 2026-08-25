import 'package:http/http.dart' as http;
import 'package:providentia/features/identity/application/login_link_approval_port.dart';
import 'package:providentia/features/identity/domain/login_link_approval_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

final class GeneratedLoginLinkApprovalTransport
    implements LoginLinkApprovalPort {
  const GeneratedLoginLinkApprovalTransport(this._client);

  final ProvidentiaApiClient _client;

  @override
  Future<void> prove(LoginLinkApprovalCapability capability) async {
    try {
      final object = (await _client.proveLoginLinkApproval(
        requestId: capability.requestId,
        body: _proof(capability),
      )).requireObject();
      if (object['valid'] != true ||
          _string(object, 'requestId') != capability.requestId ||
          _string(object, 'applicationKind') != 'homeowner') {
        throw const FormatException('Login approval proof changed.');
      }
      _dateTime(object, 'expiresAt');
    } on ProvidentiaApiException catch (error) {
      throw _failure(error);
    } on FormatException {
      throw const LoginLinkApprovalException(
        LoginLinkApprovalFailureKind.invalidResponse,
        'The login approval response was invalid.',
      );
    } on http.ClientException {
      throw const LoginLinkApprovalException(
        LoginLinkApprovalFailureKind.unavailable,
        'The login approval service is unavailable.',
      );
    }
  }

  @override
  Future<LoginLinkApprovalReview> review(
    LoginLinkApprovalCapability capability,
  ) async {
    try {
      final object = (await _client.reviewLoginLinkApproval(
        requestId: capability.requestId,
        body: _proof(capability),
      )).requireObject();
      if (_string(object, 'requestId') != capability.requestId ||
          _string(object, 'applicationKind') != 'homeowner') {
        throw const FormatException('Login approval review changed.');
      }
      return LoginLinkApprovalReview(
        requestId: capability.requestId,
        deviceName: _string(object, 'deviceName'),
        platform: _string(object, 'platform'),
        createdAt: _dateTime(object, 'createdAt'),
        expiresAt: _dateTime(object, 'expiresAt'),
      );
    } on ProvidentiaApiException catch (error) {
      throw _failure(error);
    } on FormatException {
      throw const LoginLinkApprovalException(
        LoginLinkApprovalFailureKind.invalidResponse,
        'The login approval response was invalid.',
      );
    } on ArgumentError {
      throw const LoginLinkApprovalException(
        LoginLinkApprovalFailureKind.invalidResponse,
        'The login approval response was invalid.',
      );
    } on http.ClientException {
      throw const LoginLinkApprovalException(
        LoginLinkApprovalFailureKind.unavailable,
        'The login approval service is unavailable.',
      );
    }
  }

  @override
  Future<void> decide({
    required LoginLinkApprovalCapability capability,
    required LoginLinkApprovalDecision decision,
  }) async {
    try {
      final object = (await _client.decideLoginLinkApproval(
        requestId: capability.requestId,
        body: <String, Object?>{
          ..._proof(capability),
          'decision': decision.name,
        },
      )).requireObject();
      if (_string(object, 'requestId') != capability.requestId ||
          _string(object, 'applicationKind') != 'homeowner' ||
          _string(object, 'status') != 'received') {
        throw const FormatException('Login approval decision changed.');
      }
    } on ProvidentiaApiException catch (error) {
      throw _failure(error);
    } on FormatException {
      throw const LoginLinkApprovalException(
        LoginLinkApprovalFailureKind.invalidResponse,
        'The login approval response was invalid.',
      );
    } on http.ClientException {
      throw const LoginLinkApprovalException(
        LoginLinkApprovalFailureKind.unavailable,
        'The login approval service is unavailable.',
      );
    }
  }

  Map<String, Object?> _proof(LoginLinkApprovalCapability capability) =>
      <String, Object?>{
        'applicationKind': 'homeowner',
        'approvalToken': capability.approvalToken,
      };
}

LoginLinkApprovalException _failure(ProvidentiaApiException error) {
  if (error.statusCode == 404 ||
      error.statusCode == 409 ||
      error.statusCode == 422) {
    return const LoginLinkApprovalException(
      LoginLinkApprovalFailureKind.invalidOrExpired,
      'This login approval link is invalid, expired, or already used.',
    );
  }
  if (error.statusCode == 429) {
    return const LoginLinkApprovalException(
      LoginLinkApprovalFailureKind.rateLimited,
      'Too many approval attempts were made. Try again later.',
    );
  }
  return const LoginLinkApprovalException(
    LoginLinkApprovalFailureKind.unavailable,
    'The login approval service is unavailable.',
  );
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

DateTime _dateTime(Map<String, Object?> object, String key) {
  final value = DateTime.tryParse(_string(object, key));
  if (value == null) throw FormatException('Invalid $key.');
  return value.toUtc();
}
