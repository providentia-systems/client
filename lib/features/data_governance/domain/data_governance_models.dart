import 'dart:collection';

import 'package:providentia/features/homes/domain/home_models.dart';

enum DataGovernanceRequestKind {
  accountExport,
  accountErasure,
  homeExport,
  homeErasure,
}

enum DataGovernanceScope { account, home }

enum DataGovernanceRequestStatus {
  queued,
  processing,
  completed,
  failed,
  cancelled,
}

enum DataGovernanceCapability {
  accountExport,
  accountErasure,
  accountRequestsRead,
  homeExport,
  homeErasure,
  homeRequestsRead,
  cancelAccountRequest,
  cancelHomeRequest,
}

/// Fail-closed presentation capabilities derived from authenticated state and
/// the active home's server-issued effective permission policy.
final class DataGovernanceCapabilities {
  DataGovernanceCapabilities._(Set<DataGovernanceCapability> allowed)
    : _allowed = UnmodifiableSetView<DataGovernanceCapability>(allowed);

  factory DataGovernanceCapabilities.fromEffectivePermissions({
    required bool authenticated,
    required Set<String> effectiveHomePermissions,
  }) {
    if (!authenticated) {
      return DataGovernanceCapabilities._(<DataGovernanceCapability>{});
    }
    final allowed = <DataGovernanceCapability>{
      DataGovernanceCapability.accountExport,
      DataGovernanceCapability.accountErasure,
      DataGovernanceCapability.accountRequestsRead,
      DataGovernanceCapability.cancelAccountRequest,
    };
    if (effectiveHomePermissions.contains(HomePermissions.dataExport)) {
      allowed
        ..add(DataGovernanceCapability.homeExport)
        ..add(DataGovernanceCapability.homeRequestsRead)
        ..add(DataGovernanceCapability.cancelHomeRequest);
    }
    if (effectiveHomePermissions.contains(HomePermissions.dataErasure)) {
      allowed.add(DataGovernanceCapability.homeErasure);
    }
    return DataGovernanceCapabilities._(allowed);
  }

  static final DataGovernanceCapabilities denied = DataGovernanceCapabilities._(
    <DataGovernanceCapability>{},
  );

  final Set<DataGovernanceCapability> _allowed;

  bool allows(DataGovernanceCapability capability) =>
      _allowed.contains(capability);

  Set<DataGovernanceCapability> get allowed => _allowed;
}

/// A deliberate, typed confirmation. Callers cannot reduce erasure consent to
/// a loose boolean or accidentally accept whitespace/case variants.
final class ErasureConfirmation {
  const ErasureConfirmation._();

  static const String requiredPhrase = 'ERASE';

  static ErasureConfirmation? tryCreate(String enteredPhrase) {
    return enteredPhrase == requiredPhrase
        ? const ErasureConfirmation._()
        : null;
  }
}

final class RetainedDataDisclosure {
  const RetainedDataDisclosure({
    required this.category,
    required this.treatment,
    required this.reason,
  });

  final String category;
  final String treatment;
  final String reason;
}

/// A deliberately closed projection of the governance request DTO.
///
/// The backend's diagnostic `failureReason` is validated by the transport
/// adapter but never retained here, so raw server details cannot reach UI state.
final class DataGovernanceRequest {
  DataGovernanceRequest({
    required this.id,
    required this.kind,
    required this.scope,
    required this.status,
    required this.revision,
    required List<RetainedDataDisclosure> retainedDataDisclosure,
    this.homeId,
    this.artifactExpiresAt,
    this.createdAt,
    this.updatedAt,
  }) : retainedDataDisclosure = List<RetainedDataDisclosure>.unmodifiable(
         retainedDataDisclosure,
       ) {
    if ((scope == DataGovernanceScope.home) != (homeId != null)) {
      throw ArgumentError('Home-scoped requests require exactly one home ID.');
    }
    final kindIsHome =
        kind == DataGovernanceRequestKind.homeExport ||
        kind == DataGovernanceRequestKind.homeErasure;
    if (kindIsHome != (scope == DataGovernanceScope.home)) {
      throw ArgumentError('Request kind and scope do not match.');
    }
  }

  final String id;
  final DataGovernanceRequestKind kind;
  final DataGovernanceScope scope;
  final DataGovernanceRequestStatus status;
  final int revision;
  final List<RetainedDataDisclosure> retainedDataDisclosure;
  final String? homeId;
  final DateTime? artifactExpiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get canBeCancelled => status == DataGovernanceRequestStatus.queued;
}
