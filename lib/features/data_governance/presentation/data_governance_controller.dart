import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';

enum DataGovernanceViewStatus { idle, loading, ready, submitting, failure }

enum DataGovernanceNotice {
  none,
  requestQueued,
  requestCancelled,
  authenticationRequired,
  forbidden,
  conflict,
  invalidRequest,
  invalidResponse,
  unavailable,
}

/// Presentation state retains only a fixed, user-safe failure classification.
/// Raw backend problem details and diagnostic failure reasons never enter it.
final class DataGovernanceController extends ChangeNotifier {
  DataGovernanceController(this._service);

  final DataGovernanceService _service;
  final List<DataGovernanceRequest> _accountRequests =
      <DataGovernanceRequest>[];
  final List<DataGovernanceRequest> _homeRequests = <DataGovernanceRequest>[];

  DataGovernanceViewStatus _status = DataGovernanceViewStatus.idle;
  DataGovernanceNotice _notice = DataGovernanceNotice.none;
  int _operationGeneration = 0;
  bool _disposed = false;

  DataGovernanceCapabilities get capabilities => _service.capabilities;
  String? get activeHomeId => _service.activeHomeId;
  DataGovernanceViewStatus get status => _status;
  DataGovernanceNotice get notice => _notice;
  List<DataGovernanceRequest> get accountRequests =>
      UnmodifiableListView<DataGovernanceRequest>(_accountRequests);
  List<DataGovernanceRequest> get homeRequests =>
      UnmodifiableListView<DataGovernanceRequest>(_homeRequests);

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_operationGeneration;
    _status = DataGovernanceViewStatus.loading;
    _notice = DataGovernanceNotice.none;
    _notifyListeners();
    try {
      final lists = await _loadLists(generation);
      if (!_isCurrent(generation)) return;
      _replaceLists(lists);
      _status = DataGovernanceViewStatus.ready;
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      _capture(error);
    }
    _notifyListeners();
  }

  Future<void> requestAccountExport() =>
      _submit(_service.requestAccountExport, target: _accountRequests);

  Future<void> requestAccountErasure(ErasureConfirmation confirmation) =>
      _submit(
        () => _service.requestAccountErasure(confirmation: confirmation),
        target: _accountRequests,
      );

  Future<void> requestHomeExport() =>
      _submit(_service.requestHomeExport, target: _homeRequests);

  Future<void> requestHomeErasure(ErasureConfirmation confirmation) => _submit(
    () => _service.requestHomeErasure(confirmation: confirmation),
    target: _homeRequests,
  );

  Future<void> cancel(DataGovernanceRequest request) async {
    if (_disposed) return;
    final generation = ++_operationGeneration;
    _status = DataGovernanceViewStatus.submitting;
    _notice = DataGovernanceNotice.none;
    _notifyListeners();
    try {
      await _service.cancel(request);
      if (!_isCurrent(generation)) return;
      final lists = await _loadLists(generation);
      if (!_isCurrent(generation)) return;
      _replaceLists(lists);
      _status = DataGovernanceViewStatus.ready;
      _notice = DataGovernanceNotice.requestCancelled;
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      _capture(error);
    }
    _notifyListeners();
  }

  Future<void> _submit(
    Future<DataGovernanceRequest> Function() command, {
    required List<DataGovernanceRequest> target,
  }) async {
    if (_disposed) return;
    final generation = ++_operationGeneration;
    _status = DataGovernanceViewStatus.submitting;
    _notice = DataGovernanceNotice.none;
    _notifyListeners();
    try {
      final created = await command();
      if (!_isCurrent(generation)) return;
      target
        ..removeWhere((request) => request.id == created.id)
        ..insert(0, created);
      _status = DataGovernanceViewStatus.ready;
      _notice = DataGovernanceNotice.requestQueued;
    } on Object catch (error) {
      if (!_isCurrent(generation)) return;
      _capture(error);
    }
    _notifyListeners();
  }

  void clearSensitiveState() {
    if (_disposed) return;
    _operationGeneration++;
    _accountRequests.clear();
    _homeRequests.clear();
    _status = DataGovernanceViewStatus.idle;
    _notice = DataGovernanceNotice.none;
    _notifyListeners();
  }

  Future<
    ({List<DataGovernanceRequest> account, List<DataGovernanceRequest> home})
  >
  _loadLists(int generation) async {
    final account =
        capabilities.allows(DataGovernanceCapability.accountRequestsRead)
        ? await _service.listAccountRequests()
        : const <DataGovernanceRequest>[];
    if (!_isCurrent(generation)) {
      return (
        account: const <DataGovernanceRequest>[],
        home: const <DataGovernanceRequest>[],
      );
    }
    final home = capabilities.allows(DataGovernanceCapability.homeRequestsRead)
        ? await _service.listHomeRequests()
        : const <DataGovernanceRequest>[];
    return (account: account, home: home);
  }

  void _replaceLists(
    ({List<DataGovernanceRequest> account, List<DataGovernanceRequest> home})
    lists,
  ) {
    _accountRequests
      ..clear()
      ..addAll(lists.account);
    _homeRequests
      ..clear()
      ..addAll(lists.home);
  }

  void _capture(Object error) {
    _status = DataGovernanceViewStatus.failure;
    _notice = switch (error) {
      DataGovernanceCapabilityException() => DataGovernanceNotice.forbidden,
      DataGovernanceRepositoryException(kind: final kind) => switch (kind) {
        DataGovernanceFailureKind.authenticationRequired =>
          DataGovernanceNotice.authenticationRequired,
        DataGovernanceFailureKind.forbidden => DataGovernanceNotice.forbidden,
        DataGovernanceFailureKind.conflict => DataGovernanceNotice.conflict,
        DataGovernanceFailureKind.invalidRequest =>
          DataGovernanceNotice.invalidRequest,
        DataGovernanceFailureKind.invalidResponse =>
          DataGovernanceNotice.invalidResponse,
        DataGovernanceFailureKind.unavailable =>
          DataGovernanceNotice.unavailable,
      },
      _ => DataGovernanceNotice.unavailable,
    };
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _operationGeneration;

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration++;
    _accountRequests.clear();
    _homeRequests.clear();
    super.dispose();
  }
}
