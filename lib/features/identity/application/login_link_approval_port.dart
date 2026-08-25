import 'package:providentia/features/identity/domain/login_link_approval_models.dart';

enum LoginLinkApprovalFailureKind {
  invalidOrExpired,
  rateLimited,
  unavailable,
  invalidResponse,
}

final class LoginLinkApprovalException implements Exception {
  const LoginLinkApprovalException(this.kind, this.safeMessage);

  final LoginLinkApprovalFailureKind kind;
  final String safeMessage;

  @override
  String toString() => 'LoginLinkApprovalException(${kind.name})';
}

abstract interface class LoginLinkApprovalPort {
  Future<void> prove(LoginLinkApprovalCapability capability);

  Future<LoginLinkApprovalReview> review(
    LoginLinkApprovalCapability capability,
  );

  Future<void> decide({
    required LoginLinkApprovalCapability capability,
    required LoginLinkApprovalDecision decision,
  });
}
