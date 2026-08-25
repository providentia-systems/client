/// A short-lived login approval capability received only through an app-link
/// URI fragment. It intentionally has no serialization or equality helpers.
final class LoginLinkApprovalCapability {
  LoginLinkApprovalCapability._({
    required this.requestId,
    required this.approvalToken,
  });

  factory LoginLinkApprovalCapability.parse(Uri uri, {Uri? expectedBaseUri}) {
    final expected =
        expectedBaseUri ?? Uri.parse('providentia://login-link/homeowner');
    if (!_sameAppLinkBase(uri, expected) ||
        uri.hasQuery ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('This link is not for the homeowner app.');
    }
    final entries = <String, String>{};
    for (final component in uri.fragment.split('&')) {
      final separator = component.indexOf('=');
      if (separator <= 0 || separator == component.length - 1) {
        throw const FormatException('The login approval link is incomplete.');
      }
      final key = Uri.decodeQueryComponent(component.substring(0, separator));
      final value = Uri.decodeQueryComponent(
        component.substring(separator + 1),
      );
      if (entries.containsKey(key)) {
        throw const FormatException('The login approval link is ambiguous.');
      }
      entries[key] = value;
    }
    if (entries.length != 2 ||
        !entries.containsKey('requestId') ||
        !entries.containsKey('approval')) {
      throw const FormatException('The login approval link is incomplete.');
    }
    final requestId = entries['requestId']!;
    final approvalToken = entries['approval']!;
    if (!_uuidPattern.hasMatch(requestId) ||
        approvalToken.length < 40 ||
        approvalToken.length > 128 ||
        !_base64UrlPattern.hasMatch(approvalToken)) {
      throw const FormatException('The login approval link is invalid.');
    }
    return LoginLinkApprovalCapability._(
      requestId: requestId,
      approvalToken: approvalToken,
    );
  }

  final String requestId;
  final String approvalToken;

  @override
  String toString() => 'LoginLinkApprovalCapability(<redacted>)';
}

bool isHomeownerLoginLink(Uri uri, Uri expectedBaseUri) =>
    _sameAppLinkBase(uri, expectedBaseUri) &&
    !uri.hasQuery &&
    uri.userInfo.isEmpty &&
    uri.fragment.isNotEmpty;

bool _sameAppLinkBase(Uri uri, Uri expected) =>
    uri.scheme == expected.scheme &&
    uri.host == expected.host &&
    uri.port == expected.port &&
    uri.path == expected.path;

enum LoginLinkApprovalDecision { approve, deny }

final class LoginLinkApprovalReview {
  LoginLinkApprovalReview({
    required this.requestId,
    required this.deviceName,
    required this.platform,
    required this.createdAt,
    required this.expiresAt,
  }) {
    if (!_uuidPattern.hasMatch(requestId) ||
        deviceName.trim().isEmpty ||
        platform.trim().isEmpty ||
        !expiresAt.toUtc().isAfter(createdAt.toUtc())) {
      throw ArgumentError('The login approval review is invalid.');
    }
  }

  final String requestId;
  final String deviceName;
  final String platform;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime instant) => !expiresAt.isAfter(instant.toUtc());
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _base64UrlPattern = RegExp(r'^[A-Za-z0-9_-]+$');
