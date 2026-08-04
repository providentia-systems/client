import 'dart:collection';

enum HomeRole { owner, manager, member, viewer }

enum InvitationStatus { pending, accepted, revoked, expired }

enum HomeSessionStatus {
  loading,
  selectionRequired,
  ready,
  accessRevoked,
  failure,
}

final class HomeSummary {
  HomeSummary({
    required this.id,
    required this.name,
    required this.locale,
    required this.currency,
    required this.timezone,
    required this.role,
    required this.revision,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(name, 'name');
    _requireNonEmpty(locale, 'locale');
    _requireNonEmpty(currency, 'currency');
    _requireNonEmpty(timezone, 'timezone');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  final String id;
  final String name;
  final String locale;
  final String currency;
  final String timezone;
  final HomeRole role;
  final int revision;
}

final class CreateHomeCommand {
  CreateHomeCommand({
    required this.name,
    required this.locale,
    required this.currency,
    required this.timezone,
  }) {
    _requireNonEmpty(name, 'name');
    _requireNonEmpty(locale, 'locale');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw ArgumentError.value(
        currency,
        'currency',
        'must be an ISO 4217 code',
      );
    }
    _requireNonEmpty(timezone, 'timezone');
  }

  final String name;
  final String locale;
  final String currency;
  final String timezone;
}

final class HomeMembership {
  HomeMembership({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.revision,
    Set<String> permissions = const <String>{},
    this.email,
    this.revokedAt,
  }) : permissions = UnmodifiableSetView<String>(Set<String>.of(permissions)) {
    _requireNonEmpty(userId, 'userId');
    _requireNonEmpty(displayName, 'displayName');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  final String userId;
  final String displayName;
  final String? email;
  final HomeRole role;
  final int revision;
  final Set<String> permissions;
  final DateTime? revokedAt;

  bool get isActive => revokedAt == null;
}

final class HomeInvitation {
  HomeInvitation({
    required this.id,
    required this.homeId,
    required this.email,
    required this.role,
    required this.status,
    required this.expiresAt,
    required this.revision,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(homeId, 'homeId');
    _requireNonEmpty(email, 'email');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  final String id;
  final String homeId;
  final String email;
  final HomeRole role;
  final InvitationStatus status;
  final DateTime expiresAt;
  final int revision;

  bool get mayBeRevoked => status == InvitationStatus.pending;
}

final class HomeSessionSnapshot {
  HomeSessionSnapshot({
    required this.status,
    List<HomeSummary> homes = const <HomeSummary>[],
    this.activeHome,
    List<HomeMembership> memberships = const <HomeMembership>[],
    List<HomeInvitation> invitations = const <HomeInvitation>[],
    this.revokedHomeId,
    this.safeMessage,
  }) : homes = UnmodifiableListView<HomeSummary>(List<HomeSummary>.of(homes)),
       memberships = UnmodifiableListView<HomeMembership>(
         List<HomeMembership>.of(memberships),
       ),
       invitations = UnmodifiableListView<HomeInvitation>(
         List<HomeInvitation>.of(invitations),
       );

  final HomeSessionStatus status;
  final List<HomeSummary> homes;
  final HomeSummary? activeHome;
  final List<HomeMembership> memberships;
  final List<HomeInvitation> invitations;
  final String? revokedHomeId;
  final String? safeMessage;

  bool get hasActiveHome =>
      status == HomeSessionStatus.ready && activeHome != null;

  HomeSessionSnapshot copyWith({
    HomeSessionStatus? status,
    List<HomeSummary>? homes,
    HomeSummary? activeHome,
    bool clearActiveHome = false,
    List<HomeMembership>? memberships,
    List<HomeInvitation>? invitations,
    String? revokedHomeId,
    bool clearRevokedHome = false,
    String? safeMessage,
    bool clearMessage = false,
  }) {
    return HomeSessionSnapshot(
      status: status ?? this.status,
      homes: homes ?? this.homes,
      activeHome: clearActiveHome ? null : (activeHome ?? this.activeHome),
      memberships: memberships ?? this.memberships,
      invitations: invitations ?? this.invitations,
      revokedHomeId: clearRevokedHome
          ? null
          : (revokedHomeId ?? this.revokedHomeId),
      safeMessage: clearMessage ? null : (safeMessage ?? this.safeMessage),
    );
  }
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
