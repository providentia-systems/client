import 'package:flutter/foundation.dart';
import 'package:providentia/features/reporting/application/household_report_service.dart';
import 'package:providentia/features/reporting/domain/household_report.dart';

enum ReportingStatus {
  idle,
  loading,
  ready,
  contractUnavailable,
  forbidden,
  failure,
}

final class ReportingController extends ChangeNotifier {
  factory ReportingController({
    required HouseholdReportService service,
    required String activeHomeId,
  }) => ReportingController._(service, activeHomeId);

  ReportingController._(this._service, this._activeHomeId);

  final HouseholdReportService _service;

  String _activeHomeId;
  ReportingStatus _status = ReportingStatus.idle;
  HouseholdReport? _report;
  int _loadGeneration = 0;
  bool _disposed = false;

  String get activeHomeId => _activeHomeId;
  HouseholdReport? get report => _report;
  ReportingStatus get status => _status;

  Future<void> load() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    final requestedHomeId = _activeHomeId;
    _status = ReportingStatus.loading;
    _report = null;
    _notifyListeners();
    try {
      final loaded = await _service.load(homeId: requestedHomeId);
      if (!_isCurrent(generation, requestedHomeId)) {
        return;
      }
      _report = loaded;
      _status = ReportingStatus.ready;
    } on ReportContractUnavailableException {
      if (_isCurrent(generation, requestedHomeId)) {
        _status = ReportingStatus.contractUnavailable;
      }
    } on ReportForbiddenException {
      if (_isCurrent(generation, requestedHomeId)) {
        _status = ReportingStatus.forbidden;
      }
    } on ReportRepositoryException catch (error) {
      if (_isCurrent(generation, requestedHomeId)) {
        _status = switch (error.kind) {
          ReportRepositoryFailureKind.authenticationRequired ||
          ReportRepositoryFailureKind.forbidden => ReportingStatus.forbidden,
          ReportRepositoryFailureKind.invalidResponse =>
            ReportingStatus.contractUnavailable,
          ReportRepositoryFailureKind.conflict ||
          ReportRepositoryFailureKind.unavailable => ReportingStatus.failure,
        };
      }
    } on Exception {
      if (_isCurrent(generation, requestedHomeId)) {
        _status = ReportingStatus.failure;
      }
    }
    if (_isCurrent(generation, requestedHomeId)) {
      _notifyListeners();
    }
  }

  void switchHome(String homeId) {
    if (_disposed) return;
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
    if (_activeHomeId == homeId) {
      return;
    }
    _activeHomeId = homeId;
    _loadGeneration++;
    _report = null;
    _status = ReportingStatus.idle;
    _notifyListeners();
  }

  void clearSensitiveState() {
    if (_disposed) return;
    _loadGeneration++;
    _report = null;
    _status = ReportingStatus.idle;
    _notifyListeners();
  }

  bool _isCurrent(int generation, String requestedHomeId) =>
      !_disposed &&
      generation == _loadGeneration &&
      requestedHomeId == _activeHomeId;

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _report = null;
    super.dispose();
  }
}
