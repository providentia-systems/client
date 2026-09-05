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

  Future<HomeSummary> getHome(String homeId);

  Future<HomeSummary> createHome(CreateHomeCommand command);

  Future<HomeSummary> switchActiveHome(String homeId);

  Future<HomeSummary> updateHome({
    required String homeId,
    required String name,
    required String locale,
    required String currency,
    required String timezone,
    required int expectedRevision,
  });

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

  Future<List<HomeInvitation>> listInvitations(String homeId);

  Future<void> revokeInvitation({
    required String homeId,
    required String invitationId,
    required int expectedRevision,
  });

  Future<List<RecipientHomeInvitation>> listPendingInvitations();

  Future<void> declinePendingInvitation({
    required String invitationId,
    required int expectedRevision,
  });

  Future<HomeSummary> acceptPendingInvitation({
    required String invitationId,
    required int expectedRevision,
  });

  Future<void> removeHomeMembership({
    required String homeId,
    required String userId,
    required int expectedRevision,
  });

  Future<List<HomeOwnershipTransfer>> listHomeOwnershipTransfers(String homeId);

  Future<HomeOwnershipTransfer> proposeHomeOwnershipTransfer({
    required String homeId,
    required String targetUserId,
    required int expectedTargetRevision,
    required String stepUpToken,
  });

  Future<void> acceptHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  });

  Future<void> rejectHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  });

  Future<void> revokeHomeOwnershipTransfer({
    required String homeId,
    required String transferId,
    required int expectedRevision,
  });

  Future<List<HomePermissionPolicy>> listPermissionPolicies(String homeId);

  Future<HomePermissionPolicy> putPermissionPolicy({
    required String homeId,
    required HomeRole role,
    required Set<String> permissions,
    required int expectedRevision,
  });

  Future<void> leaveHome(String homeId);
}

/// Non-secret local preference. Implementations may use platform preferences
/// or a small local table, but the value never grants authorization.
abstract interface class ActiveHomeStore {
  Future<String?> read();

  Future<void> write(String homeId);

  Future<void> clear();
}
