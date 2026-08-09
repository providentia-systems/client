import 'dart:collection';

enum PlatformAdministratorStatus { pending, active }

final class PlatformAdministrator {
  PlatformAdministrator({
    required this.id,
    required this.email,
    required this.status,
    required this.revision,
    required this.createdAt,
    this.userId,
    this.grantedByUserId,
    this.activatedAt,
  }) {
    if (id.trim().isEmpty || email.trim().isEmpty || revision < 1) {
      throw ArgumentError('Platform-administrator data is incomplete.');
    }
  }

  final String id;
  final String email;
  final String? userId;
  final PlatformAdministratorStatus status;
  final int revision;
  final String? grantedByUserId;
  final DateTime createdAt;
  final DateTime? activatedAt;
}

final class PlatformAdministrationSnapshot {
  PlatformAdministrationSnapshot({
    this.loading = false,
    List<PlatformAdministrator> administrators =
        const <PlatformAdministrator>[],
    this.safeMessage,
  }) : administrators = UnmodifiableListView<PlatformAdministrator>(
         List<PlatformAdministrator>.of(administrators),
       );

  final bool loading;
  final List<PlatformAdministrator> administrators;
  final String? safeMessage;
}
