import 'package:providentia/features/data_governance/domain/data_governance_models.dart';

enum DataGovernanceFailureKind {
  authenticationRequired,
  forbidden,
  conflict,
  invalidRequest,
  invalidResponse,
  unavailable,
}

/// Detail-free failure emitted by infrastructure and safe to classify in UI.
final class DataGovernanceRepositoryException implements Exception {
  const DataGovernanceRepositoryException(this.kind);

  final DataGovernanceFailureKind kind;
}

final class DataGovernanceCapabilityException implements Exception {
  const DataGovernanceCapabilityException();
}

abstract interface class DataGovernanceRepository {
  Future<DataGovernanceRequest> requestAccountExport();

  Future<DataGovernanceRequest> requestAccountErasure();

  Future<DataGovernanceRequest> requestHomeExport({required String homeId});

  Future<DataGovernanceRequest> requestHomeErasure({required String homeId});

  Future<List<DataGovernanceRequest>> listAccountRequests();

  Future<List<DataGovernanceRequest>> listHomeRequests({
    required String homeId,
  });

  Future<void> cancelRequest({
    required String requestId,
    required int expectedRevision,
  });
}

final class DataGovernanceService {
  const DataGovernanceService({
    required DataGovernanceRepository repository,
    required DataGovernanceCapabilities capabilities,
    String? activeHomeId,
  }) : // Public parameter names remain part of the application API.
       // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _capabilities = capabilities,
       // ignore: prefer_initializing_formals
       _activeHomeId = activeHomeId;

  final DataGovernanceRepository _repository;
  final DataGovernanceCapabilities _capabilities;
  final String? _activeHomeId;

  DataGovernanceCapabilities get capabilities => _capabilities;
  String? get activeHomeId => _activeHomeId;

  Future<DataGovernanceRequest> requestAccountExport() async {
    _require(DataGovernanceCapability.accountExport);
    return _repository.requestAccountExport();
  }

  Future<DataGovernanceRequest> requestAccountErasure({
    required ErasureConfirmation confirmation,
  }) async {
    _require(DataGovernanceCapability.accountErasure);
    _acceptConfirmation(confirmation);
    return _repository.requestAccountErasure();
  }

  Future<DataGovernanceRequest> requestHomeExport() async {
    _require(DataGovernanceCapability.homeExport);
    return _repository.requestHomeExport(homeId: _requiredHomeId());
  }

  Future<DataGovernanceRequest> requestHomeErasure({
    required ErasureConfirmation confirmation,
  }) async {
    _require(DataGovernanceCapability.homeErasure);
    _acceptConfirmation(confirmation);
    return _repository.requestHomeErasure(homeId: _requiredHomeId());
  }

  Future<List<DataGovernanceRequest>> listAccountRequests() async {
    _require(DataGovernanceCapability.accountRequestsRead);
    return _repository.listAccountRequests();
  }

  Future<List<DataGovernanceRequest>> listHomeRequests() async {
    _require(DataGovernanceCapability.homeRequestsRead);
    return _repository.listHomeRequests(homeId: _requiredHomeId());
  }

  Future<void> cancel(DataGovernanceRequest request) async {
    if (!request.canBeCancelled) {
      throw const DataGovernanceCapabilityException();
    }
    final capability = request.scope == DataGovernanceScope.account
        ? DataGovernanceCapability.cancelAccountRequest
        : DataGovernanceCapability.cancelHomeRequest;
    _require(capability);
    if (request.scope == DataGovernanceScope.home &&
        request.homeId != _requiredHomeId()) {
      throw const DataGovernanceCapabilityException();
    }
    return _repository.cancelRequest(
      requestId: request.id,
      expectedRevision: request.revision,
    );
  }

  void _require(DataGovernanceCapability capability) {
    if (!_capabilities.allows(capability)) {
      throw const DataGovernanceCapabilityException();
    }
  }

  String _requiredHomeId() {
    final homeId = _activeHomeId;
    if (homeId == null || homeId.trim().isEmpty) {
      throw const DataGovernanceCapabilityException();
    }
    return homeId;
  }

  // Keeping the typed value in the application signature is the confirmation
  // guarantee; only an exact `ERASE` phrase can construct it.
  void _acceptConfirmation(ErasureConfirmation confirmation) {}
}
