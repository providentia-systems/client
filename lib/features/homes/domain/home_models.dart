import 'dart:collection';

enum HomeRole { owner, manager, member, viewer }

enum InvitationStatus { pending, accepted, declined, revoked, expired }

enum OwnershipTransferStatus { pending, accepted, rejected, revoked, expired }

/// Backend-owned permission vocabulary used by the client only to hide or
/// disable command surfaces. The backend remains the authorization authority.
final class HomePermissions {
  const HomePermissions._();

  static const String homeRead = 'home.read';
  static const String homeManage = 'home.manage';
  static const String membersRead = 'members.read';
  static const String membersInvite = 'members.invite';
  static const String membersManage = 'members.manage';
  static const String permissionsManage = 'permissions.manage';
  static const String ownershipTransfer = 'ownership.transfer';
  static const String inventoryRead = 'inventory.read';
  static const String inventoryWrite = 'inventory.write';
  static const String inventoryManage = 'inventory.manage';
  static const String purchasesRead = 'purchases.read';
  static const String purchasesWrite = 'purchases.write';
  static const String shoppingRead = 'shopping.read';
  static const String shoppingWrite = 'shopping.write';
  static const String shoppingManage = 'shopping.manage';
  static const String aiRead = 'ai.read';
  static const String aiUse = 'ai.use';
  static const String aiManage = 'ai.manage';
  static const String reportsRead = 'reports.read';
  static const String catalogContribute = 'catalog.contribute';
  static const String catalogImport = 'catalog.import';
  static const String catalogConsentManage = 'catalog.consent.manage';
  static const String dataExport = 'data.export';
  static const String dataErasure = 'data.erasure';
  static const String billingRead = 'billing.read';
  static const String billingManage = 'billing.manage';

  /// Known home permission names. Actual owner access comes from the backend
  /// and is bounded by the home group.
  static const Set<String> owner = <String>{
    homeRead,
    homeManage,
    membersRead,
    membersInvite,
    membersManage,
    permissionsManage,
    ownershipTransfer,
    inventoryRead,
    inventoryWrite,
    inventoryManage,
    purchasesRead,
    purchasesWrite,
    shoppingRead,
    shoppingWrite,
    shoppingManage,
    aiRead,
    aiUse,
    aiManage,
    reportsRead,
    catalogContribute,
    catalogImport,
    catalogConsentManage,
    dataExport,
    dataErasure,
    billingRead,
    billingManage,
  };
}

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
    Set<String> effectivePermissions = const <String>{},
    Map<String, Object?> access = const <String, Object?>{},
  }) : effectivePermissions = Set<String>.unmodifiable(effectivePermissions),
       access = Map<String, Object?>.unmodifiable(access) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(name, 'name');
    _requireNonEmpty(locale, 'locale');
    _requireNonEmpty(currency, 'currency');
    _requireNonEmpty(timezone, 'timezone');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  final Set<String> effectivePermissions;
  final Map<String, Object?> access;
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

final class RecipientHomeInvitation {
  RecipientHomeInvitation({
    required this.id,
    required this.homeId,
    required this.homeName,
    required this.inviterUserId,
    required this.role,
    required this.expiresAt,
    required this.revision,
    this.inviterDisplayName,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(homeId, 'homeId');
    _requireNonEmpty(homeName, 'homeName');
    _requireNonEmpty(inviterUserId, 'inviterUserId');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
  }

  final String id;
  final String homeId;
  final String homeName;
  final String inviterUserId;
  final String? inviterDisplayName;
  final HomeRole role;
  final DateTime expiresAt;
  final int revision;
}

/// A server-governed proposal to move home ownership to another active
/// member. The backend changes ownership only after the target accepts the
/// pending proposal; the client merely renders participant views of it.
final class HomeOwnershipTransfer {
  HomeOwnershipTransfer({
    required this.id,
    required this.homeId,
    required this.proposedByUserId,
    required this.targetUserId,
    required this.status,
    required this.expiresAt,
    required this.revision,
    this.expectedTargetRevision,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(homeId, 'homeId');
    _requireNonEmpty(proposedByUserId, 'proposedByUserId');
    _requireNonEmpty(targetUserId, 'targetUserId');
    if (revision < 1) {
      throw ArgumentError.value(revision, 'revision', 'must be positive');
    }
    if (expectedTargetRevision case final expected? when expected < 1) {
      throw ArgumentError.value(
        expected,
        'expectedTargetRevision',
        'must be positive',
      );
    }
  }

  final String id;
  final String homeId;
  final String proposedByUserId;
  final String targetUserId;
  final int? expectedTargetRevision;
  final OwnershipTransferStatus status;
  final DateTime expiresAt;
  final int revision;

  bool get isPending => status == OwnershipTransferStatus.pending;

  bool isOfferedTo(String userId) => isPending && targetUserId == userId;
}

/// Receipt for a queued step-up confirmation email. The single-use token is
/// delivered out of band; only an explicitly enabled non-production
/// development profile returns it inline for local flows.
final class HomePermissionPolicy {
  HomePermissionPolicy({
    required this.role,
    required this.revision,
    required Set<String> permissions,
    required this.configurable,
  }) : permissions = UnmodifiableSetView<String>(Set<String>.of(permissions)) {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'must not be negative');
    }
  }

