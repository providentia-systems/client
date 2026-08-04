import 'package:providentia/features/homes/domain/home_models.dart';

enum HomeFailureKind {
  authentication,
  authorization,
  membershipRevoked,
  conflict,
  validation,
  unavailable,
  network,
}

final class HomeTransportException implements Exception {
  const HomeTransportException({
    required this.kind,
    required this.safeMessage,
    this.homeId,
  });

  final HomeFailureKind kind;
  final String safeMessage;
  final String? homeId;

  bool get revoked => kind == HomeFailureKind.membershipRevoked;

  @override
  String toString() => 'HomeTransportException(${kind.name})';
}

abstract interface class HomeTransportPort {
  Future<List<HomeSummary>> listHomes();

  Future<HomeSummary> createHome(CreateHomeCommand command);

  Future<HomeSummary> switchActiveHome(String homeId);

  Future<List<HomeMembership>> listMemberships(String homeId);

  Future<void> changeMembershipRole({
    required String homeId,
    required String userId,
    required HomeRole role,
    required int expectedRevision,
  });

  Future<HomeInvitation> createInvitation({
    required String homeId,
    required String email,
    required HomeRole role,
  });

  Future<HomeSummary> acceptInvitation(String token);

  Future<void> leaveHome(String homeId);
}

/// Optional invitation administration extension.
///
/// OpenAPI 1.7 supports creating and accepting invitations, but does not yet
/// publish invitation list or revoke operations. An adapter must implement
/// this interface only after those operations are available in its contract.
abstract interface class HomeInvitationAdministrationPort {
  Future<List<HomeInvitation>> listInvitations(String homeId);

  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  });
}

/// Non-secret local preference. Implementations may use platform preferences
/// or a small local table, but the value never grants authorization.
abstract interface class ActiveHomeStore {
  Future<String?> read();

  Future<void> write(String homeId);

  Future<void> clear();
}
