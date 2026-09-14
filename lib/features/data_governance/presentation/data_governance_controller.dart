import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';

import '../application/data_export_ports.dart';
import '../domain/data_export_artifact.dart';

enum DataGovernanceViewStatus { idle, loading, ready, submitting, failure }

enum DataGovernanceNotice {
  none,
  requestQueued,
  requestCancelled,
  exportReady,
  exportSaved,
  exportHandedToBrowser,
  exportDiscarded,
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
  DataGovernanceController(this._service, {this._exportSaver});

  final DataExportSaver? _exportSaver;
  DataExportArtifact? _artifact;
  Timer? _expiryTimer;
  String? get readyExportRequestId => _artifact?.requestId;
  bool get busy =>
      _status == DataGovernanceViewStatus.loading ||
      _status == DataGovernanceViewStatus.submitting;

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
    if (_disposed || busy) return;
    _discardArtifact();
    _clearTemporaryStorage();
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
    if (_disposed || busy) return;
    _discardArtifact();
    _clearTemporaryStorage();
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

  Future<void> download(DataGovernanceRequest request) async {
    if (_disposed || busy) return;
    final generation = ++_operationGeneration;
    _discardArtifact();
    _status = DataGovernanceViewStatus.submitting;
    _notice = DataGovernanceNotice.none;
    _notifyListeners();
    DataExportArtifact? received;
    try {
      received = await _service.retrieveExport(
        request,
        isCurrent: () => _isCurrent(generation),
      );
      if (!_isCurrent(generation)) return;
      _artifact = received;
      received = null;
      _expiryTimer = Timer(
        _artifact!.expiresAt.difference(DateTime.now().toUtc()),
        () {
          if (!_disposed && _artifact != null) discardExport();
        },
      );
      _status = DataGovernanceViewStatus.ready;
      _notice = DataGovernanceNotice.exportReady;
    } on Object catch (error) {
      if (_isCurrent(generation)) _capture(error);
    } finally {
      received?.dispose();
    }
    if (_isCurrent(generation)) _notifyListeners();
  }

  Future<void> saveExport() async {
    final artifact = _artifact;
    final saver = _exportSaver;
    if (_disposed || busy || artifact == null) return;
    if (!artifact.expiresAt.isAfter(DateTime.now().toUtc())) {
      discardExport();
      return;
    }
    final generation = ++_operationGeneration;
    _status = DataGovernanceViewStatus.submitting;
    _notifyListeners();
    try {
      if (saver == null) {
        throw const DataGovernanceRepositoryException(
          DataGovernanceFailureKind.unavailable,
        );
      }
      final result = await saver.save(artifact);
      if (!_isCurrent(generation)) return;
      _notice = switch (result) {
        DataExportSaveResult.saved => DataGovernanceNotice.exportSaved,
        DataExportSaveResult.handedToBrowser =>
          DataGovernanceNotice.exportHandedToBrowser,
        DataExportSaveResult.cancelled => DataGovernanceNotice.exportDiscarded,
      };
      _status = DataGovernanceViewStatus.ready;
    } on Object catch (error) {
      if (_isCurrent(generation)) _capture(error);
    } finally {
      // Failed/cancelled saves do not leave an unencrypted application copy.
      artifact.dispose();
      if (identical(_artifact, artifact)) _discardArtifact();
    }
    if (_isCurrent(generation)) _notifyListeners();
  }

  void discardExport() {
    if (_disposed) return;
    _operationGeneration++;
    _discardArtifact();
    _clearTemporaryStorage();
    _status = DataGovernanceViewStatus.ready;
    _notice = DataGovernanceNotice.exportDiscarded;
    _notifyListeners();
  }

  void _discardArtifact() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _artifact?.dispose();
    _artifact = null;
  }

  void _clearTemporaryStorage() {
    // Cleanup failure must not log a native error containing a private path.
    unawaited(_exportSaver?.clearTemporaryState().catchError((Object _) {}));
  }

  Future<void> _submit(
    Future<DataGovernanceRequest> Function() command, {
    required List<DataGovernanceRequest> target,
  }) async {
    if (_disposed || busy) return;
    _discardArtifact();
    _clearTemporaryStorage();
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
    _discardArtifact();
    _clearTemporaryStorage();
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
    _discardArtifact();
    _clearTemporaryStorage();
    _accountRequests.clear();
    _homeRequests.clear();
    super.dispose();
  }
}