  final HomeRole role;
  final int revision;
  final Set<String> permissions;
  final bool configurable;

  bool allows(String permission) => permissions.contains(permission);
}

final class HomeSessionSnapshot {
  HomeSessionSnapshot({
    required this.status,
    List<HomeSummary> homes = const <HomeSummary>[],
    this.activeHome,
    List<HomeMembership> memberships = const <HomeMembership>[],
    List<HomeInvitation> invitations = const <HomeInvitation>[],
    List<RecipientHomeInvitation> pendingInvitations =
        const <RecipientHomeInvitation>[],
    List<HomePermissionPolicy> permissionPolicies =
        const <HomePermissionPolicy>[],
    List<HomeOwnershipTransfer> ownershipTransfers =
        const <HomeOwnershipTransfer>[],
    this.revokedHomeId,
    this.safeMessage,
  }) : homes = UnmodifiableListView<HomeSummary>(List<HomeSummary>.of(homes)),
       memberships = UnmodifiableListView<HomeMembership>(
         List<HomeMembership>.of(memberships),
       ),
       invitations = UnmodifiableListView<HomeInvitation>(
         List<HomeInvitation>.of(invitations),
       ),
       pendingInvitations = UnmodifiableListView<RecipientHomeInvitation>(
         List<RecipientHomeInvitation>.of(pendingInvitations),
       ),
       permissionPolicies = UnmodifiableListView<HomePermissionPolicy>(
         List<HomePermissionPolicy>.of(permissionPolicies),
       ),
       ownershipTransfers = UnmodifiableListView<HomeOwnershipTransfer>(
         List<HomeOwnershipTransfer>.of(ownershipTransfers),
       );

  final HomeSessionStatus status;
  final List<HomeSummary> homes;
  final HomeSummary? activeHome;
  final List<HomeMembership> memberships;
  final List<HomeInvitation> invitations;
  final List<RecipientHomeInvitation> pendingInvitations;
  final List<HomePermissionPolicy> permissionPolicies;
  final List<HomeOwnershipTransfer> ownershipTransfers;
  final String? revokedHomeId;
  final String? safeMessage;

  bool get hasActiveHome =>
      status == HomeSessionStatus.ready && activeHome != null;

  /// Backend-evaluated permissions for this membership in this home.
  Set<String> get effectivePermissions =>
      activeHome?.effectivePermissions ?? const <String>{};

  bool allows(String permission) => effectivePermissions.contains(permission);

  HomeSessionSnapshot copyWith({
    HomeSessionStatus? status,
    List<HomeSummary>? homes,
    HomeSummary? activeHome,
    bool clearActiveHome = false,
    List<HomeMembership>? memberships,
    List<HomeInvitation>? invitations,
    List<RecipientHomeInvitation>? pendingInvitations,
    List<HomePermissionPolicy>? permissionPolicies,
    List<HomeOwnershipTransfer>? ownershipTransfers,
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
      pendingInvitations: pendingInvitations ?? this.pendingInvitations,
      permissionPolicies: permissionPolicies ?? this.permissionPolicies,
      ownershipTransfers: ownershipTransfers ?? this.ownershipTransfers,
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
